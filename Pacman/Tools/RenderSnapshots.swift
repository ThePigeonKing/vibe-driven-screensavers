import AppKit
import Foundation

/// Renders the actual saver view at several sizes for layout inspection.
@main
enum RenderSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/pacman-snapshots",
                         isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263),
            ("laptop", 1440, 900),
            ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080),
            ("portrait", 900, 1440)
        ]

        for (name, width, height) in sizes {
            let frame = CGRect(x: 0, y: 0, width: width, height: height)
            guard let saverView = AutoPacmanSaverView(frame: frame, isPreview: name == "compact"),
                  let artwork = saverView.subviews.first as? MazeArtworkView else {
                throw NSError(domain: "RenderSnapshots", code: 1)
            }
            artwork.game = MazeGame(seed: 2026)
            for _ in 0..<48 { artwork.game.step() }
            for _ in 0..<20 where artwork.game.player.previous == artwork.game.player.tile {
                artwork.game.step()
            }
            artwork.game.advance(to: 0)
            artwork.game.advance(to: MazeGame.stepInterval / 2)
            artwork.animationTime = 1 / (3.2 * 2)

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
                throw NSError(domain: "RenderSnapshots", code: 2)
            }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            artwork.draw(artwork.bounds)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw NSError(domain: "RenderSnapshots", code: 3)
            }
            let destination = output.appendingPathComponent("\(name).png")
            try png.write(to: destination)
            print(destination.path)
        }
    }
}
