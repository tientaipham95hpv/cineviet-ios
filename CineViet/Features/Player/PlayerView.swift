import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    @State private var controlsVisible = true
    @State private var pictureInPictureRequestID = 0
    @State private var controlsLocked = false
    @State private var hideTask: Task<Void, Never>?
    let servers: [EpisodeServer]

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService))
        servers = movie.episodes
    }

    var body: some View {
        cinematicPlayer
            .ignoresSafeArea()
        .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar).hidesFloatingNavigation()
        .onAppear { OrientationManager.landscape(); viewModel.start(); scheduleControlsHide() }
        .onDisappear { hideTask?.cancel(); viewModel.stop(); OrientationManager.portrait() }
    }

    private var cinematicPlayer: some View {
        ZStack {
            PictureInPicturePlayerView(player: viewModel.player, requestID: $pictureInPictureRequestID)
            Color.black.opacity(controlsVisible ? 0.34 : 0.001)
            if controlsVisible { playerOverlay.transition(.opacity) }
            subtitleOverlay
            loadingAndError
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle()).onTapGesture { guard !controlsLocked else { return }; withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }; if controlsVisible { scheduleControlsHide() } }
    }

    private var playerOverlay: some View {
        VStack {
            HStack {
                Button { OrientationManager.portrait(); dismiss() } label: { controlIcon("chevron.left") }
                Button { controlsLocked.toggle(); controlsVisible = true; controlsLocked ? hideTask?.cancel() : scheduleControlsHide() } label: { controlIcon(controlsLocked ? "lock.fill" : "lock.open") }.accessibilityLabel("Khóa điều khiển")
                VStack(alignment: .leading, spacing: 2) { Text(viewModel.movie.title).font(.subheadline.bold()).lineLimit(1); Text("\(viewModel.currentServer.name) • \(viewModel.currentEpisode.name)").font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(1) }
                Spacer()
                AirPlayButton().frame(width: 34, height: 34)
                Button { viewModel.isAutoPlayEnabled.toggle() } label: { controlIcon(viewModel.isAutoPlayEnabled ? "play.rectangle.on.rectangle.fill" : "play.rectangle.on.rectangle") }
            }.padding(12)
            Spacer()
            HStack(spacing: 42) {
                Button { viewModel.skip(-10) } label: { Image(systemName: "gobackward.10").font(.title) }
                Button { viewModel.togglePlayback(); scheduleControlsHide() } label: { Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 34, weight: .bold)).frame(width: 68, height: 68).background(.white.opacity(0.94), in: Circle()).foregroundStyle(.black) }
                Button { viewModel.skip(10) } label: { Image(systemName: "goforward.10").font(.title) }
            }
            Spacer()
            VStack(spacing: 6) {
                Slider(value: $viewModel.playbackPosition, in: 0...max(viewModel.playbackDuration, 1), onEditingChanged: { editing in if !editing { viewModel.seek(to: viewModel.playbackPosition) } }).tint(CineVietTheme.accent)
                HStack { Text(time(viewModel.playbackPosition)); Spacer(); Text("-\(time(max(0, viewModel.playbackDuration - viewModel.playbackPosition)))") }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.82))
                HStack(spacing: 24) {
                    Menu { Toggle("Tự động phát tập tiếp", isOn: $viewModel.isAutoPlayEnabled); if let next = viewModel.nextEpisode { Button("Phát \(next.name)") { viewModel.playNextEpisode() } } } label: { Label("Tự động", systemImage: "rectangle.stack.fill") }
                    optionMenu("Server", "server.rack", servers.map(\.name), selected: viewModel.currentServer.name) { viewModel.playServer(named: $0) }
                    subtitleMenu
                    Menu { ForEach(viewModel.currentServer.items) { episode in Button(episode.name) { viewModel.play(episode, server: viewModel.currentServer) }.disabled(PlayerViewModel.directMediaURL(for: episode) == nil) } } label: { Label("Tập phim", systemImage: "list.bullet.rectangle") }
                    audioMenu
                    Button { pictureInPictureRequestID += 1 } label: { Image(systemName: "pip.enter") }
                    AirPlayButton().frame(width: 26, height: 26)
                }
                .font(.caption.bold()).frame(maxWidth: .infinity)
            }.padding(.horizontal, 14).padding(.bottom, 8)
        }
    }

    private var subtitleOverlay: some View { VStack { Spacer(); if let subtitle = viewModel.overlaySubtitle { Text(subtitle).font(.headline).multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20).padding(.bottom, controlsVisible ? 46 : 12) } }.allowsHitTesting(false) }

    @ViewBuilder private var loadingAndError: some View {
        if viewModel.isLoading { ProgressView().controlSize(.large).tint(CineVietTheme.accent) }
        if viewModel.isBuffering && !viewModel.isLoading { ProgressView().tint(CineVietTheme.accent) }
        if let message = viewModel.errorMessage { VStack(spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CineVietTheme.accent); Text(message).font(.subheadline).multilineTextAlignment(.center); Button("Thử lại") { viewModel.retry() }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black) }.padding(18).background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16)).padding() }
    }

    private var audioMenu: some View { Menu { if viewModel.availableAudio.isEmpty { Text("Theo nguồn M3U8") } else { ForEach(viewModel.availableAudio) { source in Button(source.label.isEmpty ? source.key : source.label) { viewModel.selectAudio(source) } } } } label: { Label("Âm thanh", systemImage: "speaker.wave.2.fill").optionChip() } }
    private var subtitleMenu: some View { Menu { Button("Tắt") { viewModel.selectSubtitle("off") }; if viewModel.availableSubtitles.contains(where: { $0.lang.lowercased().hasPrefix("vi") }) && viewModel.availableSubtitles.contains(where: { $0.lang.lowercased().hasPrefix("en") }) { Button("Song ngữ Việt + Anh") { viewModel.selectSubtitle("dual") } }; ForEach(viewModel.availableSubtitles) { subtitle in Button(subtitle.label.isEmpty ? subtitle.lang : subtitle.label) { viewModel.selectSubtitle(subtitle.lang) } } } label: { Label("Phụ đề", systemImage: "captions.bubble.fill").optionChip() } }

    private func scheduleControlsHide() {
        hideTask?.cancel()
        guard !controlsLocked else { return }
        hideTask = Task { try? await Task.sleep(nanoseconds: 4_000_000_000); guard !Task.isCancelled else { return }; await MainActor.run { withAnimation { controlsVisible = false } } }
    }
    private func optionMenu(_ title: String, _ icon: String, _ values: [String], selected: String, action: @escaping (String) -> Void) -> some View { Menu { ForEach(values, id: \.self) { value in Button { action(value) } label: { if value == selected { Label(value, systemImage: "checkmark") } else { Text(value) } } } } label: { Label(title, systemImage: icon).optionChip() } }
    private func controlIcon(_ name: String) -> some View { Image(systemName: name).font(.headline).frame(width: 38, height: 38).background(.black.opacity(0.55), in: Circle()) }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds.isFinite ? seconds : 0)); return String(format: "%02d:%02d", value / 60, value % 60) }
}

private extension View { func optionChip() -> some View { self.font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 9).background(CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(CineVietTheme.border) } } }

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = true; view.tintColor = .white; view.activeTintColor = UIColor(CineVietTheme.accent); return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
