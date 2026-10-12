import AppKit
import SwiftUI
import ServiceManagement

// Explicit alias keeps the stable property wrapper available with CLI-only SDKs.
private typealias ViewState<Value> = SwiftUI.State<Value>
import UserNotifications

struct CoffeeMark: View {
    var active: Bool
    var size: CGFloat = 60
    var body: some View {
        VStack(spacing: -size * 0.08) {
            HStack(spacing: size * 0.07) {
                ForEach(0..<3) { index in
                    Steam().stroke(style: StrokeStyle(lineWidth: max(0.8, size * 0.032), lineCap: .round))
                        .frame(width: size * 0.085, height: size * 0.23)
                        .offset(y: index == 1 ? -size * 0.04 : 0)
                }
            }.opacity(active ? 0.8 : 0.35)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.72, weight: .regular))
        }
        .foregroundStyle(active ? Color.accentColor : Color.secondary)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
    private struct Steam: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.width * 0.5, y: rect.height))
                p.addCurve(to: CGPoint(x: rect.width * 0.5, y: 0),
                    control1: CGPoint(x: -rect.width, y: rect.height * 0.6),
                    control2: CGPoint(x: rect.width * 2, y: rect.height * 0.4))
            }
        }
    }
}

struct PopoverView: View {
    @ObservedObject var model: AppModel
    var showSettings: () -> Void = {}
    var showAbout: () -> Void = {}
    var quit: () -> Void = {}
    @ViewState<Bool> private var showCustom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init(model: AppModel, showSettings: @escaping () -> Void = {}, showAbout: @escaping () -> Void = {},
         quit: @escaping () -> Void = {}, initiallyShowCustom: Bool = false) {
        self.model = model
        self.showSettings = showSettings
        self.showAbout = showAbout
        self.quit = quit
        self._showCustom = ViewState(initialValue: initiallyShowCustom)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 17)).foregroundStyle(Color.accentColor)
                Text("Brew").font(.system(size: 18, weight: .semibold))
                Spacer()
                Toggle("Keep awake", isOn: Binding(get: { model.isActive }, set: { _ in model.toggle() }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
                    .accessibilityLabel("Keep Mac awake")
                    .help("Start or end an awake session")
            }.padding(.horizontal, 22).padding(.vertical, 19)
            Divider().padding(.horizontal, 20)
            VStack(spacing: 10) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.055), lineWidth: 5)
                    Circle().trim(from: 0, to: model.isActive ? max(0.005, model.progress) : 0)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Circle().fill(Color.accentColor.opacity(model.isActive ? 0.075 : 0.025))
                        .padding(10)
                    CoffeeMark(active: model.isActive, size: 68)
                }.frame(width: 112, height: 112).padding(.bottom, 5)
                HStack(spacing: 6) {
                    Circle().fill(model.isActive ? Color.accentColor : Color.secondary.opacity(0.6))
                        .frame(width: 6, height: 6)
                    Text(model.isActive ? "Keeping your Mac awake" : "Ready when you are")
                        .font(.system(size: 13, weight: .medium))
                }
                Text(model.isActive ? model.countdown : model.preferences.defaultDuration.label)
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                    .contentTransition(.identity)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(height: 17)
            }.padding(.top, 25).padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("DURATION").font(.system(size: 10, weight: .semibold)).tracking(1.3)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { showCustom.toggle() } label: {
                        HStack(spacing: 4) {
                            Text("Custom")
                            Image(systemName: showCustom ? "chevron.up" : "plus")
                        }.font(.system(size: 11, weight: .medium))
                    }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Set a custom duration")
                }
                HStack(spacing: 6) {
                    ForEach(Array(BrewDuration.presets.enumerated()), id: \.offset) { _, duration in
                        DurationButton(duration: duration,
                            selected: model.preferences.defaultDuration == duration) { model.select(duration) }
                    }
                }
                if showCustom {
                    CustomDurationView(selected: model.preferences.defaultDuration) { duration in
                        model.select(duration)
                        showCustom = false
                    }
                }
            }.padding(.horizontal, 22).padding(.bottom, 20)
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 22).padding(.bottom, 12)
            }
            Divider().padding(.horizontal, 20)
            Button(action: showSettings) {
                HStack {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 13))
                    Text("Settings").font(.system(size: 13))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }.padding(.horizontal, 22).padding(.vertical, 16).contentShape(Rectangle())
            }.buttonStyle(.plain).keyboardShortcut(",", modifiers: .command)
            Divider().padding(.horizontal, 20)
            HStack(spacing: 14) {
                Image(systemName: model.powerSample.isOnAC ? "powerplug" : "battery.75percent")
                    .font(.system(size: 11))
                Text(powerLabel).font(.system(size: 10))
                Spacer()
                Button("About", action: showAbout).buttonStyle(.plain).font(.system(size: 11))
                Button(action: quit) { Image(systemName: "power").font(.system(size: 12)) }
                    .buttonStyle(.plain).help("Quit Brew").accessibilityLabel("Quit Brew")
                    .keyboardShortcut("q", modifiers: .command)
            }.foregroundStyle(.secondary).padding(.horizontal, 22).padding(.vertical, 14)
        }
        .frame(width: 360)
        .background(.regularMaterial)
        .onChange(of: showCustom) { _ in
            (NSApp.delegate as? AppDelegate)?.resizePopover()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.isActive)
    }
    private var subtitle: String {
        if let message = model.lastMessage { return message }
        if !model.isActive { return "Your next focus session, one click away." }
        return model.preferences.allowDisplaySleep ? "System awake · Display can sleep" : "System & display stay awake"
    }
    private var powerLabel: String {
        if model.powerSample.isOnAC { return "Connected to power" }
        return model.powerSample.batteryPercent.map { "Battery · \($0)%" } ?? "On battery"
    }
}

private struct DurationButton: View {
    let duration: BrewDuration
    let selected: Bool
    let action: () -> Void
    @ViewState<Bool> private var hovered = false
    var body: some View {
        Button(action: action) {
            Text(duration.chipLabel)
                .font(.system(size: duration.seconds == nil ? 22 : 11, weight: .semibold, design: .rounded))
                .frame(width: 34, height: 34)
                .background(selected ? Color.accentColor : Color.primary.opacity(hovered ? 0.12 : 0.055), in: Circle())
                .foregroundStyle(selected ? Color.white : Color.primary)
                .overlay(Circle().strokeBorder(Color.primary.opacity(selected ? 0 : 0.045), lineWidth: 1))
                .contentShape(Circle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel(duration.label)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help("\(duration.label)\(selected ? " — click to restart an active session" : "")")
    }
}

struct CustomDurationView: View {
    var selected: BrewDuration
    var onApply: (BrewDuration) -> Void
    @ViewState<String> private var hours = "1"
    @ViewState<String> private var minutes = "0"
    @ViewState<Bool> private var untilTime = false
    @ViewState<Date> private var endTime = Date().addingTimeInterval(3600)
    @ViewState<String?> private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Custom timer", selection: $untilTime) {
                Text("For a duration").tag(false)
                Text("Until a time").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            if untilTime {
                DatePicker("End at", selection: $endTime,
                    in: Date()...Date().addingTimeInterval(BrewDuration.maximum), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.field).font(.system(size: 12))
            } else {
                HStack(spacing: 8) {
                    TextField("Hours", text: $hours).frame(width: 44).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Custom duration hours")
                    Text("hr").foregroundStyle(.secondary)
                    TextField("Minutes", text: $minutes).frame(width: 44).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Custom duration minutes")
                    Text("min").foregroundStyle(.secondary)
                    Spacer()
                }.font(.system(size: 12))
            }
            if let error { Text(error).font(.system(size: 10)).foregroundStyle(.red) }
            Button("Use duration") {
                let seconds: Double
                if untilTime { seconds = endTime.timeIntervalSinceNow }
                else {
                    guard let h = Int(hours), let m = Int(minutes), h >= 0, h <= 168, m >= 0, m <= 59 else {
                        error = "Enter 0–168 hours and 0–59 minutes."; return
                    }
                    seconds = Double(h * 3600 + m * 60)
                }
                guard BrewDuration.seconds(seconds).isValid else {
                    error = "Choose a future duration up to 7 days."; return
                }
                onApply(.seconds(seconds))
            }.buttonStyle(.borderedProminent).controlSize(.small).frame(maxWidth: .infinity, alignment: .trailing)
        }.padding(12).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .onAppear {
                if let seconds = selected.seconds {
                    hours = "\(Int(seconds) / 3600)"; minutes = "\((Int(seconds) % 3600) / 60)"
                }
            }
    }
}

enum SettingsTab: String, CaseIterable {
    case general = "General", appearance = "Appearance", shortcuts = "Shortcuts"
    var symbol: String {
        switch self { case .general: return "gearshape"; case .appearance: return "paintpalette"; case .shortcuts: return "command" }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var login: LoginItem
    @ViewState<SettingsTab> private var tab: SettingsTab = .general
    @ViewState<UNAuthorizationStatus> private var notificationStatus: UNAuthorizationStatus = .notDetermined
    init(model: AppModel, login: LoginItem, initialTab: SettingsTab = .general) {
        self.model = model
        self.login = login
        self._tab = ViewState(initialValue: initialTab)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                ForEach(SettingsTab.allCases, id: \.self) { item in
                    Button { tab = item } label: {
                        VStack(spacing: 5) {
                            Image(systemName: item.symbol).font(.system(size: 20))
                            Text(item.rawValue).font(.system(size: 11))
                        }.frame(width: 76, height: 52)
                            .background(tab == item ? Color.primary.opacity(0.075) : .clear,
                                in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(tab == item ? .primary : .secondary)
                        .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }.padding(14).frame(maxWidth: .infinity).background(.bar)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    switch tab {
                    case .general: general
                    case .appearance: appearance
                    case .shortcuts: shortcuts
                    }
                    if let error = model.error ?? login.error {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12)).foregroundStyle(.red)
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            HStack {
                CoffeeMark(active: model.isActive, size: 20)
                Text("Brew 1.0").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Text("A little energy. A lot of focus.").font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.vertical, 12)
        }.frame(width: 530, height: 590).background(Color(nsColor: .windowBackgroundColor))
            .onAppear { refreshNotifications() }
    }
    private var general: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "KEEP AWAKE", symbol: "sun.max") {
                SettingToggle(title: "Allow the display to sleep", detail: "Keep your Mac working while the screen rests.",
                    value: $model.preferences.allowDisplaySleep)
                Divider()
                SettingToggle(title: "Keep awake with the lid closed", detail: "Requests extended protection. macOS may override this on battery or unsupported hardware.",
                    value: $model.preferences.keepAwakeWithLidClosed)
                Divider()
                SettingToggle(title: "Deactivate when unplugged", detail: "End the session when the charger disconnects.",
                    value: $model.preferences.deactivateWhenUnplugged)
            }
            SettingsSection(title: "STARTUP", symbol: "power") {
                SettingToggle(title: "Launch at login", detail: "Brew will be ready in your menu bar.",
                    value: Binding(get: { login.enabled }, set: { login.setEnabled($0) }))
                if login.needsApproval {
                    Button("Allow in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                        .font(.system(size: 11))
                }
                Divider()
                SettingToggle(title: "Activate on launch", detail: "Start using your last selected duration.",
                    value: $model.preferences.activateOnLaunch)
            }
            SettingsSection(title: "NOTIFICATIONS", symbol: "bell") {
                SettingToggle(title: "Notify when a session ends", detail: "A gentle reminder when your Mac can sleep again.",
                    value: Binding(get: { model.preferences.notifyWhenFinished }, set: {
                        model.preferences.notifyWhenFinished = $0
                        if $0 {
                            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in
                                DispatchQueue.main.async { refreshNotifications() }
                            }
                        }
                    }))
                if notificationStatus == .denied && model.preferences.notifyWhenFinished {
                    Button("Enable notifications in System Settings…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }.font(.system(size: 11))
                }
                Divider()
                SettingToggle(title: "Play a notification sound", detail: nil,
                    value: $model.preferences.notificationSound).disabled(!model.preferences.notifyWhenFinished)
            }
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "APPEARANCE", symbol: "circle.lefthalf.filled") {
                Picker("Theme", selection: $model.preferences.appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }.pickerStyle(.segmented)
                Text("System follows your Mac’s light and dark mode.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsSection(title: "MENU BAR", symbol: "menubar.rectangle") {
                Picker("Active icon color", selection: $model.preferences.iconColor) {
                    ForEach(IconColorChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("Accent uses your macOS accent color. The cup fills when Brew is active.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Divider()
                SettingToggle(title: "Show remaining time", detail: "Display the countdown beside the coffee cup.",
                    value: $model.preferences.showCountdownInMenuBar)
            }
            SettingsSection(title: "PREVIEW", symbol: "eye") {
                HStack(spacing: 22) {
                    CoffeeMark(active: false, size: 46)
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    CoffeeMark(active: true, size: 46)
                    Spacer()
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Small footprint. Native feel.").font(.system(size: 12, weight: .medium))
                        Text("No Dock icon. Always within reach.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
        }
    }
    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "ONE-CLICK CONTROL", symbol: "cursorarrow.click") {
                SettingToggle(title: "Activate with left click", detail: model.preferences.activateWithLeftClick
                    ? "Left click toggles Brew. Right click opens the menu."
                    : "Left click opens the menu. Right click toggles Brew.", value: $model.preferences.activateWithLeftClick)
                Text("Control-click works as a right click. Option-click always opens the menu.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsSection(title: "GLOBAL KEYBOARD SHORTCUT", symbol: "keyboard") {
                SettingToggle(title: "Enable global shortcut", detail: "Toggle Brew from any app without changing focus.",
                    value: $model.preferences.shortcutEnabled)
                HStack {
                    Text("Toggle awake session").font(.system(size: 12))
                    Spacer()
                    ShortcutRecorder(shortcut: $model.preferences.shortcut, enabled: model.preferences.shortcutEnabled)
                        .frame(width: 155, height: 28)
                }
                Text("Click the shortcut to record. Include ⌘, ⌥, or ⌃. Press Esc to cancel.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            SettingsSection(title: "AUTOMATION", symbol: "point.3.connected.trianglepath.dotted") {
                Text(Bundle.main.object(forInfoDictionaryKey: "BrewNativeShortcuts") as? Bool == false
                    ? "In Shortcuts, use Open URLs with brew://start, brew://stop, or brew://toggle. Build with Xcode to register native Brew actions."
                    : "Find Start Brew, Stop Brew, and Toggle Brew in the Shortcuts app.")
                    .font(.system(size: 12))
                Text("AppleScript").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                Text("tell application \"Brew\" to start session\ntell application \"Brew\" to stop session\ntell application \"Brew\" to toggle")
                    .font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("URL: brew://start?seconds=3600").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Button("Open Shortcuts") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app")) }
                    .controlSize(.small)
            }
        }
    }
    private func refreshNotifications() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async { notificationStatus = settings.authorizationStatus }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    var title: String
    var symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .semibold))
                .tracking(1).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12, content: content)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.045)))
        }
    }
}
private struct SettingToggle: View {
    var title: String
    var detail: String?
    @Binding var value: Bool
    var body: some View {
        Toggle(isOn: $value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12, weight: .medium))
                if let detail { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.toggleStyle(.switch).controlSize(.small)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 24).fill(Color.accentColor.opacity(0.1)).frame(width: 104, height: 104)
                CoffeeMark(active: true, size: 67)
            }
            VStack(spacing: 5) {
                Text("Brew").font(.system(size: 28, weight: .semibold, design: .rounded))
                Text("A little energy for your Mac.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
            Text("Keep your Mac awake for the things that matter.\nA quiet companion for calls, downloads, and deep work.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Divider().padding(.horizontal, 25)
            Text("Version 1.0.0 · Native macOS app").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Works entirely on your Mac. No account required.").font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(30).frame(width: 380).background(.regularMaterial)
    }
}
