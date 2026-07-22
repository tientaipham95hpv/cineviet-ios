import Foundation

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private var refreshTask: Task<TokenPair, Error>?

    init(
        baseURL: URL = AppEnvironment.apiBaseURL,
        tokenStore: TokenStore,
        session: URLSession? = nil
    ) {
        self.baseURL = baseURL
        self.tokenStore = tokenStore
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = AppEnvironment.connectTimeout
            configuration.timeoutIntervalForResource = AppEnvironment.resourceTimeout
            self.session = URLSession(configuration: configuration)
        }
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let (data, response) = try await execute(request)
        guard !data.isEmpty else {
            throw NetworkError.invalidResponse
        }
        do {
            return try JSONDecoder.cineViet.decode(Response.self, from: data)
        } catch {
            throw NetworkError.decoding(error.localizedDescription)
        }
    }

    func send(_ request: APIRequest) async throws {
        _ = try await execute(request)
    }

    func uploadAvatar(_ data: Data, filename: String = "cineviet-avatar.jpg") async throws -> User {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8)); body.append(data); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: baseURL.appendingPathComponent("user/avatar")); request.httpMethod = HTTPMethod.post.rawValue; request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type"); request.setValue(AppEnvironment.mobileKey, forHTTPHeaderField: "X-Mobile-Key"); request.setValue("Bearer \(try tokenStore.load()?.accessToken ?? \"\")", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NetworkError.invalidResponse }
        do { return try JSONDecoder.cineViet.decode(User.self, from: data) } catch { return try JSONDecoder.cineViet.decode(CurrentUserResponse.self, from: data).user }
    }

    private func execute(
        _ request: APIRequest,
        retryingAfterRefresh: Bool = false
    ) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try makeURLRequest(request)
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }
            if http.statusCode == 401,
               shouldRefresh(for: request),
               !retryingAfterRefresh,
               try tokenStore.load()?.refreshToken?.isEmpty == false {
                _ = try await refreshAccessToken()
                return try await execute(request, retryingAfterRefresh: true)
            }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { throw NetworkError.unauthorized }
                if let envelope = try? JSONDecoder.cineViet.decode(ServerErrorEnvelope.self, from: data),
                   let message = envelope.message ?? envelope.error,
                   !message.isEmpty {
                    throw NetworkError.serverMessage(message)
                }
                throw NetworkError.httpStatus(http.statusCode)
            }
            return (data, http)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw NetworkError.transport(error.localizedDescription)
        }
    }

    private func makeURLRequest(_ request: APIRequest) throws -> URLRequest {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(request.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        ) else { throw NetworkError.invalidURL }
        if !request.queryItems.isEmpty { components.queryItems = request.queryItems }
        guard let url = components.url else { throw NetworkError.invalidURL }

        var result = URLRequest(url: url)
        result.httpMethod = request.method.rawValue
        result.httpBody = request.body
        result.setValue("application/json", forHTTPHeaderField: "Accept")
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue(AppEnvironment.userAgent, forHTTPHeaderField: "User-Agent")
        result.setValue(AppEnvironment.mobileKey, forHTTPHeaderField: "X-Mobile-Key")
        let accessToken = try tokenStore.load()?.accessToken
        if request.requiresAuthentication,
           accessToken?.isEmpty != false {
            throw NetworkError.missingToken
        }
        if let accessToken, !accessToken.isEmpty {
            // Flutter's Dio interceptor attaches the stored token to every API
            // request, including catalog requests that can also work publicly.
            result.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        return result
    }

    private func shouldRefresh(for request: APIRequest) -> Bool {
        !request.path.contains("/auth/login") && !request.path.contains("/auth/refresh")
    }

    private func refreshAccessToken() async throws -> TokenPair {
        if let refreshTask { return try await refreshTask.value }
        let task = Task<TokenPair, Error> {
            guard let stored = try tokenStore.load(),
                  let refreshToken = stored.refreshToken,
                  !refreshToken.isEmpty else { throw NetworkError.missingToken }
            let body = RefreshTokenRequest(refreshToken: refreshToken)
            let request = try APIRequest.json(method: .post, path: "/auth/refresh", body: body)
            let response: AuthResponse = try await sendWithoutRefresh(request)
            let tokens = try response.tokens(fallbackRefreshToken: refreshToken)
            try tokenStore.save(tokens)
            return tokens
        }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func sendWithoutRefresh<Response: Decodable>(_ request: APIRequest) async throws -> Response {
        let (data, response) = try await session.data(for: makeURLRequest(request))
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw NetworkError.httpStatus(http.statusCode) }
        do { return try JSONDecoder.cineViet.decode(Response.self, from: data) }
        catch { throw NetworkError.decoding(error.localizedDescription) }
    }
}

private struct ServerErrorEnvelope: Decodable {
    let message: String?
    let error: String?
}

extension JSONDecoder {
    static var cineViet: JSONDecoder {
        let decoder = JSONDecoder()
        return decoder
    }
}
