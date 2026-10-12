# Brew implementation checklist

Build a native macOS menu bar sleep-prevention app, inspired by Caffeinated's public interface and features. User instruction “Start” authorizes implementation. This is a new project isolated from existing workspace projects.

Assumptions: SwiftUI + AppKit; macOS 13 or later; independent Brew branding; offline operation; no paid dependencies. Use the supplied global AGENTS.md agreement, native platform controls, SF Symbols, semantic colors, VoiceOver labels, and reduced-motion support. Closed-lid protection is best effort and must describe the OS limitation.

- [x] Add session and command models in `Sources/BrewKit/Session.swift`; verify preset/custom duration, deadline expiry, restart, and URL validation in Swift tests.
- [x] Add IOKit assertion management in `PowerController.swift`; verify system/display assertions, live reconfiguration, finite OS timeout, and release with the app's diagnostic mode.
- [x] Add persisted preferences, notifications, power-source monitoring, and login-item support in `AppModel.swift` and `Services.swift`; verify persistence and power-transition logic with tests and diagnostic checks.
- [x] Add the menu bar icon and click behavior in `AppDelegate.swift`; verify launch, popover, configurable click behavior, global hotkey registration, and shutdown cleanup.
- [x] Add compact popover, custom duration form, settings, and About in `Views.swift`; render and inspect native light/dark images.
- [x] Add configurable keyboard recording in `HotKey.swift`; verify changing and disabling registration and error feedback.
- [x] Add App Intents definitions, AppleScript command classes, and URL actions in `Automation.swift`; source compiles and native AppleScript/URL event smoke passes against the running app.
- [ ] Extract native App Intents metadata using the Xcode app build after the owner accepts its license; verify actions appear in Shortcuts.
- [x] Add a reproducible Xcode project, Swift package, build script, app icon, and usage README; verify release app bundle, code signature, and packaged archive.

Research: https://caffeinated.app/, https://caffeinated.app/helpcenter/, https://apps.apple.com/us/app/caffeinated-anti-sleep-app/id1362171212?mt=12, local macOS 27 SDK IOPMLib.h and Apple PowerManagement sources. Verified Xcode 27 and Swift 6.4 are installed.

## Verification and remaining environment work

- Standalone core harness: 17 tests, 58 assertions, 0 failures (`build/core-tests.log`).
- Live macOS diagnostics: all checks passed, including independent OS timeout and assertion release (`build/diagnostics.log`). Extended closed-lid assertion is accepted on this Mac; physical lid behavior remains hardware-dependent.
- Native AppleScript event and URL smoke: start, toggle, stop, actual timer expiry, URL start, URL stop all passed (`build/automation.log`).
- Native light/dark snapshots rendered for idle, active, custom duration, all settings tabs, and About; inspected and corrected control alignment (`build/previews/`).
- Xcode project plist and scripting definition XML validate. Standalone bundle builds and passes strict local code-signature verification.
- Pending: owner must accept Xcode license to build and verify native Shortcuts metadata. URL-based Shortcuts work in the standalone bundle. XCTest is also unavailable in Command Line Tools; the same core cases pass via the standalone harness.
- Interface is English; translations and commercial pixel-for-pixel parity are not claimed.

Final UI check: actual menu bar icon and popover launch passed; captured the real popover at `build/brew-live-popover.png`. Final app is locally signed; `dist/Brew.zip` contains the standalone app bundle.

## Menu bar visibility repair

The user screenshot exposed a black inactive icon against the dark menu bar. Replaced the SF Symbol/template tint with explicit native coffee artwork and system-theme foreground colors. Added a persistent status-item name and explicit window-close behavior. Native launch QA passed after closing the popup and Settings. Pixel inspection of the actual status-button captures confirms black foreground in light mode, white in dark mode, and white in the current macOS Dark configuration. See `build/brew-status-system.png` and `build/launch-check.log`. Rebuilt, signed, and repackaged the app.

## Installer and first release

- [x] Add isolated build output support in `scripts/build.sh`; verify packaging does not replace the running development app.
- [x] Add `scripts/package.sh` and native installer resources; verify architecture/minimum macOS, non-relocatable Applications payload, and checksums.
- [x] Extract the package and ZIP, compare their payloads, validate signatures, and run core tests and live diagnostics from the packaged app.
- [ ] Push packaging source, tag `v1.0.0`, upload the PKG, ZIP, and checksums, and verify the public release and uploaded hashes.

No Developer ID identities are installed on this Mac. Publish an explicitly unsigned, unnotarized Apple Silicon release with local app signing and clear installation notes.

Release validation: `build/release-core-tests.log` reports 17 tests, 58 assertions, 0 failures. `build/release-final-1.0.0/validation.log` confirms matching payloads, version, architecture, minimum OS, fixed destination, and native Installer selection. Both extracted app signatures validate, live packaged-app diagnostics pass, and download checksums match.
