import Foundation

enum BrewDuration: Equatable, Codable {
    case indefinitely
    case seconds(TimeInterval)

    static let presets: [BrewDuration] = [.indefinitely, .seconds(900), .seconds(1800),
        .seconds(2700), .seconds(3600), .seconds(14400), .seconds(28800), .seconds(43200)]
    static let maximum: TimeInterval = 7 * 24 * 3600

    var seconds: TimeInterval? {
        if case let .seconds(value) = self { return value }
        return nil
    }
    var isValid: Bool {
        guard let value = seconds else { return true }
        return value.isFinite && value >= 1 && value <= Self.maximum
    }
    var label: String {
        guard let value = seconds else { return "Indefinitely" }
        let total = Int(value)
        if total < 60 { return "\(total) sec" }
        if total % 3600 == 0 { return "\(total / 3600) hr" }
        if total < 3600 { return "\(total / 60) min" }
        return "\(total / 3600) hr \((total % 3600) / 60) min"
    }
    var chipLabel: String {
        guard let value = seconds else { return "∞" }
        return value < 3600 ? "\(Int(value / 60))m" : "\(Int(value / 3600))h"
    }
}

struct BrewSession: Equatable {
    let startedAt: Date
    let duration: BrewDuration
    var deadline: Date? { duration.seconds.map { startedAt.addingTimeInterval($0) } }
    func remaining(at date: Date) -> TimeInterval? {
        deadline.map { max(0, $0.timeIntervalSince(date)) }
    }
    func hasExpired(at date: Date) -> Bool { deadline.map { date >= $0 } ?? false }
    func progress(at date: Date) -> Double {
        guard let total = duration.seconds, total > 0 else { return 1 }
        return min(1, max(0, (remaining(at: date) ?? 0) / total))
    }
    func countdown(at date: Date) -> String {
        guard let remaining = remaining(at: date) else { return "No time limit" }
        let seconds = Int(ceil(remaining))
        if seconds >= 3600 {
            return String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

enum AppearanceChoice: String, Codable, CaseIterable {
    case system, light, dark
    var label: String { rawValue.capitalized }
}
enum IconColorChoice: String, Codable, CaseIterable {
    case monochrome, accent, graphite
    var label: String { rawValue.capitalized }
}

struct Shortcut: Equatable, Codable {
    var keyCode: UInt32 = 11 // B
    var modifiers: UInt32 = 256 | 2048 // command + option (Carbon)
    var keyLabel: String = "B"
    var label: String {
        var result = ""
        if modifiers & 4096 != 0 { result += "⌃" }
        if modifiers & 2048 != 0 { result += "⌥" }
        if modifiers & 512 != 0 { result += "⇧" }
        if modifiers & 256 != 0 { result += "⌘" }
        return result + keyLabel
    }
}

struct Preferences: Equatable, Codable {
    var defaultDuration: BrewDuration = .indefinitely
    var allowDisplaySleep = false
    var keepAwakeWithLidClosed = false
    var deactivateWhenUnplugged = false
    var activateOnLaunch = false
    var activateWithLeftClick = false
    var notifyWhenFinished = false
    var notificationSound = false
    var showCountdownInMenuBar = false
    var shortcutEnabled = true
    var shortcut = Shortcut()
    var appearance: AppearanceChoice = .system
    var iconColor: IconColorChoice = .accent

    static func load(from defaults: UserDefaults) -> Preferences {
        guard let data = defaults.data(forKey: "preferences.v1"),
              var value = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        if !value.defaultDuration.isValid { value.defaultDuration = .indefinitely }
        return value
    }
    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "preferences.v1")
    }
}

enum AutomationCommand: Equatable {
    case start(BrewDuration?)
    case stop
    case toggle
    case settings

    static func parse(_ url: URL) throws -> AutomationCommand {
        guard url.scheme?.lowercased() == "brew", let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw CommandError.invalidURL
        }
        switch host {
        case "start":
            let values = (components.queryItems ?? []).filter { $0.name == "seconds" }
            guard values.count <= 1 else { throw CommandError.invalidDuration }
            guard let item = values.first else { return .start(nil) }
            guard let text = item.value, let seconds = Double(text), BrewDuration.seconds(seconds).isValid else {
                throw CommandError.invalidDuration
            }
            return .start(.seconds(seconds))
        case "stop": return .stop
        case "toggle": return .toggle
        case "settings": return .settings
        default: throw CommandError.invalidURL
        }
    }
    enum CommandError: LocalizedError {
        case invalidURL, invalidDuration
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Use brew://start, brew://stop, brew://toggle, or brew://settings."
            case .invalidDuration: return "Duration must be between 1 second and 7 days."
            }
        }
    }
}

struct PowerTransition {
    static func shouldStop(previousAC: Bool?, currentAC: Bool, preference: Bool) -> Bool {
        preference && previousAC == true && !currentAC
    }
}
