import SwiftUI

@MainActor
final class AccountViewModel: ObservableObject {
    @Published private(set) var membership: MembershipSummary?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    private let service: AuthenticationServicing

    init(service: AuthenticationServicing) { self.service = service }

    func loadMembership() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do { membership = try await service.membershipSummary() }
        catch { errorMessage = message(error, fallback: "Không tải được thông tin đặc quyền.") }
    }

    func updateName(_ name: String) async throws -> User { try await service.updateProfile(name: name) }
    func changePassword(current: String, new: String) async throws { try await service.changePassword(current: current, new: new) }
    func message(_ error: Error, fallback: String) -> String { (error as? LocalizedError)?.errorDescription ?? fallback }
}

struct AccountView: View {
    @EnvironmentObject private var settings: AppSettings
    let user: User
    let updateUser: (User) -> Void
    let logout: () -> Void
    let watchHistoryService: WatchHistoryServicing
    @StateObject private var model: AccountViewModel
    @State private var confirmsLogout = false

    init(user: User, service: AuthenticationServicing, watchHistoryService: WatchHistoryServicing, updateUser: @escaping (User) -> Void, logout: @escaping () -> Void) {
        self.user = user; self.watchHistoryService = watchHistoryService; self.updateUser = updateUser; self.logout = logout
        _model = StateObject(wrappedValue: AccountViewModel(service: service))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 18) {
                    profileHeader
                    membershipCard
                    settingsCard
                    securityCard
                    appCard
                    logoutButton
                    Color.clear.frame(height: 94)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            .refreshable { await model.loadMembership() }
            .background(CineVietTheme.background.ignoresSafeArea())
            .navigationTitle("Tài khoản")
            .toolbar(.hidden, for: .navigationBar)
            .task { if model.membership == nil { await model.loadMembership() } }
            .confirmationDialog("Đăng xuất khỏi CineViet?", isPresented: $confirmsLogout, titleVisibility: .visible) {
                Button("Đăng xuất", role: .destructive, action: logout)
                Button("Hủy", role: .cancel) {}
            } message: { Text("Bạn cần đăng nhập lại để sử dụng thư viện và đồng bộ tiến độ xem.") }
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                avatar
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayName).font(.title2.bold()).lineLimit(2)
                    if let email = user.email { Text(email).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).lineLimit(1).textSelection(.enabled) }
                    HStack(spacing: 7) {
                        Label(membershipLabel, systemImage: user.isVip ? "crown.fill" : "person.fill")
                        if let status = user.status, !status.isEmpty { Text("•"); Text(status.capitalized) }
                    }
                    .font(.caption.weight(.bold)).foregroundStyle(user.isVip ? CineVietTheme.accent : CineVietTheme.textMuted)
                }
                Spacer(minLength: 0)
            }
            NavigationLink { EditProfileView(user: user, model: model, updateUser: updateUser) } label: {
                Label("Chỉnh sửa hồ sơ", systemImage: "pencil").font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.bordered).tint(CineVietTheme.accent)
        }
        .padding(18).cineGlass(cornerRadius: 24, tint: CineVietTheme.accent)
        .accessibilityElement(children: .contain)
    }

    private var avatar: some View {
        Group {
            if let raw = user.avatar, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() } else { initialsAvatar }
                }
            } else { initialsAvatar }
        }
        .frame(width: 82, height: 82).clipShape(Circle())
        .overlay { Circle().stroke(CineVietTheme.accent.opacity(0.75), lineWidth: 2) }
        .accessibilityLabel("Ảnh đại diện của \(displayName)")
    }

    private var initialsAvatar: some View {
        ZStack {
            LinearGradient(colors: [CineVietTheme.accent, CineVietTheme.accentDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(initials).font(.title.bold()).foregroundStyle(.black)
        }
    }

    private var membershipCard: some View {
        card(title: "Đặc quyền", icon: "crown.fill") {
            if model.isLoading {
                HStack(spacing: 12) { ProgressView(); Text("Đang tải trạng thái tài khoản…").foregroundStyle(CineVietTheme.textMuted) }.frame(minHeight: 48)
            } else if let entitlement = model.membership?.entitlement {
                infoRow("Trạng thái", entitlement.active ? "Đang hoạt động" : "Chưa kích hoạt hoặc đã hết hạn", icon: entitlement.active ? "checkmark.seal.fill" : "minus.circle")
                if entitlement.active, let days = entitlement.remainingDays { Divider(); infoRow("Thời gian còn lại", "\(days) ngày", icon: "calendar") }
                if entitlement.active, let expiry = formatted(entitlement.expiresAt) { Divider(); infoRow("Đến ngày", expiry, icon: "clock") }
            } else {
                Text("Chưa có thông tin đặc quyền.").foregroundStyle(CineVietTheme.textMuted)
            }
            if let error = model.errorMessage {
                Divider(); Label(error, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(.red)
                Button("Thử lại") { Task { await model.loadMembership() } }.buttonStyle(.bordered).frame(minHeight: 44)
            }
        }
    }

    private var settingsCard: some View {
        card(title: "Giao diện", icon: "circle.lefthalf.filled") {
            Text("Áp dụng ngay trên toàn bộ ứng dụng và được ghi nhớ cho lần mở sau.").font(.caption).foregroundStyle(CineVietTheme.textMuted)
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { appearance in
                    Button { settings.appearance = appearance } label: {
                        VStack(spacing: 7) {
                            Image(systemName: appearanceIcon(appearance)).font(.title3)
                            Text(appearance.title).font(.caption.weight(.bold)).lineLimit(1).minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .foregroundStyle(settings.appearance == appearance ? .black : .primary)
                        .background(settings.appearance == appearance ? CineVietTheme.accent : CineVietTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 15))
                        .overlay { RoundedRectangle(cornerRadius: 15).stroke(settings.appearance == appearance ? CineVietTheme.accent : CineVietTheme.border) }
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(settings.appearance == appearance ? .isSelected : [])
                }
            }
        }
    }

    private var securityCard: some View {
        card(title: "Bảo mật", icon: "lock.shield.fill") {
            NavigationLink { ChangePasswordView(model: model) } label: {
                HStack { Label("Đổi mật khẩu", systemImage: "key.fill"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(CineVietTheme.textMuted) }.frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityHint("Mở màn hình đổi mật khẩu")
        }
    }

    private var appCard: some View {
        card(title: "Ứng dụng", icon: "info.circle.fill") {
            infoRow("Phiên bản", appBuildLabel, icon: "app.badge")
            Divider()
            infoRow("Tài khoản", user.id, icon: "number").textSelection(.enabled)
            Divider()
            NavigationLink { OfflineDownloadsView(watchHistoryService: watchHistoryService) } label: { HStack { Label("Nội dung tải xuống", systemImage: "arrow.down.circle.fill"); Spacer(); Image(systemName: "chevron.right").foregroundStyle(CineVietTheme.textMuted) }.frame(minHeight: 48) }.buttonStyle(.plain).accessibilityHint("Mở thư viện xem offline")
        }
    }

    private var logoutButton: some View {
        Button(role: .destructive) { confirmsLogout = true } label: {
            Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right").font(.headline).frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered).tint(.red).accessibilityHint("Yêu cầu xác nhận trước khi đăng xuất")
    }

    private func card<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline).foregroundStyle(CineVietTheme.accent)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(CineVietTheme.border) }
    }

    private func infoRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack(spacing: 12) { Image(systemName: icon).frame(width: 24).foregroundStyle(CineVietTheme.accent); Text(title); Spacer(); Text(value).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.trailing).lineLimit(2) }.font(.subheadline).frame(minHeight: 38).accessibilityElement(children: .combine)
    }

    private var displayName: String { user.name ?? user.username ?? "Thành viên CineViet" }
    private var initials: String { displayName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased().nonEmpty ?? "CV" }
    private var appBuildLabel: String { let info = Bundle.main.infoDictionary; let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"; let build = info?["CFBundleVersion"] as? String ?? "dev"; return "\(version) (\(build))" }
    private var membershipLabel: String { let role = (user.role ?? user.userRole ?? user.type)?.lowercased(); if role == "admin" || role == "administrator" { return "Administrator" }; return user.isVip ? "VIP" : "Thành viên" }
    private func appearanceIcon(_ appearance: AppAppearance) -> String { switch appearance { case .system: "iphone"; case .light: "sun.max.fill"; case .dark: "moon.fill" } }
    private func formatted(_ raw: String?) -> String? { guard let raw, !raw.isEmpty else { return nil }; let iso = ISO8601DateFormatter(); let date = iso.date(from: raw) ?? DateFormatter.backend.date(from: raw); return date?.formatted(date: .long, time: .omitted) }
}

private extension DateFormatter {
    static let backend: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
}
