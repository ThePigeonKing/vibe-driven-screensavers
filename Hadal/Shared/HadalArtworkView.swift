import AppKit
import ImageIO

/// Three reusable buffers: the scene, an animated animal, and the actual light field.
/// A destination-in mask makes unlit anatomy disappear rather than merely tinting it.
final class HadalArtworkView: NSView {
    var model = HadalSceneModel()
    var assetURLOverride: URL? {
        didSet { if oldValue != assetURLOverride { assets = nil; background = nil } }
    }
    private var assets: HadalAssets?
    private var background: CGImage?
    private var scene: CGContext?
    private var animal: CGContext?
    private var illumination: CGContext?
    private var size = CGSize.zero

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
        let pixel = max(1, ceil(sqrt(backing.width * backing.height / 1_300_000)))
        let w = max(1, Int(ceil(backing.width / pixel)))
        let h = max(1, Int(ceil(backing.height / pixel)))
        if size != CGSize(width: w, height: h) {
            background = nil
            func buffer(divisor: Int = 1) -> CGContext? {
                let bw = max(1, (w + divisor - 1) / divisor)
                let bh = max(1, (h + divisor - 1) / divisor)
                return CGContext(data: nil, width: bw, height: bh, bitsPerComponent: 8,
                          bytesPerRow: bw * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            }
            scene = buffer(); animal = buffer(); illumination = buffer(divisor: 2)
            size = CGSize(width: w, height: h)
        }
        if assets == nil {
            assets = HadalAssets(bundle: Bundle(for: HadalArtworkView.self), override: assetURLOverride)
        }
        guard let scene, let animal, let illumination, let assets else { return }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        func paint(_ context: CGContext, _ body: (HadalPainting) -> Void) {
            context.saveGState()
            context.interpolationQuality = .none
            context.setShouldAntialias(false)
            context.translateBy(x: 0, y: Double(context.height))
            context.scaleBy(x: Double(context.width) / Double(w),
                            y: -Double(context.height) / Double(h))
            body(HadalPainting(c: context, width: Double(w), height: Double(h),
                               assets: assets, model: model))
            context.restoreGState()
        }
        if background == nil {
            paint(scene) { $0.drawBackground() }
            background = scene.makeImage()
        }
        if let background {
            scene.saveGState()
            scene.setBlendMode(.copy)
            scene.interpolationQuality = .none
            scene.draw(background, in: rect)
            scene.restoreGState()
        }
        paint(scene) { $0.drawSearchlights() }
        if let encounter = model.encounter {
            animal.clear(rect)
            illumination.clear(rect)
            paint(animal) { $0.drawCreature(encounter) }
            paint(illumination) { $0.drawIllumination() }
            if let mask = illumination.makeImage() {
                animal.saveGState()
                animal.setBlendMode(.destinationIn)
                // Only the smooth light field is enlarged with interpolation;
                // creature texture and the finished pixel grid remain sharp.
                animal.interpolationQuality = .low
                animal.draw(mask, in: rect)
                animal.restoreGState()
            }
            if let creature = animal.makeImage() {
                paint(scene) { $0.image(creature, in: rect) }
            }
        }
        paint(scene) { $0.drawForeground() }
        guard let frame = scene.makeImage() else { return }
        destination.saveGState()
        destination.setShouldAntialias(false)
        destination.interpolationQuality = .none
        destination.draw(frame, in: CGRect(x: 0, y: 0,
                                           width: Double(w) * pixel / backingScale,
                                           height: Double(h) * pixel / backingScale))
        destination.restoreGState()
    }
}

private func hc(_ rgb: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255, alpha: max(0, min(1, alpha)))
}

private func hg(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
               colors: colors as CFArray, locations: locations)!
}

private func hs(_ value: Double) -> Double {
    let x = max(0, min(1, value))
    return x * x * (3 - 2 * x)
}

private enum HadalPaint {
    static let water = hg([hc(0x030a11), hc(0x04111a), hc(0x02070b)])
    static let haze = hg([hc(0x173841, 0.25), hc(0x102c36, 0.10), hc(0x07151f, 0)])
    static let whiteLight = hg([hc(0xffffff, 1), hc(0xffffff, 0.78),
                                hc(0xffffff, 0.25), hc(0xffffff, 0)], [0, 0.22, 0.65, 1])
    static let beamMask = hg([hc(0xffffff, 1), hc(0xffffff, 0.65), hc(0xffffff, 0)])
    static let beamFog = hg([hc(0x76a9ae, 0.065), hc(0x436a79, 0.025), hc(0x294757, 0)])
    static let flareFog = hg([hc(0xc79b6c, 0.16), hc(0x997449, 0.04), hc(0x564735, 0)])
    static let flareTint = hg([hc(0xc69861, 0.45), hc(0x957045, 0.17), hc(0x4e4738, 0)])
    static let lampFog = hg([hc(0xe4ae63, 0.35), hc(0xab7949, 0.06), hc(0x685034, 0)])
    static let fogCone = makeCone(mask: false)
    static let maskCone = makeCone(mask: true)

    /// Soft cone falloff never changes; rotate a small cached texture instead
    /// of evaluating twelve clipped gradients across the screen every frame.
    private static func makeCone(mask: Bool) -> CGImage? {
        let width = 1024, height = 256
        guard let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if mask { context.setBlendMode(.plusLighter) }
        context.setShouldAntialias(true)
        let origin = CGPoint(x: 0, y: 128)
        for layer in 0..<3 {
            let spread = [0.105, 0.075, 0.045][layer]
            let shape = CGMutablePath()
            shape.move(to: origin)
            shape.addLine(to: CGPoint(x: cos(spread) * 1024, y: 128 - sin(spread) * 1024))
            shape.addLine(to: CGPoint(x: cos(spread) * 1024, y: 128 + sin(spread) * 1024))
            shape.closeSubpath()
            context.saveGState()
            context.addPath(shape); context.clip()
            context.setAlpha(mask ? [0.08, 0.12, 0.21][layer] : [0.20, 0.20, 0.15][layer])
            context.drawLinearGradient(mask ? beamMask : beamFog, start: origin,
                                       end: CGPoint(x: 1024, y: 128), options: [])
            context.restoreGState()
        }
        return context.makeImage()
    }
}

private struct HadalBand {
    let image: CGImage
    let unit: CGRect
}

private struct HadalSprite {
    let bands: [HadalBand]
    let aspect: Double
    let horizontal: Bool

    init(image: CGImage, horizontal: Bool) {
        self.horizontal = horizontal
        aspect = Double(image.height) / Double(image.width)
        let length = horizontal ? image.height : image.width
        var strips: [HadalBand] = []
        for index in 0..<48 {
            let start = index * length / 48, end = (index + 1) * length / 48
            guard end > start else { continue }
            let r = horizontal ? CGRect(x: 0, y: start, width: image.width, height: end - start)
                : CGRect(x: start, y: 0, width: end - start, height: image.height)
            if let crop = image.cropping(to: r) {
                strips.append(HadalBand(image: crop,
                    unit: CGRect(x: r.minX / Double(image.width), y: r.minY / Double(image.height),
                                 width: r.width / Double(image.width), height: r.height / Double(image.height))))
            }
        }
        bands = strips
    }
}

private struct HadalAssets {
    let cityBackdrop: CGImage?
    let floor: CGImage?
    let oceanColor: CGColor
    let creatures: [HadalCreatureKind: HadalSprite]

    init(bundle: Bundle, override: URL?) {
        func load(_ name: String) -> CGImage? {
            let url = override.map { $0.deletingLastPathComponent().appendingPathComponent(name + ".png") }
                ?? bundle.url(forResource: name, withExtension: "png")
            guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options = [kCGImageSourceShouldCache: true,
                           kCGImageSourceShouldCacheImmediately: true] as CFDictionary
            return CGImageSourceCreateImageAtIndex(source, 0, options)
        }
        let city = load("hadal-city-seabed")
        cityBackdrop = city.flatMap(Self.featherEdges) ?? city
        floor = city.flatMap { source in
            source.cropping(to: CGRect(x: 0, y: Int(Double(source.height) * 0.78),
                                      width: source.width, height: Int(Double(source.height) * 0.22)))
        }.flatMap(Self.featherEdges)
        oceanColor = city.flatMap(Self.sampleWater) ?? hc(0x061a2c)
        var result: [HadalCreatureKind: HadalSprite] = [:]
        for kind in HadalCreatureKind.allCases {
            if let source = load(kind.assetName) {
                result[kind] = HadalSprite(image: source, horizontal: kind == .medusa || kind == .elder)
            }
        }
        creatures = result
    }

    private static func sampleWater(_ image: CGImage) -> CGColor? {
        guard let top = image.cropping(to: CGRect(x: 0, y: 0, width: image.width,
                                                 height: max(1, image.height / 10))),
              let sample = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                     bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        sample.interpolationQuality = .high
        sample.draw(top, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        guard let data = sample.data else { return nil }
        let pixel = data.assumingMemoryBound(to: UInt8.self)
        return CGColor(red: Double(pixel[0]) / 255, green: Double(pixel[1]) / 255,
                       blue: Double(pixel[2]) / 255, alpha: 1)
    }

    /// Runtime edge alpha blends wide and portrait layouts without altering the source.
    private static func featherEdges(_ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard let buffer = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                     bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        buffer.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let mask = hg([hc(0, 0), hc(0), hc(0), hc(0, 0)], [0, 0.045, 0.955, 1])
        buffer.setBlendMode(.destinationIn)
        buffer.drawLinearGradient(mask, start: .zero, end: CGPoint(x: w, y: 0), options: [])
        buffer.drawLinearGradient(mask, start: .zero, end: CGPoint(x: 0, y: h), options: [])
        return buffer.makeImage()
    }
}

private struct HadalBeam {
    let origin: CGPoint
    let angle: Double
    let length: Double
    let strength: Double
}

private struct HadalPainting {
    let c: CGContext
    let width: Double
    let height: Double
    let assets: HadalAssets
    let model: HadalSceneModel
    private var time: Double { model.elapsed }
    private var unit: Double { min(width / 1600, height / 1000) }
    private var canvas: CGRect {
        CGRect(x: (width - 1600 * unit) / 2, y: (height - 1000 * unit) / 2,
               width: 1600 * unit, height: 1000 * unit)
    }
    private var base: CGPoint { point(HadalPoint(x: 0.5, y: 0.59)) }
    private var cityRect: CGRect {
        CGRect(x: canvas.minX + canvas.width * 0.075, y: canvas.minY + canvas.height * 0.1175,
               width: canvas.width * 0.85, height: canvas.height * 0.85)
    }
    private var shieldCenter: CGPoint {
        point(HadalPoint(x: HadalCityLayout.domeCenterX, y: HadalCityLayout.domeBaseY))
    }
    private var shieldRX: Double { canvas.width * HadalCityLayout.domeRadiusX }
    private var shieldRY: Double { canvas.height * HadalCityLayout.domeRadiusY }

    func image(_ image: CGImage, in rect: CGRect) {
        c.saveGState()
        c.translateBy(x: rect.minX, y: rect.maxY)
        c.scaleBy(x: 1, y: -1)
        c.draw(image, in: CGRect(origin: .zero, size: rect.size))
        c.restoreGState()
    }

    private func point(_ p: HadalPoint) -> CGPoint {
        CGPoint(x: canvas.minX + p.x * canvas.width, y: canvas.minY + p.y * canvas.height)
    }

    private func shieldPath() -> CGPath {
        let p = CGMutablePath(), center = shieldCenter
        let k = 0.5522847498
        p.move(to: CGPoint(x: center.x - shieldRX, y: center.y))
        p.addCurve(to: CGPoint(x: center.x, y: center.y - shieldRY),
                   control1: CGPoint(x: center.x - shieldRX, y: center.y - shieldRY * k),
                   control2: CGPoint(x: center.x - shieldRX * k, y: center.y - shieldRY))
        p.addCurve(to: CGPoint(x: center.x + shieldRX, y: center.y),
                   control1: CGPoint(x: center.x + shieldRX * k, y: center.y - shieldRY),
                   control2: CGPoint(x: center.x + shieldRX, y: center.y - shieldRY * k))
        p.closeSubpath()
        return p
    }

    private func shieldArc(from: Double = 0, to: Double = .pi, samples: Int = 96) -> [CGPoint] {
        (0...samples).map { index in
            let angle = from + (to - from) * Double(index) / Double(samples)
            return CGPoint(x: shieldCenter.x + cos(angle) * shieldRX,
                           y: shieldCenter.y - sin(angle) * shieldRY)
        }
    }

    private func protected(_ p: CGPoint) -> Bool {
        let dx = (p.x - shieldCenter.x) / shieldRX
        let dy = (p.y - shieldCenter.y) / shieldRY
        return p.y <= shieldCenter.y && dx * dx + dy * dy <= 1
    }

    private func clipToOpenWater() {
        let ground = point(HadalPoint(x: 0, y: HadalCityLayout.seabedY)).y
        c.clip(to: CGRect(x: 0, y: 0, width: width, height: max(0, ground)))
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: 0, y: 0, width: width, height: height))
        outside.addPath(shieldPath())
        c.addPath(outside)
        c.clip(using: .evenOdd)
    }

    private func line(_ points: [CGPoint], color: UInt32, alpha: Double, thickness: Double = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for p in points.dropFirst() { c.addLine(to: p) }
        c.setStrokeColor(hc(color, alpha))
        c.setLineWidth(thickness)
        c.strokePath()
    }

    private func radial(_ gradient: CGGradient, center: CGPoint, radius: Double, alpha: Double = 1) {
        guard radius > 0, alpha > 0 else { return }
        c.saveGState()
        c.setAlpha(alpha)
        c.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                             endCenter: center, endRadius: radius, options: [])
        c.restoreGState()
    }

    func drawBackground() {
        c.setFillColor(assets.oceanColor)
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let depth = hg([hc(0x020914, 0.12), hc(0x020914, 0.48), hc(0x020914, 0.85)])
        c.drawLinearGradient(depth, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        // Repeat real rock texture at its natural proportions. Stretching one
        // thin strip to the whole portrait foreground would turn rocks into streaks.
        let ground = cityRect.minY + cityRect.height * 0.78
        if let floor = assets.floor, ground < height {
            let tileW = cityRect.width
            let tileH = tileW * Double(floor.height) / Double(floor.width)
            let stepX = tileW * 0.92, stepY = tileH * 0.90
            var y = ground
            var row = 0
            while y < height, row < 64 {
                var x = cityRect.minX - stepX * ceil(cityRect.minX / stepX)
                while x < width {
                    image(floor, in: CGRect(x: x, y: y, width: tileW, height: tileH))
                    x += stepX
                }
                row += 1
                y += stepY
            }
            let shadow = hg([hc(0x020812, 0), hc(0x020812, 0.75)])
            c.saveGState()
            c.clip(to: CGRect(x: 0, y: ground, width: width, height: height - ground))
            c.drawLinearGradient(shadow, start: CGPoint(x: 0, y: ground),
                                 end: CGPoint(x: 0, y: height), options: [])
            c.restoreGState()
        }
        if let city = assets.cityBackdrop { image(city, in: cityRect) }
        drawShieldLattice()
    }

    private func drawShieldLattice() {
        c.saveGState()
        c.setShouldAntialias(true)
        c.addPath(shieldPath()); c.clip()
        let tint = hg([hc(0x6ca6ae, 0.025), hc(0x244c5d, 0.008)])
        c.drawLinearGradient(tint, start: CGPoint(x: shieldCenter.x, y: shieldCenter.y - shieldRY),
                             end: shieldCenter, options: [])
        for fraction in [-0.78, -0.48, 0.0, 0.48, 0.78] {
            let points = (0...48).map { index -> CGPoint in
                let a = Double(index) / 48 * .pi / 2
                return CGPoint(x: shieldCenter.x + shieldRX * fraction * sin(a),
                               y: shieldCenter.y - shieldRY * cos(a))
            }
            line(points, color: 0x5b8e9b, alpha: 0.10, thickness: max(0.6, unit * 0.8))
        }
        for fraction in [0.25, 0.45, 0.65, 0.83, 0.96] {
            let y = shieldCenter.y - shieldRY * sqrt(1 - fraction * fraction)
            let points = (0...64).map { index -> CGPoint in
                let a = Double(index) / 64 * .pi
                return CGPoint(x: shieldCenter.x + cos(a) * shieldRX * fraction,
                               y: y + sin(a) * shieldRY * 0.055 * fraction)
            }
            line(points, color: 0x4d8493, alpha: 0.11, thickness: max(0.6, unit * 0.7))
        }
        c.restoreGState()
        line(shieldArc(), color: 0x67b7c7, alpha: 0.055, thickness: max(2, unit * 7))
        line(shieldArc(), color: 0x6db6c4, alpha: 0.32, thickness: max(0.8, unit * 1.15))
        c.setStrokeColor(hc(0x6095a3, 0.14))
        c.setLineWidth(max(0.6, unit))
        c.strokeEllipse(in: CGRect(x: shieldCenter.x - shieldRX, y: shieldCenter.y - 16 * unit,
                                   width: shieldRX * 2, height: 32 * unit))
    }

    private func drawShieldMotion() {
        c.saveGState()
        c.setShouldAntialias(true)
        c.setLineDash(phase: time.truncatingRemainder(dividingBy: 64) * 5 * unit,
                      lengths: [14 * unit, 150 * unit])
        line(shieldArc(), color: 0x9ed2d5, alpha: 0.11 + sin(time / 13) * 0.025,
             thickness: max(0.8, unit * 1.25))
        c.restoreGState()
        for charge in model.charges where charge.burst > 0 {
            let target = point(charge.target)
            let angle = max(0.04, min(.pi - 0.04,
                atan2((shieldCenter.y - target.y) / shieldRY, (target.x - shieldCenter.x) / shieldRX)))
            line(shieldArc(from: max(0, angle - 0.16), to: min(.pi, angle + 0.16), samples: 24),
                 color: 0x8ad3da, alpha: charge.burst * 0.25, thickness: max(1, unit * 2.2))
        }
    }

    func drawSearchlights() {
        for beam in beams() { cone(beam, mask: false) }
    }

    func drawCreature(_ event: HadalEncounter) {
        guard let sprite = assets.creatures[event.kind] else { return }
        let nominal: Double
        let anchor: CGPoint
        switch event.kind {
        case .maw: nominal = 1310; anchor = CGPoint(x: 0.23, y: 0.48)
        case .ribbon: nominal = 1630; anchor = CGPoint(x: 0.20, y: 0.48)
        case .medusa: nominal = 675; anchor = CGPoint(x: 0.5, y: 0.28)
        case .carapace: nominal = 930; anchor = CGPoint(x: 0.35, y: 0.45)
        case .elder: nominal = 650; anchor = CGPoint(x: 0.5, y: 0.30)
        }
        let w = nominal * unit * event.scale
        let h = w * sprite.aspect
        let center = point(event.center)
        c.saveGState()
        clipToOpenWater()
        c.setAlpha(event.visibility * 0.90)
        c.translateBy(x: center.x, y: center.y)
        let recoil = hs((event.age - HadalSceneModel.chargeImpactAge) / 6)
        c.rotate(by: recoil * Double(event.facing) * (event.kind == .carapace ? 0.05 : -0.10))
        if event.kind != .medusa && event.kind != .elder { c.scaleBy(x: -Double(event.facing), y: 1) }
        for band in sprite.bands {
            if sprite.horizontal {
                let v0 = band.unit.minY, v1 = band.unit.maxY
                func sway(_ v: Double) -> Double {
                    sin(time / 10 + v * 5.6) * (1 + v * v * 17) * unit
                }
                let top = sway(v0), bottom = sway(v1), bh = band.unit.height * h
                c.saveGState()
                c.translateBy(x: -anchor.x * w + top, y: -anchor.y * h + v0 * h)
                c.concatenate(CGAffineTransform(a: 1, b: 0, c: (bottom - top) / bh, d: 1, tx: 0, ty: 0))
                image(band.image, in: CGRect(x: 0, y: 0, width: w, height: bh))
                c.restoreGState()
            } else {
                let u0 = band.unit.minX, u1 = band.unit.maxX
                func sway(_ u: Double) -> Double {
                    let amplitude = event.kind == .carapace ? 4.0 : 23.0
                    return sin(time / 8 - u * 6) * (1 + u * u * amplitude) * unit
                }
                let first = sway(u0), last = sway(u1), bw = band.unit.width * w
                c.saveGState()
                c.translateBy(x: -anchor.x * w + u0 * w, y: -anchor.y * h + first)
                c.concatenate(CGAffineTransform(a: 1, b: (last - first) / bw, c: 0, d: 1, tx: 0, ty: 0))
                image(band.image, in: CGRect(x: 0, y: 0, width: bw, height: h))
                c.restoreGState()
            }
        }
        c.restoreGState()
        // Local warm scatter is clipped to the already rendered anatomy.
        c.saveGState()
        c.setBlendMode(.sourceAtop)
        c.setFillColor(hc(0x092633, 0.26))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        for flare in model.flares {
            radial(HadalPaint.flareTint, center: point(flare.position),
                   radius: flare.radius * 1600 * unit, alpha: flare.strength)
        }
        c.restoreGState()
    }

    func drawIllumination() {
        // Almost no ambient animal visibility. Most of the silhouette stays unknown.
        c.setFillColor(hc(0xffffff, 0.012))
        c.fill(CGRect(x: 0, y: 0, width: width, height: height))
        c.saveGState(); c.setBlendMode(.plusLighter)
        for beam in beams() { cone(beam, mask: true) }
        for flare in model.flares {
            radial(HadalPaint.whiteLight, center: point(flare.position),
                   radius: flare.radius * 1600 * unit, alpha: flare.strength * 0.88)
        }
        for charge in model.charges where charge.burst > 0 {
            radial(HadalPaint.whiteLight, center: point(charge.target),
                   radius: (110 + charge.burst * 115) * unit, alpha: charge.burst * 0.75)
        }
        c.restoreGState()
    }

    private func beams() -> [HadalBeam] {
        let mounts: [(Double, Double, Double)] = [(0.245, 0.480, -2.5), (0.445, 0.350, -1.95),
                                                  (0.565, 0.405, -1.14), (0.780, 0.505, -0.44)]
        return mounts.enumerated().map { index, mount in
            let origin = point(HadalPoint(x: mount.0, y: mount.1))
            let phase = time.truncatingRemainder(dividingBy: 70 + Double(index) * 9)
                / (70 + Double(index) * 9) * 2 * .pi
            let patrol = mount.2 + sin(phase + Double(index)) * 0.42
            var angle = patrol
            var strength = 0.46
            if let event = model.encounter {
                let target = point(event.center)
                // Hand the target between the two sides over a broad central
                // band, rather than switching whole searchlights at x == 0.5.
                let rightWeight = hs((event.center.x - 0.38) / 0.24)
                let sideWeight = index < 2 ? 1 - rightWeight : rightWeight
                let blend = min(hs((event.age - 3) / 7),
                                hs((event.duration - event.age) / 12)) * sideWeight
                var tracked = atan2(target.y - origin.y, target.x - origin.x)
                // All species now remain in the continuous upper angle sector.
                tracked += sin(time / 9 + Double(index) * 1.4) * 0.12
                angle = patrol + (tracked - patrol) * blend
                strength += 0.20 * blend
            }
            return HadalBeam(origin: origin, angle: angle,
                             length: 1130 * unit, strength: strength)
        }
    }

    private func cone(_ beam: HadalBeam, mask: Bool) {
        guard let texture = mask ? HadalPaint.maskCone : HadalPaint.fogCone else { return }
        c.saveGState()
        c.translateBy(x: beam.origin.x, y: beam.origin.y)
        c.rotate(by: beam.angle)
        c.setAlpha(mask ? beam.strength : 1)
        c.interpolationQuality = .low
        image(texture, in: CGRect(x: 0, y: -beam.length * 0.125,
                                  width: beam.length, height: beam.length * 0.25))
        c.restoreGState()
    }

    func drawForeground() {
        for flare in model.flares {
            radial(HadalPaint.flareFog, center: point(flare.position),
                   radius: flare.radius * 1600 * unit, alpha: flare.strength)
        }
        drawShieldMotion()
        drawStationWindows()
        drawDefence()
        drawMarineSnow()
        drawBubbles()
    }

    private func drawStationWindows() {
        let positions: [(Double, Double)] = [(0.15, 0.58), (0.27, 0.54), (0.41, 0.59), (0.50, 0.38),
                                            (0.60, 0.58), (0.78, 0.53), (0.43, 0.30), (0.54, 0.47)]
        for (id, p) in positions.enumerated() {
            let r = cityRect
            radial(HadalPaint.lampFog,
                   center: CGPoint(x: r.minX + p.0 * r.width, y: r.minY + p.1 * r.height),
                   radius: 15 * unit, alpha: model.windowLight(id: id) * 0.38)
        }
    }

    private func drawDefence() {
        for flare in model.flares {
            let p = point(flare.position)
            radial(HadalPaint.lampFog, center: p, radius: 20 * unit, alpha: flare.strength)
            c.setFillColor(hc(0xe5b77e, flare.strength * 0.8))
            c.fillEllipse(in: CGRect(x: p.x - 2 * unit, y: p.y - 4 * unit,
                                     width: 4 * unit, height: 8 * unit))
            for index in 0..<9 {
                let i = Double(index)
                let drift = (flare.age * 0.12 + i / 9).truncatingRemainder(dividingBy: 1)
                let fade = sin(drift * .pi) * flare.strength
                let x = p.x + sin(drift * 5 + i) * 4 * unit
                let y = p.y - drift * 39 * unit
                c.setFillColor(hc(0xc28c55, fade * 0.30))
                c.fill(CGRect(x: x, y: y, width: max(1, unit), height: max(1, unit)))
            }
        }
        for charge in model.charges {
            let p = point(charge.position)
            if charge.progress < 1 {
                let o = point(charge.origin), t = point(charge.target)
                let angle = atan2(t.y - o.y, t.x - o.x)
                let launch = hs(charge.progress / 0.08)
                line([CGPoint(x: p.x - cos(angle) * 18 * unit, y: p.y - sin(angle) * 18 * unit), p],
                     color: 0x648e91, alpha: launch * 0.38, thickness: max(1, 2 * unit))
                c.setFillColor(hc(0xb2bbad, launch * 0.75))
                c.fillEllipse(in: CGRect(x: p.x - 2 * unit, y: p.y - 2 * unit,
                                         width: 4 * unit, height: 4 * unit))
            }
            if charge.burst > 0 {
                let target = point(charge.target)
                let age = max(0, (model.encounter?.age ?? 0) - HadalSceneModel.chargeImpactAge)
                let radius = (12 + age * 40) * unit
                c.setStrokeColor(hc(0x86a6a3, charge.burst * 0.20))
                c.setLineWidth(max(1, unit))
                c.strokeEllipse(in: CGRect(x: target.x - radius, y: target.y - radius * 0.62,
                                          width: radius * 2, height: radius * 1.24))
                radial(HadalPaint.flareFog, center: target, radius: 155 * unit, alpha: charge.burst * 0.7)
            }
        }
    }

    private func drawMarineSnow() {
        for (index, mote) in HadalMote.field.enumerated() {
            let x = (mote.x * width + time * mote.depth * 0.48 + sin(time / 31 + mote.phase) * 2)
                .truncatingRemainder(dividingBy: width)
            let positiveX = x < 0 ? x + width : x
            let y = (mote.y * height + time * (0.25 + mote.depth * 0.6))
                .truncatingRemainder(dividingBy: height)
            if protected(CGPoint(x: positiveX, y: y)) { continue }
            if y > point(HadalPoint(x: 0, y: HadalCityLayout.seabedY)).y { continue }
            let edge = min(1, min(positiveX, width - positiveX) / 12) * min(1, min(y, height - y) / 12)
            c.setFillColor(hc(0x507180, edge * (0.06 + mote.depth * 0.09)))
            let size = index % 19 == 0 ? 1.4 : 0.8
            c.fill(CGRect(x: floor(positiveX), y: floor(y), width: size, height: size))
        }
    }

    private func drawBubbles() {
        let vent = point(HadalPoint(x: 0.94, y: 0.72))
        for index in 0..<17 {
            let i = Double(index)
            let age = (time / 23 + i / 17).truncatingRemainder(dividingBy: 1)
            let x = vent.x + sin(i * 2.3 + age * 7) * 6 * unit
            let y = vent.y - age * 150 * unit
            let size = (0.8 + age * 1.3) * unit
            c.setStrokeColor(hc(0x6d8b90, sin(age * .pi) * 0.13))
            c.setLineWidth(max(0.5, unit * 0.7))
            c.strokeEllipse(in: CGRect(x: x, y: y, width: size, height: size))
        }
    }
}

private struct HadalMote {
    let x: Double, y: Double, depth: Double, phase: Double
    static let field: [HadalMote] = {
        var state: UInt64 = 0x4ADAC0DE
        func next() -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Double(state >> 11) / Double(UInt64.max >> 11)
        }
        return (0..<210).map { _ in
            HadalMote(x: next(), y: next(), depth: 0.3 + next() * 0.7, phase: next() * 2 * .pi)
        }
    }()
}
