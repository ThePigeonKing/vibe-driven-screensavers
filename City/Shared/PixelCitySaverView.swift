import AppKit
import ScreenSaver

/// Shared entry point for macOS ScreenSaverEngine and the preview application.
@objc(PixelCitySaverView)
final class PixelCitySaverView: ScreenSaverView {
    private let artwork = CityArtworkView(frame: .zero)

    /// Preview-only control; the installed saver always follows the live weather.
    var weatherOverride: CityWeatherPreset? {
        get { artwork.weatherOverride }
        set {
            artwork.weatherOverride = newValue
            artwork.needsDisplay = true
        }
    }

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
