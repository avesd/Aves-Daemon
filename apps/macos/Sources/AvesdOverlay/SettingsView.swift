import SwiftUI

enum OverlayPreferences {
    static let durationKey = "flyoverDuration"
    static let prefetchKey = "prefetchCommonAirlines"
    static let durations = [3, 5, 8]
    static let defaultDuration = 5

    static func register() {
        UserDefaults.standard.register(defaults: [durationKey: defaultDuration, prefetchKey: true])
    }

    static var duration: TimeInterval {
        let seconds = UserDefaults.standard.integer(forKey: durationKey)
        return TimeInterval(durations.contains(seconds) ? seconds : defaultDuration)
    }
}

struct SettingsView: View {
    let cache: AirlineLogoCache?
    let previewFlight: () -> Void
    let previewRain: () -> Void
    let previewWorld: (PreviewKind) -> Void
    let changePrefetch: (Bool) -> Void
    let clearCache: () async throws -> Void

    var brandPresentation = 0

    @AppStorage(OverlayPreferences.durationKey) private var duration = OverlayPreferences.defaultDuration
    @AppStorage(OverlayPreferences.prefetchKey) private var prefetch = true
    @State private var statistics: LogoCacheStatistics?
    @State private var revision = 0
    @State private var showingAbout = false
    @State private var clearing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Preferences")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .padding(.leading, 20)
                .padding(.top, 16)
            settingsForm
            BrandFooter { showingAbout = true }
                .id(brandPresentation)
        }
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .sheet(isPresented: $showingAbout) { AboutView() }
    }

    private var settingsForm: some View {
        Form {
            Section("Screen-edge previews") {
                Picker("Display duration", selection: $duration) {
                    ForEach(OverlayPreferences.durations, id: \.self) { seconds in
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
            Section("Airline logos") {
                Toggle("Preload common airlines", isOn: Binding(get: { prefetch }, set: { enabled in
                    prefetch = enabled
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
