import SwiftUI

struct MainTabView: View {
    let user: User
    let movieService: MovieServicing
    let watchHistoryService: WatchHistoryServicing
    let libraryService: LibraryServicing
    let authenticationService: AuthenticationServicing
    let updateUser: (User) -> Void
    let logout: () -> Void
    @State private var selectedTab = 0
    @State private var hidesFloatingNavigation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService, logout: logout).tag(0)
            SearchView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService).tag(1)
            PlaylistsView(libraryService: libraryService).tag(2)
            AccountView(user: user, service: authenticationService, updateUser: updateUser, logout: logout).tag(3)
            FavoritesView(movieService: movieService, watchHistoryService: watchHistoryService, libraryService: libraryService).tag(4)
        }
        .toolbar(.hidden, for: .tabBar)
        // The floating bar is visual chrome, not layout content. Using a
        // safeAreaInset here left its reserved region behind while a pushed
        // detail screen hid the bar, producing a blank strip on that screen.
        .overlay(alignment: .bottom) {
            if !hidesFloatingNavigation {
                floatingNavigation
                    .allowsHitTesting(true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onPreferenceChange(FloatingNavigationHiddenKey.self) { hidden in
            setFloatingNavigationHidden(hidden)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cineVietPlayerDidAppear)) { _ in
            setFloatingNavigationHidden(true, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: .cineVietPlayerDidDisappear)) { _ in
            setFloatingNavigationHidden(false)
        }
        .tint(CineVietTheme.accent)
    }

    private func setFloatingNavigationHidden(_ hidden: Bool, animated: Bool = true) {
        guard hidesFloatingNavigation != hidden else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.18)) { hidesFloatingNavigation = hidden }
        } else {
            hidesFloatingNavigation = hidden
        }
    }

    private var floatingNavigation: some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                navItem(0, "house.fill", "Trang chủ")
                navItem(1, "magnifyingglass", "Tìm kiếm")
                navItem(2, "rectangle.stack.fill", "Playlist")
                navItem(3, "person.fill", "Tài khoản")
            }
            .padding(7)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Capsule().fill(CineVietTheme.panel.opacity(0.82)))
            .overlay { Capsule().stroke(CineVietTheme.border.opacity(0.8), lineWidth: 1) }
            .shadow(color: .black.opacity(0.46), radius: 22, y: 10)

            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { selectedTab = 4 } } label: {
                Image(systemName: selectedTab == 4 ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(selectedTab == 4 ? .black : .primary)
                    .frame(width: 54, height: 54)
                    .background(selectedTab == 4 ? CineVietTheme.accent : CineVietTheme.panel.opacity(0.88), in: Circle())
                    .overlay { Circle().stroke(selectedTab == 4 ? CineVietTheme.accent.opacity(0.85) : CineVietTheme.border, lineWidth: 1.5) }
                    .shadow(color: (selectedTab == 4 ? CineVietTheme.accent : .black).opacity(0.4), radius: 16, y: 7)
            }
            .accessibilityLabel("Yêu thích")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 5)
    }

    private func navItem(_ index: Int, _ icon: String, _ label: String) -> some View {
        Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { selectedTab = index } } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 19, weight: .semibold))
                if selectedTab == index { Text(label).font(.system(size: 9, weight: .bold)).lineLimit(1) }
            }
            .foregroundStyle(selectedTab == index ? .black : CineVietTheme.textMuted)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(selectedTab == index ? CineVietTheme.accent : .clear, in: Capsule())
        }
        .accessibilityLabel(label)
    }
}

struct FloatingNavigationHiddenKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

extension View {
    func hidesFloatingNavigation(_ hidden: Bool = true) -> some View { preference(key: FloatingNavigationHiddenKey.self, value: hidden) }
}

extension Notification.Name {
    static let cineVietPlayerDidAppear = Notification.Name("cineviet.player.didAppear")
    static let cineVietPlayerDidDisappear = Notification.Name("cineviet.player.didDisappear")
}
