import AppKit
import Foundation

@main
enum RenderIslandSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/island-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, width, height) in [("compact", 420, 263), ("laptop", 1440, 900), ("wide", 1920, 1080),
                                       ("ultrawide", 2560, 1080), ("portrait", 900, 1440), ("retina", 3024, 1890), ("4k", 3840, 2160)] {
            try render(seed: 2026, time: 16, width: width, height: height,
                       output: output.appendingPathComponent(name + ".png"))
        }
        try render(seed: 2027, time: 12, width: 1440, height: 900, output: output.appendingPathComponent("alternate.png"))
        try render(seed: 2026, time: 240, width: 1440, height: 900, output: output.appendingPathComponent("later.png"))
    }
    private static func render(seed: UInt64, time: Double, width: Int, height: Int, output: URL) throws {
        try autoreleasepool {
            guard let saver = LivingIslandSaverView(frame: CGRect(x: 0, y: 0, width: width, height: height), isPreview: width == 420),
                  let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw failure() }
            saver.artwork.model = IslandSceneModel(seed: seed)
            saver.artwork.model.step(seconds: time)
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            saver.artwork.draw(saver.artwork.bounds); context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            guard let data = bitmap.representation(using: .png, properties: [:]) else { throw failure() }
            try data.write(to: output); print(output.path)
        }
    }
    private static func failure() -> NSError { NSError(domain: "RenderIslandSnapshots", code: 1) }
}
