import AppKit
import ServiceManagement
import SwiftUI

/// MacPen's own window: shows that MacPen is running and holds all of its settings.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    var onVisibilityChange: ((Bool) -> Void)?
    private let window: NSWindow
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        let hosting = NSHostingController(rootView: MainView(model: model))
        hosting.sizingOptions = [.minSize]
        window = NSWindow(contentViewController: hosting)
        super.init()
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "MacPen"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 580, height: 720))
        window.center()
        window.setFrameAutosaveName("MacPenMainWindow")
        window.delegate = self
    }

    func show() {
        model.refreshLaunchAtLogin()
        onVisibilityChange?(true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshLaunchAtLogin()
    }

    func windowDidResignKey(_ notification: Notification) {
        model.isRecordingHotKey = false
    }

    func windowWillClose(_ notification: Notification) {
        model.isRecordingHotKey = false
        onVisibilityChange?(false)
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                StatusHeader(model: model)
            }
            ShortcutSection(model: model)
            CursorStyleSection(model: model)
            PenSection(model: model)
            GeneralSection(model: model)
            AboutSection(model: model)
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct StatusHeader: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 60, height: 60)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("MacPen")
                        .font(.title2.weight(.semibold))
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.isDrawing ? Color.orange : Color.green)
                            .frame(width: 8, height: 8)
                        Text(model.isDrawing ? "正在标注" : "正在运行")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
                Spacer()
                Button {
                    model.toggleDrawing()
                } label: {
                    Text(model.isDrawing ? "结束标注" : "开始标注")
                        .frame(minWidth: 72)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            (Text("关掉这个窗口后，MacPen 仍会在菜单栏（")
                + Text(Image(systemName: "pencil.tip.crop.circle"))
                + Text("）里运行。随时按 ")
                + Text(model.config.hotKey.displayString).fontWeight(.semibold)
                + Text(" 开始标注，按 Esc 结束。"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

private struct ShortcutSection: View {
    @ObservedObject var model: AppModel

    private let overlayKeys: [(key: String, action: String)] = [
        ("1", "画笔"), ("2", "橡皮擦"),
        ("3", "撤销"), ("4", "清空"),
        ("5", "区域截图"), ("6", "隐藏 / 显示墨迹"),
        ("7", "鼠标穿透"), ("8", "激光笔"),
        ("[  ]", "笔变细 / 变粗"), ("Esc", "结束标注")
    ]

    var body: some View {
        Section {
            // Not LabeledContent: it aligns by text baseline, which the AppKit recorder lacks.
            HStack {
                Text("开始 / 结束标注")
                Spacer()
                HotKeyRecorder(hotKey: model.config.hotKey,
                               isRecording: $model.isRecordingHotKey) { hotKey in
                    model.config.hotKey = hotKey
                }
                .fixedSize()
            }
            if let error = model.hotKeyError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("标注时可以直接按这些键")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading,
                          spacing: 8) {
                    ForEach(overlayKeys, id: \.key) { item in
                        HStack(spacing: 8) {
                            KeyCap(item.key)
                            Text(item.action)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("快捷键")
        } footer: {
            Text("点击快捷键后按下新的组合即可修改，需要包含 ⌘、⌥ 或 ⌃。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct KeyCap: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 6)
            .frame(minWidth: 24, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.18)))
    }
}

private struct CursorStyleSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(AppConfig.CursorStyle.allCases, id: \.self) { style in
                    CursorStyleTile(style: style,
                                    penWidth: model.config.defaultPenWidth,
                                    isSelected: model.config.cursorStyle == style) {
                        model.config.cursorStyle = style
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("鼠标样式")
        } footer: {
            Text("画笔模式下鼠标显示成的样子。激光笔、橡皮擦和截图有各自固定的样式。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CursorStyleTile: View {
    let style: AppConfig.CursorStyle
    let penWidth: Double
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.33, green: 0.39, blue: 0.48),
                                                      Color(red: 0.55, green: 0.62, blue: 0.71)],
                                             startPoint: .topLeading,
                                             endPoint: .bottomTrailing))
                    Image(nsImage: CursorArt.pen(style: style,
                                                 color: .systemRed,
                                                 diameter: CGFloat(penWidth),
                                                 alpha: 1).preview(scale: 1.6))
                }
                .frame(height: 64)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                  lineWidth: isSelected ? 2.5 : 1))
                HStack(spacing: 3) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    Text(style.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PenSection: View {
    @ObservedObject var model: AppModel

    private var laserColor: Binding<Color> {
        Binding {
            Color(nsColor: NSColor(hex: model.config.laserColorHex) ?? .systemRed)
        } set: { color in
            if let hex = NSColor(color).hexString {
                model.config.laserColorHex = hex
            }
        }
    }

    var body: some View {
        Section("画笔") {
            SliderRow(title: "默认笔粗细",
                      value: $model.config.defaultPenWidth,
                      range: 1...8,
                      step: 1,
                      format: { String(format: "%.0f", $0) })
            SliderRow(title: "激光笔粗细",
                      value: $model.config.laserWidth,
                      range: 2...16,
                      step: 1,
                      format: { String(format: "%.0f", $0) })
            SliderRow(title: "激光笔停留时间",
                      value: $model.config.laserDuration,
                      range: 0.2...3.0,
                      step: 0.1,
                      format: { String(format: "%.1f 秒", $0) })
            ColorPicker("激光笔颜色", selection: laserColor, supportsOpacity: false)
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: (Double) -> String

    /// Rounds to `step` itself: a stepped Slider draws a tick mark for every step.
    private var steppedValue: Binding<Double> {
        Binding {
            value
        } set: { newValue in
            value = (newValue / step).rounded() * step
        }
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 10) {
                Slider(value: steppedValue, in: range)
                    .frame(width: 200)
                    .labelsHidden()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }
}

private struct GeneralSection: View {
    @ObservedObject var model: AppModel

    private var launchAtLogin: Binding<Bool> {
        Binding {
            model.launchAtLoginStatus == .enabled || model.launchAtLoginStatus == .requiresApproval
        } set: { enabled in
            model.setLaunchAtLogin(enabled)
        }
    }

    var body: some View {
        Section("通用") {
            Toggle("开机时自动启动", isOn: launchAtLogin)
                .disabled(!model.canLaunchAtLogin)
            if model.launchAtLoginStatus == .requiresApproval {
                HStack {
                    Text("还需要在“系统设置 › 通用 › 登录项”里允许 MacPen。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开登录项设置") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }
            if let error = model.launchAtLoginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            Toggle("打开 MacPen 时显示此窗口", isOn: $model.config.showWindowOnLaunch)
            Toggle(isOn: $model.config.showDockIcon) {
                Text("在程序坞中显示图标")
                Text("关闭后，窗口关上时 MacPen 只在菜单栏显示图标。")
            }
            LabeledContent("截图保存到") {
                HStack(spacing: 10) {
                    Text("~/Pictures/MacPen")
                        .foregroundStyle(.secondary)
                    Button("在访达中打开") {
                        let folder = AppConfig.snapshotFolder
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(folder)
                    }
                }
            }
        }
    }
}

private struct AboutSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Section {
            HStack {
                Text("版本 \(UpdateController.currentVersion)")
                    .foregroundStyle(.secondary)
                Spacer()
                if let version = model.availableUpdate {
                    Button("更新到 \(version)…") {
                        model.checkForUpdates()
                    }
                    .buttonStyle(.borderedProminent)
                } else if model.canCheckForUpdates {
                    Button("检查更新…") {
                        model.checkForUpdates()
                    }
                }
                Button("退出 MacPen") {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
