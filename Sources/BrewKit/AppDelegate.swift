import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel.shared
    private let popover = NSPopover()
    private let hotkey = GlobalHotKey()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var hosting: NSHostingController<PopoverView>?
    private let login = LoginItem()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--cleanup-brew") {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: "app.local.brew")
                where app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                print("Closing Brew QA instance \(app.processIdentifier): \(app.terminate())")
            }
            NSApp.terminate(nil)
            return
        }
        debugLog("Application finished launching")
        if CommandLine.arguments.contains("--verify") {
            Diagnostics.run()
            NSApp.terminate(nil)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-previews"),
           CommandLine.arguments.indices.contains(index + 1) {
            Diagnostics.render(to: CommandLine.arguments[index + 1])
            NSApp.terminate(nil)
            return
        }
        NSApp.setActivationPolicy(.accessory)
        configureMainMenu()
        debugLog("Main menu configured")
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Brew"
        item.isVisible = true
        statusItem = item
        debugLog("Status item created")
        item.button?.target = self
        item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.button?.setAccessibilityLabel("Brew — keep Mac awake")
        hosting = NSHostingController(rootView: PopoverView(model: model,
            showSettings: { [weak self] in self?.showSettings() },
            showAbout: { [weak self] in self?.showAbout() },
            quit: { NSApp.terminate(nil) }))
        popover.contentViewController = hosting
        debugLog("Popover created")
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentSize = NSSize(width: 360, height: 476)
        hotkey.onPress = { [weak self] in self?.model.toggle() }
        model.$preferences.removeDuplicates().sink { [weak self] preferences in
            // @Published emits before assignment. Defer rendering until the model holds the new value.
            DispatchQueue.main.async { self?.preferencesChanged(preferences) }
        }.store(in: &cancellables)
        model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatusItem(); self?.resizePopover() }
        }.store(in: &cancellables)
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.model.tick()
                    self?.model.powerChanged(PowerSample.read())
                }
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSColor.systemColorsDidChangeNotification,
            object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateStatusItem() }
            })
        _ = NSScriptSuiteRegistry.shared()
        debugLog("Automation handlers registered")
        updateStatusItem()
        if CommandLine.arguments.contains("--automation-smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                Diagnostics.automationSmoke()
            }
            return
        }
        if CommandLine.arguments.contains("--launch-check") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else { return }
                self.showPopover()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let valid = self.popover.isShown && self.statusItem?.button?.image != nil &&
                        self.hosting?.view.bounds.width == 360 && (self.hosting?.view.bounds.height ?? 0) > 450
                    print(valid ? "PASS actual menu bar icon and popover launch" : "FAIL actual popover launch")
                    if let view = self.hosting?.view, let reportIndex = CommandLine.arguments.firstIndex(of: "--report"),
                       CommandLine.arguments.indices.contains(reportIndex + 1) {
                        let path = URL(fileURLWithPath: CommandLine.arguments[reportIndex + 1])
                            .deletingLastPathComponent().appendingPathComponent("brew-live-popover.png")
                        Diagnostics.capture(view, to: path)
                    }
                    self.popover.performClose(nil)
                    self.showSettings()
                    self.settingsWindow?.close()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        let persistent = self.statusItem?.isVisible == true && self.statusItem?.button?.image != nil
                        print(persistent ? "PASS menu bar item survives closing popup and Settings" : "FAIL menu bar persistence")
                        if let button = self.statusItem?.button,
                           let reportIndex = CommandLine.arguments.firstIndex(of: "--report"),
                           CommandLine.arguments.indices.contains(reportIndex + 1) {
                            let directory = URL(fileURLWithPath: CommandLine.arguments[reportIndex + 1]).deletingLastPathComponent()
                            let previous = button.appearance
                            print("Menu icon: appearance=\(previous?.name.rawValue ?? "system"), macOS=\(UserDefaults.standard.string(forKey: "AppleInterfaceStyle") ?? "Light")")
                            Diagnostics.capture(button, to: directory.appendingPathComponent("brew-status-system.png"))
                            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                                button.appearance = NSAppearance(named: appearance)
                                self.updateStatusItem()
                                button.displayIfNeeded()
                                Diagnostics.capture(button, to: directory.appendingPathComponent("brew-status-\(name).png"))
                            }
                            button.appearance = previous
                            self.updateStatusItem()
                        }
                        NSApp.terminate(nil)
                    }
                }
            }
            return
        }
        if model.preferences.activateOnLaunch { model.start() }
        let firstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunched")
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        if (firstLaunch || CommandLine.arguments.contains("--show")) && !CommandLine.arguments.contains("--background") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.showPopover() }
        }
    }
    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        hotkey.register(model.preferences.shortcut, enabled: false)
        if let item = statusItem { NSStatusBar.system.removeStatusItem(item) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { login.refresh() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showPopover() }
        return true
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            do { model.handle(try AutomationCommand.parse(url)) }
            catch { model.error = error.localizedDescription; showPopover() }
        }
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { showPopover(); return }
        if event.modifierFlags.contains(.option) { togglePopover(); return }
        let secondary = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        let shouldToggle = model.preferences.activateWithLeftClick ? !secondary : secondary
        if shouldToggle { model.toggle() }
        else { togglePopover() }
    }
    private func togglePopover() { popover.isShown ? popover.performClose(nil) : showPopover() }
    func showPopover() {
        guard let button = statusItem?.button else { return }
        resizePopover()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }
    func resizePopover() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let hosting = self.hosting else { return }
            hosting.view.layoutSubtreeIfNeeded()
            self.popover.contentSize = NSSize(width: 360, height: hosting.view.fittingSize.height)
        }
    }
    private func preferencesChanged(_ preferences: Preferences) {
        switch preferences.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if !hotkey.register(preferences.shortcut, enabled: preferences.shortcutEnabled) {
            model.error = hotkey.error
        } else if model.error == "This shortcut is already in use. Record another combination." {
            model.error = nil
        }
        updateStatusItem()
    }
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        // Menu bar contrast follows macOS, independently of Brew's window theme.
        let dark = button.appearance.map { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
            ?? (UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark")
        var foreground: NSColor = dark ? .white : .black
        if model.isActive {
            switch model.preferences.iconColor {
            case .accent: foreground = .controlAccentColor
            case .graphite: foreground = (dark ? NSColor.white : .black).withAlphaComponent(0.75)
            case .monochrome: break
            }
        }
        button.image = StatusIcon.image(active: model.isActive, foreground: foreground)
        button.appearsDisabled = false
        button.contentTintColor = nil
        button.title = model.isActive && model.preferences.showCountdownInMenuBar && model.session?.deadline != nil
            ? " " + model.countdown : ""
        button.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        button.imagePosition = .imageLeading
        button.toolTip = model.isActive ? "Brew is keeping your Mac awake — \(model.countdown)" : "Brew — ready when you are"
    }
    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(model: model, login: login))
            settingsWindow = makeWindow(title: "Brew Settings", controller: controller)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
        login.refresh()
    }
    func showAbout() {
        popover.performClose(nil)
        if aboutWindow == nil {
            aboutWindow = makeWindow(title: "About Brew", controller: NSHostingController(rootView: AboutView()))
        }
        NSApp.activate(ignoringOtherApps: true)
        aboutWindow?.makeKeyAndOrderFront(nil)
    }
    private func makeWindow<T: View>(title: String, controller: NSHostingController<T>) -> NSWindow {
        let window = NSWindow(contentViewController: controller)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
    private func configureMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Brew")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Brew", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"),
                                   ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(NSMenuItem(title: title, action: Selector(action), keyEquivalent: key))
        }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
    private func debugLog(_ message: String) {
        if CommandLine.arguments.contains("--automation-smoke") { print(message) }
    }
}

// Retain the delegate for the complete application lifetime (NSApplication.delegate is weak).
@MainActor private var retainedDelegate: AppDelegate?
@MainActor public func runBrew() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    retainedDelegate = delegate
    app.delegate = delegate
    app.run()
}
