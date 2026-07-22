import PhotosUI
import SwiftUI

struct EditProfileView: View {
    let user: User
    @ObservedObject var model: AccountViewModel
    let updateUser: (User) -> Void
    @State private var name: String
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var avatarData: Data?
    @State private var removeAvatar = false
    @State private var busy = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(user: User, model: AccountViewModel, updateUser: @escaping (User) -> Void) { self.user = user; self.model = model; self.updateUser = updateUser; _name = State(initialValue: user.name ?? user.username ?? "") }

    var body: some View {
        Form {
            Section {
                UserAvatar(name: name.isEmpty ? "CineViet" : name, url: removeAvatar ? nil : URL(string: user.avatar ?? ""), isVIP: user.isVip, size: 92)
                    .frame(maxWidth: .infinity)
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Chọn ảnh đại diện", systemImage: "photo.on.rectangle") }.frame(maxWidth: .infinity)
                if user.avatar?.isEmpty == false { Button("Xoá ảnh đại diện", role: .destructive) { removeAvatar = true; avatarData = nil } }
            }
            Section("Tên hiển thị") { TextField("Tên hiển thị", text: $name).textContentType(.name); Text("Ảnh sẽ được gửi dạng JPEG tối ưu.").font(.caption).foregroundStyle(CineVietTheme.textMuted) }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            Section { Button { Task { await save() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Lưu thay đổi").bold(); Spacer() } }.disabled(!canSave) }
        }
        .scrollContentBackground(.hidden).background(CineVietTheme.background).navigationTitle("Chỉnh sửa hồ sơ").navigationBarTitleDisplayMode(.inline).task(id: selectedPhoto) { if let selectedPhoto { avatarData = try? await selectedPhoto.loadTransferable(type: Data.self); removeAvatar = false } }
    }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !cleanName.isEmpty && !busy && (cleanName != (user.name ?? user.username ?? "") || avatarData != nil || removeAvatar) }
    private func save() async { guard canSave else { return }; busy = true; defer { busy = false }; do { let updated = try await model.updateProfile(name: cleanName, avatarData: avatarData, removeAvatar: removeAvatar); updateUser(updated); dismiss() } catch { error = model.message(error, fallback: "Không cập nhật được hồ sơ.") } }
}

struct ChangePasswordView: View {
    @ObservedObject var model: AccountViewModel; @State private var current = ""; @State private var next = ""; @State private var confirmation = ""; @State private var busy = false; @State private var error: String?; @State private var succeeded = false
    var body: some View { Form { Section("Mật khẩu") { SecureField("Mật khẩu hiện tại", text: $current); SecureField("Mật khẩu mới", text: $next); SecureField("Nhập lại mật khẩu mới", text: $confirmation) }; if let error { Section { Text(error).foregroundStyle(.red) } }; Section { Button { Task { await save() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Đổi mật khẩu").bold(); Spacer() } }.disabled(!valid || busy || succeeded) } }.scrollContentBackground(.hidden).background(CineVietTheme.background).navigationTitle("Đổi mật khẩu") }
    private var valid: Bool { !current.isEmpty && next.count >= 6 && next == confirmation }
    private func save() async { busy = true; defer { busy = false }; do { try await model.changePassword(current: current, new: next); succeeded = true } catch { error = model.message(error, fallback: "Không đổi được mật khẩu.") } }
}
