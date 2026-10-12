import AppKit
import Combine

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel(notifier: Notifications())
    @Published var preferences: Preferences {
        didSet {
            preferences.save(to: defaults)
            if session != nil && (preferences.allowDisplaySleep != oldValue.allowDisplaySleep ||
                preferences.keepAwakeWithLidClosed != oldValue.keepAwakeWithLidClosed) {
                refreshProtection()
            }
        }
    }
    @Published private(set) var session: BrewSession?
    @Published private(set) var now = Date()
    @Published private(set) var powerSample: PowerSample
    @Published var error: String?
    @Published private(set) var lastMessage: String?
    let defaults: UserDefaults
    private let power: SleepControlling
    private let notifier: SessionNotifying?
    private var timer: Timer?
    private var monitor: PowerMonitor?
    private var activity: NSObjectProtocol?
    private var lastAC: Bool?
    var isActive: Bool { session != nil }
    var countdown: String { session?.countdown(at: now) ?? preferences.defaultDuration.label }
    var progress: Double { session?.progress(at: now) ?? 0 }
    var extendedProtectionAvailable: Bool { (power as? PowerController)?.extendedProtectionAvailable ?? false }

    init(defaults: UserDefaults = .standard, power: SleepControlling = PowerController(),
         notifier: SessionNotifying? = nil, monitorPower: Bool = true) {
        self.defaults = defaults
        self.power = power
        self.notifier = notifier
        preferences = Preferences.load(from: defaults)
        powerSample = PowerSample.read()
        lastAC = powerSample.isOnAC
        if monitorPower {
            monitor = PowerMonitor()
            monitor?.onChange = { [weak self] sample in self?.powerChanged(sample) }
        }
    }
    func toggle() { isActive ? stop() : start() }
    func start(duration: BrewDuration? = nil, at date: Date = Date()) {
        let selected = duration ?? preferences.defaultDuration
        guard selected.isValid else {
            error = "Choose a duration from 1 second to 7 days."
            return
        }
        do {
            try power.acquire(allowDisplaySleep: preferences.allowDisplaySleep,
                closedLid: preferences.keepAwakeWithLidClosed, timeout: selected.seconds)
            now = date
            session = BrewSession(startedAt: date, duration: selected)
            lastMessage = nil
            error = nil
            timer?.invalidate()
            timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            RunLoop.main.add(timer!, forMode: .common)
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep],
                    reason: "Brew awake session")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
    func select(_ duration: BrewDuration) {
        guard duration.isValid else { return }
        preferences.defaultDuration = duration
        if isActive { start(duration: duration) }
    }
    func stop(message: String? = nil, notify: Bool = false) {
        let wasActive = isActive
        timer?.invalidate()
        timer = nil
        power.release()
        session = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        lastMessage = message
        error = nil
        if wasActive && notify && preferences.notifyWhenFinished {
            notifier?.finished(reason: message ?? "Your Mac can sleep normally again.", sound: preferences.notificationSound)
        }
    }
    func tick(at date: Date = Date()) {
        now = date
        if session?.hasExpired(at: date) == true {
            stop(message: "Time’s up. Your Mac can rest.", notify: true)
        }
    }
    func powerChanged(_ sample: PowerSample) {
        powerSample = sample
        if PowerTransition.shouldStop(previousAC: lastAC, currentAC: sample.isOnAC,
                                      preference: preferences.deactivateWhenUnplugged) && isActive {
            stop(message: "Charger disconnected. Session ended.", notify: true)
        }
        lastAC = sample.isOnAC
    }
    private func refreshProtection() {
        guard let session else { return }
        if session.hasExpired(at: Date()) { tick(); return }
        do {
            try power.acquire(allowDisplaySleep: preferences.allowDisplaySleep,
                closedLid: preferences.keepAwakeWithLidClosed, timeout: session.remaining(at: Date()))
        } catch {
            stop()
            self.error = error.localizedDescription
        }
    }
    func handle(_ command: AutomationCommand) {
        switch command {
        case .start(let duration): start(duration: duration)
        case .stop: stop()
        case .toggle: toggle()
        case .settings: (NSApp.delegate as? AppDelegate)?.showSettings()
        }
    }
}
