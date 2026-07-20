import AVFoundation
import Foundation

struct OfflineTrack: Codable, Hashable, Identifiable {
    var key: String; var label: String; var url: String; var language: String?; var format: String?
    var id: String { key + "|" + url }
}

enum OfflineDownloadState: String, Codable { case queued, downloading, completed, failed, cancelled }

struct OfflineDownloadItem: Codable, Identifiable, Hashable {
    let id: String; let movieId: Int; let movieSlug: String; let movieTitle: String; let episodeName: String; let serverName: String; let sourceURL: String; let posterURL: String
    // AVAssetDownloadURLSession downloads the media selections embedded in the HLS asset.
    // These fields remain decode-compatible with the first beta, but the UI no longer promises
    // unsupported sidecar-track persistence.
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
    private let delegateQueue: OperationQueue = { let q = OperationQueue(); q.name = "live.cineviet.offline.delegate"; q.maxConcurrentOperationCount = 1; return q }()
    private lazy var session: AVAssetDownloadURLSession = {
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.backgroundIdentifier)
        configuration.sessionSendsLaunchEvents = true; configuration.isDiscretionary = false
        return AVAssetDownloadURLSession(configuration: configuration, assetDownloadDelegate: self, delegateQueue: delegateQueue)
    }()
    private var loaded = false
    private nonisolated let delegateEvents = OfflineDelegateEvents()
    private var tombstones = Set<String>()
    private var backgroundCompletion: (() -> Void)?
    private var backgroundEventsFinished = false
    private var persistRetry: Task<Void, Never>?
    private var indexURL: URL { rootURL.appendingPathComponent("downloads.json") }
    private var rootURL: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineDownloads", isDirectory: true) }
    override private init() { super.init() }

    func handleBackgroundEvents(completionHandler: @escaping () -> Void) {
        backgroundCompletion?()
        backgroundCompletion = completionHandler
        backgroundEventsFinished = false
        _ = session
    }

    private func finishDelegateEvent() {
        delegateEvents.endFinalization()
        completeBackgroundEventsIfReady()
    }

    private func completeBackgroundEventsIfReady() {
        guard backgroundEventsFinished, !delegateEvents.hasPendingFinalizations else { return }
        persist()
        let completion = backgroundCompletion
        backgroundCompletion = nil
        backgroundEventsFinished = false
        DispatchQueue.main.async { completion?() }
    }

    func load(force: Bool = false) async {
        guard force || !loaded else { return }; loaded = true; loadError = nil
        do {
            try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: indexURL.path) {
                var decoded = try JSONDecoder.offline.decode([OfflineDownloadItem].self, from: Data(contentsOf: indexURL)).filter { !$0.id.isEmpty }
                var seen = Set<String>(); decoded = decoded.filter { seen.insert($0.id).inserted }
                for index in decoded.indices { decoded[index].localManifestPath = migratePath(decoded[index].localManifestPath, id: decoded[index].id) }
                items = decoded
            }
            await reconcileTasks(); try persistNow()
        } catch { loadError = "Không đọc hoặc lưu được thư viện tải xuống." }
    }

    func enqueue(movie: Movie, server: EpisodeServer, episode: EpisodeItem) async throws {
        guard let source = Self.eligibleURL(episode), source.pathExtension.lowercased() == "m3u8" || source.absoluteString.lowercased().contains("m3u8") else { throw OfflineError.unsupported }
        await ensureLoaded()
        let id = OfflineDownloadItem.stableID(movieId: movie.id, slug: movie.slug, server: server.name, episode: episode.name)
        let tasks = await allTasks(); if tasks.contains(where: { $0.taskDescription == id && $0.state != .completed }) { return }
        if let old = items.first(where: { $0.id == id }), old.state == .completed, fileExists(old) { return }
        tombstones.remove(id)
        let item = OfflineDownloadItem(id: id, movieId: movie.id, movieSlug: movie.slug, movieTitle: movie.title, episodeName: episode.name, serverName: server.name, sourceURL: source.absoluteString, posterURL: movie.posterURL?.absoluteString ?? "", audioSources: [], subtitles: [], state: .queued, createdAt: items.first(where: { $0.id == id })?.createdAt ?? Date(), localManifestPath: "", receivedBytes: 0, totalBytes: 0, progress: 0, error: "", taskIdentifier: nil)
        try replaceAndPersist(item); try await start(id)
    }

    func retry(_ id: String) async {
        await ensureLoaded(); guard let item = items.first(where: { $0.id == id }), !item.isActive else { return }
        let tasks = await allTasks(); guard !tasks.contains(where: { $0.taskDescription == id && $0.state != .completed }) else { return }
        tombstones.remove(id); try? FileManager.default.removeItem(at: itemDirectory(id)); update(id) { $0.localManifestPath = ""; $0.error = ""; $0.progress = 0 }
        do { try await start(id) } catch { update(id) { $0.state = .failed; $0.error = "Không thể tạo tác vụ tải xuống" } }
    }

    func cancel(_ id: String) async {
        await ensureLoaded(); let tasks = await allTasks(); tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        update(id) { $0.state = .cancelled; $0.error = "Đã hủy"; $0.taskIdentifier = nil }
    }

    func delete(_ id: String) async {
        await ensureLoaded(); tombstones.insert(id)
        let tasks = await allTasks(); tasks.filter { $0.taskDescription == id }.forEach { $0.cancel() }
        try? FileManager.default.removeItem(at: itemDirectory(id)); items.removeAll { $0.id == id }; persist()
    }
    func deleteMovie(_ ids: [String]) async {
        await ensureLoaded()
        let deleting = Set(ids)
        tombstones.formUnion(deleting)
        let tasks = await allTasks()
        tasks.filter { task in task.taskDescription.map(deleting.contains) == true }.forEach { $0.cancel() }
        for id in deleting { try? FileManager.default.removeItem(at: itemDirectory(id)) }
        items.removeAll { deleting.contains($0.id) }
        persist()
    }

    func playbackURL(for item: OfflineDownloadItem) -> URL? { let url = resolvedURL(item); return FileManager.default.fileExists(atPath: url.path) ? url : nil }
    static func serverEligible(_ server: EpisodeServer) -> Bool {
        let normalized = server.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).replacingOccurrences(of: " ", with: "").lowercased()
        guard normalized != "nguonc", !server.items.contains(where: { ($0.linkEmbed + $0.linkM3u8).lowercased().contains("streamc.xyz") }) else { return false }
        return server.items.contains { eligibleURL($0) != nil }
    }
    static func eligibleURL(_ episode: EpisodeItem) -> URL? { guard !episode.linkM3u8.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let u = PlayerViewModel.directMediaURL(for: episode), !u.absoluteString.lowercased().contains("/embed") else { return nil }; return u }

    private func ensureLoaded() async { if !loaded { await load() } }
    private func allTasks() async -> [URLSessionTask] { await withCheckedContinuation { continuation in session.getAllTasks { continuation.resume(returning: $0) } } }
    private func start(_ id: String) async throws {
        guard let item = items.first(where: { $0.id == id }), let url = URL(string: item.sourceURL) else { throw OfflineError.unsupported }
        // Match Player transport: CineViet's HLS gateway rejects playlist, key and
        // segment requests without trusted app provenance. AVURLAsset propagates
        // these fields through the full asset-download resource graph.
        let headers = [
            "Origin": AppEnvironment.siteBaseURL.absoluteString,
            "Referer": AppEnvironment.siteBaseURL.appendingPathComponent("").absoluteString,
            "User-Agent": AppEnvironment.userAgent
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        guard let task = session.makeAssetDownloadTask(asset: asset, assetTitle: "\(item.movieTitle) – \(item.episodeName)", assetArtworkData: nil, options: [AVAssetDownloadTaskMinimumRequiredMediaBitrateKey: 0]) else { throw OfflineError.cannotCreate }
        task.taskDescription = id; update(id) { $0.state = .downloading; $0.error = ""; $0.progress = 0; $0.taskIdentifier = task.taskIdentifier }; task.resume()
    }
    private func reconcileTasks() async {
        let tasks = await allTasks(); var byID: [String: URLSessionTask] = [:]
        for task in tasks {
            guard let id = task.taskDescription, !id.isEmpty else { task.cancel(); continue }
            if tombstones.contains(id) { task.cancel(); continue }
            if byID[id] == nil { byID[id] = task } else { task.cancel() }
            if !items.contains(where: { $0.id == id }) { task.cancel() } // orphan: no trustworthy metadata
        }
        for index in items.indices {
            if let task = byID[items[index].id] { items[index].taskIdentifier = task.taskIdentifier; items[index].state = .downloading }
            else if items[index].isActive { items[index].state = .cancelled; items[index].error = "Đã hủy"; items[index].taskIdentifier = nil }
            if items[index].state == .completed, !fileExists(items[index]) { items[index].state = .failed; items[index].error = "Bản tải xuống không còn trên thiết bị" }
        }
    }
    private func itemDirectory(_ id: String) -> URL { rootURL.appendingPathComponent(id, isDirectory: true) }
    private func resolvedURL(_ item: OfflineDownloadItem) -> URL {
        let candidate = (item.localManifestPath.hasPrefix("/") ? URL(fileURLWithPath: item.localManifestPath) : rootURL.appendingPathComponent(item.localManifestPath)).standardizedFileURL
        let root = rootURL.standardizedFileURL.path + "/"
        guard candidate.path.hasPrefix(root), candidate.path == itemDirectory(item.id).appendingPathComponent("asset.movpkg", isDirectory: true).standardizedFileURL.path else { return rootURL.appendingPathComponent(".invalid") }
        return candidate
    }
    private func fileExists(_ item: OfflineDownloadItem) -> Bool { !item.localManifestPath.isEmpty && FileManager.default.fileExists(atPath: resolvedURL(item).path) }
    private func migratePath(_ path: String, id: String) -> String {
        guard !path.isEmpty else { return path }; if !path.hasPrefix("/") { return path }
        let legacy = URL(fileURLWithPath: path); if FileManager.default.fileExists(atPath: legacy.path) {
            let destination = itemDirectory(id).appendingPathComponent("asset.movpkg", isDirectory: true)
            if legacy.standardizedFileURL != destination.standardizedFileURL { try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true); try? FileManager.default.moveItem(at: legacy, to: destination) }
        }
        return "\(id)/asset.movpkg"
    }
    private func replaceAndPersist(_ item: OfflineDownloadItem) throws { if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item } else { items.insert(item, at: 0) }; try persistNow() }
    private func update(_ id: String, _ body: (inout OfflineDownloadItem) -> Void) { guard !tombstones.contains(id), let i = items.firstIndex(where: { $0.id == id }) else { return }; body(&items[i]); persist() }
    private func persist() { do { try persistNow(); loadError = nil } catch { loadError = "Không thể lưu thay đổi thư viện tải xuống."; schedulePersistRetry() } }
    private func persistNow() throws { try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true); let data = try JSONEncoder.offline.encode(items); let tmp = indexURL.appendingPathExtension("tmp"); try data.write(to: tmp, options: [.atomic]); if FileManager.default.fileExists(atPath: indexURL.path) { _ = try FileManager.default.replaceItemAt(indexURL, withItemAt: tmp) } else { try FileManager.default.moveItem(at: tmp, to: indexURL) } }
    private func schedulePersistRetry() { persistRetry?.cancel(); persistRetry = Task { try? await Task.sleep(nanoseconds: 1_000_000_000); guard !Task.isCancelled else { return }; do { try persistNow(); loadError = nil } catch { loadError = "Không thể lưu thay đổi thư viện tải xuống." } } }
}

extension OfflineDownloadManager: AVAssetDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didLoad timeRange: CMTimeRange, totalTimeRangesLoaded ranges: [NSValue], timeRangeExpectedToLoad expectedRange: CMTimeRange) { let expected = expectedRange.duration.seconds; let value = expected > 0 ? ranges.reduce(0) { $0 + $1.timeRangeValue.duration.seconds } / expected : 0; guard let id = assetDownloadTask.taskDescription else { return }; Task { @MainActor in self.update(id) { $0.progress = min(max(value, 0), 0.99); $0.state = .downloading } } }
    nonisolated func urlSession(_ session: URLSession, assetDownloadTask: AVAssetDownloadTask, didFinishDownloadingTo location: URL) {
        // The system-owned location is temporary. Move it before returning from
        // the delegate callback, then finalize it on the main actor in order.
        delegateEvents.stage(location, for: assetDownloadTask.taskIdentifier)
    }
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) { guard let id = task.taskDescription else { return }; delegateEvents.beginFinalization(); let taskID = task.taskIdentifier; let temporary = delegateEvents.take(taskID); let stagingError = delegateEvents.takeError(taskID); let errorCode = (error as NSError?)?.code; Task { @MainActor in
        defer { self.finishDelegateEvent() }
        if self.tombstones.contains(id) { if let temporary { try? FileManager.default.removeItem(at: temporary) }; return }
        if let errorCode { if let temporary { try? FileManager.default.removeItem(at: temporary) }; self.update(id) { $0.state = errorCode == NSURLErrorCancelled ? .cancelled : .failed; $0.error = errorCode == NSURLErrorCancelled ? "Đã hủy" : "Lỗi mạng khi tải video"; $0.taskIdentifier = nil }; return }
        guard let temporary, stagingError == nil else { self.update(id) { $0.state = .failed; $0.error = stagingError ?? "Không tìm thấy tệp đã tải"; $0.taskIdentifier = nil }; return }
        do { let destination = self.itemDirectory(id).appendingPathComponent("asset.movpkg", isDirectory: true); try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()); try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true); try FileManager.default.moveItem(at: temporary, to: destination); let bytes = (try? FileManager.default.allocatedSizeOfDirectory(at: destination)) ?? 0; self.update(id) { $0.state = .completed; $0.localManifestPath = "\(id)/asset.movpkg"; $0.progress = 1; $0.receivedBytes = bytes; $0.totalBytes = bytes; $0.taskIdentifier = nil; $0.error = "" } } catch { self.update(id) { $0.state = .failed; $0.error = "Không thể lưu bản tải xuống"; $0.taskIdentifier = nil } }
    } }
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) { Task { @MainActor in self.backgroundEventsFinished = true; self.completeBackgroundEventsIfReady() } }
}

enum OfflineError: LocalizedError { case unsupported, cannotCreate; var errorDescription: String? { switch self { case .unsupported: "Nguồn này không hỗ trợ tải offline"; case .cannotCreate: "Không thể tạo tác vụ tải xuống" } } }
private extension JSONEncoder { static var offline: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e } }
private extension JSONDecoder { static var offline: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
private extension FileManager { func allocatedSizeOfDirectory(at url: URL) throws -> Int64 { let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]; return try enumerator(at: url, includingPropertiesForKeys: Array(keys))?.compactMap { $0 as? URL }.reduce(0) { result, file in let v = try? file.resourceValues(forKeys: keys); return result + Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0) } ?? 0 } }
private final class OfflineDelegateEvents: @unchecked Sendable {
    private let lock = NSLock(); private var locations: [Int: URL] = [:]; private var errors: [Int: String] = [:]; private var pendingFinalizations = 0
    func stage(_ url: URL, for id: Int) {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OfflineDownloads/.incoming", isDirectory: true)
        let destination = root.appendingPathComponent("\(id).movpkg", isDirectory: true)
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); try? FileManager.default.removeItem(at: destination); try FileManager.default.moveItem(at: url, to: destination); lock.lock(); locations[id] = destination; lock.unlock() }
        catch { lock.lock(); errors[id] = "Không thể lưu tệp tải xuống tạm thời"; lock.unlock() }
    }
    func take(_ id: Int) -> URL? { lock.lock(); defer { lock.unlock() }; return locations.removeValue(forKey: id) }
    func takeError(_ id: Int) -> String? { lock.lock(); defer { lock.unlock() }; return errors.removeValue(forKey: id) }
    func beginFinalization() { lock.lock(); pendingFinalizations += 1; lock.unlock() }
    func endFinalization() { lock.lock(); pendingFinalizations = max(0, pendingFinalizations - 1); lock.unlock() }
    var hasPendingFinalizations: Bool { lock.lock(); defer { lock.unlock() }; return pendingFinalizations != 0 }
}
