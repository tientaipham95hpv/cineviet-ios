import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var isBuffering = false
    @Published private(set) var resumePosition: Double?
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentEpisode: EpisodeItem
    @Published private(set) var currentServer: EpisodeServer
    @Published private(set) var selectedAudioKey: String?
    @Published var selectedSubtitleLanguage: String
    @Published private(set) var overlaySubtitle: String?
    @Published private(set) var isPlaying = false
    @Published var playbackPosition: Double = 0
    @Published private(set) var playbackDuration: Double = 1
    @Published var isAutoPlayEnabled: Bool {
        didSet { defaults.set(isAutoPlayEnabled, forKey: autoPlayPreferenceKey) }
    }

    let movie: Movie
    let player = AVPlayer()

    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var subtitleTask: Task<Void, Never>?
    private var historyObserver: Any?
    private var resumeTask: Task<Void, Never>?
    private var playbackEndObserver: NSObjectProtocol?
    private var controlsTimeObserver: Any?
    private let defaults: UserDefaults
    private let watchHistoryService: WatchHistoryServicing
    private var lastSavedPosition: Double = 0
    private var serverPreferenceKey: String { "cineviet.player.server.\(movie.id)" }
    private var episodePreferenceKey: String { "cineviet.player.episode.\(movie.id)" }
    private var autoPlayPreferenceKey: String { "cineviet.player.autoplay" }
    var availableAudio: [EpisodeAudioSource] { currentEpisode.audioSources }
    var availableSubtitles: [EpisodeSubtitleTrack] { currentEpisode.subtitles }

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing, defaults: UserDefaults = .standard) {
        self.movie = movie
        self.defaults = defaults
        self.watchHistoryService = watchHistoryService
        let preferredServerName = defaults.string(forKey: "cineviet.player.server.\(movie.id)")
        let restoredServer = movie.episodes.first(where: { $0.name == preferredServerName }) ?? server
        let preferredEpisodeId = defaults.string(forKey: "cineviet.player.episode.\(movie.id)")
        currentServer = restoredServer
        currentEpisode = restoredServer.items.first(where: { $0.id == preferredEpisodeId }) ?? episode
        selectedAudioKey = defaults.string(forKey: "cineviet.player.audio.\(movie.id)")
        selectedSubtitleLanguage = defaults.string(forKey: "cineviet.player.subtitle.\(movie.id)") ?? "vi"
        isAutoPlayEnabled = defaults.object(forKey: "cineviet.player.autoplay") as? Bool ?? true
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate }
        }
    }

    deinit {
        itemObservation?.invalidate()
        timeControlObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let historyObserver { player.removeTimeObserver(historyObserver) }
        if let controlsTimeObserver { player.removeTimeObserver(controlsTimeObserver) }
        subtitleTask?.cancel()
        resumeTask?.cancel()
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
    }

    func start() {
        configureAudioSession()
        installPlaybackEndObserver()
        load(currentEpisode, server: currentServer)
        installControlsObserver()
    }

    func stop() {
        player.pause()
        itemObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        saveProgress()
        if let historyObserver { player.removeTimeObserver(historyObserver); self.historyObserver = nil }
        if let controlsTimeObserver { player.removeTimeObserver(controlsTimeObserver); self.controlsTimeObserver = nil }
        subtitleTask?.cancel()
        resumeTask?.cancel()
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
    }

    func play(_ episode: EpisodeItem, server: EpisodeServer) {
        currentEpisode = episode
        currentServer = server
        persistPlaybackSelection()
        lastSavedPosition = 0
        load(episode, server: server)
    }

    var nextEpisode: EpisodeItem? {
        guard let index = currentServer.items.firstIndex(where: { $0.id == currentEpisode.id }) else { return nil }
        let nextIndex = currentServer.items.index(after: index)
        guard nextIndex < currentServer.items.endIndex else { return nil }
        return currentServer.items[nextIndex]
    }

    func playNextEpisode() {
        guard let nextEpisode else { return }
        play(nextEpisode, server: currentServer)
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing { player.pause() } else { player.play() }
        isPlaying = player.timeControlStatus != .playing
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: max(0, seconds), preferredTimescale: 600))
    }

    func skip(_ seconds: Double) { seek(to: playbackPosition + seconds) }

    private func installControlsObserver() {
        if let controlsTimeObserver { player.removeTimeObserver(controlsTimeObserver) }
        controlsTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            self.playbackPosition = time.seconds.isFinite ? time.seconds : 0
            let duration = self.player.currentItem?.duration.seconds ?? 0
            self.playbackDuration = duration.isFinite && duration > 0 ? duration : 1
            self.isPlaying = self.player.timeControlStatus == .playing
        }
    }

    func selectAudio(_ source: EpisodeAudioSource?) {
        selectedAudioKey = source?.key
        defaults.set(source?.key, forKey: "cineviet.player.audio.\(movie.id)")
        load(currentEpisode, server: currentServer)
    }

    func selectSubtitle(_ language: String) {
        selectedSubtitleLanguage = language
        defaults.set(language, forKey: "cineviet.player.subtitle.\(movie.id)")
        applyEmbeddedSubtitleSelection()
        startExternalSubtitleOverlay(for: currentEpisode)
    }

    private func load(_ episode: EpisodeItem, server: EpisodeServer) {
        itemObservation?.invalidate()
        overlaySubtitle = nil
        subtitleTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        errorMessage = nil
        isLoading = true

        guard let url = Self.directMediaURL(for: episode, audioKey: selectedAudioKey) else {
            player.replaceCurrentItem(with: nil)
            isLoading = false
            errorMessage = episode.linkEmbed.isEmpty
                ? "Tập phim chưa có nguồn phát trực tiếp."
                : "Nguồn này chỉ hỗ trợ trình phát nhúng và chưa thể phát bằng AVPlayer."
            return
        }

        let item = AVPlayerItem(url: url)
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false
                    self.errorMessage = nil
                    self.applyEmbeddedSubtitleSelection()
                    self.startExternalSubtitleOverlay(for: episode)
                    self.resumePlaybackIfNeeded(for: episode)
                case .failed:
                    self.isLoading = false
                    self.errorMessage = item.error?.localizedDescription ?? "Không thể mở nguồn phát."
                case .unknown:
                    self.isLoading = true
                @unknown default:
                    self.isLoading = false
                    self.errorMessage = "Trạng thái trình phát không được hỗ trợ."
                }
            }
        }
        player.replaceCurrentItem(with: item)
    }

    private func persistPlaybackSelection() {
        defaults.set(currentServer.name, forKey: serverPreferenceKey)
        defaults.set(currentEpisode.id, forKey: episodePreferenceKey)
    }

    private func installPlaybackEndObserver() {
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, notification.object as? AVPlayerItem === self.player.currentItem else { return }
                self.saveProgress()
                if self.isAutoPlayEnabled { self.playNextEpisode() }
            }
        }
    }

    private func resumePlaybackIfNeeded(for episode: EpisodeItem) {
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            guard let self else { return }
            let resume = await self.watchHistoryService.resume(movieId: self.movie.id)
            guard !Task.isCancelled else { return }
            if let resume,
               (resume.episodeName == episode.name || resume.streamURL == Self.directMediaURL(for: episode, audioKey: self.selectedAudioKey)?.absoluteString),
               resume.positionSeconds > 3 {
                await self.player.seek(to: CMTime(seconds: resume.positionSeconds, preferredTimescale: 600))
                self.lastSavedPosition = resume.positionSeconds
                self.resumePosition = resume.positionSeconds
            }
            self.installHistoryObserver()
            self.player.play()
        }
    }

    private func installHistoryObserver() {
        if let historyObserver { player.removeTimeObserver(historyObserver) }
        historyObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main
        ) { [weak self] _ in self?.saveProgress() }
    }

    private func saveProgress() {
        guard let item = player.currentItem else { return }
        let position = player.currentTime().seconds
        let duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, position >= 3,
              abs(position - lastSavedPosition) >= 5 else { return }
        lastSavedPosition = position
        let serverIndex = movie.episodes.firstIndex(where: { $0.name == currentServer.name }) ?? 0
        let service = watchHistoryService
        let movie = movie
        let server = currentServer
        let episode = currentEpisode
        Task { await service.save(movie: movie, server: server, serverIndex: serverIndex, episode: episode, position: position, duration: duration) }
    }

    private func startExternalSubtitleOverlay(for episode: EpisodeItem) {
        overlaySubtitle = nil
        subtitleTask?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        guard selectedSubtitleLanguage != "off",
              let track = episode.subtitles.first(where: { $0.lang.lowercased() == selectedSubtitleLanguage.lowercased() }),
              let url = subtitleURL(track.url) else { return }
        subtitleTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let source = String(data: data, encoding: .utf8) else { return }
                let cues = SubtitleParser.parse(source, format: track.format)
                guard !cues.isEmpty else { return }
                self.timeObserver = self.player.addPeriodicTimeObserver(
                    forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
                ) { [weak self] time in
                    guard let self else { return }
                    let seconds = time.seconds
                    self.overlaySubtitle = cues.first(where: { seconds >= $0.start && seconds < $0.end })?.text
                }
            } catch { }
        }
    }

    private func subtitleURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") { return URL(string: "https:\(value)") }
        if let url = URL(string: value), url.scheme == "http" || url.scheme == "https" { return url }
        return URL(string: value, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }

    private func applyEmbeddedSubtitleSelection() {
        guard let item = player.currentItem,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        if selectedSubtitleLanguage == "off" {
            item.select(nil, in: group)
            return
        }
        let option = group.options.first { option in
            let language = option.extendedLanguageTag ?? option.locale?.language.languageCode?.identifier
            return language?.lowercased().hasPrefix(selectedSubtitleLanguage.lowercased()) == true
        }
        item.select(option, in: group)
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // AVPlayer can still attempt playback; surface only media failures.
        }
    }

    static func directMediaURL(for episode: EpisodeItem, audioKey: String? = nil) -> URL? {
        let selectedAudio = audioKey.flatMap { key in
            episode.audioSources.first { $0.key == key }
        }
        let originalAudio = episode.audioSources.first { $0.key.lowercased() == "original" }
        // The episode HLS URL is the canonical playback source. Audio variants are
        // only fallbacks when the backend does not provide link_m3u8.
        let candidates = [episode.linkM3u8, selectedAudio?.url, originalAudio?.url, episode.audioSources.first?.url]
        let raw = candidates.compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? ""
        guard !raw.isEmpty else { return nil }
        if raw.hasPrefix("//") { return URL(string: "https:\(raw)") }
        if let absolute = URL(string: raw), absolute.scheme == "http" || absolute.scheme == "https" {
            return absolute
        }
        return URL(string: raw, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }
}
