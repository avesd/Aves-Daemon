import AvesdEnvironment
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
                    SettingsHeading(title: SettingsPage.sources.title)
                    Spacer()
                    Button { editing = MurmurSource(name: "", address: "", mode: .regional) } label: {
                        Label(SettingsText.sourceAdd.string, systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(SettingsText.sourceGroup.string).font(.headline)
                        Spacer()
                        Text(SettingsText.sourceInclude.string).font(.caption).foregroundStyle(.secondary)
                    }
                    Text(SettingsText.sourceOrderHelp.string)
                        .font(.callout).foregroundStyle(.secondary)
                    ForEach($preferences.sources) { $source in
                        let index = preferences.sources.firstIndex { $0.id == source.id } ?? 0
                        HStack(spacing: 12) {
                            Image(systemName: "line.3.horizontal")
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 32)
                                .contentShape(Rectangle())
                                .draggable(source.id.uuidString) { Text(source.displayName).padding(6) }
                                .help(SettingsText.sourceDrag(source.displayName).string)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.displayName).font(.headline)
                                let address = source.resolvedAddress(localServerURL: localServerURL)
                                Text(address).font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                                    .help(address)
                                Text(status(of: source))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            Menu {
                                if source.mode != .local { Button(SettingsText.sourceEditAction.string) { editing = source } }
                                Button(SettingsText.sourceUp.string) { preferences.moveSource(source.id, to: index - 1) }
                                    .disabled(index == 0)
                                Button(SettingsText.sourceDown.string) { preferences.moveSource(source.id, to: index + 1) }
                                    .disabled(index + 1 >= preferences.sources.count)
                            } label: { Image(systemName: "ellipsis.circle") }
                            .menuStyle(.borderlessButton).fixedSize()
                            .accessibilityLabel(SettingsText.sourceOptions(source.displayName).string)
                            Toggle(SettingsText.sourcePoll(source.displayName).string, isOn: $source.enabled)
                                .labelsHidden().toggleStyle(.switch)
                                .help(SettingsText.sourceInclude.string)
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
                        Text(SettingsText.sourceNone.string).foregroundStyle(.secondary)
                    }
                }
                if preferences.usesRegion { RegionSettings(region: region) }
                LocalServerSettings(preferences: preferences, server: localServer)
            }
        }
    }

    private func status(of source: MurmurSource) -> String {
        if source.mode == .local && !localServer.state.isRunning { return SettingsText.sourceStopped.string }
        if !source.enabled { return SettingsText.sourcePollingOff.string }
        return polling.status[source.id] ?? SettingsText.sourceWaiting.string
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
        value.name = value.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        value.address = value.address.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }

    private var sourceIndex: Int? {
        preferences.sources.firstIndex { $0.id == draft.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsHeading(title: sourceIndex == nil ? SettingsText.sourceAdd.string : SettingsText.sourceEdit.string)
            VStack(alignment: .leading, spacing: 5) {
                Text(SettingsText.sourceName.string)
                TextField(SettingsText.sourceName.string, text: Binding(
                    get: { draft.displayName },
                    set: { if $0 != draft.displayName { draft.name = $0 } }
                )).labelsHidden().focused($editingName)
            }
            Picker(SettingsText.sourceEndpoint.string, selection: $draft.mode) {
                Text(SettingsText.sourceRegional.string).tag(MurmurSource.Mode.regional)
                Text(SettingsText.sourceFixed.string).tag(MurmurSource.Mode.fixed)
            }
            VStack(alignment: .leading, spacing: 5) {
                let label = draft.mode == .regional ? SettingsText.sourceBaseURL.string : SettingsText.sourceEventURL.string
                Text(label)
                TextField(label, text: $draft.address).labelsHidden()
                if draft.mode == .regional {
                    Text(SettingsText.sourceUrlHelp.string)
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !cleaned.address.isEmpty && cleaned.configuredURL == nil {
                    Text(SettingsText.sourceInvalidURL.string).foregroundStyle(.red)
                }
            }
            HStack {
                if let index = sourceIndex {
                    Button(SettingsText.sourceRemove.string, role: .destructive) {
                        preferences.sources.remove(at: index)
                        finish()
                    }
                }
                Spacer()
                Button(SettingsText.actionCancel.string, action: finish).keyboardShortcut(.cancelAction)
                Button(SettingsText.actionSave.string) {
                    if let index = sourceIndex { preferences.sources[index] = cleaned }
                    else { preferences.sources.append(cleaned) }
                    finish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(cleaned.displayName.isEmpty || cleaned.configuredURL == nil)
            }
        }
        .onAppear { editingName = true }
    }
}
