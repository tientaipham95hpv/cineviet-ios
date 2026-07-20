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
    static func stableID(movieId: Int, slug: String, server: String, episode: String) -> String {
        Data("\(movieId)|\(slug)|\(server)|\(episode)".utf8).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

@MainActor
final class OfflineDownloadManager: NSObject, ObservableObject {
    static let shared = OfflineDownloadManager()
    static let backgroundIdentifier = "live.cineviet.ios.offline-hls"
    @Published private(set) var items: [OfflineDownloadItem] = []
    @Published private(set) var loadError: String?
    private var loaded = false
    private var jobs: [String: Task<Void, Never>] = [:]
    private var tombstones = Set<String>()
    private var persistRetry: Task<Void, Never>?
    private var indexURL: URL { rootURL.appendingPathComponent("downloads.json") }
    private var rootURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineDownloads", isDirectory: true) }

    func handleBackgroundEvents(completionHandler: @escaping () -> Void) { DispatchQueue.main.async { completionHandler() } }

    func load(force: Bool = false) async {
        guard force || !loaded else { return }; loaded = true; loadError = nil
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                var decoded = try JSONDecoder.offline.decode([OfflineDownloadItem].self, from: Data(contentsOf: indexURL)).filter { !$0.id.isEmpty }
                var seen = Set<String>(); decoded = decoded.filter { seen.insert($0.id).inserted }
                for index in decoded.indices {
                    decoded[index].localManifestPath = migratePath(decoded[index].localManifestPath, id: decoded[index].id)
                    if decoded[index].isActive { decoded[index].state = .cancelled; decoded[index].error = "Tác vụ bị gián đoạn. Nhấn thử lại để tiếp tục."; decoded[index].taskIdentifier = nil }
                    if decoded[index].state == .completed, !fileExists(decoded[index]) { decoded[index].state = .failed; decoded[index].error = "Bản tải xuống không còn trên thiết bị" }
                }
                items = decoded
            }
            try persistNow()
        } catch { loadError = "Không đọc hoặc lưu được thư viện tải xuống." }
    }

    func enqueue(movie: Movie, server: EpisodeServer, episode: EpisodeItem, selectedAudioKeys: Set<String>? = nil, selectedSubtitleKeys: Set<String>? = nil) async throws {
        guard let source = Self.eligibleURL(episode), source.pathExtension.lowercased() == "m3u8" || source.absoluteString.lowercased().contains("m3u8") else { throw OfflineError.unsupported }
        await ensureLoaded()
        let id = OfflineDownloadItem.stableID(movieId: movie.id, slug: movie.slug, server: server.name, episode: episode.name)
        if jobs[id] != nil { return }
        if let old = items.first(where: { $0.id == id }), old.state == .completed, fileExists(old) { return }
        tombstones.remove(id)
        let audio = episode.audioSources.compactMap { source -> OfflineTrack? in
            guard selectedAudioKeys?.contains(source.key) != false, Self.remoteURL(source.url) != nil else { return nil }
            return OfflineTrack(key: source.key, label: source.label, url: source.url, language: nil, format: nil)
        }
        let subtitles = episode.subtitles.compactMap { subtitle -> OfflineTrack? in
            guard selectedSubtitleKeys?.contains(subtitle.lang) != false, Self.remoteURL(subtitle.url) != nil else { return nil }
            return OfflineTrack(key: subtitle.lang, label: subtitle.label, url: subtitle.url, language: subtitle.lang, format: subtitle.format)
        }
        let item = OfflineDownloadItem(id: id, movieId: movie.id, movieSlug: movie.slug, movieTitle: movie.title, episodeName: episode.name, serverName: server.name, sourceURL: source.absoluteString, posterURL: movie.posterURL?.absoluteString ?? "", audioSources: audio, subtitles: subtitles, state: .queued, createdAt: items.first(where: { $0.id == id })?.createdAt ?? Date(), localManifestPath: "", receivedBytes: 0, totalBytes: 0, progress: 0, error: "", taskIdentifier: nil)
        try replaceAndPersist(item)
        start(id)
    }

    func retry(_ id: String) async {
        await ensureLoaded(); guard jobs[id] == nil, items.contains(where: { $0.id == id }) else { return }
        tombstones.remove(id); try? FileManager.default.removeItem(at: itemDirectory(id))
        update(id) { $0.localManifestPath = ""; $0.error = ""; $0.progress = 0; $0.receivedBytes = 0; $0.totalBytes = 0 }
        start(id)
    }

    func cancel(_ id: String) async { await ensureLoaded(); jobs[id]?.cancel(); jobs[id] = nil; update(id) { $0.state = .cancelled; $0.error = "Đã hủy"; $0.taskIdentifier = nil } }
    func delete(_ id: String) async { await ensureLoaded(); tombstones.insert(id); jobs[id]?.cancel(); jobs[id] = nil; try? FileManager.default.removeItem(at: itemDirectory(id)); items.removeAll { $0.id == id }; persist() }
    func deleteMovie(_ ids: [String]) async { await ensureLoaded(); let deleting = Set(ids); tombstones.formUnion(deleting); for id in deleting { jobs[id]?.cancel(); jobs[id] = nil; try? FileManager.default.removeItem(at: itemDirectory(id)) }; items.removeAll { deleting.contains($0.id) }; persist() }

    func playbackURL(for item: OfflineDownloadItem) -> URL? {
        let manifest = resolvedURL(item)
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return OfflineLoopbackServer.shared.register(directory: manifest.deletingLastPathComponent(), id: item.id)
    }
    static func serverEligible(_ server: EpisodeServer) -> Bool { let normalized = server.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).replacingOccurrences(of: " ", with: "").lowercased(); guard normalized != "nguonc", !server.items.contains(where: { ($0.linkEmbed + $0.linkM3u8).lowercased().contains("streamc.xyz") }) else { return false }; return server.items.contains { eligibleURL($0) != nil } }
    static func eligibleURL(_ episode: EpisodeItem) -> URL? { guard !episode.linkM3u8.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = PlayerViewModel.directMediaURL(for: episode), !url.absoluteString.lowercased().contains("/embed") else { return nil }; return url }

    private func start(_ id: String) {
        update(id) { $0.state = .downloading; $0.error = ""; $0.progress = 0 }
        jobs[id] = Task { [weak self] in
            guard let self else { return }
            do { try await self.download(id) }
            catch is CancellationError { self.update(id) { $0.state = .cancelled; $0.error = "Đã hủy" } }
            catch { self.update(id) { $0.state = .failed; $0.error = (error as? LocalizedError)?.errorDescription ?? "Lỗi mạng khi tải video" } }
            self.jobs[id] = nil
        }
    }

    private func download(_ id: String) async throws {
        guard let item = items.first(where: { $0.id == id }), let source = URL(string: item.sourceURL) else { throw OfflineError.unsupported }
        let directory = itemDirectory(id); try? FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifestURL = source
        var manifest = try await text(from: manifestURL)
        guard manifest.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") else { throw OfflineError.notHLS }
        if manifest.contains("#EXT-X-STREAM-INF") {
            guard let variant = bestVariant(in: manifest, relativeTo: manifestURL) else { throw OfflineError.noVariant }
            manifestURL = variant; manifest = try await text(from: manifestURL)
        }
        guard !manifest.contains("METHOD=SAMPLE-AES"), !manifest.contains("KEYFORMAT=") else { throw OfflineError.drm }
        let resources = manifestResources(in: manifest, relativeTo: manifestURL)
        guard !resources.isEmpty else { throw OfflineError.empty }
        update(id) { $0.totalBytes = Int64(resources.count); $0.receivedBytes = 0 }
        var rewritten = manifest; var bytes: Int64 = 0
        for (index, resource) in resources.enumerated() {
            try Task.checkCancellation(); guard !tombstones.contains(id) else { throw CancellationError() }
            let name = "\(resource.kind)_\(String(format: "%05d", index)).\(fileExtension(for: resource))"
            let data = try await data(from: resource.url)
            try data.write(to: directory.appendingPathComponent(name), options: [.atomic]); bytes += Int64(data.count)
            rewritten = rewrite(rewritten, remote: resource.reference, local: name)
            let done = index + 1; update(id) { $0.receivedBytes = bytes; $0.totalBytes = max($0.totalBytes, bytes); $0.progress = min(Double(done) / Double(resources.count), 0.99) }
        }
        try Task.checkCancellation(); guard !tombstones.contains(id) else { throw CancellationError() }
        let manifestFile = directory.appendingPathComponent("index.m3u8"); try rewritten.data(using: .utf8)?.write(to: manifestFile, options: [.atomic])
        var localAudio: [OfflineTrack] = []
        for (index, track) in item.audioSources.enumerated() {
            guard let remote = Self.remoteURL(track.url) else { continue }
            if remote.absoluteString == source.absoluteString { localAudio.append(OfflineTrack(key: track.key, label: track.label, url: "index.m3u8", language: track.language, format: track.format)); continue }
            do {
                let folder = directory.appendingPathComponent("audio_\(index)", isDirectory: true)
                let result = try await downloadHLS(remote, into: folder, prefix: "audio")
                bytes += result.bytes
                localAudio.append(OfflineTrack(key: track.key, label: track.label, url: "audio_\(index)/index.m3u8", language: track.language, format: track.format))
            } catch is CancellationError { throw CancellationError() } catch { }
        }
        var localSubtitles: [OfflineTrack] = []
        for (index, track) in item.subtitles.enumerated() {
            guard let remote = Self.remoteURL(track.url) else { continue }
            do {
                let format = (track.format?.isEmpty == false ? track.format! : (remote.pathExtension.isEmpty ? "vtt" : remote.pathExtension)).lowercased()
                let name = "subtitle_\(index).\(format)"; let subtitle = try await data(from: remote); try subtitle.write(to: directory.appendingPathComponent(name), options: [.atomic]); bytes += Int64(subtitle.count)
                localSubtitles.append(OfflineTrack(key: track.key, label: track.label, url: name, language: track.language, format: format))
            } catch is CancellationError { throw CancellationError() } catch { }
        }
        update(id) { $0.state = .completed; $0.localManifestPath = "\(id)/index.m3u8"; $0.audioSources = localAudio; $0.subtitles = localSubtitles; $0.progress = 1; $0.receivedBytes = bytes; $0.totalBytes = bytes; $0.taskIdentifier = nil; $0.error = "" }
    }

    private static func remoteURL(_ value: String) -> URL? { guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }; return url }
    private func downloadHLS(_ source: URL, into directory: URL, prefix: String) async throws -> (bytes: Int64, files: Int) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var manifestURL = source; var manifest = try await text(from: manifestURL)
        guard manifest.hasPrefix("#EXTM3U") else { throw OfflineError.notHLS }
        if manifest.contains("#EXT-X-STREAM-INF") { guard let variant = bestVariant(in: manifest, relativeTo: manifestURL) else { throw OfflineError.noVariant }; manifestURL = variant; manifest = try await text(from: manifestURL) }
        guard !manifest.contains("METHOD=SAMPLE-AES"), !manifest.contains("KEYFORMAT=") else { throw OfflineError.drm }
        let resources = manifestResources(in: manifest, relativeTo: manifestURL); guard !resources.isEmpty else { throw OfflineError.empty }
        var rewritten = manifest; var bytes: Int64 = 0
        for (index, resource) in resources.enumerated() { try Task.checkCancellation(); let name = "\(prefix)_\(resource.kind)_\(String(format: "%05d", index)).\(fileExtension(for: resource))"; let payload = try await data(from: resource.url); try payload.write(to: directory.appendingPathComponent(name), options: [.atomic]); bytes += Int64(payload.count); rewritten = rewrite(rewritten, remote: resource.reference, local: name) }
        try rewritten.data(using: .utf8)?.write(to: directory.appendingPathComponent("index.m3u8"), options: [.atomic]); return (bytes, resources.count)
    }
    private func request(_ url: URL) -> URLRequest { var request = URLRequest(url: url); request.timeoutInterval = 120; request.setValue(AppEnvironment.siteBaseURL.absoluteString, forHTTPHeaderField: "Origin"); request.setValue(AppEnvironment.siteBaseURL.appendingPathComponent("").absoluteString, forHTTPHeaderField: "Referer"); request.setValue(AppEnvironment.userAgent, forHTTPHeaderField: "User-Agent"); return request }
    private func data(from url: URL) async throws -> Data { let (data, response) = try await URLSession.shared.data(for: request(url)); guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw OfflineError.sourceUnavailable }; return data }
    private func text(from url: URL) async throws -> String { guard let value = String(data: try await data(from: url), encoding: .utf8) else { throw OfflineError.notHLS }; return value }
    private func bestVariant(in manifest: String, relativeTo base: URL) -> URL? { let lines = manifest.components(separatedBy: .newlines); var values: [(Int, URL)] = []; for i in lines.indices where lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("#EXT-X-STREAM-INF:") { let line = lines[i]; let bandwidth = Int(line.firstMatch(#"BANDWIDTH=(\d+)"#) ?? "0") ?? 0; var j = i + 1; while j < lines.count { let candidate = lines[j].trimmingCharacters(in: .whitespacesAndNewlines); if !candidate.isEmpty { if !candidate.hasPrefix("#"), let url = URL(string: candidate, relativeTo: base)?.absoluteURL { values.append((bandwidth, url)) }; break }; j += 1 } }; return values.max { $0.0 < $1.0 }?.1 }
    private func manifestResources(in manifest: String, relativeTo base: URL) -> [HLSResource] { var result: [HLSResource] = []; var seen = Set<String>(); for raw in manifest.components(separatedBy: .newlines) { let line = raw.trimmingCharacters(in: .whitespacesAndNewlines); if line.isEmpty { continue }; if !line.hasPrefix("#"), seen.insert(line).inserted, let url = URL(string: line, relativeTo: base)?.absoluteURL { result.append(HLSResource(reference: line, url: url, kind: "segment")) } else if line.hasPrefix("#EXT-X-KEY:") || line.hasPrefix("#EXT-X-MAP:"), let reference = line.firstMatch(#"URI="([^"]+)""#), seen.insert(reference).inserted, let url = URL(string: reference, relativeTo: base)?.absoluteURL { result.append(HLSResource(reference: reference, url: url, kind: line.hasPrefix("#EXT-X-KEY:") ? "key" : "map")) } }; return result }
    private func rewrite(_ manifest: String, remote: String, local: String) -> String { manifest.components(separatedBy: .newlines).map { line in let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines); if trimmed == remote { return local }; if (trimmed.hasPrefix("#EXT-X-KEY:") || trimmed.hasPrefix("#EXT-X-MAP:")) && line.contains("URI=\"\(remote)\"") { return line.replacingOccurrences(of: "URI=\"\(remote)\"", with: "URI=\"\(local)\"") }; return line }.joined(separator: "\n") }
    private func fileExtension(for resource: HLSResource) -> String { if resource.kind == "key" { return "key" }; let ext = resource.url.pathExtension.lowercased(); if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) { return ext }; return resource.kind == "map" ? "mp4" : "ts" }

    private func ensureLoaded() async { if !loaded { await load() } }
    private func itemDirectory(_ id: String) -> URL { rootURL.appendingPathComponent(id, isDirectory: true) }
    private func resolvedURL(_ item: OfflineDownloadItem) -> URL { let candidate = (item.localManifestPath.hasPrefix("/") ? URL(fileURLWithPath: item.localManifestPath) : rootURL.appendingPathComponent(item.localManifestPath)).standardizedFileURL; let root = rootURL.standardizedFileURL.path + "/"; guard candidate.path.hasPrefix(root), candidate.path == itemDirectory(item.id).appendingPathComponent("index.m3u8").standardizedFileURL.path else { return rootURL.appendingPathComponent(".invalid") }; return candidate }
    private func fileExists(_ item: OfflineDownloadItem) -> Bool { !item.localManifestPath.isEmpty && FileManager.default.fileExists(atPath: resolvedURL(item).path) }
    private func migratePath(_ path: String, id: String) -> String { guard !path.isEmpty else { return path }; if path == "\(id)/index.m3u8" { return path }; if path.hasSuffix("asset.movpkg") { return path }; return path }
    private func replaceAndPersist(_ item: OfflineDownloadItem) throws { if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = item } else { items.insert(item, at: 0) }; try persistNow() }
    private func update(_ id: String, _ body: (inout OfflineDownloadItem) -> Void) { guard !tombstones.contains(id), let index = items.firstIndex(where: { $0.id == id }) else { return }; body(&items[index]); persist() }
    private func persist() { do { try persistNow(); loadError = nil } catch { loadError = "Không thể lưu thay đổi thư viện tải xuống."; schedulePersistRetry() } }
    private func persistNow() throws { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true); let data = try JSONEncoder.offline.encode(items); let temporary = indexURL.appendingPathExtension("tmp"); try data.write(to: temporary, options: [.atomic]); if FileManager.default.fileExists(atPath: indexURL.path) { _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: temporary) } else { try FileManager.default.moveItem(at: temporary, to: indexURL) } }
    private func schedulePersistRetry() { persistRetry?.cancel(); persistRetry = Task { try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }; do { try persistNow(); loadError = nil } catch { loadError = "Không thể lưu thay đổi thư viện tải xuống." } } }
}

private struct HLSResource { let reference: String; let url: URL; let kind: String }

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
enum OfflineError: LocalizedError { case unsupported, sourceUnavailable, notHLS, noVariant, drm, empty; var errorDescription: String? { switch self { case .unsupported: "Nguồn này không hỗ trợ tải offline"; case .sourceUnavailable: "Nguồn phim không còn khả dụng. Vui lòng chọn server khác."; case .notHLS: "Nguồn trả về không phải HLS"; case .noVariant: "Không tìm thấy luồng HLS phù hợp"; case .drm: "Nguồn DRM không hỗ trợ tải offline"; case .empty: "Danh sách HLS không có phân đoạn video" } } }
private extension JSONEncoder { static var offline: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder } }
private extension JSONDecoder { static var offline: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder } }
