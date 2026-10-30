import AppKit
import Foundation

/// Fixed-seed captures of the micro-city, seafloor, forcefield and all species.
@main
enum RenderHadalSnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/hadal-snapshots", isDirectory: true)
        let asset = URL(fileURLWithPath: "Hadal/Resources/hadal-city-seabed.png")
        guard FileManager.default.fileExists(atPath: asset.path) else {
            throw failure(1, "Run from the repository root with the bundled artwork present")
        }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263), ("laptop", 1440, 900), ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080), ("portrait", 900, 1440),
            ("retina", 3024, 1890), ("4k", 3840, 2160)
        ]
        for (name, width, height) in sizes {
            try autoreleasepool {
                try render(model: encounter(.medusa, age: 24), width: width, height: height,
                           isPreview: name == "compact", asset: asset,
                           destination: output.appendingPathComponent(name + ".png"))
            }
        }
        for kind in [HadalCreatureKind.maw, .ribbon, .medusa, .carapace, .elder] {
            try autoreleasepool {
                try render(model: encounter(kind, age: 24), width: 1440, height: 900,
                           isPreview: false, asset: asset,
                           destination: output.appendingPathComponent("species-" + kind.rawValue + ".png"))
            }
        }
        for (name, age) in [("approach", 8.0), ("flare", 20.0), ("impact", 31.5), ("retreat", 43.0)] {
            try render(model: encounter(.maw, age: age), width: 1440, height: 900,
                       isPreview: false, asset: asset,
                       destination: output.appendingPathComponent("phase-" + name + ".png"))
        }
        try render(model: HadalSceneModel(seed: 2026), width: 1440, height: 900,
                   isPreview: false, asset: asset,
                   destination: output.appendingPathComponent("initial.png"))
    }

    private static func encounter(_ kind: HadalCreatureKind, age: Double) -> HadalSceneModel {
        var model = HadalSceneModel(seed: 2026)
        model.startEncounter(kind: kind)
        for _ in 0..<Int(age / 0.25) { model.step(seconds: 0.25) }
        let remainder = age.truncatingRemainder(dividingBy: 0.25)
        if remainder > 0 { model.step(seconds: remainder) }
        return model
    }

    private static func render(model: HadalSceneModel, width: Int, height: Int,
                               isPreview: Bool, asset: URL, destination: URL) throws {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = HadalOutpostSaverView(frame: frame, isPreview: isPreview) else {
            throw failure(2, "Cannot construct HadalOutpostSaverView")
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
        try png.write(to: destination)
        print(destination.path)
    }

    private static func failure(_ code: Int, _ description: String) -> NSError {
        NSError(domain: "RenderHadalSnapshots", code: code,
                userInfo: [NSLocalizedDescriptionKey: description])
    }
}
