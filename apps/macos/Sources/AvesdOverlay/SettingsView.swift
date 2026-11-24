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
    @Published var page: SettingsPage = .display
}

struct SettingsHeading: View {
    let title: String

    var body: some View {
        Text(title).font(.system(size: 27, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
    }
}

struct SettingsRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(label)
                Spacer(minLength: 8)
                content()
            }
            .padding(.vertical, 12)
            Divider()
        }
    }
}

struct SettingsView: View {
    @ObservedObject var region: EventRegion
    @ObservedObject var preferences: DaemonPreferences
    @ObservedObject var polling: EventPolling
    let localServer: LocalMurmurServer
    let updates: SoftwareUpdates
    let cache: AirlineLogoCache?
    let preview: (PreviewKind) -> Void
    let changePrefetch: (Bool) -> Void
    let clearCache: () async throws -> Void

    var brandPresentation = 0
    @ObservedObject var navigation: SettingsNavigation
    @Environment(\.colorScheme) private var scheme
    @FocusState private var focusedPage: SettingsPage?
    @State private var statistics: LogoCacheStatistics?
    @State private var revision = 0
    @State private var showingAbout = false
    @State private var clearing = false
    @State private var errorMessage: String?

    private var accent: Color {
        scheme == .dark ? Color(red: 0.64, green: 0.77, blue: 0.88) : Color(red: 0.20, green: 0.36, blue: 0.51)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if navigation.page != .sources {
                        SettingsHeading(title: navigation.page.rawValue)
                    }
                    switch navigation.page {
                    case .display: displaySettings
                    case .sources: SourceSettings(preferences: preferences, polling: polling, region: region, localServer: localServer)
                    case .polling: PollingSettings(preferences: preferences)
                    case .maintenance: maintenanceSettings
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
            }
            .id(navigation.page)
            .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.99))
        }
        .tint(accent)
        .frame(minWidth: 640, minHeight: 420)
        .sheet(isPresented: $showingAbout) { AboutView() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            SidebarBrand { showingAbout = true }
                .id(brandPresentation)
                .padding(.horizontal, 8)
            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases) { page in
                    let selected = page == navigation.page
                    Button {
                        navigation.page = page
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: page.icon).frame(width: 18)
                            Text(page.rawValue).lineLimit(1)
                        }
                        .fontWeight(selected ? .semibold : .regular)
                        .foregroundStyle(selected ? accent : .primary)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 35, alignment: .leading)
                        .background(selected ? accent.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focused($focusedPage, equals: page)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .onMoveCommand { direction in
                let pages = SettingsPage.allCases
                guard let focusedPage, let index = pages.firstIndex(of: focusedPage),
                      direction == .down || direction == .up else { return }
                let next = pages[min(max(index + (direction == .down ? 1 : -1), 0), pages.count - 1)]
                self.focusedPage = next
                navigation.page = next
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 22)
        .frame(width: 190)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(scheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.21)
                                    : Color(red: 0.92, green: 0.94, blue: 0.96))
    }

    private var displaySettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsRow(label: "Display duration") {
                Picker("Display duration", selection: $preferences.displaySeconds) {
                    ForEach(DaemonPreferences.durations, id: \.self) { seconds in
                        Text("\(seconds) s").tag(seconds)
                    }
                }
                .labelsHidden().pickerStyle(.segmented).fixedSize()
            }
            Text("Event previews").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(PreviewKind.allCases, id: \.self) { event in
                    Button { preview(event) } label: {
                        Text(event.rawValue).frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("Preview \(event.rawValue)")
                }
            }
        }
    }

    private var maintenanceSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Airline logos").font(.headline)
            SettingsRow(label: "Preload common airlines") {
                Toggle("Preload common airlines", isOn: $preferences.preloadLogos)
                    .labelsHidden().toggleStyle(.switch)
                    .onChange(of: preferences.preloadLogos, perform: changePrefetch)
            }
            SettingsRow(label: "Local cache") {
                Text(cacheDescription).foregroundStyle(.secondary)
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
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            Text("Software updates").font(.headline)
            if let updater = updates.updater {
                UpdateSettings(updater: updater).toggleStyle(.switch)
            } else {
                Text("Software updates are unavailable in this build.").foregroundStyle(.secondary)
            }
        }
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
