import AppKit
import Foundation

/// A ten-second rain passage with rail and road traffic rendered at 12 fps.
@main
enum RenderCityAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/city-animation-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = 840, height = 525
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = PixelCitySaverView(frame: frame, isPreview: false),
              let artwork = saver.subviews.first as? CityArtworkView else {
            throw NSError(domain: "RenderCityAnimation", code: 1)
        }
        saver.weatherOverride = .rain
        artwork.model = CitySceneModel(seed: 2026)
        artwork.model.step(seconds: 8)
        artwork.dateOverride = Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 2, hour: 22, minute: 48
        ))!
        for index in 0..<120 {
            if index > 0 { artwork.model.step(seconds: 1.0 / 12.0) }
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "RenderCityAnimation", code: 2)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(artwork.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RenderCityAnimation", code: 3)
            }
            try png.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
        }
        print("Rendered 120 frames at 12 fps to \(output.path)")
    }
}
