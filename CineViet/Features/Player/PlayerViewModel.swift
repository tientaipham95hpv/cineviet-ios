import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentEpisode: EpisodeItem
    @Published private(set) var currentServer: EpisodeServer
    @Published private(set) var selectedAudioKey: String?
    @Published var selectedSubtitleLanguage: String
    @Published private(set) var overlaySubtitle: String?

    let movie: Movie
    let player = AVPlayer()

    private var itemObservation: NSKeyValueObservation?
    private var timeObserver: Any?
    private var subtitleTask: Task<Void, Never>?
    private let defaults: UserDefaults
    var availableAudio: [EpisodeAudioSource] { currentEpisode.audioSources }
    var availableSubtitles: [EpisodeSubtitleTrack] { currentEpisode.subtitles }

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, defaults: UserDefaults = .standard) {
        self.movie = movie
        currentServer = server
        currentEpisode = episode
        self.defaults = defaults
        selectedAudioKey = defaults.string(forKey: "cineviet.player.audio.\(movie.id)")
        selectedSubtitleLanguage = defaults.string(forKey: "cineviet.player.subtitle.\(movie.id)") ?? "vi"
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
    }

    deinit {
        itemObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        subtitleTask?.cancel()
    }

    func start() {
        configureAudioSession()
        load(currentEpisode, server: currentServer)
    }

    func stop() {
        player.pause()
        itemObservation?.invalidate()
        if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
        subtitleTask?.cancel()
    }

    func play(_ episode: EpisodeItem, server: EpisodeServer) {
        currentEpisode = episode
        currentServer = server
        load(episode, server: server)
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
                    self.player.play()
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
        let candidates = [selectedAudio?.url, originalAudio?.url, episode.audioSources.first?.url, episode.linkM3u8]
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
