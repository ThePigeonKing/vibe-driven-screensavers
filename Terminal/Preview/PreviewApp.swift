import AppKit

@main
enum PreviewMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = PreviewApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

private final class PreviewApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var saverView: AlarmTerminalSaverView?
    private var compact = false
    private var themeItems: [TerminalTheme: NSMenuItem] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()

        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1100, height: 690),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Тревожный терминал — предпросмотр"
        window.minSize = NSSize(width: 360, height: 240)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        installSaverView(isPreview: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        saverView?.stopAnimation()
    }

    func windowWillClose(_ notification: Notification) {
        saverView?.stopAnimation()
    }

    @objc private func showCompactPreview(_ sender: Any?) {
        guard !compact else { return }
        compact = true
        window.setContentSize(NSSize(width: 420, height: 263))
        installSaverView(isPreview: true)
    }

    @objc private func showRegularPreview(_ sender: Any?) {
        guard compact else { return }
        compact = false
        window.setContentSize(NSSize(width: 1100, height: 690))
        installSaverView(isPreview: false)
    }

    private func installSaverView(isPreview: Bool) {
        saverView?.stopAnimation()
        let view = AlarmTerminalSaverView(frame: window.contentView?.bounds ?? .zero,
                                          isPreview: isPreview)!
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        saverView = view
        view.startAnimation()
        updateThemeMenu()
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let theme = TerminalTheme(rawValue: rawValue) else { return }
        saverView?.theme = theme
        updateThemeMenu()
    }

    private func updateThemeMenu() {
        for (theme, item) in themeItems {
            item.state = saverView?.theme == theme ? .on : .off
        }
    }

    private func installMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main

        let applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "Тревожный терминал")
        applicationItem.submenu = applicationMenu
        applicationMenu.addItem(withTitle: "Завершить предпросмотр",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "Вид")
        viewItem.submenu = viewMenu
        let compactItem = viewMenu.addItem(withTitle: "Маленький предпросмотр",
                                           action: #selector(showCompactPreview(_:)), keyEquivalent: "1")
        compactItem.target = self
        let regularItem = viewMenu.addItem(withTitle: "Обычное окно",
                                           action: #selector(showRegularPreview(_:)), keyEquivalent: "2")
        regularItem.target = self
        viewMenu.addItem(NSMenuItem.separator())
        let fullScreenItem = viewMenu.addItem(withTitle: "Полный экран",
                                              action: #selector(NSWindow.toggleFullScreen(_:)),
                                              keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.control, .command]

        let themeItem = NSMenuItem()
        main.addItem(themeItem)
        let themeMenu = NSMenu(title: "Палитра")
        themeItem.submenu = themeMenu
        for (index, theme) in TerminalTheme.allCases.enumerated() {
            let item = themeMenu.addItem(withTitle: theme.title,
                                         action: #selector(selectTheme(_:)),
                                         keyEquivalent: String(index + 3))
            item.target = self
            item.representedObject = theme.rawValue
            themeItems[theme] = item
        }
    }
}
