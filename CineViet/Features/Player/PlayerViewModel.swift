import AVFoundation
import Combine
import Foundation
import UIKit

struct EmbeddedMediaOption: Identifiable {
    let id: String
    let displayName: String
    let languageTag: String?
    fileprivate let option: AVMediaSelectionOption
}

struct PlaybackCandidate: Identifiable, Equatable {
    let id: String
    let url: URL
    let server: EpisodeServer
    let episode: EpisodeItem
    let label: String
}

@MainActor
final class PlayerViewModel: ObservableObject {
    struct SubtitleStyle: Equatable, Codable {
        var font: String = "Lora"
        var size: Double
        var colorHex: String
        var bottom: Double
        static let vietnamese = SubtitleStyle(size: 30, colorHex: "FFFFFF", bottom: 7)
        static let english = SubtitleStyle(size: 25, colorHex: "FFFF99", bottom: 20)
    }
    @Published private(set) var isLoading = true
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackNotice: String?
    @Published private(set) var currentEpisode: EpisodeItem
    @Published private(set) var currentServer: EpisodeServer
    @Published private(set) var selectedAudioKey: String?
    @Published var selectedSubtitleLanguage: String
    @Published private(set) var embeddedAudioOptions: [EmbeddedMediaOption] = []
    @Published private(set) var embeddedSubtitleOptions: [EmbeddedMediaOption] = []
    @Published private(set) var selectedEmbeddedAudioID: String?
    /// External subtitle cues keyed by language. Keeping the tracks separate
    /// avoids confusing a multiline cue with the boundary between VI and EN.
    @Published private(set) var overlaySubtitles: [String: String] = [:]
    @Published var subtitleStyles: [String: SubtitleStyle] = ["vi": .vietnamese, "en": .english]
    var subtitleStyle: SubtitleStyle { subtitleStyles[selectedSubtitleLanguage == "en" ? "en" : "vi"] ?? .vietnamese }
    @Published private(set) var isPlaying = false
    @Published var playbackPosition: Double = 0
    @Published private(set) var playbackDuration: Double = 1
    @Published private(set) var activeSourceLabel = "Đang chuẩn bị nguồn"
    @Published private(set) var autoNextCountdown: Int?
    @Published var isAutoPlayEnabled: Bool {
        didSet { defaults.set(isAutoPlayEnabled, forKey: autoPlayPreferenceKey) }
    }

    let movie: Movie
    let player = AVPlayer()
    var servers: [EpisodeServer] { movie.episodes }
    var availableAudio: [EpisodeAudioSource] { currentEpisode.audioSources.filter { Self.normalizedURL($0.url) != nil } }
    var availableSubtitles: [EpisodeSubtitleTrack] { currentEpisode.subtitles.filter { Self.normalizedURL($0.url) != nil } }
    var currentEpisodeIndex: Int? { currentServer.items.firstIndex(where: { Self.sameEpisode($0, currentEpisode) }) }
    var previousEpisode: EpisodeItem? {
        guard let index = currentEpisodeIndex, index > 0 else { return nil }
        return currentServer.items[index - 1]
    }
    var nextEpisode: EpisodeItem? {
        guard let index = currentEpisodeIndex, index + 1 < currentServer.items.count else { return nil }
        return currentServer.items[index + 1]
    }

    private let defaults: UserDefaults
    private let watchHistoryService: WatchHistoryServicing
    private var itemObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var controlsTimeObserver: Any?
    private var historyObserver: Any?
    private var subtitleTimeObserver: Any?
    private var playbackEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var audioInterruptionObserver: NSObjectProtocol?
    private var audioRouteObserver: NSObjectProtocol?
    private var subtitleTask: Task<Void, Never>?
    private var mediaSelectionTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var autoNextTask: Task<Void, Never>?
    private var embeddedAudioGroup: AVMediaSelectionGroup?
    private var embeddedSubtitleGroup: AVMediaSelectionGroup?
    private var candidateQueue: [PlaybackCandidate] = []
    private var candidateIndex = 0
    private var pendingResumePosition: Double?
    private var shouldFetchRemoteResume = true
    private var lastSavedPosition: Double = 0
    private var started = false
    private let offlineURL: URL?

    private var serverPreferenceKey: String { "cineviet.player.server.\(movie.id)" }
    private var episodePreferenceKey: String { "cineviet.player.episode.\(movie.id)" }
    private var audioPreferenceKey: String { "cineviet.player.audio.\(movie.id)" }
    private var embeddedAudioPreferenceKey: String { "cineviet.player.audio.embedded.\(movie.id)" }
    private var subtitlePreferenceKey: String { "cineviet.player.subtitle.\(movie.id)" }
    private var autoPlayPreferenceKey: String { "cineviet.player.autoplay" }
    private var subtitleStylePreferenceKey: String { "cineviet.player.subtitle.style.\(movie.id)" }

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing, offlineURL: URL? = nil, defaults: UserDefaults = .standard) {
        self.movie = movie
        self.defaults = defaults
        self.watchHistoryService = watchHistoryService
        self.offlineURL = offlineURL
        // The launch contract is authoritative: an episode tapped in Detail or
        // resolved from Continue Watching must not be replaced by stale local
        // preferences from a previous session.
        currentServer = server
        currentEpisode = server.items.first(where: { Self.sameEpisode($0, episode) }) ?? episode
        let savedAudio = defaults.string(forKey: "cineviet.player.audio.\(movie.id)")
        selectedAudioKey = episode.audioSources.contains(where: { $0.key == savedAudio && Self.normalizedURL($0.url) != nil }) ? savedAudio : Self.defaultAudioKey(for: episode)
        selectedEmbeddedAudioID = defaults.string(forKey: "cineviet.player.audio.embedded.\(movie.id)")
        selectedSubtitleLanguage = defaults.string(forKey: "cineviet.player.subtitle.\(movie.id)") ?? "vi"
        let subtitleStyleKey = "cineviet.player.subtitle.style.\(movie.id)"
        if let data = defaults.data(forKey: subtitleStyleKey), let saved = try? JSONDecoder().decode([String: SubtitleStyle].self, from: data) { subtitleStyles = ["vi": saved["vi"] ?? .vietnamese, "en": saved["en"] ?? .english] }
        isAutoPlayEnabled = defaults.object(forKey: "cineviet.player.autoplay") as? Bool ?? true
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
        player.automaticallyWaitsToMinimizeStalling = true
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self?.isPlaying = player.rate > 0
            }
        }
    }

    deinit {
        itemObservation?.invalidate(); timeControlObservation?.invalidate()
        if let controlsTimeObserver { player.removeTimeObserver(controlsTimeObserver) }
        if let historyObserver { player.removeTimeObserver(historyObserver) }
        if let subtitleTimeObserver { player.removeTimeObserver(subtitleTimeObserver) }
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver) }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver) }
        if let audioInterruptionObserver { NotificationCenter.default.removeObserver(audioInterruptionObserver) }
        if let audioRouteObserver { NotificationCenter.default.removeObserver(audioRouteObserver) }
    }

    func start() {
        guard !started else { return }
        started = true
        configureAudioSession()
        installObservers()
        rebuildQueueAndLoad(preserving: nil, includeEquivalentServers: true)
    }

    func stop() {
        flushProgress()
        player.pause()
        started = false
        cancelAsyncWork()
        removePlayerObservers()
        deactivateAudioSession()
    }

    func applicationDidEnterBackground() {
        flushProgress()
        // Playback may continue only through an active system PiP session.
        // Otherwise pausing avoids invisible audio/video playback.
        if !player.isExternalPlaybackActive { player.pause() }
    }

    func applicationWillEnterForeground() {
        configureAudioSession()
    }

    func flushProgress() { saveProgress(force: true) }

    func togglePlayback() {
        autoNextTask?.cancel(); autoNextCountdown = nil
        if player.rate > 0 { player.pause(); isPlaying = false }
        else { player.play(); isPlaying = true }
    }

    func seek(to seconds: Double) {
        let maximum = playbackDuration > 1 ? playbackDuration : max(seconds, 1)
        let target = min(max(0, seconds), maximum)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        playbackPosition = target
    }

    func skip(_ seconds: Double) { seek(to: playbackPosition + seconds) }

    func retry() {
        errorMessage = nil
        candidateIndex = 0
        pendingResumePosition = playbackPosition > 3 ? playbackPosition : nil
        shouldFetchRemoteResume = false
        loadCurrentCandidate()
    }

    func play(_ episode: EpisodeItem, server: EpisodeServer) {
        saveProgress(force: true)
        currentServer = server
        currentEpisode = episode
        selectedAudioKey = restoredAudioKey(validFor: episode)
        persistSelection()
        lastSavedPosition = 0
        shouldFetchRemoteResume = true
        pendingResumePosition = nil
        rebuildQueueAndLoad(preserving: nil, includeEquivalentServers: true)
    }

    func playServer(named name: String) {
        guard let server = movie.episodes.first(where: { $0.name == name }) else { return }
        let equivalent = server.items.first(where: { Self.sameEpisode($0, currentEpisode) && !Self.urls(for: $0, audioKey: selectedAudioKey).isEmpty })
        guard let episode = equivalent ?? server.items.first(where: { !Self.urls(for: $0, audioKey: selectedAudioKey).isEmpty }) else {
            showNotice("Máy chủ này chưa có nguồn phát trực tiếp.")
            return
        }
        play(episode, server: server)
    }

    func playPreviousEpisode() { if let previousEpisode { play(previousEpisode, server: currentServer) } }
    func playNextEpisode() { if let nextEpisode { play(nextEpisode, server: currentServer) } }

    func selectAudio(_ source: EpisodeAudioSource?) {
        pendingResumePosition = playbackPosition
        shouldFetchRemoteResume = false
        selectedAudioKey = source?.key
        defaults.set(source?.key, forKey: audioPreferenceKey)
        rebuildQueueAndLoad(preserving: pendingResumePosition, includeEquivalentServers: true)
        announce(source == nil ? "Đã chọn âm thanh HLS chính" : "Đã chọn âm thanh \(source?.label ?? "")")
    }

    func selectEmbeddedAudio(_ track: EmbeddedMediaOption?) {
        guard let item = player.currentItem, let group = embeddedAudioGroup else { return }
        item.select(track?.option, in: group)
        selectedEmbeddedAudioID = track?.id
        defaults.set(track?.id, forKey: embeddedAudioPreferenceKey)
        announce(track == nil ? "Đã chọn âm thanh mặc định trong nguồn" : "Đã chọn âm thanh \(track?.displayName ?? "")")
    }

    func selectSubtitle(_ language: String) {
        selectedSubtitleLanguage = language
        defaults.set(language, forKey: subtitlePreferenceKey)
        applyEmbeddedSubtitleSelection()
        startExternalSubtitleOverlay(for: currentEpisode)
        showNotice(language == "off" ? "Đã tắt phụ đề" : "Đã chọn phụ đề")
        announce(language == "off" ? "Đã tắt phụ đề" : "Đã thay đổi phụ đề")
    }

    func updateSubtitleStyle(_ style: SubtitleStyle, language: String? = nil) {
        let key = language ?? (selectedSubtitleLanguage == "en" ? "en" : "vi")
        subtitleStyles[key] = style
        if let data = try? JSONEncoder().encode(subtitleStyles) { defaults.set(data, forKey: subtitleStylePreferenceKey) }
        objectWillChange.send()
    }

    func resetSubtitleStyles() {
        subtitleStyles = ["vi": .vietnamese, "en": .english]
        if let data = try? JSONEncoder().encode(subtitleStyles) { defaults.set(data, forKey: subtitleStylePreferenceKey) }
        objectWillChange.send()
    }

    func dismissNotice() { playbackNotice = nil; noticeTask?.cancel() }

    private func rebuildQueueAndLoad(preserving position: Double?, includeEquivalentServers: Bool) {
        pendingResumePosition = position
        candidateQueue = buildCandidateQueue(includeEquivalentServers: includeEquivalentServers)
        candidateIndex = 0
        loadCurrentCandidate()
    }

    private func buildCandidateQueue(includeEquivalentServers: Bool) -> [PlaybackCandidate] {
        if let offlineURL {
            // App v2 treats each API audio source as a complete alternate HLS
            // playback URL, not as an AVPlayer embedded-audio selection. The
            // offline package mirrors that layout, so a selected downloaded
            // audio playlist must replace the main local playlist.
            if let selectedAudioKey,
               let selected = currentEpisode.audioSources.first(where: { $0.key == selectedAudioKey }),
               let selectedURL = Self.normalizedURL(selected.url) {
                return [PlaybackCandidate(id: selectedURL.absoluteString, url: selectedURL, server: currentServer, episode: currentEpisode, label: "Bản tải xuống • \(selected.label.isEmpty ? selected.key : selected.label)")]
            }
            return [PlaybackCandidate(id: offlineURL.absoluteString, url: offlineURL, server: currentServer, episode: currentEpisode, label: "Bản tải xuống")]
        }
        var result: [PlaybackCandidate] = []
        var seen = Set<String>()
        func append(server: EpisodeServer, episode: EpisodeItem) {
            for source in Self.urlSources(for: episode, audioKey: selectedAudioKey) where seen.insert(source.url.absoluteString).inserted {
                result.append(PlaybackCandidate(id: source.url.absoluteString, url: source.url, server: server, episode: episode, label: "\(server.name) • \(source.label)"))
            }
        }
        append(server: currentServer, episode: currentEpisode)
        if includeEquivalentServers {
            for server in movie.episodes where server.name != currentServer.name {
                if let episode = server.items.first(where: { Self.sameEpisode($0, currentEpisode) }) { append(server: server, episode: episode) }
            }
        }
        return result
    }

    private func loadCurrentCandidate() {
        clearCurrentItemState()
        guard candidateIndex < candidateQueue.count else {
            player.replaceCurrentItem(with: nil)
            isLoading = false
            errorMessage = currentEpisode.linkEmbed.isEmpty
                ? "Không tìm thấy nguồn phát trực tiếp cho tập này."
                : "Tập này chỉ có nguồn nhúng, AVPlayer không hỗ trợ."
            return
        }
        let candidate = candidateQueue[candidateIndex]
        if candidate.server.name != currentServer.name || !Self.sameEpisode(candidate.episode, currentEpisode) {
            currentServer = candidate.server; currentEpisode = candidate.episode; persistSelection()
        }
        activeSourceLabel = candidate.label
        isLoading = true
        let item: AVPlayerItem
        if candidate.url.isFileURL {
            item = AVPlayerItem(url: candidate.url)
        } else {
            // CineViet playback endpoints require a trusted browser/app
            // provenance header. AVURLAsset propagates these headers to HLS
            // playlist, redirect, key and segment requests, unlike the plain
            // AVPlayerItem(url:) initializer.
            let headers = [
                "Origin": AppEnvironment.siteBaseURL.absoluteString,
                "Referer": AppEnvironment.siteBaseURL.appendingPathComponent("").absoluteString,
                "User-Agent": AppEnvironment.userAgent
            ]
            let asset = AVURLAsset(url: candidate.url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
            item = AVPlayerItem(asset: asset)
        }
        observe(item: item, candidate: candidate)
        player.replaceCurrentItem(with: item)
        player.play()
    }

    private func observe(item: AVPlayerItem, candidate: PlaybackCandidate) {
        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.isLoading = false; self.errorMessage = nil
                    self.discoverMediaSelections(for: item, episode: candidate.episode)
                    self.resumePlaybackIfNeeded(for: candidate)
                case .failed: self.failCurrentCandidate(item.error?.localizedDescription)
                case .unknown: self.isLoading = true
                @unknown default: self.failCurrentCandidate("Trạng thái nguồn không được hỗ trợ")
                }
            }
        }
        itemFailureObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] note in
            Task { @MainActor in self?.failCurrentCandidate((note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription) }
        }
    }

    private func failCurrentCandidate(_ reason: String?) {
        guard candidateIndex < candidateQueue.count else { return }
        let position = player.currentTime().seconds
        if position.isFinite && position > 3 { pendingResumePosition = position }
        shouldFetchRemoteResume = false
        candidateIndex += 1
        if candidateIndex < candidateQueue.count {
            showNotice("Nguồn bị lỗi, đang tự chuyển sang nguồn dự phòng…")
            loadCurrentCandidate()
        } else {
            isLoading = false
            errorMessage = reason ?? "Tất cả nguồn phát trực tiếp đều không hoạt động."
            showNotice("Đã thử toàn bộ nguồn tương đương.")
        }
    }

    private func clearCurrentItemState() {
        itemObservation?.invalidate(); itemObservation = nil
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver); self.itemFailureObserver = nil }
        subtitleTask?.cancel(); mediaSelectionTask?.cancel(); overlaySubtitles = [:]
        embeddedAudioOptions = []; embeddedSubtitleOptions = []
        embeddedAudioGroup = nil; embeddedSubtitleGroup = nil
        if let subtitleTimeObserver { player.removeTimeObserver(subtitleTimeObserver); self.subtitleTimeObserver = nil }
        errorMessage = nil; isLoading = false; isPlaying = false
    }

    private func installObservers() {
        controlsTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            self.playbackPosition = time.seconds.isFinite ? time.seconds : 0
            let duration = self.player.currentItem?.duration.seconds ?? 0
            self.playbackDuration = duration.isFinite && duration > 0 ? duration : 1
            self.isPlaying = self.player.rate > 0
        }
        historyObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 10, preferredTimescale: 1), queue: .main) { [weak self] _ in self?.saveProgress(force: false) }
        audioInterruptionObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleAudioInterruption(note) }
        }
        audioRouteObserver = NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            Task { @MainActor in self?.handleAudioRouteChange(note) }
        }
        playbackEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] note in
            Task { @MainActor in
                guard let self, note.object as? AVPlayerItem === self.player.currentItem else { return }
                self.saveProgress(force: true)
                if self.isAutoPlayEnabled, self.nextEpisode != nil { self.beginAutoNextCountdown() }
            }
        }
    }

    private func removePlayerObservers() {
        itemObservation?.invalidate(); itemObservation = nil
        if let controlsTimeObserver { player.removeTimeObserver(controlsTimeObserver); self.controlsTimeObserver = nil }
        if let historyObserver { player.removeTimeObserver(historyObserver); self.historyObserver = nil }
        if let subtitleTimeObserver { player.removeTimeObserver(subtitleTimeObserver); self.subtitleTimeObserver = nil }
        if let playbackEndObserver { NotificationCenter.default.removeObserver(playbackEndObserver); self.playbackEndObserver = nil }
        if let itemFailureObserver { NotificationCenter.default.removeObserver(itemFailureObserver); self.itemFailureObserver = nil }
        if let audioInterruptionObserver { NotificationCenter.default.removeObserver(audioInterruptionObserver); self.audioInterruptionObserver = nil }
        if let audioRouteObserver { NotificationCenter.default.removeObserver(audioRouteObserver); self.audioRouteObserver = nil }
    }

    private func resumePlaybackIfNeeded(for candidate: PlaybackCandidate) {
        resumeTask?.cancel()
        if let position = pendingResumePosition, position > 3 {
            pendingResumePosition = nil
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play(); return
        }
        guard offlineURL == nil, shouldFetchRemoteResume else { player.play(); return }
        shouldFetchRemoteResume = false
        resumeTask = Task { [weak self] in
            guard let self else { return }
            let resume = await self.watchHistoryService.resume(movieId: self.movie.id)
            guard !Task.isCancelled else { return }
            if let resume, (resume.episodeName == candidate.episode.name || resume.streamURL == candidate.url.absoluteString), resume.positionSeconds > 3 {
                await self.player.seek(to: CMTime(seconds: resume.positionSeconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
                self.lastSavedPosition = resume.positionSeconds
                self.showNotice("Tiếp tục từ \(Self.formatTime(resume.positionSeconds))")
            }
            self.player.play()
        }
    }

    private func beginAutoNextCountdown() {
        autoNextTask?.cancel()
        autoNextCountdown = 5
        autoNextTask = Task { [weak self] in
            for value in stride(from: 4, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                self?.autoNextCountdown = value
            }
            self?.autoNextCountdown = nil
            self?.playNextEpisode()
        }
    }

    func cancelAutoNext() { autoNextTask?.cancel(); autoNextCountdown = nil; showNotice("Đã hủy tự chuyển tập") }

    private func saveProgress(force: Bool) {
        guard offlineURL == nil, let item = player.currentItem else { return }
        let position = player.currentTime().seconds, duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, position >= 3 else { return }
        let delta = abs(position - lastSavedPosition)
        guard delta >= (force ? 0.75 : 5) else { return }
        lastSavedPosition = position
        let index = movie.episodes.firstIndex(where: { $0.name == currentServer.name }) ?? 0
        let service = watchHistoryService, movie = movie, server = currentServer, episode = currentEpisode
        Task { await service.save(movie: movie, server: server, serverIndex: index, episode: episode, position: position, duration: duration) }
    }

    private func showNotice(_ message: String) {
        playbackNotice = message; noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            self?.playbackNotice = nil
        }
    }

    private func startExternalSubtitleOverlay(for episode: EpisodeItem) {
        overlaySubtitles = [:]; subtitleTask?.cancel()
        if let subtitleTimeObserver { player.removeTimeObserver(subtitleTimeObserver); self.subtitleTimeObserver = nil }
        guard selectedSubtitleLanguage != "off" else { return }
        let tracks: [EpisodeSubtitleTrack]
        if selectedSubtitleLanguage == "dual" {
            tracks = ["vi", "en"].compactMap { code in episode.subtitles.first(where: { $0.lang.lowercased().hasPrefix(code) }) }
        } else if selectedSubtitleLanguage.hasPrefix("external:") {
            let identity = String(selectedSubtitleLanguage.dropFirst("external:".count))
            tracks = episode.subtitles.filter { $0.id == identity }
        } else {
            tracks = []
        }
        guard !tracks.isEmpty else { return }
        let expectedItem = player.currentItem
        subtitleTask = Task { [weak self, weak expectedItem] in
            guard let self, let expectedItem else { return }
            var cueSets: [(language: String, cues: [SubtitleCue])] = []
            for track in tracks {
                guard let url = self.subtitleURL(track.url) else { continue }
                do {
                    let data = try await Self.loadSubtitleData(from: url)
                    guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
                    let language = track.lang.lowercased().hasPrefix("en") ? "en" : "vi"
                    cueSets.append((language, SubtitleParser.parse(text, format: track.format)))
                } catch {
                    guard !Task.isCancelled, self.player.currentItem != nil else { return }
                    self.showNotice("Không thể tải phụ đề đã chọn.")
                    self.announce("Không thể tải phụ đề đã chọn")
                }
            }
            guard !Task.isCancelled, self.player.currentItem === expectedItem, !cueSets.isEmpty else { return }
            self.subtitleTimeObserver = self.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
                var active: [String: String] = [:]
                for cueSet in cueSets {
                    if let text = cueSet.cues.first(where: { time.seconds >= $0.start && time.seconds < $0.end })?.text,
                       !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        active[cueSet.language] = text
                    }
                }
                guard self?.player.currentItem === expectedItem else { return }
                self?.overlaySubtitles = active
            }
        }
    }

    private func applyEmbeddedSubtitleSelection() {
        guard let item = player.currentItem, let group = embeddedSubtitleGroup else { return }
        guard selectedSubtitleLanguage.hasPrefix("embedded:") else { item.select(nil, in: group); return }
        let id = String(selectedSubtitleLanguage.dropFirst("embedded:".count))
        let selected = embeddedSubtitleOptions.first(where: { $0.id == id })?.option
        item.select(selected, in: group)
    }

    private func discoverMediaSelections(for item: AVPlayerItem, episode: EpisodeItem) {
        mediaSelectionTask?.cancel()
        mediaSelectionTask = Task { [weak self, weak item] in
            guard let self, let item else { return }
            do {
                async let audible = item.asset.loadMediaSelectionGroup(for: .audible)
                async let legible = item.asset.loadMediaSelectionGroup(for: .legible)
                let (audioGroup, subtitleGroup) = try await (audible, legible)
                guard !Task.isCancelled, self.player.currentItem === item else { return }
                self.embeddedAudioGroup = audioGroup
                self.embeddedSubtitleGroup = subtitleGroup
                self.embeddedAudioOptions = self.options(from: audioGroup)
                self.embeddedSubtitleOptions = self.options(from: subtitleGroup)
                if let group = audioGroup {
                    let restored = self.embeddedAudioOptions.first(where: { $0.id == self.selectedEmbeddedAudioID })
                    if self.selectedEmbeddedAudioID != nil && restored == nil { self.selectedEmbeddedAudioID = nil }
                    if let restored { item.select(restored.option, in: group) }
                    else { self.selectedEmbeddedAudioID = item.currentMediaSelection.selectedMediaOption(in: group).map { self.optionIdentity($0) } }
                }
                self.revalidateSubtitleSelection(for: episode)
                self.applyEmbeddedSubtitleSelection()
                self.startExternalSubtitleOverlay(for: episode)
            } catch {
                guard !Task.isCancelled, self.player.currentItem === item else { return }
                self.revalidateSubtitleSelection(for: episode)
                self.startExternalSubtitleOverlay(for: episode)
            }
        }
    }

    private func options(from group: AVMediaSelectionGroup?) -> [EmbeddedMediaOption] {
        group?.options.map { EmbeddedMediaOption(id: optionIdentity($0), displayName: $0.displayName, languageTag: $0.extendedLanguageTag, option: $0) } ?? []
    }
    private func optionIdentity(_ option: AVMediaSelectionOption) -> String { "\(option.extendedLanguageTag ?? option.locale?.identifier ?? "und")|\(option.displayName)" }

    private func revalidateSubtitleSelection(for episode: EpisodeItem) {
        let external = availableSubtitles
        let vi = external.first { $0.lang.lowercased().hasPrefix("vi") }
        let en = external.first { $0.lang.lowercased().hasPrefix("en") }
        let valid: Bool
        if selectedSubtitleLanguage == "off" { valid = true }
        else if selectedSubtitleLanguage == "dual" { valid = vi != nil && en != nil }
        else if selectedSubtitleLanguage.hasPrefix("external:") { valid = external.contains { "external:\($0.id)" == selectedSubtitleLanguage } }
        else if selectedSubtitleLanguage.hasPrefix("embedded:") { valid = embeddedSubtitleOptions.contains { "embedded:\($0.id)" == selectedSubtitleLanguage } }
        else { valid = false }
        if !valid {
            if vi != nil && en != nil { selectedSubtitleLanguage = "dual" }
            else if let vi { selectedSubtitleLanguage = "external:\(vi.id)" }
            else if let first = external.first { selectedSubtitleLanguage = "external:\(first.id)" }
            else if let first = embeddedSubtitleOptions.first { selectedSubtitleLanguage = "embedded:\(first.id)" }
            else { selectedSubtitleLanguage = "off" }
            defaults.set(selectedSubtitleLanguage, forKey: subtitlePreferenceKey)
        }
    }

    private func subtitleURL(_ raw: String) -> URL? { Self.normalizedURL(raw) }
    private func persistSelection() { defaults.set(currentServer.name, forKey: serverPreferenceKey); defaults.set(currentEpisode.id, forKey: episodePreferenceKey) }
    private func restoredAudioKey(validFor episode: EpisodeItem) -> String? {
        let stored = defaults.string(forKey: audioPreferenceKey)
        return episode.audioSources.contains(where: { $0.key == stored && Self.normalizedURL($0.url) != nil }) ? stored : Self.defaultAudioKey(for: episode)
    }
    private func cancelAsyncWork() { subtitleTask?.cancel(); mediaSelectionTask?.cancel(); resumeTask?.cancel(); noticeTask?.cancel(); autoNextTask?.cancel() }
    private func announce(_ message: String) { UIAccessibility.post(notification: .announcement, argument: message) }
    nonisolated private static func loadSubtitleData(from url: URL) async throws -> Data {
        if url.isFileURL { return try await Task.detached { try Data(contentsOf: url) }.value }
        var request = URLRequest(url: url)
        request.setValue(AppEnvironment.siteBaseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(AppEnvironment.siteBaseURL.appendingPathComponent("").absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(AppEnvironment.userAgent, forHTTPHeaderField: "User-Agent")
        return try await URLSession.shared.data(for: request).0
    }
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .moviePlayback)
        try? session.setActive(true)
    }
    private func deactivateAudioSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    private func handleAudioInterruption(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            flushProgress(); player.pause(); showNotice("Phát phim đã tạm dừng do gián đoạn âm thanh")
        } else if let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
                  AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
            configureAudioSession(); player.play()
        }
    }
    private func handleAudioRouteChange(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        player.pause(); flushProgress(); showNotice("Đã tạm dừng vì thiết bị âm thanh bị ngắt kết nối")
    }

    static func directMediaURL(for episode: EpisodeItem, audioKey: String? = nil) -> URL? { urls(for: episode, audioKey: audioKey).first }
    static func urls(for episode: EpisodeItem, audioKey: String?) -> [URL] { urlSources(for: episode, audioKey: audioKey).map(\.url) }
    private static func urlSources(for episode: EpisodeItem, audioKey: String?) -> [(url: URL, label: String)] {
        var values: [(String, String)] = []
        // A selected audio variant is an explicit user choice.  The canonical
        // link_m3u8 is only the default; keeping it first made bilingual
        // servers silently continue playing the old audio stream.
        if let audioKey, let selected = episode.audioSources.first(where: { $0.key == audioKey }) {
            values.append((selected.url, selected.label.isEmpty ? selected.key : selected.label))
        }
        if !episode.linkM3u8.isEmpty { values.append((episode.linkM3u8, "HLS chính")) }
        if let original = episode.audioSources.first(where: { $0.key.lowercased() == "original" }) { values.append((original.url, original.label.isEmpty ? "Âm thanh gốc" : original.label)) }
        for source in episode.audioSources { values.append((source.url, source.label.isEmpty ? source.key : source.label)) }
        var seen = Set<String>()
        return values.compactMap { raw, label in guard let url = normalizedURL(raw), seen.insert(url.absoluteString).inserted else { return nil }; return (url, label) }
    }
    private static func normalizedURL(_ raw: String) -> URL? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("//") { return URL(string: "https:\(value)") }
        if let url = URL(string: value), url.isFileURL || ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        return URL(string: value, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }
    private static func defaultAudioKey(for episode: EpisodeItem) -> String? {
        let usable = episode.audioSources.filter { normalizedURL($0.url) != nil }
        return usable.first(where: { $0.key.lowercased() == "original" })?.key ?? usable.first?.key
    }
    private static func sameEpisode(_ lhs: EpisodeItem, _ rhs: EpisodeItem) -> Bool { lhs.id == rhs.id || lhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == rhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func formatTime(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60) }
}
