import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class ShortDramaViewModel: ObservableObject {
    @Published private(set) var movies: [Movie] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let movieService: MovieServicing

    init(movieService: MovieServicing) { self.movieService = movieService }

    func load(force: Bool = false) async {
        if !force, !movies.isEmpty { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var query = MovieListQuery()
            query.genre = "short-drama"
            query.limit = 100
            movies = try await movieService.list(query).movies
        } catch {
            errorMessage = "Không thể tải Short Drama. Vui lòng thử lại."
        }
    }
}

struct ShortDramaView: View {
    let movieService: MovieServicing
    @StateObject private var viewModel: ShortDramaViewModel

    init(movieService: MovieServicing) {
        self.movieService = movieService
        _viewModel = StateObject(wrappedValue: ShortDramaViewModel(movieService: movieService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.movies.isEmpty { loading }
                else if let message = viewModel.errorMessage, viewModel.movies.isEmpty { failure(message) }
                else if viewModel.movies.isEmpty { empty }
                else { grid }
            }
            .background(CineVietTheme.background.ignoresSafeArea())
            .navigationTitle("Short Drama")
            .navigationBarTitleDisplayMode(.large)
        }
        .task { await viewModel.load() }
    }

    private var grid: some View {
        GeometryReader { proxy in
            let minimum = proxy.size.width >= 700 ? 170.0 : 138.0
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum, maximum: 210), spacing: 14)], spacing: 18) {
                    ForEach(viewModel.movies) { movie in
                        NavigationLink {
                            ShortDramaViewer(movie: movie, movieService: movieService)
                        } label: {
                            ShortDramaCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 105)
            }
            .refreshable { await viewModel.load(force: true) }
        }
    }

    private var loading: some View {
        VStack(spacing: 14) {
            ProgressView().tint(CineVietTheme.accent)
            Text("Đang tải Short Drama").foregroundStyle(CineVietTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failure(_ message: String) -> some View {
        stateView(icon: "wifi.exclamationmark", title: "Không thể tải nội dung", message: message) {
            Button("Tải lại") { Task { await viewModel.load(force: true) } }.buttonStyle(.borderedProminent)
        }
    }

    private var empty: some View {
        stateView(icon: "rectangle.portrait.slash", title: "Chưa có Short Drama", message: "Nội dung mới sẽ xuất hiện tại đây.") { EmptyView() }
    }

    private func stateView<Actions: View>(icon: String, title: String, message: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 42)).foregroundStyle(CineVietTheme.textMuted)
            Text(title).font(.title3.bold())
            Text(message).foregroundStyle(CineVietTheme.textMuted).multilineTextAlignment(.center)
            actions()
        }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ShortDramaCard: View {
    let movie: Movie
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: movie.posterURL) { phase in
                if case let .success(image) = phase { image.resizable().scaledToFill() }
                else { ZStack { CineVietTheme.panel; Image(systemName: "play.rectangle.fill").font(.title).foregroundStyle(CineVietTheme.textMuted); if case .empty = phase { ProgressView().tint(CineVietTheme.accent) } } }
            }
            .aspectRatio(2 / 3, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                if !movie.episodeCurrent.isEmpty { Text(movie.episodeCurrent).font(.caption2.bold()).padding(.horizontal, 7).padding(.vertical, 4).background(.black.opacity(0.75), in: Capsule()).padding(8) }
            }
            Text(movie.title).font(.subheadline.weight(.semibold)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if !movie.metadataLine.isEmpty { Text(movie.metadataLine).font(.caption).foregroundStyle(CineVietTheme.textMuted).lineLimit(1) }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel([movie.title, movie.episodeCurrent].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityHint("Mở trình xem Short Drama")
    }
}

@MainActor
final class ShortDramaViewerModel: ObservableObject {
    @Published private(set) var movie: Movie?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    private let seed: Movie
    private let service: MovieServicing
    init(movie: Movie, service: MovieServicing) { seed = movie; self.service = service }
    var episodes: [EpisodeItem] { movie?.episodes.flatMap(\.items).filter { !$0.linkM3u8.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? [] }
    func load() async {
        isLoading = true; errorMessage = nil; defer { isLoading = false }
        do { movie = try await service.detail(idOrSlug: seed.routeKey) }
        catch { errorMessage = "Không thể tải phim. Vui lòng thử lại." }
    }
}

struct ShortDramaViewer: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ShortDramaViewerModel
    @State private var page = 0

    init(movie: Movie, movieService: MovieServicing) {
        _viewModel = StateObject(wrappedValue: ShortDramaViewerModel(movie: movie, service: movieService))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if viewModel.isLoading && viewModel.movie == nil { ProgressView("Đang mở Short Drama").tint(.white).foregroundStyle(.white) }
            else if let message = viewModel.errorMessage { errorView(message) }
            else if viewModel.episodes.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "play.slash").font(.system(size: 44))
                    Text("Chưa có tập phát trực tiếp").font(.headline)
                    Button("Đóng") { dismiss() }.buttonStyle(.bordered)
                }.foregroundStyle(.white)
            } else { verticalPages }
        }
        .toolbar(.hidden, for: .navigationBar)
        .hidesFloatingNavigation()
        .task { await viewModel.load() }
        .onAppear { NotificationCenter.default.post(name: .cineVietPlayerDidAppear, object: nil) }
        .onDisappear { NotificationCenter.default.post(name: .cineVietPlayerDidDisappear, object: nil) }
    }

    private var verticalPages: some View {
        GeometryReader { geometry in
            TabView(selection: $page) {
                ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                    ShortEpisodeView(movie: viewModel.movie!, episode: episode, index: index, total: viewModel.episodes.count, isActive: page == index, dismiss: { dismiss() })
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .rotationEffect(.degrees(90))
                        .tag(index)
                }
            }
            .frame(width: geometry.size.height, height: geometry.size.width)
            .rotationEffect(.degrees(-90), anchor: .topLeading)
            .offset(x: 0, y: geometry.size.height)
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .ignoresSafeArea()
        .accessibilityHint("Vuốt lên hoặc xuống để đổi tập")
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
            Text(message).multilineTextAlignment(.center)
            Button("Tải lại") { Task { await viewModel.load() } }.buttonStyle(.borderedProminent)
            Button("Đóng") { dismiss() }.buttonStyle(.bordered)
        }.foregroundStyle(.white).padding(24)
    }
}

private struct ShortEpisodeView: View {
    @Environment(\.scenePhase) private var scenePhase
    let movie: Movie
    let episode: EpisodeItem
    let index: Int
    let total: Int
    let isActive: Bool
    let dismiss: () -> Void
    @StateObject private var controller: ShortEpisodeController
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?

    init(movie: Movie, episode: EpisodeItem, index: Int, total: Int, isActive: Bool, dismiss: @escaping () -> Void) {
        self.movie = movie; self.episode = episode; self.index = index; self.total = total; self.isActive = isActive; self.dismiss = dismiss
        _controller = StateObject(wrappedValue: ShortEpisodeController(episode: episode))
    }

    var body: some View {
        ZStack {
            AsyncImage(url: movie.posterURL) { phase in if case let .success(image) = phase { image.resizable().scaledToFill() } else { Color.black } }.ignoresSafeArea()
            if let player = controller.player { NativePlayerView(player: player, showsPlaybackControls: false).ignoresSafeArea() }
            LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).opacity(controlsVisible ? 1 : 0)
            if controller.isLoading { ProgressView().tint(.white).scaleEffect(1.25) }
            if let error = controller.errorMessage { VStack(spacing: 12) { Image(systemName: "exclamationmark.triangle.fill"); Text(error); Button("Thử lại") { controller.reload() }.buttonStyle(.borderedProminent) }.foregroundStyle(.white).padding() }
            if !controller.isPlaying && !controller.isLoading && controller.errorMessage == nil { Image(systemName: "play.fill").font(.system(size: 64)).foregroundStyle(.white).shadow(radius: 8).accessibilityHidden(true) }
            controls
        }
        .contentShape(Rectangle())
        .onTapGesture { controlsVisible ? controller.toggle() : showControls() }
        .onChange(of: isActive) { active in active ? controller.play() : controller.pause() }
        .onChange(of: scenePhase) { phase in
            if phase != .active { controller.pause() }
        }
        .onAppear { if isActive { controller.play() }; scheduleHide() }
        .onDisappear { controller.pause(); hideTask?.cancel() }
        .accessibilityAction(named: controller.isPlaying ? "Tạm dừng" : "Phát") { controller.toggle() }
        .accessibilityAction(named: "Tua lùi 5 giây") { controller.seek(by: -5) }
        .accessibilityAction(named: "Tua tới 5 giây") { controller.seek(by: 5) }
    }

    private var controls: some View {
        VStack {
            HStack {
                Button(action: dismiss) { Image(systemName: "chevron.left").frame(width: 44, height: 44).background(.black.opacity(0.48), in: Circle()) }.accessibilityLabel("Đóng trình xem")
                Spacer()
                Text("\(index + 1)/\(total)").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(.black.opacity(0.48), in: Capsule())
            }
            Spacer()
            VStack(alignment: .leading, spacing: 5) { Text(movie.title).font(.headline); Text(episode.name).font(.subheadline).foregroundStyle(.white.opacity(0.8)); if controller.duration > 0 { Slider(value: Binding(get: { controller.position }, set: { controller.seek(to: $0) }), in: 0...controller.duration).tint(CineVietTheme.accent).accessibilityLabel("Tiến độ phát") } }
        }
        .foregroundStyle(.white).padding(.horizontal, 16).padding(.vertical, 12).opacity(controlsVisible ? 1 : 0).allowsHitTesting(controlsVisible)
    }

    private func showControls() { controlsVisible = true; scheduleHide() }
    private func scheduleHide() { hideTask?.cancel(); hideTask = Task { try? await Task.sleep(nanoseconds: 3_000_000_000); guard !Task.isCancelled, controller.isPlaying else { return }; controlsVisible = false } }
}

@MainActor
private final class ShortEpisodeController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = true
    @Published private(set) var isPlaying = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    private let episode: EpisodeItem
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init(episode: EpisodeItem) { self.episode = episode; reload() }
    deinit { if let timeObserver, let player { player.removeTimeObserver(timeObserver) }; if let endObserver { NotificationCenter.default.removeObserver(endObserver) } }

    func reload() {
        tearDown()
        guard let url = Self.streamURL(episode.linkM3u8) else { isLoading = false; errorMessage = "Đường dẫn tập không hợp lệ"; return }
        isLoading = true; errorMessage = nil
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        player = next
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in Task { @MainActor in guard let self else { return }; self.isLoading = item.status == .unknown; if item.status == .failed { self.errorMessage = "Không thể phát tập này" } } }
        timeObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in guard let self else { return }; self.position = max(0, time.seconds.isFinite ? time.seconds : 0); let value = item.duration.seconds; self.duration = value.isFinite ? max(0, value) : 0; self.isPlaying = next.timeControlStatus == .playing }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak next] _ in next?.seek(to: .zero); next?.play() }
    }
    func play() { player?.play(); isPlaying = true }
    func pause() { player?.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }
    func seek(by seconds: Double) { seek(to: position + seconds) }
    func seek(to seconds: Double) { player?.seek(to: CMTime(seconds: min(max(0, seconds), duration > 0 ? duration : seconds), preferredTimescale: 600)) }
    private func tearDown() { if let timeObserver, let player { player.removeTimeObserver(timeObserver) }; if let endObserver { NotificationCenter.default.removeObserver(endObserver) }; timeObserver = nil; endObserver = nil; statusObserver = nil; player?.pause(); player = nil }
    private static func streamURL(_ raw: String) -> URL? {
        let clean = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let direct = clean.hasPrefix("//") ? "https:\(clean)" : clean
        if direct.hasPrefix("\(AppEnvironment.apiBaseURL.absoluteString)/stream?") { return URL(string: direct) }
        var components = URLComponents(url: AppEnvironment.apiBaseURL.appendingPathComponent("stream"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "url", value: direct)]
        return components?.url
    }
}
