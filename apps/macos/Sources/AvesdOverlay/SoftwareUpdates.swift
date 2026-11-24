import Sparkle
import SwiftUI

@MainActor
final class SoftwareUpdates: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private let item = NSMenuItem(title: "Check for Updates…", action: nil, keyEquivalent: "")
    private weak var button: NSStatusBarButton?
    private var controller: SPUStandardUpdaterController?
    var updater: SPUUpdater? { controller?.updater }

    func attach(to menu: NSMenu, button: NSStatusBarButton?) {
        self.button = button
        menu.addItem(item)
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else {
            item.isEnabled = false
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        item.target = controller
        item.action = #selector(SPUStandardUpdaterController.checkForUpdates(_:))
        controller.startUpdater()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        if !handleShowingUpdate { showReminder(version: update.displayVersionString) }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        showReminder(version: nil)
    }

    func standardUserDriverWillFinishUpdateSession() {
        showReminder(version: nil)
    }

    private func showReminder(version: String?) {
        item.title = version.map { "Update Available · \($0)…" } ?? "Check for Updates…"
        button?.image = MenuBarBrand.image(showsUpdate: version != nil)
        let label = version.map { "Aves Daemon, version \($0) available" } ?? "Aves Daemon"
        button?.toolTip = label
        button?.setAccessibilityLabel(label)
    }
}

struct UpdateSettings: View {
    let updater: SPUUpdater
    @State private var checks = false
    @State private var downloads = false

    var body: some View {
        Toggle("Automatically check for updates", isOn: Binding(
            get: { checks }, set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { checks = $0 }

        Toggle("Automatically download and install updates", isOn: Binding(
            get: { downloads }, set: { updater.automaticallyDownloadsUpdates = $0 }
        ))
        .disabled(!checks)
        .onReceive(updater.publisher(for: \.automaticallyDownloadsUpdates)) { downloads = $0 }
    }
}
