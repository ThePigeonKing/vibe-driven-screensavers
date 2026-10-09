import AppKit
import ScreenSaver

/// Both the installable screen saver and the preview app use this view.
@objc(AutoPacmanSaverView)
final class AutoPacmanSaverView: ScreenSaverView {
    private let artwork = MazeArtworkView(frame: .zero)

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configureArtwork()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureArtwork()
    }

    private func configureArtwork() {
        animationTimeInterval = 1.0 / 30.0
        artwork.autoresizingMask = [.width, .height]
        artwork.frame = bounds
        addSubview(artwork)
    }

    override func layout() {
        super.layout()
        artwork.frame = bounds
    }

    override func animateOneFrame() {
        artwork.advanceFrame()
        artwork.needsDisplay = true
    }
}
