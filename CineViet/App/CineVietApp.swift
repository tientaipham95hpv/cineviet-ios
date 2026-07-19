import SwiftUI

@main
struct CineVietApp: App {
    private let container = AppContainer.live

    var body: some Scene {
        WindowGroup {
            SessionRootView(container: container)
                .environmentObject(container)
                .environmentObject(container.settings)
                .preferredColorScheme(container.settings.isDarkMode ? .dark : .light)
        }
    }
}
