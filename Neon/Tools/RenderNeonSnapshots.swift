import AppKit
import Foundation

/// Deterministic frames from the same view hosted by ScreenSaverEngine.
@main
enum RenderNeonSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/neon-snapshots", isDirectory: true)
        let asset = URL(fileURLWithPath: "Neon/Resources/neon-district.png")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263),
            ("laptop", 1440, 900),
            ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080),
            ("portrait", 900, 1440),
            ("retina", 3024, 1890),
            ("4k", 3840, 2160)
        ]
        for (name, width, height) in sizes {
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            guard let saver = NeonDistrictSaverView(frame: frame, isPreview: name == "compact"),
                  let artwork = saver.subviews.first as? NeonArtworkView else {
                throw NSError(domain: "RenderNeonSnapshots", code: 1)
            }
            artwork.assetURLOverride = asset
            artwork.model = NeonAnimationModel(seed: 2026)
            artwork.model.step(seconds: 12)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "RenderNeonSnapshots", code: 2)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(artwork.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RenderNeonSnapshots", code: 3)
            }
            let destination = output.appendingPathComponent("\(name).png")
            try png.write(to: destination)
            print(destination.path)
        }
    }
}
