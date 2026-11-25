import SwiftUI

struct SourceSettings: View {
    let localServerURL: URL
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var polling: EventPolling
    @ObservedObject var region: EventRegion
    @ObservedObject var localServer: LocalMurmurServer
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Murmur sources").font(.headline)
                        Spacer()
                        Text("Include in polling").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("When several sources have events, they take turns in this order.")
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach($preferences.sources) { $source in
                        let index = preferences.sources.firstIndex { $0.id == source.id } ?? 0
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 32)
                                .contentShape(Rectangle())
                                .draggable(source.id.uuidString) { Text(source.name).padding(6) }
                                .help("Drag to reorder \(source.name)")
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name).font(.headline)
                                let address = source.resolvedAddress(localServerURL: localServerURL)
                                Text(address).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    .help(address)
                                Text(status(of: source))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Menu {
                                if source.mode != .local { Button("Edit source…") { editing = source } }
                                Button("Move up") { preferences.moveSource(source.id, to: index - 1) }
                                    .disabled(index == 0)
                                Button("Move down") { preferences.moveSource(source.id, to: index + 1) }
                                    .disabled(index + 1 >= preferences.sources.count)
                            } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel("Options for \(source.name)")
                            Toggle("Include \(source.name) in polling", isOn: $source.enabled)
                                .labelsHidden().toggleStyle(.switch)
                                .help("Include in polling")
                        }
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                        .dropDestination(for: String.self) { items, _ in
                            guard let value = items.first, let id = UUID(uuidString: value),
                                  preferences.sources.contains(where: { $0.id == id }) else { return false }
                            preferences.moveSource(id, to: index)
                            return true
                        }
                        Divider()
                    }
                    if preferences.sources.isEmpty {
                        Text("No sources configured").foregroundStyle(.secondary)
                    }
                }
                if preferences.usesRegion { RegionSettings(region: region) }
                LocalServerSettings(preferences: preferences, server: localServer)
            }
        }
    }

    private func status(of source: MurmurSource) -> String {
        if source.mode == .local && !localServer.state.isRunning { return "Server stopped" }
        if !source.enabled { return "Polling off" }
        return polling.status[source.id] ?? "Waiting for the next request"
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
                if !cleaned.address.isEmpty && cleaned.configuredURL == nil {
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
                .disabled(cleaned.name.isEmpty || cleaned.configuredURL == nil)
            }
        }
        .onAppear { editingName = true }
    }
}
