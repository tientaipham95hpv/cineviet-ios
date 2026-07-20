import SwiftUI

struct OfflineDownloadsView: View {
    @ObservedObject var manager = OfflineDownloadManager.shared
    let watchHistoryService: WatchHistoryServicing
    @State private var playback: OfflineDownloadItem?
    @State private var deleteItem: OfflineDownloadItem?
    @State private var deleteGroup: Group?
    @State private var message: String?

    private struct Group: Identifiable { let id: String; let title: String; let poster: String; let items: [OfflineDownloadItem] }
    private var groups: [Group] {
        Dictionary(grouping: manager.items) { $0.movieId > 0 ? String($0.movieId) : $0.movieSlug }.map { key, value in Group(id: key, title: value.first?.movieTitle ?? "Phim", poster: value.first?.posterURL ?? "", items: value.sorted { episodeNumber($0.episodeName) < episodeNumber($1.episodeName) }) }.sorted { ($0.items.first?.createdAt ?? .distantPast) > ($1.items.first?.createdAt ?? .distantPast) }
    }

    var body: some View {
        List {
            if let error = manager.loadError { ContentMessage(icon: "exclamationmark.triangle", title: "Không tải được thư viện", message: error); Button("Thử lại") { Task { await manager.load(force: true) } } }
            else if manager.items.isEmpty { ContentMessage(icon: "arrow.down.circle", title: "Chưa có nội dung tải xuống", message: "Các tập phim đã tải sẽ xuất hiện tại đây.").listRowBackground(Color.clear) }
            else { ForEach(groups) { group in Section { DisclosureGroup { ForEach(group.items) { row($0) } } label: { groupHeader(group) } } } }
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden).background(CineVietTheme.background.ignoresSafeArea()).navigationTitle("Nội dung tải xuống")
        .task { await manager.load() }
        .fullScreenCover(item: $playback) { item in OfflinePlayerBridge(item: item, watchHistoryService: watchHistoryService) }
        .confirmationDialog("Xóa tập đã tải?", isPresented: Binding(get: { deleteItem != nil }, set: { if !$0 { deleteItem = nil } }), titleVisibility: .visible) { Button("Xóa", role: .destructive) { if let deleteItem { Task { await manager.delete(deleteItem.id) } }; deleteItem = nil }; Button("Hủy", role: .cancel) {} } message: { Text("Tệp trên thiết bị sẽ bị xóa và không thể hoàn tác.") }
        .confirmationDialog("Xóa toàn bộ phim?", isPresented: Binding(get: { deleteGroup != nil }, set: { if !$0 { deleteGroup = nil } }), titleVisibility: .visible) { Button("Xóa tất cả", role: .destructive) { if let deleteGroup { Task { await manager.deleteMovie(deleteGroup.items.map(\.id)) } }; deleteGroup = nil }; Button("Hủy", role: .cancel) {} }
        .alert("CineViet", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
    }

    private func groupHeader(_ group: Group) -> some View { HStack(spacing: 12) { AsyncImage(url: URL(string: group.poster)) { phase in if case .success(let image) = phase { image.resizable().scaledToFill() } else { Image(systemName: "film.fill").frame(maxWidth: .infinity, maxHeight: .infinity).background(CineVietTheme.panel) } }.frame(width: 54, height: 78).clipShape(RoundedRectangle(cornerRadius: 8)); VStack(alignment: .leading, spacing: 5) { Text(group.title).font(.headline); Text("\(group.items.filter { $0.state == .completed }.count)/\(group.items.count) tập đã tải • \(bytes(group.items.reduce(0) { $0 + $1.receivedBytes }))").font(.caption).foregroundStyle(CineVietTheme.textMuted) }; Spacer(); Button(role: .destructive) { deleteGroup = group } label: { Image(systemName: "trash") }.accessibilityLabel("Xóa toàn bộ \(group.title)") }.padding(.vertical, 4) }
    private func row(_ item: OfflineDownloadItem) -> some View { VStack(alignment: .leading, spacing: 8) { HStack { VStack(alignment: .leading, spacing: 4) { Text(item.episodeName).font(.subheadline.bold()); Text(status(item)).font(.caption).foregroundStyle(item.state == .failed ? .red : CineVietTheme.textMuted) }; Spacer(); Button { action(item) } label: { Image(systemName: actionIcon(item)).frame(width: 44, height: 44) }.accessibilityLabel(actionLabel(item)); Button(role: .destructive) { deleteItem = item } label: { Image(systemName: "trash") }.frame(width: 44, height: 44).accessibilityLabel("Xóa \(item.episodeName)") }; if item.isActive { ProgressView(value: item.progress).tint(CineVietTheme.accent).accessibilityLabel("Tiến độ tải").accessibilityValue("\(Int(item.progress * 100)) phần trăm") } }.padding(.vertical, 4) }
    private func action(_ item: OfflineDownloadItem) { if item.isActive { Task { await manager.cancel(item.id) } } else if item.state == .completed { if manager.playbackURL(for: item) != nil { playback = item } else { message = "Bản tải xuống không còn trên thiết bị" } } else { Task { await manager.retry(item.id) } } }
    private func actionIcon(_ i: OfflineDownloadItem) -> String { i.isActive ? "xmark.circle" : (i.state == .completed ? "play.circle.fill" : "arrow.clockwise.circle") }
    private func actionLabel(_ i: OfflineDownloadItem) -> String { i.isActive ? "Hủy tải" : (i.state == .completed ? "Phát offline" : "Tải lại") }
    private func status(_ i: OfflineDownloadItem) -> String { switch i.state { case .queued: "Đang chờ tải"; case .downloading: "Đang tải \(Int(i.progress * 100))% • \(bytes(i.receivedBytes))"; case .completed: "Đã tải • \(bytes(i.receivedBytes))"; case .cancelled: "Đã hủy • chạm tải lại"; case .failed: i.error.isEmpty ? "Tải thất bại" : i.error } }
    private func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
    private func episodeNumber(_ s: String) -> Double { Double(s.filter { $0.isNumber || $0 == "." }) ?? .greatestFiniteMagnitude }
}

private struct OfflinePlayerBridge: View {
    let item: OfflineDownloadItem; let watchHistoryService: WatchHistoryServicing
    var body: some View {
        let episode = EpisodeItem.offline(name: item.episodeName, path: item.localManifestPath)
        let server = EpisodeServer(name: item.serverName, items: [episode])
        if let url = OfflineDownloadManager.shared.playbackURL(for: item), url.isFileURL {
            PlayerView(movie: Movie.offline(id: item.movieId, slug: item.movieSlug, title: item.movieTitle, poster: item.posterURL, server: server), server: server, episode: episode, watchHistoryService: watchHistoryService, offlineURL: url)
        } else { ContentMessage(icon: "exclamationmark.triangle", title: "Không thể phát offline", message: "Bản tải xuống không còn trên thiết bị") }
    }
}
