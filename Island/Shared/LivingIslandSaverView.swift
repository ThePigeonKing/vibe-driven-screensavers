import AppKit
import ScreenSaver

@objc(LivingIslandSaverView)
final class LivingIslandSaverView: ScreenSaverView {
    let artwork = IslandArtworkView(frame: .zero)
    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configure()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }
    private func configure() {
        animationTimeInterval = 1.0 / 30.0
        artwork.frame = bounds
        artwork.autoresizingMask = [.width, .height]
        addSubview(artwork)
    }
    override func layout() { super.layout(); artwork.frame = bounds }
    override func animateOneFrame() { artwork.advanceFrame() }
}
