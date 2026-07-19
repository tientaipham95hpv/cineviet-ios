import AVKit
import SwiftUI

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    let servers: [EpisodeServer]

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(movie: movie, server: server, episode: episode))
        servers = movie.episodes
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NativePlayerView(player: viewModel.player)
                    .ignoresSafeArea(edges: .horizontal)
                if viewModel.isLoading {
                    ProgressView("Đang tải nguồn phát…")
                        .tint(.orange)
                        .padding()
                        .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
                }
                if let message = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(message).multilineTextAlignment(.center)
                        Button("Thử lại") { viewModel.start() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 16))
                    .padding()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)

            List {
                Section {
                    Text(viewModel.movie.title).font(.headline)
                    Text("\(viewModel.currentServer.name) • \(viewModel.currentEpisode.name)")
                        .foregroundStyle(.secondary)
                }
                if !viewModel.availableAudio.isEmpty {
                    Section("Âm thanh") {
                        ForEach(viewModel.availableAudio) { source in
                            Button { viewModel.selectAudio(source) } label: {
                                selectionRow(source.label.isEmpty ? source.key : source.label,
                                             selected: viewModel.selectedAudioKey == source.key)
                            }
                        }
                    }
                }
                if !viewModel.availableSubtitles.isEmpty {
                    Section("Phụ đề") {
                        Button { viewModel.selectSubtitle("off") } label: {
                            selectionRow("Tắt", selected: viewModel.selectedSubtitleLanguage == "off")
                        }
                        ForEach(viewModel.availableSubtitles) { subtitle in
                            Button { viewModel.selectSubtitle(subtitle.lang) } label: {
                                selectionRow(subtitle.label.isEmpty ? subtitle.lang : subtitle.label,
                                             selected: viewModel.selectedSubtitleLanguage == subtitle.lang)
                            }
                        }
                        Text("AVPlayer tự chọn track phụ đề tương ứng khi nguồn HLS cung cấp. Phụ đề rời SRT/WebVTT sẽ được hỗ trợ ở lớp overlay tiếp theo.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(servers, id: \.name) { server in
                    Section(server.name) {
                        ForEach(server.items) { episode in
                            Button {
                                viewModel.play(episode, server: server)
                            } label: {
                                HStack {
                                    Text(episode.name)
                                    Spacer()
                                    if episode.id == viewModel.currentEpisode.id,
                                       server.name == viewModel.currentServer.name {
                                        Image(systemName: "play.circle.fill").foregroundStyle(.orange)
                                    }
                                }
                            }
                            .disabled(PlayerViewModel.directMediaURL(for: episode) == nil)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundStyle(.white)
        .navigationTitle(viewModel.currentEpisode.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }

    private func selectionRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(.orange) }
        }
    }
}
