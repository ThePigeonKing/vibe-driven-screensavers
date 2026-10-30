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
enum RenderOrbitAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
            ?? "build/orbit-animation-frames", isDirectory:true)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let view = try OrbitRender.view(width:960,height:600,time:8)
        for index in 0..<432 {
            try autoreleasepool {
                if index>0 { view.model.step(seconds:1.0/12.0) }
                // NSBitmapImageRep caches its encoded CGImage. Each exported
                // frame needs a fresh bitmap so it cannot reuse the first PNG.
                let (bitmap,context) = try OrbitRender.canvas(width:960,height:600)
                OrbitRender.draw(view,context:context)
                try OrbitRender.png(bitmap,to:output.appendingPathComponent(String(format:"frame-%03d.png",index)))
            }
        }
        print("Rendered 432 frames at 12fps, 36 seconds, to "+output.path)
    }
}
