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
        context.coordinator.attachIfNeeded(to: view.playerLayer)
        guard requestID != context.coordinator.lastRequestID else { return }
        context.coordinator.lastRequestID = requestID
        context.coordinator.requestToggle()
    }

    static func dismantleUIView(_ uiView: PlayerSurfaceView, coordinator: Coordinator) {
        coordinator.invalidate()
        uiView.playerLayer.player = nil
    }

    final class Coordinator: NSObject, AVPictureInPictureControllerDelegate {
        private(set) var pictureInPictureController: AVPictureInPictureController?
        private weak var attachedLayer: AVPlayerLayer?
        private var possibleObservation: NSKeyValueObservation?
        private var pendingStart = false
        private var readinessTimeout: DispatchWorkItem?
        var lastRequestID = 0

        func attach(to layer: AVPlayerLayer) {
            guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
            attachedLayer = layer
            let controller = AVPictureInPictureController(playerLayer: layer)
            controller.canStartPictureInPictureAutomaticallyFromInline = true
            controller.delegate = self
            pictureInPictureController = controller
            possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
                DispatchQueue.main.async { self?.startWhenReady(controller) }
            }
        }

        func attachIfNeeded(to layer: AVPlayerLayer) {
            if attachedLayer !== layer || pictureInPictureController == nil { attach(to: layer) }
        }

        func requestToggle() {
            guard let controller = pictureInPictureController else { return }
            if controller.isPictureInPictureActive {
                pendingStart = false
                controller.stopPictureInPicture()
                return
            }
            pendingStart = true
            startWhenReady(controller)
            readinessTimeout?.cancel()
            let timeout = DispatchWorkItem { [weak self] in self?.pendingStart = false }
            readinessTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        }

        private func startWhenReady(_ controller: AVPictureInPictureController) {
            guard pendingStart, controller.isPictureInPicturePossible, !controller.isPictureInPictureActive else { return }
            pendingStart = false
            readinessTimeout?.cancel()
            controller.startPictureInPicture()
        }

        func invalidate() {
            readinessTimeout?.cancel()
            possibleObservation?.invalidate()
            possibleObservation = nil
            pictureInPictureController?.delegate = nil
            pictureInPictureController = nil
            attachedLayer = nil
        }

        func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
            pendingStart = false
        }
    }
}

final class PlayerSurfaceView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
