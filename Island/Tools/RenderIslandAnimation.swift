import AppKit
import Foundation

@main
enum RenderIslandAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/island-animation-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let width = 960, height = 600
        guard let saver = LivingIslandSaverView(frame: CGRect(x: 0, y: 0, width: width, height: height), isPreview: false) else { throw failure() }
        saver.artwork.model = IslandSceneModel(seed: 2026)
        saver.artwork.model.step(seconds: 12)
        for index in 0..<180 {
            try autoreleasepool {
                if index > 0 { saver.artwork.model.step(seconds: 1.0 / 12) }
                guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                      let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure() }
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
                saver.artwork.draw(saver.artwork.bounds); context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()
                guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure() }
                try data.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
            }
        }
        print("Rendered 180 frames at 12 fps: \(output.path)")
    }
    private static func failure() -> NSError { NSError(domain: "RenderIslandAnimation", code: 1) }
}
