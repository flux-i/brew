import AppKit
import IOKit.pwr_mgt
import SwiftUI

@MainActor
enum Diagnostics {
    static func automationSmoke() {
        print("Starting native automation smoke check")
        AppModel.shared.stop()
        sendScriptEvent(0x73746172, seconds: 3)
        after(0.3) {
            guard verify(AppModel.shared.isActive, "AppleScript start event") else { return }
            after(3.6) {
                guard verify(!AppModel.shared.isActive, "real timer expiry") else { return }
                sendScriptEvent(0x746F676C)
                after(0.3) {
                    guard verify(AppModel.shared.isActive, "AppleScript toggle event") else { return }
                    sendScriptEvent(0x73746F70)
                    after(0.3) {
                        guard verify(!AppModel.shared.isActive, "AppleScript stop event") else { return }
                        NSWorkspace.shared.open(URL(string: "brew://start?seconds=10")!)
                        after(0.7) {
                            guard verify(AppModel.shared.isActive, "URL start") else { return }
                            NSWorkspace.shared.open(URL(string: "brew://stop")!)
                            after(0.7) {
                                guard verify(!AppModel.shared.isActive, "URL stop") else { return }
                                print("AUTOMATION CHECKS PASSED")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                }
            }
        }
    }
    private static func after(_ seconds: TimeInterval, _ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { body() }
    }
    @discardableResult private static func verify(_ value: Bool, _ description: String) -> Bool {
        print("\(value ? "PASS" : "FAIL") \(description)")
        if !value { print("AUTOMATION CHECKS FAILED"); AppModel.shared.stop(); NSApp.terminate(nil) }
        return value
    }
    private static func sendScriptEvent(_ eventID: AEEventID, seconds: Double? = nil) {
        let event = NSAppleEventDescriptor(eventClass: 0x42726577,
            eventID: eventID, targetDescriptor: NSAppleEventDescriptor(processIdentifier: ProcessInfo.processInfo.processIdentifier),
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        if let seconds { event.setParam(NSAppleEventDescriptor(double: seconds), forKeyword: 0x64757261) }
        do { _ = try event.sendEvent(options: [.noReply], timeout: 2) }
        catch { print("FAIL AppleScript send: \(error)"); AppModel.shared.stop(); NSApp.terminate(nil) }
    }

    static func run() {
        var failures: [String] = []
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            let passed = condition()
            print("\(passed ? "PASS" : "FAIL") \(name)")
            if !passed { failures.append(name) }
        }
        let power = PowerController()
        do {
            try power.acquire(allowDisplaySleep: false, closedLid: false, timeout: 60)
            check(power.assertionIDs.count == 2, "system and display assertions acquired")
            let oldIDs = power.assertionIDs
            for id in oldIDs {
                let properties = IOPMAssertionCopyProperties(id)?.takeRetainedValue() as? [String: Any]
                check((properties?[kIOPMAssertionLevelKey] as? NSNumber)?.intValue == 255,
                    "macOS reports assertion \(id) enabled")
                check(properties?[kIOPMAssertionTimeoutKey] != nil, "OS timeout attached to assertion \(id)")
            }
            try power.acquire(allowDisplaySleep: true, closedLid: false, timeout: nil)
            check(power.assertionIDs.count == 1, "display sleep setting removes display assertion")
            check(oldIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "replacement releases old assertions")
            let activeIDs = power.assertionIDs
            power.release()
            check(power.assertionIDs.isEmpty && activeIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil },
                "session cleanup releases assertions")
            try power.acquire(allowDisplaySleep: true, closedLid: false, timeout: 1)
            let timedIDs = power.assertionIDs
            Thread.sleep(forTimeInterval: 1.4)
            check(timedIDs.allSatisfy { IOPMAssertionCopyProperties($0) == nil }, "macOS independently expires timed assertion")
            power.release()
            try power.acquire(allowDisplaySleep: true, closedLid: true, timeout: 5)
            print("INFO extended closed-lid assertion accepted: \(power.extendedProtectionAvailable); hardware behavior requires manual verification")
            power.release()
        } catch { failures.append(error.localizedDescription); print("FAIL \(error.localizedDescription)") }
        let name = "Brew.Diagnostics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let model = AppModel(defaults: defaults, power: power, monitorPower: false)
        model.start(duration: .seconds(1))
        check(model.isActive, "session activates")
        model.tick(at: Date().addingTimeInterval(2))
        check(!model.isActive && power.assertionIDs.isEmpty, "deadline deactivates session and releases protection")
        model.preferences.deactivateWhenUnplugged = true
        model.powerChanged(PowerSample(isOnAC: true, batteryPercent: 100))
        model.start()
        model.powerChanged(PowerSample(isOnAC: false, batteryPercent: 99))
        check(!model.isActive, "charger disconnect ends session")
        check(Preferences.load(from: defaults).deactivateWhenUnplugged, "preferences persist")
        let key = GlobalHotKey()
        check(key.register(Shortcut(keyCode: 64, modifiers: 256 | 2048, keyLabel: "F17"), enabled: true), "global shortcut registers")
        check(key.register(Shortcut(keyCode: 79, modifiers: 256 | 2048, keyLabel: "F18"), enabled: true), "global shortcut can be changed")
        check(key.register(Shortcut(), enabled: false), "global shortcut can be disabled")
        print("\(failures.isEmpty ? "ALL CHECKS PASSED" : "CHECKS FAILED") (\(failures.count) failures)")
        if !failures.isEmpty { exit(1) }
    }

    static func render(to directory: String) {
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        catch { print("Cannot create preview directory: \(error)"); exit(1) }
        let name = "Brew.Preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let mock = PreviewPower()
        let model = AppModel(defaults: defaults, power: mock, monitorPower: false)
        model.preferences.defaultDuration = .seconds(3600)
        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            model.stop()
            snapshot(PopoverView(model: model), appearance: appearance,
                to: url.appendingPathComponent("brew-idle-\(suffix).png"))
            let date = Date()
            model.start(duration: .seconds(3600), at: date.addingTimeInterval(-854))
            model.tick(at: date)
            snapshot(PopoverView(model: model), appearance: appearance,
                to: url.appendingPathComponent("brew-active-\(suffix).png"))
            snapshot(PopoverView(model: model, initiallyShowCustom: true), appearance: appearance,
                to: url.appendingPathComponent("brew-custom-\(suffix).png"))
            for tab in SettingsTab.allCases {
                snapshot(SettingsView(model: model, login: LoginItem(), initialTab: tab), appearance: appearance,
                    to: url.appendingPathComponent("brew-settings-\(tab.rawValue.lowercased())-\(suffix).png"))
            }
            snapshot(AboutView(), appearance: appearance, to: url.appendingPathComponent("brew-about-\(suffix).png"))
        }
        model.stop()
        print("Rendered native previews to \(directory)")
    }
    private static func snapshot<V: View>(_ view: V, appearance: NSAppearance.Name, to url: URL) {
        let hosting = NSHostingView(rootView: view.environment(\.controlActiveState, .key).background(Color(nsColor: .windowBackgroundColor)))
        hosting.appearance = NSAppearance(named: appearance)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = hosting.appearance
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))
        hosting.displayIfNeeded()
        capture(hosting, to: url)
        window.orderOut(nil)
    }
    static func capture(_ view: NSView, to url: URL) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            print("Snapshot failed: \(url.lastPathComponent)"); exit(1)
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        do { try bitmap.representation(using: .png, properties: [:])?.write(to: url) }
        catch { print("Snapshot write failed: \(error)"); exit(1) }
    }
    private final class PreviewPower: SleepControlling {
        func acquire(allowDisplaySleep: Bool, closedLid: Bool, timeout: TimeInterval?) throws {}
        func release() {}
    }
}
