import AVFoundation
import Combine
import Foundation

struct PlaybackCandidate: Identifiable, Equatable {
    let id: String
    let url: URL
    let server: EpisodeServer
    let episode: EpisodeItem
    let label: String
}

@MainActor
final class PlayerViewModel: ObservableObject {
    struct SubtitleStyle: Equatable {
        var font = "Lora"
        var size: Double = 22
        var colorHex = "FFFFFF"
        var bottom: Double = 8
    }
    @Published private(set) var isLoading = true
    @Published private(set) var isBuffering = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var playbackNotice: String?
    @Published private(set) var currentEpisode: EpisodeItem
    @Published private(set) var currentServer: EpisodeServer
    @Published private(set) var selectedAudioKey: String?
    @Published var selectedSubtitleLanguage: String
    @Published private(set) var overlaySubtitle: String?
    @Published var subtitleStyle = SubtitleStyle()
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
    var availableAudio: [EpisodeAudioSource] { currentEpisode.audioSources }
    var availableSubtitles: [EpisodeSubtitleTrack] { currentEpisode.subtitles }
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
    private var subtitleTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var autoNextTask: Task<Void, Never>?
    private var candidateQueue: [PlaybackCandidate] = []
    private var candidateIndex = 0
    private var pendingResumePosition: Double?
    private var shouldFetchRemoteResume = true
    private var lastSavedPosition: Double = 0
    private var started = false

    private var serverPreferenceKey: String { "cineviet.player.server.\(movie.id)" }
    private var episodePreferenceKey: String { "cineviet.player.episode.\(movie.id)" }
    private var audioPreferenceKey: String { "cineviet.player.audio.\(movie.id)" }
    private var subtitlePreferenceKey: String { "cineviet.player.subtitle.\(movie.id)" }
    private var autoPlayPreferenceKey: String { "cineviet.player.autoplay" }
    private var subtitleStylePreferenceKey: String { "cineviet.player.subtitle.style.\(movie.id)" }

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem, watchHistoryService: WatchHistoryServicing, defaults: UserDefaults = .standard) {
        self.movie = movie
        self.defaults = defaults
        self.watchHistoryService = watchHistoryService
        let preferredServer = defaults.string(forKey: "cineviet.player.server.\(movie.id)")
        let restoredServer = movie.episodes.first(where: { $0.name == preferredServer }) ?? server
        let preferredEpisode = defaults.string(forKey: "cineviet.player.episode.\(movie.id)")
        currentServer = restoredServer
        currentEpisode = restoredServer.items.first(where: { $0.id == preferredEpisode })
            ?? restoredServer.items.first(where: { Self.sameEpisode($0, episode) }) ?? episode
        selectedAudioKey = defaults.string(forKey: "cineviet.player.audio.\(movie.id)")
        selectedSubtitleLanguage = defaults.string(forKey: "cineviet.player.subtitle.\(movie.id)") ?? "vi"
        if let data = defaults.data(forKey: "cineviet.player.subtitle.style.\(movie.id)"), let saved = try? JSONDecoder().decode(SubtitleStyleDTO.self, from: data) { subtitleStyle = saved.value }
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
    }

    func start() {
        guard !started else { return }
        started = true
        configureAudioSession()
        installObservers()
        rebuildQueueAndLoad(preserving: nil, includeEquivalentServers: true)
    }

    func stop() {
        saveProgress(force: true)
        player.pause()
        started = false
        cancelAsyncWork()
        removePlayerObservers()
    }

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
    }

    func selectSubtitle(_ language: String) {
        selectedSubtitleLanguage = language
        defaults.set(language, forKey: subtitlePreferenceKey)
        applyEmbeddedSubtitleSelection()
        startExternalSubtitleOverlay(for: currentEpisode)
        showNotice(language == "off" ? "Đã tắt phụ đề" : "Đã chọn phụ đề")
    }

    func updateSubtitleStyle(_ style: SubtitleStyle) {
        subtitleStyle = style
        if let data = try? JSONEncoder().encode(SubtitleStyleDTO(value: style)) { defaults.set(data, forKey: subtitleStylePreferenceKey) }
    }

    private struct SubtitleStyleDTO: Codable {
        let font: String; let size: Double; let colorHex: String; let bottom: Double
        init(value: SubtitleStyle) { font = value.font; size = value.size; colorHex = value.colorHex; bottom = value.bottom }
        var value: SubtitleStyle { SubtitleStyle(font: font, size: size, colorHex: colorHex, bottom: bottom) }
    }

    func dismissNotice() { playbackNotice = nil; noticeTask?.cancel() }

    private func rebuildQueueAndLoad(preserving position: Double?, includeEquivalentServers: Bool) {
        pendingResumePosition = position
        candidateQueue = buildCandidateQueue(includeEquivalentServers: includeEquivalentServers)
        candidateIndex = 0
        loadCurrentCandidate()
    }

    private func buildCandidateQueue(includeEquivalentServers: Bool) -> [PlaybackCandidate] {
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
        let item = AVPlayerItem(url: candidate.url)
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
                    self.applyEmbeddedSubtitleSelection()
                    self.startExternalSubtitleOverlay(for: candidate.episode)
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
        subtitleTask?.cancel(); overlaySubtitle = nil
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
    }

    private func resumePlaybackIfNeeded(for candidate: PlaybackCandidate) {
        resumeTask?.cancel()
        if let position = pendingResumePosition, position > 3 {
            pendingResumePosition = nil
            player.seek(to: CMTime(seconds: position, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            player.play(); return
        }
        guard shouldFetchRemoteResume else { player.play(); return }
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
        guard let item = player.currentItem else { return }
        let position = player.currentTime().seconds, duration = item.duration.seconds
        guard position.isFinite, duration.isFinite, position >= 3, force || abs(position - lastSavedPosition) >= 5 else { return }
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
        overlaySubtitle = nil; subtitleTask?.cancel()
        if let subtitleTimeObserver { player.removeTimeObserver(subtitleTimeObserver); self.subtitleTimeObserver = nil }
        guard selectedSubtitleLanguage != "off" else { return }
        let tracks: [EpisodeSubtitleTrack]
        if selectedSubtitleLanguage == "dual" {
            tracks = ["vi", "en"].compactMap { code in episode.subtitles.first(where: { $0.lang.lowercased().hasPrefix(code) }) }
        } else {
            tracks = episode.subtitles.filter { $0.lang.lowercased().hasPrefix(selectedSubtitleLanguage.lowercased()) }
        }
        guard !tracks.isEmpty else { return }
        subtitleTask = Task { [weak self] in
            guard let self else { return }
            var cueSets: [[SubtitleCue]] = []
            for track in tracks {
                guard let url = self.subtitleURL(track.url), let (data, _) = try? await URLSession.shared.data(from: url), let text = String(data: data, encoding: .utf8) else { continue }
                cueSets.append(SubtitleParser.parse(text, format: track.format))
            }
            guard !Task.isCancelled, !cueSets.isEmpty else { return }
            self.subtitleTimeObserver = self.player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
                let lines = cueSets.compactMap { cues in cues.first(where: { time.seconds >= $0.start && time.seconds < $0.end })?.text }
                self?.overlaySubtitle = lines.isEmpty ? nil : lines.joined(separator: "\n")
            }
        }
    }

    private func applyEmbeddedSubtitleSelection() {
        guard let item = player.currentItem, let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible) else { return }
        guard selectedSubtitleLanguage != "off", selectedSubtitleLanguage != "dual" else { item.select(nil, in: group); return }
        let selected = group.options.first {
            let language = $0.extendedLanguageTag ?? $0.locale?.language.languageCode?.identifier
            return language?.lowercased().hasPrefix(selectedSubtitleLanguage.lowercased()) == true
        }
        item.select(selected, in: group)
    }

    private func subtitleURL(_ raw: String) -> URL? { Self.normalizedURL(raw) }
    private func persistSelection() { defaults.set(currentServer.name, forKey: serverPreferenceKey); defaults.set(currentEpisode.id, forKey: episodePreferenceKey) }
    private func restoredAudioKey(validFor episode: EpisodeItem) -> String? {
        let stored = defaults.string(forKey: audioPreferenceKey)
        return episode.audioSources.contains(where: { $0.key == stored }) ? stored : nil
    }
    private func cancelAsyncWork() { subtitleTask?.cancel(); resumeTask?.cancel(); noticeTask?.cancel(); autoNextTask?.cancel() }
    private func configureAudioSession() { try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback); try? AVAudioSession.sharedInstance().setActive(true) }

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
        if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { return url }
        return URL(string: value, relativeTo: AppEnvironment.siteBaseURL)?.absoluteURL
    }
    private static func sameEpisode(_ lhs: EpisodeItem, _ rhs: EpisodeItem) -> Bool { lhs.id == rhs.id || lhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == rhs.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    private static func formatTime(_ seconds: Double) -> String { let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60) }
}
