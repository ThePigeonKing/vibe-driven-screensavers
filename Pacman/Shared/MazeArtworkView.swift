import AppKit
import CoreGraphics

/// The preview app and screen saver share this live, resolution-independent canvas.
final class MazeArtworkView: NSView {
    var game = MazeGame()
    var animationTime: TimeInterval = ProcessInfo.processInfo.systemUptime

    override var isOpaque: Bool { true }

    func advanceFrame() {
        animationTime = ProcessInfo.processInfo.systemUptime
        game.advance(to: animationTime)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setFillColor(ArcadeColor.background.cgColor)
        context.fill(bounds)

        let scale = min(bounds.width / 1440, bounds.height / 900)
        guard scale > 0 else { return }
        let origin = CGPoint(x: bounds.midX - 720 * scale,
                             y: bounds.midY - 450 * scale)
        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        MazeArtwork(game: game, animationTime: animationTime).draw(in: context,
                                                                  compact: scale < 0.42)
        context.restoreGState()
    }
}

private enum ArcadeColor {
    static let background = NSColor(calibratedRed: 0.016, green: 0.019, blue: 0.045, alpha: 1)
    static let board = NSColor(calibratedRed: 0.012, green: 0.014, blue: 0.036, alpha: 1)
    static let wall = NSColor(calibratedRed: 0.045, green: 0.061, blue: 0.151, alpha: 1)
    static let wallEdge = NSColor(calibratedRed: 0.28, green: 0.41, blue: 0.94, alpha: 1)
    static let wallHighlight = NSColor(calibratedRed: 0.52, green: 0.63, blue: 1.0, alpha: 1)
    static let border = NSColor(calibratedRed: 0.32, green: 0.44, blue: 0.92, alpha: 1)
    static let text = NSColor(calibratedRed: 0.85, green: 0.84, blue: 0.95, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.48, green: 0.52, blue: 0.71, alpha: 1)
    static let pellet = NSColor(calibratedRed: 0.98, green: 0.78, blue: 0.65, alpha: 1)
    static let player = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.16, alpha: 1)
    static let red = NSColor(calibratedRed: 1.0, green: 0.30, blue: 0.37, alpha: 1)
    static let pink = NSColor(calibratedRed: 1.0, green: 0.57, blue: 0.78, alpha: 1)
    static let cyan = NSColor(calibratedRed: 0.34, green: 0.84, blue: 0.98, alpha: 1)
    static let orange = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.28, alpha: 1)
    static let frightened = NSColor(calibratedRed: 0.20, green: 0.32, blue: 0.84, alpha: 1)
    static let eye = NSColor(calibratedRed: 0.95, green: 0.95, blue: 0.98, alpha: 1)
    static let pupil = NSColor(calibratedRed: 0.10, green: 0.15, blue: 0.43, alpha: 1)
}

private struct MazeArtwork {
    let game: MazeGame
    let animationTime: TimeInterval

    private let tile: CGFloat = 38
    private let board = CGRect(x: 131, y: 87, width: 1178, height: 722)

    func draw(in context: CGContext, compact: Bool) {
        drawBackground(in: context)
        drawMaze(in: context)
        drawPellets(in: context)
        drawPlayer(in: context)
        drawGhosts(in: context)
        drawHUD(in: context, compact: compact)
        drawOutcome(in: context)
    }

    private func drawBackground(in context: CGContext) {
        // Crisp nested borders frame the game without a glow that softens pixel edges.
        context.setFillColor(ArcadeColor.wall.cgColor)
        context.fill(board.insetBy(dx: -18, dy: -18))
        context.setFillColor(ArcadeColor.border.cgColor)
        context.fill(board.insetBy(dx: -10, dy: -10))
        context.setFillColor(ArcadeColor.background.cgColor)
        context.fill(board.insetBy(dx: -6, dy: -6))
        context.setFillColor(ArcadeColor.board.cgColor)
        context.fill(board)

        context.setFillColor(ArcadeColor.border.cgColor)
        context.fill(CGRect(x: 132, y: 820, width: 1176, height: 2))
        context.fill(CGRect(x: 132, y: 74, width: 1176, height: 2))
        for x in [132.0, 1292.0] {
            context.fill(CGRect(x: x, y: 833, width: 16, height: 3))
            context.fill(CGRect(x: x, y: 62, width: 16, height: 3))
        }
    }

    private func drawMaze(in context: CGContext) {
        for y in 0..<MazeGame.height {
            for x in 0..<MazeGame.width where game.isWall(x: x, y: y) {
                let cell = cellRect(x: x, y: y)
                context.setFillColor(ArcadeColor.wall.cgColor)
                context.fill(cell)

                context.setFillColor(ArcadeColor.wallEdge.cgColor)
                if !game.isWall(x: x, y: y - 1) {
                    context.fill(CGRect(x: cell.minX, y: cell.maxY - 4,
                                        width: tile, height: 4))
                }
                if !game.isWall(x: x, y: y + 1) {
                    context.fill(CGRect(x: cell.minX, y: cell.minY,
                                        width: tile, height: 4))
                }
                if !game.isWall(x: x - 1, y: y) {
                    context.fill(CGRect(x: cell.minX, y: cell.minY,
                                        width: 4, height: tile))
                }
                if !game.isWall(x: x + 1, y: y) {
                    context.fill(CGRect(x: cell.maxX - 4, y: cell.minY,
                                        width: 4, height: tile))
                }

                // A one-pixel inner accent separates adjacent wall blocks on large displays.
                context.setFillColor(ArcadeColor.wallHighlight.cgColor)
                if !game.isWall(x: x, y: y - 1) {
                    context.fill(CGRect(x: cell.minX + 3, y: cell.maxY - 6,
                                        width: tile - 6, height: 1))
                }
                if !game.isWall(x: x, y: y + 1) {
                    context.fill(CGRect(x: cell.minX + 3, y: cell.minY + 5,
                                        width: tile - 6, height: 1))
                }
            }
        }
    }

    private func drawPellets(in context: CGContext) {
        context.setFillColor(ArcadeColor.pellet.cgColor)
        for point in game.pellets {
            let center = cellCenter(point)
            context.fill(CGRect(x: center.x - 3, y: center.y - 3,
                                width: 6, height: 6))
        }
        for point in game.powerPellets {
            let center = cellCenter(point)
            // A steady square orb stays readable at the tiny System Settings preview size.
            context.fill(CGRect(x: center.x - 6, y: center.y - 9, width: 12, height: 18))
            context.fill(CGRect(x: center.x - 9, y: center.y - 6, width: 18, height: 12))
        }
    }

    private func drawPlayer(in context: CGContext) {
        let actor = game.player
        let center = interpolatedCenter(actor)
        let facing = atan2(CGFloat(-actor.heading.dy), CGFloat(actor.heading.dx))
        let chomp = 0.5 - 0.5 * cos(animationTime * 2 * .pi * 3.2)
        let halfOpening: CGFloat = actor.previous == actor.tile
            ? 0.03 : CGFloat(0.04 + 0.85 * chomp)
        let pixel: CGFloat = 3
        let radius: CGFloat = 16.8

        context.setFillColor(ArcadeColor.player.cgColor)
        for row in 0..<13 {
            for column in 0..<13 {
                let dx = CGFloat(column - 6) * pixel
                let dy = CGFloat(row - 6) * pixel
                let distanceSquared = dx * dx + dy * dy
                guard distanceSquared <= radius * radius else { continue }
                let direction = atan2(dy, dx)
                let difference = atan2(sin(direction - facing), cos(direction - facing))
                if distanceSquared > 4 && abs(difference) < halfOpening { continue }
                context.fill(CGRect(x: floor(center.x + dx - pixel / 2),
                                    y: floor(center.y + dy - pixel / 2),
                                    width: pixel, height: pixel))
            }
        }
    }

    private func drawGhosts(in context: CGContext) {
        let colors = [ArcadeColor.red, ArcadeColor.pink,
                      ArcadeColor.cyan, ArcadeColor.orange]
        let footFrame = Int(animationTime * 4) % 2
        for (index, actor) in game.sentries.enumerated() {
            let center = interpolatedCenter(actor)
            let color = game.powerTicks > 0 ? ArcadeColor.frightened
                                           : colors[index % colors.count]
            let origin = CGPoint(x: floor(center.x - 18), y: floor(center.y - 18))
            let body = footFrame == 0 ? Self.ghostBodyA : Self.ghostBodyB
            context.setFillColor(color.cgColor)
            for (row, pattern) in body.enumerated() {
                for (column, mark) in pattern.enumerated() where mark == "#" {
                    ghostPixel(in: context, origin: origin, x: column, row: row)
                }
            }

            if game.powerTicks > 0 {
                drawFrightenedFace(in: context, origin: origin)
            } else {
                drawGhostEyes(in: context, origin: origin, heading: actor.heading)
            }
        }
    }

    private func drawGhostEyes(in context: CGContext, origin: CGPoint,
                               heading: MazeHeading) {
        context.setFillColor(ArcadeColor.eye.cgColor)
        for start in [2, 7] {
            for row in 4...6 {
                for column in start...(start + 2) {
                    ghostPixel(in: context, origin: origin, x: column, row: row)
                }
            }
        }
        context.setFillColor(ArcadeColor.pupil.cgColor)
        let xOffset = heading.dx < 0 ? 0 : (heading.dx > 0 ? 2 : 1)
        let pupilRow = heading.dy < 0 ? 4 : (heading.dy > 0 ? 6 : 5)
        ghostPixel(in: context, origin: origin, x: 2 + xOffset, row: pupilRow)
        ghostPixel(in: context, origin: origin, x: 7 + xOffset, row: pupilRow)
    }

    private func drawFrightenedFace(in context: CGContext, origin: CGPoint) {
        context.setFillColor(ArcadeColor.eye.cgColor)
        for column in [3, 8] {
            ghostPixel(in: context, origin: origin, x: column, row: 5)
            ghostPixel(in: context, origin: origin, x: column, row: 6)
        }
        for column in [3, 5, 7, 9] {
            ghostPixel(in: context, origin: origin, x: column, row: 9)
        }
        for column in [4, 6, 8] {
            ghostPixel(in: context, origin: origin, x: column, row: 10)
        }
    }

    private func ghostPixel(in context: CGContext, origin: CGPoint,
                            x: Int, row: Int) {
        context.fill(CGRect(x: origin.x + CGFloat(x) * 3,
                            y: origin.y + CGFloat(11 - row) * 3,
                            width: 3, height: 3))
    }

    private static let ghostBodyA = [
        "....####....", "..########..", ".##########.", "############",
        "############", "############", "############", "############",
        "############", "############", "############", "###.####.###"
    ]

    private static let ghostBodyB = [
        "....####....", "..########..", ".##########.", "############",
        "############", "############", "############", "############",
        "############", "############", "############", "####.####.##"
    ]

    private func drawHUD(in context: CGContext, compact: Bool) {
        pixelText("MAZE CHASE // AUTO", at: CGPoint(x: 132, y: 845),
                  pixel: 4, color: ArcadeColor.player, in: context)
        pixelText(String(format: "ROUND %02d", game.round),
                  at: CGPoint(x: 1092, y: 845), pixel: 4,
                  color: ArcadeColor.text, in: context)

        pixelTextCentered(String(format: "TIME %03d", game.remainingTimeSeconds),
                          y: 845, pixel: 4, color: ArcadeColor.muted, in: context)

        if !compact {
            let colors = [ArcadeColor.red, ArcadeColor.pink,
                          ArcadeColor.cyan, ArcadeColor.orange]
            for (index, color) in colors.enumerated() {
                context.setFillColor(color.cgColor)
                context.fill(CGRect(x: 899 + CGFloat(index) * 19, y: 850,
                                    width: 12, height: 12))
            }
        }

        pixelText(String(format: "NODES %03d", game.remainingNodes),
                  at: CGPoint(x: 132, y: 38), pixel: 4,
                  color: ArcadeColor.pellet, in: context)
        pixelText(String(format: "SCORE %06d", game.score),
                  at: CGPoint(x: 558, y: 38), pixel: 4,
                  color: ArcadeColor.text, in: context)
        pixelText(String(format: "LIVES %02d", game.lives),
                  at: CGPoint(x: 1092, y: 38), pixel: 4,
                  color: ArcadeColor.player, in: context)
    }

    private func drawOutcome(in context: CGContext) {
        guard game.phase != .playing else { return }

        // Keep the final board visible behind a quiet, opaque arcade marquee.
        context.setFillColor(NSColor(calibratedRed: 0.005, green: 0.008,
                                     blue: 0.025, alpha: 0.77).cgColor)
        context.fill(board)

        let won = game.phase == .won
        let accent = won ? ArcadeColor.player : ArcadeColor.red
        let panel = CGRect(x: 272, y: 306, width: 896, height: 288)
        context.setFillColor(accent.cgColor)
        context.fill(panel)
        context.setFillColor(ArcadeColor.background.cgColor)
        context.fill(panel.insetBy(dx: 5, dy: 5))
        context.setFillColor(ArcadeColor.wall.cgColor)
        context.fill(panel.insetBy(dx: 15, dy: 15))
        context.setFillColor(ArcadeColor.background.cgColor)
        context.fill(panel.insetBy(dx: 19, dy: 19))

        if won {
            pixelTextCentered("YOU WON", y: 447, pixel: 14,
                              color: ArcadeColor.player, in: context)
            drawTrophy(in: context, origin: CGPoint(x: 323, y: 458))
            drawTrophy(in: context, origin: CGPoint(x: 1042, y: 458))
        } else {
            pixelTextCentered("GAME OVER", y: 447, pixel: 14,
                              color: ArcadeColor.red, in: context)
        }

        pixelTextCentered(String(format: "SCORE %06d", game.score),
                          y: 392, pixel: 6, color: ArcadeColor.text, in: context)
        let seconds = min(3, max(1, Int(ceil(Double(game.intermissionTicksRemaining)
                                              * MazeGame.stepInterval))))
        pixelTextCentered(String(format: "NEW MAZE IN %02d", seconds),
                          y: 347, pixel: 4, color: ArcadeColor.muted, in: context)
    }

    private func drawTrophy(in context: CGContext, origin: CGPoint) {
        // A tiny original bitmap cup; fixed pixel cells stay crisp in previews.
        let rows = [
            "....#######....", "..###########..", ".##.#######.##.",
            "##..#######..##", "##..#######..##", ".##.#######.##.",
            "..##.#####.##..", "...#########...", "....#######....",
            ".....#####.....", "......###......", "......###......",
            "....#######....", "...#########..."
        ]
        let pixel: CGFloat = 5
        context.setFillColor(ArcadeColor.player.cgColor)
        for (row, pattern) in rows.enumerated() {
            for (column, mark) in pattern.enumerated() where mark == "#" {
                context.fill(CGRect(x: origin.x + CGFloat(column) * pixel,
                                    y: origin.y + CGFloat(rows.count - row - 1) * pixel,
                                    width: pixel, height: pixel))
            }
        }
    }

    private func pixelTextCentered(_ text: String, y: CGFloat, pixel: CGFloat,
                                   color: NSColor, in context: CGContext) {
        let width = CGFloat(text.count * 6 - 1) * pixel
        pixelText(text, at: CGPoint(x: floor((1440 - width) / 2), y: y),
                  pixel: pixel, color: color, in: context)
    }

    private func pixelText(_ text: String, at point: CGPoint, pixel: CGFloat,
                           color: NSColor, in context: CGContext) {
        context.setFillColor(color.cgColor)
        for (index, character) in text.uppercased().enumerated() {
            guard let rows = Self.glyphs[character] else { continue }
            for (row, bits) in rows.enumerated() {
                for column in 0..<5 where bits & UInt8(1 << (4 - column)) != 0 {
                    context.fill(CGRect(x: point.x + CGFloat(index * 6 + column) * pixel,
                                        y: point.y + CGFloat(6 - row) * pixel,
                                        width: pixel, height: pixel))
                }
            }
        }
    }

    // Five by seven bitmap type keeps the heads-up display legible at preview size.
    private static let glyphs: [Character: [UInt8]] = [
        "A": [14, 17, 17, 31, 17, 17, 17],
        "B": [30, 17, 17, 30, 17, 17, 30],
        "C": [14, 17, 16, 16, 16, 17, 14],
        "D": [30, 17, 17, 17, 17, 17, 30],
        "E": [31, 16, 16, 30, 16, 16, 31],
        "F": [31, 16, 16, 30, 16, 16, 16],
        "G": [14, 17, 16, 23, 17, 17, 14],
        "H": [17, 17, 17, 31, 17, 17, 17],
        "I": [31, 4, 4, 4, 4, 4, 31],
        "J": [7, 2, 2, 2, 18, 18, 12],
        "K": [17, 18, 20, 24, 20, 18, 17],
        "L": [16, 16, 16, 16, 16, 16, 31],
        "M": [17, 27, 21, 21, 17, 17, 17],
        "N": [17, 25, 21, 19, 17, 17, 17],
        "O": [14, 17, 17, 17, 17, 17, 14],
        "P": [30, 17, 17, 30, 16, 16, 16],
        "Q": [14, 17, 17, 17, 21, 18, 13],
        "R": [30, 17, 17, 30, 20, 18, 17],
        "S": [15, 16, 16, 14, 1, 1, 30],
        "T": [31, 4, 4, 4, 4, 4, 4],
        "U": [17, 17, 17, 17, 17, 17, 14],
        "V": [17, 17, 17, 17, 17, 10, 4],
        "W": [17, 17, 17, 21, 21, 21, 10],
        "X": [17, 17, 10, 4, 10, 17, 17],
        "Y": [17, 17, 10, 4, 4, 4, 4],
        "Z": [31, 1, 2, 4, 8, 16, 31],
        "0": [14, 17, 19, 21, 25, 17, 14],
        "1": [4, 12, 4, 4, 4, 4, 14],
        "2": [14, 17, 1, 2, 4, 8, 31],
        "3": [30, 1, 1, 14, 1, 1, 30],
        "4": [2, 6, 10, 18, 31, 2, 2],
        "5": [31, 16, 16, 30, 1, 1, 30],
        "6": [14, 16, 16, 30, 17, 17, 14],
        "7": [31, 1, 2, 4, 8, 8, 8],
        "8": [14, 17, 17, 14, 17, 17, 14],
        "9": [14, 17, 17, 15, 1, 1, 14],
        "/": [1, 1, 2, 4, 8, 16, 16],
        "-": [0, 0, 0, 31, 0, 0, 0],
        ":": [0, 4, 4, 0, 4, 4, 0],
        " ": [0, 0, 0, 0, 0, 0, 0]
    ]

    private func cellRect(x: Int, y: Int) -> CGRect {
        CGRect(x: board.minX + CGFloat(x) * tile,
               y: board.minY + CGFloat(MazeGame.height - 1 - y) * tile,
               width: tile, height: tile)
    }

    private func cellCenter(_ point: GridPoint) -> CGPoint {
        CGPoint(x: board.minX + (CGFloat(point.x) + 0.5) * tile,
                y: board.minY + (CGFloat(MazeGame.height - 1 - point.y) + 0.5) * tile)
    }

    private func interpolatedCenter(_ actor: MazeActor) -> CGPoint {
        let from = cellCenter(actor.previous)
        let to = cellCenter(actor.tile)
        let fraction = CGFloat(max(0, min(1, game.interpolation)))
        return CGPoint(x: from.x + (to.x - from.x) * fraction,
                       y: from.y + (to.y - from.y) * fraction)
    }
}
