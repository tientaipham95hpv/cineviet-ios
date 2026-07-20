import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationMask: UIInterfaceOrientationMask = .portrait

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationMask
    }

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String, completionHandler: @escaping () -> Void) {
        guard identifier == OfflineDownloadManager.backgroundIdentifier else { completionHandler(); return }
        Task { @MainActor in OfflineDownloadManager.shared.handleBackgroundEvents(completionHandler: completionHandler) }
    }
}

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
