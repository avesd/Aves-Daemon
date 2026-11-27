import AvesdEnvironment
import CoreLocation
import SwiftUI

struct RegionSettings: View {
    @ObservedObject var region: EventRegion
    @State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsRow(label: SettingsText.regionArea.string) {
                Menu(region.locating ? SettingsText.regionLocating.string : region.selection.label) {
                    Button(SettingsText.regionUseDevice.string) { region.useMyLocation() }
                        .disabled(region.locating)
                    Button(SettingsText.regionChoose.string) { choosing = true }
                    Button(SettingsText.regionReset.string) { region.select(.kyoto) }
                }
                .fixedSize()
                .accessibilityLabel(SettingsText.regionArea.string)
                .accessibilityValue(region.selection.label)
            }
            if let message = region.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $choosing) {
            PlacePicker { selection in
                region.select(selection)
                choosing = false
            }
        }
    }
}

private struct PlacePicker: View {
    let select: (RegionSelection) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [CLPlacemark] = []
    @State private var search: Task<Void, Never>?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SettingsText.regionPickerTitle.string).font(.headline)
            HStack {
                TextField(SettingsText.regionQuery.string, text: $query)
                    .onSubmit { find() }
                Button(SettingsText.regionFind.string) { find() }.disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message { Text(message).font(.callout).foregroundStyle(.secondary) }
            ForEach(matches.indices, id: \.self) { index in
                let match = matches[index]
                let name = [match.locality ?? match.name, match.administrativeArea, match.country]
                    .compactMap { $0 }.joined(separator: ", ")
                if let coordinate = match.location?.coordinate, let cell = EventRegion.cell(for: coordinate) {
                    Button(name.isEmpty ? query : name) { select(.place(name: name.isEmpty ? query : name, cell: cell)) }
                }
            }
            HStack {
                Button(SettingsText.regionReset.string) { select(.kyoto) }
                Spacer()
                Button(SettingsText.actionCancel.string) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onChange(of: query) { _ in
            search?.cancel()
            matches = []
            message = nil
        }
        .onDisappear { search?.cancel() }
    }

    private func find() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        search?.cancel()
        matches = []
        message = SettingsText.regionSearching.string
        search = Task {
            do {
                let places = try await CLGeocoder().geocodeAddressString(text)
                guard !Task.isCancelled else { return }
                matches = places.filter { $0.location != nil }
                message = matches.isEmpty ? SettingsText.regionNoResults.string : nil
            } catch {
                guard !Task.isCancelled else { return }
                message = SettingsText.regionSearchFailed.string
            }
        }
    }
}
