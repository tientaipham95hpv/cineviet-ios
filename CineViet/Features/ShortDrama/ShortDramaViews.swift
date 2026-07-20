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
    @GestureState private var verticalDrag: CGFloat = 0

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
            ZStack {
                ForEach(Array(viewModel.episodes.enumerated()), id: \.element.id) { index, episode in
                    // Keep only the current page and its neighbours in the
                    // render tree. Controllers outside this window never own
                    // an AVPlayer, even when a title has up to 100 episodes.
                    if abs(index - page) <= 1 {
                        ShortEpisodeView(movie: viewModel.movie!, episode: episode, index: index, total: viewModel.episodes.count, isActive: page == index, dismiss: { dismiss() })
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .offset(y: CGFloat(index - page) * geometry.size.height + verticalDrag)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(verticalPagingGesture(pageHeight: geometry.size.height))
        }
        .ignoresSafeArea()
        .accessibilityHint("Vuốt lên hoặc xuống để đổi tập")
        .accessibilityAction(named: "Tập tiếp theo") { movePage(by: 1) }
        .accessibilityAction(named: "Tập trước") { movePage(by: -1) }
    }

    private func verticalPagingGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($verticalDrag) { value, state, _ in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let atFirst = page == 0 && value.translation.height > 0
                let atLast = page == viewModel.episodes.count - 1 && value.translation.height < 0
                state = (atFirst || atLast) ? value.translation.height * 0.18 : value.translation.height
            }
            .onEnded { value in
                guard abs(value.translation.height) > abs(value.translation.width) else { return }
                let projected = value.predictedEndTranslation.height
                let threshold = min(max(pageHeight * 0.16, 72), 150)
                if projected < -threshold { movePage(by: 1) }
                else if projected > threshold { movePage(by: -1) }
            }
    }

    private func movePage(by delta: Int) {
        let target = min(max(0, page + delta), viewModel.episodes.count - 1)
        guard target != page else { return }
        withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.88)) { page = target }
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

private struct ShortCoverPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
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
    @State private var seekFeedback: Int?
    @State private var hideTask: Task<Void, Never>?
    @State private var feedbackTask: Task<Void, Never>?

    init(movie: Movie, episode: EpisodeItem, index: Int, total: Int, isActive: Bool, dismiss: @escaping () -> Void) {
        self.movie = movie
        self.episode = episode
        self.index = index
        self.total = total
        self.isActive = isActive
        self.dismiss = dismiss
        _controller = StateObject(wrappedValue: ShortEpisodeController(episode: episode))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                AsyncImage(url: movie.posterURL) { phase in
                    if case let .success(image) = phase { image.resizable().scaledToFill() }
                    else { Color.black }
                }
                // Slight overscan prevents a one-pixel seam caused by UIKit ↔
                // SwiftUI rounding on some device scales and safe-area widths.
                .frame(width: proxy.size.width + 4, height: proxy.size.height + 4)
                .clipped()

                if let player = controller.player {
                    ShortCoverPlayerView(player: player)
                        .frame(width: proxy.size.width + 4, height: proxy.size.height + 4)
                        .clipped()
                        .accessibilityHidden(true)
                }

                LinearGradient(colors: [.black.opacity(0.55), .clear, .black.opacity(0.88)], startPoint: .top, endPoint: .bottom)
                    .opacity(controlsVisible ? 1 : 0)
                    .animation(.easeOut(duration: 0.22), value: controlsVisible)
                    .allowsHitTesting(false)

                centeredStatus
                if controller.isFastForwarding { speedChip }
                if let seekFeedback { seekFeedbackView(seekFeedback) }
                controls
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(tapGesture(viewWidth: proxy.size.width))
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .simultaneousGesture(longPressGesture)
        .onChange(of: isActive) { active in
            if active && scenePhase == .active { controller.activate() } else { controller.deactivate() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && isActive { controller.activate() } else { controller.deactivate() }
        }
        .onChange(of: controller.isPlaying) { playing in
            if playing { scheduleHide() } else { showControls(autoHide: false) }
        }
        .onAppear {
            if isActive && scenePhase == .active { controller.activate() }
            showControls(autoHide: true)
        }
        .onDisappear {
            controller.deactivate(release: true)
            hideTask?.cancel()
            feedbackTask?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(movie.title), \(episodeDisplayName), tập \(index + 1) trên \(total)")
        .accessibilityHint("Vuốt lên hoặc xuống để đổi tập")
        .accessibilityAction(named: controller.isPlaying ? "Tạm dừng" : "Phát") { togglePlayback() }
        .accessibilityAction(named: "Tua lùi 5 giây") { seek(-5) }
        .accessibilityAction(named: "Tua tới 5 giây") { seek(5) }
    }

    @ViewBuilder private var centeredStatus: some View {
        if controller.isLoading {
            ProgressView().tint(.white).scaleEffect(1.3).accessibilityLabel("Đang tải video")
        } else if let error = controller.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title)
                Text(error).font(.body).multilineTextAlignment(.center)
                Button("Thử lại") { controller.reload(autoplay: isActive && scenePhase == .active) }
                    .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white).padding(24)
        } else if !controller.isPlaying {
            Image(systemName: "play.fill")
                .font(.system(size: 66, weight: .semibold))
                .foregroundStyle(.white).shadow(radius: 8).accessibilityHidden(true)
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: dismiss) {
                    Image(systemName: "chevron.left").font(.headline).frame(width: 44, height: 44)
                        .background(.black.opacity(0.5), in: Circle())
                }
                .accessibilityLabel("Quay lại")
                Spacer()
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 7) {
                Text(movie.title).font(.title3.weight(.heavy)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(episodeDisplayName)  •  \(index + 1)/\(total)")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.78)).lineLimit(2)
                Text("Vuốt để đổi tập • chạm đúp trái/phải tua 5s • giữ để xem 2x")
                    .font(.footnote).foregroundStyle(.white.opacity(0.9)).fixedSize(horizontal: false, vertical: true)
                if controller.duration > 0 {
                    Slider(value: Binding(get: { controller.position }, set: { controller.seek(to: $0) }), in: 0...controller.duration)
                        .tint(CineVietTheme.accent).accessibilityLabel("Tiến độ phát")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 54)
        .padding(.bottom, 38)
        .opacity(controlsVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.22), value: controlsVisible)
        .allowsHitTesting(controlsVisible)
    }

    private var speedChip: some View {
        VStack { HStack { Spacer(); Label("2x", systemImage: "forward.fill").font(.subheadline.bold()).padding(.horizontal, 12).padding(.vertical, 8).background(.black.opacity(0.62), in: Capsule()) }; Spacer() }
            .foregroundStyle(.white).padding(.horizontal, 20).padding(.top, 96).allowsHitTesting(false)
            .accessibilityLabel("Tốc độ hai lần")
    }

    private func seekFeedbackView(_ seconds: Int) -> some View {
        HStack {
            if seconds > 0 { Spacer() }
            Label(seconds < 0 ? "−5 giây" : "+5 giây", systemImage: seconds < 0 ? "gobackward.5" : "goforward.5")
                .font(.headline.bold()).padding(.horizontal, 18).padding(.vertical, 12)
                .background(.black.opacity(0.62), in: Capsule()).foregroundStyle(.white)
            if seconds < 0 { Spacer() }
        }
        .padding(.horizontal, 42).transition(.opacity).allowsHitTesting(false)
    }

    private func tapGesture(viewWidth: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in seek(value.location.x < viewWidth / 2 ? -5 : 5) }
            .exclusively(before: SpatialTapGesture().onEnded { _ in
                controlsVisible ? togglePlayback() : showControls(autoHide: true)
            })
    }

    private var longPressGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in if case .second(true, _) = value { controller.setFastForward(true) } }
            .onEnded { _ in controller.setFastForward(false) }
    }

    private var episodeDisplayName: String {
        let value = episode.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Tập \(index + 1)" : value
    }

    private func togglePlayback() {
        controller.setFastForward(false)
        controller.toggle()
        showControls(autoHide: true)
    }

    private func seek(_ seconds: Int) {
        controller.seek(by: Double(seconds))
        withAnimation(.easeOut(duration: 0.12)) { seekFeedback = seconds }
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 750_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.12)) { seekFeedback = nil }
        }
    }

    private func showControls(autoHide: Bool) {
        controlsVisible = true
        if autoHide { scheduleHide() } else { hideTask?.cancel() }
    }

    private func scheduleHide() {
        hideTask?.cancel()
        guard controller.isPlaying else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled, controller.isPlaying else { return }
            controlsVisible = false
        }
    }
}

@MainActor
private final class ShortEpisodeController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var isLoading = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isFastForwarding = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var position = 0.0
    @Published private(set) var duration = 0.0
    private let episode: EpisodeItem
    private var shouldAutoplay = false
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var timeoutTask: Task<Void, Never>?
    private var wasPlayingBeforeFastForward = false

    init(episode: EpisodeItem) { self.episode = episode }

    func activate() {
        shouldAutoplay = true
        if player == nil { reload(autoplay: true) } else if errorMessage == nil { play() }
    }

    func deactivate(release: Bool = false) {
        shouldAutoplay = false
        setFastForward(false)
        pause()
        if release { tearDown() }
    }

    func reload(autoplay: Bool = true) {
        tearDown()
        shouldAutoplay = autoplay
        guard let url = Self.streamURL(episode.linkM3u8) else {
            errorMessage = "Đường dẫn tập không hợp lệ"
            return
        }
        isLoading = true
        errorMessage = nil
        let item = AVPlayerItem(url: url)
        let next = AVPlayer(playerItem: item)
        player = next
        statusObserver = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.timeoutTask?.cancel()
                    self.isLoading = false
                    if self.shouldAutoplay { self.play() }
                case .failed:
                    self.failPlayback()
                default: break
                }
            }
        }
        timeObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self, weak next] time in
            guard let self, let next else { return }
            self.position = time.seconds.isFinite ? max(0, time.seconds) : 0
            let seconds = item.duration.seconds
            self.duration = seconds.isFinite ? max(0, seconds) : 0
            self.isPlaying = next.timeControlStatus == .playing
        }
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self, weak next] _ in
            next?.seek(to: .zero) { _ in Task { @MainActor in if self?.shouldAutoplay == true { next?.play() } } }
        }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 18_000_000_000)
            guard !Task.isCancelled, self?.isLoading == true else { return }
            self?.failPlayback()
        }
    }

    func play() { guard errorMessage == nil else { return }; player?.play(); isPlaying = true }
    func pause() { player?.pause(); isPlaying = false }
    func toggle() { isPlaying ? pause() : play() }

    func setFastForward(_ enabled: Bool) {
        guard let player, errorMessage == nil, isFastForwarding != enabled else { return }
        if enabled {
            wasPlayingBeforeFastForward = isPlaying
            isFastForwarding = true
            player.rate = 2
            isPlaying = true
        } else {
            isFastForwarding = false
            player.rate = wasPlayingBeforeFastForward ? 1 : 0
            isPlaying = wasPlayingBeforeFastForward
            wasPlayingBeforeFastForward = false
        }
    }

    func seek(by seconds: Double) { seek(to: position + seconds) }
    func seek(to seconds: Double) {
        guard let player else { return }
        let upper = duration > 0 ? duration : max(0, seconds)
        let target = min(max(0, seconds), upper)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        position = target
    }

    private func failPlayback() {
        timeoutTask?.cancel()
        isLoading = false
        isPlaying = false
        errorMessage = "Không thể phát tập này"
        player?.pause()
    }

    private func tearDown() {
        timeoutTask?.cancel()
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
        statusObserver = nil
        player?.pause()
        player = nil
        isLoading = false
        isPlaying = false
        isFastForwarding = false
        wasPlayingBeforeFastForward = false
        position = 0
        duration = 0
    }

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
