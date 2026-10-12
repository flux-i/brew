import Foundation
import IOKit.pwr_mgt

protocol SleepControlling: AnyObject {
    func acquire(allowDisplaySleep: Bool, closedLid: Bool, timeout: TimeInterval?) throws
    func release()
}

final class PowerController: SleepControlling {
    private(set) var assertionIDs: [IOPMAssertionID] = []
    private(set) var extendedProtectionAvailable = false

    // Acquire replacements before releasing old assertions, avoiding an unprotected gap.
    func acquire(allowDisplaySleep: Bool, closedLid: Bool, timeout: TimeInterval?) throws {
        var replacements: [IOPMAssertionID] = []
        do {
            replacements.append(try create(type: kIOPMAssertPreventUserIdleSystemSleep, timeout: timeout))
            if !allowDisplaySleep {
                replacements.append(try create(type: kIOPMAssertPreventUserIdleDisplaySleep, timeout: timeout))
            }
        } catch {
            replacements.forEach { IOPMAssertionRelease($0) }
            throw error
        }
        extendedProtectionAvailable = false
        if closedLid {
            // The OS may accept this extended assertion, but its clamshell policy still wins.
            // It is deliberately optional: unsupported extended protection must not break idle protection.
            if let id = try? create(type: "PreventSystemSleep", timeout: timeout) {
                replacements.append(id)
                extendedProtectionAvailable = true
            }
        }
        release()
        assertionIDs = replacements
    }

    private func create(type: String, timeout: TimeInterval?) throws -> IOPMAssertionID {
        var properties: [String: Any] = [
            kIOPMAssertionTypeKey: type,
            kIOPMAssertionNameKey: "Brew — keep Mac awake",
            kIOPMAssertionLevelKey: kIOPMAssertionLevelOn,
            kIOPMAssertionDetailsKey: "User-requested awake session"
        ]
        if let timeout {
            properties[kIOPMAssertionTimeoutKey] = max(1, timeout)
            properties[kIOPMAssertionTimeoutActionKey] = kIOPMAssertionTimeoutActionRelease
        }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithProperties(properties as CFDictionary, &id)
        guard result == kIOReturnSuccess else { throw PowerError(code: result) }
        return id
    }
    func release() {
        assertionIDs.forEach { IOPMAssertionRelease($0) }
        assertionIDs.removeAll()
    }
    deinit { release() }

    struct PowerError: LocalizedError {
        let code: IOReturn
        var errorDescription: String? { "macOS could not start sleep prevention (\(code)). Try starting the session again." }
    }
}
