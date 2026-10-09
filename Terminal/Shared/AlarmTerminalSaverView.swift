import AppKit
import ScreenSaver

/// The same ScreenSaverView is used by the installable module and the preview app.
@objc(AlarmTerminalSaverView)
final class AlarmTerminalSaverView: ScreenSaverView {
    private let artwork = TerminalArtworkView(frame: .zero)
    private var settingsWindow: NSWindow?
    private var lastThemeCheck: TimeInterval = 0

    var theme: TerminalTheme {
        get { artwork.theme }
        set {
            artwork.theme = newValue
            TerminalPreferences.selectedTheme = newValue
        }
    }

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        configureArtwork()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureArtwork()
    }

    private func configureArtwork() {
        animationTimeInterval = 1.0 / 24.0
        artwork.theme = TerminalPreferences.selectedTheme
        artwork.autoresizingMask = [.width, .height]
        artwork.frame = bounds
        addSubview(artwork)
    }

    override func layout() {
        super.layout()
        artwork.frame = bounds
    }

    override func animateOneFrame() {
        let uptime = ProcessInfo.processInfo.systemUptime
        if uptime - lastThemeCheck >= 1 {
            lastThemeCheck = uptime
            let savedTheme = TerminalPreferences.selectedTheme
            if artwork.theme != savedTheme {
                artwork.theme = savedTheme
            }
        }
        artwork.needsDisplay = true
    }

    override var hasConfigureSheet: Bool { true }

    override var configureSheet: NSWindow? {
        if let settingsWindow { return settingsWindow }

        let sheet = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 430, height: 188),
                             styleMask: [.titled], backing: .buffered, defer: false)
        sheet.title = "Тревожный терминал"
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 430, height: 188))

        let title = NSTextField(labelWithString: "Цветовая схема")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.frame = CGRect(x: 25, y: 139, width: 380, height: 24)
        content.addSubview(title)

        let selector = NSPopUpButton(frame: CGRect(x: 25, y: 92, width: 380, height: 32),
                                    pullsDown: false)
        selector.addItems(withTitles: TerminalTheme.allCases.map(\.title))
        selector.selectItem(at: TerminalTheme.allCases.firstIndex(of: theme) ?? 0)
        selector.target = self
        selector.action = #selector(selectTheme(_:))
        content.addSubview(selector)

        let note = NSTextField(labelWithString: "Выбор сохраняется для этой заставки.")
        note.textColor = .secondaryLabelColor
        note.frame = CGRect(x: 25, y: 63, width: 380, height: 20)
        content.addSubview(note)

        let done = NSButton(title: "Готово", target: self, action: #selector(closeSettings(_:)))
        done.frame = CGRect(x: 319, y: 20, width: 86, height: 30)
        done.keyEquivalent = "\r"
        content.addSubview(done)

        sheet.contentView = content
        settingsWindow = sheet
        return sheet
    }

    @objc private func selectTheme(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard TerminalTheme.allCases.indices.contains(index) else { return }
        theme = TerminalTheme.allCases[index]
    }

    @objc private func closeSettings(_ sender: Any?) {
        guard let settingsWindow else { return }
        if let parent = settingsWindow.sheetParent {
            parent.endSheet(settingsWindow)
        } else {
            settingsWindow.close()
        }
    }
}

private enum TerminalPreferences {
    private static let defaults = ScreenSaverDefaults(
        forModuleWithName: "com.thepigeonking.vibedrivenscreensavers.AlarmTerminal"
    )
    private static let key = "terminalTheme"

    static var selectedTheme: TerminalTheme {
        get { TerminalTheme(rawValue: defaults?.string(forKey: key) ?? "") ?? .amber }
        set {
            defaults?.set(newValue.rawValue, forKey: key)
            defaults?.synchronize()
        }
    }
}
