import AvesdEnvironment
import SwiftUI

struct LocalServerSettings: View {
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var server: LocalMurmurServer
    @State private var confirmReset = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingsText.serverTitle.string).font(.headline)
            Toggle(SettingsText.serverEnable.string, isOn: $preferences.localServerEnabled)
            switch server.state {
            case .stopped: EmptyView()
            case .starting: Text(SettingsText.serverStarting.string).foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason).foregroundStyle(.red)
                Button(SettingsText.serverRetry.string) { server.start() }
            case .running(let port):
                let address = "http://127.0.0.1:\(port)"
                Text(SettingsText.serverListening(address).string).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                ViewThatFits(in: .horizontal) {
                    HStack { actions(address) }
                    VStack(alignment: .leading) { actions(address) }
                }
                Toggle(SettingsText.serverTrigger.string, isOn: $preferences.allowsTriggers)
                if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
        .alert(SettingsText.serverConfirmReset.string, isPresented: $confirmReset) {
            Button(SettingsText.actionCancel.string, role: .cancel) {}
            Button(SettingsText.serverReset.string, role: .destructive) {
                do {
                    try server.resetToken()
                    feedback = SettingsText.serverResetDone.string
                } catch { feedback = error.localizedDescription }
            }
        } message: { Text(SettingsText.serverResetHelp.string) }
    }

    @ViewBuilder private func actions(_ address: String) -> some View {
        Button(SettingsText.serverCopyAddress.string) { copy(address, message: SettingsText.serverAddressCopied.string) }
        Button(SettingsText.serverCopyToken.string) {
            if let token = server.token { copy(token, message: SettingsText.serverTokenCopied.string) }
        }
        Button(SettingsText.serverResetAction.string) { confirmReset = true }
    }

    private func copy(_ text: String, message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        feedback = pasteboard.setString(text, forType: .string) ? message : SettingsText.serverCopyFailed.string
    }
}
