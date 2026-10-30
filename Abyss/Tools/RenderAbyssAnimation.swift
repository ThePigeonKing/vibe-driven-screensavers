import AppKit
import Foundation

/// Fifteen seconds of the shared scene at 12 fps, starting in the first encounter.
@main
enum RenderAbyssAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/abyss-animation-frames", isDirectory: true)
        let asset = URL(fileURLWithPath: "Abyss/Resources/abyss-station.png")
        guard FileManager.default.fileExists(atPath: asset.path) else {
            throw failure(1, "Run from the repository root with the bundled artwork present")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = 960, height = 600
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = AbyssStationSaverView(frame: frame, isPreview: false) else {
            throw failure(2, "Cannot construct AbyssStationSaverView")
        }
        let artwork = saver.artwork
        artwork.assetURLOverride = asset
        artwork.model = AbyssSceneModel(seed: 2026)
        for _ in 0..<72 { artwork.model.step(seconds: 0.25) }
        for index in 0..<180 {
            try autoreleasepool {
                if index > 0 { artwork.model.step(seconds: 1.0 / 12.0) }
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                    pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4,
                                                    hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB,
                                                    bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                    throw failure(3, "Cannot allocate the output bitmap")
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                artwork.draw(artwork.bounds)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw failure(4, "Cannot encode PNG")
                }
                try png.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
            }
        }
        print("Rendered 180 frames at 12 fps to \(output.path)")
    }

    private static func failure(_ code: Int, _ description: String) -> NSError {
        NSError(domain: "RenderAbyssAnimation", code: code,
                userInfo: [NSLocalizedDescriptionKey: description])
    }
}
