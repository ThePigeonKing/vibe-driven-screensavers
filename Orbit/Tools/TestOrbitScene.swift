import Foundation

@main
enum TestOrbitScene {
    static func main() {
        testInitialTraffic()
        testSustainedTrafficAndContinuity()
        testFrameRates()
        testTimeRecovery()
        testManySeeds()
        print("Orbit docking schedules, sustained traffic, continuous phases, frame rates and sleep recovery: OK")
    }

    private static func testInitialTraffic() {
        let model = OrbitSceneModel(seed: 2026)
        precondition(model.elapsed == 0)
        precondition(model.ships.count == 1)
        precondition(model.ships[0].id == 0 && model.ships[0].phase == .approaching)
        precondition(model.ships[0].progress > 0)
        precondition(OrbitSceneModel.ports.count == 3)
    }

    private static func testSustainedTrafficAndContinuity() {
        var model = OrbitSceneModel(seed: 2026)
        var previous = [Int: OrbitShip]()
        var seen = [Set<OrbitShipPhase>](repeating: [], count: 3)
        var arrivals = 0
        var sawTwo = false
        let step = 1.0 / 60
        for _ in 0..<(30 * 60 * 60) {
            let ships = model.ships
            precondition(ships.count <= 3)
            if ships.count >= 2 { sawTwo = true }
            var current = [Int: OrbitShip]()
            for ship in ships {
                check(ship)
                precondition(current[ship.id] == nil)
                seen[ship.id].insert(ship.phase)
                if let before = previous[ship.id] {
                    precondition(distance(before.position, ship.position) < 0.004,
                                 "Ship jumps across a phase boundary")
                    let angular = abs(atan2(sin(ship.angle - before.angle), cos(ship.angle - before.angle)))
                    precondition(angular < 0.03, "Ship attitude snaps")
                    precondition(abs(ship.engine - before.engine) < 0.015)
                    if before.phase == ship.phase, ship.phase != .docked,
                       distance(before.position, ship.position) > 0.00000001 {
                        let velocityAngle = atan2((ship.position.y - before.position.y) * 1000,
                                                  (ship.position.x - before.position.x) * 1600)
                        let headingError = abs(atan2(sin(ship.angle - velocityAngle),
                                                     cos(ship.angle - velocityAngle)))
                        precondition(headingError < 0.05, "Ship nose does not follow its flight path")
                    }
                    if before.phase != .docked && ship.phase == .docked { arrivals += 1 }
                }
                if ship.phase == .docked {
                    precondition(ship.position == OrbitSceneModel.ports[ship.id])
                    precondition(ship.engine == 0)
                }
                current[ship.id] = ship
            }
            previous = current
            model.step(seconds: step)
        }
        precondition(seen.allSatisfy { $0 == Set(OrbitShipPhase.allCases) })
        precondition(arrivals >= 40 && arrivals <= 90)
        precondition(sawTwo)
        print("30-minute sample: \(arrivals) dockings, all three ports and flight phases, bounded three ships")
    }

    private static func testFrameRates() {
        var slow = OrbitSceneModel(seed: 42)
        var fast = slow
        for _ in 0..<10_800 { slow.step(seconds: 1.0 / 30) }
        for _ in 0..<21_600 { fast.step(seconds: 1.0 / 60) }
        precondition(abs(slow.elapsed - fast.elapsed) < 0.000001)
        precondition(slow.ships.count == fast.ships.count)
        for (a, b) in zip(slow.ships, fast.ships) {
            precondition(a.id == b.id && a.phase == b.phase)
            precondition(distance(a.position, b.position) < 0.000001)
            precondition(abs(a.angle - b.angle) < 0.000001)
        }
        precondition(abs(slow.stationAngle - fast.stationAngle) < 0.000001)
        precondition(abs(slow.ringPhase - fast.ringPhase) < 0.000001)
    }

    private static func testTimeRecovery() {
        var model = OrbitSceneModel(seed: 2026)
        model.advance(to: 100)
        model.advance(to: 100.25)
        precondition(model.elapsed == 0.25)
        model.advance(to: 20_000)
        precondition(model.elapsed == 0.75)
        model.advance(to: 99)
        model.advance(to: .nan)
        model.advance(to: .infinity)
        precondition(model.elapsed == 0.75)
        model.step(seconds: -1)
        model.step(seconds: .nan)
        model.step(seconds: .infinity)
        precondition(model.elapsed == 0.75)
        model.step(seconds: 1_000_000_000)
        precondition(model.ships.count <= 3)
        model.step(seconds: Double.greatestFiniteMagnitude / 8)
        precondition(model.elapsed.isFinite)
        precondition(model.stationAngle.isFinite && model.ringPhase.isFinite)
        for ship in model.ships { check(ship) }
        for id in [Int.min, -1, 0, Int.max] {
            precondition((0...1).contains(model.beaconStrength(id: id)))
        }
    }

    private static func testManySeeds() {
        var variedPositions = Set<String>()
        for seed in 0..<32 {
            var model = OrbitSceneModel(seed: UInt64(seed))
            for _ in 0..<300 {
                model.step(seconds: 0.25)
                for ship in model.ships { check(ship) }
                precondition(abs(model.stationAngle) <= 0.0251)
                precondition((0...1).contains(model.ringPhase))
            }
            if let ship = model.ships.first {
                variedPositions.insert(String(format: "%.5f,%.5f", ship.position.x, ship.position.y))
            }
        }
        precondition(variedPositions.count > 16)
    }

    private static func check(_ ship: OrbitShip) {
        precondition((0..<3).contains(ship.id))
        precondition((0...1).contains(ship.progress))
        precondition(ship.position.x.isFinite && ship.position.y.isFinite && ship.angle.isFinite)
        precondition((-0.2...1.2).contains(ship.position.x))
        precondition((-0.2...1.2).contains(ship.position.y))
        precondition((0...1).contains(ship.engine))
    }

    private static func distance(_ a: OrbitPoint, _ b: OrbitPoint) -> Double {
        hypot(a.x - b.x, a.y - b.y)
    }
}
