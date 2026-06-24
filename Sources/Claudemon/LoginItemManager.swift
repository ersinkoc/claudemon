import Foundation
import ServiceManagement
import os

private let loginLog = Logger(subsystem: "com.claudemon.app", category: "LoginItem")

/// Manages "launch at login" via `SMAppService.mainApp` (macOS 13+).
///
/// Persists the user's *intent* in UserDefaults and reflects the *actual*
/// system status (which may be `.requiresApproval` until the user approves the
/// item in System Settings > General > Login Items).
@MainActor
final class LoginItemManager: ObservableObject {

    static let intentKey = "launchAtLoginIntent"

    /// The user's desired on/off intent (drives the toggle).
    @Published var isEnabled: Bool {
        didSet {
            guard !isSyncing, oldValue != isEnabled else { return }
            UserDefaults.standard.set(isEnabled, forKey: Self.intentKey)
            apply(isEnabled)
            refreshStatus()
        }
    }

    /// The live system registration status.
    @Published private(set) var status: SMAppService.Status = .notRegistered

    /// Guards against the toggle's didSet firing while we sync from the system.
    private var isSyncing = false

    init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: Self.intentKey)
        refreshStatus()
    }

    /// True when macOS needs the user to approve the login item in Settings.
    var requiresApproval: Bool { status == .requiresApproval }

    func refreshStatus() {
        status = SMAppService.mainApp.status
        // Reflect reality: if the system reports enabled/notRegistered and that
        // disagrees with our intent, adopt the system's truth without
        // re-triggering register/unregister. `.requiresApproval` is left as-is
        // so the toggle keeps showing the user's pending intent.
        switch status {
        case .enabled where !isEnabled:
            isSyncing = true; isEnabled = true; isSyncing = false
        case .notRegistered where isEnabled:
            isSyncing = true; isEnabled = false; isSyncing = false
        default:
            break
        }
    }

    private func apply(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    loginLog.debug("registered login item")
                }
            } else {
                try SMAppService.mainApp.unregister()
                loginLog.debug("unregistered login item")
            }
        } catch {
            loginLog.error("login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Open the Login Items pane so the user can approve a pending item.
    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
