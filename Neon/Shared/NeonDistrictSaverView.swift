import AppKit
import ScreenSaver

/// Shared entry point for ScreenSaverEngine and the Xcode preview application.
@objc(NeonDistrictSaverView)
final class NeonDistrictSaverView: ScreenSaverView {
    private let artwork = NeonArtworkView(frame: .zero)

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
