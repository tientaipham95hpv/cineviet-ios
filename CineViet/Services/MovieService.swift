import Foundation

protocol MovieServicing {
    func list(_ query: MovieListQuery) async throws -> MovieListResponse
    func detail(idOrSlug: String) async throws -> Movie
}

struct MovieListQuery {
    var page: Int = 1
    var limit: Int = 24
    var search = ""
    var type = ""
    var genre = ""
    var country = ""
    var year = ""
    var sort = "created_at"
    var featured = ""
    var cinema = ""
    var bilingual = ""

    var queryItems: [URLQueryItem] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "sort", value: sort),
            URLQueryItem(name: "order", value: "desc")
        ]
        let optional: [(String, String)] = [
            ("search", search), ("type", type), ("genre", genre),
            ("country", country), ("release_year", year), ("featured", featured),
            ("chieu_rap", cinema), ("song_ngu", bilingual)
        ]
        items.append(contentsOf: optional.compactMap { key, value in
            value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : URLQueryItem(name: key, value: value)
        })
        return items
    }
}

struct MovieListResponse: Decodable {
    let movies: [Movie]

    private enum CodingKeys: String, CodingKey { case movies }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var rows = try container.nestedUnkeyedContainer(forKey: .movies)
        var decoded: [Movie] = []
        while !rows.isAtEnd {
            if let movie = try? rows.decode(Movie.self) {
                decoded.append(movie)
            } else {
                _ = try? rows.decode(JSONValue.self)
            }
        }
        movies = decoded
    }
}

final class MovieService: MovieServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    func list(_ query: MovieListQuery = MovieListQuery()) async throws -> MovieListResponse {
        let request = APIRequest(method: .get, path: "/movies", queryItems: query.queryItems)
        return try await apiClient.send(request)
    }

    func detail(idOrSlug: String) async throws -> Movie {
        let request = APIRequest(method: .get, path: "/movies/\(idOrSlug)")
        return try await apiClient.send(request)
    }
}
