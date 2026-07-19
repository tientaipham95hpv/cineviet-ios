import AVKit
import SwiftUI

struct PlayerView: View {
    @StateObject private var viewModel: PlayerViewModel
    @State private var isFullScreen = false
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
                        .tint(CineVietTheme.accent)
                        .padding()
                        .cineGlass(cornerRadius: 14, tint: CineVietTheme.accent)
                }
                if viewModel.isBuffering && !viewModel.isLoading {
                    ProgressView().tint(CineVietTheme.accent).padding(16).cineGlass(cornerRadius: 18, tint: CineVietTheme.accent)
                }
                if let message = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(CineVietTheme.accent)
                        Text(message).multilineTextAlignment(.center)
                        Button("Thử lại") { viewModel.start() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .cineGlass(cornerRadius: 18, tint: CineVietTheme.accent)
                    .padding()
                }
                VStack {
                    HStack { Spacer(); Button { isFullScreen = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.headline).padding(11).cineGlass(cornerRadius: 14) }.accessibilityLabel("Toàn màn hình") }
                    Spacer()
                }.padding(10)
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 9, contentMode: .fit)

            List {
                Section {
                    Text(viewModel.movie.title).font(.headline)
                    Text("\(viewModel.currentServer.name) • \(viewModel.currentEpisode.name)")
                        .foregroundStyle(.secondary)
                    if let seconds = viewModel.resumePosition {
                        Label("Đã tiếp tục từ \(Int(seconds / 60)):\(String(format: "%02d", Int(seconds) % 60))", systemImage: "clock.arrow.circlepath")
                            .font(.caption).foregroundStyle(CineVietTheme.accent)
                    }
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
                                        Image(systemName: "play.circle.fill").foregroundStyle(CineVietTheme.accent)
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
        .fullScreenCover(isPresented: $isFullScreen) {
            FullScreenPlayer(player: viewModel.player, dismiss: { isFullScreen = false })
        }
    }

    private func selectionRow(_ title: String, selected: Bool) -> some View {
        HStack {
            Text(title)
            Spacer()
            if selected { Image(systemName: "checkmark").foregroundStyle(CineVietTheme.accent) }
        }
    }
}

private struct FullScreenPlayer: View {
    let player: AVPlayer
    let dismiss: () -> Void
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            NativePlayerView(player: player).ignoresSafeArea()
            Button(action: dismiss) { Image(systemName: "xmark").font(.headline).padding(12).cineGlass(cornerRadius: 16) }
                .padding()
        }
        .onAppear { player.play() }
    }
}
