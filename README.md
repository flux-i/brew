# Brew

A native macOS menu bar app that keeps your Mac awake for calls, downloads, presentations, and focused work. Inspired by Caffeinated's public feature set, with independent Brew branding and original coffee artwork. SwiftUI, AppKit, and IOKit; no third-party dependencies or network service.

## Run

Download the installer or app ZIP from [GitHub Releases](https://github.com/flux-i/brew/releases/latest). The installer places Brew in `/Applications/Brew.app`; for the ZIP, unzip and drag the app into Applications. Quit an existing Brew instance before installing, then open Brew from Applications.

Release binaries currently support Apple Silicon and macOS 13 or later. The initial release uses an unsigned installer and a locally signed, unnotarized app. macOS may require approval through System Settings → Privacy & Security → Open Anyway; see [Apple's guidance](https://support.apple.com/en-us/102445).

To build locally, use the commands below and open `dist/Brew.app`. Brew appears as a coffee cup in the menu bar and has no Dock icon. On first launch it opens its control popover. Configure Launch at login in Settings if you want Brew available after signing in.

Default controls: left click opens the popover; right click or Control-click toggles the awake session; Option-click always opens the popover. The default global shortcut is **⌥⌘B**. Change or disable it in Settings → Shortcuts.

## Features

- System and display sleep prevention using IOKit power assertions.
- Infinite, 15/30/45-minute, and 1/4/8/12-hour sessions.
- Custom duration up to seven days, or a specific end date and time.
- Saved default duration; clicking the selected duration restarts an active timer.
- Live countdown and progress ring; optional countdown beside the menu bar cup.
- Allow the display to sleep while the system remains awake.
- Best-effort extended sleep protection for closed-lid use.
- Deactivate on charger disconnect, and optional activation on launch.
- Launch at login via ServiceManagement, with native approval and error state.
- Optional completion notifications and sound, requested only when enabled.
- Configurable left/right-click behavior and a recorded global keyboard shortcut.
- System/light/dark appearance; monochrome, system accent, or graphite active icon.
- AppleScript, URL automation, and native App Intents source for Shortcuts.
- Native controls, keyboard navigation, VoiceOver labels, Retina artwork, and reduced-motion support.
- Automatic power assertion release when the session ends, on quit, and on process exit. Finite sessions have an independent OS timeout.

## Automation

```applescript
tell application "Brew" to start session
tell application "Brew" to start session for seconds 3600
tell application "Brew" to stop session
tell application "Brew" to toggle
tell application "Brew" to is awake
```

```sh
open 'brew://start?seconds=3600'
open 'brew://stop'
open 'brew://toggle'
open 'brew://settings'
```

Native Shortcuts actions are **Start Brew** (optional duration in minutes), **Stop Brew**, and **Toggle Brew**. Xcode's app build extracts and embeds their App Intents metadata. A Command Line Tools build supports Shortcuts through the standard **Open URLs** action using the URLs above, but does not register native actions.

## Build and verify

Requires macOS 13 or later. Xcode 15 or later is recommended (this project was developed on macOS 27 with Swift 6.4). Xcode's license must be accepted by the Mac's owner before using Xcode tools.

```sh
# Full app build, including native Shortcuts metadata
zsh scripts/build.sh

# App build using Command Line Tools, without native Shortcuts metadata
zsh scripts/build.sh --standalone

# Installer, versioned app ZIP, and SHA-256 checksums
zsh scripts/package.sh --standalone

# Core and controller tests, using the standalone test harness
zsh scripts/test.sh

# With a licensed Xcode installation, the same tests also run with XCTest
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  swift test --disable-sandbox --scratch-path build/spm --cache-path build/cache

# Live macOS assertion, timeout, hotkey, and cleanup checks
open -n -W "$PWD/dist/Brew.app" --args --verify --report "$PWD/build/diagnostics.log"

# Render native light/dark previews of this app's views
open -n -W "$PWD/dist/Brew.app" --args --render-previews "$PWD/build/previews" --report "$PWD/build/previews.log"

# End-to-end AppleScript and URL smoke check, including real timer expiry
open -n -W "$PWD/dist/Brew.app" --args --automation-smoke --report "$PWD/build/automation.log"

# Verify the real menu bar popover and capture its own view
open -n -W "$PWD/dist/Brew.app" --args --launch-check --report "$PWD/build/launch-check.log"
```

Open `Brew.xcodeproj` to develop in Xcode. `scripts/generate_project.py` regenerates the project from the Swift source list. The build script generates the icon, signs the bundle locally, and creates `dist/Brew.zip`. For distribution to other Macs, sign and notarize with your own Apple Developer credentials.

The packaging script builds in an isolated temporary folder, then creates `dist/Brew-<version>-<architecture>.pkg`, the matching ZIP, and a checksums file. It enforces the app's macOS and architecture requirements, disables bundle relocation, and installs only into Applications. No install scripts are included. `BREW_OUTPUT_DIR` overrides the build script's output folder. Optional `BREW_CODE_SIGN_IDENTITY` and `BREW_INSTALLER_SIGN_IDENTITY` select installed app and installer signing certificates; notarization is a separate step.

## Verified on this Mac

17 core tests (58 assertions) passed. Live diagnostics verified system/display assertions, live reconfiguration, OS timeout, release, charger-transition behavior, preference persistence, and hotkey registration/change/disable. Native automation smoke verified AppleScript events, real timer expiry, and URL start/stop. The actual menu bar popover launch passed, and native light/dark previews were inspected. The status icon renders white in dark mode and black in light mode, and closing Settings leaves the menu bar item running. Validation commands generate logs and previews under the locally ignored `build/` directory.

The locally verified app uses the standalone build. Native Shortcuts metadata remains pending Xcode license acceptance; AppleScript and URL-based Shortcuts are available. App bundles and build outputs are generated locally and are not committed to this repository.

## Practical limits

macOS can still sleep after an explicit Sleep command, thermal emergency, depleted battery, or lid closure. Closed-lid mode requests an additional `PreventSystemSleep` assertion when the OS accepts it; it cannot guarantee operation on every Mac. It does not change global power settings or require administrator privileges. Physical lid behavior, login-item launch after logout, and notification delivery depend on the target Mac's configuration and should be checked there.

The interface is currently English. This is an independent implementation based on the publicly documented controls, not a claim of pixel-for-pixel or every-language parity with the commercial app.

## Reference

[Caffeinated website](https://caffeinated.app/), [public support controls](https://caffeinated.app/helpcenter/), and [App Store feature list and changelog](https://apps.apple.com/us/app/caffeinated-anti-sleep-app/id1362171212?mt=12). Apple power behavior is documented in the installed SDK's `IOPMLib.h` and [IOKit assertion documentation](https://developer.apple.com/documentation/iokit/1557078-iopmassertioncreatewithdescripti).
