import AVKit
import SwiftUI

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    let servers: [EpisodeServer]

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService))
        servers = movie.episodes
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                NativePlayerView(player: viewModel.player)
                    .ignoresSafeArea(edges: .horizontal)
                if let subtitle = viewModel.overlaySubtitle {
                    VStack {
                        Spacer()
                        Text(subtitle)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .cineGlass(cornerRadius: 10)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 18)
                    }
                    .allowsHitTesting(false)
                }
                if viewModel.isLoading {
                    ProgressView("Đang tải nguồn phát…")
                        .tint(.orange)
                        .padding()
                        .cineGlass(cornerRadius: 14, tint: .orange)
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
                    .cineGlass(cornerRadius: 18, tint: .orange)
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
                    Toggle("Tự động phát tập tiếp theo", isOn: $viewModel.isAutoPlayEnabled)
                    if let nextEpisode = viewModel.nextEpisode {
                        Button {
                            viewModel.playNextEpisode()
                        } label: {
                            Label("Phát tiếp: \(nextEpisode.name)", systemImage: "forward.end.fill")
                        }
                    }
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
                        Text("Hỗ trợ track HLS nhúng và phụ đề rời SRT/WebVTT đồng bộ theo thời gian phát.")
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
            .listRowBackground(Color.white.opacity(0.055))
        }
        .background(CineVietTheme.background.ignoresSafeArea())
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
