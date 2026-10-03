import AppKit
import ServiceManagement

/// State shared by the menu bar item, the overlay and the main window.
///
/// The main window edits `config` directly; every change is saved and handed to
/// `configDidChange` so it takes effect immediately.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            config.save()
            configDidChange?(config)
        }
    }
    @Published var isDrawing = false
    /// Why the global hot key could not be registered, if it could not.
    @Published var hotKeyError: String?
    @Published var isRecordingHotKey = false {
        didSet {
            guard isRecordingHotKey != oldValue else { return }
            recordingHotKeyDidChange?(isRecordingHotKey)
        }
    }
    @Published var availableUpdate: String?
    @Published private(set) var launchAtLoginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var launchAtLoginError: String?

    var canCheckForUpdates = false
    /// `swift run` builds are not app bundles, so they cannot be login items.
    let canLaunchAtLogin = Bundle.main.bundleURL.pathExtension == "app"

    var configDidChange: ((AppConfig) -> Void)?
    var recordingHotKeyDidChange: ((Bool) -> Void)?
    var toggleDrawing: () -> Void = {}
    var checkForUpdates: () -> Void = {}

    init() {
        config = AppConfig.load()
        refreshLaunchAtLogin()
    }

    /// The user can also change this in System Settings, so it is re-read whenever the window is shown.
    func refreshLaunchAtLogin() {
        guard canLaunchAtLogin else { return }
        launchAtLoginStatus = SMAppService.mainApp.status
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        refreshLaunchAtLogin()
    }
}
