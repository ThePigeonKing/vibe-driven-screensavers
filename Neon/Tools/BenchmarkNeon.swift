import AppKit
import Foundation

/// Cached shared-view drawing, including compositing into a full-size bitmap.
/// No window, PNG encoding, disk writes or first-frame artwork decoding is timed.
@main
enum BenchmarkNeon {
    static func main() throws {
        let asset = URL(fileURLWithPath: "Neon/Resources/neon-district.png")
        for (width, height) in [(1440, 900), (2560, 1080), (900, 1440), (420, 263),
                                (3024, 1890), (3840, 2160)] {
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            let artwork = NeonArtworkView(frame: frame)
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
                throw NSError(domain: "BenchmarkNeon", code: 1)
            }
            var samples: [Double] = []
            for index in 0...60 {
                let start = ProcessInfo.processInfo.systemUptime
                autoreleasepool {
                    artwork.model.step(seconds: 1.0 / 30.0)
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = context
                    artwork.draw(artwork.bounds)
                    context.flushGraphics()
                    NSGraphicsContext.restoreGraphicsState()
                }
                // The first draw decodes and samples the illustration and
                // allocates the scene raster. Later draws reuse both caches.
                if index > 0 {
                    samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                }
            }
            samples.sort()
            let median = (samples[29] + samples[30]) / 2
            let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
            print(String(format: "%dx%d, 60 cached frames: median %.3f ms, p95 %.3f ms, max %.3f ms / frame",
                         width, height, median, p95, samples.last!))
        }
    }
}
