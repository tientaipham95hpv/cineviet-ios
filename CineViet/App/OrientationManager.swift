import SwiftUI
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
#endif
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        #if canImport(FirebaseCore) && canImport(FirebaseMessaging)
        if FirebaseApp.app() == nil, Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }
        #endif
        if let payload = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            Task { @MainActor in AppContainer.live.deepLinkRouter.handle(userInfo: payload) }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await AppContainer.live.pushNotificationService.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        AppContainer.live.pushNotificationService.didFailToRegister(error)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .badge] }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await AppContainer.live.deepLinkRouter.handle(userInfo: response.notification.request.content.userInfo)
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == OfflineDownloadManager.backgroundIdentifier else { completionHandler(); return }
        Task { @MainActor in OfflineDownloadManager.shared.handleBackgroundEvents(completionHandler: completionHandler) }
    }
}

#if canImport(FirebaseMessaging)
extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { await AppContainer.live.pushNotificationService.didReceiveMessagingToken(fcmToken) }
    }
}
#endif

@MainActor
enum OrientationManager {
    static func landscape() {
        AppDelegate.orientationMask = .landscape
        rotate(to: .landscapeRight, mask: .landscape)
    }

    static func portrait() {
        AppDelegate.orientationMask = .portrait
        rotate(to: .portrait, mask: .portrait)
    }

    private static func rotate(to orientation: UIInterfaceOrientation, mask: UIInterfaceOrientationMask) {
        if #available(iOS 16.0, *) {
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            scene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
            scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
        UIDevice.current.setValue(orientation.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
