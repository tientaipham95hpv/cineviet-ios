import SwiftUI

@MainActor
final class AccountViewModel: ObservableObject {
    @Published var membership: MembershipSummary?
    @Published var isLoading = false
    @Published var errorMessage: String?
    private let service: AuthenticationServicing

    init(service: AuthenticationServicing) { self.service = service }

    func loadMembership() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { membership = try await service.membershipSummary() }
        catch { errorMessage = message(error, fallback: "Không tải được thông tin đặc quyền.") }
    }

    func updateName(_ name: String) async throws -> User { try await service.updateProfile(name: name) }
    func changePassword(current: String, new: String) async throws { try await service.changePassword(current: current, new: new) }

    func message(_ error: Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}

struct AccountView: View {
    @EnvironmentObject private var settings: AppSettings
    let user: User
    let updateUser: (User) -> Void
    let logout: () -> Void
    @StateObject private var model: AccountViewModel
    @State private var confirmsLogout = false

    init(user: User, service: AuthenticationServicing, updateUser: @escaping (User) -> Void, logout: @escaping () -> Void) {
        self.user = user; self.updateUser = updateUser; self.logout = logout
        _model = StateObject(wrappedValue: AccountViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Tài khoản") {
                    if let name = user.name ?? user.username { LabeledContent("Tên hiển thị", value: name) }
                    if let email = user.email { LabeledContent("Email", value: email) }
                    LabeledContent("Hạng", value: membershipLabel)
                    if user.isVip, let expiry = formatted(user.vipExpiresAt) { LabeledContent("Hết hạn", value: expiry) }
                }
                Section("Đặc quyền") {
                    if model.isLoading { HStack { ProgressView(); Text("Đang tải đặc quyền…") } }
                    else if let entitlement = model.membership?.entitlement {
                        LabeledContent("Trạng thái", value: entitlement.active ? "Đang hoạt động" : "Chưa kích hoạt hoặc đã hết hạn")
                        if entitlement.active, let days = entitlement.remainingDays { LabeledContent("Thời gian còn lại", value: "\(days) ngày") }
                        if entitlement.active, let expiry = formatted(entitlement.expiresAt) { LabeledContent("Đến ngày", value: expiry) }
                    }
                    if let error = model.errorMessage {
                        Text(error).foregroundStyle(.red).accessibilityLabel("Lỗi: \(error)")
                        Button("Thử lại") { Task { await model.loadMembership() } }.frame(minHeight: 44)
                    }
                }
                Section("Bảo mật và hồ sơ") {
                    NavigationLink("Chỉnh sửa tên hiển thị") { EditProfileView(user: user, model: model, updateUser: updateUser) }.frame(minHeight: 44)
                    NavigationLink("Đổi mật khẩu") { ChangePasswordView(model: model) }.frame(minHeight: 44)
                }
                Section("Ứng dụng") {
                    Picker("Giao diện", selection: $settings.appearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .pickerStyle(.navigationLink)
                    .accessibilityHint("Chọn giao diện theo hệ thống, sáng hoặc tối")
                    LabeledContent("Phiên bản", value: appBuildLabel)
                        .textSelection(.enabled)
                        .accessibilityHint("Dùng mã này để xác minh bản ứng dụng đang cài")
                }
                Section {
                    Button("Đăng xuất", role: .destructive) { confirmsLogout = true }.frame(maxWidth: .infinity, minHeight: 44)
                }
            }
            .scrollContentBackground(.hidden).background(CineVietTheme.background.ignoresSafeArea())
            .navigationTitle("Tài khoản")
            .task { await model.loadMembership() }
            .confirmationDialog("Đăng xuất khỏi CineViet?", isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive, action: logout); Button("Hủy", role: .cancel) {}
            }
        }
    }

    private var appBuildLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "dev"
        return "\(version) (\(build))"
    }
    private var membershipLabel: String {
        let role = (user.role ?? user.userRole ?? user.type)?.lowercased()
        if role == "admin" || role == "administrator" { return "Administrator" }
        return user.isVip ? "VIP" : "Thành viên"
    }
    private func formatted(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        let date = iso.date(from: raw) ?? DateFormatter.backend.date(from: raw)
        guard let date else { return nil }
        return date.formatted(date: .long, time: .omitted)
    }
}

private extension DateFormatter {
    static let backend: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
}
