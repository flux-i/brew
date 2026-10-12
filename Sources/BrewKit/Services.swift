import AppKit
import IOKit.ps
import ServiceManagement
import UserNotifications

@MainActor protocol SessionNotifying: AnyObject {
    func finished(reason: String, sound: Bool)
}

@MainActor
final class Notifications: NSObject, SessionNotifying, UNUserNotificationCenterDelegate {
    @Published private(set) var status: UNAuthorizationStatus = .notDetermined
    private let center = UNUserNotificationCenter.current()
    override init() {
        super.init()
        center.delegate = self
        refresh()
    }
    func refresh() {
        center.getNotificationSettings { settings in
            Task { @MainActor in self.status = settings.authorizationStatus }
        }
    }
    func request() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in
            Task { @MainActor in self.refresh() }
        }
    }
    func finished(reason: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Brew session finished"
        content.body = reason
        if sound { content.sound = .default }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

struct PowerSample {
    var isOnAC: Bool
    var batteryPercent: Int?
    static func read() -> PowerSample {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return PowerSample(isOnAC: true, batteryPercent: nil)
        }
        let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        var percent: Int?
        if let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                      let current = data[kIOPSCurrentCapacityKey] as? Int,
                      let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
                percent = min(100, max(0, current * 100 / maximum))
            }
        }
        return PowerSample(isOnAC: type != kIOPSBatteryPowerValue, batteryPercent: percent)
    }
}

@MainActor
final class PowerMonitor {
    private var source: CFRunLoopSource?
    var onChange: ((PowerSample) -> Void)?
    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { monitor.onChange?(PowerSample.read()) }
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }
    deinit {
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
    }
}

@MainActor
final class LoginItem: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var needsApproval = false
    @Published var error: String?
    init() { refresh() }
    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        needsApproval = SMAppService.mainApp.status == .requiresApproval
    }
    func setEnabled(_ value: Bool) {
        do {
            if value { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch { self.error = "Launch at login could not be changed: \(error.localizedDescription)" }
        refresh()
    }
}
