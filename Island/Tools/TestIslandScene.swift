import Foundation

@main
enum TestIslandScene {
    static func main() {
        for seed in 0..<64 { validate(IslandSceneModel(seed: UInt64(seed))) }
        var clock = IslandSceneModel(seed: 2026)
        clock.advance(to: 100)
        clock.advance(to: 100.25)
        precondition(clock.elapsed == 0.25)
        clock.advance(to: 50)
        clock.advance(to: .nan)
        clock.advance(to: .infinity)
        precondition(clock.elapsed == 0.25)
        clock.advance(to: 100_000)
        precondition(clock.elapsed == 0.75, "Sleep must not replay the missed day")
        var first = IslandSceneModel(seed: 2026)
        let originalCount = first.buildings.count
        precondition(first.project == nil)
        first.step(seconds: 14)
        precondition(abs(first.project!.progress - 0.5) < 0.0001)
        first.step(seconds: 12)
        precondition(first.buildings.count == originalCount + 1)
        precondition(first.completedConstructions == 1)

        var thirty = IslandSceneModel(seed: 42), sixty = IslandSceneModel(seed: 42)
        for _ in 0..<18_000 {
            thirty.step(seconds: 1.0 / 30)
            sixty.step(seconds: 1.0 / 60); sixty.step(seconds: 1.0 / 60)
        }
        precondition(thirty.buildings == sixty.buildings)
        precondition(thirty.revision == sixty.revision)
        precondition(thirty.project?.building == sixty.project?.building)
        precondition(abs((thirty.project?.progress ?? 0) - (sixty.project?.progress ?? 0)) < 0.00001)

        var town = IslandSceneModel(seed: 2026)
        let monuments = town.buildings.filter(\.permanent)
        let initial = town.buildings
        for index in 0..<7_200 {
            town.step(seconds: 0.25)
            if index % 4 == 0 { validate(town) }
        }
        precondition(town.completedConstructions > 15 && town.completedDismantlings > 10)
        precondition(town.buildings != initial)
        precondition(town.buildings.filter(\.permanent) == monuments)
        precondition(town.revision == UInt64(town.completedConstructions + town.completedDismantlings))
        print("30-minute sample: \(town.completedConstructions) constructions, \(town.completedDismantlings) careful dismantlings; \(town.buildings.count)/\(town.plots.count) occupied plots")
        town.step(seconds: 1_000_000_000)
        validate(town)
        town.step(seconds: .greatestFiniteMagnitude)
        town.step(seconds: .infinity)
        precondition(town.elapsed.isFinite)
        print("Connected roads and pier, terrain support, bounded construction cycles, varied architecture and clock recovery: OK")
    }

    private static func validate(_ town: IslandSceneModel) {
        let allCells = town.tiles.map(\.cell)
        precondition(Set(allCells).count == allCells.count)
        let walkable = Set(town.tiles.filter(\.isWalkable).map(\.cell))
        var reached: Set<IslandCell> = []
        var queue = [walkable.first!]
        var offset = 0
        while offset < queue.count {
            let cell = queue[offset]; offset += 1
            guard reached.insert(cell).inserted else { continue }
            for next in cell.neighbours where walkable.contains(next) { queue.append(next) }
        }
        precondition(reached == walkable, "Roads or harbour pier disconnected")
        precondition(town.buildings.count <= town.plots.count)
        precondition(Set(town.buildings.map(\.cell)).count == town.buildings.count)
        precondition(Set(town.buildings.map(\.id)).count == town.buildings.count)
        for tile in town.tiles {
            precondition((0...14).contains(tile.cell.x) && (0...12).contains(tile.cell.y))
            precondition((0...3).contains(tile.level))
            for next in tile.cell.neighbours {
                if let neighbour = town.tile(at: next) {
                    precondition(abs(tile.level - neighbour.level) <= 1)
                }
            }
        }
        for building in town.buildings {
            precondition(town.plots.contains(building.cell))
            precondition(town.tile(at: building.cell)?.ground == .grass)
            precondition(building.cell.neighbours.contains { walkable.contains($0) })
            precondition((1...4).contains(building.floors))
        }
        if let project = town.project {
            precondition((0...1).contains(project.progress))
            precondition((0...1).contains(project.visibleFraction))
            precondition(!project.building.permanent)
            precondition(town.plots.contains(project.building.cell))
            precondition(project.dismantling == town.buildings.contains { $0.id == project.building.id })
        }
    }
}
