import Foundation

struct OrbitPoint: Equatable, Sendable {
    let x: Double
    let y: Double
}

enum OrbitShipPhase: CaseIterable, Sendable {
    case approaching, docked, departing
}

struct OrbitShip: Equatable, Sendable {
    let id: Int
    let phase: OrbitShipPhase
    let progress: Double
    let position: OrbitPoint
    /// Heading in the physical 1600×1000 design canvas, not square normalized space.
    let angle: Double
    let engine: Double
}

/// Three independent port schedules are enough for sustained docking traffic.
/// Coordinates use the shared 1600×1000 composition; storage never grows.
struct OrbitSceneModel: Sendable {
    static let stationCenter = OrbitPoint(x: 0.59, y: 0.49)
    static let ports = [OrbitPoint(x: 0.795, y: 0.632),
                        OrbitPoint(x: 0.375, y: 0.595),
                        OrbitPoint(x: 0.59, y: 0.30)]
    static let maximumFrameAdvance = 0.5
    private(set) var elapsed: Double = 0
    private var schedules: [OrbitPortSchedule]
    private var previousUptime: Double?

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        var random = OrbitRandom(seed: seed)
        schedules = (0..<3).map { id in
            let first = id == 0 ? -5.0 : Double(id) * 19 + random.value(in: 0...8)
            return OrbitPortSchedule(id: id, departure: first, random: OrbitRandom(seed: random.next()))
        }
    }

    var ships: [OrbitShip] { schedules.compactMap { $0.ship(at: elapsed) } }

    /// The habitat makes a slow, small attitude adjustment; no abrupt full turns.
    var stationAngle: Double {
        sin(elapsed.truncatingRemainder(dividingBy: 2 * .pi * 47) / 47) * 0.025
    }

    var ringPhase: Double { elapsed.truncatingRemainder(dividingBy: 120) / 120 }

    func beaconStrength(id: Int) -> Double {
        let index = ((id % 13) + 13) % 13
        let period = 10 + Double(index) * 1.7
        let angle = elapsed.truncatingRemainder(dividingBy: period) / period * 2 * .pi
        return 0.74 + sin(angle + Double(index) * 1.83) * 0.17
    }

    mutating func advance(to timestamp: Double) {
        guard timestamp.isFinite else { return }
        guard let previous = previousUptime else {
            previousUptime = timestamp
            return
        }
        guard timestamp >= previous else { return }
        previousUptime = timestamp
        step(seconds: min(timestamp - previous, Self.maximumFrameAdvance))
    }

    mutating func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, (elapsed + seconds).isFinite else { return }
        elapsed += seconds
        for index in schedules.indices { schedules[index].advance(to: elapsed) }
    }
}

private struct OrbitPortSchedule: Sendable {
    let id: Int
    private var random: OrbitRandom
    private var departure: Double
    private var approach = 20.0
    private var hold = 10.0
    private var exit = 20.0
    private var pause = 30.0
    private var start = OrbitPoint(x: 1.1, y: 0.8)
    private var end = OrbitPoint(x: -0.1, y: 0.7)
    private var dockingAngle = 0.0

    private var port: OrbitPoint { OrbitSceneModel.ports[id] }
    private var activeEnd: Double { orbitFuture(after: departure, delay: approach + hold + exit) }
    private var cycleEnd: Double { orbitFuture(after: activeEnd, delay: pause) }

    init(id: Int, departure: Double, random: OrbitRandom) {
        self.id = id
        self.departure = departure
        self.random = random
        chooseVoyage()
    }

    mutating func advance(to time: Double) {
        var changes = 0
        while time >= cycleEnd, changes < 16 {
            departure = cycleEnd
            chooseVoyage()
            changes += 1
        }
        if time >= cycleEnd {
            departure = orbitFuture(after: time, delay: random.value(in: 15...40))
            chooseVoyage()
        }
    }

    private mutating func chooseVoyage() {
        approach = random.value(in: 18...26)
        hold = random.value(in: 8...15)
        exit = random.value(in: 18...25)
        pause = random.value(in: 20...55)
        switch id {
        case 0:
            start = OrbitPoint(x: 1.12, y: 0.80 + random.value(in: -0.06...0.06))
            end = OrbitPoint(x: 1.12, y: 0.18 + random.value(in: -0.05...0.05))
        case 1:
            start = OrbitPoint(x: -0.12, y: 0.82 + random.value(in: -0.05...0.05))
            end = OrbitPoint(x: -0.12, y: 0.23 + random.value(in: -0.06...0.06))
        default:
            start = OrbitPoint(x: 0.93 + random.value(in: -0.06...0.06), y: -0.12)
            end = OrbitPoint(x: 0.24 + random.value(in: -0.05...0.05), y: -0.12)
        }
        dockingAngle = atan2(port.y - start.y, port.x - start.x)
    }

    func ship(at time: Double) -> OrbitShip? {
        let age = time - departure
        guard time.isFinite, age.isFinite, age >= 0, age < approach + hold + exit else { return nil }
        if age < approach {
            let progress = orbitClamp(age / approach)
            let travel = orbitSmooth(progress)
            let c1 = orbitLerp(start, port, 0.38)
            let c2 = OrbitPoint(x: port.x - cos(dockingAngle) * 0.11,
                                y: port.y - sin(dockingAngle) * 0.11)
            let path = orbitBezier(start, c1, c2, port, travel)
            let tangent = orbitBezierTangent(start, c1, c2, port, travel)
            let angle = orbitUnwrap(atan2(tangent.y * 1000, tangent.x * 1600),
                                    near: orbitCanvasAngle(dockingAngle))
            let engine = (0.57 + 0.07 * sin(time / 3 + Double(id))) *
                (1 - orbitSmooth((progress - 0.60) / 0.40))
            return OrbitShip(id: id, phase: .approaching, progress: progress,
                             position: path, angle: angle, engine: engine)
        }
        if age < approach + hold {
            let progress = orbitClamp((age - approach) / hold)
            return OrbitShip(id: id, phase: .docked, progress: progress,
                             position: port, angle: orbitCanvasAngle(dockingAngle) + .pi * orbitSmooth(progress),
                             engine: 0)
        }
        let progress = orbitClamp((age - approach - hold) / exit)
        let travel = orbitSmooth(progress)
        let leavingAngle = dockingAngle + .pi
        let c1 = OrbitPoint(x: port.x + cos(leavingAngle) * 0.12,
                            y: port.y + sin(leavingAngle) * 0.12)
        let c2 = orbitLerp(port, end, 0.70)
        let path = orbitBezier(port, c1, c2, end, travel)
        let tangent = orbitBezierTangent(port, c1, c2, end, travel)
        let angle = orbitUnwrap(atan2(tangent.y * 1000, tangent.x * 1600),
                                near: orbitCanvasAngle(dockingAngle) + .pi)
        let engine = (0.64 + sin(time / 3.7 + Double(id)) * 0.07) *
            orbitSmooth(progress / 0.12) * (1 - orbitSmooth((progress - 0.88) / 0.12))
        return OrbitShip(id: id, phase: .departing, progress: progress,
                         position: path, angle: angle, engine: engine)
    }
}

private struct OrbitRandom: Sendable {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func value(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / Double(UInt64.max >> 11)
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

private func orbitClamp(_ x: Double) -> Double { max(0, min(1, x)) }
private func orbitSmooth(_ x: Double) -> Double { let t = orbitClamp(x); return t * t * (3 - 2 * t) }
private func orbitFuture(after time: Double, delay: Double) -> Double {
    let result = time + delay
    return result > time ? result : time.nextUp
}
private func orbitLerp(_ a: OrbitPoint, _ b: OrbitPoint, _ t: Double) -> OrbitPoint {
    OrbitPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}
private func orbitBezier(_ a: OrbitPoint, _ b: OrbitPoint, _ c: OrbitPoint, _ d: OrbitPoint,
                         _ t: Double) -> OrbitPoint {
    let u = 1 - t
    return OrbitPoint(x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
                      y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)
}
private func orbitBezierTangent(_ a: OrbitPoint, _ b: OrbitPoint, _ c: OrbitPoint, _ d: OrbitPoint,
                                _ t: Double) -> OrbitPoint {
    let u = 1 - t
    return OrbitPoint(x: 3 * u * u * (b.x - a.x) + 6 * u * t * (c.x - b.x) + 3 * t * t * (d.x - c.x),
                      y: 3 * u * u * (b.y - a.y) + 6 * u * t * (c.y - b.y) + 3 * t * t * (d.y - c.y))
}
private func orbitUnwrap(_ angle: Double, near reference: Double) -> Double {
    reference + atan2(sin(angle - reference), cos(angle - reference))
}
private func orbitCanvasAngle(_ normalized: Double) -> Double {
    atan2(sin(normalized) * 1000, cos(normalized) * 1600)
}
