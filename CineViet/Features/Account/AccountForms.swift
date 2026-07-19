import SwiftUI

struct EditProfileView: View {
    let user: User; @ObservedObject var model: AccountViewModel; let updateUser: (User) -> Void
    @State private var name: String; @State private var busy = false; @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    init(user: User, model: AccountViewModel, updateUser: @escaping (User) -> Void) {
        self.user = user; self.model = model; self.updateUser = updateUser; _name = State(initialValue: user.name ?? "")
    }
    var body: some View {
        Form {
            TextField("Tên hiển thị", text: $name).textContentType(.name).submitLabel(.done)
            if let error { Text(error).foregroundStyle(.red) }
            Button { Task { await save() } } label: { HStack { if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Lưu thay đổi") }.frame(maxWidth: .infinity, minHeight: 44) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
        }.navigationTitle("Chỉnh sửa hồ sơ").navigationBarTitleDisplayMode(.inline)
    }
    private func save() async {
        busy = true; error = nil; defer { busy = false }
        do { let updated = try await model.updateName(name.trimmingCharacters(in: .whitespacesAndNewlines)); updateUser(updated); dismiss() }
        catch { self.error = model.message(error, fallback: "Không cập nhật được hồ sơ.") }
    }
}

struct ChangePasswordView: View {
    @ObservedObject var model: AccountViewModel
    @State private var current = ""; @State private var next = ""; @State private var confirmation = ""; @State private var busy = false; @State private var error: String?; @State private var succeeded = false
    var body: some View {
        Form {
            SecureField("Mật khẩu hiện tại", text: $current).textContentType(.password)
            SecureField("Mật khẩu mới", text: $next).textContentType(.newPassword)
            SecureField("Nhập lại mật khẩu mới", text: $confirmation).textContentType(.newPassword)
            if let error { Text(error).foregroundStyle(.red) }
            if succeeded { Label("Đã đổi mật khẩu", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            Button { Task { await save() } } label: { HStack { if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Đổi mật khẩu") }.frame(maxWidth: .infinity, minHeight: 44) }.disabled(!valid || busy || succeeded)
        }.navigationTitle("Đổi mật khẩu").navigationBarTitleDisplayMode(.inline)
    }
    private var valid: Bool { !current.isEmpty && next.count >= 6 && next == confirmation }
    private func save() async {
        guard valid else { error = "Mật khẩu mới tối thiểu 6 ký tự và phải trùng nhau."; return }
        busy = true; error = nil; defer { busy = false }
        do { try await model.changePassword(current: current, new: next); current = ""; next = ""; confirmation = ""; succeeded = true }
        catch { self.error = model.message(error, fallback: "Không đổi được mật khẩu.") }
    }
}
