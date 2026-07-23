import SwiftUI
import GoogleSignIn
import UIKit

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: Field?
    @State private var authSheet: AuthSheet?

    fileprivate enum AuthSheet: String, Identifiable { case register, forgot; var id: String { rawValue } }

    enum Field {
        case email
        case password
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header
                form
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("authentication-error")
                }
                if let success = viewModel.successMessage { Text(success).foregroundStyle(.green).accessibilityIdentifier("authentication-success") }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(CineVietTheme.background.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $authSheet) { mode in AuthFlowSheet(mode: mode, viewModel: viewModel) }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("CineViet")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(CineVietTheme.accent)
            Text("Đăng nhập để tiếp tục xem phim")
                .font(.headline)
                .foregroundStyle(CineVietTheme.textMuted)
        }
    }

    private var form: some View {
        VStack(spacing: 14) {
            TextField("Email", text: $viewModel.email)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .email)
                .submitLabel(.next)
                .onSubmit { focusedField = .password }
                .textFieldStyle(CineVietTextFieldStyle())
                .accessibilityIdentifier("login-email")

            SecureField("Mật khẩu", text: $viewModel.password)
                .textContentType(.password)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .textFieldStyle(CineVietTextFieldStyle())
                .accessibilityIdentifier("login-password")

            Button(action: submit) {
                Group {
                    if viewModel.isSubmitting {
                        ProgressView().tint(.black)
                    } else {
                        Text("Đăng nhập")
                    }
                }
                .font(.headline.weight(.bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
            }
            .foregroundStyle(.black)
            .background(CineVietTheme.accent, in: RoundedRectangle(cornerRadius: 12))
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.55)
            .accessibilityIdentifier("login-submit")

            HStack {
                Button("Quên mật khẩu?") { authSheet = .forgot }
                Spacer()
                Button("Tạo tài khoản") { authSheet = .register }
            }.font(.subheadline.weight(.semibold))

            HStack(spacing: 12) {
                Rectangle().fill(CineVietTheme.border).frame(height: 1)
                Text("HOẶC").font(.caption.weight(.semibold)).foregroundStyle(CineVietTheme.textMuted)
                Rectangle().fill(CineVietTheme.border).frame(height: 1)
            }
            .padding(.vertical, 4)

            Button(action: signInWithGoogle) {
                HStack(spacing: 10) {
                    Image(systemName: "g.circle.fill")
                        .font(.title3)
                    Text("Tiếp tục với Google")
                        .font(.headline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .foregroundStyle(.primary)
            .background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(CineVietTheme.border, lineWidth: 0.8) }
            .disabled(viewModel.isSubmitting)
            .opacity(viewModel.isSubmitting ? 0.55 : 1)
            .accessibilityIdentifier("login-google")
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.login() }
    }

    private func signInWithGoogle() {
        focusedField = nil
        guard let presenter = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController else {
            viewModel.reportGoogleLoginError("Không thể mở đăng nhập Google.")
            return
        }

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: AppEnvironment.googleClientID,
            serverClientID: AppEnvironment.googleServerClientID
        )
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { result, error in
            if error != nil {
                // Cancellation is intentionally silent; Google reports it as an NSError.
                return
            }
            guard let idToken = result?.user.idToken?.tokenString, !idToken.isEmpty else {
                viewModel.reportGoogleLoginError("Không nhận được mã xác thực từ Google.")
                return
            }
            Task { await viewModel.completeGoogleLogin(idToken: idToken) }
        }
    }
}

private struct AuthFlowSheet: View {
    let mode: LoginView.AuthSheet
    @ObservedObject var viewModel: AuthenticationViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showReset = false
    var body: some View {
        NavigationStack { Form {
            if mode == .register { TextField("Họ tên", text: $viewModel.name).textContentType(.name) }
            TextField("Email", text: $viewModel.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
            if mode == .register || showReset {
                if showReset {
                    TextField("Token trong liên kết email", text: $viewModel.resetToken)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Mã xác nhận 6 số", text: $viewModel.resetCode)
                        .keyboardType(.numberPad)
                }
                SecureField("Mật khẩu mới", text: $viewModel.password)
                SecureField("Xác nhận mật khẩu", text: $viewModel.confirmation)
            }
            Button(mode == .register ? "Đăng ký" : (showReset ? "Đặt lại mật khẩu" : "Gửi hướng dẫn")) {
                Task {
                    if mode == .register { await viewModel.register() }
                    else if showReset { await viewModel.resetPassword() }
                    else { await viewModel.requestPasswordReset() }
                }
            }.disabled(viewModel.isSubmitting)
            if mode == .forgot { Toggle("Tôi đã có mã xác nhận", isOn: $showReset) }
            if let message = viewModel.errorMessage { Text(message).foregroundStyle(.red) }
            if let message = viewModel.successMessage { Text(message).foregroundStyle(.green) }
        }.navigationTitle(mode == .register ? "Tạo tài khoản" : "Khôi phục mật khẩu").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } } }
    }
}

private struct CineVietTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .foregroundStyle(.primary)
            .background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(CineVietTheme.border, lineWidth: 0.8)
            }
    }
}
