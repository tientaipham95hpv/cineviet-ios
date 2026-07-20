import SwiftUI

@main
struct CineVietApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            SessionRootView(container: container)
                .environmentObject(container)
                .environmentObject(container.settings)
                .preferredColorScheme(container.settings.appearance.colorScheme)
        }
    }
}
