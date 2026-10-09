import Foundation
import CoreGraphics

/// A bounded, discrete random walk for the two auxiliary gauges.
/// Positions 1...31 refer to the gaps between 32 drawn blocks.
struct TelemetryModel {
    static let blockCount = 32
    static let updateInterval: TimeInterval = 5

    private(set) var signalDivider = 18
    private(set) var loadDivider = 12
    private var previousSignal: Int?
    private var previousLoad: Int?
    private var signalDirection = 1
    private var loadDirection = -1
    private var lastUpdate: TimeInterval?
    private var randomState: UInt64

    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) {
        randomState = seed
    }

    mutating func advance(at uptime: TimeInterval) {
        guard let lastUpdate else {
            self.lastUpdate = uptime
            return
        }
        if uptime < lastUpdate {
            self.lastUpdate = uptime
            return
        }
        guard uptime - lastUpdate >= Self.updateInterval else { return }

        // One update after waking from sleep; never replay a backlog of jumps.
        self.lastUpdate = uptime
        let signal = nextDivider(current: signalDivider, previous: previousSignal,
                                 direction: signalDirection)
        let load = nextDivider(current: loadDivider, previous: previousLoad,
                               direction: loadDirection)
        previousSignal = signalDivider
        previousLoad = loadDivider
        signalDivider = signal.index
        loadDivider = load.index
        signalDirection = signal.direction
        loadDirection = load.direction
    }

    private mutating func nextDivider(current: Int, previous: Int?,
                                      direction: Int) -> (index: Int, direction: Int) {
        let reverse = nextRandom() % 100 < 32
        var heading = reverse ? -direction : direction
        let longJump = nextRandom() % 11 == 0
        let distance = longJump ? 5 + Int(nextRandom() % 5) : 1 + Int(nextRandom() % 4)
        var candidate = current + heading * distance

        if !(1..<Self.blockCount).contains(candidate) {
            heading = -heading
            candidate = current + heading * distance
        }

        if candidate == previous {
            let nearby = (1..<Self.blockCount).filter {
                $0 != current && $0 != previous && abs($0 - current) <= 8
            }
            candidate = nearby[Int(nextRandom() % UInt64(nearby.count))]
        }

        return (candidate, candidate > current ? 1 : -1)
    }

    private mutating func nextRandom() -> UInt64 {
        // SplitMix64: a small reproducible generator with well-mixed steps.
        randomState &+= 0x9E3779B97F4A7C15
        var value = randomState
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

enum MeterGeometry {
    static func clampedDivider(_ divider: Int) -> Int {
        min(max(divider, 1), TelemetryModel.blockCount - 1)
    }

    static func markerX(track: CGRect, divider: Int, gap: CGFloat) -> CGFloat {
        let safeDivider = clampedDivider(divider)
        let count = TelemetryModel.blockCount
        let blockWidth = (track.width - CGFloat(count - 1) * gap) / CGFloat(count)
        return track.minX + CGFloat(safeDivider) * blockWidth
            + (CGFloat(safeDivider) - 0.5) * gap
    }
}
