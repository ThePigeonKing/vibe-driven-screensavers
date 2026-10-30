import AppKit
import ImageIO

/// Both native entry points share the same scene, caches and monotonic clock.
final class OrbitArtworkView: NSView {
    var model = OrbitSceneModel()
    var assetURLOverride: URL? {
        didSet { if oldValue != assetURLOverride { assets = nil; background = nil } }
    }
    private var assets: OrbitAssets?
    private var raster: CGContext?
    private var background: CGImage?
    private var size = CGSize.zero

    override var isOpaque: Bool { true }

    func advanceFrame() {
        model.advance(to: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0,
              let destination = NSGraphicsContext.current?.cgContext else { return }
        let physical = convertToBacking(bounds)
        let backingScale = max(1, physical.width / bounds.width)
        let pixel = max(1, ceil(sqrt(physical.width * physical.height / 1_300_000)))
        let width = max(1, Int(ceil(physical.width / pixel)))
        let height = max(1, Int(ceil(physical.height / pixel)))
        if size != CGSize(width: width, height: height) {
            raster = CGContext(data: nil, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            size = CGSize(width: width, height: height)
            background = nil
        }
        if assets == nil { assets = OrbitAssets(bundle: Bundle(for: OrbitArtworkView.self), override: assetURLOverride) }
        guard let raster, let assets else { return }
        func paint(_ operation: (OrbitPainting) -> Void) {
            raster.saveGState()
            raster.interpolationQuality = .none
            raster.setShouldAntialias(false)
            raster.translateBy(x: 0, y: Double(height))
            raster.scaleBy(x: 1, y: -1)
            operation(OrbitPainting(c: raster, width: Double(width), height: Double(height),
                                    assets: assets, model: model))
            raster.restoreGState()
        }
        if background == nil {
            paint { $0.drawBackground() }
            background = raster.makeImage()
        }
        if let background {
            raster.saveGState()
            raster.setBlendMode(.copy)
            raster.draw(background, in: CGRect(x: 0, y: 0, width: width, height: height))
            raster.restoreGState()
        }
        paint { $0.drawAnimation() }
        guard let image = raster.makeImage() else { return }
        destination.saveGState()
        destination.setShouldAntialias(false)
        destination.interpolationQuality = .none
        destination.draw(image, in: CGRect(x: 0, y: 0,
                                           width: Double(width) * pixel / backingScale,
                                           height: Double(height) * pixel / backingScale))
        destination.restoreGState()
    }
}

private func orbitColor(_ rgb: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255, alpha: max(0, min(1, alpha)))
}

private func orbitGradient(_ colors: [CGColor]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: colors as CFArray, locations: nil)!
}

private enum OrbitPaint {
    static let empty = orbitGradient([orbitColor(0x061020), orbitColor(0x02060e)])
    static let engine = orbitGradient([orbitColor(0x9cd7e5, 0.65), orbitColor(0x367889, 0.20), orbitColor(0x102936, 0)])
    static let amber = orbitGradient([orbitColor(0xe5b77b, 0.24), orbitColor(0x9c7847, 0.05), orbitColor(0x58493b, 0)])
    static let veil: CGImage? = {
        guard let b = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8,
                                bytesPerRow: 512 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let g = orbitGradient([orbitColor(0x000514, 0), orbitColor(0x000514, 0.035), orbitColor(0x000514, 0.17)])
        b.drawLinearGradient(g, start: .zero, end: CGPoint(x: 512, y: 0), options: [])
        return b.makeImage()
    }()
}

private struct OrbitAssets {
    let planet: CGImage?
    let station: CGImage?

    init(bundle: Bundle, override: URL?) {
        func load(_ name: String) -> CGImage? {
            let url = override.map { $0.deletingLastPathComponent().appendingPathComponent(name + ".png") }
                ?? bundle.url(forResource: name, withExtension: "png")
            guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            return CGImageSourceCreateImageAtIndex(source, 0,
                [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        }
        planet = load("orbit-planet")
        station = load("orbit-station")
    }
}

private struct OrbitPainting {
    let c: CGContext
    let width: Double
    let height: Double
    let assets: OrbitAssets
    let model: OrbitSceneModel
    private var time: Double { model.elapsed }
    private var unit: Double { min(width / 1600, height / 1000) }
    private var canvas: CGRect {
        CGRect(x: (width - 1600 * unit) / 2, y: (height - 1000 * unit) / 2,
               width: 1600 * unit, height: 1000 * unit)
    }
    private var center: CGPoint { point(OrbitPoint(x: 0.59, y: 0.49)) }
    private var planetRect: CGRect {
        let ratio = Double(assets.planet?.width ?? 1600) / Double(assets.planet?.height ?? 1000)
        let w = max(width, height * ratio), h = w / ratio
        return CGRect(x: (width - w) / 2, y: (height - h) / 2, width: w, height: h)
    }
    private var stationRect: CGRect {
        let w = 830 * unit
        let h = w * Double(assets.station?.height ?? 1086) / Double(assets.station?.width ?? 1450)
        return CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    }

    private func point(_ p: OrbitPoint) -> CGPoint {
        CGPoint(x: canvas.minX + p.x * canvas.width, y: canvas.minY + p.y * canvas.height)
    }

    private func image(_ image: CGImage, in rect: CGRect) {
        c.saveGState()
        c.translateBy(x: rect.minX, y: rect.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: rect.size))
        c.restoreGState()
    }

    private func path(_ points: [CGPoint], fill: UInt32, alpha: Double = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.closePath(); c.setFillColor(orbitColor(fill, alpha)); c.fillPath()
    }

    private func line(_ points: [CGPoint], color: UInt32, alpha: Double = 1, width: Double = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.setLineWidth(width); c.setStrokeColor(orbitColor(color, alpha)); c.strokePath()
    }

    private func glow(_ g: CGGradient, at p: CGPoint, radius: Double, alpha: Double = 1) {
        c.saveGState(); c.setAlpha(alpha)
        c.drawRadialGradient(g, startCenter: p, startRadius: 0,
                             endCenter: p, endRadius: radius, options: [])
        c.restoreGState()
    }

    func drawBackground() {
        c.drawLinearGradient(OrbitPaint.empty, start: .zero,
                             end: CGPoint(x: 0, y: height), options: [.drawsAfterEndLocation])
        if let planet = assets.planet { image(planet, in: planetRect) }
    }

    func drawAnimation() {
        drawPlanetVeil()
        drawStars()
        // Ships and docking ports share the station frame, so a slow attitude
        // change cannot cause a docked vessel to drift away from its berth.
        c.saveGState()
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: model.stationAngle)
        if let station = assets.station { image(station, in: stationRect) }
        drawRingTraffic()
        drawPorts()
        for ship in model.ships { drawShip(ship) }
        c.restoreGState()
    }

    private func drawPlanetVeil() {
        guard let veil = OrbitPaint.veil else { return }
        let r = planetRect
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        c.addEllipse(in: CGRect(x: r.minX - r.width * 0.69, y: r.minY - r.height * 0.01,
                               width: r.width * 1.38, height: r.height * 1.92))
        c.clip()
        image(veil, in: CGRect(x: r.minX + sin(time / 163) * r.width * 0.045,
                              y: r.minY, width: r.width * 0.74, height: r.height))
        c.restoreGState()
        // Warm city lights remain gentle and independent; no one-frame flashes.
        for index in 0..<9 {
            let i = Double(index)
            let x = r.minX + r.width * (0.36 + i * 0.023)
            let y = r.minY + r.height * (0.47 + i * 0.043 + sin(i * 2.2) * 0.03)
            glow(OrbitPaint.amber, at: CGPoint(x: x, y: y), radius: max(2, unit * 6),
                 alpha: 0.10 + model.beaconStrength(id: index + 10) * 0.16)
        }
    }

    private func drawStars() {
        for (index, star) in OrbitStar.field.enumerated() {
            let x = star.x * width, y = star.y * height
            // Added stars are only in open space; never in front of the planet.
            let r = planetRect
            let dx = (x - r.minX) / (r.width * 0.69)
            let dy = (y - (r.minY + r.height * 0.95)) / (r.height * 0.96)
            if dx * dx + dy * dy < 1.04 { continue }
            let phase = time.truncatingRemainder(dividingBy: 49 + Double(index) * 1.7)
                / (49 + Double(index) * 1.7) * 2 * .pi
            let a = 0.12 + (0.5 + sin(phase + star.phase) * 0.5) * 0.16
            c.setFillColor(orbitColor(index % 7 == 0 ? 0xc0b493 : 0x8ea9c3, a))
            c.fill(CGRect(x: floor(x), y: floor(y), width: index % 19 == 0 ? 1.4 : 0.8, height: 1))
        }
    }

    private func drawRingTraffic() {
        let r = stationRect
        let rx = r.width * 0.399, ry = r.height * 0.264
        let cy = -r.height * 0.055
        for index in 0..<12 {
            let phase = model.ringPhase * 2 * .pi + Double(index) / 12 * 2 * .pi
            let p = CGPoint(x: cos(phase) * rx, y: cy + sin(phase) * ry)
            let next = CGPoint(x: cos(phase + 0.025) * rx, y: cy + sin(phase + 0.025) * ry)
            line([p, next], color: index % 3 == 0 ? 0x93c5d1 : 0xe3bb7f,
                 alpha: 0.20 + model.beaconStrength(id: index) * 0.23,
                 width: max(1, unit * 1.5))
        }
    }

    private func drawPorts() {
        let docks = [OrbitPoint(x: 0.795, y: 0.632), OrbitPoint(x: 0.375, y: 0.595), OrbitPoint(x: 0.59, y: 0.30)]
        for (index, dock) in docks.enumerated() {
            let p = point(dock)
            let local = CGPoint(x: p.x - center.x, y: p.y - center.y)
            let a = model.beaconStrength(id: index + 20)
            glow(OrbitPaint.engine, at: local, radius: max(2, unit * 8), alpha: a * 0.28)
            c.setFillColor(orbitColor(0x99c4c8, a * 0.70))
            c.fill(CGRect(x: local.x - 1.2 * unit, y: local.y - unit,
                          width: max(1, unit * 2.4), height: max(1, unit * 2)))
        }
    }

    private func drawShip(_ ship: OrbitShip) {
        let p = point(ship.position)
        c.saveGState()
        c.translateBy(x: p.x - center.x, y: p.y - center.y)
        c.rotate(by: ship.angle)
        let s = unit * (ship.id % 3 == 1 ? 1.15 : 0.88)
        c.scaleBy(x: s, y: s)
        if ship.engine > 0.01 {
            c.saveGState()
            c.translateBy(x: -17, y: 0)
            c.scaleBy(x: 1 + ship.engine * 1.8, y: 0.42)
            glow(OrbitPaint.engine, at: .zero, radius: 9, alpha: ship.engine * 0.75)
            c.restoreGState()
        }
        path([CGPoint(x: 19, y: 0), CGPoint(x: 7, y: -6), CGPoint(x: -12, y: -5),
              CGPoint(x: -16, y: 0), CGPoint(x: -12, y: 5), CGPoint(x: 7, y: 6)], fill: 0x9daeb5)
        path([CGPoint(x: -2, y: -4), CGPoint(x: -13, y: -15), CGPoint(x: -17, y: -15),
              CGPoint(x: -11, y: 0)], fill: 0x586a7b)
        path([CGPoint(x: -2, y: 4), CGPoint(x: -13, y: 15), CGPoint(x: -17, y: 15),
              CGPoint(x: -11, y: 0)], fill: 0x3b4a5b)
        path([CGPoint(x: 19, y: 0), CGPoint(x: 4, y: 2), CGPoint(x: -13, y: 2),
              CGPoint(x: -12, y: 5), CGPoint(x: 7, y: 6)], fill: 0x485964)
        path([CGPoint(x: 9, y: -2), CGPoint(x: 4, y: -4), CGPoint(x: 1, y: -2),
              CGPoint(x: 6, y: -1)], fill: 0x83bac6)
        line([CGPoint(x: -10, y: -2), CGPoint(x: -3, y: -2)], color: 0xd4ad75, alpha: 0.8)
        c.setFillColor(orbitColor(0x203242))
        c.fill(CGRect(x: -17, y: -3, width: 3, height: 6))
        if ship.phase == .docked {
            let alpha = sin(ship.progress * .pi) * 0.4
            c.setFillColor(orbitColor(0xc4aa72, alpha))
            let travel = sin(time / 3 + Double(ship.id)) * 5
            c.fill(CGRect(x: travel - 2, y: 8, width: 4, height: 3))
        }
        c.restoreGState()
    }
}

private struct OrbitStar {
    let x: Double, y: Double, phase: Double
    static let field: [OrbitStar] = {
        var state: UInt64 = 0x0AB17A1
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        return (0..<95).map { _ in OrbitStar(x: next(), y: next(), phase: next() * 2 * .pi) }
    }()
}
