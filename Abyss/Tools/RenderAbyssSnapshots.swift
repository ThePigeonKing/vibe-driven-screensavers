import AppKit
import Foundation

/// Deterministic frames from the real saver view, rendered without a window.
/// Run from the repository root; only command-line tools override the asset URL.
@main
enum RenderAbyssSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/abyss-snapshots", isDirectory: true)
        let asset = URL(fileURLWithPath: "Abyss/Resources/abyss-station.png")
        guard FileManager.default.fileExists(atPath: asset.path) else {
            throw failure(1, "Run from the repository root with the bundled artwork present")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let elder = model(at: 42)
        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263),
            ("laptop", 1440, 900),
            ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080),
            ("portrait", 900, 1440),
            ("retina", 3024, 1890),
            ("4k", 3840, 2160)
        ]
        for (name, width, height) in sizes {
            try autoreleasepool {
                try render(model: elder, width: width, height: height,
                           isPreview: name == "compact", asset: asset,
                           destination: output.appendingPathComponent("\(name).png"))
            }
        }
        try render(model: model(at: 0), width: 1440, height: 900,
                   isPreview: false, asset: asset,
                   destination: output.appendingPathComponent("initial.png"))

        var leviathan = AbyssSceneModel(seed: 2026)
        var foundLeviathan = false
        var firstLeviathanTime: Double?
        // Bounded search: capture a naturally scheduled encounter, without
        // constructing an artificial state that could never happen in the saver.
        for _ in 0..<2_000 {
            leviathan.step(seconds: 0.25)
            if leviathan.encounter?.kind == .leviathan, firstLeviathanTime == nil {
                firstLeviathanTime = leviathan.elapsed
            }
            if let encounter = leviathan.encounter,
               encounter.kind == .leviathan,
               (0.48...0.52).contains(encounter.progress) {
                foundLeviathan = true
                break
            }
        }
        guard foundLeviathan else { throw failure(2, "No leviathan encounter within 500 seconds") }
        print(String(format: "First leviathan at %.2f s; capture at %.2f s, progress %.3f",
                     firstLeviathanTime!, leviathan.elapsed, leviathan.encounter!.progress))
        try render(model: leviathan, width: 1440, height: 900,
                   isPreview: false, asset: asset,
                   destination: output.appendingPathComponent("leviathan.png"))
    }

    private static func model(at seconds: Double) -> AbyssSceneModel {
        var model = AbyssSceneModel(seed: 2026)
        let fullSteps = Int(seconds / 0.25)
        for _ in 0..<fullSteps { model.step(seconds: 0.25) }
        let remainder = seconds - Double(fullSteps) * 0.25
        if remainder > 0 { model.step(seconds: remainder) }
        return model
    }

    private static func render(model: AbyssSceneModel, width: Int, height: Int,
                               isPreview: Bool, asset: URL, destination: URL) throws {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = AbyssStationSaverView(frame: frame, isPreview: isPreview) else {
            throw failure(3, "Cannot construct AbyssStationSaverView")
        }
        let artwork = saver.artwork
        artwork.assetURLOverride = asset
        artwork.model = model
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw failure(4, "Cannot allocate the output bitmap")
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        artwork.draw(artwork.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw failure(5, "Cannot encode PNG")
        }
        try png.write(to: destination)
        print(destination.path)
    }

    private static func failure(_ code: Int, _ description: String) -> NSError {
        NSError(domain: "RenderAbyssSnapshots", code: code,
                userInfo: [NSLocalizedDescriptionKey: description])
    }
}
