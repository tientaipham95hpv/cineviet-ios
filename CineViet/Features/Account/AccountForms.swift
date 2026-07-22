import PhotosUI
import SwiftUI
import UIKit

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
                avatarPreview.frame(maxWidth: .infinity)
                PhotosPicker(selection: $selectedPhoto, matching: .images) { Label("Chọn ảnh đại diện", systemImage: "photo.on.rectangle") }.frame(maxWidth: .infinity)
                if avatarData != nil || user.avatar?.isEmpty == false { Button("Xoá ảnh đại diện", role: .destructive) { removeAvatar = true; avatarData = nil; selectedPhoto = nil } }
            }
            Section("Tên hiển thị") { TextField("Tên hiển thị", text: $name).textContentType(.name); Text("Ảnh được cắt vuông, thu nhỏ tối đa 1024 px và nén JPEG trước khi tải lên.").font(.caption).foregroundStyle(CineVietTheme.textMuted) }
            if let error { Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) } }
            Section { Button { Task { await save() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Lưu thay đổi").bold(); Spacer() } }.disabled(!canSave) }
        }
        .scrollContentBackground(.hidden).background(CineVietTheme.background).navigationTitle("Chỉnh sửa hồ sơ").navigationBarTitleDisplayMode(.inline).task(id: selectedPhoto) { await prepareSelectedAvatar() }
    }
    @ViewBuilder private var avatarPreview: some View {
        if let avatarData, let image = UIImage(data: avatarData) {
            Image(uiImage: image).resizable().scaledToFill().frame(width: 92, height: 92).clipShape(Circle()).overlay(Circle().stroke(user.isVip ? Color.yellow : CineVietTheme.accent, lineWidth: user.isVip ? 3 : 1))
        } else { UserAvatar(name: name.isEmpty ? "CineViet" : name, url: removeAvatar ? nil : URL(string: user.avatar ?? ""), isVIP: user.isVip, size: 92) }
    }
    private func prepareSelectedAvatar() async {
        guard let selectedPhoto else { return }
        do {
            guard let source = try await selectedPhoto.loadTransferable(type: Data.self), let optimized = AvatarImageProcessor.optimize(source) else { throw AvatarImageError.invalidImage }
            avatarData = optimized; removeAvatar = false; error = nil
        } catch { avatarData = nil; error = "Không thể xử lý ảnh đã chọn. Vui lòng thử ảnh khác." }
    }
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !cleanName.isEmpty && !busy && (cleanName != (user.name ?? user.username ?? "") || avatarData != nil || removeAvatar) }
    private func save() async { guard canSave else { return }; busy = true; defer { busy = false }; do { let updated = try await model.updateProfile(name: cleanName, avatarData: avatarData, removeAvatar: removeAvatar); updateUser(updated); dismiss() } catch { error = model.message(error, fallback: "Không cập nhật được hồ sơ.") } }
}

private enum AvatarImageError: Error { case invalidImage }
private enum AvatarImageProcessor {
    static func optimize(_ data: Data, maximumDimension: CGFloat = 1024, quality: CGFloat = 0.82) -> Data? {
        guard let source = UIImage(data: data) else { return nil }
        let normalized = normalize(source)
        guard let cgImage = normalized.cgImage else { return nil }
        let side = min(CGFloat(cgImage.width), CGFloat(cgImage.height))
        let crop = CGRect(x: (CGFloat(cgImage.width) - side) / 2, y: (CGFloat(cgImage.height) - side) / 2, width: side, height: side).integral
        guard let cropped = cgImage.cropping(to: crop) else { return nil }
        let outputSide = min(side, maximumDimension)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: outputSide, height: outputSide), format: format).image { _ in
            UIImage(cgImage: cropped).draw(in: CGRect(x: 0, y: 0, width: outputSide, height: outputSide))
        }
        return image.jpegData(compressionQuality: quality)
    }

    private static func normalize(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat(); format.scale = image.scale; format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: image.size)) }
    }
}

struct ChangePasswordView: View {
    @ObservedObject var model: AccountViewModel; @State private var current = ""; @State private var next = ""; @State private var confirmation = ""; @State private var busy = false; @State private var error: String?; @State private var succeeded = false
    var body: some View { Form { Section("Mật khẩu") { SecureField("Mật khẩu hiện tại", text: $current); SecureField("Mật khẩu mới", text: $next); SecureField("Nhập lại mật khẩu mới", text: $confirmation) }; if let error { Section { Text(error).foregroundStyle(.red) } }; Section { Button { Task { await save() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "Đang lưu…" : "Đổi mật khẩu").bold(); Spacer() } }.disabled(!valid || busy || succeeded) } }.scrollContentBackground(.hidden).background(CineVietTheme.background).navigationTitle("Đổi mật khẩu") }
    private var valid: Bool { !current.isEmpty && next.count >= 6 && next == confirmation }
    private func save() async { busy = true; defer { busy = false }; do { try await model.changePassword(current: current, new: next); succeeded = true } catch { error = model.message(error, fallback: "Không đổi được mật khẩu.") } }
}
