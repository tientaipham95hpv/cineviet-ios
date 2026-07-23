import Combine
import Foundation
import GoogleSignIn

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
    @Published var name = ""
    @Published var resetToken = ""
    @Published var resetCode = ""
    @Published var confirmation = ""
    @Published var successMessage: String?
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    private let authenticationService: AuthenticationServicing
    private let tokenStore: TokenStore
    private weak var pushNotificationService: PushNotificationServicing?

    init(
        authenticationService: AuthenticationServicing,
        tokenStore: TokenStore,
        pushNotificationService: PushNotificationServicing? = nil
    ) {
        self.authenticationService = authenticationService
        self.tokenStore = tokenStore
        self.pushNotificationService = pushNotificationService
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
                try? await authenticationService.logout()
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

    func register() async {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, canSubmit, password == confirmation else {
            errorMessage = password != confirmation ? "Mật khẩu xác nhận chưa khớp." : "Vui lòng nhập đầy đủ thông tin."
            return
        }
        isSubmitting = true; errorMessage = nil; defer { isSubmitting = false }
        do {
            _ = try await authenticationService.register(name: name.trimmed, email: email.trimmed, password: password)
            sessionState = .signedIn(try await authenticationService.currentUser())
        } catch { errorMessage = userFacingMessage(for: error) }
    }

    func requestPasswordReset() async {
        guard !email.trimmed.isEmpty else { errorMessage = "Vui lòng nhập email."; return }
        isSubmitting = true; errorMessage = nil; defer { isSubmitting = false }
        do { try await authenticationService.forgotPassword(email: email.trimmed); successMessage = "Nếu email tồn tại, hướng dẫn khôi phục đã được gửi." }
        catch { errorMessage = userFacingMessage(for: error) }
    }

    func resetPassword() async {
        guard !resetToken.trimmed.isEmpty,
              resetCode.filter(\.isNumber).count == 6,
              password.count >= 6,
              password == confirmation else {
            errorMessage = "Kiểm tra liên kết đặt lại, mã 6 số và mật khẩu."
            return
        }
        isSubmitting = true; errorMessage = nil; defer { isSubmitting = false }
        do {
            _ = try await authenticationService.resetPassword(
                token: resetToken.trimmed,
                code: String(resetCode.filter(\.isNumber).prefix(6)),
                password: password
            )
            sessionState = .signedIn(try await authenticationService.currentUser())
            successMessage = "Đổi mật khẩu thành công."
        } catch { errorMessage = userFacingMessage(for: error) }
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

    func reportGoogleLoginError(_ message: String) {
        errorMessage = message
    }

    func logout() {
        Task {
            do {
                await pushNotificationService?.unregister()
                try await authenticationService.logout()
                GIDSignIn.sharedInstance.signOut()
                email = ""
                password = ""
                errorMessage = nil
                sessionState = .signedOut
            } catch {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    func updateUser(_ user: User) {
        sessionState = .signedIn(user)
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

private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
