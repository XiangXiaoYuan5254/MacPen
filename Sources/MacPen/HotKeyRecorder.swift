import AppKit
import Carbon
import SwiftUI

/// A field that shows the global hot key; click it, then press a new combination.
struct HotKeyRecorder: NSViewRepresentable {
    var hotKey: AppConfig.HotKey
    @Binding var isRecording: Bool
    var onRecord: (AppConfig.HotKey) -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        HotKeyRecorderView()
    }

    func updateNSView(_ view: HotKeyRecorderView, context: Context) {
        view.hotKey = hotKey
        view.onRecord = onRecord
        view.onRecordingChange = { isRecording = $0 }
        view.setRecording(isRecording)
    }
}

@MainActor
final class HotKeyRecorderView: NSView {
    var hotKey: AppConfig.HotKey? {
        didSet {
            needsDisplay = true
            setAccessibilityValue(hotKey?.displayString)
        }
    }
    var onRecord: ((AppConfig.HotKey) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?

    private var isRecording = false
    private var heldModifiers: NSEvent.ModifierFlags = []
    private var message: String?

    private static let modifierFlags: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toolTip = "点击后按下新的快捷键，按 Esc 取消"
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("开始或结束标注的快捷键")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 168, height: 28)
    }

    /// Only while recording, so opening the window never starts a recording on its own.
    override var acceptsFirstResponder: Bool {
        isRecording
    }

    func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        heldModifiers = []
        message = nil
        if recording {
            if window?.makeFirstResponder(self) != true {
                finish()
            }
        } else if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording {
            finish()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            finish()
        } else {
            setRecording(true)
            onRecordingChange?(isRecording)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        record(event)
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else {
            super.flagsChanged(with: event)
            return
        }
        heldModifiers = event.modifierFlags.intersection(Self.modifierFlags)
        message = nil
        needsDisplay = true
    }

    private func record(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.modifierFlags)
        if event.keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
            finish()
            return
        }
        guard let key = AppConfig.HotKey.key(forKeyCode: UInt32(event.keyCode)) else {
            show(message: "只支持字母、数字和 F1–F12")
            return
        }
        // Without one of these the hot key would swallow ordinary typing.
        guard !modifiers.isDisjoint(with: [.command, .option, .control]) else {
            show(message: "请同时按住 ⌘、⌥ 或 ⌃")
            return
        }

        var modifierKeys: [String] = []
        if modifiers.contains(.command) { modifierKeys.append("command") }
        if modifiers.contains(.shift) { modifierKeys.append("shift") }
        if modifiers.contains(.option) { modifierKeys.append("option") }
        if modifiers.contains(.control) { modifierKeys.append("control") }
        onRecord?(AppConfig.HotKey(key: key, modifierKeys: modifierKeys))
        finish()
    }

    private func finish() {
        setRecording(false)
        onRecordingChange?(false)
    }

    private func show(message: String) {
        self.message = message
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.message == message else { return }
            self?.message = nil
            self?.needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isRecording {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            shape.fill()
            NSColor.controlAccentColor.setStroke()
            shape.lineWidth = 2
        } else {
            NSColor.controlBackgroundColor.setFill()
            shape.fill()
            NSColor.separatorColor.setStroke()
            shape.lineWidth = 1
        }
        shape.stroke()

        let text: String
        let color: NSColor
        let font: NSFont
        if let message {
            text = message
            color = .systemRed
            font = .systemFont(ofSize: 12)
        } else if isRecording {
            let held = Self.symbols(for: heldModifiers)
            text = held.isEmpty ? "请按下新的快捷键" : held + " …"
            color = .secondaryLabelColor
            font = .systemFont(ofSize: 12)
        } else {
            text = hotKey?.displayString ?? ""
            color = .labelColor
            font = .systemFont(ofSize: 14, weight: .medium)
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2,
                                            y: bounds.midY - size.height / 2),
                                withAttributes: attributes)
    }

    private static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        return AppConfig.HotKey.modifierSymbols(carbon)
    }
}
