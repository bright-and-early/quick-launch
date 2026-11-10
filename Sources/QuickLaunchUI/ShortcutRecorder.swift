import AppKit
import QuickLaunchCore

public final class ShortcutRecorder: NSButton {
    public private(set) var isRecording = false
    public var onChange: ((LauncherHotKey) -> String?)?
    public var onMessage: ((String) -> Void)?
    private var shortcut: LauncherHotKey = .standard
    public override var acceptsFirstResponder: Bool { true }
    public override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self; action = #selector(beginRecording)
        setAccessibilityLabel("Launcher hotkey")
        display(.standard)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    public func display(_ value: LauncherHotKey) { shortcut = value; title = value.title }
    @objc private func beginRecording() {
        isRecording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
        onMessage?("Use Command, Option, or Control. Escape cancels.")
    }
    public func cancelRecording() { isRecording = false; title = shortcut.title; onMessage?("") }
    public override func resignFirstResponder() -> Bool { if isRecording { cancelRecording() }; return super.resignFirstResponder() }
    public override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { cancelRecording(); return }
        var modifiers: UInt32 = 0
        for (flag, bit): (NSEvent.ModifierFlags, UInt32) in [(.command, 1), (.option, 2), (.control, 4), (.shift, 8)] {
            if event.modifierFlags.contains(flag) { modifiers |= bit }
        }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 123: "←", 124: "→", 125: "↓", 126: "↑", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let key = names[event.keyCode] ?? (event.charactersIgnoringModifiers ?? "").uppercased()
        let value = LauncherHotKey(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
        guard value.isValid else { onMessage?("Include Command, Option, or Control."); return }
        if let error = onChange?(value) { onMessage?(error); return }
        display(value); isRecording = false; onMessage?("")
    }
}
