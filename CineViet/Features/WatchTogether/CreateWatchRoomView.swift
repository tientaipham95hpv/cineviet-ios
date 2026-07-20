import SwiftUI

struct CreateWatchRoomView: View {
    let movie: Movie
    @ObservedObject var service: WatchTogetherService
    let onCreated: (EpisodeServer, EpisodeItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var serverIndex = 0
    @State private var episodeIndex = 0
    @State private var isPublic = true
    @State private var capacity = 8
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Nội dung") {
                    Picker("Máy chủ", selection: $serverIndex) { ForEach(movie.episodes.indices, id: \.self) { Text(movie.episodes[$0].name).tag($0) } }
                        .onChange(of: serverIndex) { _ in episodeIndex = 0 }
                    if !movie.episodes.isEmpty {
                        Picker("Tập phim", selection: $episodeIndex) { ForEach(movie.episodes[serverIndex].items.indices, id: \.self) { Text(movie.episodes[serverIndex].items[$0].name).tag($0) } }
                    }
                }
                Section("Phòng") {
                    Toggle("Hiển thị công khai", isOn: $isPublic)
                    Picker("Sức chứa", selection: $capacity) { ForEach([2, 4, 6, 8], id: \.self) { Text("\($0) người").tag($0) } }.pickerStyle(.segmented)
                }
                if let error { Section { Text(error).foregroundStyle(.red); Button("Thử lại") { Task { await create() } } } }
                Section { Button { Task { await create() } } label: { HStack { Spacer(); if busy { ProgressView() }; Text(busy ? "Đang tạo…" : "Tạo phòng"); Spacer() } }.disabled(busy || selection == nil) }
            }
            .navigationTitle("Tạo phòng xem chung").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Huỷ") { dismiss() }.disabled(busy) } }
        }
    }

    private var selection: (EpisodeServer, EpisodeItem)? {
        guard movie.episodes.indices.contains(serverIndex), movie.episodes[serverIndex].items.indices.contains(episodeIndex) else { return nil }
        return (movie.episodes[serverIndex], movie.episodes[serverIndex].items[episodeIndex])
    }
    private func create() async {
        guard let (server, episode) = selection else { error = "Chọn máy chủ và tập phim"; return }
        busy = true; error = nil; defer { busy = false }
        do { _ = try await service.create(movie: movie, videoURL: episode.playUrl, maxMembers: capacity, isPublic: isPublic); onCreated(server, episode); dismiss() }
        catch { self.error = error.localizedDescription.replacingOccurrences(of: "Exception: ", with: "") }
    }
}
