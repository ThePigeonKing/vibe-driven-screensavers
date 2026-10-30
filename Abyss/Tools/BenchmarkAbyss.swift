import AppKit
import Foundation

/// Warmed shared-view drawing into physical-size bitmaps at a 1x backing scale.
/// Does not include first-frame decoding, PNG encoding, disk writes or window work.
@main
enum BenchmarkAbyss {
    static func main() throws {
        let asset = URL(fileURLWithPath: "Abyss/Resources/abyss-station.png")
        guard FileManager.default.fileExists(atPath: asset.path) else {
            throw NSError(domain: "BenchmarkAbyss", code: 1,
                          userInfo: [NSLocalizedDescriptionKey:
                            "Run from the repository root with the bundled artwork present"])
        }
        for (width, height) in [(1440, 900), (3840, 2160), (420, 263)] {
            try autoreleasepool {
                let frame = CGRect(x: 0, y: 0, width: width, height: height)
                let artwork = AbyssArtworkView(frame: frame)
                artwork.assetURLOverride = asset
                artwork.model = AbyssSceneModel(seed: 2026)
                for _ in 0..<168 { artwork.model.step(seconds: 0.25) }
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                    pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                    throw NSError(domain: "BenchmarkAbyss", code: 2)
                }
                var samples: [Double] = []
                for index in 0..<50 {
                    let start = ProcessInfo.processInfo.systemUptime
                    autoreleasepool {
                        artwork.model.step(seconds: 1.0 / 30.0)
                        NSGraphicsContext.saveGraphicsState()
                        NSGraphicsContext.current = context
                        artwork.draw(artwork.bounds)
                        context.flushGraphics()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    // Decode the artwork and prepare all render caches before
                    // collecting 45 measured frames.
                    if index >= 5 {
                        samples.append((ProcessInfo.processInfo.systemUptime - start) * 1_000)
                    }
                }
                samples.sort()
                let median = samples[samples.count / 2]
                let p95 = samples[Int(ceil(Double(samples.count) * 0.95)) - 1]
                print(String(format: "%dx%d, 45 warmed frames at 1x: median %.3f ms, p95 %.3f ms, max %.3f ms / frame",
                             width, height, median, p95, samples.last!))
            }
        }
    }
}
