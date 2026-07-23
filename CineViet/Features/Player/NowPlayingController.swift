import AVFoundation
import MediaPlayer

@MainActor
final class NowPlayingController {
    private weak var player: AVPlayer?
    private var previous: (() -> Void)?
    private var next: (() -> Void)?

    func activate(player: AVPlayer, title: String, subtitle: String, previous: @escaping () -> Void, next: @escaping () -> Void) {
        self.player = player; self.previous = previous; self.next = next
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.removeTarget(nil); commands.pauseCommand.removeTarget(nil)
        commands.changePlaybackPositionCommand.removeTarget(nil); commands.previousTrackCommand.removeTarget(nil); commands.nextTrackCommand.removeTarget(nil)
        commands.playCommand.addTarget { [weak self] _ in self?.player?.play(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.player?.pause(); return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let seconds = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else { return .commandFailed }
            self?.player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)); return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.previous?(); return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.next?(); return .success }
        update(title: title, subtitle: subtitle, position: 0, duration: 0, rate: 0)
    }

    func update(title: String, subtitle: String, position: Double, duration: Double, rate: Float) {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title, MPMediaItemPropertyAlbumTitle: subtitle,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: rate
        ]
    }
    func deactivate() { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; player = nil; previous = nil; next = nil }
}
