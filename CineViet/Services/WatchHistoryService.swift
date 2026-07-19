import Foundation

struct WatchHistoryItem: Decodable, Equatable {
    let movieId: Int
    let serverName: String
    let serverIndex: Int
    let episodeName: String
    let streamURL: String
    let positionSeconds: Double
    let durationSeconds: Double

    enum CodingKeys: String, CodingKey {
        case movieId = "movie_id", serverName = "server_name", serverIndex = "server_index"
        case episodeName = "episode_name", streamURL = "stream_url"
        case positionSeconds = "position_seconds", durationSeconds = "duration_seconds"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        movieId = values.decodeFlexibleInt(forKey: .movieId) ?? 0
        serverName = (try? values.decode(String.self, forKey: .serverName)) ?? ""
        serverIndex = values.decodeFlexibleInt(forKey: .serverIndex) ?? 0
        episodeName = (try? values.decode(String.self, forKey: .episodeName)) ?? ""
        streamURL = (try? values.decode(String.self, forKey: .streamURL)) ?? ""
        positionSeconds = values.decodeFlexibleDouble(forKey: .positionSeconds) ?? 0
        durationSeconds = values.decodeFlexibleDouble(forKey: .durationSeconds) ?? 0
    }
}

private struct WatchHistoryEnvelope: Decodable {
    let items: [WatchHistoryItem]

    private enum CodingKeys: String, CodingKey { case history }

    init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([WatchHistoryItem].self) {
            items = list
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? values.decode([WatchHistoryItem].self, forKey: .history)) ?? []
    }
}

private struct WatchProgressPayload: Encodable {
    let movieId: Int
    let episode: Int
    let progress: Int
    let completed: Int
    let positionSeconds: Double
    let durationSeconds: Double
    let serverIndex: Int
    let episodeName: String
    let serverName: String
    let streamURL: String

    enum CodingKeys: String, CodingKey {
        case movieId = "movie_id", episode, progress, completed
        case positionSeconds = "position_seconds", durationSeconds = "duration_seconds"
        case serverIndex = "server_index", episodeName = "episode_name"
        case serverName = "server_name", streamURL = "stream_url"
    }
}

protocol WatchHistoryServicing {
    func resume(movieId: Int) async -> WatchHistoryItem?
    func save(movie: Movie, server: EpisodeServer, serverIndex: Int, episode: EpisodeItem, position: Double, duration: Double) async
}

struct WatchHistoryService: WatchHistoryServicing {
    let apiClient: APIClient

    func resume(movieId: Int) async -> WatchHistoryItem? {
        var request = APIRequest(method: .get, path: "/history/continue-watching", requiresAuthentication: true)
        request.queryItems = [URLQueryItem(name: "limit", value: "20")]
        let envelope: WatchHistoryEnvelope? = try? await apiClient.send(request)
        return envelope?.items.first { $0.movieId == movieId && $0.positionSeconds >= 3 && $0.durationSeconds > 0 && $0.positionSeconds / $0.durationSeconds < 0.95 }
    }

    func save(movie: Movie, server: EpisodeServer, serverIndex: Int, episode: EpisodeItem, position: Double, duration: Double) async {
        guard movie.id > 0, position >= 3, duration.isFinite, duration > 0 else { return }
        let ratio = min(max(position / duration, 0), 1)
        let payload = WatchProgressPayload(
            movieId: movie.id, episode: Self.episodeNumber(episode.name), progress: Int((ratio * 100).rounded()),
            completed: ratio >= 0.95 ? 1 : 0, positionSeconds: position, durationSeconds: duration,
            serverIndex: serverIndex, episodeName: episode.name, serverName: server.name,
            streamURL: Self.mediaURL(for: episode)?.absoluteString ?? episode.playUrl
        )
        guard let watch = try? APIRequest.json(method: .post, path: "/movies/\(movie.id)/watch", body: payload, requiresAuthentication: true),
              let history = try? APIRequest.json(method: .post, path: "/history", body: payload, requiresAuthentication: true) else { return }
        try? await apiClient.send(watch)
        try? await apiClient.send(history)
    }

    private static func mediaURL(for episode: EpisodeItem) -> URL? {
        let source = episode.audioSources.first { $0.key.lowercased() == "original" } ?? episode.audioSources.first
        let raw = [source?.url, episode.linkM3u8].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? ""
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if let url = URL(string: raw), url.scheme == "http" || url.scheme == "https" { return url }
        return URL(string: raw, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }

    private static func episodeNumber(_ name: String) -> Int {
        let digits = name.split(whereSeparator: { !$0.isNumber }).first(where: { !$0.isEmpty })
        return digits.flatMap { Int($0) } ?? 0
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeFlexibleDouble(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
}
