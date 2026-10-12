import AppKit
import Carbon
import SwiftUI

@MainActor
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    private(set) var error: String?
    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotkey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { hotkey.onPress?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    @discardableResult func register(_ shortcut: Shortcut, enabled: Bool) -> Bool {
        if let reference { UnregisterEventHotKey(reference) }
        reference = nil
        error = nil
        guard enabled else { return true }
        let id = EventHotKeyID(signature: 0x42524557, id: 1)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, id,
                                        GetApplicationEventTarget(), 0, &reference)
        if status != noErr { error = "This shortcut is already in use. Record another combination." }
        return status == noErr
    }
    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    var enabled: Bool
    func makeNSView(context: Context) -> RecorderView { RecorderView() }
    func updateNSView(_ view: RecorderView, context: Context) {
        view.value = shortcut
        view.isEnabled = enabled
        view.onRecord = { shortcut = $0 }
        view.refreshTitle()
    }
    final class RecorderView: NSButton {
        var value = Shortcut()
        var onRecord: ((Shortcut) -> Void)?
        private var recording = false
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            bezelStyle = .rounded
            target = self
            action = #selector(beginRecording)
            setAccessibilityLabel("Record global shortcut")
            toolTip = "Click, then press a key with Command, Option, or Control. Escape cancels."
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override var acceptsFirstResponder: Bool { true }
        @objc private func beginRecording() {
            recording = true
            window?.makeFirstResponder(self)
            refreshTitle()
        }
        func refreshTitle() { title = recording ? "Press shortcut…" : value.label }
        override func resignFirstResponder() -> Bool {
            recording = false
            refreshTitle()
            return super.resignFirstResponder()
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if recording { keyDown(with: event); return true }
            return super.performKeyEquivalent(with: event)
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { super.keyDown(with: event); return }
            if event.keyCode == 53 { recording = false; refreshTitle(); return }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard !flags.intersection([.command, .option, .control]).isEmpty else {
                NSSound.beep(); return
            }
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if flags.contains(.option) { modifiers |= UInt32(optionKey) }
            if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            if flags.contains(.control) { modifiers |= UInt32(controlKey) }
            let special: [UInt16: String] = [36: "↩", 48: "⇥", 49: "Space", 51: "⌫",
                123: "←", 124: "→", 125: "↓", 126: "↑"]
            guard let label = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased(),
                  !label.isEmpty else { NSSound.beep(); return }
            value = Shortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
            recording = false
            refreshTitle()
            onRecord?(value)
        }
    }
}
