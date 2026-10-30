import Foundation

enum AbyssEncounterKind: CaseIterable, Sendable {
    case leviathan
    case elder
}

struct AbyssEncounter: Equatable, Sendable {
    let kind: AbyssEncounterKind
    /// Normalized passage progress; direction changes the creature's orientation.
    let progress: Double
    let direction: Int
    let variation: Double
}

/// The small station keeps its own long-lived lighting schedules while enormous
/// creatures occasionally cross the water beyond it. Work and storage per frame
/// stay bounded, including after sleep or a very large direct simulation jump.
struct AbyssSceneModel: Sendable {
    static let windowCount = 12
    static let maximumFrameAdvance = 0.5
    private static let maximumCatchUpChanges = 32

    private(set) var elapsed: Double = 0
    private var windows: [AbyssWindowSchedule]
    private var passage: AbyssEncounterSchedule
    private let ventPhase: Double
    private var lastUptime: Double?

    var encounter: AbyssEncounter? { passage.state(at: elapsed) }

    /// A creature eases out of and back into the haze over many seconds.
    var encounterVisibility: Double {
        guard encounter != nil else { return 0 }
        return min(abyssSmooth((elapsed - passage.departure) / 10),
                   abyssSmooth((passage.departure + passage.duration - elapsed) / 13))
    }

    /// One full searchlight sweep takes almost a minute.
    var beamPhase: Double { elapsed.truncatingRemainder(dividingBy: 57) / 57 }

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        var random = AbyssRandom(seed: seed)
        windows = (0..<Self.windowCount).map { _ in AbyssWindowSchedule(seed: random.next()) }
        passage = AbyssEncounterSchedule(seed: random.next())
        ventPhase = random.value(in: 0...(2 * .pi))
    }

    /// Use monotonic uptime in the live view. The first sample anchors the clock.
    /// Long pauses advance at most half a second, with no replay of missed events.
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

    /// Deterministic tools may simulate larger intervals directly. Each schedule
    /// processes a fixed number of changes before discarding a huge backlog.
    mutating func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, (elapsed + seconds).isFinite else { return }
        elapsed += seconds
        for index in windows.indices {
            windows[index].advance(to: elapsed, maximumChanges: Self.maximumCatchUpChanges)
        }
        passage.advance(to: elapsed, maximumChanges: Self.maximumCatchUpChanges)
    }

    func windowLight(id: Int) -> Double {
        let index = ((id % Self.windowCount) + Self.windowCount) % Self.windowCount
        return windows[index].light(at: elapsed)
    }

    func ventStrength(id: Int) -> Double {
        let phase = ventPhase + Double(id % 97) * 1.71
        let first = abyssWave(time: elapsed, period: 11.3, phase: phase)
        let second = abyssWave(time: elapsed, period: 23.7, phase: phase * 0.73)
        return 0.31 + 0.44 * first + 0.24 * second
    }
}

private struct AbyssEncounterSchedule: Sendable {
    private var random: AbyssRandom
    private(set) var departure: Double = 5
    private(set) var duration: Double
    private var kind: AbyssEncounterKind = .elder
    private var direction: Int
    private var variation: Double

    init(seed: UInt64) {
        var source = AbyssRandom(seed: seed)
        duration = source.value(in: 72...90)
        direction = source.next() % 2 == 0 ? 1 : -1
        variation = source.value(in: 0...1)
        random = source
    }

    func state(at time: Double) -> AbyssEncounter? {
        guard departure.isFinite, time >= departure else { return nil }
        let sinceDeparture = time - departure
        guard sinceDeparture < duration else { return nil }
        return AbyssEncounter(kind: kind, progress: min(1, max(0, sinceDeparture / duration)),
                              direction: direction, variation: variation)
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
        departure = abyssFuture(after: time, delay: random.value(in: 35...75))
        duration = random.value(in: 65...95)
        kind = kind == .elder ? .leviathan : .elder
        direction = random.next() % 2 == 0 ? 1 : -1
        variation = random.value(in: 0...1)
    }
}

private struct AbyssWindowSchedule: Sendable {
    private var random: AbyssRandom
    private var previous: Double
    private var current: Double
    private var transitionStart: Double = 0
    private var transitionDuration: Double = 0
    private var nextChange: Double

    init(seed: UInt64) {
        var source = AbyssRandom(seed: seed)
        let initial = source.value(in: 0.55...0.96)
        previous = initial
        current = initial
        nextChange = source.value(in: 12...55)
        random = source
    }

    func light(at time: Double) -> Double {
        let blend = transitionDuration > 0
            ? abyssSmooth((time - transitionStart) / transitionDuration) : 1
        return previous + (current - previous) * blend
    }

    mutating func advance(to time: Double, maximumChanges: Int) {
        var remaining = maximumChanges
        while time >= nextChange, remaining > 0 {
            previous = current
            current = random.value(in: 0.45...1)
            transitionStart = nextChange
            transitionDuration = random.value(in: 5...9)
            nextChange = abyssFuture(after: transitionStart,
                                     delay: transitionDuration + random.value(in: 24...100))
            remaining -= 1
        }
        if time >= nextChange {
            previous = current
            transitionStart = time
            transitionDuration = 0
            nextChange = abyssFuture(after: time, delay: random.value(in: 24...100))
        }
    }
}

private struct AbyssRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / 9_007_199_254_740_992
        return range.lowerBound + unit * (range.upperBound - range.lowerBound)
    }
}

private func abyssFuture(after time: Double, delay: Double) -> Double {
    let future = time + delay
    return future.isFinite && future > time ? future : .infinity
}

private func abyssSmooth(_ value: Double) -> Double {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - 2 * clamped)
}

private func abyssWave(time: Double, period: Double, phase: Double) -> Double {
    let angle = time.truncatingRemainder(dividingBy: period) * (2 * .pi / period) + phase
    return 0.5 + 0.5 * sin(angle)
}
