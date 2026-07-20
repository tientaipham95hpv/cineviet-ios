import Foundation

protocol NotificationServicing {
    func notifications(limit: Int) async throws -> UserNotificationsResponse
    func markAllRead() async throws
    func settings() async throws -> NotificationSettings
    func updateSettings(_ update: NotificationSettingUpdate) async throws -> NotificationSettings
}

final class NotificationService: NotificationServicing {
    private let apiClient: APIClient

    init(apiClient: APIClient) { self.apiClient = apiClient }

    func notifications(limit: Int = 30) async throws -> UserNotificationsResponse {
        var request = APIRequest(method: .get, path: "/user/notifications", requiresAuthentication: true)
        request.queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 30)))]
        return try await apiClient.send(request)
    }

    func markAllRead() async throws {
        try await apiClient.send(APIRequest(method: .post, path: "/user/notifications/read", requiresAuthentication: true))
    }

    func settings() async throws -> NotificationSettings {
        try await apiClient.send(APIRequest(method: .get, path: "/user/notification-settings", requiresAuthentication: true))
    }

    func updateSettings(_ update: NotificationSettingUpdate) async throws -> NotificationSettings {
        let request = try APIRequest.json(method: .patch, path: "/user/notification-settings", body: update, requiresAuthentication: true)
        return try await apiClient.send(request)
    }
}
