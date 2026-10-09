import AppKit
import Foundation

/// Deterministic snapshots from the same view hosted by ScreenSaverEngine.
/// Weather and date overrides are used only by this standalone QA tool.
@main
enum RenderCitySnapshots {
    static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first
                             ?? "build/city-snapshots", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let localDate = Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 2, hour: 22, minute: 48
        ))!
        let sizes: [(String, Int, Int)] = [
            ("compact", 420, 263),
            ("laptop", 1440, 900),
            ("wide", 1920, 1080),
            ("ultrawide", 2560, 1080),
            ("portrait", 900, 1440)
        ]
        for (name, width, height) in sizes {
            try render(.clear, name: "clear-\(name)", width: width, height: height,
                       localDate: localDate, output: output)
        }
        try render(.cloudy, name: "cloudy-laptop", width: 1440, height: 900,
                   localDate: localDate, output: output)
        try render(.rain, name: "rain-laptop", width: 1440, height: 900,
                   localDate: localDate, output: output)
        try render(.rain, name: "rain-compact", width: 420, height: 263,
                   localDate: localDate, output: output)
    }

    private static func render(_ weather: CityWeatherPreset, name: String,
                               width: Int, height: Int, localDate: Date, output: URL) throws {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        guard let saver = PixelCitySaverView(frame: frame, isPreview: name.hasSuffix("compact")),
              let artwork = saver.subviews.first as? CityArtworkView else {
            throw NSError(domain: "RenderCitySnapshots", code: 1)
        }
        saver.weatherOverride = weather
        artwork.model = CitySceneModel(seed: 2026)
        artwork.model.step(seconds: 12)
        artwork.dateOverride = localDate
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
                                            pixelsWide: width, pixelsHigh: height,
                                            bitsPerSample: 8, samplesPerPixel: 4,
                                            hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            throw NSError(domain: "RenderCitySnapshots", code: 2)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        artwork.draw(artwork.bounds)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "RenderCitySnapshots", code: 3)
        }
        let destination = output.appendingPathComponent("\(name).png")
        try png.write(to: destination)
        print(destination.path)
    }
}
