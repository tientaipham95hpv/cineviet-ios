import Foundation

protocol AuthenticationServicing {
    func login(email: String, password: String) async throws -> AuthResponse
    func loginWithGoogle(idToken: String) async throws -> AuthResponse
    func currentUser() async throws -> User
    func refreshSession() async throws -> AuthResponse
    func updateProfile(name: String) async throws -> User
    func changePassword(current: String, new: String) async throws
    func membershipSummary() async throws -> MembershipSummary
    func requireOfflineDownloadAccess() async throws
    func confirmTV(code: String) async throws
    func logout() async throws
}

final class AuthenticationService: AuthenticationServicing {
    private let apiClient: APIClient
    private let tokenStore: TokenStore
    private let defaults: UserDefaults
    private static let cachedUserKey = "auth.cached-user.offline"
    private static let vipOnlyKey = "cineviet_offline_download_vip_only"

    init(apiClient: APIClient, tokenStore: TokenStore, defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.tokenStore = tokenStore
        self.defaults = defaults
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password, mobileKey: AppEnvironment.mobileKey)
        let request = try APIRequest.json(method: .post, path: "/auth/login", body: body)
        let response: AuthResponse = try await apiClient.send(request)
        try tokenStore.save(try response.tokens())
        if let user = response.user { cacheOfflineIdentity(user) }
        return response
    }

    func loginWithGoogle(idToken: String) async throws -> AuthResponse {
        let body = GoogleLoginRequest(idToken: idToken, remember: true)
        let request = try APIRequest.json(method: .post, path: "/auth/google/mobile", body: body)
        let response: AuthResponse = try await apiClient.send(request)
        try tokenStore.save(try response.tokens())
        if let user = response.user { cacheOfflineIdentity(user) }
        return response
    }

    func currentUser() async throws -> User {
        let request = APIRequest(method: .get, path: "/auth/me", requiresAuthentication: true)
        let response: CurrentUserResponse = try await apiClient.send(request)
        cacheOfflineIdentity(response.user)
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

    func requireOfflineDownloadAccess() async throws {
        guard let tokens = try tokenStore.load(), !tokens.accessToken.isEmpty || tokens.refreshToken?.isEmpty == false else { throw OfflineAccessError.loginRequired }
        guard await offlineDownloadVipOnly() else { return }
        let identity: OfflineIdentity
        do { identity = OfflineIdentity(user: try await currentUser()) }
        catch {
            guard let data = defaults.data(forKey: Self.cachedUserKey), let cached = try? JSONDecoder().decode(OfflineIdentity.self, from: data) else { throw OfflineAccessError.cannotVerify }
            identity = cached
        }
        guard identity.isVip || identity.isAdmin else { throw OfflineAccessError.vipRequired }
    }

    func confirmTV(code: String) async throws {
        let body = TVConfirmRequest(code: code.filter(\.isNumber))
        let request = try APIRequest.json(method: .post, path: "/auth/tv/confirm", body: body, requiresAuthentication: true)
        try await apiClient.send(request)
    }

    func logout() async throws {
        let refreshToken = try? tokenStore.load()?.refreshToken
        if let refreshToken, !refreshToken.isEmpty {
            let body = RefreshTokenRequest(refreshToken: refreshToken)
            if let request = try? APIRequest.json(method: .post, path: "/auth/logout", body: body) {
                // Server revocation is best effort. Local credentials must always
                // be removed so logout also works without connectivity.
                try? await apiClient.send(request)
            }
        }
        try tokenStore.clear()
        defaults.removeObject(forKey: Self.cachedUserKey)
    }

    private func offlineDownloadVipOnly() async -> Bool {
        do {
            let settings: OfflineDownloadSettings = try await apiClient.send(APIRequest(method: .get, path: "/settings"))
            let value = settings.offlineDownloadVipOnly.value
            defaults.set(value, forKey: Self.vipOnlyKey)
            return value
        } catch {
            return defaults.object(forKey: Self.vipOnlyKey) as? Bool ?? true
        }
    }

    private func cacheOfflineIdentity(_ user: User) {
        if let data = try? JSONEncoder().encode(OfflineIdentity(user: user)) { defaults.set(data, forKey: Self.cachedUserKey) }
    }
}

private struct TVConfirmRequest: Encodable { let code: String }

private struct OfflineDownloadSettings: Decodable {
    let offlineDownloadVipOnly: LossyBoolean
    enum CodingKeys: String, CodingKey { case offlineDownloadVipOnly = "offline_download_vip_only" }
}

private enum LossyBoolean: Decodable {
    case enabled, disabled
    var value: Bool {
        switch self {
        case .enabled: return true
        case .disabled: return false
        }
    }
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = value ? .enabled : .disabled; return }
        if let value = try? container.decode(Int.self) { self = value == 0 ? .disabled : .enabled; return }
        let value = (try? container.decode(String.self))?.trimmingCharacters(in: .whitespacesAndNewlines)
        self = value == "0" ? .disabled : .enabled
    }
}

private struct OfflineIdentity: Codable {
    let isVip: Bool
    let isAdmin: Bool
    init(user: User) { let role = (user.role ?? user.userRole ?? user.type)?.lowercased(); isVip = user.isVip; isAdmin = role == "admin" || role == "administrator" }
}

enum OfflineAccessError: LocalizedError {
    case loginRequired, vipRequired, cannotVerify
    var errorDescription: String? { switch self { case .loginRequired: "Vui lòng đăng nhập để tải xuống"; case .vipRequired: "Tải xuống cần tài khoản VIP hoặc Administrator"; case .cannotVerify: "Không thể xác minh quyền tải xuống khi ngoại tuyến" } }
}
