#if canImport(XCTest)
import XCTest
@testable import BrewKit
#else
import Foundation

// The same tests run without XCTest on Macs with only Command Line Tools.
@MainActor class XCTestCase {
    func setUp() async throws {}
    func tearDown() async throws {}
}
@MainActor enum TestHarness {
    static var failures: [String] = []
    static var checks = 0
    static func check(_ passed: Bool, _ message: String, file: StaticString, line: UInt) {
        checks += 1
        if !passed { failures.append("\(file):\(line): \(message)") }
    }
}
@MainActor func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(lhs == rhs, "Expected \(lhs) == \(rhs)", file: file, line: line)
}
@MainActor func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(value, "Expected true", file: file, line: line)
}
@MainActor func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(!value, "Expected false", file: file, line: line)
}
@MainActor func XCTAssertNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(value == nil, "Expected nil", file: file, line: line)
}
@MainActor func XCTAssertNotNil<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(value != nil, "Expected non-nil", file: file, line: line)
}
@MainActor func XCTAssertGreaterThan<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(lhs > rhs, "Expected \(lhs) > \(rhs)", file: file, line: line)
}
@MainActor func XCTAssertLessThanOrEqual<T: Comparable>(_ lhs: T, _ rhs: T, file: StaticString = #filePath, line: UInt = #line) {
    TestHarness.check(lhs <= rhs, "Expected \(lhs) <= \(rhs)", file: file, line: line)
}
@MainActor func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do {
        _ = try expression()
        TestHarness.check(false, "Expected a thrown error", file: file, line: line)
    } catch { TestHarness.check(true, "", file: file, line: line) }
}

@main enum StandaloneTestRunner {
    @MainActor static func main() async throws {
        let session = SessionTests()
        let sessionTests: [(String, () throws -> Void)] = [
            ("preset durations", session.testPresetDurationsMatchReference),
            ("indefinite session", session.testInfiniteSessionDoesNotExpire),
            ("deadline and negative-time protection", session.testExactDeadlineExpiresAndNeverShowsNegativeTime),
            ("countdown formatting", session.testCountdownRoundsUpAndFormatsHours),
            ("custom duration validation", session.testCustomDurationLimitsRejectNonfiniteAndZero),
            ("deadline after wake", session.testWakeAfterDeadlineStillExpires),
            ("progress clock-change bounds", session.testProgressClampsClockChanges),
            ("URL command validation", session.testURLCommandsValidateDuration),
            ("AC transition detection", session.testDisconnectOnlyStopsOnActualACToBatteryTransition),
            ("preferences and corruption recovery", session.testPreferencesRoundTripAndCorruptDataRecovery)
        ]
        for (name, test) in sessionTests {
            let previous = TestHarness.failures.count
            try test()
            print("\(TestHarness.failures.count == previous ? "PASS" : "FAIL") \(name)")
        }
        let model = AppModelTests()
        let modelTests: [(String, () -> Void)] = [
            ("timer restart", model.testRepeatingSelectedDurationRestartsTimer),
            ("failed activation", model.testFailedStartDoesNotClaimToBeActive),
            ("single expiry notification", model.testExpiryReleasesAndNotifiesExactlyOnce),
            ("live assertion reconfiguration", model.testPreferenceChangeUpdatesAssertionsWithoutRestartingSession),
            ("reconfiguration error cleanup", model.testReconfigurationFailureStopsAndReportsError),
            ("manual stop notification behavior", model.testManualStopDoesNotNotify),
            ("manual battery activation and unplug", model.testBatteryDoesNotPreventManualActivation)
        ]
        for (name, test) in modelTests {
            try await model.setUp()
            let previous = TestHarness.failures.count
            test()
            try await model.tearDown()
            print("\(TestHarness.failures.count == previous ? "PASS" : "FAIL") \(name)")
        }
        TestHarness.failures.forEach { print("FAIL \($0)") }
        print("\(sessionTests.count + modelTests.count) tests, \(TestHarness.checks) assertions, \(TestHarness.failures.count) failures")
        if !TestHarness.failures.isEmpty { exit(1) }
    }
}
#endif

final class SessionTests: XCTestCase {
    func testPresetDurationsMatchReference() {
        XCTAssertEqual(BrewDuration.presets.compactMap(\.seconds), [900, 1800, 2700, 3600, 14400, 28800, 43200])
        XCTAssertEqual(BrewDuration.presets.first, .indefinitely)
    }
    func testInfiniteSessionDoesNotExpire() {
        let session = BrewSession(startedAt: .distantPast, duration: .indefinitely)
        XCTAssertNil(session.deadline)
        XCTAssertFalse(session.hasExpired(at: .distantFuture))
        XCTAssertEqual(session.countdown(at: Date()), "No time limit")
    }
    func testExactDeadlineExpiresAndNeverShowsNegativeTime() {
        let start = Date(timeIntervalSince1970: 100)
        let session = BrewSession(startedAt: start, duration: .seconds(60))
        XCTAssertFalse(session.hasExpired(at: start.addingTimeInterval(59.9)))
        XCTAssertTrue(session.hasExpired(at: start.addingTimeInterval(60)))
        XCTAssertEqual(session.remaining(at: start.addingTimeInterval(100)), 0)
        XCTAssertEqual(session.countdown(at: start.addingTimeInterval(100)), "00:00")
    }
    func testCountdownRoundsUpAndFormatsHours() {
        let start = Date(timeIntervalSince1970: 100)
        let session = BrewSession(startedAt: start, duration: .seconds(3661))
        XCTAssertEqual(session.countdown(at: start), "1:01:01")
        XCTAssertEqual(session.countdown(at: start.addingTimeInterval(3600.2)), "01:01")
    }
    func testCustomDurationLimitsRejectNonfiniteAndZero() {
        for seconds in [Double.nan, .infinity, -.infinity, 0, -1, 604801] {
            XCTAssertFalse(BrewDuration.seconds(seconds).isValid)
        }
        XCTAssertTrue(BrewDuration.seconds(1).isValid)
        XCTAssertTrue(BrewDuration.seconds(604800).isValid)
    }
    func testWakeAfterDeadlineStillExpires() {
        let start = Date()
        let session = BrewSession(startedAt: start, duration: .seconds(3600))
        XCTAssertTrue(session.hasExpired(at: start.addingTimeInterval(7200)))
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(7200)), 0)
    }
    func testProgressClampsClockChanges() {
        let start = Date()
        let session = BrewSession(startedAt: start, duration: .seconds(100))
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(25)), 0.75)
        XCTAssertEqual(session.progress(at: start.addingTimeInterval(-100)), 1)
    }
    func testURLCommandsValidateDuration() throws {
        XCTAssertEqual(try AutomationCommand.parse(URL(string: "brew://start?seconds=90")!), .start(.seconds(90)))
        XCTAssertEqual(try AutomationCommand.parse(URL(string: "brew://stop")!), .stop)
        XCTAssertEqual(try AutomationCommand.parse(URL(string: "brew://toggle")!), .toggle)
        XCTAssertEqual(try AutomationCommand.parse(URL(string: "brew://settings")!), .settings)
        XCTAssertEqual(try AutomationCommand.parse(URL(string: "brew://start")!), .start(nil))
        for url in ["brew://start?seconds=0", "brew://start?seconds=nan", "brew://start?seconds=900000",
                    "brew://start?seconds=1&seconds=2", "https://start", "brew://other", "brew://start?seconds="] {
            XCTAssertThrowsError(try AutomationCommand.parse(URL(string: url)!))
        }
    }
    func testDisconnectOnlyStopsOnActualACToBatteryTransition() {
        XCTAssertTrue(PowerTransition.shouldStop(previousAC: true, currentAC: false, preference: true))
        XCTAssertFalse(PowerTransition.shouldStop(previousAC: nil, currentAC: false, preference: true))
        XCTAssertFalse(PowerTransition.shouldStop(previousAC: false, currentAC: false, preference: true))
        XCTAssertFalse(PowerTransition.shouldStop(previousAC: true, currentAC: false, preference: false))
        XCTAssertFalse(PowerTransition.shouldStop(previousAC: false, currentAC: true, preference: true))
    }
    func testPreferencesRoundTripAndCorruptDataRecovery() {
        let name = "Brew.Tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var preferences = Preferences()
        preferences.defaultDuration = .seconds(5340)
        preferences.appearance = .dark
        preferences.allowDisplaySleep = true
        preferences.shortcutEnabled = false
        preferences.save(to: defaults)
        XCTAssertEqual(Preferences.load(from: defaults), preferences)
        defaults.set(Data("corrupt".utf8), forKey: "preferences.v1")
        XCTAssertEqual(Preferences.load(from: defaults), Preferences())
    }
}

@MainActor
final class AppModelTests: XCTestCase {
    private var defaults: UserDefaults!
    private var domain: String!
    private var power: MockPower!
    private var notifier: MockNotifier!
    private var model: AppModel!
    override func setUp() async throws {
        domain = "Brew.ModelTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: domain)
        power = MockPower()
        notifier = MockNotifier()
        model = AppModel(defaults: defaults, power: power, notifier: notifier, monitorPower: false)
    }
    override func tearDown() async throws {
        model.stop()
        defaults.removePersistentDomain(forName: domain)
        model = nil
    }
    func testRepeatingSelectedDurationRestartsTimer() {
        let date = Date()
        model.start(duration: .seconds(60), at: date.addingTimeInterval(-20))
        let previousDeadline = model.session?.deadline
        model.select(.seconds(60))
        XCTAssertGreaterThan(model.session!.deadline!, previousDeadline!)
        XCTAssertEqual(power.acquisitions.count, 2)
    }
    func testFailedStartDoesNotClaimToBeActive() {
        power.fail = true
        model.start()
        XCTAssertFalse(model.isActive)
        XCTAssertNotNil(model.error)
    }
    func testExpiryReleasesAndNotifiesExactlyOnce() {
        model.preferences.notifyWhenFinished = true
        let date = Date()
        model.start(duration: .seconds(60), at: date)
        model.tick(at: date.addingTimeInterval(60))
        model.tick(at: date.addingTimeInterval(61))
        XCTAssertFalse(model.isActive)
        XCTAssertEqual(power.releaseCount, 1)
        XCTAssertEqual(notifier.messages.count, 1)
    }
    func testPreferenceChangeUpdatesAssertionsWithoutRestartingSession() {
        model.start(duration: .seconds(60))
        let deadline = model.session?.deadline
        model.preferences.allowDisplaySleep = true
        XCTAssertEqual(model.session?.deadline, deadline)
        XCTAssertTrue(power.acquisitions.last!.allowDisplay)
        XCTAssertLessThanOrEqual(power.acquisitions.last!.timeout!, 60)
    }
    func testReconfigurationFailureStopsAndReportsError() {
        model.start()
        power.fail = true
        model.preferences.allowDisplaySleep = true
        XCTAssertFalse(model.isActive)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(power.releaseCount, 1)
    }
    func testManualStopDoesNotNotify() {
        model.preferences.notifyWhenFinished = true
        model.start()
        model.stop()
        XCTAssertTrue(notifier.messages.isEmpty)
    }
    func testBatteryDoesNotPreventManualActivation() {
        model.preferences.deactivateWhenUnplugged = true
        model.powerChanged(PowerSample(isOnAC: false, batteryPercent: 60))
        model.start()
        model.powerChanged(PowerSample(isOnAC: false, batteryPercent: 59))
        XCTAssertTrue(model.isActive)
        model.powerChanged(PowerSample(isOnAC: true, batteryPercent: 59))
        model.powerChanged(PowerSample(isOnAC: false, batteryPercent: 59))
        XCTAssertFalse(model.isActive)
    }
    final class MockPower: SleepControlling {
        var fail = false
        var releaseCount = 0
        var acquisitions: [(allowDisplay: Bool, closedLid: Bool, timeout: TimeInterval?)] = []
        func acquire(allowDisplaySleep: Bool, closedLid: Bool, timeout: TimeInterval?) throws {
            if fail { throw NSError(domain: "BrewTests", code: 1) }
            acquisitions.append((allowDisplaySleep, closedLid, timeout))
        }
        func release() { releaseCount += 1 }
    }
    final class MockNotifier: SessionNotifying {
        var messages: [String] = []
        func finished(reason: String, sound: Bool) { messages.append(reason) }
    }
}
