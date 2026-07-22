import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published private(set) var notifications: [UserNotification] = []
    @Published private(set) var unreadCount = 0
    @Published private(set) var settings: NotificationSettings?
    @Published private(set) var isLoading = false
    @Published private(set) var isMarkingRead = false
    @Published private(set) var savingSetting: String?
    @Published var errorMessage: String?
    private let service: NotificationServicing

    init(service: NotificationServicing) { self.service = service }

    func load() async {
        guard !isLoading else { return }
        isLoading = true; errorMessage = nil
        defer { isLoading = false }
        do {
            async let list = service.notifications(limit: 30)
            async let preferences = service.settings()
            let (loadedList, loadedSettings) = try await (list, preferences)
            notifications = loadedList.notifications
            unreadCount = loadedList.unreadCount
            settings = loadedSettings
        } catch { errorMessage = message(error, fallback: "Không tải được thông báo.") }
    }

    func markAllRead() async {
        guard unreadCount > 0, !isMarkingRead else { return }
        isMarkingRead = true; errorMessage = nil
        defer { isMarkingRead = false }
        do { try await service.markAllRead(); unreadCount = 0 }
        catch { errorMessage = message(error, fallback: "Không đánh dấu đã đọc được.") }
    }

    func update(_ key: String, value: Bool) async {
        guard savingSetting == nil else { return }
        savingSetting = key; errorMessage = nil
        defer { savingSetting = nil }
        let update = NotificationSettingUpdate(
            phimMoi: key == "phim_moi" ? value : nil,
            tapMoi: key == "tap_moi" ? value : nil,
            watchParty: key == "watch_party" ? value : nil,
            uuDai: key == "uu_dai" ? value : nil
        )
        do { settings = try await service.updateSettings(update) }
        catch { errorMessage = message(error, fallback: "Không lưu được cài đặt thông báo.") }
    }

    private func message(_ error: Error, fallback: String) -> String {
        (error as? LocalizedError)?.errorDescription ?? fallback
    }
}

struct NotificationsView: View {
    @StateObject private var model: NotificationsViewModel
    @EnvironmentObject private var container: AppContainer
    @Environment(\.openURL) private var openURL
    @State private var linkedMovie: Movie?
    @State private var linkError: String?

    init(service: NotificationServicing) {
        _model = StateObject(wrappedValue: NotificationsViewModel(service: service))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                preferencesCard
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline).foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Thử lại") { Task { await model.load() } }.buttonStyle(.bordered)
                }
                notificationList
            }
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
            .padding(16).padding(.bottom, 80)
        }
        .background(CineVietTheme.background.ignoresSafeArea())
        .navigationTitle("Thông báo")
        .toolbar {
            if model.unreadCount > 0 {
                Button { Task { await model.markAllRead() } } label: {
                    if model.isMarkingRead { ProgressView() } else { Text("Đọc tất cả") }
                }
                .disabled(model.isMarkingRead)
                .accessibilityHint("Đánh dấu toàn bộ thông báo là đã đọc")
            }
        }
        .refreshable { await model.load() }
        .task { if model.settings == nil { await model.load() } }
        .hidesFloatingNavigation()
        .navigationDestination(item: $linkedMovie) { movie in
            MovieDetailView(movie: movie, movieService: container.movieService, watchHistoryService: container.watchHistoryService, libraryService: container.libraryService)
        }
        .alert("Thông báo", isPresented: Binding(get: { linkError != nil }, set: { if !$0 { linkError = nil } })) { Button("OK") {} } message: { Text(linkError ?? "") }
    }

    @ViewBuilder private var notificationList: some View {
        if model.isLoading && model.notifications.isEmpty {
            ProgressView("Đang tải thông báo…").frame(maxWidth: .infinity, minHeight: 160)
        } else if model.notifications.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bell.slash").font(.system(size: 38)).foregroundStyle(CineVietTheme.textMuted)
                Text("Chưa có thông báo").font(.headline)
                Text("Thông báo hệ thống sẽ xuất hiện tại đây.").font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .accessibilityElement(children: .combine)
        } else {
            ForEach(Array(model.notifications.enumerated()), id: \.element.id) { index, item in
                notificationCard(item, isUnread: index < model.unreadCount)
            }
        }
    }

    private var preferencesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tùy chọn thông báo", systemImage: "slider.horizontal.3").font(.headline).foregroundStyle(CineVietTheme.accent)
            if let settings = model.settings {
                settingToggle("Phim mới", key: "phim_moi", value: settings.phimMoi)
                Divider(); settingToggle("Tập mới", key: "tap_moi", value: settings.tapMoi)
                Divider(); settingToggle("Phòng xem chung", key: "watch_party", value: settings.watchParty)
                Divider(); settingToggle("Ưu đãi", key: "uu_dai", value: settings.uuDai)
            } else { ProgressView().frame(maxWidth: .infinity, minHeight: 80) }
        }
        .padding(18).background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(CineVietTheme.border) }
    }

    private func settingToggle(_ title: String, key: String, value: Bool) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { next in Task { await model.update(key, value: next) } }))
            .disabled(model.savingSetting != nil)
            .frame(minHeight: 44)
            .accessibilityValue(value ? "Bật" : "Tắt")
    }

    private func notificationCard(_ item: UserNotification, isUnread: Bool) -> some View {
        Button {
            guard let url = item.externalURL else { return }
            if let slug = movieSlug(from: url) { Task { await openMovie(slug) } }
            else { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Circle().fill(isUnread ? CineVietTheme.accent : CineVietTheme.border).frame(width: 9, height: 9).padding(.top, 7)
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading)
                    if let description = item.description, !description.isEmpty { Text(description).font(.subheadline).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.leading) }
                    HStack { if let sender = item.sender { Text(sender) }; Spacer(); if item.externalURL != nil { Image(systemName: "arrow.up.right.square") } }.font(.caption).foregroundStyle(CineVietTheme.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(isUnread ? CineVietTheme.accent.opacity(0.65) : CineVietTheme.border) }
        }
        .buttonStyle(.plain).disabled(item.externalURL == nil)
        .accessibilityLabel("\(isUnread ? "Chưa đọc. " : "")\(item.title). \(item.description ?? "")")
        .accessibilityHint(item.externalURL == nil ? "" : "Mở nội dung thông báo")
    }

    private func movieSlug(from url: URL) -> String? {
        guard url.host?.lowercased() == AppEnvironment.siteBaseURL.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard let marker = parts.firstIndex(where: { ["phim", "movie", "movies"].contains($0.lowercased()) }), parts.indices.contains(marker + 1) else { return nil }
        return parts[marker + 1].removingPercentEncoding ?? parts[marker + 1]
    }

    private func openMovie(_ slug: String) async {
        do { linkedMovie = try await container.movieService.detail(idOrSlug: slug) }
        catch { linkError = "Không mở được phim từ thông báo." }
    }
}
