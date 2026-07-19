import Combine
import Foundation

@MainActor
final class AuthenticationViewModel: ObservableObject {
    enum SessionState: Equatable {
        case restoring
        case signedOut
        case signedIn(User)
    }

    @Published private(set) var sessionState: SessionState = .restoring
    @Published var email = ""
    @Published var password = ""
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let authenticationService: AuthenticationServicing
    private let tokenStore: TokenStore

    init(
        authenticationService: AuthenticationServicing,
        tokenStore: TokenStore
    ) {
        self.authenticationService = authenticationService
        self.tokenStore = tokenStore
    }

    var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
            && !isSubmitting
    }

    func restoreSession() async {
        sessionState = .restoring
        errorMessage = nil
        do {
            guard try tokenStore.load() != nil else {
                sessionState = .signedOut
                return
            }
            let user = try await authenticationService.currentUser()
            sessionState = .signedIn(user)
        } catch {
            // A stored refresh token may still be valid even when the access
            // token is absent or expired. Refresh once before signing out.
            do {
                _ = try await authenticationService.refreshSession()
                let user = try await authenticationService.currentUser()
                sessionState = .signedIn(user)
            } catch {
                try? authenticationService.logout()
                sessionState = .signedOut
            }
        }
    }

    func login() async {
        guard canSubmit else {
            if email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                errorMessage = "Vui lòng nhập email."
            } else if password.isEmpty {
                errorMessage = "Vui lòng nhập mật khẩu."
            }
            return
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await authenticationService.login(
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                password: password
            )
            let user = try await authenticationService.currentUser()
            password = ""
            sessionState = .signedIn(user)
        } catch {
            errorMessage = userFacingMessage(for: error)
            sessionState = .signedOut
        }
    }

    func completeGoogleLogin(idToken: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            _ = try await authenticationService.loginWithGoogle(idToken: idToken)
            let user = try await authenticationService.currentUser()
            sessionState = .signedIn(user)
        } catch {
            errorMessage = userFacingMessage(for: error)
            sessionState = .signedOut
        }
    }

    func logout() {
        do {
            try authenticationService.logout()
            email = ""
            password = ""
            errorMessage = nil
            sessionState = .signedOut
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func userFacingMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let message = localized.errorDescription,
           !message.isEmpty {
            return message
        }
        return "Đăng nhập chưa thành công. Vui lòng thử lại."
    }
}
