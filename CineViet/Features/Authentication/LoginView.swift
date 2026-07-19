import SwiftUI

struct LoginView: View {
    @ObservedObject var viewModel: AuthenticationViewModel
    @FocusState private var focusedField: Field?

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
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.vertical, 48)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("CineViet")
                .font(.system(size: 38, weight: .black, design: .rounded))
                .foregroundStyle(CineVietTheme.accent)
            Text("Đăng nhập để tiếp tục xem phim")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.78))
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
        }
    }

    private func submit() {
        focusedField = nil
        Task { await viewModel.login() }
    }
}

private struct CineVietTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}
