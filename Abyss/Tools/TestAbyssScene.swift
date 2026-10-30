import Foundation

@main
enum TestAbyssScene {
    static func main() {
        testFirstEncounter()
        testDeterminismAndThirtyMinutes()
        testIndependentWindows()
        testFrameRateIndependence()
        testClockAndPauses()
        testHugeJumpsAndIdentifiers()
        print("Abyss encounters, independent station lights, smooth fades, clock recovery and 30-minute simulation: OK")
    }

    private static func testFirstEncounter() {
        for seed in [UInt64(0), 1, 7, 2026, UInt64.max] {
            var model = AbyssSceneModel(seed: seed)
            model.step(seconds: 4.999)
            precondition(model.encounter == nil)
            precondition(model.encounterVisibility == 0)
            model.step(seconds: 0.001)
            precondition(model.encounter?.kind == .elder)
            precondition(model.encounterVisibility < 0.001)
            model.step(seconds: 7)
            precondition(model.encounterVisibility > 0.7)
            precondition(model.encounter?.progress ?? 1 < 0.15)
        }
    }

    private static func testDeterminismAndThirtyMinutes() {
        var model = AbyssSceneModel(seed: 2026)
        var matching = AbyssSceneModel(seed: 2026)
        let other = AbyssSceneModel(seed: 2027)
        precondition(snapshot(model) != snapshot(other))
        var kinds = Set<String>()
        var directions = Set<Int>()
        var appearances = 0
        var previouslyPresent = false
        var previousProgress = 0.0
        var previousVisibility = 0.0
        var previousWindows = (0..<AbyssSceneModel.windowCount).map { model.windowLight(id: $0) }
        for _ in 0..<54_000 {
            model.step(seconds: 1.0 / 30)
            matching.step(seconds: 1.0 / 30)
            precondition(snapshot(model) == snapshot(matching), "Matching seeds diverged")
            validate(model)
            if let encounter = model.encounter {
                if !previouslyPresent { appearances += 1 }
                kinds.insert(encounter.kind == .elder ? "elder" : "leviathan")
                directions.insert(encounter.direction)
                if previouslyPresent {
                    precondition(encounter.progress >= previousProgress)
                    precondition(encounter.progress - previousProgress < 0.001)
                }
                previousProgress = encounter.progress
            }
            precondition(abs(model.encounterVisibility - previousVisibility) < 0.006,
                         "Creature visibility changed abruptly")
            let windows = (0..<AbyssSceneModel.windowCount).map { model.windowLight(id: $0) }
            for index in windows.indices {
                precondition(abs(windows[index] - previousWindows[index]) < 0.006,
                             "A station window flashed")
            }
            previousVisibility = model.encounterVisibility
            previousWindows = windows
            previouslyPresent = model.encounter != nil
        }
        precondition(kinds.count == 2 && directions.count == 2)
        precondition((10...18).contains(appearances))
        print("30-minute sample: \(appearances) slow encounters, both creature kinds and travel directions")
    }

    private static func testIndependentWindows() {
        var model = AbyssSceneModel(seed: 27)
        let initial = (0..<AbyssSceneModel.windowCount).map { model.windowLight(id: $0) }
        precondition(Set(initial).count > 8)
        var changed = Set<Int>()
        var independentSteps = 0
        var previous = initial
        for _ in 0..<12_000 {
            model.step(seconds: 0.1)
            let current = (0..<AbyssSceneModel.windowCount).map { model.windowLight(id: $0) }
            let count = current.indices.filter { abs(current[$0] - previous[$0]) > 0.00001 }.count
            if count > 0 && count < AbyssSceneModel.windowCount { independentSteps += 1 }
            for index in current.indices where current[index] != initial[index] { changed.insert(index) }
            previous = current
        }
        precondition(changed.count == AbyssSceneModel.windowCount)
        precondition(independentSteps > 500)
    }

    private static func testFrameRateIndependence() {
        var thirty = AbyssSceneModel(seed: 7)
        var sixty = AbyssSceneModel(seed: 7)
        thirty.advance(to: 100)
        sixty.advance(to: 100)
        for frame in 1...18_000 {
            thirty.advance(to: 100 + Double(frame) / 30)
            sixty.advance(to: 100 + Double(frame * 2 - 1) / 60)
            sixty.advance(to: 100 + Double(frame * 2) / 60)
            for (first, second) in zip(snapshot(thirty), snapshot(sixty)) {
                precondition(abs(first - second) < 0.000001, "Frame-rate dependent schedule")
            }
        }
    }

    private static func testClockAndPauses() {
        var model = AbyssSceneModel(seed: 8)
        model.advance(to: .nan)
        model.advance(to: .infinity)
        model.advance(to: 100)
        precondition(model.elapsed == 0)
        model.advance(to: 100.25)
        precondition(model.elapsed == 0.25)
        model.advance(to: 99)
        model.advance(to: -.infinity)
        precondition(model.elapsed == 0.25)
        model.advance(to: 100.5)
        precondition(model.elapsed == 0.5)
        model.advance(to: 1_000_000)
        precondition(model.elapsed == 1, "A long pause replayed missed time")
        model.advance(to: 1_000_000.125)
        precondition(model.elapsed == 1.125)
        validate(model)
    }

    private static func testHugeJumpsAndIdentifiers() {
        var model = AbyssSceneModel(seed: UInt64.max)
        for value in [0.0, -1, Double.nan, .infinity, -.infinity] { model.step(seconds: value) }
        precondition(model.elapsed == 0)
        model.step(seconds: 100_000_000)
        precondition(model.elapsed == 100_000_000)
        validate(model)
        model.step(seconds: Double.greatestFiniteMagnitude / 2)
        validate(model)
        let before = model.elapsed
        model.step(seconds: Double.greatestFiniteMagnitude)
        precondition(model.elapsed == before, "Overflowing elapsed time was accepted")
        for id in [Int.min, -1000, -1, 0, 1, 1000, Int.max] {
            precondition((0.45...1).contains(model.windowLight(id: id)))
            precondition((0.3...1).contains(model.ventStrength(id: id)))
        }
    }

    private static func validate(_ model: AbyssSceneModel) {
        precondition(model.elapsed.isFinite && model.elapsed >= 0)
        precondition((0...1).contains(model.encounterVisibility))
        precondition((0...1).contains(model.beamPhase))
        if let encounter = model.encounter {
            precondition((0...1).contains(encounter.progress))
            precondition((0...1).contains(encounter.variation))
            precondition(encounter.direction == 1 || encounter.direction == -1)
        } else {
            precondition(model.encounterVisibility == 0)
        }
        for id in 0..<AbyssSceneModel.windowCount {
            precondition((0.45...1).contains(model.windowLight(id: id)))
            precondition((0.3...1).contains(model.ventStrength(id: id)))
        }
    }

    private static func snapshot(_ model: AbyssSceneModel) -> [Double] {
        var values = [model.elapsed, model.encounterVisibility, model.beamPhase]
        if let encounter = model.encounter {
            values += [encounter.kind == .elder ? 1 : 2, encounter.progress,
                       Double(encounter.direction), encounter.variation]
        } else {
            values += [0, 0, 0, 0]
        }
        values += (0..<AbyssSceneModel.windowCount).map { model.windowLight(id: $0) }
        values += (0..<3).map { model.ventStrength(id: $0) }
        return values
    }
}
