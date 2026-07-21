import Foundation
import Network

struct OfflineTrack: Codable, Hashable, Identifiable {
    var key: String; var label: String; var url: String; var language: String?; var format: String?
    var id: String { key + "|" + url }
}

enum OfflineDownloadState: String, Codable { case queued, downloading, completed, failed, cancelled }

struct OfflineDownloadItem: Codable, Identifiable, Hashable {
    let id: String; let movieId: Int; let movieSlug: String; let movieTitle: String; let episodeName: String; let serverName: String; let sourceURL: String; let posterURL: String
    var audioSources: [OfflineTrack]; var subtitles: [OfflineTrack]
    var state: OfflineDownloadState; let createdAt: Date; var localManifestPath: String
    var receivedBytes: Int64; var totalBytes: Int64; var progress: Double; var error: String; var taskIdentifier: Int?
    var isActive: Bool { state == .queued || state == .downloading }
    static func stableID(movieId: Int, slug: String, server: String, episode: String) -> String { Data("\(movieId)|\(slug)|\(server)|\(episode)".utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}

private struct OfflineResource: Codable, Hashable {
    enum State: String, Codable { case pending, running, complete }
    var id: String; var remote: String; var relativePath: String; var reference: String; var manifest: String?; var optional: Bool; var state: State; var bytes: Int64
}
private struct OfflineCheckpoint: Codable {
    var resources: [OfflineResource]; var manifests: [String: String]; var localAudio: [OfflineTrack]; var localSubtitles: [OfflineTrack]
}
private struct TaskIdentity: Codable { let item: String; let resource: String }
private struct HLSResource { let reference: String; let url: URL; let kind: String }

private final class OfflineSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionDelegate, @unchecked Sendable {
    weak var owner: OfflineDownloadManager?
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let description = downloadTask.taskDescription
        do {
            // The temporary URL is valid only during this callback. Resolve the
            // checkpoint destination and move it directly into the package,
            // avoiding a second staging file that can fail while the device is locked.
            guard let destination = Self.destination(for: description) else { throw OfflineError.missingCheckpoint }
            let parent = destination.deletingLastPathComponent()
            guard FileManager.default.fileExists(atPath: parent.path) else { throw OfflineError.missingCheckpoint }
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor [weak owner] in owner?.downloadFinished(description: description, permanentURL: destination, response: downloadTask.response) }
        } catch {
            Task { @MainActor [weak owner] in owner?.downloadFailed(description: description, error: error) }
        }
    }
    private static func destination(for description: String?) -> URL? {
        guard let description, let identityData = Data(base64Encoded: description),
              let identity = try? JSONDecoder().decode(TaskIdentity.self, from: identityData) else { return nil }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineDownloads", isDirectory: true)
        let itemRoot = root.appendingPathComponent(identity.item, isDirectory: true).standardizedFileURL
        let checkpointURL = itemRoot.appendingPathComponent("checkpoint.json")
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? JSONDecoder().decode(OfflineCheckpoint.self, from: data),
              let resource = checkpoint.resources.first(where: { $0.id == identity.resource }) else { return nil }
        let destination = itemRoot.appendingPathComponent(resource.relativePath).standardizedFileURL
        guard destination.path.hasPrefix(itemRoot.path + "/") else { return nil }
        return destination
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }; let description = task.taskDescription
        Task { @MainActor [weak owner] in owner?.downloadFailed(description: description, error: error) }
    }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak owner] in owner?.finishBackgroundEvents() }
    }
}

@MainActor
final class OfflineDownloadManager: NSObject, ObservableObject {
    static let shared = OfflineDownloadManager(); static let backgroundIdentifier = "live.cineviet.ios.offline-hls"
    @Published private(set) var items: [OfflineDownloadItem] = []; @Published private(set) var loadError: String?
    private var loaded = false; private var tombstones = Set<String>(); private var paused = Set<String>(); private var completionHandler: (() -> Void)?
    private let delegate = OfflineSessionDelegate(); private lazy var session: URLSession = {
        let c = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier); c.sessionSendsLaunchEvents = true; c.isDiscretionary = false; c.waitsForConnectivity = true; c.httpMaximumConnectionsPerHost = 1
        return URLSession(configuration: c, delegate: delegate, delegateQueue: nil)
    }()
    private var rootURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineDownloads", isDirectory: true) }
    private var indexURL: URL { rootURL.appendingPathComponent("downloads.json") }
    override private init() { super.init(); delegate.owner = self; _ = session }

    func handleBackgroundEvents(completionHandler: @escaping () -> Void) { self.completionHandler = completionHandler; _ = session }
    fileprivate func finishBackgroundEvents() { let handler = completionHandler; completionHandler = nil; handler?() }

    func load(force: Bool = false) async {
        guard force || !loaded else { return }; loaded = true
        do { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true); if FileManager.default.fileExists(atPath: indexURL.path) { items = try JSONDecoder.offline.decode([OfflineDownloadItem].self, from: Data(contentsOf: indexURL)) }; try persistNow() } catch { loadError = "Không đọc hoặc lưu được thư viện tải xuống." }
        let tasks = await allTasks(); let active = Set(tasks.compactMap { identity($0.taskDescription)?.item })
        for i in items.indices where items[i].isActive && !active.contains(items[i].id) { items[i].state = .queued }
        persist(); for item in items where item.isActive { reconcile(item.id, existing: tasks) }
    }

    func enqueue(movie: Movie, server: EpisodeServer, episode: EpisodeItem, selectedAudioKeys: Set<String>? = nil, selectedSubtitleKeys: Set<String>? = nil) async throws {
        guard let source = Self.eligibleURL(episode), source.absoluteString.lowercased().contains("m3u8") else { throw OfflineError.unsupported }; await ensureLoaded()
        let id = OfflineDownloadItem.stableID(movieId: movie.id, slug: movie.slug, server: server.name, episode: episode.name); if let old = items.first(where: {$0.id == id}), old.state == .completed, fileExists(old) { return }
        tombstones.remove(id); paused.remove(id)
        let audio = episode.audioSources.compactMap { selectedAudioKeys?.contains($0.key) != false && Self.remoteURL($0.url) != nil ? OfflineTrack(key:$0.key,label:$0.label,url:$0.url,language:nil,format:nil) : nil }
        let subtitles = episode.subtitles.compactMap { selectedSubtitleKeys?.contains($0.lang) != false && Self.remoteURL($0.url) != nil ? OfflineTrack(key:$0.lang,label:$0.label,url:$0.url,language:$0.lang,format:$0.format) : nil }
        let item = OfflineDownloadItem(id:id,movieId:movie.id,movieSlug:movie.slug,movieTitle:movie.title,episodeName:episode.name,serverName:server.name,sourceURL:source.absoluteString,posterURL:movie.posterURL?.absoluteString ?? "",audioSources:audio,subtitles:subtitles,state:.queued,createdAt:Date(),localManifestPath:"",receivedBytes:0,totalBytes:0,progress:0,error:"",taskIdentifier:nil)
        if let i=items.firstIndex(where:{$0.id==id}) { items[i]=item } else { items.insert(item,at:0) }; try persistNow()
        do { try await prepare(id); reconcile(id, existing: await allTasks()) } catch { update(id){$0.state = .failed; $0.error=(error as? LocalizedError)?.errorDescription ?? error.localizedDescription} }
    }

    func retry(_ id: String) async {
        await ensureLoaded(); tombstones.remove(id); paused.remove(id); update(id){$0.state = .queued;$0.error=""}
        if loadCheckpoint(id) == nil {
            do { try await prepare(id) } catch { update(id){$0.state = .failed; $0.error=(error as? LocalizedError)?.errorDescription ?? error.localizedDescription}; return }
        }
        reconcile(id, existing: await allTasks())
    }
    func cancel(_ id: String) async { await ensureLoaded(); paused.insert(id); for t in await allTasks() where identity(t.taskDescription)?.item == id { t.cancel() }; update(id){$0.state = .cancelled;$0.error="Đã hủy";$0.taskIdentifier=nil} }
    func delete(_ id: String) async { await ensureLoaded(); tombstones.insert(id); paused.remove(id); for t in await allTasks() where identity(t.taskDescription)?.item == id { t.cancel() }; try? FileManager.default.removeItem(at:itemDirectory(id)); items.removeAll{$0.id==id}; persist() }
    func deleteMovie(_ ids:[String]) async { for id in ids { await delete(id) } }

    func playbackURL(for item: OfflineDownloadItem)->URL? { let u=resolvedURL(item); guard FileManager.default.fileExists(atPath:u.path) else{return nil}; return OfflineLoopbackServer.shared.register(directory:u.deletingLastPathComponent(),id:item.id) }
    static func serverEligible(_ server: EpisodeServer)->Bool { let n=server.name.folding(options:[.diacriticInsensitive,.caseInsensitive],locale:.current).replacingOccurrences(of:" ",with:"").lowercased(); return n != "nguonc" && !server.items.contains{($0.linkEmbed+$0.linkM3u8).lowercased().contains("streamc.xyz")} && server.items.contains{eligibleURL($0) != nil} }
    static func eligibleURL(_ episode:EpisodeItem)->URL? { guard !episode.linkM3u8.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, let u=PlayerViewModel.directMediaURL(for:episode), !u.absoluteString.lowercased().contains("/embed") else{return nil}; return u }

    private func prepare(_ id:String) async throws {
        guard let item=items.first(where:{$0.id==id}), let source=URL(string:item.sourceURL) else{throw OfflineError.unsupported}; try FileManager.default.createDirectory(at:itemDirectory(id),withIntermediateDirectories:true)
        var cp = loadCheckpoint(id) ?? OfflineCheckpoint(resources:[],manifests:[:],localAudio:[],localSubtitles:[])
        if cp.resources.isEmpty {
            try await appendHLS(source, folder:"", prefix:"main", optional:false, checkpoint:&cp)
            for (i,t) in item.audioSources.enumerated() { guard let u=Self.remoteURL(t.url) else{continue}; do { try await appendHLS(u,folder:"audio_\(i)",prefix:"audio",optional:true,checkpoint:&cp); cp.localAudio.append(OfflineTrack(key:t.key,label:t.label,url:"audio_\(i)/index.m3u8",language:t.language,format:t.format)) } catch {} }
            for (i,t) in item.subtitles.enumerated() { guard let u=Self.remoteURL(t.url) else{continue}; let ext=(t.format?.isEmpty==false ? t.format! : (u.pathExtension.isEmpty ? "vtt":u.pathExtension)); cp.resources.append(OfflineResource(id:"subtitle-\(i)",remote:u.absoluteString,relativePath:"subtitle_\(i).\(ext)",reference:u.absoluteString,manifest:nil,optional:true,state:.pending,bytes:0)); cp.localSubtitles.append(OfflineTrack(key:t.key,label:t.label,url:"subtitle_\(i).\(ext)",language:t.language,format:ext)) }
            // Create every destination directory while the app is active. The
            // background daemon can then deliver files without needing to create
            // protected directories while the device is locked.
            for resource in cp.resources {
                let parent = itemDirectory(id).appendingPathComponent(resource.relativePath).deletingLastPathComponent()
                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true,
                    attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
                )
            }
            try saveCheckpoint(cp,id:id)
        }
    }
    private func appendHLS(_ source:URL, folder:String, prefix:String, optional:Bool, checkpoint cp:inout OfflineCheckpoint) async throws {
        var base=source; var text=try await fetchText(base); guard text.trimmingCharacters(in:.whitespacesAndNewlines).hasPrefix("#EXTM3U") else{throw OfflineError.notHLS}
        if text.contains("#EXT-X-STREAM-INF") { guard let v=bestVariant(in:text,relativeTo:base) else{throw OfflineError.noVariant}; base=v;text=try await fetchText(v) }
        guard !text.contains("METHOD=SAMPLE-AES"), !text.contains("KEYFORMAT=") else{throw OfflineError.drm}; let rs=manifestResources(in:text,relativeTo:base); guard !rs.isEmpty else{throw OfflineError.empty}
        let manifestKey=folder.isEmpty ? "index.m3u8":"\(folder)/index.m3u8"; cp.manifests[manifestKey]=text
        for (i,r) in rs.enumerated() { let path=(folder.isEmpty ? "":"\(folder)/")+"\(prefix)_\(r.kind)_\(String(format:"%05d",i)).\(fileExtension(r))"; cp.resources.append(OfflineResource(id:"\(prefix)-\(folder)-\(i)",remote:r.url.absoluteString,relativePath:path,reference:r.reference,manifest:manifestKey,optional:optional,state:.pending,bytes:0)) }
    }
    private func reconcile(_ id:String, existing:[URLSessionTask]) {
        guard !tombstones.contains(id), var cp=loadCheckpoint(id) else{return}; let running=Set(existing.compactMap{identity($0.taskDescription)}.filter{$0.item==id}.map{$0.resource})
        for i in cp.resources.indices { let file=itemDirectory(id).appendingPathComponent(cp.resources[i].relativePath); if FileManager.default.fileExists(atPath:file.path){cp.resources[i].state = .complete} else if !running.contains(cp.resources[i].id){cp.resources[i].state = .pending} }
        try? saveCheckpoint(cp,id:id); schedule(id,checkpoint:cp)
    }
    private func schedule(_ id:String, checkpoint cp:OfflineCheckpoint) {
        guard !tombstones.contains(id) else{return}; var cp=cp; let active=cp.resources.filter{$0.state == .running}.count
        // Keep exactly one daemon-owned download file open per package. Creating
        // several segment tasks at once can make nsurlsessiond fail with -3000
        // before our destination callback is reached on physical devices.
        if active == 0, let i=cp.resources.firstIndex(where:{$0.state == .pending}), let u=URL(string:cp.resources[i].remote) {
            let task=session.downloadTask(with:request(u)); task.taskDescription=encodeIdentity(TaskIdentity(item:id,resource:cp.resources[i].id)); cp.resources[i].state = .running; task.resume()
            try? saveCheckpoint(cp,id:id); update(id){$0.state = .downloading;$0.taskIdentifier=task.taskIdentifier}; return
        }
        try? saveCheckpoint(cp,id:id); if active == 0 { finalizeIfReady(id,checkpoint:cp) }
    }
    fileprivate func downloadFinished(description:String?, permanentURL:URL, response:URLResponse?) {
        guard let key=identity(description), !tombstones.contains(key.item), var cp=loadCheckpoint(key.item), let i=cp.resources.firstIndex(where:{$0.id==key.resource}) else { try? FileManager.default.removeItem(at: permanentURL); return }
        guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else { try? FileManager.default.removeItem(at: permanentURL); cp.resources[i].state = .pending; try? saveCheckpoint(cp,id:key.item); if !paused.contains(key.item) { schedule(key.item,checkpoint:cp) }; return }
        cp.resources[i].state = .complete; cp.resources[i].bytes=(try? FileManager.default.attributesOfItem(atPath:permanentURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        do { try saveCheckpoint(cp,id:key.item); updateProgress(key.item,cp); if !paused.contains(key.item) { schedule(key.item,checkpoint:cp) } } catch { downloadFailed(description:description,error:error) }
    }
    fileprivate func downloadFailed(description:String?, error:Error) {
        guard let key=identity(description), !tombstones.contains(key.item), var cp=loadCheckpoint(key.item), let i=cp.resources.firstIndex(where:{$0.id==key.resource}) else{return}
        cp.resources[i].state = .pending; try? saveCheckpoint(cp,id:key.item)
        guard !paused.contains(key.item) else { return }
        if cp.resources[i].optional {
            // Optional tracks must not enter an immediate retry loop. They stay
            // pending and are retried explicitly with the package.
            update(key.item){$0.state = .failed;$0.error=Self.downloadErrorMessage(error)}
        } else {
            update(key.item){$0.state = .failed;$0.error=Self.downloadErrorMessage(error)}
        }
    }
    private func finalizeIfReady(_ id:String,checkpoint cp:OfflineCheckpoint) {
        let required=cp.resources.filter{!$0.optional}; guard required.allSatisfy({$0.state == .complete}) else{return}; var written=false
        for (path,var manifest) in cp.manifests { let related=cp.resources.filter{$0.manifest==path && $0.state == .complete}; if related.contains(where:{!$0.optional}) || related.count == cp.resources.filter({$0.manifest==path}).count { for r in related { manifest=rewrite(manifest,remote:r.reference,local:URL(fileURLWithPath:r.relativePath).lastPathComponent) }; let out=itemDirectory(id).appendingPathComponent(path); try? FileManager.default.createDirectory(at:out.deletingLastPathComponent(),withIntermediateDirectories:true); if (try? manifest.data(using:.utf8)?.write(to:out,options:.atomic)) != nil { if path=="index.m3u8"{written=true} } } }
        guard written else{return}; let bytes=cp.resources.reduce(0){$0+$1.bytes}; update(id){$0.state = .completed;$0.localManifestPath="\(id)/index.m3u8";$0.audioSources=cp.localAudio.filter{FileManager.default.fileExists(atPath:self.itemDirectory(id).appendingPathComponent($0.url).path)};$0.subtitles=cp.localSubtitles.filter{FileManager.default.fileExists(atPath:self.itemDirectory(id).appendingPathComponent($0.url).path)};$0.progress=1;$0.receivedBytes=bytes;$0.totalBytes=bytes;$0.error=""}
    }
    private func updateProgress(_ id:String,_ cp:OfflineCheckpoint){let done=cp.resources.filter{$0.state == .complete}.count;let bytes=cp.resources.reduce(0){$0+$1.bytes};update(id){$0.receivedBytes=bytes;$0.totalBytes=Int64(cp.resources.count);$0.progress=min(Double(done)/Double(max(cp.resources.count,1)),0.99)}}

    private func allTasks() async->[URLSessionTask]{await withCheckedContinuation{c in session.getAllTasks{c.resume(returning:$0)}}}
    private func checkpointURL(_ id:String)->URL{itemDirectory(id).appendingPathComponent("checkpoint.json")}; private func loadCheckpoint(_ id:String)->OfflineCheckpoint?{try? JSONDecoder.offline.decode(OfflineCheckpoint.self,from:Data(contentsOf:checkpointURL(id)))}
    private func saveCheckpoint(_ cp:OfflineCheckpoint,id:String)throws{let u=checkpointURL(id);try FileManager.default.createDirectory(at:u.deletingLastPathComponent(),withIntermediateDirectories:true);try JSONEncoder.offline.encode(cp).write(to:u,options:.atomic)}
    private func encodeIdentity(_ x:TaskIdentity)->String?{guard let d=try? JSONEncoder().encode(x) else{return nil};return d.base64EncodedString()}; private func identity(_ s:String?)->TaskIdentity?{guard let s,let d=Data(base64Encoded:s) else{return nil};return try? JSONDecoder().decode(TaskIdentity.self,from:d)}
    private func request(_ u:URL)->URLRequest{var r=URLRequest(url:u);r.timeoutInterval=120;r.setValue(AppEnvironment.siteBaseURL.absoluteString,forHTTPHeaderField:"Origin");r.setValue(AppEnvironment.siteBaseURL.appendingPathComponent("").absoluteString,forHTTPHeaderField:"Referer");r.setValue(AppEnvironment.userAgent,forHTTPHeaderField:"User-Agent");return r}
    private func fetchText(_ u:URL)async throws->String{let(d,r)=try await URLSession.shared.data(for:request(u));guard let h=r as? HTTPURLResponse,(200...299).contains(h.statusCode),let s=String(data:d,encoding:.utf8) else{throw OfflineError.sourceUnavailable};return s}
    private func bestVariant(in m:String,relativeTo b:URL)->URL?{let l=m.components(separatedBy:.newlines);var v:[(Int,URL)]=[];for i in l.indices where l[i].contains("#EXT-X-STREAM-INF:"){let bw=Int(l[i].firstMatch(#"BANDWIDTH=(\d+)"#) ?? "0") ?? 0;var j=i+1;while j<l.count{let x=l[j].trimmingCharacters(in:.whitespacesAndNewlines);if !x.isEmpty{if !x.hasPrefix("#"),let u=URL(string:x,relativeTo:b)?.absoluteURL{v.append((bw,u))};break};j+=1}};return v.max{$0.0<$1.0}?.1}
    private func manifestResources(in m:String,relativeTo b:URL)->[HLSResource]{var a:[HLSResource]=[];var seen=Set<String>();for raw in m.components(separatedBy:.newlines){let l=raw.trimmingCharacters(in:.whitespacesAndNewlines);if !l.hasPrefix("#"),!l.isEmpty,seen.insert(l).inserted,let u=URL(string:l,relativeTo:b)?.absoluteURL{a.append(HLSResource(reference:l,url:u,kind:"segment"))}else if (l.hasPrefix("#EXT-X-KEY:") || l.hasPrefix("#EXT-X-MAP:")),let x=l.firstMatch(#"URI="([^"]+)""#),seen.insert(x).inserted,let u=URL(string:x,relativeTo:b)?.absoluteURL{a.append(HLSResource(reference:x,url:u,kind:l.hasPrefix("#EXT-X-KEY:") ? "key":"map"))}};return a}
    private func rewrite(_ m:String,remote:String,local:String)->String{m.components(separatedBy:.newlines).map{let x=$0.trimmingCharacters(in:.whitespacesAndNewlines);if x==remote{return local};return $0.replacingOccurrences(of:"URI=\"\(remote)\"",with:"URI=\"\(local)\"")}.joined(separator:"\n")}
    private func fileExtension(_ r:HLSResource)->String{if r.kind=="key"{return "key"};let x=r.url.pathExtension.lowercased();return !x.isEmpty && x.count<7 ? x:(r.kind=="map" ? "mp4":"ts")}
    private static func remoteURL(_ s:String)->URL?{guard let u=URL(string:s.trimmingCharacters(in:.whitespacesAndNewlines)),["http","https"].contains(u.scheme?.lowercased() ?? "") else{return nil};return u}
    private static func downloadErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
        let diagnostic = underlying.map { "\(nsError.domain) \(nsError.code) / \($0.domain) \($0.code)" } ?? "\(nsError.domain) \(nsError.code)"
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCannotCreateFile {
            return "Không thể tạo tệp tải xuống (\(diagnostic)). Hãy nhấn thử lại."
        }
        return "\(error.localizedDescription) (\(diagnostic))"
    }
    private func ensureLoaded()async{if !loaded{await load()}}; private func itemDirectory(_ id:String)->URL{rootURL.appendingPathComponent(id,isDirectory:true)}
    private func resolvedURL(_ i:OfflineDownloadItem)->URL{let u=rootURL.appendingPathComponent(i.localManifestPath).standardizedFileURL;return u.path==itemDirectory(i.id).appendingPathComponent("index.m3u8").standardizedFileURL.path ? u:rootURL.appendingPathComponent(".invalid")}; private func fileExists(_ i:OfflineDownloadItem)->Bool{!i.localManifestPath.isEmpty && FileManager.default.fileExists(atPath:resolvedURL(i).path)}
    private func update(_ id:String,_ body:(inout OfflineDownloadItem)->Void){guard !tombstones.contains(id),let i=items.firstIndex(where:{$0.id==id}) else{return};body(&items[i]);persist()}; private func persist(){do{try persistNow();loadError=nil}catch{loadError="Không thể lưu thay đổi thư viện tải xuống."}}; private func persistNow()throws{try FileManager.default.createDirectory(at:rootURL,withIntermediateDirectories:true);try JSONEncoder.offline.encode(items).write(to:indexURL,options:.atomic)}
}

private final class OfflineLoopbackServer: @unchecked Sendable {
    static let shared = OfflineLoopbackServer()
    private let queue = DispatchQueue(label: "live.cineviet.offline.loopback")
    private var listener: NWListener?
    private let port: UInt16 = 49_159
    private var roots: [String: URL] = [:]

    func register(directory: URL, id: String) -> URL? { queue.sync {
        roots[id] = directory.standardizedFileURL
        if listener == nil { start() }
        guard listener != nil else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/\(id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id)/index.m3u8")
    } }

    private func start() {
        guard let endpointPort = NWEndpoint.Port(rawValue: port), let listener = try? NWListener(using: .tcp, on: endpointPort) else { return }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.queue.async { self?.listener?.cancel(); self?.listener = nil } }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        self.listener = listener; listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, error in
            guard let self, error == nil, let data, let request = String(data: data, encoding: .utf8), let first = request.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = first.split(separator: " "); guard parts.count >= 2, parts[0] == "GET" else { self.respond(connection, status: "405 Method Not Allowed", type: "text/plain", data: Data()); return }
            self.serve(String(parts[1]), on: connection)
        }
    }

    private func serve(_ rawPath: String, on connection: NWConnection) {
        let path = rawPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? rawPath
        let components = path.split(separator: "/").map(String.init)
        guard components.count >= 2, let id = components.first?.removingPercentEncoding, let root = roots[id] else { respond(connection, status: "404 Not Found", type: "text/plain", data: Data()); return }
        let relative = components.dropFirst().joined(separator: "/").removingPercentEncoding ?? ""
        let file = root.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else { respond(connection, status: "404 Not Found", type: "text/plain", data: Data()); return }
        respond(connection, status: "200 OK", type: mime(file.pathExtension), data: data)
    }

    private func respond(_ connection: NWConnection, status: String, type: String, data: Data) { var response = Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8); response.append(data); connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() }) }
    private func mime(_ ext: String) -> String { switch ext.lowercased() { case "m3u8": "application/vnd.apple.mpegurl"; case "ts": "video/mp2t"; case "m4s": "video/iso.segment"; case "mp4": "video/mp4"; case "vtt": "text/vtt"; case "srt": "application/x-subrip"; default: "application/octet-stream" } }
}
private extension String { func firstMatch(_ pattern: String) -> String? { guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: self, range: NSRange(startIndex..., in: self)), match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: self) else { return nil }; return String(self[range]) } }
enum OfflineError: LocalizedError { case unsupported, sourceUnavailable, notHLS, noVariant, drm, empty, missingCheckpoint; var errorDescription: String? { switch self { case .unsupported: "Nguồn này không hỗ trợ tải offline"; case .sourceUnavailable: "Nguồn phim không còn khả dụng. Vui lòng chọn server khác."; case .notHLS: "Nguồn trả về không phải HLS"; case .noVariant: "Không tìm thấy luồng HLS phù hợp"; case .drm: "Nguồn DRM không hỗ trợ tải offline"; case .empty: "Danh sách HLS không có phân đoạn video"; case .missingCheckpoint: "Không tìm thấy checkpoint của tệp tải xuống" } } }
private extension JSONEncoder { static var offline: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder } }
private extension JSONDecoder { static var offline: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
