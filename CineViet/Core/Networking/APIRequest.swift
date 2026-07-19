import Foundation

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest {
    let method: HTTPMethod
    let path: String
    var queryItems: [URLQueryItem] = []
    var body: Data?
    var requiresAuthentication = false

    static func json<Body: Encodable>(
        method: HTTPMethod,
        path: String,
        body: Body,
        requiresAuthentication: Bool = false
    ) throws -> APIRequest {
        var request = APIRequest(
            method: method,
            path: path,
            requiresAuthentication: requiresAuthentication
        )
        request.body = try JSONEncoder().encode(body)
        return request
    }
}
