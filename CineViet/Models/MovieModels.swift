import Foundation

struct Movie: Codable, Identifiable, Equatable {
    let id: Int
    let title: String
    let slug: String
    let titleEn: String
    let description: String
    let tmdbId: String
    let imdbId: String
    let poster: String
    let backdrop: String
    let thumbnail: String
    let trailerUrl: String
    let releaseYear: Int?
    let duration: Int?
    let rating: Double?
    let quality: String
    let language: String
    let country: String
    let type: String
    let episodeCurrent: String
    let totalEpisodes: Int?
    let partNumber: Int?
    let genres: [String]
    let cast: [MoviePerson]
    let directors: [MoviePerson]
    let episodes: [EpisodeServer]
    let related: [Movie]
    let collection: MovieCollection?

    init(watchTogetherTitle title: String, code: String, videoURL: String) {
        id = 0; self.title = title; slug = "watch-together-\(code)"; titleEn = ""; description = ""; tmdbId = ""; imdbId = ""; poster = ""; backdrop = ""; thumbnail = ""; trailerUrl = ""; releaseYear = nil; duration = nil; rating = nil; quality = ""; language = ""; country = ""; type = ""; episodeCurrent = ""; totalEpisodes = nil; partNumber = nil; genres = []; cast = []; directors = []
        episodes = [EpisodeServer(name: "Xem chung", items: [EpisodeItem(watchTogetherURL: videoURL)])]
        related = []; collection = nil
    }

    static func offline(id: Int, slug: String, title: String, poster: String, server: EpisodeServer) -> Movie {
        Movie(offlineID: id, slug: slug, title: title, poster: poster, server: server)
    }

    private init(offlineID: Int, slug: String, title: String, poster: String, server: EpisodeServer) {
        id = offlineID; self.title = title; self.slug = slug; titleEn = ""; description = ""; tmdbId = ""; imdbId = ""; self.poster = poster; backdrop = ""; thumbnail = ""; trailerUrl = ""; releaseYear = nil; duration = nil; rating = nil; quality = ""; language = ""; country = ""; type = ""; episodeCurrent = ""; totalEpisodes = 1; partNumber = nil; genres = []; cast = []; directors = []; episodes = [server]; related = []; collection = nil
    }

    var routeKey: String { slug.isEmpty ? String(id) : slug }

    var posterURL: URL? {
        imageURL(from: poster.isEmpty ? thumbnail : poster, tmdbSize: "w500")
    }

    var backdropURL: URL? {
        let source = backdrop.isEmpty ? (thumbnail.isEmpty ? poster : thumbnail) : backdrop
        return imageURL(from: source, tmdbSize: "w1280")
    }

    var metadataLine: String {
        [releaseYear.map(String.init), quality.nonEmpty, language.nonEmpty, episodeCurrent.nonEmpty]
            .compactMap { $0 }
            .joined(separator: "  •  ")
    }

    private func imageURL(from value: String, tmdbSize: String) -> URL? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw != "null" else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if raw.hasPrefix("/"), !tmdbId.isEmpty {
            return URL(string: "https://image.tmdb.org/t/p/\(tmdbSize)\(raw)")
        }
        if raw.hasPrefix("/") { return URL(string: "\(AppEnvironment.siteBaseURL.absoluteString)\(raw)") }
        return URL(string: "\(AppEnvironment.siteBaseURL.absoluteString)/\(raw)")
    }

    enum CodingKeys: String, CodingKey {
        case id, title, slug, description, poster, backdrop, thumbnail, duration, rating, quality, language, country, type, genres, cast, episodes, related, collection
        case titleEn = "title_en", tmdbId = "tmdb_id", imdbId = "imdb_id", trailerUrl = "trailer_url", releaseYear = "release_year", episodeCurrent = "episode_current", totalEpisodes = "total_episodes", partNumber = "part_number", directors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeFlexibleInt(.id) ?? 0
        title = try c.decodeFlexibleString(.title)?.nonEmpty ?? "Không tên"
        slug = try c.decodeFlexibleString(.slug) ?? String(id)
        titleEn = try c.decodeFlexibleString(.titleEn) ?? ""
        description = try c.decodeFlexibleString(.description) ?? ""
        tmdbId = try c.decodeFlexibleString(.tmdbId) ?? ""
        imdbId = try c.decodeFlexibleString(.imdbId) ?? ""
        poster = try c.decodeFlexibleString(.poster) ?? ""
        backdrop = try c.decodeFlexibleString(.backdrop) ?? ""
        thumbnail = try c.decodeFlexibleString(.thumbnail) ?? ""
        trailerUrl = try c.decodeFlexibleString(.trailerUrl) ?? ""
        releaseYear = try c.decodeFlexibleInt(.releaseYear)
        duration = try c.decodeFlexibleInt(.duration)
        rating = try c.decodeFlexibleDouble(.rating)
        quality = try c.decodeFlexibleString(.quality) ?? ""
        language = try c.decodeFlexibleString(.language) ?? ""
        country = try c.decodeFlexibleString(.country) ?? ""
        type = try c.decodeFlexibleString(.type) ?? ""
        episodeCurrent = try c.decodeFlexibleString(.episodeCurrent) ?? ""
        totalEpisodes = try c.decodeFlexibleInt(.totalEpisodes)
        partNumber = try c.decodeFlexibleInt(.partNumber)
        genres = try c.decodeStringList(.genres)
        cast = try c.decodeFlexibleArray(.cast, as: MoviePerson.self)
        directors = try c.decodeFlexibleArray(.directors, as: MoviePerson.self)
        episodes = try c.decodeFlexibleArray(.episodes, as: EpisodeServer.self)
        related = try c.decodeIfPresent([Movie].self, forKey: .related) ?? []
        collection = try c.decodeIfPresent(MovieCollection.self, forKey: .collection)
    }
}

struct MoviePerson: Codable, Equatable {
    let name: String
    let avatar: String

    var avatarURL: URL? {
        let raw = avatar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, raw.lowercased() != "null" else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return URL(string: raw) }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        // TMDB profile paths are returned as /abc123.jpg, matching app v2.
        if raw.hasPrefix("/"), !raw.hasPrefix("/uploads/") { return URL(string: "https://image.tmdb.org/t/p/w185\(raw)") }
        return URL(string: raw, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            name = value; avatar = ""; return
        }
        let raw = try [String: JSONValue](from: decoder)
        name = raw["name"]?.stringValue.nonEmpty ?? raw["title"]?.stringValue ?? ""
        avatar = raw["avatar"]?.stringValue.nonEmpty
            ?? raw["photo"]?.stringValue.nonEmpty
            ?? raw["profile_path"]?.stringValue
            ?? ""
    }
}

struct MovieCollection: Codable, Equatable {
    let id: Int
    let title: String
    let items: [MovieCollectionItem]
}

struct MovieCollectionItem: Codable, Equatable {
    let movieId: Int
    let slug: String
    let title: String
    let displayName: String
    let sortOrder: Int
    let isCurrent: Bool
    let posterUrl: String
    let year: Int?

    enum CodingKeys: String, CodingKey {
        case movieId = "movie_id", slug, title, displayName = "display_name"
        case sortOrder = "sort_order", isCurrent = "is_current"
        case posterUrl = "poster_url", year
    }
}

struct EpisodeServer: Codable, Equatable {
    let name: String
    let items: [EpisodeItem]
    enum CodingKeys: String, CodingKey { case name = "server_name", items = "server_data" }
    init(name: String, items: [EpisodeItem]) { self.name = name; self.items = items }
}

struct EpisodeItem: Codable, Equatable, Identifiable {
    let name: String
    let filename: String
    let linkM3u8: String
    let linkEmbed: String
    let subtitles: [EpisodeSubtitleTrack]
    let audioSources: [EpisodeAudioSource]
    var id: String { "\(name)|\(linkM3u8)|\(linkEmbed)" }
    var playUrl: String { linkM3u8.isEmpty ? linkEmbed : linkM3u8 }
    enum CodingKeys: String, CodingKey { case name, filename, linkM3u8 = "link_m3u8", linkEmbed = "link_embed", subtitles, audioSources = "audio_sources" }
    init(watchTogetherURL: String) { name = "Đang xem"; filename = ""; linkM3u8 = watchTogetherURL; linkEmbed = ""; subtitles = []; audioSources = [] }
    static func offline(name: String, path: String, subtitles: [EpisodeSubtitleTrack] = [], audioSources: [EpisodeAudioSource] = []) -> EpisodeItem { EpisodeItem(offlineName: name, path: path, subtitles: subtitles, audioSources: audioSources) }
    private init(offlineName: String, path: String, subtitles: [EpisodeSubtitleTrack], audioSources: [EpisodeAudioSource]) { name = offlineName; filename = ""; linkM3u8 = URL(fileURLWithPath: path).absoluteString; linkEmbed = ""; self.subtitles = subtitles; self.audioSources = audioSources }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Tập phim"
        filename = try c.decodeIfPresent(String.self, forKey: .filename) ?? ""
        linkM3u8 = try c.decodeIfPresent(String.self, forKey: .linkM3u8) ?? ""
        linkEmbed = try c.decodeIfPresent(String.self, forKey: .linkEmbed) ?? ""
        subtitles = try c.decodeIfPresent([EpisodeSubtitleTrack].self, forKey: .subtitles) ?? []
        audioSources = try c.decodeIfPresent([EpisodeAudioSource].self, forKey: .audioSources) ?? []
    }
}

struct IntroSkipSegment: Codable, Equatable, Identifiable {
    let type: String
    let start: Double
    let end: Double
    var id: String { "\(type):\(start):\(end)" }
    var label: String {
        switch type.lowercased() { case "recap": return "Bỏ qua recap"; case "outro": return "Bỏ qua outro"; default: return "Bỏ qua intro" }
    }
    enum CodingKeys: String, CodingKey { case type, start = "start_sec", end = "end_sec" }
}

struct IntroSkipResponse: Codable { let segments: [IntroSkipSegment] }

struct EpisodeSubtitleTrack: Codable, Equatable, Identifiable {
    let lang: String
    let label: String
    let url: String
    let format: String
    var id: String { "\(lang)|\(url)" }
    enum CodingKeys: String, CodingKey { case lang, label, url, format }
}

struct EpisodeAudioSource: Codable, Equatable, Identifiable {
    let key: String
    let label: String
    let url: String
    var id: String { "\(key)|\(url)" }
}

extension KeyedDecodingContainer {
    func decodeFlexibleArray<Element: Decodable>(_ key: Key, as type: Element.Type) throws -> [Element] {
        if !contains(key) || (try? decodeNil(forKey: key)) == true { return [] }
        if let values = try? decode([Element].self, forKey: key) { return values }
        if let raw = try? decode(String.self, forKey: key) {
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text != "null", let data = text.data(using: .utf8) else { return [] }
            return (try? JSONDecoder.cineViet.decode([Element].self, from: data)) ?? []
        }
        return []
    }

    func decodeFlexibleString(_ key: Key) throws -> String? {
        if let value = try? decode(String.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return String(value) }
        if let value = try? decode(Double.self, forKey: key) { return String(value) }
        if let value = try? decode(Bool.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeFlexibleInt(_ key: Key) throws -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(Double.self, forKey: key) { return Int(value) }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        if let value = try? decode(Bool.self, forKey: key) { return value ? 1 : 0 }
        return nil
    }

    func decodeFlexibleDouble(_ key: Key) throws -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        if let value = try? decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? decode(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func decodeStringList(_ key: Key) throws -> [String] {
        if let value = try? decode([String].self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return []
    }
}
