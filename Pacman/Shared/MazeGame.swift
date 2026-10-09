import Foundation

struct GridPoint: Hashable, Sendable {
    let x: Int
    let y: Int

    func moved(_ heading: MazeHeading) -> GridPoint {
        GridPoint(x: x + heading.dx, y: y + heading.dy)
    }
}

enum MazeHeading: CaseIterable, Sendable {
    case up, right, down, left

    var dx: Int {
        switch self {
        case .left: -1
        case .right: 1
        case .up, .down: 0
        }
    }

    var dy: Int {
        switch self {
        case .up: -1
        case .down: 1
        case .left, .right: 0
        }
    }

    var opposite: MazeHeading {
        switch self {
        case .up: .down
        case .right: .left
        case .down: .up
        case .left: .right
        }
    }
}

enum MazeGhostMode: Sendable {
    case scatter, chase, frightened
}

enum MazeGamePhase: Equatable, Sendable {
    case playing, gameOver, won
}

/// Four distinct pursuit rules inspired by the arcade game's ghost personalities.
/// This generated maze and its movement timing are original, not an arcade emulation.
enum MazeGhostKind: Int, CaseIterable, Sendable {
    case red, pink, cyan, orange

    var scatterTarget: GridPoint {
        switch self {
        case .red: GridPoint(x: MazeGame.width + 1, y: -2)
        case .pink: GridPoint(x: -2, y: -2)
        case .cyan: GridPoint(x: MazeGame.width + 1, y: MazeGame.height + 1)
        case .orange: GridPoint(x: -2, y: MazeGame.height + 1)
        }
    }

    func chaseTarget(player: GridPoint, heading: MazeHeading,
                     red: GridPoint, own: GridPoint) -> GridPoint {
        switch self {
        case .red:
            return player
        case .pink:
            return GridPoint(x: player.x + heading.dx * 4,
                             y: player.y + heading.dy * 4)
        case .cyan:
            let twoAhead = GridPoint(x: player.x + heading.dx * 2,
                                     y: player.y + heading.dy * 2)
            return GridPoint(x: twoAhead.x * 2 - red.x,
                             y: twoAhead.y * 2 - red.y)
        case .orange:
            let dx = own.x - player.x
            let dy = own.y - player.y
            return dx * dx + dy * dy >= 64 ? player : scatterTarget
        }
    }
}

struct MazeActor: Sendable {
    var tile: GridPoint
    var previous: GridPoint
    var heading: MazeHeading

    init(tile: GridPoint, heading: MazeHeading) {
        self.tile = tile
        previous = tile
        self.heading = heading
    }
}

/// A small, self-playing maze game. Coordinates and rules never depend on the view size.
struct MazeGame {
    static let width = 31
    static let height = 19
    static let stepInterval: TimeInterval = 0.18
    static let maxGameTicks = Int(200 / stepInterval)
    static let intermissionDurationTicks = 17
    static let startingLives = 3

    private static let playerSpawn = GridPoint(x: 1, y: 17)
    private static let sentrySpeeds = [0.98, 0.96, 0.94, 0.92]
    // Scatter and chase alternate; frightened time pauses this clock.
    private static let phaseLengths = [39, 111, 39, 111, 28, 111, 28]
    private static let ghostHeadingPriority: [MazeHeading] = [.up, .left, .down, .right]
    private static let powerDuration = 24

    private(set) var pellets: Set<GridPoint> = []
    private(set) var powerPellets: Set<GridPoint> = []
    private(set) var player = MazeActor(tile: Self.playerSpawn, heading: .right)
    private(set) var sentries: [MazeActor] = []
    private(set) var score = 0
    private(set) var round = 1
    private(set) var lives = Self.startingLives
    private(set) var clears = 0
    private(set) var powerTicks = 0
    private(set) var interpolation = 1.0
    private(set) var phase: MazeGamePhase = .playing
    private(set) var intermissionTicksRemaining = 0
    private(set) var elapsedGameTicks = 0
    private(set) var wins = 0
    private(set) var losses = 0

    var remainingTimeSeconds: Int {
        max(0, Int(ceil(Double(timeLimitTicks - elapsedGameTicks) * Self.stepInterval)))
    }

    var ghostMode: MazeGhostMode {
        powerTicks > 0 ? .frightened : (phaseIndex.isMultiple(of: 2) ? .scatter : .chase)
    }

    var remainingNodes: Int { pellets.count + powerPellets.count }

    private var walls = [Bool](repeating: true, count: Self.width * Self.height)
    private var rng: MazeRandom
    private let configuredSentryCount: Int
    private let timeLimitTicks: Int
    private var sentrySpawns: [GridPoint] = []
    private var sentryCharge: [Double] = []
    private var sentryReversePending: [Bool] = []
    private var phaseIndex = 0
    private var phaseTurns = 0
    private var selectedPellet: GridPoint?
    private var noProgressSteps = 0
    private var respawnSteps = 0
    private var lastUptime: TimeInterval?
    private var accumulatedTime: TimeInterval = 0

    /// `sentryCount: 0` and a short time limit are useful in deterministic rule tests.
    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max),
         sentryCount: Int = 4, timeLimitTicks: Int = maxGameTicks) {
        rng = MazeRandom(seed: seed)
        configuredSentryCount = min(max(sentryCount, 0), MazeGhostKind.allCases.count)
        self.timeLimitTicks = max(1, timeLimitTicks)
        generateRound()
    }

    func isWall(x: Int, y: Int) -> Bool {
        guard x >= 0, x < Self.width, y >= 0, y < Self.height else { return true }
        return walls[y * Self.width + x]
    }

    /// Advances by elapsed monotonic time. Sleeping does not replay minutes of game turns.
    mutating func advance(to uptime: TimeInterval) {
        guard uptime.isFinite else { return }
        guard let lastUptime else {
            self.lastUptime = uptime
            return
        }
        self.lastUptime = uptime
        guard uptime >= lastUptime else {
            accumulatedTime = 0
            interpolation = 1
            return
        }

        accumulatedTime += min(uptime - lastUptime, Self.stepInterval * 4)
        var turns = 0
        while accumulatedTime >= Self.stepInterval && turns < 4 {
            let previousPhase = phase
            step()
            accumulatedTime -= Self.stepInterval
            turns += 1
            if phase != previousPhase {
                accumulatedTime = 0
                break
            }
        }
        if accumulatedTime >= Self.stepInterval {
            accumulatedTime.formTruncatingRemainder(dividingBy: Self.stepInterval)
        }
        interpolation = phase == .playing
            ? min(max(accumulatedTime / Self.stepInterval, 0), 1) : 1
    }

    /// One complete board turn; exposed so rule tests need no display timer.
    mutating func step() {
        interpolation = 0
        if phase != .playing {
            interpolation = 1
            intermissionTicksRemaining -= 1
            if intermissionTicksRemaining <= 0 {
                beginNextGame()
            }
            return
        }

        elapsedGameTicks += 1
        if elapsedGameTicks >= timeLimitTicks {
            finishGame(as: .gameOver)
            return
        }

        player.previous = player.tile
        for index in sentries.indices { sentries[index].previous = sentries[index].tile }

        if respawnSteps > 0 {
            respawnSteps -= 1
            return
        }
        if powerTicks > 0 { powerTicks -= 1 }

        let oldPlayer = player.tile
        let oldSentries = sentries.map(\.tile)
        let next = choosePlayerStep()
        player.heading = heading(from: player.tile, to: next) ?? player.heading
        player.tile = next

        var atePellet = false
        if pellets.remove(next) != nil {
            score += 10
            atePellet = true
        }
        if powerPellets.remove(next) != nil {
            score += 50
            if powerTicks == 0 { requestSentryReversal() }
            powerTicks = Self.powerDuration
            atePellet = true
        }
        if atePellet {
            noProgressSteps = 0
            if selectedPellet == next { selectedPellet = nil }
        } else {
            noProgressSteps += 1
        }

        if remainingNodes == 0 {
            score += 500
            finishGame(as: .won)
            return
        }

        advanceGhostClock()

        for index in sentries.indices {
            var speed = Self.sentrySpeeds[index]
            if powerTicks > 0 {
                speed *= 0.72
            } else if index == MazeGhostKind.red.rawValue && remainingNodes <= 20 {
                // The red pursuer becomes more urgent as the board empties.
                speed = min(speed + (remainingNodes <= 10 ? 0.14 : 0.08), 0.995)
            }
            sentryCharge[index] += speed
            if sentryCharge[index] >= 1 {
                sentryCharge[index] -= 1
                moveSentry(index)
            }
        }

        for index in sentries.indices {
            let sharedTile = sentries[index].tile == player.tile
            let crossed = oldSentries[index] == player.tile && sentries[index].tile == oldPlayer
            guard sharedTile || crossed else { continue }
            if powerTicks > 0 {
                score += 200
                sentries[index] = MazeActor(tile: sentrySpawns[index], heading: .left)
                sentryCharge[index] = 0
            } else {
                loseLife()
                return
            }
        }
    }

    private mutating func finishGame(as result: MazeGamePhase) {
        precondition(result != .playing)
        phase = result
        intermissionTicksRemaining = Self.intermissionDurationTicks
        interpolation = 1
        if result == .won {
            wins += 1
            clears += 1
        } else {
            losses += 1
        }
    }

    private mutating func beginNextGame() {
        round += 1
        score = 0
        lives = Self.startingLives
        phase = .playing
        intermissionTicksRemaining = 0
        elapsedGameTicks = 0
        generateRound()
    }

    private mutating func generateRound() {
        walls = [Bool](repeating: true, count: Self.width * Self.height)
        let roomWidth = (Self.width - 1) / 2
        let roomHeight = (Self.height - 1) / 2
        var visited = [Bool](repeating: false, count: roomWidth * roomHeight)
        let firstRoom = GridPoint(x: 0, y: roomHeight - 1)
        var stack = [firstRoom]
        visited[firstRoom.y * roomWidth + firstRoom.x] = true
        carve(GridPoint(x: 1, y: Self.height - 2))

        // A spanning tree makes every room reachable, even for unusual seeds.
        while let room = stack.last {
            let options = MazeHeading.allCases.compactMap { heading -> GridPoint? in
                let next = room.moved(heading)
                guard next.x >= 0, next.x < roomWidth,
                      next.y >= 0, next.y < roomHeight,
                      !visited[next.y * roomWidth + next.x] else { return nil }
                return next
            }
            guard !options.isEmpty else {
                stack.removeLast()
                continue
            }
            let next = options[rng.nextInt(options.count)]
            let roomTile = GridPoint(x: room.x * 2 + 1, y: room.y * 2 + 1)
            let nextTile = GridPoint(x: next.x * 2 + 1, y: next.y * 2 + 1)
            carve(GridPoint(x: (roomTile.x + nextTile.x) / 2,
                            y: (roomTile.y + nextTile.y) / 2))
            carve(nextTile)
            visited[next.y * roomWidth + next.x] = true
            stack.append(next)
        }

        // Extra bridges turn the tree into a maze with escape loops and varied routes.
        var closedBridges: [GridPoint] = []
        for y in stride(from: 1, through: Self.height - 2, by: 2) {
            for x in stride(from: 1, through: Self.width - 2, by: 2) {
                if x + 2 < Self.width - 1, isWall(x: x + 1, y: y) {
                    closedBridges.append(GridPoint(x: x + 1, y: y))
                }
                if y + 2 < Self.height - 1, isWall(x: x, y: y + 1) {
                    closedBridges.append(GridPoint(x: x, y: y + 1))
                }
            }
        }
        if closedBridges.count > 1 {
            for index in stride(from: closedBridges.count - 1, through: 1, by: -1) {
                closedBridges.swapAt(index, rng.nextInt(index + 1))
            }
        }
        for bridge in closedBridges.prefix((closedBridges.count * 3) / 10) { carve(bridge) }

        player = MazeActor(tile: Self.playerSpawn, heading: .right)
        sentrySpawns = chooseSentrySpawns(count: configuredSentryCount)
        sentries = sentrySpawns.map { MazeActor(tile: $0, heading: .left) }
        sentryCharge = [Double](repeating: 0, count: sentries.count)
        sentryReversePending = [Bool](repeating: false, count: sentries.count)
        phaseIndex = 0
        phaseTurns = 0
        selectedPellet = nil
        noProgressSteps = 0
        respawnSteps = 0
        powerTicks = 0

        pellets.removeAll(keepingCapacity: true)
        powerPellets.removeAll(keepingCapacity: true)
        for y in 1..<(Self.height - 1) {
            for x in 1..<(Self.width - 1) where !isWall(x: x, y: y) {
                let tile = GridPoint(x: x, y: y)
                if tile != Self.playerSpawn && !sentrySpawns.contains(tile) { pellets.insert(tile) }
            }
        }
        let powerCandidates = [GridPoint(x: 5, y: 3), GridPoint(x: 25, y: 3),
                               GridPoint(x: 25, y: 15), GridPoint(x: 5, y: 15),
                               GridPoint(x: 15, y: 9), GridPoint(x: 15, y: 3)]
        for tile in powerCandidates where powerPellets.count < 4 {
            if pellets.remove(tile) != nil { powerPellets.insert(tile) }
        }
    }

    private mutating func carve(_ tile: GridPoint) {
        walls[index(of: tile)] = false
    }

    private mutating func chooseSentrySpawns(count: Int) -> [GridPoint] {
        guard count > 0 else { return [] }
        let candidates = (0..<Self.height).flatMap { y in
            (0..<Self.width).compactMap { x -> GridPoint? in
                guard x % 2 == 1, y % 2 == 1 else { return nil }
                return GridPoint(x: x, y: y)
            }
        }.filter { $0 != Self.playerSpawn }
        let fromPlayer = distanceField(from: [Self.playerSpawn])
        var selected: [GridPoint] = []
        for _ in 0..<count {
            let separation = selected.map { distanceField(from: [$0]) }
            let best = candidates.filter { !selected.contains($0) }.max { lhs, rhs in
                func value(_ tile: GridPoint) -> Int {
                    let location = index(of: tile)
                    let apart = separation.map { $0[location] }.min() ?? 0
                    return fromPlayer[location] * 2 + apart
                }
                let a = value(lhs), b = value(rhs)
                return a == b ? index(of: lhs) > index(of: rhs) : a < b
            }!
            selected.append(best)
        }
        return selected
    }

    private mutating func choosePlayerStep() -> GridPoint {
        let start = index(of: player.tile)
        let danger = distanceField(from: sentries.map(\.tile))
        let ignoreDanger = powerTicks > 0 || noProgressSteps >= 65
        let infinity = Int.max / 8
        var costs = [Int](repeating: infinity, count: walls.count)
        var firstSteps = [Int](repeating: -1, count: walls.count)
        var heap = MazeMinHeap()
        costs[start] = 0
        heap.push(cost: 0, index: start)

        while let current = heap.pop() {
            if current.cost != costs[current.index] { continue }
            let point = point(at: current.index)
            for (neighbor, _) in neighbors(of: point) {
                let location = index(of: neighbor)
                let nearest = danger[location]
                var penalty = 0
                if !ignoreDanger {
                    switch nearest {
                    case 0: penalty = 80
                    case 1: penalty = 24
                    case 2: penalty = 9
                    case 3: penalty = 3
                    default: break
                    }
                    if nearest <= 5 && neighbors(of: neighbor).count == 1 { penalty += 8 }
                }
                // Mildly prefer continuing forward when otherwise equally safe.
                if current.index == start && neighbor == player.previous { penalty += 2 }
                let proposed = current.cost + 1 + penalty
                if proposed < costs[location] {
                    costs[location] = proposed
                    firstSteps[location] = current.index == start
                        ? location : firstSteps[current.index]
                    heap.push(cost: proposed, index: location)
                }
            }
        }

        var bestTile: GridPoint?
        var bestScore = infinity
        for location in walls.indices where !walls[location] {
            let tile = point(at: location)
            guard pellets.contains(tile) || powerPellets.contains(tile),
                  firstSteps[location] >= 0 else { continue }
            var value = costs[location]
            if tile != selectedPellet { value += 3 }
            if powerPellets.contains(tile) && danger[start] <= 6 { value -= 4 }
            if value < bestScore {
                bestScore = value
                bestTile = tile
            }
        }
        if let bestTile {
            selectedPellet = bestTile
            return point(at: firstSteps[index(of: bestTile)])
        }
        return neighbors(of: player.tile).first?.0 ?? player.tile
    }

    private mutating func advanceGhostClock() {
        guard powerTicks == 0, phaseIndex < Self.phaseLengths.count else { return }
        phaseTurns += 1
        guard phaseTurns >= Self.phaseLengths[phaseIndex] else { return }
        phaseTurns = 0
        phaseIndex += 1
        requestSentryReversal()
    }

    private mutating func requestSentryReversal() {
        for index in sentryReversePending.indices { sentryReversePending[index] = true }
    }

    private mutating func moveSentry(_ actorIndex: Int) {
        let actor = sentries[actorIndex]
        var options = neighbors(of: actor.tile)
        guard !options.isEmpty else { return }

        if sentryReversePending[actorIndex] {
            sentryReversePending[actorIndex] = false
            if let backward = options.first(where: { $0.1 == actor.heading.opposite }) {
                sentries[actorIndex].tile = backward.0
                sentries[actorIndex].heading = backward.1
                return
            }
        }
        if options.count > 1 {
            options.removeAll { $0.1 == actor.heading.opposite }
        }
        if options.isEmpty { options = neighbors(of: actor.tile) }

        if powerTicks > 0 {
            // Frightened ghosts move slower and choose a seeded random legal turn.
            let chosen = options[rng.nextInt(options.count)]
            sentries[actorIndex].tile = chosen.0
            sentries[actorIndex].heading = chosen.1
            return
        }

        let kind = MazeGhostKind(rawValue: actorIndex)!
        let target: GridPoint
        if ghostMode == .scatter && !(kind == .red && remainingNodes <= 20) {
            target = kind.scatterTarget
        } else {
            target = kind.chaseTarget(player: player.tile, heading: player.heading,
                                      red: sentries[0].tile, own: actor.tile)
        }
        // The target may lie inside a wall or outside the board. At each turn,
        // choose the legal neighboring tile closest to it, with fixed tie order.
        // This local steering is intentionally unlike shortest-path pursuit.
        let chosen = options.min {
            let a = squaredDistance($0.0, target)
            let b = squaredDistance($1.0, target)
            return a == b ? headingRank($0.1) < headingRank($1.1) : a < b
        }!
        sentries[actorIndex].tile = chosen.0
        sentries[actorIndex].heading = chosen.1
    }

    private mutating func loseLife() {
        lives -= 1
        powerTicks = 0
        selectedPellet = nil
        noProgressSteps = 0
        if lives <= 0 {
            finishGame(as: .gameOver)
            return
        }
        player = MazeActor(tile: Self.playerSpawn, heading: .right)
        sentries = sentrySpawns.map { MazeActor(tile: $0, heading: .left) }
        sentryCharge = [Double](repeating: 0, count: sentries.count)
        sentryReversePending = [Bool](repeating: false, count: sentries.count)
        phaseIndex = 0
        phaseTurns = 0
        respawnSteps = 4
    }

    private func distanceField(from sources: [GridPoint]) -> [Int] {
        let infinity = Int.max / 8
        var distances = [Int](repeating: infinity, count: walls.count)
        var queue: [GridPoint] = []
        for source in sources where !isWall(x: source.x, y: source.y) {
            let location = index(of: source)
            if distances[location] == 0 { continue }
            distances[location] = 0
            queue.append(source)
        }
        var head = 0
        while head < queue.count {
            let current = queue[head]
            head += 1
            let nextDistance = distances[index(of: current)] + 1
            for (neighbor, _) in neighbors(of: current) {
                let location = index(of: neighbor)
                guard nextDistance < distances[location] else { continue }
                distances[location] = nextDistance
                queue.append(neighbor)
            }
        }
        return distances
    }

    private func neighbors(of tile: GridPoint) -> [(GridPoint, MazeHeading)] {
        MazeHeading.allCases.compactMap { heading in
            let next = tile.moved(heading)
            return isWall(x: next.x, y: next.y) ? nil : (next, heading)
        }
    }

    private func index(of tile: GridPoint) -> Int { tile.y * Self.width + tile.x }
    private func point(at index: Int) -> GridPoint {
        GridPoint(x: index % Self.width, y: index / Self.width)
    }

    private func heading(from start: GridPoint, to end: GridPoint) -> MazeHeading? {
        MazeHeading.allCases.first { start.moved($0) == end }
    }

    private func headingRank(_ heading: MazeHeading) -> Int {
        Self.ghostHeadingPriority.firstIndex(of: heading)!
    }

    private func squaredDistance(_ a: GridPoint, _ b: GridPoint) -> Int {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

private struct MazeRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextInt(_ upperBound: Int) -> Int {
        precondition(upperBound > 0)
        return Int(next() % UInt64(upperBound))
    }
}

private struct MazeMinHeap {
    private struct Entry {
        let cost: Int
        let index: Int

        func precedes(_ other: Entry) -> Bool {
            cost == other.cost ? index < other.index : cost < other.cost
        }
    }

    private var entries: [Entry] = []

    mutating func push(cost: Int, index: Int) {
        entries.append(Entry(cost: cost, index: index))
        var child = entries.count - 1
        while child > 0 {
            let parent = (child - 1) / 2
            guard entries[child].precedes(entries[parent]) else { break }
            entries.swapAt(child, parent)
            child = parent
        }
    }

    mutating func pop() -> (cost: Int, index: Int)? {
        guard !entries.isEmpty else { return nil }
        let first = entries[0]
        let last = entries.removeLast()
        if !entries.isEmpty {
            entries[0] = last
            var parent = 0
            while true {
                let left = parent * 2 + 1
                guard left < entries.count else { break }
                let right = left + 1
                let child = right < entries.count && entries[right].precedes(entries[left])
                    ? right : left
                guard entries[child].precedes(entries[parent]) else { break }
                entries.swapAt(child, parent)
                parent = child
            }
        }
        return (first.cost, first.index)
    }
}
