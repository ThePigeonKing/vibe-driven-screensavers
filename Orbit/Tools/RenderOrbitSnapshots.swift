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
enum RenderOrbitSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
            ?? "build/orbit-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sizes = [("compact",420,263),("laptop",1440,900),("wide",1920,1080),
                     ("ultrawide",2560,1080),("portrait",900,1440),("retina",3024,1890),("4k",3840,2160)]
        for (name,w,h) in sizes {
            try autoreleasepool {
                let view = try OrbitRender.view(width:w,height:h,time:22,preview:name=="compact")
                let (bitmap,context) = try OrbitRender.canvas(width:w,height:h)
                OrbitRender.draw(view,context:context)
                try OrbitRender.png(bitmap,to:output.appendingPathComponent(name+".png"))
            }
        }
        for (name,time) in [("arrival",8.0),("docked",22.0),("departure",40.0)] {
            try autoreleasepool {
                let view = try OrbitRender.view(width:1440,height:900,time:time)
                let (bitmap,context) = try OrbitRender.canvas(width:1440,height:900)
                OrbitRender.draw(view,context:context)
                try OrbitRender.png(bitmap,to:output.appendingPathComponent(name+".png"))
            }
        }
        print("Rendered seven sizes and three traffic states to "+output.path)
    }
}
