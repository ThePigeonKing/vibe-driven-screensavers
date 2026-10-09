import Foundation

@main
enum TestMazeGame {
    static func main() {
        testGeneratedMazes()
        testGhostPersonalities()
        testGhostModes()
        testElapsedTime()
        testOutcomeIntermissions()
        testTimedRestartsAndMazeVariety()
        testRoundCompletion()
        testOutcomeBalance()
        testLongPlay()
        print("Connected random mazes, ghost rules, timed game outcomes, autonomous play and sustained play: OK")
    }

    private static func testGeneratedMazes() {
        for seed in 0..<128 {
            let game = MazeGame(seed: UInt64(seed))
            checkBoard(game)
            let reachable = floodFill(game, from: game.player.tile)
            var floorCount = 0
            for y in 0..<MazeGame.height {
                for x in 0..<MazeGame.width {
                    let tile = GridPoint(x: x, y: y)
                    if !game.isWall(x: x, y: y) {
                        floorCount += 1
                        precondition(reachable.contains(tile), "Disconnected maze for seed \(seed)")
                    }
                }
            }
            precondition(floorCount > 250 && floorCount < 350)
            precondition(game.powerPellets.count == 4)
            precondition(game.sentries.count == 4)
            precondition(game.pellets.isDisjoint(with: game.powerPellets))
            for tile in game.pellets.union(game.powerPellets) {
                precondition(reachable.contains(tile))
            }
        }
    }

    private static func testGhostPersonalities() {
        let player = GridPoint(x: 10, y: 10)
        let red = GridPoint(x: 2, y: 4)
        let far = GridPoint(x: 20, y: 15)
        let near = GridPoint(x: 12, y: 11)
        precondition(MazeGhostKind.red.chaseTarget(player: player, heading: .right,
                                                   red: red, own: far) == player)
        precondition(MazeGhostKind.pink.chaseTarget(player: player, heading: .right,
                                                    red: red, own: far) == GridPoint(x: 14, y: 10))
        precondition(MazeGhostKind.pink.chaseTarget(player: player, heading: .up,
                                                    red: red, own: far) == GridPoint(x: 10, y: 6))
        precondition(MazeGhostKind.cyan.chaseTarget(player: player, heading: .right,
                                                    red: red, own: far) == GridPoint(x: 22, y: 16))
        precondition(MazeGhostKind.orange.chaseTarget(player: player, heading: .right,
                                                      red: red, own: far) == player)
        precondition(MazeGhostKind.orange.chaseTarget(player: player, heading: .right,
                                                      red: red, own: near) == MazeGhostKind.orange.scatterTarget)
        precondition(Set(MazeGhostKind.allCases.map(\.scatterTarget)).count == 4)
    }

    private static func testGhostModes() {
        var game = MazeGame(seed: 0xA11CE, sentryCount: 0)
        precondition(game.ghostMode == .scatter)
        var unpoweredTurns = 0
        var sawFrightened = false
        var sawChase = false
        for _ in 0..<700 {
            let originalRound = game.round
            game.step()
            precondition(game.round == originalRound, "First round ended before testing ghost modes")
            if game.ghostMode == .frightened {
                precondition(game.powerTicks > 0)
                sawFrightened = true
                continue
            }
            unpoweredTurns += 1
            if unpoweredTurns < 39 {
                precondition(game.ghostMode == .scatter, "Scatter clock advanced during frightened mode")
            } else if unpoweredTurns < 150 {
                precondition(game.ghostMode == .chase)
                sawChase = true
            } else {
                precondition(game.ghostMode == .scatter)
                break
            }
        }
        precondition(sawFrightened, "Player never triggered frightened mode")
        precondition(sawChase, "Chase mode never started")
        precondition(unpoweredTurns >= 150, "Scatter/chase timer did not progress")
    }

    private static func testElapsedTime() {
        let defaultDuration = Double(MazeGame.maxGameTicks) * MazeGame.stepInterval
        precondition((199...200).contains(defaultDuration))
        var game = MazeGame(seed: 2026)
        let initial = game.player.tile
        game.advance(to: 0)
        game.advance(to: MazeGame.stepInterval * 0.9)
        precondition(game.player.tile == initial)
        game.advance(to: MazeGame.stepInterval * 1.01)
        precondition(game.player.tile != initial)
        precondition((0...1).contains(game.interpolation))
        game.advance(to: 1_000_000)
        precondition((0...1).contains(game.interpolation))
        precondition(game.round >= 1 && game.lives >= 1)
        checkBoard(game)

        var timed = MazeGame(seed: 2027, sentryCount: 0, timeLimitTicks: 1)
        timed.advance(to: 0)
        timed.advance(to: 1)
        precondition(timed.phase == .gameOver)
        precondition(timed.intermissionTicksRemaining == MazeGame.intermissionDurationTicks)
        // A long pause must not skip the result screen or replay hours of turns.
        timed.advance(to: 1_000_001)
        precondition(timed.phase == .gameOver)
        precondition(timed.intermissionTicksRemaining >= MazeGame.intermissionDurationTicks - 4)
    }

    private static func testRoundCompletion() {
        var game = MazeGame(seed: 0xC0FFEE, sentryCount: 0)
        var turns = 0
        while game.clears < 2 && turns < 5_000 {
            game.step()
            turns += 1
            if turns % 101 == 0 { checkBoard(game) }
        }
        precondition(game.clears >= 2, "Autonomous player failed to clear the maze")
        precondition(game.lives >= 3)
        checkBoard(game)
    }

    private static func testOutcomeIntermissions() {
        var game = MazeGame(seed: 0xC0FFEE, sentryCount: 0)
        var turns = 0
        while game.phase == .playing && turns < MazeGame.maxGameTicks {
            game.step()
            turns += 1
        }
        precondition(game.phase == .won, "No-ghost game did not reach victory")
        precondition(game.wins == 1 && game.losses == 0 && game.clears == 1)
        precondition(game.remainingNodes == 0)
        precondition(game.intermissionTicksRemaining == MazeGame.intermissionDurationTicks)
        let finishedMap = wallFingerprint(game)
        let finalScore = game.score
        let finalPlayer = game.player.tile
        let finalRound = game.round
        for remaining in stride(from: MazeGame.intermissionDurationTicks - 1,
                                through: 1, by: -1) {
            game.step()
            precondition(game.phase == .won && game.intermissionTicksRemaining == remaining)
            precondition(game.round == finalRound && game.score == finalScore)
            precondition(game.player.tile == finalPlayer && wallFingerprint(game) == finishedMap)
        }
        game.step()
        precondition(game.phase == .playing && game.round == finalRound + 1)
        precondition(game.intermissionTicksRemaining == 0 && game.elapsedGameTicks == 0)
        precondition(game.score == 0 && game.lives == 3)
        precondition(wallFingerprint(game) != finishedMap)
        checkBoard(game)
    }

    private static func testTimedRestartsAndMazeVariety() {
        var game = MazeGame(seed: 0xBEEF, sentryCount: 0, timeLimitTicks: 4)
        var fingerprints: Set<[Bool]> = []
        for expectedRound in 1...128 {
            precondition(game.round == expectedRound && game.phase == .playing)
            checkBoard(game)
            let map = wallFingerprint(game)
            precondition(fingerprints.insert(map).inserted, "Generated maze repeated")
            let reachable = floodFill(game, from: game.player.tile)
            for y in 0..<MazeGame.height {
                for x in 0..<MazeGame.width where !game.isWall(x: x, y: y) {
                    precondition(reachable.contains(GridPoint(x: x, y: y)),
                                 "Disconnected regenerated maze")
                }
            }
            for _ in 0..<4 { game.step() }
            precondition(game.phase == .gameOver)
            precondition(game.elapsedGameTicks == 4 && game.remainingTimeSeconds == 0)
            precondition(game.losses == expectedRound && game.wins == 0)
            let finishedPlayer = game.player.tile
            let finishedScore = game.score
            for _ in 1..<MazeGame.intermissionDurationTicks {
                game.step()
                precondition(game.phase == .gameOver && game.round == expectedRound)
                precondition(game.player.tile == finishedPlayer && game.score == finishedScore)
                precondition(wallFingerprint(game) == map)
            }
            game.step()
            precondition(game.phase == .playing && game.round == expectedRound + 1)
            precondition(game.lives == 3 && game.score == 0)
        }
    }

    private static func testOutcomeBalance() {
        let sampleSize = 200
        var wins = 0
        var losses = 0
        var timedOut = 0
        for seed in 0..<sampleSize {
            var game = MazeGame(seed: UInt64(seed))
            while game.phase == .playing { game.step() }
            if game.phase == .won {
                wins += 1
            } else {
                losses += 1
                if game.remainingTimeSeconds == 0 { timedOut += 1 }
            }
        }
        print("Independent games: \(wins) wins / \(losses) losses, \(timedOut) timeouts")
        precondition((50...90).contains(wins),
                     "Win rate should be roughly one in three over deterministic seeds")
    }

    private static func testLongPlay() {
        for seed in [UInt64(7), 27, 2026, 0xDEADBEEF] {
            var game = MazeGame(seed: seed)
            var lastRound = game.round
            var lastRemaining = game.remainingNodes
            var turnsWithoutProgress = 0
            var visitedTiles = Set<GridPoint>()
            for turn in 0..<25_000 {
                let oldPlayer = game.player.tile
                let oldRound = game.round
                let oldLives = game.lives
                game.step()
                visitedTiles.insert(game.player.tile)
                precondition((0...3).contains(game.lives))
                precondition(game.round >= oldRound)
                precondition(game.score >= 0)
                if game.round == oldRound && game.lives == oldLives {
                    precondition(manhattan(oldPlayer, game.player.tile) <= 1)
                }
                if game.round != lastRound || game.remainingNodes < lastRemaining {
                    turnsWithoutProgress = 0
                } else {
                    turnsWithoutProgress += 1
                }
                precondition(turnsWithoutProgress < 1_200,
                             "No food collected for 1200 turns, seed \(seed), turn \(turn)")
                lastRound = game.round
                lastRemaining = game.remainingNodes
                if turn % 97 == 0 { checkBoard(game) }
            }
            precondition(visitedTiles.count > 100)
            precondition(game.round > 1)
            precondition(game.clears > 0)
            precondition(game.wins + game.losses > 0)
            print("seed \(seed): wins=\(game.wins), losses=\(game.losses), rounds=\(game.round)")
            checkBoard(game)
        }
    }

    private static func checkBoard(_ game: MazeGame) {
        precondition(game.remainingNodes == game.pellets.count + game.powerPellets.count)
        precondition(game.phase == .won ? game.remainingNodes == 0 : game.remainingNodes > 0)
        precondition(game.pellets.isDisjoint(with: game.powerPellets))
        precondition(!game.isWall(x: game.player.tile.x, y: game.player.tile.y))
        precondition(!game.isWall(x: game.player.previous.x, y: game.player.previous.y))
        precondition(game.sentries.count == 4 || game.sentries.isEmpty)
        for actor in game.sentries {
            precondition(!game.isWall(x: actor.tile.x, y: actor.tile.y))
            precondition(!game.isWall(x: actor.previous.x, y: actor.previous.y))
        }
        for tile in game.pellets.union(game.powerPellets) {
            precondition(!game.isWall(x: tile.x, y: tile.y))
        }
        for x in 0..<MazeGame.width {
            precondition(game.isWall(x: x, y: 0))
            precondition(game.isWall(x: x, y: MazeGame.height - 1))
        }
        for y in 0..<MazeGame.height {
            precondition(game.isWall(x: 0, y: y))
            precondition(game.isWall(x: MazeGame.width - 1, y: y))
        }
        precondition(game.isWall(x: -1, y: 1))
        precondition(game.isWall(x: MazeGame.width, y: 1))
    }

    private static func floodFill(_ game: MazeGame, from start: GridPoint) -> Set<GridPoint> {
        var visited: Set<GridPoint> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let tile = queue[head]
            head += 1
            for heading in MazeHeading.allCases {
                let next = tile.moved(heading)
                guard !game.isWall(x: next.x, y: next.y), visited.insert(next).inserted
                else { continue }
                queue.append(next)
            }
        }
        return visited
    }

    private static func manhattan(_ a: GridPoint, _ b: GridPoint) -> Int {
        abs(a.x - b.x) + abs(a.y - b.y)
    }

    private static func wallFingerprint(_ game: MazeGame) -> [Bool] {
        (0..<MazeGame.height).flatMap { y in
            (0..<MazeGame.width).map { x in game.isWall(x: x, y: y) }
        }
    }
}
