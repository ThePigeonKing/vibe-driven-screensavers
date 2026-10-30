import AppKit

@main
enum HadalOutpostPreviewMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = HadalOutpostPreviewDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

private final class HadalOutpostPreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var saverView: HadalOutpostSaverView?
    private var compact = false
    private let previewKinds: [HadalCreatureKind] = [.maw, .ribbon, .medusa, .carapace, .elder]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Форпост «Надир» — предпросмотр"
        window.minSize = NSSize(width: 320, height: 220)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        installSaverView(isPreview: false)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { saverView?.stopAnimation() }
    func windowWillClose(_ notification: Notification) { saverView?.stopAnimation() }

    @objc private func showCompactPreview(_ sender: Any?) {
        window.setContentSize(NSSize(width: 420, height: 263))
        guard !compact else { return }
        compact = true
        installSaverView(isPreview: true)
    }

    @objc private func showRegularPreview(_ sender: Any?) {
        window.setContentSize(NSSize(width: 1280, height: 800))
        guard compact else { return }
        compact = false
        installSaverView(isPreview: false)
    }

    @objc private func showNaturalCycle(_ sender: Any?) {
        saverView?.artwork.model = HadalSceneModel()
        saverView?.artwork.needsDisplay = true
    }

    @objc private func showCreature(_ sender: NSMenuItem) {
        guard previewKinds.indices.contains(sender.tag), let artwork = saverView?.artwork else { return }
        artwork.model.startEncounter(kind: previewKinds[sender.tag])
        artwork.model.step(seconds: 12)
        artwork.needsDisplay = true
    }

    private func installSaverView(isPreview: Bool) {
        let previousModel = saverView?.artwork.model
        saverView?.stopAnimation()
        guard let view = HadalOutpostSaverView(frame: window.contentView?.bounds ?? .zero,
                                               isPreview: isPreview) else { return }
        if let previousModel { view.artwork.model = previousModel }
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        saverView = view
        view.startAnimation()
    }

    private func installMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main
        let applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "Форпост «Надир»")
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
        viewMenu.addItem(.separator())
        let fullScreenItem = viewMenu.addItem(withTitle: "Полный экран",
                                              action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreenItem.keyEquivalentModifierMask = [.control, .command]

        let creaturesItem = NSMenuItem()
        main.addItem(creaturesItem)
        let creaturesMenu = NSMenu(title: "Существа")
        creaturesItem.submenu = creaturesMenu
        let natural = creaturesMenu.addItem(withTitle: "Естественный цикл",
                                            action: #selector(showNaturalCycle(_:)), keyEquivalent: "0")
        natural.target = self
        creaturesMenu.addItem(.separator())
        let titles = previewKinds.map(\.title)
        for (index, title) in titles.enumerated() {
            let item = creaturesMenu.addItem(withTitle: "Показать: " + title,
                                             action: #selector(showCreature(_:)), keyEquivalent: String(index + 3))
            item.tag = index
            item.target = self
        }
    }
}
