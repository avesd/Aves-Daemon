import SwiftUI

struct SourceSettings: View {
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var polling: EventPolling
    @ObservedObject var region: EventRegion
    @State private var editing: MurmurSource?

    var body: some View {
        if let source = editing {
            SourceEditor(source: source, preferences: preferences) { editing = nil }
        } else {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SettingsHeading(title: SettingsPage.sources.rawValue)
                    Spacer()
                    Button { editing = MurmurSource(name: "", address: "", mode: .regional) } label: {
                        Label("Add source", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 0) {
                    ForEach($preferences.sources) { $source in
                        HStack(spacing: 12) {
                            Image(systemName: source.mode == .regional ? "antenna.radiowaves.left.and.right" : "server.rack")
                                .foregroundStyle(.tint)
                                .frame(width: 32, height: 32)
                                .background(.tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name).font(.headline)
                                Text(source.address).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    .help(source.address)
                                Text(source.enabled ? polling.status[source.id] ?? "Waiting for the next request" : "Disabled")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Button { editing = source } label: { Image(systemName: "pencil") }
                                .accessibilityLabel("Edit \(source.name)")
                                .help("Edit \(source.name)")
                            Toggle("Enable \(source.name)", isOn: $source.enabled)
                                .labelsHidden().toggleStyle(.switch)
                        }
                        .padding(.vertical, 12)
                        Divider()
                    }
                    if preferences.sources.isEmpty {
                        Text("No sources configured").foregroundStyle(.secondary)
                    }
                }
                if preferences.usesRegion { RegionSettings(region: region) }
            }
        }
    }
}

private struct SourceEditor: View {
    @ObservedObject var preferences: DaemonPreferences
    @State private var draft: MurmurSource
    @FocusState private var editingName: Bool
    let finish: () -> Void

    init(source: MurmurSource, preferences: DaemonPreferences, finish: @escaping () -> Void) {
        _draft = State(initialValue: source)
        self.preferences = preferences
        self.finish = finish
    }

    private var cleaned: MurmurSource {
        var value = draft
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        value.address = value.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var sourceIndex: Int? {
        preferences.sources.firstIndex { $0.id == draft.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(title: sourceIndex == nil ? "Add source" : "Edit source")
            VStack(alignment: .leading, spacing: 5) {
                Text("Source name")
                TextField("Source name", text: $draft.name).labelsHidden().focused($editingName)
            }
            Picker("Endpoint type", selection: $draft.mode) {
                Text("Follow selected area").tag(MurmurSource.Mode.regional)
                Text("Fixed event URL").tag(MurmurSource.Mode.fixed)
            }
            VStack(alignment: .leading, spacing: 5) {
                let label = draft.mode == .regional ? "API base URL" : "Event URL"
                Text(label)
                TextField(label, text: $draft.address).labelsHidden()
                if draft.mode == .regional {
                    Text("The app appends /v1/regions/{cell}/event to the base URL.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !cleaned.address.isEmpty && cleaned.url == nil {
                    Text("Enter a valid HTTP or HTTPS URL.").foregroundStyle(.red)
                }
            }
            HStack {
                if let index = sourceIndex {
                    Button("Remove source", role: .destructive) {
                        preferences.sources.remove(at: index)
                        finish()
                    }
                }
                Spacer()
                Button("Cancel", action: finish).keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let index = sourceIndex { preferences.sources[index] = cleaned }
                    else { preferences.sources.append(cleaned) }
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleaned.name.isEmpty || cleaned.url == nil)
            }
        }
        .onAppear { editingName = true }
    }
}
