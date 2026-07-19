import AVFoundation
import Combine
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    @Published private(set) var currentEpisode: EpisodeItem
    @Published private(set) var currentServer: EpisodeServer

    let movie: Movie
    let player = AVPlayer()

    private var itemObservation: NSKeyValueObservation?

    init(movie: Movie, server: EpisodeServer, episode: EpisodeItem) {
        self.movie = movie
        currentServer = server
        currentEpisode = episode
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
    }

    deinit { itemObservation?.invalidate() }

    func start() {
        configureAudioSession()
        load(currentEpisode, server: currentServer)
    }

    func stop() {
        player.pause()
        itemObservation?.invalidate()
    }

    func play(_ episode: EpisodeItem, server: EpisodeServer) {
        currentEpisode = episode
        currentServer = server
        load(episode, server: server)
    }

    private func load(_ episode: EpisodeItem, server: EpisodeServer) {
        itemObservation?.invalidate()
        errorMessage = nil
        isLoading = true

        guard let url = Self.directMediaURL(for: episode) else {
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

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            // AVPlayer can still attempt playback; surface only media failures.
        }
    }

    static func directMediaURL(for episode: EpisodeItem) -> URL? {
        let originalAudio = episode.audioSources.first { $0.key.lowercased() == "original" }
        let audioSource = originalAudio ?? episode.audioSources.first
        let candidates = [audioSource?.url, episode.linkM3u8]
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
