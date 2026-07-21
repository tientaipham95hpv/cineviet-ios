import Foundation

struct CinePlaylist: Codable, Identifiable, Equatable {
    let id: Int
    let name: String
    let slug: String
    let description: String
    let cover: String
    let movieCount: Int
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, slug, description, cover, movieCount = "movie_count", isPublic = "is_public"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(Int.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        slug = try values.decodeIfPresent(String.self, forKey: .slug) ?? ""
        description = try values.decodeIfPresent(String.self, forKey: .description) ?? ""
        cover = try values.decodeIfPresent(String.self, forKey: .cover) ?? ""
        movieCount = try values.decodeIfPresent(Int.self, forKey: .movieCount) ?? 0
        isPublic = (try? values.decode(Bool.self, forKey: .isPublic))
            ?? ((try? values.decode(Int.self, forKey: .isPublic)) == 1)
    }
}

struct PlaylistDetail: Equatable {
    let playlist: CinePlaylist
    let movies: [Movie]
}

protocol LibraryServicing {
    func favorites() async throws -> [Movie]
    func favoriteIDs() async -> Set<Int>
    func toggleFavorite(movieID: Int, add: Bool) async throws
    func playlists() async throws -> [CinePlaylist]
    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> CinePlaylist
    func add(movieID: Int, to playlistID: Int) async throws
    func playlistDetail(_ playlist: CinePlaylist) async throws -> PlaylistDetail
    func updatePlaylist(_ playlistID: Int, name: String?, description: String?, isPublic: Bool?) async throws -> CinePlaylist
    func remove(movieID: Int, from playlistID: Int) async throws
    func deletePlaylist(_ playlistID: Int) async throws
    func comments(movieID: Int) async throws -> [MovieComment]
    func addComment(movieID: Int, content: String, isSpoiler: Bool) async throws -> MovieComment
    func ratingStats(movieID: Int) async throws -> RatingStats
    func rate(movieID: Int, rating: Int) async throws -> RatingStats
}

struct LibraryService: LibraryServicing {
    let apiClient: APIClient

    func favorites() async throws -> [Movie] {
        let request = APIRequest(method: .get, path: "/user/favorites", requiresAuthentication: true)
        let response: FavoriteMoviesEnvelope = try await apiClient.send(request)
        return response.movies
    }

    func favoriteIDs() async -> Set<Int> {
        let request = APIRequest(method: .get, path: "/user/favorite-ids", requiresAuthentication: true)
        guard let response: JSONValue = try? await apiClient.send(request) else { return [] }
        let values = response.object?["ids"]?.array ?? response.object?["movie_ids"]?.array ?? response.array ?? []
        return Set(values.compactMap { $0.intValue }.filter { $0 > 0 })
    }

    func toggleFavorite(movieID: Int, add: Bool) async throws {
        let method: HTTPMethod = add ? .post : .delete
        let request = APIRequest(method: method, path: "/user/favorites/\(movieID)", requiresAuthentication: true)
        let _: JSONValue = try await apiClient.send(request)
    }

    func playlists() async throws -> [CinePlaylist] {
        let request = APIRequest(method: .get, path: "/playlists/my", requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func createPlaylist(name: String, description: String, isPublic: Bool) async throws -> CinePlaylist {
        let body = CreatePlaylistPayload(name: name.trimmingCharacters(in: .whitespacesAndNewlines), description: description, isPublic: isPublic)
        let request = try APIRequest.json(method: .post, path: "/playlists", body: body, requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func add(movieID: Int, to playlistID: Int) async throws {
        let body = AddMoviePayload(movieID: movieID)
        let request = try APIRequest.json(method: .post, path: "/playlists/\(playlistID)/movies", body: body, requiresAuthentication: true)
        let _: JSONValue = try await apiClient.send(request)
    }

    func playlistDetail(_ playlist: CinePlaylist) async throws -> PlaylistDetail {
        let request = APIRequest(method: .get, path: "/playlists/\(playlist.id)/movies", requiresAuthentication: true)
        let response: PlaylistDetailResponse = try await apiClient.send(request)
        return PlaylistDetail(playlist: response.playlist, movies: response.movies)
    }

    func updatePlaylist(_ playlistID: Int, name: String? = nil, description: String? = nil, isPublic: Bool? = nil) async throws -> CinePlaylist {
        let body = UpdatePlaylistPayload(name: name, description: description, isPublic: isPublic)
        let request = try APIRequest.json(method: .patch, path: "/playlists/\(playlistID)", body: body, requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func remove(movieID: Int, from playlistID: Int) async throws {
        let request = APIRequest(method: .delete, path: "/playlists/\(playlistID)/movies/\(movieID)", requiresAuthentication: true)
        let _: JSONValue = try await apiClient.send(request)
    }

    func deletePlaylist(_ playlistID: Int) async throws {
        let request = APIRequest(method: .delete, path: "/playlists/\(playlistID)", requiresAuthentication: true)
        let _: JSONValue = try await apiClient.send(request)
    }

    func comments(movieID: Int) async throws -> [MovieComment] {
        try await apiClient.send(APIRequest(method: .get, path: "/movies/\(movieID)/comments"))
    }

    func addComment(movieID: Int, content: String, isSpoiler: Bool) async throws -> MovieComment {
        let request = try APIRequest.json(method: .post, path: "/movies/\(movieID)/comments", body: CommentPayload(content: content, isSpoiler: isSpoiler), requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func ratingStats(movieID: Int) async throws -> RatingStats {
        try await apiClient.send(APIRequest(method: .get, path: "/movies/\(movieID)/rating-stats"))
    }

    func rate(movieID: Int, rating: Int) async throws -> RatingStats {
        let request = try APIRequest.json(method: .post, path: "/movies/\(movieID)/rate", body: RatingPayload(rating: rating), requiresAuthentication: true)
        let _: JSONValue = try await apiClient.send(request)
        return try await ratingStats(movieID: movieID)
    }
}

private struct PlaylistDetailResponse: Decodable { let playlist: CinePlaylist; let movies: [Movie] }
private struct UpdatePlaylistPayload: Encodable {
    let name: String?; let description: String?; let isPublic: Bool?
    enum CodingKeys: String, CodingKey { case name, description, isPublic = "is_public" }
}

private struct FavoriteMoviesEnvelope: Decodable {
    let movies: [Movie]
    private enum CodingKeys: String, CodingKey { case movies, favorites }

    init(from decoder: Decoder) throws {
        if let list = try? decoder.singleValueContainer().decode([Movie].self) {
            movies = list
            return
        }
        let values = try decoder.container(keyedBy: CodingKeys.self)
        movies = (try? values.decode([Movie].self, forKey: .movies))
            ?? (try? values.decode([Movie].self, forKey: .favorites))
            ?? []
    }
}

private struct CreatePlaylistPayload: Encodable {
    let name: String
    let description: String
    let isPublic: Bool
    enum CodingKeys: String, CodingKey { case name, description, isPublic = "is_public" }
}
private struct AddMoviePayload: Encodable {
    let movieID: Int
    enum CodingKeys: String, CodingKey { case movieID = "movie_id" }
}

struct MovieComment: Decodable, Identifiable, Equatable {
    let id: Int
    let content: String
    let userName: String
    let createdAt: String
    let isSpoiler: Bool
    let avatar: String?
    let isVip: Bool
    let isAdmin: Bool

    enum CodingKeys: String, CodingKey { case id, content, userName = "user_name", createdAt = "created_at", isSpoiler = "is_spoiler" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeFlexibleInt(.id) ?? 0
        content = try c.decodeFlexibleString(.content) ?? ""
        userName = try c.decodeFlexibleString(.userName)?.nonEmpty ?? "CineViet"
        createdAt = try c.decodeFlexibleString(.createdAt) ?? ""
        isSpoiler = (try c.decodeFlexibleInt(.isSpoiler) ?? 0) == 1
        let raw = try [String: JSONValue](from: decoder)
        let nested = [raw["user"]?.object, raw["author"]?.object, raw["profile"]?.object, raw["account"]?.object].compactMap { $0 }
        func value(_ key: String) -> JSONValue? { raw[key] ?? nested.compactMap { $0[key] }.first }
        avatar = value("avatar")?.stringValue.nonEmpty
        let role = (value("role")?.stringValue ?? value("user_role")?.stringValue ?? value("type")?.stringValue ?? "").lowercased()
        isAdmin = value("is_admin")?.intValue == 1 || role == "admin" || role == "administrator"
        isVip = value("is_vip")?.intValue == 1 || (value("status")?.stringValue ?? "").lowercased() == "vip"
    }
}

struct RatingStats: Decodable, Equatable {
    let average: Double
    let total: Int
    let userRating: Int?

    enum CodingKeys: String, CodingKey { case average, rating, total, count, userRating, user_rating }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        average = try c.decodeFlexibleDouble(.average) ?? c.decodeFlexibleDouble(.rating) ?? 0
        total = try c.decodeFlexibleInt(.total) ?? c.decodeFlexibleInt(.count) ?? 0
        userRating = try c.decodeFlexibleInt(.userRating) ?? c.decodeFlexibleInt(.user_rating)
    }
}

private struct CommentPayload: Encodable { let content: String; let isSpoiler: Bool; enum CodingKeys: String, CodingKey { case content; case isSpoiler = "is_spoiler" } }
private struct RatingPayload: Encodable { let rating: Int }
