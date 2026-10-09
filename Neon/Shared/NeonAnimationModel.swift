import Foundation

struct NeonBillboardState: Equatable, Sendable {
    let current: Int
    let previous: Int
    /// Smooth crossfade from the previous artwork to the current artwork.
    let blend: Double
    let brightness: Double
}

struct NeonTrainState: Equatable, Sendable {
    /// Passage progress always goes from 0 to 1, in either travel direction.
    let progress: Double
    let direction: Int
    let carCount: Int
}

/// Independent sign and train schedules and analytic light curves keep memory
/// use and the amount of work per animation frame constant over long sessions.
struct NeonAnimationModel: Sendable {
    static let billboardCount = 5
    static let maximumFrameAdvance = 0.5
    private static let maximumCatchUpChanges = 64

    private(set) var time: Double = 0
    private var signs: [NeonSignSchedule]
    private var trainSchedule: NeonTrainSchedule
    private let carLightPeriod: Double
    private let carLightPhase: Double
    private let underglowPhase: Double
    private let exhaustPhase: Double
    private var lastUptime: TimeInterval?

    /// These are continuous, slow changes in intensity, rather than on/off
    /// flashes. The car stays visible even at the bottom of a pulse.
    var carLight: Double {
        0.55 + 0.45 * neonWave(time: time, period: carLightPeriod, phase: carLightPhase)
    }

    var underglow: Double {
        0.58 + 0.34 * neonWave(time: time, period: 12.7, phase: underglowPhase)
    }

    var exhaust: Double {
        0.4 + 0.5 * neonWave(time: time, period: 9.3, phase: exhaustPhase)
    }

    var train: NeonTrainState? {
        trainSchedule.state(at: time)
    }

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        var source = NeonRandom(seed: seed)
        signs = (0..<Self.billboardCount).map { _ in
            NeonSignSchedule(seed: source.next())
        }
        carLightPeriod = source.value(in: 6...10)
        carLightPhase = source.value(in: 0...(2 * .pi))
        underglowPhase = source.value(in: 0...(2 * .pi))
        exhaustPhase = source.value(in: 0...(2 * .pi))
        trainSchedule = NeonTrainSchedule(seed: source.next())
    }

    /// Reanchor after sleep or a paused preview without replaying accumulated
    /// events. Ignore backward and non-finite clock samples.
    mutating func advance(to uptime: TimeInterval) {
        guard uptime.isFinite else { return }
        guard let previous = lastUptime else {
            lastUptime = uptime
            return
        }
        guard uptime >= previous else { return }
        lastUptime = uptime
        step(seconds: min(uptime - previous, Self.maximumFrameAdvance))
    }

    /// Direct simulation is useful for deterministic screenshots and tests.
    /// A huge QA jump still processes at most 64 sign changes and 64 departures.
    mutating func step(seconds: Double) {
        guard seconds.isFinite, seconds > 0, (time + seconds).isFinite else { return }
        time += seconds
        var remainingChanges = Self.maximumCatchUpChanges
        for index in signs.indices {
            signs[index].advance(to: time, remainingChanges: &remainingChanges)
        }
        trainSchedule.advance(to: time, maximumChanges: Self.maximumCatchUpChanges)
    }

    func billboard(id: Int) -> NeonBillboardState {
        // Remainders stay small even for Int.min, so this also safely supports
        // arbitrary renderer identifiers without growing the stored sign pool.
        let index = ((id % Self.billboardCount) + Self.billboardCount) % Self.billboardCount
        return signs[index].state(at: time)
    }
}

private struct NeonTrainSchedule: Sendable {
    private var random: NeonRandom
    private var departure: Double = 6
    private var duration: Double
    private var direction: Int
    private var carCount: Int

    init(seed: UInt64) {
        var source = NeonRandom(seed: seed)
        duration = source.value(in: 7...10)
        direction = source.next() % 2 == 0 ? 1 : -1
        carCount = 3 + Int(source.next() % 2)
        random = source
    }

    func state(at time: Double) -> NeonTrainState? {
        guard departure.isFinite, time >= departure else { return nil }
        let elapsed = time - departure
        guard elapsed.isFinite, elapsed < duration else { return nil }
        return NeonTrainState(progress: min(1, max(0, elapsed / duration)),
                              direction: direction, carCount: carCount)
    }

    mutating func advance(to time: Double, maximumChanges: Int) {
        var remainingChanges = maximumChanges
        while time >= departure + duration, remainingChanges > 0 {
            schedule(after: departure + duration)
            remainingChanges -= 1
        }
        if time >= departure + duration {
            // Discard an enormous backlog and resume with one future passage.
            schedule(after: time)
        }
    }

    private mutating func schedule(after time: Double) {
        let nextDeparture = time + random.value(in: 35...65)
        // At extreme QA times, seconds may be smaller than Double precision.
        // An infinite sentinel safely leaves the track empty in that case.
        departure = nextDeparture.isFinite && nextDeparture > time ? nextDeparture : .infinity
        duration = random.value(in: 7...10)
        direction = random.next() % 2 == 0 ? 1 : -1
        carCount = 3 + Int(random.next() % 2)
    }
}

private struct NeonSignSchedule: Sendable {
    private var random: NeonRandom
    private var current: Int
    private var previous: Int
    private var transitionStart: Double = 0
    private var transitionDuration: Double = 0
    private var nextChange: Double
    private let lightPeriod: Double
    private let lightPhase: Double

    init(seed: UInt64) {
        var source = NeonRandom(seed: seed)
        let variant = Int(source.next() % 4)
        current = variant
        previous = variant
        // Stagger the first updates so a short preview already feels alive.
        // Later holds are always longer and unrelated across signs.
        nextChange = source.value(in: 3...15)
        lightPeriod = source.value(in: 24...48)
        lightPhase = source.value(in: 0...(2 * .pi))
        random = source
    }

    func state(at time: Double) -> NeonBillboardState {
        let blend = transitionDuration > 0
            ? neonSmooth((time - transitionStart) / transitionDuration) : 1
        let brightness = 0.91 + 0.09 * neonWave(time: time, period: lightPeriod, phase: lightPhase)
        return NeonBillboardState(current: current, previous: previous,
                                  blend: blend, brightness: brightness)
    }

    mutating func advance(to time: Double, remainingChanges: inout Int) {
        while time >= nextChange, remainingChanges > 0 {
            previous = current
            // Pick one of the other three artworks, never the one just shown.
            current = (current + 1 + Int(random.next() % 3)) % 4
            transitionStart = nextChange
            transitionDuration = random.value(in: 2.5...5)
            nextChange = transitionStart + transitionDuration + random.value(in: 14...38)
            remainingChanges -= 1
        }
        if time >= nextChange {
            // Only enormous direct simulation jumps hit this branch. Keep the
            // latest settled artwork and resume a normal independent schedule.
            previous = current
            transitionStart = time
            transitionDuration = 0
            nextChange = time + random.value(in: 14...38)
        }
    }
}

private struct NeonRandom: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func value(in range: ClosedRange<Double>) -> Double {
        let unit = Double(next() >> 11) / 9_007_199_254_740_992
        return range.lowerBound + (range.upperBound - range.lowerBound) * unit
    }
}

private func neonSmooth(_ value: Double) -> Double {
    let clamped = min(1, max(0, value))
    return clamped * clamped * (3 - 2 * clamped)
}

private func neonWave(time: Double, period: Double, phase: Double) -> Double {
    // Reduce time before multiplying so even unusually large finite QA times
    // cannot overflow the analytic light curves.
    let angle = time.truncatingRemainder(dividingBy: period) * (2 * .pi / period) + phase
    return 0.5 + 0.5 * sin(angle)
}
