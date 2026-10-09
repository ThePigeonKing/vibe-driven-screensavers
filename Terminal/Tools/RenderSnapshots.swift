import AppKit
import Foundation

/// Renders the real shared artwork view at representative window sizes.
/// This tool is intentionally not part of either Xcode target.
@main
enum RenderSnapshots {
    static func main() throws {
        guard NSClassFromString("AlarmTerminalSaverView") != nil else {
            throw NSError(domain: "RenderSnapshots", code: 3)
        }
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/snapshots",
                         isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263),
            ("laptop", 1440, 900),
            ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080),
            ("portrait", 900, 1440)
        ]

        for theme in TerminalTheme.allCases {
            for (name, width, height) in sizes {
                guard let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: width,
                pixelsHigh: height,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
                ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
                    throw NSError(domain: "RenderSnapshots", code: 1)
                }

                let frame = CGRect(x: 0, y: 0, width: width, height: height)
                guard let saverView = AlarmTerminalSaverView(frame: frame, isPreview: name == "compact"),
                      let view = saverView.subviews.first as? TerminalArtworkView else {
                    throw NSError(domain: "RenderSnapshots", code: 4)
                }
                saverView.animateOneFrame()
                // Keep the screenshot matrix independent of the user's saved
                // theme while still exercising the real saver view wrapper.
                view.theme = theme
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                view.draw(view.bounds)
                context.flushGraphics()
                NSGraphicsContext.restoreGraphicsState()

                guard let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw NSError(domain: "RenderSnapshots", code: 2)
                }
                let destination = output.appendingPathComponent("\(theme.rawValue)-\(name).png")
                try png.write(to: destination)
                print(destination.path)
            }
        }
    }
}
