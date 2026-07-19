import AVKit
import SwiftUI

struct PlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: PlayerViewModel
    @State private var isFullScreen = false
    @State private var controlsVisible = true
    let servers: [EpisodeServer]

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing) {
        _viewModel = StateObject(wrappedValue: PlayerViewModel(movie: movie, server: server, episode: episode, watchHistoryService: watchHistoryService))
        servers = movie.episodes
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                cinematicPlayer
                playerInformation
                playbackOptions
                episodeBrowser
            }
        }
        .background(CineVietTheme.background.ignoresSafeArea()).foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar).hidesFloatingNavigation()
        .onAppear { viewModel.start() }.onDisappear { viewModel.stop() }
        .fullScreenCover(isPresented: $isFullScreen) { FullScreenPlayer(viewModel: viewModel, dismiss: { isFullScreen = false }) }
    }

    private var cinematicPlayer: some View {
        ZStack {
            NativePlayerView(player: viewModel.player, showsPlaybackControls: false)
            Color.black.opacity(controlsVisible ? 0.34 : 0.001)
            if controlsVisible { playerOverlay.transition(.opacity) }
            subtitleOverlay
            loadingAndError
        }
        .frame(maxWidth: .infinity).aspectRatio(16 / 9, contentMode: .fit)
        .contentShape(Rectangle()).onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() } }
    }

    private var playerOverlay: some View {
        VStack {
            HStack {
                Button { dismiss() } label: { controlIcon("chevron.left") }
                VStack(alignment: .leading, spacing: 2) { Text(viewModel.movie.title).font(.subheadline.bold()).lineLimit(1); Text("\(viewModel.currentServer.name) • \(viewModel.currentEpisode.name)").font(.caption).foregroundStyle(.white.opacity(0.72)).lineLimit(1) }
                Spacer()
                AirPlayButton().frame(width: 34, height: 34)
                Button { isFullScreen = true } label: { controlIcon("arrow.up.left.and.arrow.down.right") }
            }.padding(12)
            Spacer()
            HStack(spacing: 42) {
                Button { viewModel.skip(-10) } label: { Image(systemName: "gobackward.10").font(.title) }
                Button { viewModel.togglePlayback() } label: { Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 34, weight: .bold)).frame(width: 68, height: 68).background(.white.opacity(0.94), in: Circle()).foregroundStyle(.black) }
                Button { viewModel.skip(10) } label: { Image(systemName: "goforward.10").font(.title) }
            }
            Spacer()
            VStack(spacing: 3) {
                Slider(value: $viewModel.playbackPosition, in: 0...max(viewModel.playbackDuration, 1), onEditingChanged: { editing in if !editing { viewModel.seek(to: viewModel.playbackPosition) } }).tint(CineVietTheme.accent)
                HStack { Text(time(viewModel.playbackPosition)); Spacer(); Text("-\(time(max(0, viewModel.playbackDuration - viewModel.playbackPosition)))") }.font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.82))
            }.padding(.horizontal, 14).padding(.bottom, 8)
        }
    }

    private var subtitleOverlay: some View { VStack { Spacer(); if let subtitle = viewModel.overlaySubtitle { Text(subtitle).font(.headline).multilineTextAlignment(.center).padding(.horizontal, 12).padding(.vertical, 7).background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20).padding(.bottom, controlsVisible ? 46 : 12) } }.allowsHitTesting(false) }

    @ViewBuilder private var loadingAndError: some View {
        if viewModel.isLoading { ProgressView().controlSize(.large).tint(CineVietTheme.accent) }
        if viewModel.isBuffering && !viewModel.isLoading { ProgressView().tint(CineVietTheme.accent) }
        if let message = viewModel.errorMessage { VStack(spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(CineVietTheme.accent); Text(message).font(.subheadline).multilineTextAlignment(.center); Button("Thử lại") { viewModel.start() }.buttonStyle(.borderedProminent).tint(CineVietTheme.accent).foregroundStyle(.black) }.padding(18).background(.black.opacity(0.82), in: RoundedRectangle(cornerRadius: 16)).padding() }
    }

    private var playerInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.movie.title).font(.title2.bold())
            HStack { Text(viewModel.currentEpisode.name); Text("•"); Text(viewModel.currentServer.name) }.font(.subheadline).foregroundStyle(CineVietTheme.textMuted)
            HStack(spacing: 10) {
                optionMenu("Máy chủ", "server.rack", servers.map(\.name), selected: viewModel.currentServer.name) { name in if let server = servers.first(where: { $0.name == name }), let episode = server.items.first(where: { PlayerViewModel.directMediaURL(for: $0) != nil }) { viewModel.play(episode, server: server) } }
                audioMenu
                subtitleMenu
                Button { isFullScreen = true } label: { Label("Toàn màn hình", systemImage: "arrow.up.left.and.arrow.down.right").optionChip() }
            }
        }.padding(18)
    }

    private var playbackOptions: some View { VStack(spacing: 0) { Toggle(isOn: $viewModel.isAutoPlayEnabled) { Label("Tự động phát tập tiếp theo", systemImage: "forward.end.fill") }.tint(CineVietTheme.accent).padding(16); if let next = viewModel.nextEpisode { Divider().overlay(CineVietTheme.border); Button { viewModel.playNextEpisode() } label: { HStack { Label("Phát tiếp: \(next.name)", systemImage: "play.circle.fill"); Spacer(); Image(systemName: "chevron.right") }.padding(16) } } }.background(CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 18) }

    private var episodeBrowser: some View { VStack(alignment: .leading, spacing: 14) { Text("Danh sách tập").font(.title3.bold()); ForEach(servers, id: \.name) { server in DisclosureGroup(server.name) { LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 10)], spacing: 10) { ForEach(server.items) { episode in Button { viewModel.play(episode, server: server) } label: { Text(episode.name).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 48).background(episode.id == viewModel.currentEpisode.id && server.name == viewModel.currentServer.name ? CineVietTheme.accent : CineVietTheme.panel, in: RoundedRectangle(cornerRadius: 10)).foregroundStyle(episode.id == viewModel.currentEpisode.id && server.name == viewModel.currentServer.name ? .black : .white) }.disabled(PlayerViewModel.directMediaURL(for: episode) == nil) } }.padding(.top, 10) }.padding(.vertical, 8) } }.padding(18) }

    private var audioMenu: some View { Menu { if viewModel.availableAudio.isEmpty { Text("Theo nguồn M3U8") } else { ForEach(viewModel.availableAudio) { source in Button(source.label.isEmpty ? source.key : source.label) { viewModel.selectAudio(source) } } } } label: { Label("Âm thanh", systemImage: "speaker.wave.2.fill").optionChip() } }
    private var subtitleMenu: some View { Menu { Button("Tắt") { viewModel.selectSubtitle("off") }; ForEach(viewModel.availableSubtitles) { subtitle in Button(subtitle.label.isEmpty ? subtitle.lang : subtitle.label) { viewModel.selectSubtitle(subtitle.lang) } } } label: { Label("Phụ đề", systemImage: "captions.bubble.fill").optionChip() } }
    private func optionMenu(_ title: String, _ icon: String, _ values: [String], selected: String, action: @escaping (String) -> Void) -> some View { Menu { ForEach(values, id: \.self) { value in Button { action(value) } label: { if value == selected { Label(value, systemImage: "checkmark") } else { Text(value) } } } } label: { Label(title, systemImage: icon).optionChip() } }
    private func controlIcon(_ name: String) -> some View { Image(systemName: name).font(.headline).frame(width: 38, height: 38).background(.black.opacity(0.55), in: Circle()) }
    private func time(_ seconds: Double) -> String { let value = max(0, Int(seconds.isFinite ? seconds : 0)); return String(format: "%02d:%02d", value / 60, value % 60) }
}

private extension View { func optionChip() -> some View { self.font(.caption.bold()).padding(.horizontal, 11).padding(.vertical, 9).background(CineVietTheme.panel, in: Capsule()).overlay { Capsule().stroke(CineVietTheme.border) } } }

private struct FullScreenPlayer: View {
    @ObservedObject var viewModel: PlayerViewModel
    let dismiss: () -> Void
    var body: some View { ZStack(alignment: .topTrailing) { Color.black.ignoresSafeArea(); NativePlayerView(player: viewModel.player).ignoresSafeArea(); if let subtitle = viewModel.overlaySubtitle { Text(subtitle).font(.headline).padding(9).background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8)).frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 30) }; Button(action: dismiss) { Image(systemName: "xmark").font(.headline).padding(12).cineGlass(cornerRadius: 16) }.padding() }.onAppear { viewModel.player.play() } }
}

private struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView { let view = AVRoutePickerView(); view.prioritizesVideoDevices = true; view.tintColor = .white; view.activeTintColor = UIColor(CineVietTheme.accent); return view }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) { }
}
