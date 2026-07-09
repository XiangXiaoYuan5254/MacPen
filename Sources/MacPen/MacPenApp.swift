import AppKit
import Carbon
import CoreGraphics

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var overlay: OverlayWindowController?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var config = AppConfig.load()
    private var settingsWindowController: SettingsWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        registerHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "MacPen")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "MacPen"
        }
        refreshMenu()
    }

    private func refreshMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: overlay == nil ? "Start Drawing" : "Stop Drawing",
                                action: #selector(toggleOverlay),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Undo",
                                action: #selector(undo),
                                keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "Clear",
                                action: #selector(clear),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Thinner Brush",
                                action: #selector(makeBrushThinner),
                                keyEquivalent: "["))
        menu.addItem(NSMenuItem(title: "Thicker Brush",
                                action: #selector(makeBrushThicker),
                                keyEquivalent: "]"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Pointer Mode",
                                action: #selector(togglePointerMode),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Snapshot Region",
                                action: #selector(snapshotRegion),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Laser Pen",
                                action: #selector(selectLaserPen),
                                keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...",
                                action: #selector(openSettings),
                                keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(quit),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func toggleOverlay() {
        if let overlay {
            overlay.dismiss()
            self.overlay = nil
        } else {
            let controller = OverlayWindowController(config: config)
            controller.onClose = { [weak self] in
                self?.overlay = nil
                self?.refreshMenu()
            }
            overlay = controller
            controller.show()
        }
        refreshMenu()
    }

    @objc private func undo() {
        overlay?.canvas.undo()
    }

    @objc private func clear() {
        overlay?.canvas.clearInk()
    }

    @objc private func makeBrushThinner() {
        overlay?.canvas.adjustBrushWidth(by: 0.85)
    }

    @objc private func makeBrushThicker() {
        overlay?.canvas.adjustBrushWidth(by: 1.18)
    }

    @objc private func togglePointerMode() {
        overlay?.togglePointerMode()
    }

    @objc private func snapshotRegion() {
        ensureOverlay().canvas.beginSnapshotSelection()
    }

    @objc private func selectLaserPen() {
        ensureOverlay().canvas.selectLaserPen()
    }

    @objc private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(config: config) { [weak self] newConfig in
                self?.apply(config: newConfig)
            }
        } else {
            settingsWindowController?.update(config: config)
        }
        settingsWindowController?.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func ensureOverlay() -> OverlayWindowController {
        if let overlay {
            return overlay
        }
        let controller = OverlayWindowController(config: config)
        controller.onClose = { [weak self] in
            self?.overlay = nil
            self?.refreshMenu()
        }
        overlay = controller
        controller.show()
        refreshMenu()
        return controller
    }

    private func registerHotKey() {
        unregisterHotKey()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4d50656e), id: 1)
        let status = RegisterEventHotKey(config.hotKey.keyCode,
                                         config.hotKey.carbonModifiers,
                                         hotKeyID,
                                         GetApplicationEventTarget(),
                                         0,
                                         &hotKeyRef)
        guard status == noErr else {
            NSLog("RegisterEventHotKey failed: \(status)")
            return
        }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in
                delegate.toggleOverlay()
            }
            return noErr
        }

        InstallEventHandler(GetApplicationEventTarget(),
                            callback,
                            1,
                            &eventType,
                            Unmanaged.passUnretained(self).toOpaque(),
                            &eventHandler)
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func apply(config: AppConfig) {
        self.config = config
        config.save()
        registerHotKey()
        overlay?.canvas.apply(config: config)
        settingsWindowController?.update(config: config)
    }
}

struct AppConfig: Codable {
    enum CursorStyle: String, Codable, CaseIterable {
        case whiteRingDot = "white_ring_dot"
        case solidDot = "solid_dot"
        case crosshair = "crosshair"
        case softRing = "soft_ring"
        case pencilOutline = "pencil_outline"

        var title: String {
            switch self {
            case .whiteRingDot: return "白环点"
            case .solidDot: return "实心圆点"
            case .crosshair: return "细十字"
            case .softRing: return "柔光圆环"
            case .pencilOutline: return "铅笔轮廓"
            }
        }
    }

    struct HotKey: Codable {
        var key: String
        var modifierKeys: [String]

        var keyCode: UInt32 {
            Self.keyCodeMap[key.uppercased()] ?? UInt32(kVK_ANSI_G)
        }

        var modifiersValue: UInt32 {
            modifierKeys.reduce(0) { partial, item in
                partial | (Self.modifierMap[item.lowercased()] ?? 0)
            }
        }

        var carbonModifiers: UInt32 {
            modifiersValue == 0 ? UInt32(cmdKey | shiftKey) : modifiersValue
        }

        private static let modifierMap: [String: UInt32] = [
            "command": UInt32(cmdKey),
            "cmd": UInt32(cmdKey),
            "shift": UInt32(shiftKey),
            "option": UInt32(optionKey),
            "alt": UInt32(optionKey),
            "control": UInt32(controlKey),
            "ctrl": UInt32(controlKey)
        ]

        private static let keyCodeMap: [String: UInt32] = [
            "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
            "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
            "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
            "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
            "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
            "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
            "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
            "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
            "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "F1": UInt32(kVK_F1), "F2": UInt32(kVK_F2), "F3": UInt32(kVK_F3),
            "F4": UInt32(kVK_F4), "F5": UInt32(kVK_F5), "F6": UInt32(kVK_F6),
            "F7": UInt32(kVK_F7), "F8": UInt32(kVK_F8), "F9": UInt32(kVK_F9),
            "F10": UInt32(kVK_F10), "F11": UInt32(kVK_F11), "F12": UInt32(kVK_F12)
        ]
    }

    var hotKey: HotKey
    var defaultPenWidth: Double
    var cursorStyle: CursorStyle
    var laserDuration: Double
    var laserWidth: Double
    var laserColorHex: String

    init(hotKey: HotKey,
         defaultPenWidth: Double = 4,
         cursorStyle: CursorStyle = .whiteRingDot,
         laserDuration: Double = 1.1,
         laserWidth: Double = 4,
         laserColorHex: String = "#ff2d20") {
        self.hotKey = hotKey
        self.defaultPenWidth = defaultPenWidth
        self.cursorStyle = cursorStyle
        self.laserDuration = laserDuration
        self.laserWidth = laserWidth
        self.laserColorHex = laserColorHex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hotKey = try container.decodeIfPresent(HotKey.self, forKey: .hotKey)
            ?? HotKey(key: "G", modifierKeys: ["command", "shift"])
        defaultPenWidth = try container.decodeIfPresent(Double.self, forKey: .defaultPenWidth) ?? 4
        cursorStyle = try container.decodeIfPresent(CursorStyle.self, forKey: .cursorStyle) ?? .whiteRingDot
        laserDuration = try container.decodeIfPresent(Double.self, forKey: .laserDuration) ?? 1.1
        laserWidth = try container.decodeIfPresent(Double.self, forKey: .laserWidth) ?? 4
        laserColorHex = try container.decodeIfPresent(String.self, forKey: .laserColorHex) ?? "#ff2d20"
    }

    static func load() -> AppConfig {
        let config = AppConfig(hotKey: HotKey(key: "G", modifierKeys: ["command", "shift"]))
        let url = configURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let data = try? encoder.encode(config) {
                try? data.write(to: url)
            }
            return config
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(AppConfig.self, from: data) else {
            return config
        }
        return decoded
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: Self.configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? encoder.encode(self) {
            try? data.write(to: Self.configURL)
        }
    }

    private static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacPen/config.json")
    }
}

@MainActor
final class OverlayWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let canvas: CanvasView
    var onClose: (() -> Void)?
    private var pointerToolbar: PointerToolbarController?
    private var previousApplication: NSRunningApplication?

    init(config: AppConfig) {
        let frame = NSScreen.virtualFrame
        canvas = CanvasView(frame: NSRect(origin: .zero, size: frame.size), config: config)
        window = OverlayWindow(contentRect: frame,
                               styleMask: [.borderless],
                               backing: .buffered,
                               defer: false)
        super.init()

        window.contentView = canvas
        window.delegate = self
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .screenSaver
        window.ignoresMouseEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true
        canvas.onDismiss = { [weak self] in
            self?.dismiss()
        }
        canvas.onPointerModeChanged = { [weak self] active in
            self?.handlePointerModeChanged(active)
        }
    }

    func show() {
        previousApplication = NSWorkspace.shared.frontmostApplication
        window.setFrame(NSScreen.virtualFrame, display: true)
        canvas.frame = NSRect(origin: .zero, size: window.frame.size)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(canvas)
        NSApp.activate(ignoringOtherApps: true)
    }

    func togglePointerMode() {
        canvas.togglePointerMode()
    }

    func dismiss() {
        pointerToolbar?.close()
        pointerToolbar = nil
        window.orderOut(nil)
        onClose?()
    }

    private func handlePointerModeChanged(_ active: Bool) {
        if active {
            showPointerToolbar()
            previousApplication?.activate(options: [])
        } else {
            pointerToolbar?.close()
            pointerToolbar = nil
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(canvas)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func showPointerToolbar() {
        if pointerToolbar == nil {
            pointerToolbar = PointerToolbarController(canvas: canvas)
        }
        pointerToolbar?.show()
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

private extension NSScreen {
    static var virtualFrame: NSRect {
        screens.reduce(.null) { partial, screen in
            partial.isNull ? screen.frame : partial.union(screen.frame)
        }
    }
}

private enum CanvasTool: Equatable {
    case pen(Pen)
    case laser(Pen)
    case eraser
    case snapshot
}

private struct Pen: Equatable {
    let color: NSColor
    let width: CGFloat
    let alpha: CGFloat

    static let basePalette = [
        Pen(color: .systemRed, width: 3, alpha: 1.0),
        Pen(color: .systemBlue, width: 7, alpha: 1.0),
        Pen(color: .systemYellow, width: 8, alpha: 1.0),
        Pen(color: .systemGreen, width: 7, alpha: 1.0),
        Pen(color: .systemOrange, width: 22, alpha: 0.45),
        Pen(color: .systemPurple, width: 22, alpha: 0.45)
    ]
}

private struct InkStroke {
    var points: [NSPoint]
    var pen: Pen
    var createdAt: Date = Date()
    var lastUpdatedAt: Date = Date()
    var lifetime: TimeInterval?

    func alpha(at now: Date) -> CGFloat {
        guard let lifetime else { return pen.alpha }
        let age = now.timeIntervalSince(lastUpdatedAt)
        let progress = max(0, min(1, age / lifetime))
        return pen.alpha * CGFloat(1 - progress)
    }

    func isExpired(at now: Date) -> Bool {
        guard let lifetime else { return false }
        return now.timeIntervalSince(lastUpdatedAt) >= lifetime
    }

    func draw(at now: Date, overrideAlpha: CGFloat? = nil) {
        let currentAlpha = overrideAlpha ?? alpha(at: now)
        guard currentAlpha > 0.01 else { return }

        if points.count == 1 {
            let point = points[0]
            let dotRect = NSRect(x: point.x - pen.width / 2,
                                 y: point.y - pen.width / 2,
                                 width: pen.width,
                                 height: pen.width)
            if lifetime != nil {
                pen.color.withAlphaComponent(currentAlpha * 0.30).setFill()
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -pen.width * 1.0, dy: -pen.width * 1.0)).fill()
                pen.color.withAlphaComponent(currentAlpha * 0.78).setFill()
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -pen.width * 0.28, dy: -pen.width * 0.28)).fill()
                NSColor.white.withAlphaComponent(currentAlpha * 1.0).setFill()
                NSBezierPath(ovalIn: dotRect.insetBy(dx: pen.width * 0.28, dy: pen.width * 0.28)).fill()
            } else {
                pen.color.withAlphaComponent(currentAlpha).setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return
        }

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = pen.width
        path.move(to: points[0])

        if points.count == 2 {
            path.line(to: points[1])
        } else {
            for index in 1..<(points.count - 1) {
                let current = points[index]
                let next = points[index + 1]
                let mid = NSPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
                path.curve(to: mid, controlPoint1: current, controlPoint2: current)
            }
            path.line(to: points[points.count - 1])
        }

        if lifetime != nil {
            let glow = path.copy() as! NSBezierPath
            glow.lineWidth = pen.width * 2.1
            pen.color.withAlphaComponent(currentAlpha * 0.24).setStroke()
            glow.stroke()

            let mid = path.copy() as! NSBezierPath
            mid.lineWidth = pen.width * 1.18
            pen.color.withAlphaComponent(currentAlpha * 0.72).setStroke()
            mid.stroke()

            let core = path.copy() as! NSBezierPath
            core.lineWidth = max(1.6, pen.width * 0.42)
            NSColor.white.withAlphaComponent(currentAlpha * 1.0).setStroke()
            core.stroke()
        } else {
            pen.color.withAlphaComponent(currentAlpha).setStroke()
            path.stroke()
        }
    }

    func isNear(_ point: NSPoint, radius: CGFloat) -> Bool {
        points.contains { sample in
            hypot(sample.x - point.x, sample.y - point.y) <= radius
        }
    }
}

@MainActor
final class CanvasView: NSView {
    private enum LaserInteractionMode {
        case idle
        case undecided(NSPoint)
        case drawing
        case scrolling(NSPoint)
    }

    private var strokes: [InkStroke] = []
    private var redoStack: [InkStroke] = []
    private var currentStroke: InkStroke?
    private var tool: CanvasTool
    private var currentPenIndex = 0
    fileprivate var penPalette: [Pen]
    private var toolbarItems: [(String, NSRect, () -> Void)] = []
    private var hoveredToolbarLabel: String?
    private var pressedToolbarLabel: String?
    private var flashedToolbarLabel: String?
    private var pendingToolbarAction: (() -> Void)?
    private var trackingArea: NSTrackingArea?
    private var snapshotStart: NSPoint?
    private var snapshotRect: NSRect?
    private var inkVisible = true
    private var brushScale: CGFloat = 1.0
    private var config: AppConfig
    private var laserFadeTimer: Timer?
    private var laserLastActivityAt: Date?
    private var laserFadeStartAt: Date?
    private let forwardedScrollMarker: Int64 = 0x67496E6B
    private var scrollPassthroughRestoreWorkItem: DispatchWorkItem?
    private var laserInteractionMode: LaserInteractionMode = .idle
    var onDismiss: (() -> Void)?
    var onPointerModeChanged: ((Bool) -> Void)?
    var pointerMode = false {
        didSet {
            applyCurrentCursor()
            if oldValue != pointerMode {
                onPointerModeChanged?(pointerMode)
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    init(frame frameRect: NSRect, config: AppConfig) {
        self.config = config
        self.penPalette = Pen.basePalette
        self.penPalette[0] = Pen(color: .systemRed, width: CGFloat(config.defaultPenWidth), alpha: 1.0)
        self.tool = .pen(self.penPalette[0])
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func apply(config: AppConfig) {
        self.config = config
        penPalette = Pen.basePalette
        penPalette[0] = Pen(color: .systemRed, width: CGFloat(config.defaultPenWidth), alpha: 1.0)

        switch tool {
        case .pen:
            selectPen(currentPenIndex)
        case .laser:
            selectLaserPen()
        default:
            applyCurrentCursor()
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()
        pruneExpiredLaserStrokes()
        let now = Date()
        let laserAlpha = sharedLaserAlpha(at: now)

        if inkVisible {
            strokes.forEach { stroke in
                let overrideAlpha = stroke.lifetime != nil ? stroke.pen.alpha * laserAlpha : nil
                stroke.draw(at: now, overrideAlpha: overrideAlpha)
            }
            if let currentStroke {
                let overrideAlpha = currentStroke.lifetime != nil ? currentStroke.pen.alpha : nil
                currentStroke.draw(at: now, overrideAlpha: overrideAlpha)
            }
        }

        drawSnapshotSelection()
        drawToolbar()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: cursorForCurrentTool())
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        rebuildToolbarItems()
        if let hit = toolbarItems.first(where: { $0.1.contains(point) }) {
            pressedToolbarLabel = hit.0
            pendingToolbarAction = hit.2
            needsDisplay = true
            return
        }

        switch tool {
        case .pen(let pen):
            redoStack.removeAll()
            currentStroke = InkStroke(points: [point], pen: penForEvent(pen, event))
        case .laser(let pen):
            currentStroke = InkStroke(points: [point],
                                      pen: Pen(color: pen.color, width: CGFloat(config.laserWidth), alpha: pen.alpha),
                                      createdAt: Date(),
                                      lifetime: config.laserDuration)
            noteLaserActivity()
            laserInteractionMode = .undecided(point)
        case .eraser:
            erase(at: point)
        case .snapshot:
            snapshotStart = point
            snapshotRect = NSRect(origin: point, size: .zero)
        }
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        updateHoveredButton(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        hoveredToolbarLabel = nil
        applyCurrentCursor()
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch tool {
        case .pen:
            currentStroke?.points.append(point)
        case .laser:
            handleLaserDrag(at: point)
        case .eraser:
            erase(at: point)
        case .snapshot:
            if let snapshotStart {
                snapshotRect = NSRect(x: min(snapshotStart.x, point.x),
                                      y: min(snapshotStart.y, point.y),
                                      width: abs(point.x - snapshotStart.x),
                                      height: abs(point.y - snapshotStart.y))
            }
        }
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        rebuildToolbarItems()
        if toolbarItems.contains(where: { $0.1.contains(point) }) {
            super.scrollWheel(with: event)
            return
        }

        guard case .laser = tool, !pointerMode else {
            super.scrollWheel(with: event)
            return
        }

        if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == forwardedScrollMarker {
            return
        }

        forwardScrollEvent(event)
    }

    override func mouseUp(with event: NSEvent) {
        if let pressedLabel = pressedToolbarLabel {
            let point = convert(event.locationInWindow, from: nil)
            let releasedInside = toolbarItems.contains { label, rect, _ in
                label == pressedLabel && rect.contains(point)
            }
            let action = pendingToolbarAction
            pressedToolbarLabel = nil
            pendingToolbarAction = nil
            applyCurrentCursor()
            needsDisplay = true
            if releasedInside {
                action?()
            }
            return
        }

        if case .snapshot = tool {
            if let rect = snapshotRect, rect.width > 8, rect.height > 8 {
                saveSnapshot(rect)
            }
            snapshotStart = nil
            snapshotRect = nil
            selectPen(currentPenIndex)
            needsDisplay = true
            return
        }

        if let stroke = currentStroke, (!stroke.points.isEmpty) {
            strokes.append(stroke)
            ensureLaserFadeTimer()
        }
        currentStroke = nil
        laserInteractionMode = .idle
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "1":
            flashToolbarButton("1 画笔")
            selectPen(currentPenIndex)
            return
        case "2":
            flashToolbarButton("2 橡皮")
            selectEraser()
            return
        case "3":
            flashToolbarButton("3 撤销")
            undo()
            return
        case "4":
            flashToolbarButton("4 清空")
            clearInk()
            return
        case "5":
            flashToolbarButton("5 截图")
            beginSnapshotSelection()
            return
        case "6":
            flashToolbarButton("6 隐藏")
            toggleInkVisible()
            return
        case "7":
            flashToolbarButton("7 穿透")
            togglePointerMode()
            return
        case "8":
            flashToolbarButton("8 激光")
            selectLaserPen()
            return
        case "[":
            flashToolbarButton("↓")
            adjustBrushWidth(by: 0.85)
            return
        case "]":
            flashToolbarButton("↑")
            adjustBrushWidth(by: 1.18)
            return
        default:
            break
        }

        switch event.keyCode {
        case UInt16(kVK_Escape):
            flashToolbarButton("完成")
            onDismiss?()
        case UInt16(kVK_UpArrow):
            flashToolbarButton("↑")
            adjustBrushWidth(by: 1.18)
        case UInt16(kVK_DownArrow):
            flashToolbarButton("↓")
            adjustBrushWidth(by: 0.85)
        case UInt16(kVK_ANSI_Z) where event.modifierFlags.contains(.command):
            flashToolbarButton("3 撤销")
            undo()
        default:
            super.keyDown(with: event)
        }
    }

    func undo() {
        guard let stroke = strokes.popLast() else { return }
        redoStack.append(stroke)
        needsDisplay = true
    }

    func clearInk() {
        redoStack.removeAll()
        strokes.removeAll()
        currentStroke = nil
        laserLastActivityAt = nil
        laserFadeStartAt = nil
        laserFadeTimer?.invalidate()
        laserFadeTimer = nil
        needsDisplay = true
    }

    func selectCurrentPen() {
        selectPen(currentPenIndex)
    }

    func selectPen(_ index: Int) {
        let safeIndex = min(max(index, 0), penPalette.count - 1)
        currentPenIndex = safeIndex
        tool = .pen(penPalette[safeIndex])
        pointerMode = false
        window?.ignoresMouseEvents = false
        applyCurrentCursor()
        needsDisplay = true
    }

    func selectLaserPen() {
        tool = .laser(Pen(color: NSColor(hex: config.laserColorHex) ?? .systemRed,
                          width: CGFloat(config.laserWidth),
                          alpha: 1.0))
        pointerMode = false
        window?.ignoresMouseEvents = false
        applyCurrentCursor()
        needsDisplay = true
    }

    func selectEraser() {
        tool = .eraser
        pointerMode = false
        window?.ignoresMouseEvents = false
        applyCurrentCursor()
        needsDisplay = true
    }

    func toggleInkVisible() {
        inkVisible.toggle()
        needsDisplay = true
    }

    func togglePointerMode() {
        pointerMode.toggle()
        window?.ignoresMouseEvents = pointerMode
        if !pointerMode {
            window?.makeFirstResponder(self)
        }
        applyCurrentCursor()
        needsDisplay = true
    }

    func adjustBrushWidth(by factor: CGFloat) {
        brushScale = min(3.0, max(0.35, brushScale * factor))
        applyCurrentCursor()
        needsDisplay = true
    }

    func beginSnapshotSelection() {
        tool = .snapshot
        pointerMode = false
        window?.ignoresMouseEvents = false
        applyCurrentCursor()
        needsDisplay = true
    }

    private func penForEvent(_ pen: Pen, _ event: NSEvent) -> Pen {
        let pressure = CGFloat(max(event.pressure, 0.15))
        let adjusted = max(1.2, pen.width * brushScale * (0.62 + pressure * 0.28))
        return Pen(color: pen.color, width: adjusted, alpha: pen.alpha)
    }

    private func erase(at point: NSPoint) {
        let before = strokes.count
        strokes.removeAll { $0.isNear(point, radius: 18) }
        if strokes.count != before {
            redoStack.removeAll()
        }
    }

    private func handleLaserDrag(at point: NSPoint) {
        switch laserInteractionMode {
        case .idle:
            currentStroke?.points.append(point)
            noteLaserActivity()
            laserInteractionMode = .drawing
        case .undecided(let start):
            let dx = point.x - start.x
            let dy = point.y - start.y
            if abs(dy) > 10 && abs(dy) > abs(dx) * 1.6 {
                currentStroke = nil
                laserInteractionMode = .scrolling(point)
                postScroll(by: dy)
            } else if hypot(dx, dy) > 5 {
                currentStroke?.points.append(point)
                noteLaserActivity()
                laserInteractionMode = .drawing
            }
        case .drawing:
            currentStroke?.points.append(point)
            noteLaserActivity()
        case .scrolling(let lastPoint):
            let dy = point.y - lastPoint.y
            if abs(dy) > 1 {
                postScroll(by: dy)
                laserInteractionMode = .scrolling(point)
            }
        }
    }

    private func postScroll(by deltaY: CGFloat) {
        let lineDelta = Int32(max(-12, min(12, -deltaY / 7)))
        guard lineDelta != 0,
              let event = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .line,
                                  wheelCount: 1,
                                  wheel1: lineDelta,
                                  wheel2: 0,
                                  wheel3: 0) else { return }
        event.setIntegerValueField(.eventSourceUserData, value: forwardedScrollMarker)
        event.post(tap: .cghidEventTap)
    }

    private func forwardScrollEvent(_ event: NSEvent) {
        guard let forwarded = event.cgEvent?.copy() else {
            temporarilyPassthroughMouseEvents {
                self.postScroll(by: event.scrollingDeltaY)
            }
            return
        }
        forwarded.setIntegerValueField(.eventSourceUserData, value: forwardedScrollMarker)
        temporarilyPassthroughMouseEvents {
            forwarded.post(tap: .cghidEventTap)
        }
    }

    private func temporarilyPassthroughMouseEvents(_ action: () -> Void) {
        guard let window else {
            action()
            return
        }
        scrollPassthroughRestoreWorkItem?.cancel()
        window.ignoresMouseEvents = true
        action()
        let restore = DispatchWorkItem { [weak self, weak window] in
            guard let self, let window else { return }
            window.ignoresMouseEvents = self.pointerMode
            if !self.pointerMode {
                window.makeFirstResponder(self)
                self.applyCurrentCursor()
            }
        }
        scrollPassthroughRestoreWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: restore)
    }

    private func pruneExpiredLaserStrokes() {
        let now = Date()
        let hasLaserStrokes = strokes.contains(where: { $0.lifetime != nil })
        guard hasLaserStrokes else {
            laserLastActivityAt = nil
            laserFadeStartAt = nil
            laserFadeTimer?.invalidate()
            laserFadeTimer = nil
            return
        }

        guard let lastActivityAt = laserLastActivityAt else {
            laserLastActivityAt = now
            return
        }

        let inactivity = now.timeIntervalSince(lastActivityAt)
        if inactivity < config.laserDuration {
            laserFadeStartAt = nil
            return
        }

        if laserFadeStartAt == nil {
            laserFadeStartAt = now
            return
        }

        if sharedLaserAlpha(at: now) <= 0.01 {
            strokes.removeAll { $0.lifetime != nil }
            laserLastActivityAt = nil
            laserFadeStartAt = nil
            if !strokes.contains(where: { $0.lifetime != nil }) {
                laserFadeTimer?.invalidate()
                laserFadeTimer = nil
            }
        }
    }

    private func ensureLaserFadeTimer() {
        guard strokes.contains(where: { $0.lifetime != nil }) else { return }
        guard laserFadeTimer == nil else { return }
        laserFadeTimer = Timer.scheduledTimer(timeInterval: 1.0 / 30.0,
                                              target: self,
                                              selector: #selector(handleLaserFadeTimer),
                                              userInfo: nil,
                                              repeats: true)
    }

    @objc private func handleLaserFadeTimer() {
        pruneExpiredLaserStrokes()
        needsDisplay = true
        if !strokes.contains(where: { $0.lifetime != nil }) {
            laserFadeTimer?.invalidate()
            laserFadeTimer = nil
        }
    }

    private func updateHoveredButton(at point: NSPoint) {
        rebuildToolbarItems()
        let next = toolbarItems.first(where: { $0.1.contains(point) })?.0
        if hoveredToolbarLabel != next {
            hoveredToolbarLabel = next
            applyCurrentCursor()
            needsDisplay = true
        }
    }

    private func flashToolbarButton(_ label: String) {
        flashedToolbarLabel = label
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard self?.flashedToolbarLabel == label else { return }
            self?.flashedToolbarLabel = nil
            self?.needsDisplay = true
        }
    }

    private func applyCurrentCursor() {
        window?.invalidateCursorRects(for: self)
        cursorForCurrentTool().set()
    }

    private func noteLaserActivity() {
        let now = Date()
        laserLastActivityAt = now
        laserFadeStartAt = nil
        currentStroke?.lastUpdatedAt = now
        ensureLaserFadeTimer()
    }

    private func sharedLaserAlpha(at now: Date) -> CGFloat {
        guard let lastActivityAt = laserLastActivityAt else { return 1.0 }
        let inactivity = now.timeIntervalSince(lastActivityAt)
        guard inactivity >= config.laserDuration else { return 1.0 }
        guard let fadeStartAt = laserFadeStartAt else { return 1.0 }
        let fadeDuration = max(0.18, min(0.55, config.laserDuration * 0.28))
        let progress = max(0, min(1, now.timeIntervalSince(fadeStartAt) / fadeDuration))
        return CGFloat(1.0 - progress)
    }

    private func cursorForCurrentTool() -> NSCursor {
        if pointerMode || hoveredToolbarLabel != nil || pressedToolbarLabel != nil {
            return .arrow
        }

        switch tool {
        case .pen(let pen):
            return makePenCursor(style: config.cursorStyle,
                                 color: pen.color,
                                 diameter: pen.width * brushScale,
                                 alpha: max(0.65, pen.alpha))
        case .laser(let pen):
            return makeLaserCursor(color: pen.color, diameter: CGFloat(config.laserWidth))
        case .eraser:
            return makePenCursor(style: .softRing, color: .black, diameter: 22, alpha: 0.8)
        case .snapshot:
            return .crosshair
        }
    }

    private func makePenCursor(style: AppConfig.CursorStyle, color: NSColor, diameter: CGFloat, alpha: CGFloat) -> NSCursor {
        switch style {
        case .whiteRingDot:
            return makeWhiteRingDotCursor(diameter: diameter)
        case .solidDot:
            return makeSolidDotCursor(color: color, diameter: diameter, alpha: alpha)
        case .crosshair:
            return makeCrosshairCursor(color: color, diameter: diameter, alpha: alpha)
        case .softRing:
            return makeSoftRingCursor(color: color, diameter: diameter, alpha: alpha)
        case .pencilOutline:
            return makePencilOutlineCursor()
        }
    }

    private func makeWhiteRingDotCursor(diameter: CGFloat) -> NSCursor {
        let imageSize = NSSize(width: 28, height: 28)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let ringDiameter = min(14, max(9, diameter * 0.82 + 5.0))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let ringRect = NSRect(x: center.x - ringDiameter / 2,
                              y: center.y - ringDiameter / 2,
                              width: ringDiameter,
                              height: ringDiameter)
        let coreDiameter = max(2.8, ringDiameter * 0.28)
        let coreRect = NSRect(x: center.x - coreDiameter / 2,
                              y: center.y - coreDiameter / 2,
                              width: coreDiameter,
                              height: coreDiameter)
        let shadowRect = ringRect.insetBy(dx: -0.8, dy: -0.8)

        NSColor.black.withAlphaComponent(0.20).setStroke()
        var outline = NSBezierPath(ovalIn: shadowRect)
        outline.lineWidth = 1.2
        outline.stroke()

        NSColor.white.withAlphaComponent(0.98).setStroke()
        outline = NSBezierPath(ovalIn: ringRect)
        outline.lineWidth = 1.5
        outline.stroke()

        NSColor.white.withAlphaComponent(0.98).setFill()
        NSBezierPath(ovalIn: coreRect).fill()
        image.unlockFocus()

        return NSCursor(image: image, hotSpot: center)
    }

    private func makeSolidDotCursor(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> NSCursor {
        let imageSize = NSSize(width: 28, height: 28)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let dotDiameter = min(12, max(6, diameter * 0.9 + 2.0))
        let dotRect = NSRect(x: center.x - dotDiameter / 2,
                             y: center.y - dotDiameter / 2,
                             width: dotDiameter,
                             height: dotDiameter)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        color.withAlphaComponent(alpha * 0.25).setFill()
        NSBezierPath(ovalIn: dotRect.insetBy(dx: -2.8, dy: -2.8)).fill()
        color.withAlphaComponent(alpha).setFill()
        NSBezierPath(ovalIn: dotRect).fill()
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let outline = NSBezierPath(ovalIn: dotRect.insetBy(dx: 0.6, dy: 0.6))
        outline.lineWidth = 0.9
        outline.stroke()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    private func makeCrosshairCursor(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> NSCursor {
        let imageSize = NSSize(width: 30, height: 30)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let dotDiameter = min(7, max(3.2, diameter * 0.38))
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let path = NSBezierPath()
        path.lineWidth = 1.0
        path.move(to: NSPoint(x: center.x - 11, y: center.y))
        path.line(to: NSPoint(x: center.x - 4.5, y: center.y))
        path.move(to: NSPoint(x: center.x + 4.5, y: center.y))
        path.line(to: NSPoint(x: center.x + 11, y: center.y))
        path.move(to: NSPoint(x: center.x, y: center.y - 11))
        path.line(to: NSPoint(x: center.x, y: center.y - 4.5))
        path.move(to: NSPoint(x: center.x, y: center.y + 4.5))
        path.line(to: NSPoint(x: center.x, y: center.y + 11))

        color.withAlphaComponent(alpha * 0.9).setStroke()
        path.stroke()
        NSColor.white.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - dotDiameter / 2,
                                    y: center.y - dotDiameter / 2,
                                    width: dotDiameter,
                                    height: dotDiameter)).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    private func makeSoftRingCursor(color: NSColor, diameter: CGFloat, alpha: CGFloat) -> NSCursor {
        let imageSize = NSSize(width: 34, height: 34)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let ringDiameter = min(16, max(9, diameter * 0.74 + 4.0))
        let ringRect = NSRect(x: center.x - ringDiameter / 2,
                              y: center.y - ringDiameter / 2,
                              width: ringDiameter,
                              height: ringDiameter)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        color.withAlphaComponent(alpha * 0.12).setFill()
        NSBezierPath(ovalIn: ringRect.insetBy(dx: -4.0, dy: -4.0)).fill()
        color.withAlphaComponent(alpha * 0.28).setFill()
        NSBezierPath(ovalIn: ringRect.insetBy(dx: -1.8, dy: -1.8)).fill()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        let outline = NSBezierPath(ovalIn: ringRect)
        outline.lineWidth = 1.3
        outline.stroke()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    private func makePencilOutlineCursor() -> NSCursor {
        let imageSize = NSSize(width: 32, height: 32)
        let hotspot = NSPoint(x: 5.0, y: 6.0)
        func point(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
            NSPoint(x: x, y: imageSize.height - yFromTop)
        }
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let strokeColor = NSColor.black.withAlphaComponent(0.96)
        NSColor.white.withAlphaComponent(0.98).setFill()
        strokeColor.setStroke()

        let outline = NSBezierPath()
        outline.lineWidth = 1.8
        outline.lineCapStyle = .round
        outline.lineJoinStyle = .round
        outline.move(to: point(hotspot.x, hotspot.y))
        outline.line(to: point(10.6, 11.3))
        outline.line(to: point(22.5, 23.3))
        outline.curve(to: point(24.8, 28.2),
                      controlPoint1: point(24.1, 24.8),
                      controlPoint2: point(25.1, 26.6))
        outline.line(to: point(20.4, 30.9))
        outline.line(to: point(8.5, 18.8))
        outline.line(to: point(hotspot.x, hotspot.y))
        outline.fill()
        outline.stroke()

        let nibLines = NSBezierPath()
        nibLines.lineWidth = 1.45
        nibLines.lineCapStyle = .round
        nibLines.lineJoinStyle = .round
        nibLines.move(to: point(9.8, 12.1))
        nibLines.line(to: point(13.7, 16.0))
        nibLines.move(to: point(8.3, 17.4))
        nibLines.line(to: point(12.8, 12.9))
        nibLines.stroke()

        let ferrule = NSBezierPath()
        ferrule.lineWidth = 1.45
        ferrule.lineCapStyle = .round
        ferrule.move(to: point(20.8, 24.0))
        ferrule.line(to: point(24.0, 27.2))
        ferrule.stroke()

        let accent = NSBezierPath()
        accent.lineWidth = 1.55
        accent.lineCapStyle = .round
        accent.move(to: point(7.7, 2.6))
        accent.line(to: point(11.0, 2.6))
        accent.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: hotspot)
    }

    private func makeLaserCursor(color: NSColor, diameter: CGFloat) -> NSCursor {
        let imageSize = NSSize(width: 30, height: 30)
        let center = NSPoint(x: imageSize.width / 2, y: imageSize.height / 2)
        let outerDiameter = min(12, max(8, diameter * 0.8 + 4))
        let innerDiameter = outerDiameter * 0.40
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: imageSize).fill()

        let outerRect = NSRect(x: center.x - outerDiameter / 2,
                               y: center.y - outerDiameter / 2,
                               width: outerDiameter,
                               height: outerDiameter)
        let innerRect = NSRect(x: center.x - innerDiameter / 2,
                               y: center.y - innerDiameter / 2,
                               width: innerDiameter,
                               height: innerDiameter)

        color.withAlphaComponent(0.18).setFill()
        NSBezierPath(ovalIn: outerRect.insetBy(dx: -3.2, dy: -3.2)).fill()

        color.withAlphaComponent(0.82).setStroke()
        var path = NSBezierPath(ovalIn: outerRect)
        path.lineWidth = 1.1
        path.stroke()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        path = NSBezierPath(ovalIn: outerRect.insetBy(dx: 1.0, dy: 1.0))
        path.lineWidth = 0.8
        path.stroke()

        color.withAlphaComponent(0.98).setFill()
        NSBezierPath(ovalIn: innerRect).fill()

        NSColor.white.withAlphaComponent(1.0).setFill()
        NSBezierPath(ovalIn: innerRect.insetBy(dx: innerDiameter * 0.22, dy: innerDiameter * 0.22)).fill()
        image.unlockFocus()
        return NSCursor(image: image, hotSpot: center)
    }

    private func drawToolbar() {
        rebuildToolbarItems()
        guard !pointerMode else { return }

        let union = toolbarItems.map(\.1).reduce(NSRect.null) { partial, rect in
            partial.isNull ? rect : partial.union(rect)
        }.insetBy(dx: -8, dy: -8)

        let panelAlpha: CGFloat = pointerMode ? 0.72 : 0.9
        NSColor.windowBackgroundColor.withAlphaComponent(panelAlpha).setFill()
        NSBezierPath(roundedRect: union, xRadius: 8, yRadius: 8).fill()
        let borderColor = pointerMode ? NSColor.systemOrange : NSColor.separatorColor
        borderColor.withAlphaComponent(0.75).setStroke()
        NSBezierPath(roundedRect: union, xRadius: 8, yRadius: 8).stroke()

        for (title, rect, _) in toolbarItems {
            drawButton(title: title, rect: rect)
        }
    }

    private func drawButton(title: String, rect: NSRect) {
        let isPressed = pressedToolbarLabel == title
        let isHovered = hoveredToolbarLabel == title
        let isFlashed = flashedToolbarLabel == title
        let buttonRect = (isPressed || isFlashed) ? rect.insetBy(dx: 2, dy: 2) : rect

        let backgroundAlpha = (isPressed || isFlashed) ? 1.0 : (isHovered ? 0.98 : 0.9)
        let background = isHovered || isPressed || isFlashed ? NSColor.selectedControlColor : NSColor.controlBackgroundColor
        background.withAlphaComponent(backgroundAlpha).setFill()
        NSBezierPath(roundedRect: buttonRect, xRadius: 6, yRadius: 6).fill()

        if isHovered || isPressed || isFlashed {
            NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
            let outline = NSBezierPath(roundedRect: buttonRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            outline.lineWidth = 1.5
            outline.stroke()
        }

        if title.hasPrefix("pen:") {
            let index = Int(title.dropFirst(4)) ?? 0
            let pen = penPalette[index]
            pen.color.withAlphaComponent(max(pen.alpha, 0.75)).setFill()
            NSBezierPath(ovalIn: buttonRect.insetBy(dx: 11, dy: 11)).fill()
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: buttonRect.midX - size.width / 2,
                              y: buttonRect.midY - size.height / 2),
                  withAttributes: attrs)
    }

    private func rebuildToolbarItems() {
        let gap: CGFloat = 6
        let labels = ["1 画笔", "pen:0", "pen:1", "pen:2", "pen:3", "pen:4", "pen:5", "↓", "↑", "2 橡皮", "3 撤销", "4 清空", "5 截图", "6 隐藏", "7 穿透", "8 激光", "完成"]
        let widths = labels.map(toolbarItemWidth)
        let totalWidth = widths.reduce(0, +) + CGFloat(labels.count - 1) * gap
        var x = bounds.maxX - totalWidth - 24
        let y = max(24, bounds.minY + 24)

        toolbarItems = labels.enumerated().map { index, label in
            let width = widths[index]
            let rect = NSRect(x: x, y: y, width: width, height: 38)
            x += width + gap
            return (label, rect, toolbarAction(for: label, index: index))
        }
    }

    private func toolbarItemWidth(_ label: String) -> CGFloat {
        if label.hasPrefix("pen:") || label == "↓" || label == "↑" {
            return 38
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        let width = (label as NSString).size(withAttributes: attrs).width + 24
        return max(48, ceil(width))
    }

    private func toolbarAction(for label: String, index: Int) -> () -> Void {
        if label.hasPrefix("pen:") {
            let penIndex = Int(label.dropFirst(4)) ?? 0
            return { [weak self] in
                self?.selectPen(penIndex)
            }
        }

        switch label {
        case "1 画笔":
            return { [weak self] in
                guard let self else { return }
                self.selectPen(self.currentPenIndex)
            }
        case "↓":
            return { [weak self] in self?.adjustBrushWidth(by: 0.85) }
        case "↑":
            return { [weak self] in self?.adjustBrushWidth(by: 1.18) }
        case "2 橡皮":
            return { [weak self] in self?.selectEraser() }
        case "3 撤销":
            return { [weak self] in self?.undo() }
        case "4 清空":
            return { [weak self] in self?.clearInk() }
        case "5 截图":
            return { [weak self] in self?.beginSnapshotSelection() }
        case "6 隐藏":
            return { [weak self] in self?.toggleInkVisible() }
        case "7 穿透":
            return { [weak self] in self?.togglePointerMode() }
        case "8 激光":
            return { [weak self] in self?.selectLaserPen() }
        case "完成":
            return { [weak self] in self?.onDismiss?() }
        default:
            return {}
        }
    }

    private func drawSnapshotSelection() {
        guard let snapshotRect else { return }
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        NSColor.clear.setFill()
        snapshotRect.fill(using: .clear)
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let path = NSBezierPath(rect: snapshotRect)
        path.lineWidth = 2
        path.stroke()
    }

    private func saveSnapshot(_ rectInView: NSRect) {
        guard let window else { return }
        let screenRect = NSRect(x: window.frame.minX + rectInView.minX,
                                y: window.frame.minY + rectInView.minY,
                                width: rectInView.width,
                                height: rectInView.height)
        window.orderOut(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let cgRect = CGRect(x: screenRect.minX,
                                y: NSScreen.virtualFrame.maxY - screenRect.maxY,
                                width: screenRect.width,
                                height: screenRect.height)
            guard let image = CGWindowListCreateImage(cgRect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else {
                window.makeKeyAndOrderFront(nil)
                return
            }

            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                window.makeKeyAndOrderFront(nil)
                return
            }

            let folder = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Pictures")
                .appendingPathComponent("MacPen")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
            let url = folder.appendingPathComponent("\(formatter.string(from: Date())).png")
            try? data.write(to: url)

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: image, size: screenRect.size)])
            window.makeKeyAndOrderFront(nil)
        }
    }
}

@MainActor
private final class PointerToolbarController {
    private let panel: NSPanel
    private let toolbarView: PointerToolbarView

    init(canvas: CanvasView) {
        toolbarView = PointerToolbarView(canvas: canvas)
        let size = toolbarView.preferredSize
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.contentView = toolbarView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    func show() {
        let size = toolbarView.preferredSize
        let frame = NSScreen.virtualFrame
        let origin = NSPoint(x: frame.maxX - size.width - 24, y: frame.minY + 24)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
    }
}

@MainActor
private final class PointerToolbarView: NSView {
    private weak var canvas: CanvasView?
    private var items: [(String, NSRect, () -> Void)] = []
    private var hoveredLabel: String?
    private var pressedLabel: String?
    private var flashedLabel: String?
    private var pendingAction: (() -> Void)?
    private var trackingArea: NSTrackingArea?

    init(canvas: CanvasView) {
        self.canvas = canvas
        super.init(frame: NSRect(origin: .zero, size: .zero))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        frame = NSRect(origin: .zero, size: preferredSize)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var preferredSize: NSSize {
        rebuildItems(in: NSRect(origin: .zero, size: NSSize(width: 1200, height: 54)))
        let union = items.map(\.1).reduce(NSRect.null) { partial, rect in
            partial.isNull ? rect : partial.union(rect)
        }
        return NSSize(width: union.width + 16, height: 54)
    }

    override func draw(_ dirtyRect: NSRect) {
        rebuildItems(in: bounds)
        let panelRect = bounds.insetBy(dx: 0.5, dy: 0.5)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8).fill()
        NSColor.systemOrange.withAlphaComponent(0.85).setStroke()
        let outline = NSBezierPath(roundedRect: panelRect, xRadius: 8, yRadius: 8)
        outline.lineWidth = 1.5
        outline.stroke()

        for (title, rect, _) in items {
            drawButton(title: title, rect: rect)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let next = items.first(where: { $0.1.contains(point) })?.0
        if hoveredLabel != next {
            hoveredLabel = next
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredLabel = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        rebuildItems(in: bounds)
        guard let item = items.first(where: { $0.1.contains(point) }) else { return }
        pressedLabel = item.0
        pendingAction = item.2
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let pressedLabel else { return }
        let point = convert(event.locationInWindow, from: nil)
        let releasedInside = items.contains { label, rect, _ in
            label == pressedLabel && rect.contains(point)
        }
        let action = pendingAction
        self.pressedLabel = nil
        pendingAction = nil
        needsDisplay = true
        if releasedInside {
            action?()
        }
    }

    private func rebuildItems(in rect: NSRect) {
        let labels = ["1 画笔", "pen:0", "pen:1", "pen:2", "pen:3", "pen:4", "pen:5", "↓", "↑", "2 橡皮", "3 撤销", "4 清空", "5 截图", "6 隐藏", "8 激光", "完成"]
        let gap: CGFloat = 6
        let widths = labels.map(toolbarItemWidth)
        let totalWidth = widths.reduce(0, +) + CGFloat(labels.count - 1) * gap
        var x = rect.maxX - totalWidth - 8
        if rect.width > totalWidth + 16 {
            x = 8
        }

        items = labels.enumerated().map { index, label in
            let width = widths[index]
            let itemRect = NSRect(x: x, y: 8, width: width, height: 38)
            x += width + gap
            return (label, itemRect, action(for: label))
        }
    }

    private func toolbarItemWidth(_ label: String) -> CGFloat {
        if label.hasPrefix("pen:") || label == "↓" || label == "↑" {
            return 38
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
        ]
        let width = (label as NSString).size(withAttributes: attrs).width + 24
        return max(48, ceil(width))
    }

    private func action(for label: String) -> () -> Void {
        if label.hasPrefix("pen:") {
            let penIndex = Int(label.dropFirst(4)) ?? 0
            return { [weak self] in
                self?.flashButton(label)
                self?.canvas?.selectPen(penIndex)
            }
        }

        switch label {
        case "1 画笔":
            return { [weak self] in self?.flashButton(label); self?.canvas?.selectCurrentPen() }
        case "↓":
            return { [weak self] in self?.flashButton(label); self?.canvas?.adjustBrushWidth(by: 0.85) }
        case "↑":
            return { [weak self] in self?.flashButton(label); self?.canvas?.adjustBrushWidth(by: 1.18) }
        case "2 橡皮":
            return { [weak self] in self?.flashButton(label); self?.canvas?.selectEraser() }
        case "3 撤销":
            return { [weak self] in self?.flashButton(label); self?.canvas?.undo() }
        case "4 清空":
            return { [weak self] in self?.flashButton(label); self?.canvas?.clearInk() }
        case "5 截图":
            return { [weak self] in self?.flashButton(label); self?.canvas?.beginSnapshotSelection() }
        case "6 隐藏":
            return { [weak self] in self?.flashButton(label); self?.canvas?.toggleInkVisible() }
        case "8 激光":
            return { [weak self] in self?.flashButton(label); self?.canvas?.selectLaserPen() }
        case "完成":
            return { [weak self] in self?.flashButton(label); self?.canvas?.onDismiss?() }
        default:
            return {}
        }
    }

    private func flashButton(_ label: String) {
        flashedLabel = label
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
            guard self?.flashedLabel == label else { return }
            self?.flashedLabel = nil
            self?.needsDisplay = true
        }
    }

    private func drawButton(title: String, rect: NSRect) {
        let isPressed = pressedLabel == title
        let isHovered = hoveredLabel == title
        let isFlashed = flashedLabel == title
        let buttonRect = (isPressed || isFlashed) ? rect.insetBy(dx: 2, dy: 2) : rect

        let background = isHovered || isPressed || isFlashed ? NSColor.selectedControlColor : NSColor.controlBackgroundColor
        background.withAlphaComponent((isPressed || isFlashed) ? 1.0 : 0.92).setFill()
        NSBezierPath(roundedRect: buttonRect, xRadius: 6, yRadius: 6).fill()

        if isHovered || isPressed || isFlashed {
            NSColor.controlAccentColor.withAlphaComponent(0.75).setStroke()
            let outline = NSBezierPath(roundedRect: buttonRect.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
            outline.lineWidth = 1.5
            outline.stroke()
        }

        if title.hasPrefix("pen:") {
            let index = Int(title.dropFirst(4)) ?? 0
            guard let canvas else { return }
            let pen = canvas.penPalette[index]
            pen.color.withAlphaComponent(max(pen.alpha, 0.75)).setFill()
            NSBezierPath(ovalIn: buttonRect.insetBy(dx: 11, dy: 11)).fill()
            return
        }

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let text = title as NSString
        let size = text.size(withAttributes: attrs)
        text.draw(at: NSPoint(x: buttonRect.midX - size.width / 2,
                              y: buttonRect.midY - size.height / 2),
                  withAttributes: attrs)
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard trimmed.count == 6, let value = Int(trimmed, radix: 16) else { return nil }
        self.init(red: CGFloat((value >> 16) & 0xff) / 255.0,
                  green: CGFloat((value >> 8) & 0xff) / 255.0,
                  blue: CGFloat(value & 0xff) / 255.0,
                  alpha: 1.0)
    }
}

@MainActor
private final class SettingsWindowController: NSObject {
    private let window: NSWindow
    private let onSave: (AppConfig) -> Void
    private let keyPopup = NSPopUpButton()
    private let cursorStylePopup = NSPopUpButton()
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command", target: nil, action: nil)
    private let shiftCheckbox = NSButton(checkboxWithTitle: "Shift", target: nil, action: nil)
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control", target: nil, action: nil)
    private let defaultPenSlider = NSSlider(value: 3, minValue: 1, maxValue: 8, target: nil, action: nil)
    private let defaultPenValueLabel = NSTextField(labelWithString: "")
    private let laserWidthSlider = NSSlider(value: 4, minValue: 2, maxValue: 16, target: nil, action: nil)
    private let laserWidthValueLabel = NSTextField(labelWithString: "")
    private let laserDurationSlider = NSSlider(value: 1.1, minValue: 0.2, maxValue: 3.0, target: nil, action: nil)
    private let laserDurationValueLabel = NSTextField(labelWithString: "")
    private var currentConfig: AppConfig
    private let supportedKeys = (["A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        + ["0","1","2","3","4","5","6","7","8","9"]
        + ["F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12"])

    init(config: AppConfig, onSave: @escaping (AppConfig) -> Void) {
        self.currentConfig = config
        self.onSave = onSave
        self.window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
                               styleMask: [.titled, .closable],
                               backing: .buffered,
                               defer: false)
        super.init()
        configureWindow()
        buildUI()
        update(config: config)
    }

    func show() {
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func update(config: AppConfig) {
        currentConfig = config
        if keyPopup.itemTitles.isEmpty {
            keyPopup.addItems(withTitles: supportedKeys)
        }
        if cursorStylePopup.itemTitles.isEmpty {
            cursorStylePopup.addItems(withTitles: AppConfig.CursorStyle.allCases.map(\.title))
        }
        keyPopup.selectItem(withTitle: config.hotKey.key.uppercased())
        cursorStylePopup.selectItem(withTitle: config.cursorStyle.title)
        commandCheckbox.state = config.hotKey.modifierKeys.contains(where: { ["command", "cmd"].contains($0.lowercased()) }) ? .on : .off
        shiftCheckbox.state = config.hotKey.modifierKeys.contains(where: { $0.lowercased() == "shift" }) ? .on : .off
        optionCheckbox.state = config.hotKey.modifierKeys.contains(where: { ["option", "alt"].contains($0.lowercased()) }) ? .on : .off
        controlCheckbox.state = config.hotKey.modifierKeys.contains(where: { ["control", "ctrl"].contains($0.lowercased()) }) ? .on : .off
        defaultPenSlider.doubleValue = config.defaultPenWidth
        laserWidthSlider.doubleValue = config.laserWidth
        laserDurationSlider.doubleValue = config.laserDuration
        refreshValueLabels()
    }

    private func configureWindow() {
        window.title = "MacPen Settings"
        window.isReleasedWhenClosed = false
    }

    private func buildUI() {
        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false

        let hotkeyRow = formRow(label: "启动快捷键", control: keyPopup)
        let cursorStyleRow = formRow(label: "笔尖样式", control: cursorStylePopup)
        let modifierRow = NSStackView(views: [commandCheckbox, shiftCheckbox, optionCheckbox, controlCheckbox])
        modifierRow.orientation = .horizontal
        modifierRow.spacing = 12

        defaultPenSlider.target = self
        defaultPenSlider.action = #selector(sliderChanged)
        laserWidthSlider.target = self
        laserWidthSlider.action = #selector(sliderChanged)
        laserDurationSlider.target = self
        laserDurationSlider.action = #selector(sliderChanged)

        let defaultPenRow = sliderRow(label: "默认笔粗细", slider: defaultPenSlider, valueLabel: defaultPenValueLabel)
        let laserWidthRow = sliderRow(label: "激光笔粗细", slider: laserWidthSlider, valueLabel: laserWidthValueLabel)
        let laserDurationRow = sliderRow(label: "激光停留时间", slider: laserDurationSlider, valueLabel: laserDurationValueLabel)

        let hint = NSTextField(wrappingLabelWithString: "修改后立即保存。全局快捷键重启应用即可继续使用新组合。")
        hint.textColor = .secondaryLabelColor

        let saveButton = NSButton(title: "保存", target: self, action: #selector(savePressed))
        saveButton.bezelStyle = .rounded
        let cancelButton = NSButton(title: "关闭", target: self, action: #selector(closePressed))
        cancelButton.bezelStyle = .rounded
        let buttonRow = NSStackView(views: [saveButton, cancelButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 10
        buttonRow.alignment = .trailing

        [hotkeyRow, cursorStyleRow, modifierRow, defaultPenRow, laserWidthRow, laserDurationRow, hint, buttonRow].forEach(root.addArrangedSubview)

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor)
        ])
        window.contentView = content
    }

    private func formRow(label: String, control: NSView) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let row = NSStackView(views: [title, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func sliderRow(label: String, slider: NSSlider, valueLabel: NSTextField) -> NSView {
        valueLabel.alignment = .right
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.setContentHuggingPriority(.required, for: .horizontal)
        let title = NSTextField(labelWithString: label)
        title.font = .systemFont(ofSize: 13, weight: .semibold)

        let top = NSStackView(views: [title, valueLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.distribution = .fillProportionally

        let block = NSStackView(views: [top, slider])
        block.orientation = .vertical
        block.spacing = 6
        return block
    }

    @objc private func sliderChanged() {
        refreshValueLabels()
    }

    @objc private func savePressed() {
        let modifiers = selectedModifierKeys()
        let newConfig = AppConfig(
            hotKey: .init(key: keyPopup.titleOfSelectedItem ?? "G", modifierKeys: modifiers),
            defaultPenWidth: defaultPenSlider.doubleValue.rounded(),
            cursorStyle: selectedCursorStyle(),
            laserDuration: laserDurationSlider.doubleValue,
            laserWidth: laserWidthSlider.doubleValue.rounded(),
            laserColorHex: currentConfig.laserColorHex
        )
        currentConfig = newConfig
        onSave(newConfig)
    }

    @objc private func closePressed() {
        window.orderOut(nil)
    }

    private func refreshValueLabels() {
        defaultPenValueLabel.stringValue = String(format: "%.0f", defaultPenSlider.doubleValue.rounded())
        laserWidthValueLabel.stringValue = String(format: "%.0f", laserWidthSlider.doubleValue.rounded())
        laserDurationValueLabel.stringValue = String(format: "%.1fs", laserDurationSlider.doubleValue)
    }

    private func selectedModifierKeys() -> [String] {
        var keys: [String] = []
        if commandCheckbox.state == .on { keys.append("command") }
        if shiftCheckbox.state == .on { keys.append("shift") }
        if optionCheckbox.state == .on { keys.append("option") }
        if controlCheckbox.state == .on { keys.append("control") }
        return keys
    }

    private func selectedCursorStyle() -> AppConfig.CursorStyle {
        AppConfig.CursorStyle.allCases.first(where: { $0.title == cursorStylePopup.titleOfSelectedItem }) ?? .whiteRingDot
    }
}

@main
@MainActor
enum MacPenApp {
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.run()
    }
}
