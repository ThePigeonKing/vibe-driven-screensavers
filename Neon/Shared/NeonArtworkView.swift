import AppKit
import CoreGraphics
import ImageIO

/// The illustration and every animated detail share one small raster. The final
/// enlargement uses integer physical pixels, including on Retina displays.
final class NeonArtworkView: NSView {
    var model = NeonAnimationModel()
    /// Only the standalone rendering tools use an override. Installed savers
    /// always read their own bundled artwork and never a developer's path.
    var assetURLOverride: URL? {
        didSet { if oldValue != assetURLOverride { illustration = nil } }
    }
    private var illustration: NeonIllustration?
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
        let physicalPixel = max(1, floor(sqrt(backing.width * backing.height / (1280 * 800))))
        let width = max(1, Int(ceil(backing.width / physicalPixel)))
        let height = max(1, Int(ceil(backing.height / physicalPixel)))
        let size = CGSize(width: width, height: height)
        if rasterSize != size {
            raster = CGContext(data: nil, width: width, height: height,
                               bitsPerComponent: 8, bytesPerRow: width * 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            rasterSize = size
        }
        if illustration == nil {
            let url = assetURLOverride ?? Bundle(for: NeonArtworkView.self)
                .url(forResource: "neon-district", withExtension: "png")
            illustration = url.flatMap(NeonIllustration.init)
        }
        guard let raster else { return }
        raster.saveGState()
        raster.setShouldAntialias(false)
        raster.interpolationQuality = .none
        raster.translateBy(x: 0, y: CGFloat(height))
        raster.scaleBy(x: 1, y: -1)
        let canvas = NeonCanvas(context: raster)
        canvas.rect(0, 0, width, height, 0x051326)
        if let illustration {
            NeonScene(canvas: canvas, width: width, height: height,
                      illustration: illustration, model: model).draw()
        }
        raster.restoreGState()
        guard let image = raster.makeImage() else { return }
        destination.saveGState()
        destination.setShouldAntialias(false)
        destination.interpolationQuality = .none
        let pointPixel = physicalPixel / backingScale
        destination.draw(image, in: CGRect(x: 0, y: 0,
                                           width: CGFloat(width) * pointPixel,
                                           height: CGFloat(height) * pointPixel))
        destination.restoreGState()
    }
}

private struct NeonIllustration {
    let image: CGImage

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let original = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let buffer = CGContext(data: nil, width: 1152, height: 720,
                                     bitsPerComponent: 8, bytesPerRow: 1152 * 4,
                                     space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        buffer.interpolationQuality = .none
        buffer.setShouldAntialias(false)
        buffer.draw(original, in: CGRect(x: 0, y: 0, width: 1152, height: 720))
        guard let image = buffer.makeImage() else { return nil }
        self.image = image
    }
}

private struct NeonCanvas {
    let context: CGContext

    func rect(_ x: Int, _ y: Int, _ width: Int, _ height: Int, _ color: UInt32,
              alpha: Double = 1) {
        guard width > 0, height > 0, alpha > 0 else { return }
        context.setFillColor(CGColor(red: CGFloat((color >> 16) & 255) / 255,
                                    green: CGFloat((color >> 8) & 255) / 255,
                                    blue: CGFloat(color & 255) / 255,
                                    alpha: CGFloat(min(1, alpha))))
        context.fill(CGRect(x: x, y: y, width: width, height: height))
    }

    func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ color: UInt32,
              alpha: Double = 1) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var error = dx + dy
        while true {
            rect(x, y, 1, 1, color, alpha: alpha)
            if x == x1 && y == y1 { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }

    func ellipse(x: Int, y: Int, rx: Int, ry: Int, color: UInt32, alpha: Double = 1) {
        var previous = (x + rx, y)
        for sample in 1...64 {
            let angle = Double(sample) / 64 * 2 * .pi
            let point = (x + Int((cos(angle) * Double(rx)).rounded()),
                         y + Int((sin(angle) * Double(ry)).rounded()))
            line(previous.0, previous.1, point.0, point.1, color, alpha: alpha)
            previous = point
        }
    }

    /// Bitmap lettering stays crisp; no system font or antialiasing is involved.
    func text(_ text: String, x: Int, y: Int, color: UInt32, alpha: Double = 1) {
        var cursor = x
        for character in text {
            let glyph = NeonPixelFont.glyphs[character] ?? [0, 0, 0, 0, 0]
            for row in 0..<5 {
                for column in 0..<3 where glyph[row] & (1 << (2 - column)) != 0 {
                    rect(cursor + column, y + row, 1, 1, color, alpha: alpha)
                }
            }
            cursor += 4
        }
    }

    func image(_ image: CGImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}

private struct NeonScene {
    let canvas: NeonCanvas
    let width: Int
    let height: Int
    let illustration: NeonIllustration
    let model: NeonAnimationModel
    private var time: Double { model.time }

    func draw() {
        let scale = min(CGFloat(width) / 640, CGFloat(height) / 400)
        let scene = CGRect(x: (CGFloat(width) - 640 * scale) / 2,
                           y: (CGFloat(height) - 400 * scale) / 2,
                           width: 640 * scale, height: 400 * scale)
        drawSurroundings(scene: scene)
        canvas.image(illustration.image, in: scene)
        canvas.context.saveGState()
        canvas.context.translateBy(x: scene.minX, y: scene.minY)
        canvas.context.scaleBy(x: scale, y: scale)
        canvas.context.clip(to: CGRect(x: 0, y: 0, width: 640, height: 400))
        drawTrain()
        drawBillboards()
        drawCarLights()
        drawExhaust()
        drawPuddleLight()
        canvas.context.restoreGState()
    }

    /// Preserve the entire car and all signs. Unusual displays frame the hero
    /// scene with a quiet procedural skyline and wet pavement. No mirrored
    /// advertising, stretched edge pixels or extra image assets are needed.
    private func drawSurroundings(scene: CGRect) {
        let horizontalPadding = scene.minX
        let verticalPadding = scene.minY
        guard max(horizontalPadding, verticalPadding) > 2 else { return }
        let horizon = Int(scene.minY + scene.height * 0.82)
        for band in 0..<24 {
            let y = height * band / 24, next = height * (band + 1) / 24
            canvas.rect(0, y, width, next - y, 0x102f43,
                        alpha: 0.2 * Double(band) / 24)
        }
        for id in 0..<max(12, width / 18) {
            let x = neonHash(id + 271) % width
            let y = neonHash(id + 311) % max(1, horizon / 2)
            canvas.rect(x, y, 1, 1, 0x53677f, alpha: 0.22)
        }
        for id in 0..<5 {
            let w = 40 + neonHash(id + 12) % 100
            let period = Double(width + w)
            let x = Int((time * 0.18 + Double(id * 157)).truncatingRemainder(dividingBy: period)) - w
            let y = max(5, horizon / 3 + id * 9)
            canvas.rect(x + 10, y, w - 20, 3, 0x14334a, alpha: 0.28)
            canvas.rect(x, y + 3, w, 3, 0x14334a, alpha: 0.2)
        }
        var x = -20, id = 0
        while x < width {
            let w = 19 + neonHash(id + 717) % 32
            let h = 48 + neonHash(id + 821) % max(50, min(180, horizon / 2))
            let y = horizon - h
            canvas.rect(x, y, w, h, 0x071323)
            canvas.rect(x + 4, y - 4, w - 10, 4, 0x0b192b)
            canvas.rect(x + w - 3, y, 2, h, 0x183448, alpha: 0.5)
            if id % 3 == 0 {
                canvas.rect(x + w / 2, y - 15, 1, 11, 0x25344b, alpha: 0.6)
                canvas.rect(x + w / 2, y - 16, 1, 1, 0xcc47aa, alpha: 0.5)
            }
            for row in 0..<(h / 7) {
                for column in 0..<(w / 5) where neonHash(id * 79 + row * 11 + column) % 4 == 0 {
                    canvas.rect(x + 3 + column * 5, y + 6 + row * 7, 1, 2,
                                id % 4 == 0 ? 0x925484 : 0x2c687b, alpha: 0.4)
                }
            }
            x += w + 4
            id += 1
        }
        canvas.rect(0, horizon, width, height - horizon, 0x070f1c)
        for id in 0..<max(35, width / 3) {
            let x = neonHash(id + 104) % width
            let y = horizon + neonHash(id + 201) % max(1, height - horizon)
            let w = 2 + neonHash(id + 78) % 16
            let pulse = 0.8 + 0.2 * sin(time * 0.13 + Double(id))
            canvas.rect(x, y, w, 1, id % 5 == 0 ? 0x963477 : 0x25667c,
                        alpha: pulse * 0.18)
        }
        // A restrained dark mount makes the boundary intentional, like a view
        // through a city window, instead of pretending the artwork is wider.
        let left = Int(scene.minX), right = Int(ceil(scene.maxX))
        let top = Int(scene.minY), bottom = Int(ceil(scene.maxY))
        canvas.rect(left - 2, top - 2, right - left + 4, 2, 0x020916)
        canvas.rect(left - 2, bottom, right - left + 4, 2, 0x020916)
        canvas.rect(left - 2, top, 2, bottom - top, 0x020916)
        canvas.rect(right, top, 2, bottom - top, 0x020916)
        for corner in [(left - 2, top - 2), (right - 6, top - 2),
                       (left - 2, bottom + 1), (right - 6, bottom + 1)] {
            canvas.rect(corner.0, corner.1, 8, 1, 0x2c7087, alpha: 0.5)
        }
    }

    private func drawBillboards() {
        // Each display has its own slow crossfade AND animation inside the ad.
        // Coordinates follow the original screen planes, preserving their frame.
        screen(id: 0, origin: CGPoint(x: 446, y: 99),
               u: CGPoint(x: 121, y: -30), v: CGPoint(x: 0, y: 58),
               width: 112, height: 54, background: 0x075568) { ink, variant, alpha in
            let titles = ["NOVA LINK", "ORBITAL", "NIGHT WAVE", "CITY ROUTE"]
            ink.text(titles[variant], x: 6, y: 5, color: 0xb8fff2, alpha: alpha)
            ink.line(6, 13, 104, 13, 0x51ced8, alpha: alpha * 0.6)
            for row in stride(from: 17, to: 52, by: 7) {
                ink.line(6, row, 105, row, 0x298b9c, alpha: alpha * 0.35)
            }
            for column in stride(from: 12, to: 106, by: 12) {
                ink.line(column, 16, column, 51, 0x298b9c, alpha: alpha * 0.3)
            }
            switch variant {
            case 0:
                drawHologram(ink: ink, x: 77, y: 32, radius: 16,
                             phase: time * 0.14, alpha: alpha)
                ink.text("SYNC", x: 8, y: 21, color: 0xa3efef, alpha: alpha * 0.9)
                for row in 0..<4 {
                    let w = 9 + Int((0.5 + 0.5 * sin(time * 0.3 + Double(row))) * 18)
                    ink.rect(8, 31 + row * 4, w, 1, 0x61dce0, alpha: alpha * 0.8)
                }
            case 1:
                ink.ellipse(x: 73, y: 32, rx: 17, ry: 14, color: 0x81ffff, alpha: alpha)
                let rotation = time.truncatingRemainder(dividingBy: 28) / 28 * 2 * .pi
                ink.ellipse(x: 73, y: 32, rx: max(2, Int(abs(cos(rotation)) * 16)),
                            ry: 14, color: 0x7df5f0, alpha: alpha * 0.75)
                ink.ellipse(x: 73, y: 32, rx: 17, ry: 5, color: 0xf37bcc, alpha: alpha * 0.9)
                let satellite = (73 + Int(cos(rotation) * 23), 32 + Int(sin(rotation) * 8))
                ink.rect(satellite.0, satellite.1, 2, 2, 0xf4ffe4, alpha: alpha)
                ink.text("LUMA", x: 8, y: 22, color: 0xb8fff2, alpha: alpha)
                ink.text("FM 08", x: 8, y: 32, color: 0xe798dd, alpha: alpha * 0.85)
            case 2:
                for bar in 0..<24 {
                    let wave = 0.5 + 0.5 * sin(time * 0.44 + Double(bar) * 0.43)
                    let h = 3 + Int(wave * 23)
                    ink.rect(8 + bar * 4, 47 - h, 2, h,
                             bar % 4 == 0 ? 0xf18bd7 : 0x6ceee2, alpha: alpha * 0.88)
                }
                ink.line(8, 48, 103, 48, 0xb8fff2, alpha: alpha * 0.9)
            default:
                let nodes = [(14, 40), (31, 29), (50, 34), (72, 22), (98, 29)]
                for index in 0..<nodes.count - 1 {
                    ink.line(nodes[index].0, nodes[index].1, nodes[index + 1].0,
                             nodes[index + 1].1, 0x82f5ed, alpha: alpha * 0.9)
                }
                for (index, node) in nodes.enumerated() {
                    ink.rect(node.0 - 1, node.1 - 1, 3, 3, 0xf9b0ec, alpha: alpha)
                    ink.text(String(index + 1), x: node.0 - 1, y: node.1 + 5,
                             color: 0x9ee9ee, alpha: alpha * 0.85)
                }
                let travel = time.truncatingRemainder(dividingBy: 19) / 19 * 4
                let segment = min(3, Int(travel)), fraction = travel - Double(segment)
                let a = nodes[segment], b = nodes[segment + 1]
                let x = Int(Double(a.0) + Double(b.0 - a.0) * fraction)
                let y = Int(Double(a.1) + Double(b.1 - a.1) * fraction)
                ink.rect(x - 2, y - 1, 5, 2, 0xf5fff3, alpha: alpha)
            }
        }
        screen(id: 1, origin: CGPoint(x: 599, y: 83),
               u: CGPoint(x: 30, y: -9), v: CGPoint(x: 0, y: 88),
               width: 28, height: 86, background: 0x421747) { ink, variant, alpha in
            let titles = ["ION", "NOVA", "LUMA", "FM"]
            ink.text(titles[variant], x: 5, y: 6, color: 0xffb7e7, alpha: alpha)
            if variant % 2 == 0 {
                drawHologram(ink: ink, x: 14, y: 31, radius: 8,
                             phase: -time * 0.11 + Double(variant), alpha: alpha)
            } else {
                ink.ellipse(x: 14, y: 29, rx: 9, ry: 11, color: 0xff82d2, alpha: alpha)
                ink.ellipse(x: 14, y: 29, rx: 12, ry: 4, color: 0x9de9ee, alpha: alpha * 0.85)
                let angle = time.truncatingRemainder(dividingBy: 22) / 22 * 2 * .pi
                ink.rect(14 + Int(cos(angle) * 12), 29 + Int(sin(angle) * 4),
                         2, 1, 0xeeffff, alpha: alpha)
            }
            for row in 0..<4 {
                ink.rect(5, 48 + row * 3, 6 + neonHash(variant * 11 + row) % 14, 1,
                         0xf290d5, alpha: alpha * 0.65)
            }
            for bar in 0..<7 {
                let h = 3 + Int((0.5 + 0.5 * sin(time * 0.35 + Double(bar))) * 15)
                ink.rect(4 + bar * 3, 80 - h, 1, h, 0xffa1de, alpha: alpha * 0.9)
            }
        }
        screen(id: 2, origin: CGPoint(x: 216, y: 126),
               u: CGPoint(x: 18, y: 6), v: CGPoint(x: 0, y: 63),
               width: 18, height: 62, background: 0x501a64) { ink, variant, alpha in
            let angle = time.truncatingRemainder(dividingBy: 17) / 17 * 2 * .pi
            ink.ellipse(x: 9, y: 17, rx: 6, ry: 8, color: 0xfface3, alpha: alpha)
            ink.ellipse(x: 9, y: 17, rx: max(1, Int(abs(cos(angle)) * 6)), ry: 8,
                        color: variant % 2 == 0 ? 0xa9ffff : 0xff75ce, alpha: alpha * 0.8)
            for row in 0..<4 {
                let bits = neonHash(variant * 31 + row)
                for col in 0..<5 where bits & (1 << col) != 0 {
                    ink.rect(2 + col * 3, 32 + row * 3, 2, 1, 0xffa0db, alpha: alpha * 0.85)
                }
            }
            let scan = 46 + Int(time.truncatingRemainder(dividingBy: 11) / 11 * 12)
            ink.rect(2, scan, 14, 1, 0x93ffef, alpha: alpha * 0.55)
            ink.line(2, 58, 16, 58, 0xfe9cdc, alpha: alpha * 0.75)
        }
        let portrait = model.billboard(id: 3)
        let phase = time.truncatingRemainder(dividingBy: 29) / 29
        // The portrait stays intact. Its lower holographic badge rotates and
        // adopts the sign's independently scheduled accent color.
        let accents: [UInt32] = [0x95ffff, 0xffa2ea, 0xd7c4ff, 0x8aedcd]
        for id in 0..<60 {
            let angle = Double(id) / 60 * 2 * .pi
            let x = 116 + Int(cos(angle) * 15), y = 155 + Int(sin(angle) * 15)
            let distance = abs(Double(id) / 60 - phase)
            let alpha = max(0, 1 - min(distance, 1 - distance) * 8) * 0.6
            canvas.rect(x, y, 1, 1, accents[portrait.previous],
                        alpha: alpha * portrait.brightness * (1 - portrait.blend))
            canvas.rect(x, y, 1, 1, accents[portrait.current],
                        alpha: alpha * portrait.brightness * portrait.blend)
        }
        canvas.ellipse(x: 116, y: 155, rx: max(2, Int(abs(cos(phase * 2 * .pi)) * 12)),
                       ry: 12, color: 0xb7fdf4, alpha: portrait.brightness * 0.6)
        let side = model.billboard(id: 4)
        let row = 31 + Int(time.truncatingRemainder(dividingBy: 24) / 24 * 153)
        for offset in -4...4 {
            canvas.rect(147, row + offset, 6, 1, 0x9cf8ed,
                        alpha: (1 - Double(abs(offset)) / 5) * 0.44 * side.brightness)
        }
    }

    private func drawHologram(ink: NeonCanvas, x: Int, y: Int, radius: Int,
                              phase: Double, alpha: Double) {
        let angle = phase.truncatingRemainder(dividingBy: 2 * .pi)
        let tilt = 0.45, ct = cos(tilt), st = sin(tilt)
        var vertices: [(Int, Int)] = []
        for index in 0..<8 {
            let vx = index & 1 == 0 ? -1.0 : 1.0
            let vy = index & 2 == 0 ? -1.0 : 1.0
            let vz = index & 4 == 0 ? -1.0 : 1.0
            let rx = vx * cos(angle) + vz * sin(angle)
            let rz = -vx * sin(angle) + vz * cos(angle)
            let ry = vy * ct - rz * st
            let perspective = 0.65 + (vy * st + rz * ct) * 0.07
            vertices.append((x + Int((rx * Double(radius) * perspective).rounded()),
                             y + Int((ry * Double(radius) * perspective).rounded())))
        }
        for index in 0..<8 {
            for bit in [1, 2, 4] where index & bit == 0 {
                let a = vertices[index], b = vertices[index | bit]
                ink.line(a.0, a.1, b.0, b.1, bit == 4 ? 0xf0a2de : 0x8bfff1,
                         alpha: alpha * (bit == 4 ? 0.8 : 1))
            }
        }
        for vertex in vertices {
            ink.rect(vertex.0, vertex.1, 1, 1, 0xedfff8, alpha: alpha)
        }
    }

    private func screen(id: Int, origin: CGPoint, u: CGPoint, v: CGPoint,
                        width: Int, height: Int, background: UInt32,
                        artwork: (NeonCanvas, Int, Double) -> Void) {
        let state = model.billboard(id: id)
        let c = canvas.context
        c.saveGState()
        c.concatenate(CGAffineTransform(a: u.x / CGFloat(width), b: u.y / CGFloat(width),
                                       c: v.x / CGFloat(height), d: v.y / CGFloat(height),
                                       tx: origin.x, ty: origin.y))
        c.clip(to: CGRect(x: 0, y: 0, width: width, height: height))
        canvas.rect(0, 0, width, height, background, alpha: 0.96)
        if state.blend < 1 { artwork(canvas, state.previous, (1 - state.blend) * state.brightness) }
        artwork(canvas, state.current, state.blend * state.brightness)
        c.restoreGState()
    }

    private func drawTrain() {
        guard let train = model.train else { return }
        let c = canvas.context
        c.saveGState()
        // The small distant bridge goes down slightly toward the right. The
        // window clips arrivals behind buildings instead of fading a whole car.
        c.concatenate(CGAffineTransform(a: 1, b: 0.085, c: 0, d: 1, tx: 279, ty: 185))
        c.clip(to: CGRect(x: 0, y: -9, width: 143, height: 10))
        let carWidth = 18, gap = 2
        let length = train.carCount * (carWidth + gap) - gap
        let travel = Double(143 + length + 4)
        let position = train.direction > 0
            ? -Double(length) - 2 + train.progress * travel
            : 145 - train.progress * travel
        for index in 0..<train.carCount {
            let x = Int(position) + index * (carWidth + gap)
            canvas.rect(x + 2, -7, carWidth - 4, 1, 0x98e7ee, alpha: 0.8)
            canvas.rect(x + 1, -6, carWidth - 2, 5, 0x215c76)
            canvas.rect(x, -4, carWidth, 3, 0x306e88)
            canvas.rect(x + 1, -1, carWidth - 2, 1, 0x0b203c)
            canvas.rect(x + 2, 0, carWidth - 4, 1, 0x61dbe3, alpha: 0.7)
            for window in 0..<3 {
                canvas.rect(x + 3 + window * 5, -5, 3, 2,
                            (index + window) % 5 == 0 ? 0xffa4d8 : 0x95f3ec, alpha: 0.95)
            }
            if index < train.carCount - 1 {
                canvas.rect(x + carWidth, -3, gap, 1, 0x7198b4, alpha: 0.85)
            }
        }
        let front = train.direction > 0 ? Int(position) + length - 1 : Int(position)
        canvas.rect(front, -4, 1, 2, 0xe8fff2)
        let tail = train.direction > 0 ? Int(position) : Int(position) + length - 1
        canvas.rect(tail, -3, 1, 1, 0xf387c5)
        c.restoreGState()
    }

    private func drawCarLights() {
        let light = model.carLight
        // The source image already has illuminated tail lamps. A subtle dark
        // veil lets their intensity fall as well as rise without covering trim.
        for lamp in [(191, 269, 26), (266, 268, 30)] {
            for y in [0, 4, 8] {
                canvas.rect(lamp.0, lamp.1 + y, lamp.2, 1, 0x150d22, alpha: (1 - light) * 0.42)
                canvas.rect(lamp.0 + 1, lamp.1 + y, lamp.2 - 2, 1, 0xff9ade, alpha: light * 0.2)
            }
        }
        canvas.line(426, 316, 507, 316, 0x7aeaf2, alpha: model.underglow * 0.42)
        canvas.line(597, 296, 609, 299, 0xff77d9, alpha: light * 0.45)
        for row in 0..<4 {
            canvas.rect(433 + row * 4, 326 + row * 2, 66 - row * 9, 1,
                        0x34c7d3, alpha: model.underglow * (0.13 - Double(row) * 0.025))
        }
    }

    private func drawExhaust() {
        for (outlet, point) in [(0, CGPoint(x: 208, y: 299)), (1, CGPoint(x: 263, y: 298))] {
            for id in 0..<8 {
                let period = 7.2 + Double(outlet) * 1.1
                let phase = (time / period + Double(id) / 8 + Double(outlet) * 0.31)
                    .truncatingRemainder(dividingBy: 1)
                let rise = 5 * phase + 12 * phase * phase
                let x = Int(point.x) - Int(phase * 65)
                let y = Int(point.y) - Int(rise + sin(phase * 6 + Double(id)) * 2)
                // Keep a visible minimum: the old plume almost disappeared at
                // the low end of the exhaust cycle against detailed pavement.
                let opacity = sin(phase * .pi) * (0.32 + 0.32 * model.exhaust)
                let w = 4 + Int(phase * 13), h = 3 + Int(phase * 4)
                for row in 0..<h {
                    let inset = abs(row - h / 2) * 2
                    canvas.rect(x - w / 2 + inset / 2, y + row, max(1, w - inset), 1,
                                row < h / 2 ? 0xa2afbf : 0x7a93a7, alpha: opacity)
                }
                canvas.rect(x - w / 2 + 2, y - 1, max(1, w - 5), 1,
                            0xc1c6d4, alpha: opacity * 0.5)
                canvas.rect(x - w / 2 - 1, y + 1, 1, max(1, h - 2),
                            0x49a3b3, alpha: opacity * 0.5)
            }
        }
    }

    private func drawPuddleLight() {
        for id in 0..<26 {
            let x = 80 + neonHash(id + 42) % 530
            let y = 344 + neonHash(id + 103) % 44
            let period = 31 + Double(id % 5)
            let phase = time.truncatingRemainder(dividingBy: period)
            let wave = 0.5 + 0.5 * sin(phase * (2 * .pi / period) + Double(id))
            let pink = id % 3 == 0
            canvas.rect(x, y, 2 + neonHash(id) % 10, 1,
                        pink ? 0xed65d0 : 0x4fdbed,
                        alpha: wave * 0.14 * (pink ? model.carLight : model.underglow))
        }
    }
}

private func neonHash(_ id: Int) -> Int {
    var value = UInt64(truncatingIfNeeded: id) &+ 0x9e3779b97f4a7c15
    value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
    value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
    return Int((value ^ (value >> 31)) & 0x7fff_ffff)
}

private enum NeonPixelFont {
    static let glyphs: [Character: [Int]] = [
        "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7], "2": [7, 1, 7, 4, 7],
        "3": [7, 1, 7, 1, 7], "4": [5, 5, 7, 1, 1], "5": [7, 4, 7, 1, 7],
        "6": [7, 4, 7, 5, 7], "7": [7, 1, 1, 2, 2], "8": [7, 5, 7, 5, 7],
        "9": [7, 5, 7, 1, 7], "B": [6, 5, 6, 5, 6], "D": [6, 5, 5, 5, 6],
        "K": [5, 5, 6, 5, 5], "P": [6, 5, 6, 4, 4], "W": [5, 5, 7, 7, 5],
        "X": [5, 5, 2, 5, 5],
        "A": [2, 5, 7, 5, 5], "C": [3, 4, 4, 4, 3], "E": [7, 4, 6, 4, 7],
        "F": [7, 4, 6, 4, 4], "G": [3, 4, 5, 5, 3], "H": [5, 5, 7, 5, 5],
        "I": [7, 2, 2, 2, 7], "L": [4, 4, 4, 4, 7], "M": [5, 7, 7, 5, 5],
        "N": [5, 7, 7, 7, 5], "O": [2, 5, 5, 5, 2], "R": [6, 5, 6, 5, 5],
        "S": [3, 4, 2, 1, 6], "T": [7, 2, 2, 2, 2], "U": [5, 5, 5, 5, 7],
        "V": [5, 5, 5, 5, 2], "Y": [5, 5, 2, 2, 2], " ": [0, 0, 0, 0, 0]
    ]
}
