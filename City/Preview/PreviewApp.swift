import AppKit

@main
enum PixelCityPreviewMain {
    static func main() {
        let application = NSApplication.shared
        let delegate = PixelCityPreviewDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

private final class PixelCityPreviewDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var saverView: PixelCitySaverView?
    private var compact = false
    private var weatherOverride: CityWeatherPreset?
    private var weatherItems: [(NSMenuItem, CityWeatherPreset?)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Живой пиксельный город — предпросмотр"
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
        window.setContentSize(NSSize(width: 1200, height: 750))
        guard compact else { return }
        compact = false
        installSaverView(isPreview: false)
    }

    @objc private func showLiveWeather(_ sender: Any?) { selectWeather(nil) }
    @objc private func showClearWeather(_ sender: Any?) { selectWeather(.clear) }
    @objc private func showCloudyWeather(_ sender: Any?) { selectWeather(.cloudy) }
    @objc private func showRainWeather(_ sender: Any?) { selectWeather(.rain) }

    private func selectWeather(_ preset: CityWeatherPreset?) {
        weatherOverride = preset
        saverView?.weatherOverride = preset
        updateWeatherMenu()
    }

    private func updateWeatherMenu() {
        for (item, preset) in weatherItems {
            item.state = preset == weatherOverride ? .on : .off
        }
    }

    private func installSaverView(isPreview: Bool) {
        saverView?.stopAnimation()
        guard let view = PixelCitySaverView(frame: window.contentView?.bounds ?? .zero,
                                           isPreview: isPreview) else { return }
        view.autoresizingMask = [.width, .height]
        view.weatherOverride = weatherOverride
        window.contentView = view
        saverView = view
        view.startAnimation()
    }

    private func installMenu() {
        let main = NSMenu()
        NSApp.mainMenu = main
        let applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let applicationMenu = NSMenu(title: "Живой пиксельный город")
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

        let weatherItem = NSMenuItem()
        main.addItem(weatherItem)
        let weatherMenu = NSMenu(title: "Погода")
        weatherItem.submenu = weatherMenu
        let choices: [(String, Selector, String, CityWeatherPreset?)] = [
            ("Естественная смена", #selector(showLiveWeather(_:)), "0", nil),
            ("Ясная ночь", #selector(showClearWeather(_:)), "3", .clear),
            ("Облачно", #selector(showCloudyWeather(_:)), "4", .cloudy),
            ("Дождь", #selector(showRainWeather(_:)), "5", .rain)
        ]
        for (title, selector, key, preset) in choices {
            let item = weatherMenu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            item.target = self
            weatherItems.append((item, preset))
        }
        updateWeatherMenu()
    }
}
