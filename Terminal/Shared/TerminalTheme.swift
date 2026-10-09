import AppKit

enum TerminalTheme: String, CaseIterable {
    case amber
    case arctic
    case phosphor
    case violet

    var title: String {
        switch self {
        case .amber: "Янтарная"
        case .arctic: "Полярная"
        case .phosphor: "Фосфорная"
        case .violet: "Сумеречная"
        }
    }

    var palette: TerminalPalette {
        switch self {
        case .amber:
            TerminalPalette(background: 0x060908, panel: 0x0C0E0C,
                            primary: 0xFFAB40, highlight: 0xFFD685,
                            accent: 0xC75724, secondary: 0x649F75,
                            border: 0x7D5C38, muted: 0x948A6E)
        case .arctic:
            TerminalPalette(background: 0x071016, panel: 0x0B1A20,
                            primary: 0x69D5E9, highlight: 0xC4F4FF,
                            accent: 0x368EB5, secondary: 0x68C8A9,
                            border: 0x346775, muted: 0x78919A)
        case .phosphor:
            TerminalPalette(background: 0x061008, panel: 0x0A170E,
                            primary: 0x95DB78, highlight: 0xD8FFB9,
                            accent: 0x5FA552, secondary: 0xC4AC61,
                            border: 0x4B7045, muted: 0x81917A)
        case .violet:
            TerminalPalette(background: 0x100A16, panel: 0x190F20,
                            primary: 0xCDA6F3, highlight: 0xF1DFFF,
                            accent: 0x9D69C8, secondary: 0x70C6BB,
                            border: 0x70527D, muted: 0x96819E)
        }
    }
}

struct TerminalPalette {
    let background: NSColor
    let panel: NSColor
    let primary: NSColor
    let highlight: NSColor
    let accent: NSColor
    let secondary: NSColor
    let border: NSColor
    let muted: NSColor

    init(background: UInt32, panel: UInt32, primary: UInt32, highlight: UInt32,
         accent: UInt32, secondary: UInt32, border: UInt32, muted: UInt32) {
        self.background = Self.color(background)
        self.panel = Self.color(panel)
        self.primary = Self.color(primary)
        self.highlight = Self.color(highlight)
        self.accent = Self.color(accent)
        self.secondary = Self.color(secondary)
        self.border = Self.color(border)
        self.muted = Self.color(muted)
    }

    private static func color(_ rgb: UInt32) -> NSColor {
        NSColor(calibratedRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1)
    }
}
