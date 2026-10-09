import AppKit
import Foundation

/// Renders a short animation from the real shared saver view for visual QA.
@main
enum RenderAnimation {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/pacman-animation-frames", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let width = 840
        let height = 525
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = AutoPacmanSaverView(frame: frame, isPreview: false),
              let artwork = saver.subviews.first as? MazeArtworkView else {
            throw NSError(domain: "RenderAnimation", code: 1)
        }
        artwork.game = MazeGame(seed: 2026)

        for index in 0..<72 {
            let time = Double(index) / 12
            artwork.game.advance(to: time)
            artwork.animationTime = time

            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                                pixelsWide: width,
                                                pixelsHigh: height,
                                                bitsPerSample: 8,
                                                samplesPerPixel: 4,
                                                hasAlpha: true,
                                                isPlanar: false,
                                                colorSpaceName: .deviceRGB,
                                                bytesPerRow: 0,
                                                bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                throw NSError(domain: "RenderAnimation", code: 2)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(artwork.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RenderAnimation", code: 3)
            }
            try png.write(to: output.appendingPathComponent(String(format: "frame-%03d.png", index)))
        }
        print("Rendered 72 frames at 12 fps to \(output.path)")
    }
}
