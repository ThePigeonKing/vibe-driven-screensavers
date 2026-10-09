import AppKit
import CoreGraphics

/// All artwork is vector based, so the same drawing scales from System Settings
/// previews to full screen displays without bitmap assets or network access.
final class TerminalArtworkView: NSView {
    var theme: TerminalTheme = .amber {
        didSet {
            palette = theme.palette
            needsDisplay = true
        }
    }
    private var palette = TerminalTheme.amber.palette
    private var telemetry = TelemetryModel()

    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let bounds = self.bounds
        let uptime = ProcessInfo.processInfo.systemUptime
        telemetry.advance(at: uptime)
        context.setFillColor(palette.background.cgColor)
        context.fill(bounds)

        let scale = min(bounds.width / 1440, bounds.height / 900)
        guard scale > 0 else { return }
        let origin = CGPoint(
            x: bounds.midX - 720 * scale,
            y: bounds.midY - 450 * scale
        )

        context.saveGState()
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.setAllowsAntialiasing(true)
        TerminalArtwork(palette: palette).draw(
            in: context,
            date: Date(),
            motionTime: uptime,
            signalDivider: telemetry.signalDivider,
            loadDivider: telemetry.loadDivider,
            compact: scale < 0.43
        )
        context.restoreGState()

        // On wide displays the quiet side rails fill the extra space without
        // stretching the numerals or changing their segment proportions.
        if bounds.width > 1440 * scale + 80 {
            drawSideRails(in: context, bounds: bounds, contentWidth: 1440 * scale)
        }
    }

    private func drawSideRails(in context: CGContext, bounds: CGRect, contentWidth: CGFloat) {
        let left = bounds.midX - contentWidth / 2
        let right = bounds.midX + contentWidth / 2
        context.setStrokeColor(palette.border.withAlphaComponent(0.38).cgColor)
        context.setLineWidth(1)
        for x in stride(from: bounds.minX + 28, through: left - 24, by: 28) {
            context.move(to: CGPoint(x: x, y: bounds.midY - 22))
            context.addLine(to: CGPoint(x: x, y: bounds.midY + 22))
        }
        for x in stride(from: right + 24, through: bounds.maxX - 28, by: 28) {
            context.move(to: CGPoint(x: x, y: bounds.midY - 22))
            context.addLine(to: CGPoint(x: x, y: bounds.midY + 22))
        }
        context.strokePath()
    }
}

private struct TerminalArtwork {
    let palette: TerminalPalette

    func draw(in context: CGContext, date: Date, motionTime: TimeInterval,
              signalDivider: Int, loadDivider: Int, compact: Bool) {
        let t = CGFloat(motionTime)
        drawGrid(in: context)
        drawChassis(in: context)
        drawHeader(in: context, compact: compact)
        drawClock(in: context, date: date, motionTime: t, compact: compact)
        drawMeters(in: context, signalDivider: signalDivider,
                   loadDivider: loadDivider, compact: compact)
        drawFooter(in: context, date: date, compact: compact)
    }

    private func drawGrid(in context: CGContext) {
        context.setStrokeColor(palette.border.withAlphaComponent(0.08).cgColor)
        context.setLineWidth(1)
        for x in stride(from: 0, through: 1440, by: 40) {
            line(in: context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: 900))
        }
        for y in stride(from: 0, through: 900, by: 40) {
            line(in: context, from: CGPoint(x: 0, y: y), to: CGPoint(x: 1440, y: y))
        }
    }

    private func drawChassis(in context: CGContext) {
        stroke(in: context, CGRect(x: 34, y: 35, width: 1372, height: 830),
               color: palette.border.withAlphaComponent(0.68), width: 2)
        stroke(in: context, CGRect(x: 47, y: 48, width: 1346, height: 804),
               color: palette.border.withAlphaComponent(0.29), width: 1)

        // Corner registration marks are deliberately asymmetric and original.
        context.setStrokeColor(palette.accent.withAlphaComponent(0.74).cgColor)
        context.setLineWidth(3)
        for (x, y, dx, dy) in [(66.0, 826.0, 1.0, -1.0),
                               (1374.0, 826.0, -1.0, -1.0),
                               (66.0, 74.0, 1.0, 1.0),
                               (1374.0, 74.0, -1.0, 1.0)] {
            line(in: context, from: CGPoint(x: x, y: y), to: CGPoint(x: x + 28 * dx, y: y))
            line(in: context, from: CGPoint(x: x, y: y), to: CGPoint(x: x, y: y + 28 * dy))
        }
    }

    private func drawHeader(in context: CGContext, compact: Bool) {
        label("AT / 01", x: 93, y: 799, size: 25, color: palette.highlight, weight: .bold, tracking: 4)
        label("LOCAL CHRONOMETRY", x: 295, y: 801, size: 20, color: palette.primary, tracking: 3)
        label("SYSTEM / ACTIVE", x: 1085, y: 803, size: 16, color: palette.secondary, tracking: 2)
        context.setStrokeColor(palette.accent.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(2)
        line(in: context, from: CGPoint(x: 93, y: 780), to: CGPoint(x: 1347, y: 780))
        context.setFillColor(palette.accent.withAlphaComponent(0.74).cgColor)
        context.fill(CGRect(x: 93, y: 774, width: 132, height: 6))
        if !compact {
            label("TIME BASE  /  DEVICE LOCAL", x: 95, y: 749, size: 12, color: palette.muted, tracking: 2)
            label("CONTINUOUS DISPLAY   •   24 HOUR", x: 1055, y: 749, size: 12,
                  color: palette.muted, tracking: 1)
        }
    }

    private func drawClock(in context: CGContext, date: Date, motionTime: CGFloat, compact: Bool) {
        let clockPanel = CGRect(x: 209, y: 382, width: 1022, height: 337)
        fill(in: context, clockPanel, color: palette.panel.withAlphaComponent(0.93))
        stroke(in: context, clockPanel, color: palette.accent.withAlphaComponent(0.65), width: 2)
        stroke(in: context, clockPanel.insetBy(dx: 8, dy: 8),
               color: palette.border.withAlphaComponent(0.35), width: 1)

        label("CIVIL TIME / LOCAL", x: 238, y: 680, size: 15, color: palette.highlight, tracking: 3)
        label("SYNC  //  LIVE", x: 1042, y: 680, size: 12, color: palette.secondary, tracking: 2)
        context.setStrokeColor(palette.border.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        line(in: context, from: CGPoint(x: 238, y: 663), to: CGPoint(x: 1201, y: 663))

        let components = Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: date)
        let time = String(format: "%02d:%02d:%02d", components.hour ?? 0,
                          components.minute ?? 0, components.second ?? 0)
        let glow = 0.92 + 0.08 * sin(motionTime * 2 * .pi / 5.5)
        let widths: [CGFloat] = [122, 122, 42, 122, 122, 42, 122, 122]
        let spacing: CGFloat = 14
        let total = widths.reduce(0, +) + spacing * CGFloat(widths.count - 1)
        var cursor = 720 - total / 2
        for (index, character) in time.enumerated() {
            if character == ":" {
                drawColon(in: context, x: cursor, y: 439, width: widths[index], height: 195, glow: glow)
            } else if let value = character.wholeNumberValue {
                drawDigit(in: context, value: value,
                          frame: CGRect(x: cursor, y: 439, width: widths[index], height: 195),
                          glow: glow)
            }
            cursor += widths[index] + spacing
        }

        context.setStrokeColor(palette.accent.withAlphaComponent(0.45).cgColor)
        context.setLineWidth(1)
        line(in: context, from: CGPoint(x: 238, y: 423), to: CGPoint(x: 1201, y: 423))
        if !compact {
            label("HOUR", x: 348, y: 398, size: 12, color: palette.muted, tracking: 2)
            label("MINUTE", x: 694, y: 398, size: 12, color: palette.muted, tracking: 2)
            label("SECOND", x: 1040, y: 398, size: 12, color: palette.muted, tracking: 2)
        }

        drawSideRuler(in: context, x: 109, y: 428, height: 239, flipped: false)
        drawSideRuler(in: context, x: 1331, y: 428, height: 239, flipped: true)
    }

    private func drawDigit(in context: CGContext, value: Int, frame: CGRect, glow: CGFloat) {
        let w = frame.width
        let h = frame.height
        let t: CGFloat = 14
        let upperHeight = h / 2 - 1.5 * t
        let lowerHeight = upperHeight
        let paths: [CGPath] = [
            horizontalPath(x: frame.minX + t, y: frame.minY + h - t, width: w - 2 * t, thickness: t),
            verticalPath(x: frame.minX + w - t, y: frame.minY + h / 2 + t / 2,
                         thickness: t, height: upperHeight),
            verticalPath(x: frame.minX + w - t, y: frame.minY + t,
                         thickness: t, height: lowerHeight),
            horizontalPath(x: frame.minX + t, y: frame.minY, width: w - 2 * t, thickness: t),
            verticalPath(x: frame.minX, y: frame.minY + t,
                         thickness: t, height: lowerHeight),
            verticalPath(x: frame.minX, y: frame.minY + h / 2 + t / 2,
                         thickness: t, height: upperHeight),
            horizontalPath(x: frame.minX + t, y: frame.minY + h / 2 - t / 2,
                           width: w - 2 * t, thickness: t)
        ]
        // Top, upper right, lower right, bottom, lower left, upper left, centre.
        let masks: [Int] = [0b0111111, 0b0000110, 0b1011011, 0b1001111, 0b1100110,
                            0b1101101, 0b1111101, 0b0000111, 0b1111111, 0b1101111]
        let mask = masks[value]
        for (index, path) in paths.enumerated() {
            let lit = (mask & (1 << index)) != 0
            if lit {
                context.saveGState()
                context.setShadow(offset: .zero, blur: 20,
                                  color: palette.accent.withAlphaComponent(0.42 * glow).cgColor)
                context.addPath(path)
                context.setFillColor(palette.primary.withAlphaComponent(0.93 * glow).cgColor)
                context.fillPath()
                context.restoreGState()
                context.addPath(path)
                context.setStrokeColor(palette.highlight.withAlphaComponent(0.75 * glow).cgColor)
                context.setLineWidth(1.3)
                context.strokePath()
            } else {
                context.addPath(path)
                context.setFillColor(palette.border.withAlphaComponent(0.15).cgColor)
                context.fillPath()
            }
        }
    }

    private func horizontalPath(x: CGFloat, y: CGFloat, width: CGFloat, thickness: CGFloat) -> CGPath {
        let inset = min(thickness * 0.52, width / 4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + inset, y: y))
        path.addLine(to: CGPoint(x: x + width - inset, y: y))
        path.addLine(to: CGPoint(x: x + width, y: y + thickness / 2))
        path.addLine(to: CGPoint(x: x + width - inset, y: y + thickness))
        path.addLine(to: CGPoint(x: x + inset, y: y + thickness))
        path.addLine(to: CGPoint(x: x, y: y + thickness / 2))
        path.closeSubpath()
        return path
    }

    private func verticalPath(x: CGFloat, y: CGFloat, thickness: CGFloat, height: CGFloat) -> CGPath {
        let inset = min(thickness * 0.52, height / 4)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + thickness / 2, y: y))
        path.addLine(to: CGPoint(x: x + thickness, y: y + inset))
        path.addLine(to: CGPoint(x: x + thickness, y: y + height - inset))
        path.addLine(to: CGPoint(x: x + thickness / 2, y: y + height))
        path.addLine(to: CGPoint(x: x, y: y + height - inset))
        path.addLine(to: CGPoint(x: x, y: y + inset))
        path.closeSubpath()
        return path
    }

    private func drawColon(in context: CGContext, x: CGFloat, y: CGFloat,
                                  width: CGFloat, height: CGFloat, glow: CGFloat) {
        for fraction in [0.31, 0.68] {
            let dot = CGRect(x: x + width / 2 - 7, y: y + height * fraction - 7,
                             width: 14, height: 14)
            context.saveGState()
            context.setShadow(offset: .zero, blur: 14,
                              color: palette.accent.withAlphaComponent(0.5 * glow).cgColor)
            context.setFillColor(palette.primary.withAlphaComponent(glow).cgColor)
            context.fillEllipse(in: dot)
            context.restoreGState()
        }
    }

    private func drawSideRuler(in context: CGContext, x: CGFloat, y: CGFloat,
                                      height: CGFloat, flipped: Bool) {
        context.setStrokeColor(palette.border.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(1)
        let direction: CGFloat = flipped ? -1 : 1
        for index in 0...24 {
            let tickY = y + height * CGFloat(index) / 24
            let length: CGFloat = index.isMultiple(of: 4) ? 35 : 15
            line(in: context, from: CGPoint(x: x, y: tickY),
                 to: CGPoint(x: x + direction * length, y: tickY))
        }
    }

    private func drawMeters(in context: CGContext, signalDivider: Int,
                            loadDivider: Int, compact: Bool) {
        drawMeter(in: context, frame: CGRect(x: 94, y: 215, width: 604, height: 133),
                  name: "SIGNAL PHASE", code: "AUX / 01",
                  divider: signalDivider,
                  accent: palette.accent, compact: compact)
        drawMeter(in: context, frame: CGRect(x: 742, y: 215, width: 604, height: 133),
                  name: "SYSTEM LOAD", code: "AUX / 02",
                  divider: loadDivider,
                  accent: palette.secondary, compact: compact)
    }

    private func drawMeter(in context: CGContext, frame: CGRect, name: String,
                            code: String, divider: Int, accent: NSColor, compact: Bool) {
        fill(in: context, frame, color: palette.panel.withAlphaComponent(0.8))
        stroke(in: context, frame, color: palette.border.withAlphaComponent(0.5), width: 1)
        label(name, x: frame.minX + 17, y: frame.maxY - 36, size: 17,
              color: accent, weight: .medium, tracking: 2)
        if !compact {
            label(code, x: frame.maxX - 119, y: frame.maxY - 34, size: 11,
                  color: palette.muted, tracking: 1.5)
        }
        let track = CGRect(x: frame.minX + 18, y: frame.minY + 39,
                           width: frame.width - 36, height: 31)
        context.setStrokeColor(palette.border.withAlphaComponent(0.46).cgColor)
        context.setLineWidth(1)
        line(in: context, from: CGPoint(x: track.minX, y: track.minY - 7),
             to: CGPoint(x: track.maxX, y: track.minY - 7))
        let count = TelemetryModel.blockCount
        let gap: CGFloat = 4
        let safeDivider = MeterGeometry.clampedDivider(divider)
        let blockWidth = (track.width - CGFloat(count - 1) * gap) / CGFloat(count)
        for index in 0..<count {
            let block = CGRect(x: track.minX + CGFloat(index) * (blockWidth + gap),
                               y: track.minY, width: blockWidth, height: track.height)
            context.setFillColor(accent.withAlphaComponent(index < safeDivider ? 0.52 : 0.10).cgColor)
            context.fill(block)
        }
        // A divider is a gap between blocks, so the marker never slides across
        // a block or passes the first/last internal divider.
        let markerX = MeterGeometry.markerX(track: track, divider: safeDivider, gap: gap)
        context.setFillColor(palette.highlight.withAlphaComponent(0.78).cgColor)
        context.fill(CGRect(x: markerX - gap / 2, y: track.minY - 5,
                            width: gap, height: track.height + 10))
    }

    private func drawFooter(in context: CGContext, date: Date, compact: Bool) {
        context.setStrokeColor(palette.accent.withAlphaComponent(0.56).cgColor)
        context.setLineWidth(1)
        line(in: context, from: CGPoint(x: 94, y: 181), to: CGPoint(x: 1346, y: 181))
        label("CLOCK SOURCE  /  SYSTEM", x: 96, y: 139, size: 14,
              color: palette.muted, tracking: 2)

        let seconds = TimeZone.autoupdatingCurrent.secondsFromGMT(for: date)
        let sign = seconds >= 0 ? "+" : "−"
        let absolute = abs(seconds)
        let offset = String(format: "UTC %@%02d:%02d", sign, absolute / 3600, (absolute % 3600) / 60)
        label(offset, x: 606, y: 139, size: 14, color: palette.secondary, tracking: 2)
        label("AT-01  /  STABLE", x: 1090, y: 139, size: 14,
              color: palette.primary, tracking: 2)
        if !compact {
            label("DISPLAY CORE  //  CONTINUOUS MODE", x: 96, y: 100, size: 11,
                  color: palette.border, tracking: 1.5)
            label("NO COUNTDOWN   •   LOCAL TIME", x: 1074, y: 100, size: 11,
                  color: palette.border, tracking: 1)
        }
    }

    private func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat,
                              color: NSColor, weight: NSFont.Weight = .regular,
                              tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .kern: tracking
        ]
        (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
    }

    private func line(in context: CGContext, from a: CGPoint, to b: CGPoint) {
        context.move(to: a)
        context.addLine(to: b)
        context.strokePath()
    }

    private func fill(in context: CGContext, _ rect: CGRect, color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(rect)
    }

    private func stroke(in context: CGContext, _ rect: CGRect, color: NSColor, width: CGFloat) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.stroke(rect)
    }
}
