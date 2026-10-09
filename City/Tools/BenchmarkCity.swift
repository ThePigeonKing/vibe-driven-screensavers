import AppKit
import Foundation

/// Measures shared-view drawing without PNG encoding or a running window.
@main
enum BenchmarkCity {
    static func main() throws {
        for (width, height) in [(1440, 900), (2560, 1080)] {
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            guard let saver = PixelCitySaverView(frame: frame, isPreview: false),
                  let artwork = saver.subviews.first as? CityArtworkView,
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "BenchmarkCity", code: 1)
            }
            artwork.model = CitySceneModel(seed: 2026)
            artwork.weatherOverride = .rain
            artwork.dateOverride = Date()
            var samples: [Double] = []
            for index in 0..<330 {
                let start = ProcessInfo.processInfo.systemUptime
                autoreleasepool {
                    artwork.model.step(seconds: 1.0 / 30.0)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    artwork.draw(artwork.bounds)
                    context.flushGraphics()
                    NSGraphicsContext.restoreGraphicsState()
                }
                if index >= 30 {
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
                }
            }
            samples.sort()
            print(String(format: "%dx%d rain: median %.2f ms, p95 %.2f ms, max %.2f ms / frame",
                         width, height, samples[samples.count / 2],
                         samples[Int(Double(samples.count - 1) * 0.95)], samples.last!))
        }
    }
}
