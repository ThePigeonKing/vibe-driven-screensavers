import AppKit
import Foundation

private enum OrbitRender {
    static let asset = URL(fileURLWithPath: "Orbit/Resources/orbit-planet.png")

    static func model(at seconds: Double) -> OrbitSceneModel {
        var model = OrbitSceneModel(seed: 2026)
        let steps = Int(seconds / 0.25)
        for _ in 0..<steps { model.step(seconds: 0.25) }
        let remainder = seconds - Double(steps) * 0.25
        if remainder > 0 { model.step(seconds: remainder) }
        return model
    }

    static func view(width: Int, height: Int, time: Double, preview: Bool = false) throws -> OrbitArtworkView {
        guard FileManager.default.fileExists(atPath: asset.path),
              let saver = OrbitalStationSaverView(frame: CGRect(x: 0, y: 0, width: width, height: height),
                                                   isPreview: preview) else {
            throw NSError(domain: "OrbitRender", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Run from the repository root with both bundled PNG files"])
        }
        let artwork = saver.artwork
        artwork.assetURLOverride = asset
        artwork.model = model(at: time)
        // Retaining the artwork is sufficient for offscreen rendering after it
        // has received its frame from the real ScreenSaverView wrapper.
        return artwork
    }

    static func canvas(width: Int, height: Int) throws -> (NSBitmapImageRep, NSGraphicsContext) {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
            let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "OrbitRender", code: 2)
        }
        return (bitmap, context)
    }

    static func draw(_ artwork: OrbitArtworkView, context: NSGraphicsContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        artwork.draw(artwork.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
    }

    static func png(_ bitmap: NSBitmapImageRep, to destination: URL) throws {
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "OrbitRender", code: 3)
        }
        try png.write(to: destination)
    }
}

@main
enum BenchmarkOrbit {
    static func main() throws {
        for (w,h) in [(1440,900),(3840,2160),(420,263)] {
            try autoreleasepool {
                let view = try OrbitRender.view(width:w,height:h,time:22)
                let (_,context) = try OrbitRender.canvas(width:w,height:h)
                var times:[Double]=[]
                for index in 0..<50 {
                    let start = ProcessInfo.processInfo.systemUptime
                    autoreleasepool {
                        view.model.step(seconds:1.0/30.0)
                        OrbitRender.draw(view,context:context)
                    }
                    if index>=5 { times.append((ProcessInfo.processInfo.systemUptime-start)*1000) }
                }
                times.sort()
                print(String(format:"%dx%d, 45 warmed 1x frames: median %.3f ms / p95 %.3f / max %.3f",
                    w,h,times[times.count/2],times[Int(ceil(Double(times.count)*0.95))-1],times.last!))
            }
        }
    }
}
