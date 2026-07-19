import SwiftUI

struct MainTabView: View {
    let user: User
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    let logout: () -> Void

    var body: some View {
        TabView {
            HomeView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, logout: logout)
                .tabItem { Label("Trang chủ", systemImage: "house.fill") }
            SearchView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }
            FavoritesView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                .tabItem { Label("Yêu thích", systemImage: "heart.fill") }
            PlaylistsView(libraryService: libraryService)
                .tabItem { Label("Playlist", systemImage: "rectangle.stack.fill") }
            AccountView(user: user, logout: logout)
                .tabItem { Label("Tài khoản", systemImage: "person.crop.circle.fill") }
        }
        .tint(CineVietTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            appearance.backgroundColor = UIColor.black.withAlphaComponent(0.24)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}

struct AccountView: View {
    let user: User
    let logout: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Tài khoản") {
                    LabeledContent("Tên", value: user.name ?? user.username ?? "CineViet")
                    if let email = user.email { LabeledContent("Email", value: email) }
                    LabeledContent("Hạng", value: user.isVip ? "VIP" : "Thành viên")
                    if let expires = user.vipExpiresAt { LabeledContent("VIP đến", value: expires) }
                }
                Button("Đăng xuất", role: .destructive, action: logout)
            }
            .scrollContentBackground(.hidden)
            .background(CineVietTheme.background.ignoresSafeArea())
            .navigationTitle("Tài khoản")
        }
    }
}
