import AppKit
import Foundation

@main
enum BenchmarkIsland {
    static func main() throws {
        for (width, height) in [(1440, 900), (3840, 2160), (420, 263)] {
            try autoreleasepool {
                let view = IslandArtworkView(frame: CGRect(x: 0, y: 0, width: width, height: height))
                view.model = IslandSceneModel(seed: 2026); view.model.step(seconds: 12)
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw NSError(domain: "BenchmarkIsland", code: 1) }
                var samples: [Double] = []
                for index in 0..<50 {
                    let start = ProcessInfo.processInfo.systemUptime
                    autoreleasepool {
                        view.model.step(seconds: 1.0 / 30)
                        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                        view.draw(view.bounds); context.flushGraphics()
                        NSGraphicsContext.restoreGraphicsState()
                    }
                    if index >= 5 { samples.append((ProcessInfo.processInfo.systemUptime - start) * 1000) }
                }
                samples.sort()
                print(String(format: "%dx%d, 45 warmed frames: median %.3f ms, p95 %.3f ms", width, height,
                             samples[samples.count / 2], samples[Int(ceil(Double(samples.count) * 0.95)) - 1]))
            }
        }
    }
}
