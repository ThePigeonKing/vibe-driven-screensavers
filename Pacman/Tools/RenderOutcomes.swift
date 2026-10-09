import AppKit
import Foundation

/// Finds a real win and loss, then renders the shared saver view during each pause.
@main
enum RenderOutcomes {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/pacman-outcome-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        var won: MazeGame?
        var lost: MazeGame?
        for seed in 0..<200 where won == nil || lost == nil {
            var game = MazeGame(seed: UInt64(seed))
            for _ in 0..<2_000 where game.phase == .playing { game.step() }
            if game.phase == .won && won == nil { won = game }
            if game.phase == .gameOver && lost == nil { lost = game }
        }
        guard let won, let lost else {
            throw NSError(domain: "RenderOutcomes", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Could not observe both outcomes"])
        }

        for (name, game) in [("won", won), ("gameover", lost)] {
            for (size, width, height) in [("laptop", 1440, 900), ("compact", 420, 263)] {
                let frame = CGRect(x: 0, y: 0, width: width, height: height)
                guard let saver = AutoPacmanSaverView(frame: frame, isPreview: size == "compact"),
                      let artwork = saver.subviews.first as? MazeArtworkView else {
                    throw NSError(domain: "RenderOutcomes", code: 2)
                }
                artwork.game = game
                artwork.animationTime = 0

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
                    throw NSError(domain: "RenderOutcomes", code: 3)
                }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                artwork.draw(artwork.bounds)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()

                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "RenderOutcomes", code: 4)
                }
                let destination = output.appendingPathComponent("\(name)-\(size).png")
                try png.write(to: destination)
                print(destination.path)
            }
        }
    }
}
