import SwiftUI

struct SourceSettings: View {
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var polling: EventPolling
    @ObservedObject var region: EventRegion
    @State private var editing: MurmurSource?

    var body: some View {
        Form {
            Section {
                ForEach($preferences.sources) { $source in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(source.name)
                            Text(source.address).lineLimit(1).truncationMode(.middle)
                                .foregroundStyle(.secondary)
                            Text(source.enabled ? polling.status[source.id] ?? "Waiting for the next request" : "Disabled")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Edit") { editing = source }
                            .accessibilityLabel("Edit \(source.name)")
                        Toggle("Enable \(source.name)", isOn: $source.enabled)
                            .labelsHidden().toggleStyle(.switch)
                    }
                }
                Button("Add Source…") {
                    editing = MurmurSource(name: "", address: "", mode: .regional)
                }
            }
            if preferences.usesRegion { RegionSettings(region: region) }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { source in
            SourceEditor(source: source, preferences: preferences)
        }
    }
}

private struct SourceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var preferences: DaemonPreferences
    @State private var draft: MurmurSource

    init(source: MurmurSource, preferences: DaemonPreferences) {
        _draft = State(initialValue: source)
        self.preferences = preferences
    }

    private var cleaned: MurmurSource {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.address = value.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data source").font(.headline)
            Form {
                TextField("Name", text: $draft.name)
                Picker("Endpoint", selection: $draft.mode) {
                    Text("Follow selected area").tag(MurmurSource.Mode.regional)
                    Text("Fixed event URL").tag(MurmurSource.Mode.fixed)
                }
                TextField(draft.mode == .regional ? "API base URL" : "Event URL", text: $draft.address)
                if draft.mode == .regional {
                    Text("The app appends /v1/regions/{cell}/event to the base URL.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !cleaned.address.isEmpty && cleaned.url == nil {
                    Text("Enter a valid HTTP or HTTPS URL.").foregroundStyle(.red)
                }
            }
            HStack {
                if preferences.sources.contains(where: { $0.id == draft.id }) {
                    Button("Remove Source", role: .destructive) {
                        preferences.sources.removeAll { $0.id == draft.id }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let index = preferences.sources.firstIndex(where: { $0.id == draft.id }) {
                        preferences.sources[index] = cleaned
                    } else { preferences.sources.append(cleaned) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleaned.name.isEmpty || cleaned.url == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

