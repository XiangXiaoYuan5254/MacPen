import AppKit
import Sparkle

/// Checks the GitHub release appcast for new versions using Sparkle.
///
/// MacPen is a menu bar app, so scheduled update alerts that arrive while the user
/// is busy elsewhere are surfaced as a "gentle reminder" in the status menu instead
/// of popping a window behind other apps.
@MainActor
final class UpdateController: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var onAvailableUpdateChange: (() -> Void)?
    private(set) var availableVersion: String?
    private var controller: SPUStandardUpdaterController?

    var isEnabled: Bool {
        controller != nil
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    override init() {
        super.init()
        // `swift run` has no bundle Info.plist, so Sparkle would fail to start with an error alert.
        guard Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else {
            return
        }
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    private func setAvailableVersion(_ version: String?) {
        guard availableVersion != version else { return }
        availableVersion = version
        onAvailableUpdateChange?()
    }

    // MARK: - SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool {
        true
    }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                              andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Right after launch Sparkle shows the alert in focus; otherwise we badge the menu bar icon.
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                   forUpdate update: SUAppcastItem,
                                                   state: SPUUserUpdateState) {
        if !handleShowingUpdate {
            setAvailableVersion(update.displayVersionString)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        setAvailableVersion(nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        setAvailableVersion(nil)
    }
}
