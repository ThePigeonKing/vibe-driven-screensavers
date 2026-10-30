import AppKit

@main
enum LivingIslandPreviewMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = IslandPreviewDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

private final class IslandPreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var saver: LivingIslandSaverView?
    private var compact = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Самостроящийся мир — предпросмотр"
        window.minSize = NSSize(width: 320, height: 220)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        installView(preview: false)
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { saver?.stopAnimation() }
    func windowWillClose(_ notification: Notification) { saver?.stopAnimation() }

    @objc private func compactView(_ sender: Any?) {
        window.setContentSize(NSSize(width: 420, height: 263))
        guard !compact else { return }
        compact = true; installView(preview: true)
    }
    @objc private func regularView(_ sender: Any?) {
        window.setContentSize(NSSize(width: 1200, height: 800))
        guard compact else { return }
        compact = false; installView(preview: false)
    }
    @objc private func newIsland(_ sender: Any?) {
        saver?.artwork.model = IslandSceneModel()
        saver?.artwork.needsDisplay = true
    }

    private func installView(preview: Bool) {
        let previous = saver?.artwork.model
        saver?.stopAnimation()
        guard let view = LivingIslandSaverView(frame: window.contentView?.bounds ?? .zero, isPreview: preview) else { return }
        if let previous { view.artwork.model = previous }
        view.autoresizingMask = [.width, .height]
        window.contentView = view; saver = view
        view.startAnimation()
    }

    private func installMenu() {
        let root = NSMenu(); NSApp.mainMenu = root
        let appItem = NSMenuItem(); root.addItem(appItem)
        let app = NSMenu(title: "Самостроящийся мир"); appItem.submenu = app
        app.addItem(withTitle: "Завершить предпросмотр", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let viewItem = NSMenuItem(); root.addItem(viewItem)
        let menu = NSMenu(title: "Вид"); viewItem.submenu = menu
        let small = menu.addItem(withTitle: "Маленький предпросмотр", action: #selector(compactView(_:)), keyEquivalent: "1")
        small.target = self
        let regular = menu.addItem(withTitle: "Обычное окно", action: #selector(regularView(_:)), keyEquivalent: "2")
        regular.target = self
        let regenerate = menu.addItem(withTitle: "Новый остров", action: #selector(newIsland(_:)), keyEquivalent: "3")
        regenerate.target = self
        menu.addItem(.separator())
        let full = menu.addItem(withTitle: "Полный экран", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.control, .command]
    }
}
