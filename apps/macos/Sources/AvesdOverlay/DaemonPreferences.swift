import Foundation
import Combine

struct MurmurSource: Codable, Identifiable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable { case regional, fixed }
    var id = UUID()
    var name: String
    var address: String
    var mode: Mode
    var enabled = true

    static let official = MurmurSource(name: "Murmur", address: "https://murmur-api.avesd.ai", mode: .regional)

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
        guard let cell else { return nil }
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
    @Published var sources: [MurmurSource] {
        didSet { persist(sources, key: "murmurSources") }
    }
    @Published private(set) var polling: PollingPolicy {
        didSet { persist(polling, key: "pollingPolicy") }
    }
    var usesRegion: Bool { sources.contains { $0.enabled && $0.mode == .regional } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
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

    func setPolling(_ policy: PollingPolicy) {
        let validated = policy.validated
        if validated != polling { polling = validated }
    }

    private func persist(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

