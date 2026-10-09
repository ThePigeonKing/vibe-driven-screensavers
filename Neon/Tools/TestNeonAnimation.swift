import Foundation

@main
enum TestNeonAnimation {
    static func main() {
        testDeterminismAndThirtyMinutes()
        testClockAndSleep()
        testSignHoldsAndCrossfades()
        testTrainFrameProgressAndSleep()
        print("Neon signs, car lighting, exhaust, metro traffic, clock recovery and 30-minute simulation: OK")
    }

    private static func testDeterminismAndThirtyMinutes() {
        var scene = NeonAnimationModel(seed: 2026)
        var matching = NeonAnimationModel(seed: 2026)
        let other = NeonAnimationModel(seed: 2027)
        precondition(snapshot(scene) == snapshot(matching))
        precondition(snapshot(scene) != snapshot(other), "Different seeds produced the same scene")
        var previous = scene
        var changedSigns = Set<Int>()
        var variants = [Set<Int>](repeating: [], count: NeonAnimationModel.billboardCount)
        var independentUpdates = 0
        var trainDirections = Set<Int>()
        var trainCarCounts = Set<Int>()
        var trainDepartures = 0
        var passageStart: Double?
        var passageEnd: Double?
        for _ in 0..<18_000 {
            scene.step(seconds: 0.1)
            matching.step(seconds: 0.1)
            checkState(scene)
            precondition(snapshot(scene) == snapshot(matching), "Seeded animation was not deterministic")
            precondition(abs(scene.carLight - previous.carLight) < 0.024,
                         "Headlights flashed abruptly")
            precondition(abs(scene.underglow - previous.underglow) < 0.009,
                         "Underglow flashed abruptly")
            precondition(abs(scene.exhaust - previous.exhaust) < 0.018,
                         "Exhaust intensity changed abruptly")
            var updated = 0
            for id in 0..<NeonAnimationModel.billboardCount {
                let old = previous.billboard(id: id)
                let current = scene.billboard(id: id)
                variants[id].insert(current.current)
                if current.current != old.current {
                    changedSigns.insert(id)
                    updated += 1
                    precondition(current.previous == old.current)
                    precondition(current.current != current.previous)
                }
                // Verify the visible mixture rather than the blend counter,
                // which intentionally wraps from 1 to 0 when a fade begins.
                let oldWeights = weights(old)
                let newWeights = weights(current)
                for index in oldWeights.indices {
                    precondition(abs(newWeights[index] - oldWeights[index]) < 0.061,
                                 "Billboard artwork changed without a soft crossfade")
                }
                precondition(abs(current.brightness - old.brightness) < 0.001_3)
            }
            if updated == 1 { independentUpdates += 1 }
            if let train = scene.train {
                trainDirections.insert(train.direction)
                trainCarCounts.insert(train.carCount)
                if let old = previous.train {
                    precondition(train.direction == old.direction && train.carCount == old.carCount,
                                 "Train composition or direction changed during a passage")
                    precondition((0.009_9...0.014_4).contains(train.progress - old.progress),
                                 "Train motion did not advance smoothly through a 7...10-second passage")
                } else {
                    if let end = passageEnd {
                        precondition((34.8...65.2).contains(scene.time - end),
                                     "Metro traffic did not leave a 35...65-second gap")
                    } else {
                        precondition((5.99...6.11).contains(scene.time),
                                     "First metro passage did not begin at six seconds")
                    }
                    passageStart = scene.time
                    trainDepartures += 1
                    precondition(train.progress < 0.015, "Train entered partway through its passage")
                }
            } else if let old = previous.train, let start = passageStart {
                precondition((6.8...10.2).contains(scene.time - start),
                             "Metro passage outside its 7...10-second duration")
                precondition(old.progress > 0.985, "Train disappeared before completing its passage")
                passageEnd = scene.time
            }
            previous = scene
        }
        precondition(changedSigns.count == NeonAnimationModel.billboardCount)
        precondition(variants.allSatisfy { $0 == [0, 1, 2, 3] }, "A billboard never showed all variants")
        precondition(independentUpdates > 200, "Billboards shared a synchronized schedule")
        precondition((24...43).contains(trainDepartures), "Metro passages were missing or too frequent")
        precondition(trainDirections == [-1, 1], "Metro traffic never used both directions")
        precondition(trainCarCounts == [3, 4], "Metro traffic never varied its carriage count")
        precondition(abs(scene.time - 1_800) < 0.000_001)
        print("30-minute sample: five independent signs, four artworks each, \(trainDepartures) metro passages in both directions")
    }

    private static func testClockAndSleep() {
        var scene = NeonAnimationModel(seed: 9)
        scene.advance(to: 10_000)
        precondition(scene.time == 0)
        scene.advance(to: 10_000.2)
        precondition(abs(scene.time - 0.2) < 0.000_001)
        scene.advance(to: 9_000)
        precondition(abs(scene.time - 0.2) < 0.000_001)
        scene.advance(to: 10_000.4)
        precondition(abs(scene.time - 0.4) < 0.000_001)
        scene.advance(to: 1_000_000)
        precondition(abs(scene.time - 0.9) < 0.000_001,
                     "Resume replayed events accumulated during sleep")
        scene.advance(to: 1_000_000.1)
        precondition(abs(scene.time - 1) < 0.000_001)
        let before = snapshot(scene)
        scene.advance(to: .nan)
        scene.advance(to: .infinity)
        scene.step(seconds: .nan)
        scene.step(seconds: .infinity)
        scene.step(seconds: -1)
        scene.step(seconds: 0)
        precondition(snapshot(scene) == before)
        scene.step(seconds: 1_000_000_000)
        checkState(scene)
        scene.step(seconds: 0.1)
        checkState(scene)
        scene.step(seconds: Double.greatestFiniteMagnitude / 2)
        checkState(scene)
        scene.step(seconds: Double.greatestFiniteMagnitude)
        checkState(scene)
        precondition(scene.billboard(id: -1) == scene.billboard(id: 4))
        checkState(scene, ids: [Int.min, Int.max])
    }

    private static func testSignHoldsAndCrossfades() {
        var scene = NeonAnimationModel(seed: 0xC0_2026)
        var previous = (0..<NeonAnimationModel.billboardCount).map { scene.billboard(id: $0) }
        var starts: [Double?] = Array(repeating: nil, count: NeonAnimationModel.billboardCount)
        var settled: [Double?] = Array(repeating: nil, count: NeonAnimationModel.billboardCount)
        var changeCounts = Array(repeating: 0, count: NeonAnimationModel.billboardCount)
        for _ in 0..<6_000 {
            scene.step(seconds: 0.05)
            for id in 0..<NeonAnimationModel.billboardCount {
                let sign = scene.billboard(id: id)
                let old = previous[id]
                if sign.current != old.current {
                    if let end = settled[id] {
                        precondition((13.9...38.1).contains(scene.time - end),
                                     "Billboard hold outside its calm 14...38-second interval")
                    } else {
                        precondition((2.95...15.05).contains(scene.time),
                                     "First billboard update was not staggered through the preview")
                    }
                    starts[id] = scene.time
                    changeCounts[id] += 1
                }
                if sign.blend == 1 && old.blend < 1, let start = starts[id] {
                    precondition((2.4...5.1).contains(scene.time - start),
                                 "Billboard crossfade outside 2.5...5 seconds")
                    settled[id] = scene.time
                }
                previous[id] = sign
            }
        }
        precondition(changeCounts.allSatisfy { (7...19).contains($0) },
                     "Billboard activity was missing or too frequent")
        precondition(Set(changeCounts).count > 1, "Independent signs produced identical update counts")
    }

    private static func testTrainFrameProgressAndSleep() {
        var slow = NeonAnimationModel(seed: 43)
        var fast = NeonAnimationModel(seed: 43)
        slow.step(seconds: 6.25)
        fast.step(seconds: 6.25)
        for _ in 0..<60 {
            slow.step(seconds: 1 / 30.0)
            fast.step(seconds: 1 / 60.0)
            fast.step(seconds: 1 / 60.0)
        }
        guard let slowTrain = slow.train, let fastTrain = fast.train else {
            preconditionFailure("Train missing during frame-rate comparison")
        }
        precondition(abs(slowTrain.progress - fastTrain.progress) < 0.000_001,
                     "Train speed depended on the animation frame rate")
        precondition(slowTrain.direction == fastTrain.direction && slowTrain.carCount == fastTrain.carCount)

        slow.advance(to: 10_000)
        let beforeSleep = slow.train!
        slow.advance(to: 1_000_000)
        let afterSleep = slow.train!
        precondition(beforeSleep.direction == afterSleep.direction && beforeSleep.carCount == afterSleep.carCount)
        precondition((0.049...0.072).contains(afterSleep.progress - beforeSleep.progress),
                     "Resume replayed metro passages accumulated during sleep")
        slow.step(seconds: 1_000_000_000)
        precondition(slow.train == nil, "Huge simulation jump replayed overdue metro traffic")
        checkState(slow)
        slow.step(seconds: Double.greatestFiniteMagnitude / 2)
        checkState(slow)
        slow.step(seconds: Double.greatestFiniteMagnitude / 2)
        checkState(slow)
        precondition(slow.train == nil)
    }

    private static func checkState(_ scene: NeonAnimationModel,
                                   ids: [Int] = Array(0..<NeonAnimationModel.billboardCount)) {
        precondition(scene.time.isFinite && scene.time >= 0)
        precondition(scene.carLight.isFinite && (0.55...1).contains(scene.carLight))
        precondition(scene.underglow.isFinite && (0.58...0.92).contains(scene.underglow))
        precondition(scene.exhaust.isFinite && (0.4...0.9).contains(scene.exhaust))
        if let train = scene.train {
            precondition(train.progress.isFinite && (0...1).contains(train.progress))
            precondition(train.direction == -1 || train.direction == 1)
            precondition(train.carCount == 3 || train.carCount == 4)
        }
        for id in ids {
            let sign = scene.billboard(id: id)
            precondition((0...3).contains(sign.current) && (0...3).contains(sign.previous))
            precondition(sign.blend.isFinite && (0...1).contains(sign.blend))
            precondition(sign.brightness.isFinite && (0.91...1).contains(sign.brightness))
        }
    }

    private static func weights(_ sign: NeonBillboardState) -> [Double] {
        var values = [Double](repeating: 0, count: 4)
        values[sign.previous] += (1 - sign.blend) * sign.brightness
        values[sign.current] += sign.blend * sign.brightness
        return values
    }

    private static func snapshot(_ scene: NeonAnimationModel) -> [Double] {
        let train = scene.train
        let traffic = [train?.progress ?? -1, Double(train?.direction ?? 0), Double(train?.carCount ?? 0)]
        return [scene.time, scene.carLight, scene.underglow, scene.exhaust] + traffic
            + (0..<NeonAnimationModel.billboardCount).flatMap { id in
                let sign = scene.billboard(id: id)
                return [Double(sign.current), Double(sign.previous), sign.blend, sign.brightness]
            }
    }
}
