import AppKit
import Foundation

/// Eighteen seconds of the living neon scene, rendered at 12 fps for the README.
@main
enum RenderNeonAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/neon-animation-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = 960, height = 600
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = NeonDistrictSaverView(frame: frame, isPreview: false),
              let artwork = saver.subviews.first as? NeonArtworkView else {
            throw NSError(domain: "RenderNeonAnimation", code: 1)
        }
        artwork.assetURLOverride = URL(fileURLWithPath: "Neon/Resources/neon-district.png")
        artwork.model = NeonAnimationModel(seed: 2026)
        artwork.model.step(seconds: 4)
        for index in 0..<216 {
            if index > 0 { artwork.model.step(seconds: 1.0 / 12.0) }
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "RenderNeonAnimation", code: 2)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(artwork.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RenderNeonAnimation", code: 3)
            }
            try png.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
        }
        print("Rendered 216 frames at 12 fps to \(output.path)")
    }
}
