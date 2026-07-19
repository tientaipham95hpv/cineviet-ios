import AVKit
import SwiftUI

struct NativePlayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var showsPlaybackControls = true

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.showsPlaybackControls = showsPlaybackControls
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player { controller.player = player }
        controller.showsPlaybackControls = showsPlaybackControls
    }
}

struct PictureInPicturePlayerView: UIViewRepresentable {
    let player: AVPlayer
    @Binding var requestID: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PlayerSurfaceView {
        let view = PlayerSurfaceView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        context.coordinator.attach(to: view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerSurfaceView, context: Context) {
        if view.playerLayer.player !== player { view.playerLayer.player = player }
        guard requestID != context.coordinator.lastRequestID else { return }
        context.coordinator.lastRequestID = requestID
        context.coordinator.togglePictureInPicture()
    }

    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        var pictureInPictureController: AVPictureInPictureController?
        var lastRequestID = 0
        func attach(to layer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            pictureInPictureController = AVPictureInPictureController(playerLayer: layer)
            pictureInPictureController?.canStartPictureInPictureAutomaticallyFromInline = true
            pictureInPictureController?.delegate = self
        }
        func togglePictureInPicture() {
            guard let controller = pictureInPictureController, controller.isPictureInPicturePossible else { return }
            controller.isPictureInPictureActive ? controller.stopPictureInPicture() : controller.startPictureInPicture()
        }
    }
}

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
