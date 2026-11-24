import SwiftUI

struct LocalServerSettings: View {
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var server: LocalMurmurServer
    @State private var confirmReset = false
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Local server").font(.headline)
            Toggle("Enable local server", isOn: $preferences.localServerEnabled)
            switch server.state {
            case .stopped: EmptyView()
            case .starting: Text("Starting…").foregroundStyle(.secondary)
            case .failed(let reason):
                Text(reason).foregroundStyle(.red)
                Button("Retry") { server.start() }
            case .running(let port):
                let address = "http://127.0.0.1:\(port)"
                Text("Listening at \(address)").font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                ViewThatFits(in: .horizontal) {
                    HStack { actions(address) }
                    VStack(alignment: .leading) { actions(address) }
                }
                Toggle("Allow immediate display (trigger)", isOn: $preferences.allowsTriggers)
                if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            }
        }
        .toggleStyle(.switch)
        .alert("Reset local server token?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Reset token", role: .destructive) {
                do {
                    try server.resetToken()
                    feedback = "Token reset. Copy the new token to your scripts."
                } catch { feedback = error.localizedDescription }
            }
        } message: { Text("Scripts using the previous token will need the new one.") }
    }

    @ViewBuilder private func actions(_ address: String) -> some View {
        Button("Copy address") { copy(address, message: "Address copied.") }
        Button("Copy token") {
            if let token = server.token { copy(token, message: "Token copied.") }
        }
        Button("Reset token…") { confirmReset = true }
    }

    private func copy(_ text: String, message: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        feedback = pasteboard.setString(text, forType: .string) ? message : "Could not copy to the clipboard."
    }
}
