import Foundation
import UIKit
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

protocol PushNotificationServicing: AnyObject {
    func requestAuthorization() async
    func didRegister(deviceToken: Data) async
    func didReceiveMessagingToken(_ token: String) async
    func didFailToRegister(_ error: Error)
    func unregister() async
}

final class PushNotificationService: PushNotificationServicing {
    private let apiClient: APIClient
    private let defaults: UserDefaults
    private let tokenKey = "push.fcm.registration-token"

    init(apiClient: APIClient, defaults: UserDefaults = .standard) {
        self.apiClient = apiClient
        self.defaults = defaults
    }

    @MainActor
    func requestAuthorization() async {
        do {
            guard try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) else { return }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            AppTelemetry.shared.record(error: error, context: "push.authorization")
        }
    }

    func didRegister(deviceToken: Data) async {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = deviceToken
        do {
            let token = try await Messaging.messaging().token()
            await didReceiveMessagingToken(token)
        } catch {
            AppTelemetry.shared.record(error: error, context: "push.fcm-token")
        }
        #else
        // The backend stores Firebase registration tokens, not raw APNs tokens.
        // Keep APNs registration functional without uploading an unusable token
        // when FirebaseMessaging is intentionally omitted from a local build.
        AppTelemetry.shared.event("push_fcm_unavailable")
        #endif
    }

    func didReceiveMessagingToken(_ token: String) async {
        guard !token.isEmpty else { return }
        defaults.set(token, forKey: tokenKey)
        do {
            let body = PushTokenRequest(token: token, platform: "ios")
            try await apiClient.send(try APIRequest.json(method: .post, path: "/user/fcm-token", body: body, requiresAuthentication: true))
        } catch {
            AppTelemetry.shared.record(error: error, context: "push.register")
        }
    }

    func didFailToRegister(_ error: Error) {
        AppTelemetry.shared.record(error: error, context: "push.apns")
    }

    func unregister() async {
        guard let token = defaults.string(forKey: tokenKey) else { return }
        do {
            try await apiClient.send(try APIRequest.json(method: .delete, path: "/user/fcm-token", body: PushTokenRequest(token: token, platform: "ios"), requiresAuthentication: true))
            defaults.removeObject(forKey: tokenKey)
            #if canImport(FirebaseMessaging)
            try? await Messaging.messaging().deleteToken()
            #endif
        } catch {
            AppTelemetry.shared.record(error: error, context: "push.unregister")
        }
    }
}

private struct PushTokenRequest: Encodable {
    let token: String
    let platform: String
}
