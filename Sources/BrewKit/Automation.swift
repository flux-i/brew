import AppIntents
import AppKit

struct StartBrewIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Brew"
    static var description = IntentDescription("Keep your Mac awake indefinitely or for a set number of minutes.")
    static var openAppWhenRun = true
    @Parameter(title: "Duration in minutes") var minutes: Int?
    static var parameterSummary: some ParameterSummary { Summary("Start Brew for \(\.$minutes) minutes") }
    @MainActor func perform() async throws -> some IntentResult {
        if let minutes {
            let seconds = Double(minutes) * 60
            guard BrewDuration.seconds(seconds).isValid else { throw AutomationCommand.CommandError.invalidDuration }
            AppModel.shared.start(duration: .seconds(seconds))
        } else { AppModel.shared.start(duration: .indefinitely) }
        if let error = AppModel.shared.error { throw IntentFailure(message: error) }
        return .result()
    }
}
struct StopBrewIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Brew"
    static var description = IntentDescription("End the awake session and restore normal sleep behavior.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared.stop()
        return .result()
    }
}
struct ToggleBrewIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Brew"
    static var description = IntentDescription("Toggle sleep prevention using your selected duration.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        AppModel.shared.toggle()
        if let error = AppModel.shared.error { throw IntentFailure(message: error) }
        return .result()
    }
}
struct BrewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartBrewIntent(), phrases: ["Start \(.applicationName)", "Keep my Mac awake with \(.applicationName)"],
            shortTitle: "Start Brew", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: StopBrewIntent(), phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop Brew", systemImageName: "moon")
        AppShortcut(intent: ToggleBrewIntent(), phrases: ["Toggle \(.applicationName)"],
            shortTitle: "Toggle Brew", systemImageName: "cup.and.saucer")
    }
}
struct IntentFailure: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

@objc(BrewStartSessionCommand)
final class BrewStartSessionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            let model = AppModel.shared
            if let value = evaluatedArguments?["seconds"] as? NSNumber {
                let duration = BrewDuration.seconds(value.doubleValue)
                guard duration.isValid else {
                    scriptErrorNumber = -1700
                    scriptErrorString = "Duration must be from 1 second to 7 days."
                    return nil
                }
                model.start(duration: duration)
            } else { model.start() }
            if let error = model.error {
                scriptErrorNumber = -2700
                scriptErrorString = error
            }
            return nil
        }
    }
}
@objc(BrewStopSessionCommand)
final class BrewStopSessionCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { AppModel.shared.stop() }
        return nil
    }
}
@objc(BrewToggleCommand)
final class BrewToggleCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            AppModel.shared.toggle()
            if let error = AppModel.shared.error { scriptErrorNumber = -2700; scriptErrorString = error }
        }
        return nil
    }
}
@objc(BrewIsAwakeCommand)
final class BrewIsAwakeCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated { NSNumber(value: AppModel.shared.isActive) }
    }
}
