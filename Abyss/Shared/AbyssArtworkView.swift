import AppKit
import ImageIO

/// The installed saver and the preview render the same bounded, local scene.
final class AbyssArtworkView: NSView {
    var model = AbyssSceneModel()
    /// Only offscreen tools supply a source URL. Apps use their own resource bundle.
    var assetURLOverride: URL? { didSet { if oldValue != assetURLOverride { assets = nil } } }
    private var assets: AbyssAssets?
    private var raster: CGContext?
    private var rasterSize = CGSize.zero

    override var isOpaque: Bool { true }

    func advanceFrame() {
        model.advance(to: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0,
              let destination = NSGraphicsContext.current?.cgContext else { return }
        let backing = convertToBacking(bounds)
        let backingScale = max(1, backing.width / bounds.width)
        // Keep the work bounded on large Retina displays and use whole physical pixels.
        let pixel = max(1, ceil(sqrt(backing.width * backing.height / 1_600_000)))
        let width = max(1, Int(ceil(backing.width / pixel)))
        let height = max(1, Int(ceil(backing.height / pixel)))
        let size = CGSize(width: width, height: height)
        if rasterSize != size {
            raster = CGContext(data: nil, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            rasterSize = size
        }
        if assets == nil {
            assets = AbyssAssets(bundle: Bundle(for: AbyssArtworkView.self), override: assetURLOverride)
        }
        guard let raster else { return }
        raster.saveGState()
        raster.setShouldAntialias(false)
        raster.interpolationQuality = .none
        raster.translateBy(x: 0, y: CGFloat(height))
        raster.scaleBy(x: 1, y: -1)
        AbyssPainting(context: raster, width: Double(width), height: Double(height),
                      assets: assets, model: model).draw()
        raster.restoreGState()
        guard let frame = raster.makeImage() else { return }
        destination.saveGState()
        destination.interpolationQuality = .none
        destination.setShouldAntialias(false)
        destination.draw(frame, in: CGRect(x: 0, y: 0,
                                           width: Double(width) * pixel / backingScale,
                                           height: Double(height) * pixel / backingScale))
        destination.restoreGState()
    }
}


private struct AbyssSpriteBand {
    let image: CGImage
    let unit: CGRect
}

private struct AbyssSprite {
    let bands: [AbyssSpriteBand]
    let aspectHeight: Double

    init?(image: CGImage?, horizontalBands: Bool) {
        guard let image else { return nil }
        let w = image.width, h = image.height
        aspectHeight = Double(h) / Double(w)
        let length = horizontalBands ? h : w
        let count = 56
        var result: [AbyssSpriteBand] = []
        for index in 0..<count {
            let first = index * length / count
            let end = (index + 1) * length / count
            guard end > first else { continue }
            let rect = horizontalBands
                ? CGRect(x: 0, y: first, width: w, height: end - first)
                : CGRect(x: first, y: 0, width: end - first, height: h)
            if let crop = image.cropping(to: rect) {
                result.append(AbyssSpriteBand(image: crop,
                    unit: CGRect(x: rect.minX / Double(w), y: rect.minY / Double(h),
                                 width: rect.width / Double(w), height: rect.height / Double(h))))
            }
        }
        bands = result
    }
}

private struct AbyssAssets {
    let background: CGImage?
    let verticalBackground: CGImage?
    let horizontalBackground: CGImage?
    let elder: AbyssSprite?
    let leviathan: AbyssSprite?

    init(bundle: Bundle, override: URL?) {
        func load(_ name: String) -> CGImage? {
            let url = override.map { $0.deletingLastPathComponent().appendingPathComponent(name + ".png") }
                ?? bundle.url(forResource: name, withExtension: "png")
            guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            // Decode once before building sprite strips, rather than letting
            // ImageIO schedule lazy PNG work during the first animated frames.
            let options = [kCGImageSourceShouldCache: true,
                           kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let image = load("abyss-station")
        background = image
        verticalBackground = image.flatMap { Self.feather($0, vertical: true) }
        horizontalBackground = image.flatMap { Self.feather($0, vertical: false) }
        elder = AbyssSprite(image: load("abyss-elder"), horizontalBands: true)
        leviathan = AbyssSprite(image: load("abyss-leviathan"), horizontalBands: false)
    }

    /// Extend unusually tall/wide displays with water, without hard letterbox edges.
    /// This is a cached runtime alpha mask; the committed original remains unchanged.
    private static func feather(_ image: CGImage, vertical: Bool) -> CGImage? {
        let w = image.width, h = image.height
        guard let buffer = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        buffer.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let colors = [abyssColor(0, 0), abyssColor(0), abyssColor(0), abyssColor(0, 0)]
        let positions: [CGFloat] = [0, 0.075, 0.925, 1]
        guard let mask = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                    colors: colors as CFArray, locations: positions) else { return nil }
        buffer.setBlendMode(.destinationIn)
        buffer.drawLinearGradient(mask, start: .zero,
                                   end: CGPoint(x: vertical ? 0 : w, y: vertical ? h : 0),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        return buffer.makeImage()
    }
}

private func abyssColor(_ rgb: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255, alpha: max(0, min(1, alpha)))
}

private func abyssGradient(_ colors: [UInt32], alphas: [Double]? = nil) -> CGGradient {
    let values = colors.enumerated().map { abyssColor($0.element, alphas?[$0.offset] ?? 1) }
    return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                      colors: values as CFArray, locations: nil)!
}

private enum AbyssPaint {
    static let water = abyssGradient([0x061a22, 0x031018, 0x01070c])
    static let beam = abyssGradient([0x73b7b4, 0x2a6875, 0x1c4a60], alphas: [0.12, 0.045, 0])
    static let lamp = abyssGradient([0xe2af61, 0x9e793d, 0x655736], alphas: [0.26, 0.08, 0])
}

private struct AbyssPainting {
    let context: CGContext
    let width: Double
    let height: Double
    let assets: AbyssAssets?
    let model: AbyssSceneModel
    private var time: Double { model.elapsed }

    func draw() {
        context.drawLinearGradient(AbyssPaint.water, start: .zero,
                                   end: CGPoint(x: 0, y: height), options: [.drawsAfterEndLocation])
        let scale = min(width / 1280, height / 800)
        let origin = CGPoint(x: ((width - 1280 * scale) / 2).rounded(),
                             y: ((height - 800 * scale) / 2).rounded())
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        let hasVerticalMargins = height - 800 * scale > 1
        let hasHorizontalMargins = width - 1280 * scale > 1
        let background = hasVerticalMargins ? assets?.verticalBackground :
            hasHorizontalMargins ? assets?.horizontalBackground : assets?.background
        if let image = background {
            context.saveGState()
            context.translateBy(x: 0, y: 800)
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: 1280, height: 800))
            context.restoreGState()
        }
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: 1280, height: 800))
        drawDistantLife()
        if let encounter = model.encounter {
            context.saveGState()
            context.setAlpha(model.encounterVisibility)
            switch encounter.kind {
            case .elder: drawElder(encounter)
            case .leviathan: drawLeviathan(encounter)
            }
            context.restoreGState()
        }
        drawSearchlights()
        drawStationLights()
        drawBubbles()
        context.restoreGState()
        context.restoreGState()
        drawMarineSnow()
    }

    private func stroke(_ path: CGPath, _ color: UInt32, _ alpha: Double = 1, width: Double = 1) {
        context.addPath(path)
        context.setStrokeColor(abyssColor(color, alpha))
        context.setLineWidth(width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.strokePath()
    }

    private func ellipse(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
                         _ color: UInt32, _ alpha: Double = 1) {
        context.setFillColor(abyssColor(color, alpha))
        context.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
    }

    private func polygon(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }

    // Original translucent creature art is deformed continuously in cached strips.
    // Adjacent strips share endpoint offsets, so there are no cracks between them.
    private func drawElder(_ event: AbyssEncounter) {
        guard let sprite = assets?.elder else { return }
        let reveal = sin(event.progress * .pi)
        let w = 420 + reveal * 30
        let h = w * sprite.aspectHeight
        let x = 945 + sin(event.progress * 4.1 + event.variation) * 21
        let y = 406 + sin(time / 19) * 9 + (1 - reveal) * 23
        context.saveGState()
        context.setAlpha(0.40)
        context.translateBy(x: x, y: y)
        context.scaleBy(x: Double(event.direction), y: 1)
        for band in sprite.bands {
            let v0 = band.unit.minY, v1 = band.unit.maxY
            func drift(_ v: Double) -> Double {
                sin(time / 10 + v * 6.2) * (1.4 + v * v * 12)
            }
            let top = drift(v0), bottom = drift(v1)
            let bandHeight = band.unit.height * h
            context.saveGState()
            context.translateBy(x: -w / 2 + top, y: -h / 2 + v0 * h)
            context.concatenate(CGAffineTransform(a: 1, b: 0, c: (bottom - top) / bandHeight,
                                                  d: 1, tx: 0, ty: 0))
            drawImage(band.image, rect: CGRect(x: 0, y: 0, width: w, height: bandHeight))
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawLeviathan(_ event: AbyssEncounter) {
        guard let sprite = assets?.leviathan else { return }
        let direction = Double(event.direction)
        let x = direction > 0 ? -640 + event.progress * 2560 : 1920 - event.progress * 2560
        let w = 1110.0, h = w * sprite.aspectHeight
        let y = 240 + sin(event.progress * 2 * .pi) * 20 + event.variation * 20
        context.saveGState()
        context.setAlpha(0.41)
        context.translateBy(x: x, y: y)
        // The supplied original sprite faces left.
        context.scaleBy(x: -direction, y: 1)
        for band in sprite.bands {
            let u0 = band.unit.minX, u1 = band.unit.maxX
            func drift(_ u: Double) -> Double {
                sin(time / 8 - u * 6) * (1 + u * u * 18)
            }
            let first = drift(u0), last = drift(u1)
            let bandWidth = band.unit.width * w
            context.saveGState()
            context.translateBy(x: -w / 2 + u0 * w, y: -h / 2 + first)
            context.concatenate(CGAffineTransform(a: 1, b: (last - first) / bandWidth,
                                                  c: 0, d: 1, tx: 0, ty: 0))
            drawImage(band.image, rect: CGRect(x: 0, y: 0, width: bandWidth, height: h))
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawImage(_ image: CGImage, rect: CGRect) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }

    private func drawSearchlights() {
        let phase = model.beamPhase * 2 * .pi
        let secondPhase = time.truncatingRemainder(dividingBy: 57 / 0.71) / (57 / 0.71) * 2 * .pi
        let lights = [(385.0, 439.0, -0.20 + sin(phase) * 0.16, 0.115, 760.0),
                      (591.0, 483.0, 0.22 + sin(secondPhase + 1) * 0.17, 0.10, 570.0)]
        for (x, y, angle, spread, length) in lights {
            let origin = CGPoint(x: x, y: y)
            let cone = polygon([origin,
                                CGPoint(x: x + cos(angle - spread) * length, y: y + sin(angle - spread) * length),
                                CGPoint(x: x + cos(angle + spread) * length, y: y + sin(angle + spread) * length)])
            context.saveGState()
            context.addPath(cone)
            context.clip()
            context.drawLinearGradient(AbyssPaint.beam, start: origin,
                                       end: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length), options: [])
            context.restoreGState()
            ellipse(x - 1.5, y - 1, 3, 2, 0x9ebdb4, 0.65)
        }
    }

    private func drawStationLights() {
        let windows: [(Double, Double)] = [(225, 332), (235, 333), (244, 334), (253, 333), (264, 331),
                                           (285, 427), (296, 429), (307, 430), (318, 430), (329, 429), (340, 428), (350, 426)]
        for (id, position) in windows.enumerated() {
            let light = model.windowLight(id: id)
            context.saveGState()
            context.setAlpha(light * 0.55)
            context.drawRadialGradient(AbyssPaint.lamp,
                                       startCenter: CGPoint(x: position.0, y: position.1), startRadius: 0,
                                       endCenter: CGPoint(x: position.0, y: position.1), endRadius: 10, options: [])
            context.restoreGState()
        }
        let safetyLights = [(251.0, 230.0), (331.0, 359.0), (525.0, 442.0)]
        for (id, p) in safetyLights.enumerated() {
            let value = 0.55 + 0.14 * sin(time / 5 + Double(id) * 2.7)
            ellipse(p.0 - 2.5, p.1 - 2.5, 5, 5, 0x5b9893, value * 0.08)
            ellipse(p.0 - 0.8, p.1 - 0.8, 1.6, 1.6, 0x98b7a7, value)
        }
    }

    private func drawBubbles() {
        for vent in 0..<2 {
            let origin = vent == 0 ? CGPoint(x: 506, y: 492) : CGPoint(x: 216, y: 437)
            let strength = model.ventStrength(id: vent)
            for index in 0..<14 {
                let seed = Double(index) * 2.91 + Double(vent) * 9
                let age = (time * (0.045 + Double(index % 3) * 0.003) + Double(index) / 14)
                    .truncatingRemainder(dividingBy: 1)
                let x = origin.x + sin(age * 8 + seed) * (3 + age * 12) + age * 13
                let y = origin.y - age * 124
                let alpha = sin(age * .pi) * (0.12 + strength * 0.17)
                let radius = 0.7 + age * 0.9
                context.setStrokeColor(abyssColor(0x73a0a0, alpha))
                context.setLineWidth(0.7)
                context.strokeEllipse(in: CGRect(x: x, y: y, width: radius * 2, height: radius * 2))
            }
        }
    }

    private func drawDistantLife() {
        // Sparse bioluminescent threads establish depth; no bright swarms or blinking.
        for index in 0..<5 {
            let i = Double(index)
            let x = 667 + i * 106 + sin(time / (39 + i * 5) + i) * 26
            let y = 480 + sin(i * 3.7) * 95 - sin(time / 29 + i * 1.1) * 23
            let breath = 0.10 + 0.06 * sin(time / 11 + i * 2)
            let bell = CGMutablePath()
            bell.move(to: CGPoint(x: x - 5, y: y))
            bell.addCurve(to: CGPoint(x: x + 5, y: y),
                          control1: CGPoint(x: x - 5, y: y - 9), control2: CGPoint(x: x + 5, y: y - 9))
            stroke(bell, 0x447875, breath * 1.8)
            for limb in 0..<3 {
                let strand = CGMutablePath()
                strand.move(to: CGPoint(x: x - 3 + Double(limb) * 3, y: y))
                strand.addQuadCurve(to: CGPoint(x: x + sin(time / 8 + i) * 4, y: y + 14),
                                    control: CGPoint(x: x + Double(limb) * 3, y: y + 7))
                stroke(strand, 0x416967, breath)
            }
        }
    }

    private func drawMarineSnow() {
        for (index, mote) in AbyssMote.field.enumerated() {
            let depth = mote.depth
            let x = (mote.x * width + sin(time / 29 + mote.phase) * 3 * depth + time * depth * 0.55)
                .truncatingRemainder(dividingBy: width)
            let y = (mote.y * height + time * (0.25 + depth * 0.7))
                .truncatingRemainder(dividingBy: height)
            let edge = min(1, min(x, width - x) / 15) * min(1, min(y, height - y) / 15)
            let alpha = (0.07 + depth * 0.11) * edge
            let size = index % 13 == 0 ? 1.4 : 0.8
            context.setFillColor(abyssColor(0x648a91, alpha))
            context.fill(CGRect(x: floor(x), y: floor(y), width: size, height: size))
        }
    }
}

private struct AbyssMote {
    let x: Double
    let y: Double
    let depth: Double
    let phase: Double

    static let field: [AbyssMote] = {
        var state: UInt64 = 0xAB155
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        return (0..<240).map { _ in
            AbyssMote(x: next(), y: next(), depth: 0.3 + next() * 0.7, phase: next() * 2 * .pi)
        }
    }()
}
