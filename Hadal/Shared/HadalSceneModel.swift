import Foundation

enum HadalCreatureKind: String, CaseIterable, Sendable {
    case maw, ribbon, medusa, carapace, elder

    var assetName: String { "hadal-" + rawValue }

    var title: String {
        switch self {
        case .maw: "Костяная пасть"
        case .ribbon: "Ленточный угорь"
        case .medusa: "Медуза-собор"
        case .carapace: "Панцирный исполин"
        case .elder: "Древний"
        }
    }
}

struct HadalPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

/// Shared normalized geometry for the 1600×1000 city composition. The renderer
/// maps these coordinates into its aspect-preserving canvas on every display.
enum HadalCityLayout {
    static let domeCenterX = 0.5
    static let domeBaseY = 0.79
    static let domeRadiusX = 0.42
    static let domeRadiusY = 0.60
    static let seabedY = 0.73

    /// Greatest permitted water Y at this X: the top of the pressure field over
    /// the city, or the seabed outside it. Smaller Y is higher in the water.
    static func waterCeiling(atX x: Double) -> Double {
        guard x.isFinite else { return seabedY }
        let offset = (x - domeCenterX) / domeRadiusX
        guard abs(offset) <= 1 else { return seabedY }
        let dome = domeBaseY - domeRadiusY * sqrt(max(0, 1 - offset * offset))
        return min(seabedY, dome)
    }
}

enum HadalEncounterStage: CaseIterable, Sendable {
    case approaching, illuminated, repelled, retreating
}

struct HadalEncounter: Equatable, Sendable {
    let kind: HadalCreatureKind
    let age: Double
    let duration: Double
    let stage: HadalEncounterStage
    let center: HadalPoint
    /// Positive means moving right, negative means moving left.
    let facing: Int
    let scale: Double
    let visibility: Double
}

struct HadalFlare: Equatable, Sendable {
    let id: Int
    let position: HadalPoint
    let strength: Double
    /// Radius relative to the width of the composition.
    let radius: Double
    let age: Double
}

struct HadalCharge: Equatable, Sendable {
    let id: Int
    let origin: HadalPoint
    let position: HadalPoint
    let target: HadalPoint
    let progress: Double
    /// Smooth light pulse after arrival, not a single-frame explosion.
    let burst: Double
}

/// One encounter, twelve window schedules and two possible flares are enough to
/// animate the whole outpost. Old encounters are discarded rather than retained.
struct HadalSceneModel: Sendable {
    static let windowCount = 12
    static let chargeLaunchAge = 26.0
    static let chargeImpactAge = 30.5
    static let retreatAge = 35.5
    static let maximumFrameAdvance = 0.5
    private static let maximumCatchUpChanges = 16

    private(set) var elapsed: Double = 0
    private var random: HadalRandom
    private var bag: [HadalCreatureKind]
    private var bagIndex: Int
    private var passage: HadalPassage
    private var windows: [HadalWindow]
    private var lastUptime: Double?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        var source = HadalRandom(seed: seed)
        var firstBag = HadalCreatureKind.allCases
        source.shuffle(&firstBag)
        let first = firstBag[0]
        bag = firstBag
        bagIndex = 1
        passage = HadalPassage(kind: first, departure: 3, random: &source)
        windows = (0..<Self.windowCount).map { _ in HadalWindow(random: &source) }
        random = source
    }

    var encounter: HadalEncounter? { passage.encounter(at: elapsed) }

    var flares: [HadalFlare] {
        guard let event = encounter else { return [] }
        return (0..<2).compactMap { index in
            let age = event.age - (index == 0 ? 12.0 : 18.0)
            let lifetime = 31.0
            guard age >= 0, age < lifetime else { return nil }
            let target = passage.closestPoint
            let origin = HadalPoint(x: 0.5 + (target.x < 0.5 ? -0.18 : 0.18), y: 0.43)
            let side = index == 0 ? -1.0 : 1.0
            let destination = HadalPoint(x: 0.5 + (target.x - 0.5) * 0.75 + side * 0.045,
                                         y: 0.43 + (target.y - 0.43) * 0.86 + side * 0.015)
            let travel = 1 - pow(1 - hadalClamp(age / 11), 3)
            let drift = sin(age / 8 + Double(index) * 2.4) * 0.006
            let point = hadalLerp(origin, destination, travel)
            return HadalFlare(id: index,
                              position: HadalPoint(x: point.x + drift,
                                                   y: point.y + max(0, age - 8) * 0.001),
                              strength: min(hadalSmooth(age / 3),
                                            hadalSmooth((lifetime - age) / 9)),
                              radius: index == 0 ? 0.13 : 0.16, age: age)
        }
    }

    var charges: [HadalCharge] {
        guard let event = encounter else { return [] }
        let age = event.age - Self.chargeLaunchAge
        let travel = Self.chargeImpactAge - Self.chargeLaunchAge
        let pulseDuration = 4.2
        guard age >= 0, age < travel + pulseDuration else { return [] }
        let target = passage.point(at: Self.chargeImpactAge)
        let origin = HadalPoint(x: 0.5 + (target.x < 0.5 ? -0.18 : 0.18), y: 0.43)
        let progress = hadalClamp(age / travel)
        let straight = hadalLerp(origin, target, progress)
        let arc = sin(progress * .pi) * (target.y < 0.43 ? -0.025 : 0.025)
        let burstAge = max(0, age - travel)
        let burst = age < travel ? 0 : min(hadalSmooth(burstAge / 1.1),
                                          hadalSmooth((pulseDuration - burstAge) / 2.2))
        return [HadalCharge(id: 0, origin: origin,
                            position: HadalPoint(x: straight.x, y: straight.y + arc),
                            target: target, progress: progress, burst: burst)]
    }

    func windowLight(id: Int) -> Double {
        let count = Self.windowCount
        let index = ((id % count) + count) % count
        return windows[index].light(at: elapsed)
    }

    /// Standalone preview menus can begin a chosen species immediately. Installed
    /// savers only use the natural shuffled five-species encounter schedule.
    mutating func startEncounter(kind: HadalCreatureKind) {
        passage = HadalPassage(kind: kind, departure: elapsed, random: &random)
    }

    mutating func advance(to timestamp: Double) {
        guard timestamp.isFinite else { return }
        guard let previous = lastUptime else {
            lastUptime = timestamp
            return
        }
        guard timestamp >= previous else { return }
        lastUptime = timestamp
        step(seconds: min(timestamp - previous, Self.maximumFrameAdvance))
    }

    /// Tools may take larger deterministic steps. Even a huge time jump does at
    /// most a fixed number of event updates, never an hours-long catch-up loop.
    mutating func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, (elapsed + seconds).isFinite else { return }
        elapsed += seconds
        for index in windows.indices {
            windows[index].advance(to: elapsed, maximumChanges: Self.maximumCatchUpChanges)
        }
        var remaining = Self.maximumCatchUpChanges
        while elapsed >= passage.end, remaining > 0 {
            let departure = hadalFuture(after: passage.end, delay: random.value(in: 8...22))
            schedule(at: departure)
            remaining -= 1
        }
        if elapsed >= passage.end {
            schedule(at: hadalFuture(after: elapsed, delay: random.value(in: 8...22)))
        }
    }

    private mutating func schedule(at departure: Double) {
        if bagIndex >= bag.count {
            let last = bag.last!
            bag = HadalCreatureKind.allCases
            random.shuffle(&bag)
            // Preserve the shuffle bag while avoiding an adjacent repeat at its seam.
            if bag[0] == last { bag.swapAt(0, 1) }
            bagIndex = 0
        }
        let kind = bag[bagIndex]
        bagIndex += 1
        passage = HadalPassage(kind: kind, departure: departure, random: &random)
    }
}

private struct HadalPassage: Sendable {
    let kind: HadalCreatureKind
    let departure: Double
    let duration: Double
    let facing: Int
    let variation: Double

    var end: Double { hadalFuture(after: departure, delay: duration) }

    init(kind: HadalCreatureKind, departure: Double, random: inout HadalRandom) {
        self.kind = kind
        self.departure = departure
        duration = random.value(in: 56...64)
        facing = random.next() % 2 == 0 ? 1 : -1
        variation = random.value(in: 0...1)
    }

    var closestPoint: HadalPoint {
        let side = Double(facing)
        let point: HadalPoint
        switch kind {
        case .maw: point = HadalPoint(x: 0.5 - side * 0.26, y: 0.155 + variation * 0.025)
        case .ribbon: point = HadalPoint(x: 0.5 - side * 0.30, y: 0.19)
        case .medusa: point = HadalPoint(x: 0.5 + side * 0.12, y: 0.085 + variation * 0.02)
        case .carapace: point = HadalPoint(x: 0.5 - side * 0.31, y: 0.20)
        case .elder: point = HadalPoint(x: 0.5 - side * 0.26, y: 0.145)
        }
        return keepingClearOfCity(point)
    }

    func encounter(at time: Double) -> HadalEncounter? {
        guard time >= departure else { return nil }
        let age = time - departure
        guard age.isFinite, age >= 0, age < duration else { return nil }
        let stage: HadalEncounterStage
        if age < 12 { stage = .approaching }
        else if age < HadalSceneModel.chargeImpactAge { stage = .illuminated }
        else if age < HadalSceneModel.retreatAge { stage = .repelled }
        else { stage = .retreating }
        let retreat = hadalSmooth((age - HadalSceneModel.retreatAge) /
                                   (duration - HadalSceneModel.retreatAge))
        let approach = hadalSmooth(age / 22)
        return HadalEncounter(kind: kind, age: age, duration: duration, stage: stage,
                              center: point(at: age), facing: facing,
                              scale: (0.86 + approach * 0.14) * (1 - retreat * 0.65),
                              visibility: min(hadalSmooth(age / 8),
                                              hadalSmooth((duration - age) / 12)))
    }

    func point(at age: Double) -> HadalPoint {
        let side = Double(facing)
        let closest = closestPoint
        let start: HadalPoint
        let end: HadalPoint
        switch kind {
        case .medusa:
            start = HadalPoint(x: 0.5 + side * 0.28, y: -0.70)
            end = HadalPoint(x: 0.5 + side * 0.37, y: -0.75)
        case .carapace:
            start = HadalPoint(x: 0.5 - side * 0.36, y: -0.35)
            end = HadalPoint(x: 0.5 + side * 0.32, y: -0.55)
        case .ribbon:
            start = HadalPoint(x: 0.5 - side * 0.67, y: -0.28)
            end = HadalPoint(x: 0.5 + side * 0.67, y: -0.48)
        case .maw:
            start = HadalPoint(x: 0.5 - side * 0.58, y: -0.30)
            end = HadalPoint(x: 0.5 + side * 0.58, y: -0.50)
        case .elder:
            start = HadalPoint(x: 0.5 - side * 0.43, y: -0.38)
            end = HadalPoint(x: 0.5 + side * 0.40, y: -0.60)
        }
        if age < HadalSceneModel.chargeImpactAge {
            return age >= 22 ? closest : keepingClearOfCity(hadalLerp(start, closest, hadalSmooth(age / 22)))
        }
        if age < HadalSceneModel.retreatAge {
            let recoil = (age - HadalSceneModel.chargeImpactAge) /
                (HadalSceneModel.retreatAge - HadalSceneModel.chargeImpactAge)
            return keepingClearOfCity(HadalPoint(x: closest.x - side * sin(recoil * .pi) * 0.018,
                                                y: closest.y + sin(recoil * 2 * .pi) * 0.008))
        }
        return keepingClearOfCity(hadalLerp(closest, end,
                                           hadalSmooth((age - HadalSceneModel.retreatAge) /
                                                       (duration - HadalSceneModel.retreatAge))))
    }

    private func keepingClearOfCity(_ point: HadalPoint) -> HadalPoint {
        HadalPoint(x: point.x,
                   y: min(point.y, HadalCityLayout.waterCeiling(atX: point.x) - 0.045))
    }
}

private struct HadalWindow: Sendable {
    private var random: HadalRandom
    private var from: Double
    private var to: Double
    private var departure: Double
    private var duration: Double

    init(random source: inout HadalRandom) {
        var own = HadalRandom(seed: source.next())
        from = own.value(in: 0.45...1)
        to = own.value(in: 0.45...1)
        departure = own.value(in: 0...70)
        duration = own.value(in: 5...9)
        random = own
    }

    func light(at time: Double) -> Double {
        from + (to - from) * hadalSmooth((time - departure) / duration)
    }

    mutating func advance(to time: Double, maximumChanges: Int) {
        var remaining = maximumChanges
        while time >= departure + duration, remaining > 0 {
            schedule(after: departure + duration)
            remaining -= 1
        }
        if time >= departure + duration { schedule(after: time) }
    }

    private mutating func schedule(after time: Double) {
        from = to
        to = random.value(in: 0.45...1)
        departure = hadalFuture(after: time, delay: random.value(in: 24...100))
        duration = random.value(in: 5...9)
    }
}

private func hadalClamp(_ value: Double) -> Double { min(1, max(0, value)) }
private func hadalSmooth(_ value: Double) -> Double {
    let x = hadalClamp(value)
    return x * x * (3 - 2 * x)
}
private func hadalLerp(_ a: HadalPoint, _ b: HadalPoint, _ value: Double) -> HadalPoint {
    HadalPoint(x: a.x + (b.x - a.x) * value, y: a.y + (b.y - a.y) * value)
}
private func hadalFuture(after time: Double, delay: Double) -> Double {
    let result = time + delay
    if result.isFinite, result > time { return result }
    return time.nextUp.isFinite ? time.nextUp : time
}

private struct HadalRandom: Sendable {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &+ 0x9e3779b97f4a7c15
        var value = state
        value = (value ^ (value >> 30)) &* 0xbf58476d1ce4e5b9
        value = (value ^ (value >> 27)) &* 0x94d049bb133111eb
        return value ^ (value >> 31)
    }
    mutating func value(in range: ClosedRange<Double>) -> Double {
        let fraction = Double(next() >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + (range.upperBound - range.lowerBound) * fraction
    }
    mutating func shuffle<T>(_ values: inout [T]) {
        guard values.count > 1 else { return }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            values.swapAt(index, Int(next() % UInt64(index + 1)))
        }
    }
}
