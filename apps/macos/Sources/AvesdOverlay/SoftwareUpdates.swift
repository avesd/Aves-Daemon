import AvesdEnvironment
import SwiftUI

#if canImport(Sparkle)
import Sparkle

@MainActor
final class SoftwareUpdates: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    private let environment: AppEnvironment
    private let item = NSMenuItem(title: SettingsText.updateCheck.string, action: nil, keyEquivalent: "")
    private weak var button: NSStatusBarButton?
    private var controller: SPUStandardUpdaterController?
    init(environment: AppEnvironment) { self.environment = environment }

    @ViewBuilder var settings: some View {
        if let updater = controller?.updater {
            Text(SettingsText.updateHeading.string).font(.headline)
            UpdateSettings(updater: updater).toggleStyle(.switch)
        }
    }

    func attach(to menu: NSMenu, button: NSStatusBarButton?) {
        guard environment.updatesConfigured else { return }
        self.button = button
        menu.addItem(item)
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
        item.title = version.map { SettingsText.updateAvailable($0).string } ?? SettingsText.updateCheck.string
        button?.image = MenuBarBrand.image(showsUpdate: version != nil)
        let label = version.map { SettingsText.updateStatus(environment.statusLabel, $0).string } ?? environment.statusLabel
        button?.toolTip = label
        button?.setAccessibilityLabel(label)
    }
}

private struct UpdateSettings: View {
    let updater: SPUUpdater
    @State private var checks = false
    @State private var downloads = false

    var body: some View {
        Toggle(SettingsText.updateAutoCheck.string, isOn: Binding(
            get: { checks }, set: { updater.automaticallyChecksForUpdates = $0 }
        ))
        .onReceive(updater.publisher(for: \.automaticallyChecksForUpdates)) { checks = $0 }

        Toggle(SettingsText.updateAutoInstall.string, isOn: Binding(
            get: { downloads }, set: { updater.automaticallyDownloadsUpdates = $0 }
        ))
        .disabled(!checks)
        .onReceive(updater.publisher(for: \.automaticallyDownloadsUpdates)) { downloads = $0 }
    }
}
#else
@MainActor
struct SoftwareUpdates {
    init(environment: AppEnvironment) {}
    var settings: some View { EmptyView() }
    func attach(to menu: NSMenu, button: NSStatusBarButton?) {}
}
#endif
