import SwiftUI

enum SettingsPage: String, CaseIterable, Identifiable {
    case display = "Display & previews"
    case sources = "Data sources"
    case polling = "Rhythm"
    case maintenance = "Maintenance"

    var id: Self { self }
    var icon: String {
        switch self {
        case .display: "display"
        case .sources: "antenna.radiowaves.left.and.right"
        case .polling: "clock"
        case .maintenance: "wrench.and.screwdriver"
        }
    }
}

@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var page: SettingsPage? = .display
}

struct SettingsView: View {
    @ObservedObject var region: EventRegion
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var polling: EventPolling
    let updates: SoftwareUpdates
    let cache: AirlineLogoCache?
    let previewFlight: () -> Void
    let previewRain: () -> Void
    let previewWorld: (PreviewKind) -> Void
    let changePrefetch: (Bool) -> Void
    let clearCache: () async throws -> Void

    var brandPresentation = 0

    @ObservedObject var navigation: SettingsNavigation
    @State private var statistics: LogoCacheStatistics?
    @State private var revision = 0
    @State private var showingAbout = false
    @State private var clearing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $navigation.page) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 185, max: 235)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                Text((navigation.page ?? .display).rawValue)
                    .font(.title.bold())
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                switch navigation.page ?? .display {
                case .display: displaySettings
                case .sources: SourceSettings(preferences: preferences, polling: polling, region: region)
                case .polling: PollingSettings(preferences: preferences)
                case .maintenance: maintenanceSettings
                }
                BrandFooter { showingAbout = true }
                    .id(brandPresentation)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $showingAbout) { AboutView() }
    }

    private var displaySettings: some View {
        Form {
            Section("Screen-edge previews") {
                Picker("Display duration", selection: $preferences.displaySeconds) {
                    ForEach(DaemonPreferences.durations, id: \.self) { seconds in
                        Text("\(seconds) s").tag(seconds)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("Flight preview") {
                    Button("Preview", action: previewFlight)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Preview Flyover")
                }
                LabeledContent("Rain preview") {
                    Button("Preview", action: previewRain)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Preview Rain")
                }
                LabeledContent("World event preview") {
                    Menu("Preview") {
                        ForEach(PreviewKind.worldEvents, id: \.self) { event in
                            Button(event.rawValue) { previewWorld(event) }
                        }
                    }
                    .fixedSize()
                    .accessibilityLabel("Preview world event")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var maintenanceSettings: some View {
        Form {
            Section("Software updates") {
                if let updater = updates.updater {
                    UpdateSettings(updater: updater)
                } else {
                    Text("Software updates are unavailable in this build.").foregroundStyle(.secondary)
                }
            }
            Section("Airline logos") {
                Toggle("Preload common airlines", isOn: Binding(get: { preferences.preloadLogos }, set: { enabled in
                    preferences.preloadLogos = enabled
                    changePrefetch(enabled)
                }))
                LabeledContent("Local cache") {
                    Text(cacheDescription).foregroundStyle(.secondary)
                }
                Button("Clear Logo Cache") {
                    clearing = true
                    errorMessage = nil
                    Task {
                        do { try await clearCache() }
                        catch { errorMessage = error.localizedDescription }
                        clearing = false
                        revision += 1
                    }
                }
                .disabled(cache == nil || clearing || (statistics?.isEmpty ?? true))
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .formStyle(.grouped)
        .task(id: revision) {
            do {
                let snapshot = try await cache?.statistics()
                if !Task.isCancelled { statistics = snapshot }
            } catch {
                if !Task.isCancelled { statistics = nil; errorMessage = error.localizedDescription }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AirlineLogoCache.didChange).receive(on: RunLoop.main)) { _ in revision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in revision += 1 }
    }

    private var cacheDescription: String {
        guard cache != nil else { return "Unavailable" }
        guard let statistics else { return errorMessage == nil ? "Loading…" : "Unavailable" }
        let size = statistics.bytes == 0 ? "0 bytes" : ByteCountFormatter.string(fromByteCount: Int64(statistics.bytes), countStyle: .file)
        return "\(statistics.count) \(statistics.count == 1 ? "logo" : "logos") · \(size)"
    }
}
