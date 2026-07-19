import SwiftUI

struct MainTabView: View {
    let user: User
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    let logout: () -> Void
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, logout: logout)
                .tag(0).tabItem { Label("Trang chủ", systemImage: selectedTab == 0 ? "house.fill" : "house") }
            SearchView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                .tag(1).tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }
            FavoritesView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService)
                .tag(2).tabItem { Label("Yêu thích", systemImage: selectedTab == 2 ? "heart.fill" : "heart") }
            PlaylistsView(libraryService: libraryService)
                .tag(3).tabItem { Label("Playlist", systemImage: selectedTab == 3 ? "rectangle.stack.fill" : "rectangle.stack") }
            AccountView(user: user, logout: logout)
                .tag(4).tabItem { Label("Tài khoản", systemImage: selectedTab == 4 ? "person.crop.circle.fill" : "person.crop.circle") }
        }
        .tint(CineVietTheme.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
            appearance.backgroundColor = UIColor(red: 7 / 255, green: 9 / 255, blue: 13 / 255, alpha: 0.78)
            appearance.shadowColor = UIColor(red: 45 / 255, green: 224 / 255, blue: 160 / 255, alpha: 0.16)
            let normal = appearance.stackedLayoutAppearance.normal
            normal.iconColor = UIColor(red: 184 / 255, green: 196 / 255, blue: 212 / 255, alpha: 0.72)
            normal.titleTextAttributes = [.foregroundColor: UIColor(red: 184 / 255, green: 196 / 255, blue: 212 / 255, alpha: 0.72), .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
            let selected = appearance.stackedLayoutAppearance.selected
            selected.iconColor = UIColor(red: 45 / 255, green: 224 / 255, blue: 160 / 255, alpha: 1)
            selected.titleTextAttributes = [.foregroundColor: UIColor(red: 45 / 255, green: 224 / 255, blue: 160 / 255, alpha: 1), .font: UIFont.systemFont(ofSize: 10, weight: .bold)]
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
            UITabBar.appearance().isTranslucent = true
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
