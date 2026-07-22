import SwiftUI
import GoogleSignIn

@main
struct CineVietApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            AppAppearanceRoot(container: container)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

/// Observes the one settings instance owned by AppContainer so a Picker change
/// invalidates the scene root immediately (and the persisted value is reused on relaunch).
private struct AppAppearanceRoot: View {
    let container: AppContainer
    @ObservedObject private var settings: AppSettings

    init(container: AppContainer) {
        self.container = container
        self.settings = container.settings
    }

    var body: some View {
        SessionRootView(container: container)
            .environmentObject(container)
            .environmentObject(settings)
            .preferredColorScheme(settings.appearance.colorScheme)
    }
}
