import SwiftUI
import AVFoundation

/// A chromeless video surface — no native play/scrub/fullscreen controls,
/// since the mockup's custom play button + mute icon replace all of that.
struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        // This view has no native controls and reacts to nothing on its
        // own — all interaction goes through SwiftUI gesture modifiers on
        // ancestor views (tap-to-pause, long-press-to-2x, the scrubber).
        // But even a UIView with zero gesture recognizers of its own still
        // participates in UIKit's touch hit-testing/responder chain once
        // bridged in via UIViewRepresentable, and that was enough to make
        // PlaybackView's ScrollView(.paging) pan gesture refuse to
        // recognize for any touch starting on the video — confirmed by
        // dragging in the comments drawer (no PlayerLayerView there) paging
        // correctly while dragging the video itself did nothing at all,
        // regardless of what SwiftUI gesture modifiers were or weren't
        // attached above it. Disabling interaction here removes it from
        // that hit-testing path entirely.
        view.isUserInteractionEnabled = false
        view.playerLayer.player = player
        // .resizeAspect scales to fit within bounds, never cropping — a
        // wider-than-screen video gets letterboxed (bars above/below), a
        // taller one gets pillarboxed (bars left/right). .resizeAspectFill
        // (the previous setting) crops to fill instead, which cuts off
        // content on any video whose aspect ratio doesn't match the screen.
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerContainerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
