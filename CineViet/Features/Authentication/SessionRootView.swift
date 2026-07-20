import SwiftUI

struct SessionRootView: View {
    @StateObject private var viewModel: AuthenticationViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(
            wrappedValue: AuthenticationViewModel(
                authenticationService: container.authenticationService,
                tokenStore: container.tokenStore
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.sessionState {
            case .restoring:
                ProgressView("Đang khôi phục phiên đăng nhập…")
                    .tint(CineVietTheme.accent)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            case .signedOut:
                LoginView(viewModel: viewModel)
            case .signedIn(let user):
                MainTabView(
                    user: user,
                    movieService: container.movieService,
                    watchHistoryService: container.watchHistoryService,
                    libraryService: container.libraryService,
                    authenticationService: container.authenticationService,
                    notificationService: container.notificationService,
                    watchTogetherService: container.watchTogetherService,
                    updateUser: viewModel.updateUser,
                    logout: viewModel.logout
                )
            }
        }
        .task { await viewModel.restoreSession() }
    }
}
