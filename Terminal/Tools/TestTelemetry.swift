import Foundation
import CoreGraphics

@main
enum TestTelemetry {
    static func main() {
        for seed in [UInt64(0), 1, 0xDEADBEEF, UInt64.max] {
            var model = TelemetryModel(seed: seed)
            model.advance(at: 0)
            let initial = (model.signalDivider, model.loadDivider)
            model.advance(at: 4.999)
            precondition(model.signalDivider == initial.0 && model.loadDivider == initial.1)

            model.advance(at: 5)
            precondition(model.signalDivider != initial.0 && model.loadDivider != initial.1)
            let first = (model.signalDivider, model.loadDivider)
            model.advance(at: 9.999)
            precondition(model.signalDivider == first.0 && model.loadDivider == first.1)

            for step in 2...25_000 {
                let before = (model.signalDivider, model.loadDivider)
                model.advance(at: Double(step) * 5)
                precondition((1..<TelemetryModel.blockCount).contains(model.signalDivider))
                precondition((1..<TelemetryModel.blockCount).contains(model.loadDivider))
                precondition(model.signalDivider != before.0)
                precondition(model.loadDivider != before.1)
            }

            let beforeSleep = (model.signalDivider, model.loadDivider)
            model.advance(at: 1_000_000)
            let afterSleep = (model.signalDivider, model.loadDivider)
            precondition(afterSleep.0 != beforeSleep.0 && afterSleep.1 != beforeSleep.1)
            model.advance(at: 1_000_001)
            precondition(model.signalDivider == afterSleep.0 && model.loadDivider == afterSleep.1)
        }

        for width in [CGFloat(200), 568, 1000] {
            let track = CGRect(x: 18, y: 0, width: width, height: 31)
            let gap: CGFloat = 4
            let blockWidth = (track.width - 31 * gap) / 32
            for divider in 1...31 {
                let marker = MeterGeometry.markerX(track: track, divider: divider, gap: gap)
                let leftGapEdge = track.minX + CGFloat(divider) * blockWidth
                    + CGFloat(divider - 1) * gap
                precondition(abs((marker - gap / 2) - leftGapEdge) < 0.0001)
                precondition(marker - gap / 2 > track.minX)
                precondition(marker + gap / 2 < track.maxX)
            }
            precondition(MeterGeometry.clampedDivider(-100) == 1)
            precondition(MeterGeometry.clampedDivider(100) == 31)
        }

        print("Telemetry interval, movement and divider bounds: OK")
    }
}
