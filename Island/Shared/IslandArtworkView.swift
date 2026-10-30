import AppKit

/// Isometric stonework is drawn once per completed project; only the working
/// site, flags, boats and water need painting every frame.
final class IslandArtworkView: NSView {
    var model = IslandSceneModel()
    private var frameBuffer: CGContext?
    private var water: CGImage?
    private var behind: CGImage?
    private var ahead: CGImage?
    private var size = CGSize.zero
    private var cachedSeed: UInt64?
    private var cachedRevision: UInt64?
    private var cachedSite: Int?
    override var isOpaque: Bool { true }

    func advanceFrame() {
        model.advance(to: ProcessInfo.processInfo.systemUptime)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard bounds.width > 0, bounds.height > 0,
              let destination = NSGraphicsContext.current?.cgContext else { return }
        let backing = convertToBacking(bounds)
        let pixel = max(1, ceil(sqrt(backing.width * backing.height / 1_500_000)))
        let scale = max(1, backing.width / bounds.width)
        let w = max(1, Int(ceil(backing.width / pixel)))
        let h = max(1, Int(ceil(backing.height / pixel)))
        let newSize = CGSize(width: w, height: h)
        if size != newSize || cachedSeed != model.seed {
            size = newSize
            frameBuffer = Self.buffer(w, h)
            water = nil; behind = nil; ahead = nil
        }
        guard let frameBuffer else { return }
        let rectangle = CGRect(x: 0, y: 0, width: w, height: h)
        func paint(_ context: CGContext, _ body: (IslandPainter) -> Void) {
            context.saveGState()
            context.setShouldAntialias(false)
            context.interpolationQuality = .none
            context.translateBy(x: 0, y: Double(h)); context.scaleBy(x: 1, y: -1)
            body(IslandPainter(c: context, width: Double(w), height: Double(h), model: model))
            context.restoreGState()
        }
        if water == nil, let ocean = Self.buffer(w, h) {
            paint(ocean) { $0.drawOcean() }
            water = ocean.makeImage()
        }
        let site = model.project?.building.id
        if behind == nil || cachedRevision != model.revision || cachedSite != site || cachedSeed != model.seed,
           let back = Self.buffer(w, h), let front = Self.buffer(w, h) {
            let buildings = Dictionary(uniqueKeysWithValues: model.buildings.map { ($0.cell, $0) })
            let target = model.project?.building.cell
            for tile in model.tiles {
                let frontOfSite = target.map {
                    tile.cell.x + tile.cell.y > $0.x + $0.y ||
                        (tile.cell.x + tile.cell.y == $0.x + $0.y && tile.cell.x > $0.x)
                } ?? false
                paint(frontOfSite ? front : back) { p in
                    p.world {
                        p.drawTile(tile)
                        if let building = buildings[tile.cell], building.id != site {
                            p.drawBuilding(building, fraction: 1)
                        } else if buildings[tile.cell] == nil && tile.ground == .grass && tile.cell != target && !model.plots.contains(tile.cell) {
                            p.drawWildGarden(tile)
                        }
                    }
                }
            }
            behind = back.makeImage(); ahead = front.makeImage()
            cachedRevision = model.revision; cachedSite = site; cachedSeed = model.seed
        }
        frameBuffer.saveGState(); frameBuffer.setBlendMode(.copy)
        if let water { frameBuffer.draw(water, in: rectangle) }
        frameBuffer.restoreGState()
        paint(frameBuffer) { p in p.drawWaves(); p.world { p.drawShore(); p.drawBoat() } }
        if let behind { frameBuffer.draw(behind, in: rectangle) }
        if let project = model.project {
            paint(frameBuffer) { p in p.world {
                p.drawBuilding(project.building, fraction: project.visibleFraction)
                p.drawConstruction(project)
            } }
        }
        if let ahead { frameBuffer.draw(ahead, in: rectangle) }
        paint(frameBuffer) { p in p.world { p.drawLife() } }
        guard let result = frameBuffer.makeImage() else { return }
        destination.saveGState()
        destination.interpolationQuality = .none; destination.setShouldAntialias(false)
        destination.draw(result, in: CGRect(x: 0, y: 0,
                                            width: Double(w) * pixel / scale,
                                            height: Double(h) * pixel / scale))
        destination.restoreGState()
    }

    private static func buffer(_ w: Int, _ h: Int) -> CGContext? {
        CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    }
}

private func islandInk(_ rgb: UInt32, _ alpha: Double = 1) -> CGColor {
    CGColor(red: Double((rgb >> 16) & 255) / 255,
            green: Double((rgb >> 8) & 255) / 255,
            blue: Double(rgb & 255) / 255, alpha: max(0, min(1, alpha)))
}

private struct IslandPainter {
    let c: CGContext
    let width: Double
    let height: Double
    let model: IslandSceneModel
    private var time: Double { model.elapsed }
    private var zoom: Double { min(width / 760, height / 580) }

    func world(_ draw: () -> Void) {
        c.saveGState()
        c.translateBy(x: width * 0.5, y: height * 0.48 - 170 * zoom)
        c.scaleBy(x: zoom, y: zoom)
        draw()
        c.restoreGState()
    }

    private func p(_ x: Double, _ y: Double, _ z: Double = 0) -> CGPoint {
        CGPoint(x: (x - y) * 34, y: (x + y) * 17 - z)
    }

    private func path(_ points: [CGPoint]) -> CGPath {
        let result = CGMutablePath()
        if let first = points.first {
            result.move(to: first)
            for point in points.dropFirst() { result.addLine(to: point) }
            result.closeSubpath()
        }
        return result
    }

    private func fill(_ points: [CGPoint], _ color: UInt32, _ alpha: Double = 1) {
        c.addPath(path(points)); c.setFillColor(islandInk(color, alpha)); c.fillPath()
    }

    private func line(_ points: [CGPoint], _ color: UInt32, _ alpha: Double = 1, thickness: Double = 1) {
        guard let first = points.first else { return }
        c.beginPath(); c.move(to: first)
        for point in points.dropFirst() { c.addLine(to: point) }
        c.setStrokeColor(islandInk(color, alpha)); c.setLineWidth(thickness); c.strokePath()
    }

    private func box(_ x: Double, _ y: Double, _ z: Double, _ w: Double, _ d: Double,
                     _ h: Double, top: UInt32, left: UInt32, right: UInt32) {
        guard h > 0 else { return }
        fill([p(x, y + d, z), p(x + w, y + d, z), p(x + w, y + d, z + h), p(x, y + d, z + h)], left)
        fill([p(x + w, y, z), p(x + w, y + d, z), p(x + w, y + d, z + h), p(x + w, y, z + h)], right)
        fill([p(x, y, z + h), p(x + w, y, z + h), p(x + w, y + d, z + h), p(x, y + d, z + h)], top)
    }

    func drawOcean() {
        let palettes: [[UInt32]] = [[0x142f48, 0x27536a, 0x183b51],
                                    [0x212b49, 0x3d5367, 0x243f55],
                                    [0x153e4e, 0x2d6269, 0x1b4658]]
        let colors = palettes[Int(model.seed % 3)].map { islandInk($0) }
        if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                     colors: colors as CFArray, locations: nil) {
            c.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: height), options: [])
        }
    }

    func drawWaves() {
        for index in 0..<160 {
            let hash = islandHash(UInt64(index) &+ model.seed)
            let x = Double(hash & 65535) / 65535 * width
            let y = Double((hash >> 16) & 65535) / 65535 * height
            let phase = Double((hash >> 32) & 255) / 255 * 2 * .pi
            let drift = sin(time / 8 + phase) * 2.5
            let length = Double(6 + (hash >> 40) % 24) * max(0.6, zoom)
            let value = 0.11 + 0.10 * (0.5 + 0.5 * sin(time / 9 + phase))
            line([CGPoint(x: x + drift, y: y), CGPoint(x: x + drift + length * 0.5, y: y - 1),
                  CGPoint(x: x + drift + length, y: y)], 0x8bb5bd, value)
        }
    }

    func drawShore() {
        for tile in model.tiles where tile.ground != .pier {
            let x = Double(tile.cell.x), y = Double(tile.cell.y)
            let phase = time / 7 + x * 0.7 + y
            let swell = 0.13 + sin(phase) * 0.035
            if model.tile(at: IslandCell(x: tile.cell.x + 1, y: tile.cell.y)) == nil {
                line([p(x + 1 + swell, y, 1), p(x + 1 + swell, y + 1, 1)], 0xb4d2cf,
                     0.33 + sin(phase) * 0.08)
            }
            if model.tile(at: IslandCell(x: tile.cell.x, y: tile.cell.y + 1)) == nil {
                line([p(x, y + 1 + swell, 1), p(x + 1, y + 1 + swell, 1)], 0x9bbfbe,
                     0.30 + cos(phase) * 0.08)
            }
        }
    }

    func drawTile(_ tile: IslandTile) {
        let x = Double(tile.cell.x), y = Double(tile.cell.y), z = tile.top
        let hash = islandHash(model.seed ^ UInt64(tile.cell.x * 137 + tile.cell.y * 1777))
        if tile.ground == .pier {
            for corner in [(0.10, 0.10), (0.82, 0.82)] {
                box(x + corner.0, y + corner.1, 0, 0.09, 0.09, z,
                    top: 0xbaa382, left: 0x7a6956, right: 0x4b5356)
            }
            box(x, y, z - 4, 1, 1, 4, top: 0x9e8b6d, left: 0x78694f, right: 0x5d6055)
            for plank in 1..<7 {
                let v = Double(plank) / 7
                line([p(x, y + v, z + 0.2), p(x + 1, y + v, z + 0.2)], 0x5b6255, 0.75)
            }
            if tile.cell.x == 14 {
                line([p(x + 0.95, y + 0.05, z), p(x + 0.95, y + 0.05, z + 9),
                      p(x + 0.95, y + 0.95, z + 9), p(x + 0.95, y + 0.95, z)], 0xbaa082)
            }
            return
        }
        let east = model.tile(at: IslandCell(x: tile.cell.x + 1, y: tile.cell.y))?.top ?? 0
        let south = model.tile(at: IslandCell(x: tile.cell.x, y: tile.cell.y + 1))?.top ?? 0
        if south < z {
            fill([p(x, y + 1, south), p(x + 1, y + 1, south), p(x + 1, y + 1, z), p(x, y + 1, z)], 0x8a8170)
            for course in stride(from: south + 5, to: z, by: 7) {
                line([p(x, y + 1, course), p(x + 1, y + 1, course)], 0x59676b, 0.55)
                let offset = Int(course) % 2 == 0 ? 0.2 : 0.45
                for joint in [offset, offset + 0.4] {
                    line([p(x + joint, y + 1, course), p(x + joint, y + 1, min(z, course + 7))], 0x59676b, 0.5)
                }
            }
        }
        if east < z {
            fill([p(x + 1, y, east), p(x + 1, y + 1, east), p(x + 1, y + 1, z), p(x + 1, y, z)], 0x596a6d)
            for course in stride(from: east + 5, to: z, by: 7) {
                line([p(x + 1, y, course), p(x + 1, y + 1, course)], 0x354f5c, 0.55)
            }
        }
        let grass: [UInt32] = [0x6f8974, 0x768c73, 0x64816e, 0x7c9277]
        fill([p(x, y, z), p(x + 1, y, z), p(x + 1, y + 1, z), p(x, y + 1, z)],
             tile.ground == .path ? 0xaca58a : grass[Int(hash % 4)])
        if tile.ground == .path {
            line([p(x, y + 0.5, z), p(x + 1, y + 0.5, z)], 0x8a9180, 0.70)
            line([p(x + 0.5, y, z), p(x + 0.5, y + 1, z)], 0x8a9180, 0.70)
            for next in tile.cell.neighbours {
                if let neighbour = model.tile(at: next), neighbour.isWalkable, neighbour.top < z {
                    let dx = Double(next.x - tile.cell.x), dy = Double(next.y - tile.cell.y)
                    for step in 0..<4 {
                        let f = Double(step) / 4
                        let cx = x + 0.5 + dx * (0.3 + f * 0.55)
                        let cy = y + 0.5 + dy * (0.3 + f * 0.55)
                        line([p(cx - abs(dy) * 0.27, cy - abs(dx) * 0.27, z - f * (z - neighbour.top)),
                              p(cx + abs(dy) * 0.27, cy + abs(dx) * 0.27, z - f * (z - neighbour.top))], 0xd0c7a6)
                    }
                }
            }
        } else {
            for tuft in 0..<4 {
                let v = Double((hash >> (tuft * 8)) & 255) / 255
                let a = p(x + 0.15 + v * 0.65, y + 0.2 + Double(tuft) * 0.18, z + 0.4)
                line([a, CGPoint(x: a.x + 2, y: a.y - 1)], 0xa0a887, 0.7)
            }
        }
        if east < z { line([p(x + 1, y, z), p(x + 1, y + 1, z)], 0xb1ad8e, 0.75) }
        if south < z { line([p(x, y + 1, z), p(x + 1, y + 1, z)], 0xc0b395, 0.7) }
    }

    func drawWildGarden(_ tile: IslandTile) {
        let h = islandHash(model.seed &+ UInt64(tile.cell.x * 37 + tile.cell.y * 79))
        guard h % 3 == 0 else { return }
        tree(x: Double(tile.cell.x) + 0.55, y: Double(tile.cell.y) + 0.5,
             z: tile.top, height: 16 + Double(h % 12), variant: h)
    }

    func drawBuilding(_ building: IslandBuilding, fraction: Double) {
        guard fraction > 0, let tile = model.tile(at: building.cell) else { return }
        let x = Double(building.cell.x) + 0.12, y = Double(building.cell.y) + 0.12, z = tile.top
        let shown = building.height * min(1, fraction)
        let h = min(building.wallHeight, shown)
        if building.kind == .garden {
            box(x, y, z, 0.76, 0.76, min(4, shown), top: 0x6d8162, left: 0x9c9479, right: 0x748072)
            for index in 0..<4 where fraction * 4 > Double(index) {
                let f = min(1, fraction * 4 - Double(index))
                tree(x: x + 0.18 + Double(index % 2) * 0.40, y: y + 0.18 + Double(index / 2) * 0.40,
                     z: z + 4, height: (14 + Double((building.variant >> index) % 8)) * f,
                     variant: building.variant &+ UInt64(index))
            }
            return
        }
        let material: [UInt32] = [0xc4bba0, 0xb6b399, 0xc7b79c, 0xb9b59c]
        let wall = material[Int(building.variant % 4)]
        if building.kind == .tower {
            tower(x: x + 0.38, y: y + 0.38, z: z, radius: 0.36,
                  height: h, full: building.wallHeight, variant: building.variant, battlements: shown >= building.wallHeight + 5)
            return
        }
        let d = building.kind == .hall ? 0.66 : 0.76
        box(x - 0.035, y - 0.035, z, 0.83, d + 0.07, min(5, shown),
            top: 0xd3c8aa, left: 0xa39c86, right: 0x7e8980)
        box(x, y, z + 3, 0.76, d, max(0, h - 3), top: 0xcfc5a8, left: wall, right: 0x919b8d)
        // Horizontal courses and staggered joints make the stonework architectural.
        for course in stride(from: 8.0, to: h, by: 6) {
            line([p(x, y + d, z + course), p(x + 0.76, y + d, z + course)], 0x8e9586, 0.52)
            line([p(x + 0.76, y, z + course), p(x + 0.76, y + d, z + course)], 0x677c7b, 0.55)
            for joint in 0..<3 {
                let at = 0.08 + Double(joint) * 0.26 + (Int(course) % 12 == 0 ? 0.12 : 0)
                guard at < 0.76 else { continue }
                line([p(x + at, y + d, z + course), p(x + at, y + d, z + min(h, course + 6))], 0x8e9586, 0.55)
            }
        }
        for floor in 0..<building.floors {
            let level = 13 + Double(floor) * (building.kind == .keep ? 21 : 15)
            if level + 9 < h {
                for u in [0.22, 0.54] { window(p(x + u, y + d + 0.005, z + level), lit: true) }
                window(p(x + 0.77, y + d * 0.5, z + level), lit: building.variant % 4 != 0)
            }
        }
        if h > 16 {
            let door = p(x + 0.39, y + d + 0.01, z + 2)
            c.setFillColor(islandInk(0x45565c)); c.fill(CGRect(x: door.x - 3, y: door.y - 10, width: 6, height: 10))
            line([CGPoint(x: door.x - 4, y: door.y - 10), CGPoint(x: door.x, y: door.y - 13),
                  CGPoint(x: door.x + 4, y: door.y - 10)], 0xe1ceb0)
        }
        if building.kind == .keep {
            for corner in [(0.01, 0.01), (0.73, 0.01), (0.01, 0.73), (0.73, 0.73)] {
                tower(x: x + corner.0, y: y + corner.1, z: z,
                      radius: 0.125, height: min(h + 6, shown), full: building.wallHeight + 6,
                      variant: building.variant, battlements: shown > building.wallHeight + 8)
            }
            if shown > building.wallHeight {
                crenels(x: x, y: y, z: z + building.wallHeight, width: 0.76, depth: d,
                        height: min(7, shown - building.wallHeight))
            }
        } else if shown > building.wallHeight {
            roof(x: x - 0.07, y: y - 0.07, z: z + building.wallHeight,
                 w: 0.90, d: d + 0.14, rise: min(building.height - building.wallHeight, shown - building.wallHeight),
                 variant: building.variant)
            if building.kind == .workshop && fraction > 0.97 {
                box(x + 0.12, y + 0.12, z + building.height - 4, 0.13, 0.13, 13,
                    top: 0xb39e84, left: 0x9a8978, right: 0x68767a)
            }
        }
    }

    private func window(_ point: CGPoint, lit: Bool) {
        c.setFillColor(islandInk(0x465861)); c.fill(CGRect(x: point.x - 2, y: point.y - 7, width: 5, height: 8))
        c.setFillColor(islandInk(lit ? 0xe7ba72 : 0x718785))
        c.fill(CGRect(x: point.x - 1, y: point.y - 6, width: 3, height: 5))
        line([CGPoint(x: point.x, y: point.y - 6), CGPoint(x: point.x, y: point.y - 1)], 0x736d58, 0.65)
    }

    private func roof(x: Double, y: Double, z: Double, w: Double, d: Double, rise: Double, variant: UInt64) {
        let palette: [(UInt32, UInt32)] = [(0x566781, 0x3b5269), (0x537f80, 0x3b666e), (0x9b705d, 0x775a54)]
        let colors = palette[Int(variant % 3)]
        fill([p(x, y, z), p(x + w, y, z), p(x + w, y + d / 2, z + rise), p(x, y + d / 2, z + rise)], colors.1)
        fill([p(x, y + d, z), p(x + w, y + d, z), p(x + w, y + d / 2, z + rise), p(x, y + d / 2, z + rise)], colors.0)
        fill([p(x + w, y, z), p(x + w, y + d, z), p(x + w, y + d / 2, z + rise)], 0xc3b69a)
        for row in 1..<7 {
            let t = Double(row) / 7
            line([p(x, y + d * (1 - t / 2), z + rise * t), p(x + w, y + d * (1 - t / 2), z + rise * t)], 0x243e53, 0.37)
        }
        line([p(x, y + d / 2, z + rise), p(x + w, y + d / 2, z + rise)], 0xa5b1ab, 0.8)
    }

    private func tower(x: Double, y: Double, z: Double, radius: Double, height: Double,
                       full: Double, variant: UInt64, battlements: Bool) {
        guard height > 0 else { return }
        let points = (0..<8).map { index -> (Double, Double) in
            let angle = Double(index) / 8 * .pi * 2
            return (x + cos(angle) * radius, y + sin(angle) * radius)
        }
        let faces = (0..<8).sorted { (points[$0].0 + points[$0].1) < (points[$1].0 + points[$1].1) }
        for index in faces {
            let a = points[index], b = points[(index + 1) % 8]
            let shade: [UInt32] = [0x999d8b, 0xbab59a, 0xc9bfa2, 0xc4b99c, 0xaaa98f, 0x899a90, 0x7d9190, 0x8e9c91]
            fill([p(a.0, a.1, z), p(b.0, b.1, z), p(b.0, b.1, z + height), p(a.0, a.1, z + height)], shade[index])
        }
        for course in stride(from: 8.0, to: height, by: 8) {
            line(points.map { p($0.0, $0.1, z + course) } + [p(points[0].0, points[0].1, z + course)], 0x71877f, 0.42)
        }
        fill(points.map { p($0.0, $0.1, z + height) }, 0xcec3a4)
        if radius > 0.2 {
            for level in stride(from: 17.0, to: height - 3, by: 23) {
                window(p(x + radius * 0.62, y + radius * 0.62, z + level), lit: true)
            }
        }
        if battlements {
            for index in 0..<8 {
                let a = points[index]
                box(a.0 - 0.055, a.1 - 0.055, z + full, 0.11, 0.11, 6,
                    top: 0xe0d0ad, left: 0xbab49a, right: 0x8e9b8e)
            }
        }
    }

    private func crenels(x: Double, y: Double, z: Double, width: Double, depth: Double, height: Double) {
        for step in 0..<4 {
            let u = Double(step) / 4 * width
            for v in [0.0, depth - 0.12] {
                box(x + u, y + v, z, 0.13, 0.12, height,
                    top: 0xe0cfa9, left: 0xbdb397, right: 0x8e9d8f)
            }
        }
    }

    private func tree(x: Double, y: Double, z: Double, height: Double, variant: UInt64) {
        guard height > 1 else { return }
        let trunk = p(x, y, z)
        line([trunk, p(x, y, z + height * 0.65)], 0x626955, thickness: 2)
        let top = p(x, y, z + height)
        let radius = height * 0.33
        fill([CGPoint(x: top.x, y: top.y), CGPoint(x: top.x - radius, y: top.y + radius * 1.6),
              CGPoint(x: top.x + radius, y: top.y + radius * 1.6)], 0x355e5d)
        fill([CGPoint(x: top.x, y: top.y + radius * 0.7), CGPoint(x: top.x - radius * 1.2, y: top.y + radius * 2.25),
              CGPoint(x: top.x + radius * 1.2, y: top.y + radius * 2.25)], variant % 2 == 0 ? 0x527b65 : 0x607f67)
        line([CGPoint(x: top.x, y: top.y + 1), CGPoint(x: top.x - radius * 0.55, y: top.y + radius * 1.3)], 0x90a07a, 0.7)
    }

    func drawConstruction(_ project: IslandProject) {
        guard let tile = model.tile(at: project.building.cell) else { return }
        let x = Double(tile.cell.x), y = Double(tile.cell.y), z = tile.top
        let h = project.building.height * project.visibleFraction
        let a = p(x + 0.05, y + 1.02, z), b = p(x + 1.02, y + 1.02, z)
        let at = p(x + 0.05, y + 1.02, z + h + 12), bt = p(x + 1.02, y + 1.02, z + h + 12)
        line([a, at, bt, b], 0x967c5b, 0.95)
        for level in stride(from: 8.0, to: h + 12, by: 16) {
            line([p(x + 0.05, y + 1.02, z + level), p(x + 1.02, y + 1.02, z + min(h + 12, level + 13))], 0xba9c6a, 0.8)
        }
        let phase = (time / 1.35).truncatingRemainder(dividingBy: 1)
        let travel = project.dismantling ? 1 - phase : phase
        let from = p(x + 1.1, y + 1.1, z + 3)
        let to = p(x + 0.4, y + 0.6, z + h + 2)
        let block = CGPoint(x: from.x + (to.x - from.x) * travel,
                            y: from.y + (to.y - from.y) * travel - sin(travel * .pi) * 22)
        let fade = min(1, min(phase, 1 - phase) * 10)
        c.setFillColor(islandInk(0xd8c49b, fade)); c.fill(CGRect(x: block.x - 2, y: block.y - 2, width: 5, height: 4))
        for crate in 0..<3 {
            box(x + 0.9 + Double(crate % 2) * 0.13, y + 0.8 + Double(crate / 2) * 0.15,
                z, 0.11, 0.11, 5, top: 0xb49c6c, left: 0x907952, right: 0x6f6e56)
        }
    }

    func drawLife() {
        for building in model.buildings where building.kind == .tower || building.kind == .keep {
            guard building.id != model.project?.building.id,
                  let tile = model.tile(at: building.cell) else { continue }
            let top = p(Double(building.cell.x) + 0.5, Double(building.cell.y) + 0.5,
                        tile.top + building.wallHeight + 8)
            line([top, CGPoint(x: top.x, y: top.y - 19)], 0xc5bb9f)
            let shift = sin(time / 2.9 + Double(building.id)) * 2
            fill([CGPoint(x: top.x + 1, y: top.y - 19), CGPoint(x: top.x + 13, y: top.y - 17 + shift),
                  CGPoint(x: top.x + 10, y: top.y - 10 + shift), CGPoint(x: top.x + 1, y: top.y - 12)],
                 building.permanent ? 0xbc8e63 : 0x9b6974)
            if building.permanent && building.kind == .tower {
                c.setFillColor(islandInk(0xedca81, model.windowLight(buildingID: building.id)))
                c.fill(CGRect(x: top.x - 2, y: top.y - 3, width: 4, height: 4))
            }
        }
        for index in 0..<3 {
            let phase = time / 64 + Double(index) * 1.9
            let x = sin(phase) * 240, y = -35 + cos(phase * 0.8) * 22
            let flap = sin(time * 1.3 + Double(index)) * 2
            line([CGPoint(x: x - 4, y: y + flap), CGPoint(x: x, y: y), CGPoint(x: x + 4, y: y + flap)], 0xc3c8b6, 0.7)
        }
    }

    func drawBoat() {
        let bob = sin(time / 5) * 1.5
        let center = p(14.8, 8.7, 0)
        fill([CGPoint(x: center.x - 18, y: center.y + bob), CGPoint(x: center.x + 18, y: center.y - 5 + bob),
              CGPoint(x: center.x + 10, y: center.y + 5 + bob), CGPoint(x: center.x - 9, y: center.y + 8 + bob)], 0x9e7f5c)
        line([CGPoint(x: center.x - 12, y: center.y + 1 + bob), CGPoint(x: center.x + 13, y: center.y - 3 + bob)], 0xc2a57b)
        line([CGPoint(x: center.x, y: center.y + bob), CGPoint(x: center.x, y: center.y - 36 + bob)], 0xbaa88c)
        fill([CGPoint(x: center.x + 1, y: center.y - 34 + bob), CGPoint(x: center.x + 1, y: center.y - 7 + bob),
              CGPoint(x: center.x + 18, y: center.y - 10 + bob)], 0xc9c3a7)
        fill([CGPoint(x: center.x - 1, y: center.y - 30 + bob), CGPoint(x: center.x - 1, y: center.y - 7 + bob),
              CGPoint(x: center.x - 13, y: center.y - 5 + bob)], 0x909e99)
        for row in 0..<5 {
            let y = center.y + 12 + Double(row) * 4
            line([CGPoint(x: center.x - 11 + sin(time / 5 + Double(row)) * 2, y: y),
                  CGPoint(x: center.x + 10, y: y)], 0xb7c3b4, 0.12 - Double(row) * 0.018)
        }
    }
}
