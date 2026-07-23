import SwiftUI

struct SessionRootView: View {
    @StateObject private var viewModel: AuthenticationViewModel
    private let container: AppContainer

    init(container: AppContainer) {
        self.container = container
        _viewModel = StateObject(
            wrappedValue: AuthenticationViewModel(
                authenticationService: container.authenticationService,
                tokenStore: container.tokenStore,
                pushNotificationService: container.pushNotificationService
            )
        )
    }

    var body: some View {
        Group {
            switch viewModel.sessionState {
            case .restoring:
                CineVietLoadingView()
            case .signedOut:
                LoginView(viewModel: viewModel)
            case .signedIn(let user):
                MainTabView(
                    user: user,
                    deepLinkRouter: container.deepLinkRouter,
                    movieService: container.movieService,
                    watchHistoryService: container.watchHistoryService,
                    libraryService: container.libraryService,
                    authenticationService: container.authenticationService,
                    notificationService: container.notificationService,
                    watchTogetherService: container.watchTogetherService,
                    updateUser: viewModel.updateUser,
                    logout: viewModel.logout
                )
                .onAppear { container.currentUser = user }
                .task { await container.pushNotificationService.requestAuthorization() }
                .onChange(of: user) { container.currentUser = $0 }
            }
        }
        .task { await viewModel.restoreSession() }
    }
}

private struct CineVietLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                cinematicBackdrop(size: proxy.size)

                VStack(spacing: 0) {
                    Spacer(minLength: proxy.size.height * 0.36)
                    brandLockup
                    Spacer()
                    loadingState
                        .padding(.bottom, max(proxy.safeAreaInsets.bottom + 48, proxy.size.height * 0.12))
                }
                .padding(.horizontal, 28)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background(Color.black)
            .ignoresSafeArea()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CineViet")
        .accessibilityValue("Đang tải")
        .onAppear { isAnimating = true }
    }

    private func cinematicBackdrop(size: CGSize) -> some View {
        ZStack {
            Color(red: 3 / 255, green: 9 / 255, blue: 8 / 255)

            // Abstract film frames keep startup local, fast and independent of licensed artwork.
            filmFrame(width: size.width * 0.82, height: size.height * 0.29, rotation: -8)
                .offset(x: -size.width * 0.18, y: -size.height * 0.30)
            filmFrame(width: size.width * 0.78, height: size.height * 0.25, rotation: 7)
                .offset(x: size.width * 0.23, y: -size.height * 0.08)
            filmFrame(width: size.width * 0.72, height: size.height * 0.24, rotation: -5)
                .offset(x: -size.width * 0.24, y: size.height * 0.18)

            RadialGradient(
                colors: [CineVietTheme.accent.opacity(0.18), .clear],
                center: .init(x: 0.54, y: 0.46),
                startRadius: 8,
                endRadius: max(size.width, size.height) * 0.52
            )
            LinearGradient(
                colors: [.black.opacity(0.20), .black.opacity(0.50), .black.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.38)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }

    private func filmFrame(width: CGFloat, height: CGFloat, rotation: Double) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        CineVietTheme.accentDeep.opacity(0.28),
                        Color(red: 14 / 255, green: 32 / 255, blue: 31 / 255),
                        Color.black.opacity(0.88)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.62), radius: 28, y: 16)
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
    }

    private var brandLockup: some View {
        Image("CineVietBrand")
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 330)
            .accessibilityHidden(true)
            .shadow(color: CineVietTheme.accent.opacity(0.18), radius: 22)
            .shadow(color: .black.opacity(0.72), radius: 14, y: 6)
    }

    private var loadingState: some View {
        VStack(spacing: 15) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 3)
                Circle()
                    .trim(from: 0.04, to: 0.72)
                    .stroke(CineVietTheme.accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (isAnimating ? 360 : 0)))
                    .animation(
                        reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            .frame(width: 42, height: 42)

            Text("Đang tải…")
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}
