import Foundation

struct IslandCell: Hashable, Sendable {
    let x: Int
    let y: Int
    var neighbours: [IslandCell] {
        [IslandCell(x: x - 1, y: y), IslandCell(x: x + 1, y: y),
         IslandCell(x: x, y: y - 1), IslandCell(x: x, y: y + 1)]
    }
}

enum IslandGround: Equatable, Sendable { case grass, path, pier }

struct IslandTile: Sendable {
    let cell: IslandCell
    let level: Int
    let ground: IslandGround
    var isWalkable: Bool { ground != .grass }
    var top: Double { 24 + Double(level) * 12 }
}

enum IslandBuildingKind: CaseIterable, Equatable, Sendable {
    case house, tower, hall, workshop, garden, keep
}

struct IslandBuilding: Equatable, Sendable {
    let id: Int
    let cell: IslandCell
    let kind: IslandBuildingKind
    let floors: Int
    let variant: UInt64
    let permanent: Bool

    var wallHeight: Double {
        switch kind {
        case .house: 16 + Double(floors) * 15
        case .tower: 30 + Double(floors) * 22
        case .hall: 24 + Double(floors) * 17
        case .workshop: 19 + Double(floors) * 13
        case .keep: 35 + Double(floors) * 21
        case .garden: 23
        }
    }
    var height: Double {
        wallHeight + (kind == .house || kind == .hall ? 23 : kind == .workshop ? 16 : kind == .garden ? 0 : 17)
    }
}

struct IslandProject: Sendable {
    let building: IslandBuilding
    let dismantling: Bool
    let progress: Double
    var visibleFraction: Double { dismantling ? 1 - progress : progress }
}

/// An immutable connected island and bounded plots; only one site changes at once.
struct IslandSceneModel: Sendable {
    let seed: UInt64
    let tiles: [IslandTile]
    let plots: [IslandCell]
    private let tileMap: [IslandCell: IslandTile]
    private(set) var buildings: [IslandBuilding]
    private(set) var elapsed: Double = 0
    private(set) var revision: UInt64 = 0
    private(set) var completedConstructions = 0
    private(set) var completedDismantlings = 0
    private var random: IslandRandom
    private var schedule: IslandSchedule?
    private var lastUptime: Double?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        self.seed = seed
        var random = IslandRandom(seed: seed)
        let tiles = Self.makeTiles(seed: seed)
        let map: [IslandCell: IslandTile] = Dictionary(uniqueKeysWithValues: tiles.map { ($0.cell, $0) })
        var plots: [IslandCell] = []
        for tile in tiles where tile.ground == .grass {
            if tile.cell.neighbours.contains(where: { map[$0]?.isWalkable == true }) {
                plots.append(tile.cell)
            }
        }
        plots.sort { a, b in a.x == b.x ? a.y < b.y : a.x < b.x }
        self.tiles = tiles
        self.plots = plots
        tileMap = map
        let keepCell = IslandCell(x: 6, y: 6)
        let lighthouseCandidates = plots.filter { $0 != keepCell }
        let lighthouse = lighthouseCandidates.max { a, b in (a.x - a.y) < (b.x - b.y) }!
        let foregroundCandidates = plots.filter { $0 != keepCell && $0 != lighthouse }
        let foreground = foregroundCandidates.max { a, b in (a.x + a.y) < (b.x + b.y) }!
        var occupied: [IslandBuilding] = []
        for (id, cell) in plots.enumerated() {
            if cell == keepCell {
                occupied.append(IslandBuilding(id: id, cell: cell, kind: .keep, floors: 4,
                                               variant: random.next(), permanent: true))
            } else if cell == lighthouse {
                occupied.append(IslandBuilding(id: id, cell: cell, kind: .tower, floors: 4,
                                               variant: random.next(), permanent: true))
            } else if cell != foreground && random.unit() < 0.72 {
                occupied.append(Self.makeBuilding(id: id, cell: cell, random: &random))
            }
        }
        buildings = occupied
        self.random = random
        let id = plots.firstIndex(of: foreground)!
        let building = Self.makeBuilding(id: id, cell: foreground, random: &self.random)
        schedule = IslandSchedule(building: building, dismantling: false, start: 2, duration: 24)
    }

    var project: IslandProject? {
        guard let schedule, elapsed >= schedule.start else { return nil }
        return IslandProject(building: schedule.building, dismantling: schedule.dismantling,
                             progress: min(1, max(0, (elapsed - schedule.start) / schedule.duration)))
    }

    func tile(at cell: IslandCell) -> IslandTile? { tileMap[cell] }

    func windowLight(buildingID: Int) -> Double {
        let phase = Double((UInt64(bitPattern: Int64(buildingID)) &* 0x9E3779B97F4A7C15) >> 53) / 2048 * 2 * .pi
        return 0.65 + 0.22 * sin(elapsed / 43 + phase) + 0.08 * sin(elapsed / 81 + phase * 1.3)
    }

    mutating func advance(to timestamp: Double) {
        guard timestamp.isFinite else { return }
        guard let previous = lastUptime else { lastUptime = timestamp; return }
        guard timestamp >= previous else { return }
        lastUptime = timestamp
        step(seconds: min(0.5, timestamp - previous))
    }

    mutating func step(seconds: Double) {
        guard seconds > 0, seconds.isFinite, (elapsed + seconds).isFinite else { return }
        elapsed += seconds
        var remaining = 32
        while let current = schedule, elapsed >= current.end, remaining > 0 {
            finish(current)
            scheduleNext(after: current.end)
            remaining -= 1
        }
        if let current = schedule, elapsed >= current.end { scheduleNext(after: elapsed) }
    }

    private mutating func finish(_ current: IslandSchedule) {
        if current.dismantling {
            buildings.removeAll { $0.id == current.building.id }
            completedDismantlings &+= 1
        } else {
            buildings.removeAll { $0.id == current.building.id }
            buildings.append(current.building)
            completedConstructions &+= 1
        }
        revision &+= 1
    }

    private mutating func scheduleNext(after time: Double) {
        let occupied = Set(buildings.map(\.cell))
        let empty = plots.filter { !occupied.contains($0) }
        let removable = buildings.filter { !$0.permanent }
        let dismantling = !removable.isEmpty && (empty.isEmpty || random.next() % 3 == 0)
        let building: IslandBuilding
        if dismantling {
            building = removable[Int(random.next() % UInt64(removable.count))]
        } else {
            guard !empty.isEmpty else { schedule = nil; return }
            let cell = empty[Int(random.next() % UInt64(empty.count))]
            building = Self.makeBuilding(id: plots.firstIndex(of: cell)!, cell: cell, random: &random)
        }
        let start = islandFuture(time, random.value(3...7))
        schedule = IslandSchedule(building: building, dismantling: dismantling, start: start,
                                  duration: dismantling ? random.value(11...17) : random.value(19...31))
    }

    private static func makeBuilding(id: Int, cell: IslandCell, random: inout IslandRandom) -> IslandBuilding {
        let choice = random.next() % 12
        let kind: IslandBuildingKind = choice < 5 ? .house : choice < 7 ? .tower : choice < 9 ? .hall : choice < 10 ? .workshop : .garden
        let floors = kind == .tower ? Int(random.next() % 3) + 2 : Int(random.next() % 2) + 1
        return IslandBuilding(id: id, cell: cell, kind: kind, floors: floors,
                              variant: random.next(), permanent: false)
    }

    private static func makeTiles(seed: UInt64) -> [IslandTile] {
        var result: [IslandTile] = []
        for y in 0...12 {
            for x in 0...12 {
                let dx = x - 6, dy = y - 6
                let radius = sqrt(Double(dx * dx + dy * dy))
                let jitter = Double(islandHash(seed ^ UInt64(x * 137 + y * 7919)) % 100) / 100
                guard radius <= 5.45 + jitter * 0.4 else { continue }
                let level = radius < 2.45 ? 3 : radius < 4.25 ? 2 : 1
                let innerRing = max(abs(dx), abs(dy)) == 1
                let outerRing = max(abs(dx), abs(dy)) == 3
                let cross = (dx == 0 || dy == 0) && (dx != 0 || dy != 0)
                result.append(IslandTile(cell: IslandCell(x: x, y: y), level: level,
                                         ground: innerRing || outerRing || cross ? .path : .grass))
            }
        }
        for cell in [IslandCell(x: 12, y: 6), IslandCell(x: 13, y: 6), IslandCell(x: 14, y: 6),
                     IslandCell(x: 14, y: 5), IslandCell(x: 14, y: 7)] {
            result.append(IslandTile(cell: cell, level: 0, ground: .pier))
        }
        return result.sorted { $0.cell.x + $0.cell.y == $1.cell.x + $1.cell.y
            ? $0.cell.x < $1.cell.x : $0.cell.x + $0.cell.y < $1.cell.x + $1.cell.y }
    }
}

private struct IslandSchedule: Sendable {
    let building: IslandBuilding
    let dismantling: Bool
    let start: Double
    let duration: Double
    var end: Double { islandFuture(start, duration) }
}

private func islandFuture(_ time: Double, _ delay: Double) -> Double {
    let next = time + delay
    return next.isFinite && next > time ? next : time.nextUp
}

func islandHash(_ value: UInt64) -> UInt64 {
    var x = value &+ 0x9E3779B97F4A7C15
    x = (x ^ (x >> 30)) &* 0xBF58476D1CE4E5B9
    x = (x ^ (x >> 27)) &* 0x94D049BB133111EB
    return x ^ (x >> 31)
}

private struct IslandRandom: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; return islandHash(state) }
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64.max >> 11) }
    mutating func value(_ range: ClosedRange<Double>) -> Double {
        range.lowerBound + unit() * (range.upperBound - range.lowerBound)
    }
}
