import SwiftUI

struct EditProfileView: View {
    let user: User
    @ObservedObject var model: AccountViewModel
    let updateUser: (User) -> Void
    @State private var name: String
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(user: User, model: AccountViewModel, updateUser: @escaping (User) -> Void) {
        self.user = user; self.model = model; self.updateUser = updateUser
        _name = State(initialValue: user.name ?? user.username ?? "")
    }

    var body: some View {
        Form {
            Section("Tên hiển thị") {
                TextField("Tên hiển thị", text: $name).textContentType(.name).submitLabel(.done)
                Text("Tên này sẽ xuất hiện trên hồ sơ CineViet của bạn.").font(.caption).foregroundStyle(CineVietTheme.textMuted)
            }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            Section {
                Button { Task { await save() } } label: {
                    HStack(spacing: 10) { if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Lưu thay đổi") }.frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(!canSave)
            }
        }
        .scrollContentBackground(.hidden).background(CineVietTheme.background)
        .navigationTitle("Chỉnh sửa hồ sơ").navigationBarTitleDisplayMode(.inline).hidesFloatingNavigation()
        .interactiveDismissDisabled(busy)
    }

    private var cleanedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !cleanedName.isEmpty && cleanedName != (user.name ?? user.username ?? "") && !busy }
    private func save() async {
        guard canSave else { return }
        busy = true; error = nil; defer { busy = false }
        do { let updated = try await model.updateName(cleanedName); updateUser(updated); dismiss() }
        catch { self.error = model.message(error, fallback: "Không cập nhật được hồ sơ.") }
    }
}

struct ChangePasswordView: View {
    @ObservedObject var model: AccountViewModel
    @State private var current = ""
    @State private var next = ""
    @State private var confirmation = ""
    @State private var busy = false
    @State private var error: String?
    @State private var succeeded = false

    var body: some View {
        Form {
            Section("Mật khẩu") {
                SecureField("Mật khẩu hiện tại", text: $current).textContentType(.password)
                SecureField("Mật khẩu mới", text: $next).textContentType(.newPassword)
                SecureField("Nhập lại mật khẩu mới", text: $confirmation).textContentType(.newPassword)
                Text("Mật khẩu mới cần tối thiểu 6 ký tự.").font(.caption).foregroundStyle(CineVietTheme.textMuted)
            }
            if let validationMessage { Section { Label(validationMessage, systemImage: "info.circle").foregroundStyle(.orange) } }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            if succeeded { Section { Label("Đã đổi mật khẩu thành công", systemImage: "checkmark.circle.fill").foregroundStyle(.green) } }
            Section {
                Button { Task { await save() } } label: {
                    HStack(spacing: 10) { if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Đổi mật khẩu") }.frame(maxWidth: .infinity, minHeight: 48)
                }
                .disabled(!valid || busy || succeeded)
            }
        }
        .scrollContentBackground(.hidden).background(CineVietTheme.background)
        .navigationTitle("Đổi mật khẩu").navigationBarTitleDisplayMode(.inline).hidesFloatingNavigation()
        .interactiveDismissDisabled(busy)
    }

    private var valid: Bool { !current.isEmpty && next.count >= 6 && next == confirmation }
    private var validationMessage: String? {
        guard !next.isEmpty || !confirmation.isEmpty else { return nil }
        if next.count < 6 { return "Mật khẩu mới chưa đủ 6 ký tự." }
        if next != confirmation { return "Hai mật khẩu mới chưa trùng nhau." }
        return nil
    }
    private func save() async {
        guard valid else { return }
        busy = true; error = nil; defer { busy = false }
        do { try await model.changePassword(current: current, new: next); current = ""; next = ""; confirmation = ""; succeeded = true }
        catch { self.error = model.message(error, fallback: "Không đổi được mật khẩu.") }
    }
}
