import Foundation

@main
enum TestHadalScene {
    static func main() {
        testInitialDelayAndAllSpecies()
        testAboveCityRoutes()
        testDefenceCausalityAndContinuity()
        testIndependentWindows()
        testFrameRatesAndDeterminism()
        testClockRecoveryAndHugeJumps()
        testThirtyMinutes()
        print("Hadal top-entry city routes, shuffled species, defence causality, light continuity, clock recovery and 30-minute simulation: OK")
    }

    private static func testInitialDelayAndAllSpecies() {
        var model = HadalSceneModel(seed: 2026)
        precondition(model.encounter == nil && model.flares.isEmpty && model.charges.isEmpty)
        model.step(seconds: 2.999)
        precondition(model.encounter == nil)
        model.step(seconds: 0.001)
        precondition(model.encounter != nil)
        precondition(HadalCreatureKind.allCases.count == 5)
        precondition(Set(HadalCreatureKind.allCases.map(\.assetName)).count == 5)
        precondition(Set(HadalCreatureKind.allCases.map(\.title)).count == 5)
        for kind in HadalCreatureKind.allCases {
            model.startEncounter(kind: kind)
            precondition(model.encounter?.kind == kind)
            precondition(model.encounter?.age == 0)
            precondition(model.encounter?.visibility == 0)
            precondition(model.encounter?.stage == .approaching)
            precondition(model.flares.isEmpty && model.charges.isEmpty)
        }
    }

    private static func testAboveCityRoutes() {
        near(HadalCityLayout.waterCeiling(atX: HadalCityLayout.domeCenterX),
             HadalCityLayout.domeBaseY - HadalCityLayout.domeRadiusY)
        near(HadalCityLayout.waterCeiling(atX: -0.2), HadalCityLayout.seabedY)
        near(HadalCityLayout.waterCeiling(atX: 1.2), HadalCityLayout.seabedY)
        near(HadalCityLayout.waterCeiling(atX: 0.2), HadalCityLayout.waterCeiling(atX: 0.8))
        near(HadalCityLayout.waterCeiling(atX: .nan), HadalCityLayout.seabedY)

        var sampleCount = 0
        var directions = Set<Int>()
        for seed in 0..<32 {
            for kind in HadalCreatureKind.allCases {
                var scene = HadalSceneModel(seed: UInt64(seed))
                scene.startEncounter(kind: kind)
                let initial = scene.encounter!
                precondition(initial.center.y <= -0.2, "\(kind) did not enter from above")
                directions.insert(initial.facing)
                var previous = initial
                var last = initial
                for _ in 0..<Int(ceil(initial.duration * 60)) {
                    scene.step(seconds: 1.0 / 60)
                    guard let event = scene.encounter else { break }
                    let ceiling = HadalCityLayout.waterCeiling(atX: event.center.x)
                    precondition(event.center.y <= ceiling - 0.04,
                                 "\(kind) entered the pressure dome for seed \(seed)")
                    precondition(event.center.y < HadalCityLayout.seabedY - 0.04,
                                 "\(kind) entered the seafloor for seed \(seed)")
                    if event.stage == .retreating && previous.stage == .retreating {
                        precondition(event.center.y <= previous.center.y + 0.0000001,
                                     "\(kind) retreated downward toward the city")
                    }
                    previous = event
                    last = event
                    sampleCount += 1
                }
                precondition(last.center.y <= -0.35, "\(kind) did not leave above the city")
            }
        }
        precondition(directions == [-1, 1])
        print("City route sample: \(sampleCount) positions, five species ×32 seeds, only top entry/exit")
    }

    private static func testDefenceCausalityAndContinuity() {
        for kind in HadalCreatureKind.allCases {
            var scene = HadalSceneModel(seed: 7)
            scene.startEncounter(kind: kind)
            let duration = scene.encounter!.duration
            precondition((56...64).contains(duration))
            scene.step(seconds: 11.999)
            precondition(scene.encounter?.stage == .approaching)
            precondition(scene.flares.isEmpty && scene.charges.isEmpty)
            scene.step(seconds: 0.001)
            precondition(scene.encounter?.stage == .illuminated)
            precondition(scene.flares.count == 1)
            precondition(scene.flares[0].strength < 0.000001)
            near(scene.flares[0].position.y, 0.43)
            scene.step(seconds: 3)
            precondition(scene.flares[0].strength > 0.999)
            precondition(scene.charges.isEmpty)
            scene.step(seconds: 3)
            precondition(scene.flares.count == 2)
            precondition(scene.flares[1].strength < 0.000001)
            scene.step(seconds: 4)
            let closest = scene.encounter!.center
            scene.step(seconds: 4)
            precondition(scene.encounter?.center == closest)
            precondition(scene.charges.count == 1)
            let launched = scene.charges[0]
            near(abs(launched.origin.x - 0.5), 0.18)
            near(launched.origin.y, 0.43)
            near(launched.progress, 0)
            near(launched.burst, 0)
            near(launched.position.x, launched.origin.x)
            near(launched.position.y, launched.origin.y)
            precondition(launched.target == closest)

            scene.step(seconds: 4.499)
            precondition(scene.encounter?.stage == .illuminated)
            precondition(scene.encounter?.center == closest, "Creature recoiled before impact")
            precondition(scene.charges[0].progress < 1 && scene.charges[0].burst == 0)
            scene.step(seconds: 0.001)
            precondition(scene.encounter?.stage == .repelled)
            near(scene.charges[0].progress, 1)
            near(scene.charges[0].position.x, launched.target.x)
            near(scene.charges[0].position.y, launched.target.y)
            precondition(scene.charges[0].burst < 0.000001, "Impact flashed on its first frame")
            scene.step(seconds: 1.1)
            precondition(scene.charges[0].burst > 0.999)
            precondition(distance(scene.encounter!.center, closest) > 0.001)
            scene.step(seconds: 3.9)
            precondition(scene.encounter?.stage == .retreating)
            precondition(scene.charges.isEmpty)
            near(scene.encounter!.center.x, closest.x)
            near(scene.encounter!.center.y, closest.y)
            scene.step(seconds: 10)
            precondition(scene.encounter?.stage == .retreating)
            precondition(scene.encounter!.scale < 0.85)
            precondition(distance(scene.encounter!.center, closest) > 0.10)
            scene.step(seconds: duration - 45.5 - 0.001)
            precondition(scene.encounter!.visibility < 0.000001)
            scene.step(seconds: 0.002)
            precondition(scene.encounter == nil)
            precondition(scene.flares.isEmpty && scene.charges.isEmpty)

            var smooth = HadalSceneModel(seed: 7)
            smooth.startEncounter(kind: kind)
            var last = smooth.encounter!
            var lastFlares: [Int: HadalFlare] = [:]
            var lastCharges: [Int: HadalCharge] = [:]
            for _ in 0..<Int(duration * 60) {
                smooth.step(seconds: 1.0 / 60)
                guard let current = smooth.encounter else { break }
                precondition(abs(current.visibility - last.visibility) < 0.005)
                precondition(abs(current.scale - last.scale) < 0.003)
                precondition(distance(current.center, last.center) < 0.004)
                precondition(distance(current.center, HadalPoint(x: 0.5, y: 0.53)) > 0.20)
                for flare in smooth.flares {
                    if let old = lastFlares[flare.id] {
                        precondition(abs(flare.strength - old.strength) < 0.015)
                        precondition(distance(flare.position, old.position) < 0.003)
                    } else {
                        precondition(flare.strength < 0.001)
                    }
                }
                for charge in smooth.charges {
                    if let old = lastCharges[charge.id] {
                        precondition(abs(charge.burst - old.burst) < 0.025)
                        precondition(distance(charge.position, old.position) < 0.005)
                    } else {
                        precondition(charge.progress < 0.005 && charge.burst == 0)
                    }
                }
                lastFlares = Dictionary(uniqueKeysWithValues: smooth.flares.map { ($0.id, $0) })
                lastCharges = Dictionary(uniqueKeysWithValues: smooth.charges.map { ($0.id, $0) })
                last = current
            }
        }
    }

    private static func testIndependentWindows() {
        var scene = HadalSceneModel(seed: 123)
        var previous = (0..<HadalSceneModel.windowCount).map { scene.windowLight(id: $0) }
        precondition(Set(previous).count == HadalSceneModel.windowCount)
        var changed = Set<Int>()
        var partiallyChangedFrames = 0
        for _ in 0..<12_000 {
            scene.step(seconds: 1.0 / 30)
            var moving = 0
            for index in 0..<HadalSceneModel.windowCount {
                let value = scene.windowLight(id: index)
                precondition((0.45...1).contains(value))
                precondition(abs(value - previous[index]) < 0.006)
                if abs(value - previous[index]) > 0.0000001 {
                    changed.insert(index)
                    moving += 1
                }
                previous[index] = value
            }
            if moving > 0 && moving < HadalSceneModel.windowCount { partiallyChangedFrames += 1 }
        }
        precondition(changed.count == HadalSceneModel.windowCount)
        precondition(partiallyChangedFrames > 1_000)
        for id in [Int.min, Int.max, -97, -1, 0, 13] {
            precondition((0.45...1).contains(scene.windowLight(id: id)))
        }
    }

    private static func testFrameRatesAndDeterminism() {
        var thirty = HadalSceneModel(seed: 2026)
        var sixty = HadalSceneModel(seed: 2026)
        thirty.advance(to: 0)
        sixty.advance(to: 0)
        for frame in 1...18_000 {
            thirty.advance(to: Double(frame) / 30)
            sixty.advance(to: Double(frame * 2 - 1) / 60)
            sixty.advance(to: Double(frame * 2) / 60)
            if frame % 137 == 0 {
                near(thirty.elapsed, sixty.elapsed)
                compare(thirty.encounter, sixty.encounter)
                precondition(thirty.flares.count == sixty.flares.count)
                for (a, b) in zip(thirty.flares, sixty.flares) {
                    near(a.position.x, b.position.x)
                    near(a.position.y, b.position.y)
                    near(a.strength, b.strength)
                }
                precondition(thirty.charges.count == sixty.charges.count)
                for (a, b) in zip(thirty.charges, sixty.charges) {
                    near(a.progress, b.progress)
                    near(a.burst, b.burst)
                }
                for index in 0..<HadalSceneModel.windowCount {
                    near(thirty.windowLight(id: index), sixty.windowLight(id: index))
                }
            }
        }
        var matching = HadalSceneModel(seed: 2026)
        var different = HadalSceneModel(seed: 2027)
        matching.step(seconds: 20)
        different.step(seconds: 20)
        precondition(matching.encounter != different.encounter)
    }

    private static func testClockRecoveryAndHugeJumps() {
        var scene = HadalSceneModel(seed: 9)
        scene.advance(to: 100)
        near(scene.elapsed, 0)
        scene.advance(to: 100.2)
        near(scene.elapsed, 0.2)
        scene.advance(to: 100.1)
        scene.advance(to: .nan)
        scene.advance(to: .infinity)
        near(scene.elapsed, 0.2)
        scene.advance(to: 1_000_000_000)
        near(scene.elapsed, 0.7)
        scene.advance(to: 1_000_000_000.1)
        near(scene.elapsed, 0.8, tolerance: 0.000001)
        scene.step(seconds: -1)
        scene.step(seconds: .nan)
        scene.step(seconds: .infinity)
        near(scene.elapsed, 0.8, tolerance: 0.000001)
        let started = ProcessInfo.processInfo.systemUptime
        scene.step(seconds: 1_000_000_000_000)
        precondition(ProcessInfo.processInfo.systemUptime - started < 1)
        checkBounds(scene)
        scene.step(seconds: .greatestFiniteMagnitude)
        checkBounds(scene)
        precondition(scene.elapsed.isFinite)
    }

    private static func testThirtyMinutes() {
        var scene = HadalSceneModel(seed: 2026)
        var previous: HadalEncounter?
        var encounters: [HadalCreatureKind] = []
        var stages = Set<HadalEncounterStage>()
        var sawFlare = false, sawFlight = false, sawBurst = false, sawIdle = false
        for _ in 0..<18_000 {
            scene.step(seconds: 0.1)
            checkBounds(scene)
            if let current = scene.encounter {
                if previous == nil || current.age < previous!.age {
                    encounters.append(current.kind)
                }
                stages.insert(current.stage)
            } else { sawIdle = true }
            sawFlare = sawFlare || scene.flares.contains { $0.strength > 0.8 }
            sawFlight = sawFlight || scene.charges.contains { $0.progress < 1 }
            sawBurst = sawBurst || scene.charges.contains { $0.burst > 0.8 }
            previous = scene.encounter
        }
        precondition(encounters.count >= 20)
        precondition(stages == Set(HadalEncounterStage.allCases))
        precondition(sawFlare && sawFlight && sawBurst && sawIdle)
        for start in stride(from: 0, through: encounters.count - 5, by: 5) {
            precondition(Set(encounters[start..<(start + 5)]) == Set(HadalCreatureKind.allCases),
                         "A shuffled bag missed a species")
        }
        for pair in zip(encounters, encounters.dropFirst()) { precondition(pair.0 != pair.1) }
        print("30-minute sample: \(encounters.count) encounters, all five species, flares, charge impacts and retreats")
    }

    private static func checkBounds(_ scene: HadalSceneModel) {
        precondition(scene.flares.count <= 2 && scene.charges.count <= 1)
        if let event = scene.encounter {
            precondition(event.age.isFinite && event.age >= 0 && event.age < event.duration)
            precondition(event.center.x.isFinite && event.center.y.isFinite)
            precondition(event.center.y <= HadalCityLayout.waterCeiling(atX: event.center.x) - 0.04)
            precondition(event.center.y < HadalCityLayout.seabedY - 0.04)
            precondition(event.facing == -1 || event.facing == 1)
            precondition((0.3...1.01).contains(event.scale))
            precondition((0...1).contains(event.visibility))
        }
        for flare in scene.flares {
            precondition((0...1).contains(flare.strength))
            precondition((0...1).contains(flare.position.x) && (0...1).contains(flare.position.y))
            precondition(flare.radius > 0 && flare.radius < 0.25 && flare.age >= 0)
        }
        for charge in scene.charges {
            precondition((0...1).contains(charge.progress) && (0...1).contains(charge.burst))
            precondition(charge.position.x.isFinite && charge.position.y.isFinite)
        }
        for index in 0..<HadalSceneModel.windowCount {
            precondition((0.45...1).contains(scene.windowLight(id: index)))
        }
    }

    private static func compare(_ a: HadalEncounter?, _ b: HadalEncounter?) {
        precondition((a == nil) == (b == nil))
        guard let a, let b else { return }
        precondition(a.kind == b.kind && a.stage == b.stage && a.facing == b.facing)
        near(a.age, b.age)
        near(a.duration, b.duration)
        near(a.center.x, b.center.x)
        near(a.center.y, b.center.y)
        near(a.scale, b.scale)
        near(a.visibility, b.visibility)
    }

    private static func distance(_ a: HadalPoint, _ b: HadalPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }

    private static func near(_ a: Double, _ b: Double, tolerance: Double = 0.0000001) {
        precondition(abs(a - b) <= tolerance, "\(a) differs from \(b)")
    }
}
