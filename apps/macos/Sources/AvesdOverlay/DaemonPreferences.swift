import Foundation
import Combine

struct MurmurSource: Codable, Identifiable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable { case regional, fixed, local }
    var id = UUID()
    var name: String
    var address: String
    var mode: Mode
    var enabled = true

    static let official = MurmurSource(name: "Murmur", address: "https://murmur-api.avesd.ai", mode: .regional)

    static let localPort: UInt16 = 47831
    static let local = MurmurSource(id: UUID(uuidString: "1FE1DA74-556B-4C3F-905B-B3C3C0542535")!,
                                    name: "Local server", address: "http://127.0.0.1:\(localPort)", mode: .local)

    var url: URL? {
        guard let components = URLComponents(string: address),
              let scheme = components.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = components.host, !host.isEmpty, components.fragment == nil,
              mode == .fixed || components.query == nil else { return nil }
        return components.url
    }

    func endpoint(cell: String?) -> URL? {
        guard enabled, let url else { return nil }
        if mode == .fixed { return url }
        let selectedCell = mode == .local ? (cell ?? RegionSelection.kyoto.cell) : cell
        guard let cell = selectedCell else { return nil }
        return url.appendingPathComponent("v1/regions/\(cell)/event")
    }
}

struct PollingPolicy: Codable, Equatable {
    static let minutes = 1...1440
    var base = 5
    var increasesAfterPlayback = true
    var step = 5
    var maximum = 15

    var validated: Self {
        var policy = self
        policy.base = min(max(base, Self.minutes.lowerBound), Self.minutes.upperBound)
        policy.step = min(max(step, Self.minutes.lowerBound), Self.minutes.upperBound)
        policy.maximum = min(max(maximum, policy.base), Self.minutes.upperBound)
        return policy
    }

    func nextInterval(after previous: Int, played: Bool) -> Int {
        played && increasesAfterPlayback ? min(previous + step, maximum) : base
    }
}

@MainActor
final class DaemonPreferences: ObservableObject {
    private let defaults: UserDefaults
    static let durations = [3, 5, 8]

    @Published var displaySeconds: Int {
        didSet { defaults.set(displaySeconds, forKey: "flyoverDuration") }
    }
    @Published var preloadLogos: Bool {
        didSet { defaults.set(preloadLogos, forKey: "prefetchCommonAirlines") }
    }
    @Published var localServerEnabled: Bool {
        didSet { defaults.set(localServerEnabled, forKey: "localServerEnabled") }
    }
    @Published var allowsTriggers: Bool {
        didSet { defaults.set(allowsTriggers, forKey: "localServerAllowsTriggers") }
    }
    @Published var sources: [MurmurSource] {
        didSet { persist(sources, key: "murmurSources") }
    }
    @Published private(set) var polling: PollingPolicy {
        didSet { persist(polling, key: "pollingPolicy") }
    }
    var usesRegion: Bool { sources.contains { $0.enabled && $0.mode == .regional } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        localServerEnabled = defaults.bool(forKey: "localServerEnabled")
        allowsTriggers = defaults.bool(forKey: "localServerAllowsTriggers")
        let seconds = defaults.integer(forKey: "flyoverDuration")
        displaySeconds = Self.durations.contains(seconds) ? seconds : 5
        preloadLogos = defaults.object(forKey: "prefetchCommonAirlines") as? Bool ?? true
        polling = defaults.data(forKey: "pollingPolicy").flatMap {
            try? JSONDecoder().decode(PollingPolicy.self, from: $0)
        }?.validated ?? PollingPolicy()

        if let stored = defaults.data(forKey: "murmurSources") {
            sources = (try? JSONDecoder().decode([MurmurSource].self, from: stored)) ?? []
        } else {
            if let legacy = defaults.string(forKey: "eventPollingURL") {
                sources = [MurmurSource(name: "Custom Murmur", address: legacy, mode: .fixed)]
            } else {
                sources = [.official]
            }
            persist(sources, key: "murmurSources")
        }
    }

    func addLocalSourceIfNeeded() {
        if !sources.contains(where: { $0.mode == .local }) { sources.append(.local) }
    }

    func moveSource(_ id: UUID, to index: Int) {
        guard let from = sources.firstIndex(where: { $0.id == id }), sources.indices.contains(index),
              from != index else { return }
        var order = sources
        order.insert(order.remove(at: from), at: index)
        sources = order
    }

    func setPolling(_ policy: PollingPolicy) {
        let validated = policy.validated
        if validated != polling { polling = validated }
    }

    private func persist(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

