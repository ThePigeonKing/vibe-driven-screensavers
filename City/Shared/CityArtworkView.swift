import AppKit
import CoreGraphics

/// A small native raster is enlarged with nearest-neighbor sampling. Every edge
/// belongs to the same pixel grid, including on Retina and unusual aspect ratios.
final class CityArtworkView: NSView {
    var model = CitySceneModel()
    var weatherOverride: CityWeatherPreset?
    var dateOverride: Date?
    private var raster: CGContext?
    private var rasterSize = CGSize.zero
    private var clockMinute = Int.min
    private var clockText = "00:00"
    private let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

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
        let pixel = max(1, floor(min(backing.width / 400, backing.height / 270)))
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
        guard let raster else { return }
        let now = dateOverride ?? Date()
        let minute = Int(now.timeIntervalSince1970 / 60)
        if minute != clockMinute {
            clockMinute = minute
            clockText = clockFormatter.string(from: now)
        }

        raster.saveGState()
        raster.setShouldAntialias(false)
        raster.translateBy(x: 0, y: CGFloat(height))
        raster.scaleBy(x: 1, y: -1)
        CityArtwork(canvas: CityCanvas(context: raster), width: width, height: height,
                    model: model, weather: model.weather(for: weatherOverride),
                    clock: clockText).draw()
        raster.restoreGState()
        guard let image = raster.makeImage() else { return }
        destination.saveGState()
        destination.setShouldAntialias(false)
        destination.interpolationQuality = .none
        let pointPixel = pixel / backingScale
        destination.draw(image, in: CGRect(x: 0, y: 0,
                                           width: CGFloat(width) * pointPixel,
                                           height: CGFloat(height) * pointPixel))
        destination.restoreGState()
    }
}

private struct CityInk {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat
    init(_ hex: UInt32) {
        r = CGFloat((hex >> 16) & 255) / 255
        g = CGFloat((hex >> 8) & 255) / 255
        b = CGFloat(hex & 255) / 255
    }
    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: CGFloat(max(0, min(1, alpha))))
    }
}

private enum CityPalette {
    static let sky = CityInk(0x080f23)
    static let skyLow = CityInk(0x151a34)
    static let dusk = CityInk(0x25243e)
    static let distant = CityInk(0x19233a)
    static let distantEdge = CityInk(0x2b334c)
    static let shadow = CityInk(0x101827)
    static let deep = CityInk(0x0b1421)
    static let brick = CityInk(0x353047)
    static let brickEdge = CityInk(0x4d3b50)
    static let slate = CityInk(0x29394b)
    static let slateEdge = CityInk(0x455365)
    static let plaster = CityInk(0x3d3c52)
    static let roof = CityInk(0x182339)
    static let metal = CityInk(0x53667a)
    static let glass = CityInk(0x263b52)
    static let warmDark = CityInk(0x795039)
    static let amber = CityInk(0xdda35f)
    static let light = CityInk(0xf2cf88)
    static let cream = CityInk(0xffdf9d)
    static let cold = CityInk(0x8aa9bc)
    static let moon = CityInk(0xc1cad0)
    static let wine = CityInk(0x67414b)
    static let red = CityInk(0xa16461)
    static let pavement = CityInk(0x171f31)
    static let puddle = CityInk(0x263247)
    static let tower = CityInk(0x263b50)
    static let towerLight = CityInk(0x40586b)
    static let towerEdge = CityInk(0x69808e)
    static let bronze = CityInk(0x594b50)
    static let bronzeEdge = CityInk(0x92745e)
    static let taxi = CityInk(0xb18b4e)
}

private struct CityCanvas {
    let context: CGContext
    func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int,
              _ ink: CityInk, alpha: Double = 1) {
        guard w > 0, h > 0, alpha > 0 else { return }
        context.setFillColor(ink.cgColor(alpha: alpha))
        context.fill(CGRect(x: x, y: y, width: w, height: h))
    }
    func line(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int,
              _ ink: CityInk, alpha: Double = 1) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1
        let dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1
        var error = dx + dy
        while true {
            rect(x, y, 1, 1, ink, alpha: alpha)
            if x == x1 && y == y1 { break }
            let twice = error * 2
            if twice >= dy { error += dy; x += sx }
            if twice <= dx { error += dx; y += sy }
        }
    }
    func text(_ text: String, x: Int, y: Int, pixel: Int, ink: CityInk,
              alpha: Double = 1) {
        var cursor = x
        for character in text {
            let glyph = CityPixelFont.glyphs[character] ?? [0, 0, 0, 0, 0]
            for row in 0..<5 {
                for column in 0..<3 where glyph[row] & (1 << (2 - column)) != 0 {
                    rect(cursor + column * pixel, y + row * pixel,
                         pixel, pixel, ink, alpha: alpha)
                }
            }
            cursor += pixel * 4
        }
    }
}

private struct CityArtwork {
    let canvas: CityCanvas
    let width: Int
    let height: Int
    let model: CitySceneModel
    let weather: CityWeatherState
    let clock: String
    private var base: Int { height - 270 }
    private var left: Int { (width - 480) / 2 }
    private var time: Double { model.time }
    private var verticalExtra: Int { min(160, max(0, (height - 330) / 2)) }

    func draw() {
        drawSky()
        drawDistantCity()
        drawMoscowSkyline()
        drawNeighborhood()
        drawStreetBehindStation()
        drawStation()
        if let train = model.train { drawTrain(train) }
        drawBridgeAndStreet()
        drawCars()
        drawRain()
    }

    private func drawSky() {
        canvas.rect(0, 0, width, height, CityPalette.sky)
        let horizon = max(30, base + 206)
        for band in 0..<16 {
            let y = horizon - 144 + band * 9
            canvas.rect(0, max(0, y), width, max(0, 9 + min(0, y)),
                        CityPalette.skyLow, alpha: Double(band + 1) / 16)
        }
        for band in 0..<6 {
            canvas.rect(0, max(0, horizon - 36 + band * 6), width, 6,
                        CityPalette.dusk, alpha: Double(band + 1) * 0.035)
        }
        let starHeight = max(10, base + 126)
        let count = min(70, max(12, width * starHeight / 4200))
        for id in 0..<count {
            let hash = noise(id + 809)
            let x = hash % max(1, width - 10) + 5
            let y = noise(id + 1241) % starHeight
            let brightness = (0.2 + Double(hash % 5) * 0.09) * (1 - weather.cloudiness * 0.85)
            canvas.rect(x, y, 1, 1, CityPalette.moon, alpha: brightness)
            if id % 11 == 0 {
                canvas.rect(x - 1, y, 3, 1, CityPalette.moon, alpha: brightness * 0.35)
                canvas.rect(x, y - 1, 1, 3, CityPalette.moon, alpha: brightness * 0.35)
            }
        }
        let moonX = min(width - 23, left + 425)
        let moonY = max(25, (base + 58) / 2)
        for y in -9...9 {
            for x in -9...9 where x * x + y * y <= 81 && (x - 4) * (x - 4) + (y + 2) * (y + 2) > 65 {
                canvas.rect(moonX + x, moonY + y, 1, 1, CityPalette.moon,
                            alpha: 0.7 * (1 - weather.cloudiness * 0.75))
            }
        }
        for index in 0..<5 {
            let cloudWidth = 106 + noise(index + 47) % 74
            let travel = Double(width + cloudWidth + 40)
            let x = Int((Double(index * 117) + time * (0.18 + Double(index % 2) * 0.11))
                .truncatingRemainder(dividingBy: travel)) - cloudWidth
            let y = max(4, base + 52 + index * 19 - (index % 2) * 34)
            cloud(x: x, y: y, width: cloudWidth,
                  alpha: (0.18 + weather.cloudiness * 0.58) * (index % 2 == 0 ? 1 : 0.62))
        }
        if base > 120 {
            cloud(x: width / 5 + Int(time * 0.12) % max(1, width / 2),
                  y: base / 3, width: width / 2, alpha: weather.cloudiness * 0.4)
        }
    }

    private func cloud(x: Int, y: Int, width: Int, alpha: Double) {
        canvas.rect(x + 19, y, width - 46, 3, CityPalette.distant, alpha: alpha)
        canvas.rect(x + 8, y + 3, width - 19, 4, CityPalette.distant, alpha: alpha)
        canvas.rect(x, y + 7, width, 4, CityPalette.distant, alpha: alpha)
        canvas.rect(x + 14, y + 11, width - 28, 2, CityPalette.distant, alpha: alpha * 0.65)
    }

    private func drawDistantCity() {
        let ground = base + 213
        var x = -8, id = 0
        while x < width {
            let w = 16 + noise(id + 401) % 30
            let h = 20 + noise(id + 507) % 45 + verticalExtra / 2
            let y = ground - h
            canvas.rect(x, y, w, h, CityPalette.distant)
            canvas.rect(x + 3, y - 3, w - 9, 3, CityPalette.distant)
            if id % 3 == 0 {
                canvas.rect(x + w / 2, y - 13, 1, 10, CityPalette.distantEdge, alpha: 0.6)
            }
            for row in 0..<(h / 8) {
                for column in 0..<(w / 7) where noise(id * 91 + row * 7 + column) % 7 == 0 {
                    canvas.rect(x + 3 + column * 7, y + 6 + row * 8, 2, 2,
                                CityPalette.warmDark, alpha: 0.45)
                }
            }
            x += w - 2
            id += 1
        }
        x = -12; id = 0
        while x < width {
            let w = 30 + noise(id + 671) % 28
            let h = 20 + noise(id + 731) % 25 + verticalExtra / 3
            canvas.rect(x, ground - h + 10, w, h, CityPalette.distantEdge, alpha: 0.65)
            canvas.rect(x + 5, ground - h + 6, 10, 4, CityPalette.distantEdge, alpha: 0.65)
            x += w + 5
            id += 1
        }
    }

    private func drawMoscowSkyline() {
        let ground = base + 211
        // A fictional viewing angle: stacked volumes, a twisting ribbon, paired
        // glass towers and a bronze silhouette evoke Moscow City at a distance.
        glassTower(x: left + 40, y: ground - 83 - verticalExtra / 3,
                   w: 25, h: 83 + verticalExtra / 3, id: 6, muted: true)
        capitalTower(x: left + 83, y: ground - 121 - verticalExtra / 2,
                     w: 31, h: 121 + verticalExtra / 2, id: 7)
        capitalTower(x: left + 116, y: ground - 94 - verticalExtra / 3,
                     w: 27, h: 94 + verticalExtra / 3, id: 8)
        evolutionTower(x: left + 156, y: ground - 137 - verticalExtra * 2 / 3,
                       h: 137 + verticalExtra * 2 / 3)
        glassTower(x: left + 221, y: ground - 186 - verticalExtra,
                   w: 33, h: 186 + verticalExtra, id: 10)
        glassTower(x: left + 262, y: ground - 133 - verticalExtra * 2 / 3,
                   w: 31, h: 133 + verticalExtra * 2 / 3, id: 11)
        mercuryTower(x: left + 311, y: ground - 158 - verticalExtra * 3 / 4,
                     h: 158 + verticalExtra * 3 / 4)
        glassTower(x: left + 369, y: ground - 112 - verticalExtra / 2,
                   w: 29, h: 112 + verticalExtra / 2, id: 13, muted: true)
        canvas.rect(left + 78, ground - 5, 327, 6, CityPalette.tower)
        canvas.rect(left + 72, ground + 1, 341, 2, CityPalette.distantEdge)
    }

    private func glassTower(x: Int, y: Int, w: Int, h: Int,
                            id: Int, muted: Bool = false) {
        for row in 0..<h {
            let insetLeft = max(0, 12 - row)
            let insetRight = max(0, 6 - row / 2)
            let start = x + insetLeft
            let span = w - insetLeft - insetRight
            canvas.rect(start, y + row, span, 1, CityPalette.tower,
                        alpha: muted ? 0.78 : 1)
            canvas.rect(start + span * 2 / 3, y + row, max(1, span / 3), 1,
                        CityPalette.towerLight, alpha: muted ? 0.5 : 0.8)
            canvas.rect(start + span - 1, y + row, 1, 1, CityPalette.towerEdge,
                        alpha: muted ? 0.3 : 0.55)
            if row > 12 && row % 4 == 0 {
                towerFloor(x: start + 2, y: y + row, w: span - 4, row: row / 4,
                           id: id, warm: false, subdued: muted)
            }
        }
        for column in stride(from: 6, to: w - 2, by: 8) {
            canvas.rect(x + column, y + 13, 1, h - 13, CityPalette.shadow, alpha: 0.5)
        }
        canvas.rect(x + w / 2 + 2, y, 1, 1, CityPalette.red, alpha: 0.65)
    }

    private func capitalTower(x: Int, y: Int, w: Int, h: Int, id: Int) {
        let block = max(18, h / 5)
        let offsets = [3, -2, 4, 0, -3, 2, 0]
        for row in 0..<h {
            let segment = min(offsets.count - 1, row / block)
            let shift = offsets[segment]
            canvas.rect(x + shift, y + row, w, 1, CityPalette.tower)
            canvas.rect(x + shift + w - 7, y + row, 7, 1, CityPalette.towerLight, alpha: 0.6)
            canvas.rect(x + shift, y + row, 1, 1, CityPalette.towerEdge, alpha: 0.4)
            if row % block == 0 {
                canvas.rect(x + shift - 1, y + row, w + 2, 1,
                            CityPalette.towerEdge, alpha: 0.65)
            } else if row % 4 == 0 {
                towerFloor(x: x + shift + 2, y: y + row, w: w - 4,
                           row: row / 4, id: id, warm: false)
            }
        }
        canvas.rect(x + 7, y - 3, w - 7, 3, CityPalette.roof)
    }

    private func evolutionTower(x: Int, y: Int, h: Int) {
        for row in 0..<h {
            let fraction = Double(row) / Double(h - 1)
            let shift = Int(sin((fraction * 1.45 - 0.48) * .pi) * 11)
            let span = 27 + Int(sin(fraction * .pi) * 8)
            let start = x + 20 + shift - span / 2
            let seam = span / 2 + Int(cos(fraction * .pi) * 6)
            canvas.rect(start, y + row, span, 1, CityPalette.tower)
            canvas.rect(start, y + row, max(1, seam), 1, CityPalette.towerLight, alpha: 0.78)
            canvas.rect(start + seam, y + row, 2, 1, CityPalette.towerEdge, alpha: 0.8)
            canvas.rect(start + span - 1, y + row, 1, 1, CityPalette.towerEdge, alpha: 0.38)
            if row % 4 == 0 {
                towerFloor(x: start + 2, y: y + row, w: span - 4,
                           row: row / 4, id: 9, warm: false)
            }
        }
        canvas.rect(x + 6, y - 1, 17, 1, CityPalette.metal, alpha: 0.7)
    }

    private func mercuryTower(x: Int, y: Int, h: Int) {
        for row in 0..<h {
            let inset = max(0, 14 - row / 2)
            let rightInset = row < h / 5 ? 6 : (row < h * 2 / 5 ? 3 : 0)
            let span = 37 - inset - rightInset
            let start = x + inset
            canvas.rect(start, y + row, span, 1, CityPalette.bronze)
            canvas.rect(start + span * 2 / 3, y + row, max(1, span / 3), 1,
                        CityPalette.bronzeEdge, alpha: 0.52)
            canvas.rect(start, y + row, 1, 1, CityPalette.bronzeEdge, alpha: 0.65)
            if row > 10 && row % 4 == 0 {
                towerFloor(x: start + 2, y: y + row, w: span - 4,
                           row: row / 4, id: 12, warm: true)
            }
        }
        canvas.rect(x + 14, y - 1, 20, 1, CityPalette.bronzeEdge)
        canvas.rect(x + 26, y - 2, 1, 1, CityPalette.red, alpha: 0.6)
        canvas.rect(x + 28, y + 35, 1, h - 35, CityPalette.shadow, alpha: 0.5)
    }

    private func towerFloor(x: Int, y: Int, w: Int, row: Int, id: Int,
                             warm: Bool, subdued: Bool = false) {
        canvas.rect(x, y + 2, w, 1, CityPalette.shadow, alpha: 0.42)
        for column in 0..<max(1, w / 4) {
            let cell = id * 79 + row * 7 + column
            let light = model.windowLight(id: cell)
            let lit = noise(cell + 4127) % 4 == 0
            canvas.rect(x + column * 4, y, 2, 2,
                        warm ? CityPalette.bronzeEdge : CityPalette.cold,
                        alpha: (lit ? light * 0.56 : 0.09) * (subdued ? 0.55 : 1))
            if lit && light > 0.15 && column % 3 == 0 {
                canvas.rect(x + column * 4, y, 1, 1, CityPalette.light,
                            alpha: light * (subdued ? 0.2 : 0.32))
            }
        }
    }

    private func drawNeighborhood() {
        // Small older blocks establish distance in front of the glass skyline.
        var x = left - 72, id = 6
        while x > -90 {
            let w = 40 + noise(x + 3101) % 16
            let h = 32 + noise(x + 3133) % 20 + verticalExtra / 8
            building(x: x, y: base + 220 - h, w: w, h: h,
                     style: noise(x + 3151) % 3 == 0 ? 3 : 0, id: id)
            x -= w + 10
            id = id == 6 ? 7 : 6
        }
        x = left + 480; id = 7
        while x < width {
            let w = 40 + noise(x + 3203) % 17
            let h = 30 + noise(x + 3217) % 21 + verticalExtra / 8
            building(x: x, y: base + 220 - h, w: w, h: h,
                     style: noise(x + 3251) % 3 == 0 ? 3 : 2, id: id)
            x += w + 10
            id = id == 6 ? 7 : 6
        }
        building(x: left - 21, y: base + 174, w: 65, h: 46, style: 0, id: 0)
        building(x: left + 48, y: base + 162, w: 46, h: 58, style: 2, id: 1)
        building(x: left + 99, y: base + 177, w: 58, h: 43, style: 1, id: 2)
        building(x: left + 165, y: base + 166, w: 51, h: 54, style: 3, id: 3)
        building(x: left + 225, y: base + 182, w: 64, h: 38, style: 0, id: 4)
        building(x: left + 296, y: base + 172, w: 59, h: 48, style: 2, id: 5)
        building(x: left + 363, y: base + 184, w: 79, h: 36, style: 4, id: 6)
        building(x: left + 448, y: base + 169, w: 45, h: 51, style: 2, id: 7)
        drawTree(x: left + 41, y: base + 191)
        drawTree(x: left + 158, y: base + 195)
        drawTree(x: left + 291, y: base + 194)
        canvas.line(left + 91, base + 175, left + 168, base + 179, CityPalette.shadow)
        drawSteam(x: left + 132, y: base + 162)
        drawSteam(x: left + 406, y: base + 171, offset: 4.7)
    }

    private func building(x: Int, y: Int, w: Int, h: Int, style: Int, id: Int) {
        let ink = style == 1 ? CityPalette.brick : (style == 2 ? CityPalette.plaster : CityPalette.slate)
        canvas.rect(x, y, w, h, ink)
        canvas.rect(x + w - 7, y, 7, h, CityPalette.shadow)
        canvas.rect(x + w - 8, y, 1, h, CityPalette.roof)
        canvas.rect(x + 1, y + 1, w - 9, 1, style == 1 ? CityPalette.brickEdge : CityPalette.slateEdge)
        if style == 3 {
            for step in 0..<8 {
                canvas.rect(x + step * 2, y - step - 1, w - 7 - step * 4, 1, CityPalette.roof)
            }
            canvas.rect(x + 17, y - 6, 5, 3, CityPalette.glass)
        } else if style == 4 {
            for tooth in 0..<3 {
                let start = x + tooth * 24
                for step in 0..<10 {
                    canvas.rect(start + step * 2, y - step / 2 - 1, 2, step / 2 + 1, CityPalette.roof)
                }
            }
            canvas.rect(x, y, w, 3, CityPalette.metal, alpha: 0.5)
        } else {
            canvas.rect(x - 1, y - 3, w + 1, 3, CityPalette.roof)
            canvas.rect(x, y - 3, w - 5, 1, CityPalette.slateEdge)
            canvas.rect(x + 4, y - 7, 10, 4, CityPalette.shadow)
            canvas.rect(x + 5, y - 8, 8, 1, CityPalette.metal, alpha: 0.6)
        }
        if style == 1 {
            // A rooftop tank, inset penthouse and fire escape give the hero house
            // a recognizable silhouette without a large luminous sign.
            canvas.rect(x + 12, y - 11, 32, 8, CityPalette.brick)
            canvas.rect(x + 10, y - 12, 35, 2, CityPalette.roof)
            canvas.rect(x + 38, y - 25, 15, 12, CityPalette.shadow)
            canvas.rect(x + 37, y - 25, 17, 2, CityPalette.slateEdge)
            canvas.rect(x + 40, y - 27, 11, 2, CityPalette.roof)
            canvas.rect(x + 40, y - 13, 1, 6, CityPalette.metal)
            canvas.rect(x + 50, y - 13, 1, 6, CityPalette.metal)
            canvas.rect(x + 7, y - 20, 1, 13, CityPalette.slateEdge)
            canvas.rect(x + 3, y - 19, 10, 1, CityPalette.slateEdge)
            canvas.rect(x + 47, y - 28, 1, 1, CityPalette.red)
        }
        for row in stride(from: 7, to: h - 8, by: 8) {
            for column in stride(from: 3, to: w - 9, by: 7) where noise(row * 3 + column + id * 137) % 4 == 0 {
                canvas.rect(x + column, y + row, 3, 1,
                            style == 1 ? CityPalette.brickEdge : CityPalette.slateEdge, alpha: 0.38)
            }
        }
        let columnCount = max(1, (w - 15) / (style == 4 ? 12 : 8))
        let spacing = style == 4 ? 12 : 8
        let rowSpacing = style == 4 ? 10 : 9
        let rows = min(15, (h - 19) / rowSpacing)
        for row in 0..<rows {
            if row > 0 && row % 2 == 0 {
                canvas.rect(x + 1, y + row * rowSpacing + 4, w - 9, 1,
                            CityPalette.roof, alpha: 0.55)
            }
            for column in 0..<columnCount {
                let wx = x + 5 + column * spacing
                let wy = y + 8 + row * rowSpacing
                let ww = style == 4 ? 7 : 3
                let wh = style == 4 ? 5 : 4
                window(x: wx, y: wy, w: ww, h: wh, id: id * 128 + row * 8 + column)
                if style == 1 && column == 1 && row % 2 == 0 {
                    canvas.rect(wx + 5, wy + 7, 3, 2, CityPalette.metal, alpha: 0.7)
                }
            }
        }
        canvas.rect(x + 2, y + h - 13, w - 11, 1, CityPalette.roof)
        canvas.rect(x + 5, y + h - 12, 7, 12, CityPalette.shadow)
        canvas.rect(x + 6, y + h - 10, 4, 6, CityPalette.warmDark, alpha: 0.6)
        if w > 40 {
            canvas.rect(x + 18, y + h - 10, w - 32, 8, CityPalette.glass)
            canvas.rect(x + 20, y + h - 9, w - 36, 5, CityPalette.amber, alpha: 0.38)
            canvas.rect(x + 16, y + h - 14, w - 28, 3, CityPalette.wine)
            for stripe in stride(from: 17, to: w - 14, by: 6) {
                canvas.rect(x + stripe, y + h - 14, 2, 3, CityPalette.warmDark, alpha: 0.8)
            }
        }
        if style == 1 {
            let fx = x + w - 4
            canvas.rect(fx, y + 13, 1, h - 22, CityPalette.metal, alpha: 0.65)
            for row in stride(from: 19, to: h - 10, by: 14) {
                canvas.rect(fx - 7, y + row, 11, 1, CityPalette.metal, alpha: 0.75)
                canvas.rect(fx - 7, y + row - 4, 1, 4, CityPalette.metal, alpha: 0.55)
                canvas.rect(fx + 3, y + row - 4, 1, 4, CityPalette.metal, alpha: 0.55)
                canvas.line(fx - 5, y + row + 1, fx + 1, y + row + 12,
                            CityPalette.metal, alpha: 0.5)
            }
        }
    }

    private func window(x: Int, y: Int, w: Int, h: Int, id: Int) {
        let light = model.windowLight(id: id)
        canvas.rect(x - 1, y - 1, w + 2, h + 2, CityPalette.roof)
        canvas.rect(x, y, w, h, CityPalette.glass)
        canvas.rect(x, y, w, h, CityPalette.amber, alpha: light * 0.82)
        canvas.rect(x + 1, y + 1, w - 2, h - 2, CityPalette.light, alpha: light * 0.65)
        if noise(id + 118) % 3 == 0 {
            canvas.rect(x, y + 1, 2, h - 2, CityPalette.warmDark, alpha: light * 0.7)
        }
        canvas.rect(x + w / 2, y, 1, h, CityPalette.shadow, alpha: 0.66)
        canvas.rect(x, y + h / 2, w, 1, CityPalette.shadow, alpha: 0.4)
        canvas.rect(x - 1, y + h, w + 2, 1, CityPalette.slateEdge, alpha: 0.6)
    }

    private func drawTree(x: Int, y: Int) {
        canvas.rect(x + 4, y + 7, 2, 24, CityPalette.shadow)
        canvas.rect(x + 1, y + 4, 8, 17, CityPalette.deep)
        canvas.rect(x - 3, y + 8, 15, 8, CityPalette.deep)
        canvas.rect(x + 1, y, 6, 5, CityPalette.deep)
        canvas.rect(x - 1, y + 8, 2, 3, CityPalette.slate, alpha: 0.45)
    }

    private func drawSteam(x: Int, y: Int, offset: Double = 0) {
        for index in 0..<3 {
            let phase = (time * 0.11 + Double(index) / 3 + offset)
                .truncatingRemainder(dividingBy: 1)
            let drift = Int(sin(phase * .pi) * 4)
            let rise = Int(phase * 14)
            let opacity = sin(phase * .pi) * 0.22
            canvas.rect(x + drift, y - rise, 5 + index, 2, CityPalette.metal, alpha: opacity)
            canvas.rect(x + drift + 2, y - rise - 1, 3 + index, 1, CityPalette.metal, alpha: opacity)
        }
    }

    private func drawStreetBehindStation() {
        canvas.rect(0, base + 220, width, 12, CityPalette.deep)
        canvas.rect(0, base + 219, width, 1, CityPalette.slateEdge, alpha: 0.45)
        for x in stride(from: 2, to: width, by: 18) {
            canvas.rect(x, base + 223, 9, 1, CityPalette.warmDark, alpha: 0.22)
        }
    }

    private func drawStation() {
        let sx = left + 290, sy = base + 191
        let canopyY = sy - 5
        // A back platform, slim canopy and small clock leave the city dominant.
        canvas.rect(sx - 12, sy + 24, 177, 5, CityPalette.slate)
        canvas.rect(sx - 12, sy + 24, 177, 1, CityPalette.metal)
        canvas.rect(sx - 12, sy + 28, 177, 1, CityPalette.amber, alpha: 0.6)
        for x in stride(from: sx - 10, through: sx + 158, by: 7) {
            canvas.rect(x, sy + 25, 3, 1, CityPalette.light, alpha: 0.3)
        }
        canvas.rect(sx, canopyY - 2, 156, 4, CityPalette.roof)
        canvas.rect(sx + 8, canopyY - 4, 142, 2, CityPalette.slate)
        canvas.rect(sx, canopyY - 2, 156, 1, CityPalette.metal)
        canvas.rect(sx - 2, canopyY + 2, 160, 2, CityPalette.shadow)
        canvas.rect(sx + 1, canopyY + 4, 154, 1, CityPalette.warmDark)
        for post in [sx + 6, sx + 70, sx + 149] {
            canvas.rect(post, canopyY + 4, 2, 25, CityPalette.shadow)
            canvas.rect(post, canopyY + 4, 1, 25, CityPalette.slateEdge)
        }
        for lamp in [sx + 28, sx + 111] {
            canvas.rect(lamp, canopyY + 3, 1, 3, CityPalette.warmDark)
            canvas.rect(lamp - 4, canopyY + 6, 9, 2, CityPalette.amber)
            canvas.rect(lamp - 3, canopyY + 7, 7, 1, CityPalette.light)
            canvas.rect(lamp - 7, canopyY + 9, 15, 1, CityPalette.amber, alpha: 0.12)
        }
        // A 3x5 bitmap font, two city pixels per stroke, never antialiased.
        let clockX = sx + 52
        canvas.rect(clockX, canopyY + 6, 46, 16, CityPalette.shadow)
        canvas.rect(clockX + 1, canopyY + 7, 44, 14, CityPalette.warmDark)
        canvas.rect(clockX + 2, canopyY + 8, 42, 12, CityPalette.deep)
        canvas.text(clock, x: clockX + 4, y: canopyY + 9, pixel: 2, ink: CityPalette.amber)
        canvas.rect(sx + 13, sy + 20, 25, 2, CityPalette.wine)
        canvas.rect(sx + 15, sy + 22, 1, 2, CityPalette.shadow)
        canvas.rect(sx + 35, sy + 22, 1, 2, CityPalette.shadow)
        canvas.rect(sx + 126, sy + 16, 10, 7, CityPalette.shadow)
        canvas.text("N", x: sx + 129, y: sy + 17, pixel: 1, ink: CityPalette.amber)
        person(x: sx + 42, y: sy + 16, coat: CityPalette.wine)
        person(x: sx + 139, y: sy + 16, coat: CityPalette.slateEdge)
        let walker = (time.truncatingRemainder(dividingBy: 113) - 29) / 52
        if walker > 0 && walker < 1 {
            person(x: sx + 9 + Int(walker * 130), y: sy + 16,
                   coat: CityPalette.metal, walking: true)
        }
    }

    private func person(x: Int, y: Int, coat: CityInk, walking: Bool = false) {
        canvas.rect(x + 1, y, 2, 2, CityPalette.shadow)
        canvas.rect(x, y + 2, 4, 5, coat, alpha: 0.8)
        canvas.rect(x + 1, y + 2, 2, 5, CityPalette.shadow, alpha: 0.55)
        let stride = walking ? Int(time * 1.6) % 2 : 0
        canvas.rect(x + stride, y + 7, 1, 2, CityPalette.deep)
        canvas.rect(x + 3 - stride, y + 7, 1, 2, CityPalette.deep)
        canvas.rect(x + 4, y + 4, 1, 3, CityPalette.warmDark, alpha: 0.7)
    }

    private func drawTrain(_ train: CityTrainState) {
        let cars = train.carCount
        let carWidth = 41, gap = 3
        let length = cars * (carWidth + gap) - gap
        let travel = width + length + 20
        let x = train.direction > 0
            ? -length - 10 + Int(train.progress * Double(travel))
            : width + 10 - Int(train.progress * Double(travel))
        let y = base + 215
        for index in 0..<cars {
            let cx = x + index * (carWidth + gap)
            canvas.rect(cx + 2, y - 1, carWidth - 4, 2, CityPalette.metal)
            canvas.rect(cx, y + 1, carWidth, 10, CityPalette.slateEdge)
            canvas.rect(cx, y + 1, carWidth, 2, CityPalette.cold, alpha: 0.75)
            canvas.rect(cx + 1, y + 3, carWidth - 2, 6, CityPalette.slate)
            canvas.rect(cx, y + 9, carWidth, 2, CityPalette.wine)
            canvas.rect(cx + 1, y + 11, carWidth - 2, 2, CityPalette.shadow)
            for window in 0..<4 {
                let wx = cx + 4 + window * 8
                canvas.rect(wx, y + 4, 6, 4, CityPalette.shadow)
                canvas.rect(wx + 1, y + 5, 4, 2, CityPalette.amber,
                            alpha: 0.74 + Double(noise(index * 23 + window) % 4) * 0.05)
                canvas.rect(wx + 1, y + 5, 4, 1, CityPalette.light, alpha: 0.8)
                if window % 3 == 0 {
                    canvas.rect(wx + 3, y + 6, 1, 1, CityPalette.warmDark)
                }
            }
            canvas.rect(cx + 20, y + 3, 5, 9, CityPalette.metal)
            canvas.rect(cx + 21, y + 4, 3, 4, CityPalette.glass)
            canvas.rect(cx + 22, y + 4, 1, 8, CityPalette.shadow)
            for wheel in [cx + 6, cx + 30] {
                canvas.rect(wheel, y + 13, 6, 2, CityPalette.deep)
                canvas.rect(wheel + 1, y + 15, 2, 1, CityPalette.metal)
                canvas.rect(wheel + 4, y + 15, 1, 1, CityPalette.metal)
            }
            if index < cars - 1 {
                canvas.rect(cx + carWidth, y + 8, gap, 2, CityPalette.metal)
            }
        }
        let front = train.direction > 0 ? x + length - 1 : x
        canvas.rect(front, y + 3, 1, 5, CityPalette.cold)
        canvas.rect(front - (train.direction > 0 ? 2 : 0), y + 9, 3, 1, CityPalette.cream)
        let tail = train.direction > 0 ? x : x + length - 2
        canvas.rect(tail, y + 9, 2, 1, CityPalette.red)
    }

    private func drawBridgeAndStreet() {
        let rail = base + 231
        canvas.rect(0, rail, width, 1, CityPalette.metal)
        canvas.rect(0, rail + 1, width, 2, CityPalette.shadow)
        for x in stride(from: 0, to: width, by: 7) {
            canvas.rect(x, rail + 2, 3, 1, CityPalette.slateEdge)
        }
        canvas.rect(0, rail + 3, width, 1, CityPalette.metal, alpha: 0.75)
        canvas.rect(0, rail + 4, width, 9, CityPalette.slate)
        canvas.rect(0, rail + 5, width, 1, CityPalette.slateEdge, alpha: 0.75)
        canvas.rect(0, rail + 11, width, 2, CityPalette.shadow)
        canvas.rect(0, rail + 13, width, 1, CityPalette.deep)
        canvas.rect(0, rail + 14, width, height - rail - 14, CityPalette.pavement)
        for x in stride(from: left - 17, to: width + 15, by: 82) {
            canvas.rect(x, rail + 11, 12, 14, CityPalette.shadow)
            canvas.rect(x + 1, rail + 12, 2, 12, CityPalette.slate, alpha: 0.7)
            canvas.rect(x - 4, rail + 12, 20, 2, CityPalette.shadow)
            canvas.rect(x - 2, rail + 24, 16, 2, CityPalette.deep)
        }
        canvas.rect(0, base + 251, width, 18, CityPalette.deep)
        canvas.rect(0, base + 250, width, 1, CityPalette.slateEdge, alpha: 0.65)
        for x in stride(from: 0, to: width, by: 22) {
            canvas.rect(x, base + 260, 8, 1, CityPalette.metal, alpha: 0.42)
        }
        canvas.rect(0, height - 2, width, 2, CityPalette.deep)
        let wet = 0.25 + weather.wetness * 0.75
        for index in 0..<max(8, width / 27) {
            let x = noise(index + 1301) % width
            let y = base + 253 + noise(index + 1471) % 13
            let w = 12 + noise(index + 1703) % 27
            canvas.rect(x, y, w, 1, CityPalette.puddle, alpha: wet)
            canvas.rect(x + 4, y + 1, max(1, w - 8), 1, CityPalette.slate, alpha: wet * 0.5)
        }
        for source in [left + 132, left + 342, left + 401] {
            for row in 0..<7 {
                let jitter = noise(row + source) % 9 - 4
                let w = max(2, 16 - row * 2)
                canvas.rect(source + jitter - w / 2, base + 253 + row * 2,
                            w, 1, CityPalette.amber,
                            alpha: weather.wetness * (0.24 - Double(row) * 0.023))
            }
        }
        // Draw on top of the pavement so the wet streaks remain visible.
        if let train = model.train, weather.wetness > 0.05 {
            let length = train.carCount * 44 - 3
            let travel = width + length + 20
            let trainX = train.direction > 0
                ? -length - 10 + Int(train.progress * Double(travel))
                : width + 10 - Int(train.progress * Double(travel))
            for index in 0..<train.carCount * 3 {
                canvas.rect(trainX + 6 + index * 14, base + 254 + index % 3, 8, 1,
                            CityPalette.amber, alpha: weather.wetness * 0.2)
            }
        }
        for index in 0..<7 where weather.rain > 0.2 {
            let phase = (time * 0.31 + Double(index) * 0.381)
                .truncatingRemainder(dividingBy: 1)
            let x = noise(index + 1701) % width
            let y = base + 253 + noise(index + 1733) % 12
            let radius = Int(phase * 4) + 1
            canvas.rect(x - radius, y, radius * 2, 1, CityPalette.cold,
                        alpha: weather.rain * (1 - phase) * 0.15)
        }
    }

    private func drawCars() {
        for car in model.cars {
            let van = car.style == 2
            let w = van ? 17 : 15
            let travel = width + w + 12
            let x = car.direction > 0
                ? -w - 6 + Int(car.progress * Double(travel))
                : width + 6 - Int(car.progress * Double(travel))
            let y = base + (car.lane == 0 ? 253 : 262)
            let inks = [CityPalette.slateEdge, CityPalette.wine,
                        CityPalette.metal, CityPalette.taxi]
            let ink = inks[car.style % inks.count]
            canvas.rect(x + 3, y, van ? 11 : 8, 2, ink)
            canvas.rect(x + 1, y + 2, w - 2, van ? 4 : 3, ink)
            canvas.rect(x, y + 3, w, 2, ink)
            canvas.rect(x + 4, y + 1, van ? 8 : 5, 2, CityPalette.glass)
            canvas.rect(x + 7, y + 1, 1, 2, CityPalette.shadow)
            canvas.rect(x + 1, y + 5, w - 2, 1, CityPalette.shadow)
            canvas.rect(x + 3, y + 5, 2, 2, CityPalette.deep)
            canvas.rect(x + w - 5, y + 5, 2, 2, CityPalette.deep)
            let front = car.direction > 0 ? x + w - 1 : x
            let rear = car.direction > 0 ? x : x + w - 1
            canvas.rect(front, y + 3, 1, 1, CityPalette.cream)
            canvas.rect(rear, y + 3, 1, 1, CityPalette.red)
            if car.style == 3 {
                canvas.rect(x + 6, y - 1, 3, 1, CityPalette.amber, alpha: 0.7)
            }
            if weather.wetness > 0.1 {
                canvas.rect(x + 2, y + 7, w - 4, 1, ink, alpha: weather.wetness * 0.2)
                canvas.rect(front + (car.direction > 0 ? 1 : -3), y + 6, 3, 1,
                            CityPalette.amber, alpha: weather.wetness * 0.24)
            }
        }
    }

    private func drawRain() {
        guard weather.rain > 0.01 else { return }
        let drops = min(210, width * height / 600)
        for index in 0..<drops {
            let startX = noise(index + 2003) % width
            let speed = 28 + Double(noise(index + 2017) % 16)
            let y = Int((Double(noise(index + 2039) % height) + time * speed)
                .truncatingRemainder(dividingBy: Double(height)))
            let x = (startX - Int(time * 3) % width + width) % width
            let length = 2 + index % 3
            let opacity = weather.rain * (index % 4 == 0 ? 0.24 : 0.12)
            canvas.rect(x, y, 1, length, CityPalette.cold, alpha: opacity)
            if index % 3 == 0 {
                canvas.rect(x - 1, y + length, 1, 1, CityPalette.cold, alpha: opacity)
            }
        }
    }

    private func noise(_ id: Int) -> Int {
        var value = UInt64(truncatingIfNeeded: id) &+ 0x9e3779b97f4a7c15
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return Int((value ^ (value >> 31)) & 0x7fff_ffff)
    }
}

private enum CityPixelFont {
    static let glyphs: [Character: [Int]] = [
        "0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7],
        "2": [7, 1, 7, 4, 7], "3": [7, 1, 7, 1, 7],
        "4": [5, 5, 7, 1, 1], "5": [7, 4, 7, 1, 7],
        "6": [7, 4, 7, 5, 7], "7": [7, 1, 1, 2, 2],
        "8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 7],
        ":": [0, 2, 0, 2, 0], "N": [5, 7, 7, 5, 5],
        " ": [0, 0, 0, 0, 0]
    ]
}
