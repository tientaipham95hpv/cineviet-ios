import SwiftUI

struct OfflineDownloadPicker: View {
    @Environment(\.dismiss) private var dismiss
    let movie: Movie
    let authenticationService: AuthenticationServicing
    @ObservedObject private var manager = OfflineDownloadManager.shared
    @State private var serverIndex = 0
    @State private var message: String?
    @State private var checkingID: String?
    @State private var pendingSelection: TrackSelection?

    private var servers: [EpisodeServer] { movie.episodes.filter(OfflineDownloadManager.serverEligible) }
    var body: some View {
        NavigationStack {
            Group {
                if servers.isEmpty { ContentMessage(icon: "arrow.down.circle", title: "Không có nguồn tải khả dụng", message: "Nguồn nhúng và máy chủ không hỗ trợ HLS đã được ẩn.") }
                else { List { Picker("Máy chủ", selection: $serverIndex) { ForEach(servers.indices, id: \.self) { Text(servers[$0].name).tag($0) } }.pickerStyle(.segmented); ForEach(servers[min(serverIndex, servers.count - 1)].items.filter { OfflineDownloadManager.eligibleURL($0) != nil }) { episode in episodeRow(episode, server: servers[min(serverIndex, servers.count - 1)]) } } }
            }
            .navigationTitle("Tải \(movie.title)").navigationBarTitleDisplayMode(.inline).toolbar { ToolbarItem(placement: .cancellationAction) { Button("Đóng") { dismiss() } } }
            .alert("CineViet", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK") { message = nil } } message: { Text(message ?? "") }
            .sheet(item: $pendingSelection) { selection in trackSelectionSheet(selection) }
            .task { await manager.load() }
        }
    }
    private func episodeRow(_ episode: EpisodeItem, server: EpisodeServer) -> some View {
        let id = OfflineDownloadItem.stableID(movieId: movie.id, slug: movie.slug, server: server.name, episode: episode.name)
        let item = manager.items.first { $0.id == id }
        return HStack { VStack(alignment: .leading) { Text(episode.name).font(.headline); Text(server.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { beginDownload(episode, server: server) } label: { if let item, item.isActive { ProgressView(value: item.progress).frame(width: 42) } else if checkingID == id { ProgressView() } else { Image(systemName: item?.state == .completed ? "checkmark.circle.fill" : "arrow.down.circle.fill").font(.title2) } }.disabled(checkingID != nil || item?.state == .completed).accessibilityLabel(item?.state == .completed ? "Đã tải \(episode.name)" : (item?.isActive == true ? "Đang tải \(episode.name)" : "Tải xuống \(episode.name)")).accessibilityValue(item?.isActive == true ? "\(Int((item?.progress ?? 0) * 100)) phần trăm" : "").accessibilityHint(item?.state == .completed ? "Đã lưu trên thiết bị" : "Chọn audio và phụ đề trước khi tải") }
    }
    private func beginDownload(_ episode: EpisodeItem, server: EpisodeServer) {
        let audio = episode.audioSources.filter { URL(string: $0.url)?.scheme?.hasPrefix("http") == true }
        let subtitles = episode.subtitles.filter { URL(string: $0.url)?.scheme?.hasPrefix("http") == true }
        guard !audio.isEmpty || !subtitles.isEmpty else { Task { await download(episode, server: server, audio: [], subtitles: []) }; return }
        pendingSelection = TrackSelection(server: server, episode: episode, audioKeys: Set(audio.map(\.key)), subtitleKeys: Set(subtitles.map(\.lang)))
    }
    private func trackSelectionSheet(_ initial: TrackSelection) -> some View {
        TrackSelectionView(selection: initial) { selection in
            pendingSelection = nil
            Task { await download(selection.episode, server: selection.server, audio: selection.audioKeys, subtitles: selection.subtitleKeys) }
        }
    }
    private func download(_ episode: EpisodeItem, server: EpisodeServer, audio: Set<String>, subtitles: Set<String>) async {
        let id = OfflineDownloadItem.stableID(movieId: movie.id, slug: movie.slug, server: server.name, episode: episode.name)
        checkingID = id; defer { checkingID = nil }
        do {
            try await authenticationService.requireOfflineDownloadAccess()
            try await manager.enqueue(movie: movie, server: server, episode: episode, selectedAudioKeys: audio, selectedSubtitleKeys: subtitles)
            message = "Đã thêm \(episode.name) vào hàng tải xuống"
        } catch { message = (error as? LocalizedError)?.errorDescription ?? "Không thể kiểm tra quyền tải xuống" }
    }
}
