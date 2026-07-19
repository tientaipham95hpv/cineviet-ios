import Foundation

protocol AuthenticationServicing {
    func login(email: String, password: String) async throws -> AuthResponse
    func loginWithGoogle(idToken: String) async throws -> AuthResponse
    func currentUser() async throws -> User
    func refreshSession() async throws -> AuthResponse
    func updateProfile(name: String) async throws -> User
    func changePassword(current: String, new: String) async throws
    func membershipSummary() async throws -> MembershipSummary
    func logout() throws
}

final class AuthenticationService: AuthenticationServicing {
    private let apiClient: APIClient
    private let tokenStore: TokenStore

    init(apiClient: APIClient, tokenStore: TokenStore) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password, mobileKey: AppEnvironment.mobileKey)
        let request = try APIRequest.json(method: .post, path: "/auth/login", body: body)
        let response: AuthResponse = try await apiClient.send(request)
        try tokenStore.save(try response.tokens())
        return response
    }

    func loginWithGoogle(idToken: String) async throws -> AuthResponse {
        let body = GoogleLoginRequest(idToken: idToken, remember: true)
        let request = try APIRequest.json(method: .post, path: "/auth/google/mobile", body: body)
        let response: AuthResponse = try await apiClient.send(request)
        try tokenStore.save(try response.tokens())
        return response
    }

    func currentUser() async throws -> User {
        let request = APIRequest(method: .get, path: "/auth/me", requiresAuthentication: true)
        let response: CurrentUserResponse = try await apiClient.send(request)
        return response.user
    }

    func refreshSession() async throws -> AuthResponse {
        guard let tokens = try tokenStore.load(),
              let refreshToken = tokens.refreshToken,
              !refreshToken.isEmpty else { throw NetworkError.missingToken }
        let request = try APIRequest.json(
            method: .post,
            path: "/auth/refresh",
            body: RefreshTokenRequest(refreshToken: refreshToken)
        )
        let response: AuthResponse = try await apiClient.send(request)
        try tokenStore.save(try response.tokens(fallbackRefreshToken: refreshToken))
        return response
    }

    func updateProfile(name: String) async throws -> User {
        let request = try APIRequest.json(method: .patch, path: "/user/profile", body: ProfileUpdateRequest(name: name), requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func changePassword(current: String, new: String) async throws {
        let request = try APIRequest.json(method: .post, path: "/user/change-password", body: ChangePasswordRequest(currentPassword: current, newPassword: new), requiresAuthentication: true)
        try await apiClient.send(request)
    }

    func membershipSummary() async throws -> MembershipSummary {
        let request = APIRequest(method: .get, path: "/donations/me", requiresAuthentication: true)
        return try await apiClient.send(request)
    }

    func logout() throws {
        try tokenStore.clear()
    }
}
