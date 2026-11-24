import Foundation
import Combine

@MainActor
final class EventPolling: ObservableObject {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private struct Destination: Hashable, Sendable {
        let id: UUID
        let url: URL

        var historyScope: String {
            "\(id)/\(url.scheme ?? "")/\(url.host ?? "")/\(url.port ?? -1)"
        }
    }
    private enum Outcome: Sendable {
        case event(String, Data), empty, retry(Date), failed(String)

        var summary: String {
            switch self {
            case .event: "Received an event"
            case .empty: "No event available"
            case .retry(let date): "Retry after \(date.formatted())"
            case .failed(let reason): reason
            }
        }
    }

    private let defaults: UserDefaults
    private let fetch: Fetch
    private var cooldowns: [Destination: Date] = [:]
    private var lastPlayedSource: UUID?
    @Published private(set) var status: [UUID: String] = [:]

    init(defaults: UserDefaults = .standard, fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.defaults = defaults
        self.fetch = fetch
    }

    func run(preferences: DaemonPreferences, region: EventRegion, play: (Data) -> Bool) async {
        let policy = preferences.polling
        var minutes = policy.base
        while !Task.isCancelled {
            let available = destinations(preferences.sources, cell: region.availableCell)
            let earliest = available.map { cooldowns[$0]?.timeIntervalSinceNow ?? 0 }.min() ?? 0
            do { try await Task.sleep(for: .seconds(max(Double(minutes * 60), earliest))) }
            catch { return }
            if preferences.usesRegion { region.refreshIfNeeded() }
            let played = await poll(sources: { preferences.sources }, cell: { region.availableCell }, play: play)
            minutes = policy.nextInterval(after: minutes, played: played)
        }
    }

    private func destinations(_ sources: [MurmurSource], cell: String?) -> [Destination] {
        sources.compactMap { source in
            source.endpoint(cell: cell).map { Destination(id: source.id, url: $0) }
        }
    }

    func poll(sources: () -> [MurmurSource], cell: () -> String?, play: (Data) -> Bool) async -> Bool {
        let configured = destinations(sources(), cell: cell())
        let cutoff = Date().addingTimeInterval(-3 * 60 * 60)
        var history = (defaults.dictionary(forKey: "recentlyPlayedEvents") as? [String: Date] ?? [:])
            .filter { $0.value > cutoff }
        var known = (defaults.dictionary(forKey: "playedEventsBySource") as? [String: [String: Date]] ?? [:])
            .mapValues { $0.filter { $0.value > cutoff } }.filter { !$0.value.isEmpty }

        let now = Date()
        cooldowns = cooldowns.filter { $0.value > now }
        let ready = configured.filter { cooldowns[$0] == nil }
        let results = await withTaskGroup(of: (Destination, Outcome).self) { group in
            for destination in ready {
                let ids = known[destination.historyScope]?.keys.sorted() ?? []
                let query = ids.map { URLQueryItem(name: "played", value: $0) }
                let url = query.isEmpty ? destination.url : destination.url.appending(queryItems: query)
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
                group.addTask { [fetch] in (destination, await Self.request(request, fetch: fetch)) }
            }
            var results: [Destination: Outcome] = [:]
            for await (source, outcome) in group { results[source] = outcome }
            return results
        }
        guard !Task.isCancelled else { return false }
        let current = destinations(sources(), cell: cell())
        var order = ready.filter { current.contains($0) }
        if let lastPlayedSource, let last = configured.firstIndex(where: { $0.id == lastPlayedSource }) {
            let rotated = configured.suffix(from: last + 1) + configured.prefix(through: last)
            order = rotated.filter { order.contains($0) }
        }
        var played = false
        for source in order {
            guard let result = results[source] else { continue }
            status[source.id] = result.summary
            switch result {
            case .retry(let date):
                cooldowns[source] = date
            case .event(let id, let data):
                if history[id] == nil && !played && play(data) {
                    history[id] = Date()
                    lastPlayedSource = source.id
                    played = true
                    status[source.id] = "Played an event"
                }
            default: break
            }
        }
        // Share a played ID with a source only after that source supplied it.
        for source in order {
            if case .event(let id, _) = results[source], let date = history[id] {
                known[source.historyScope, default: [:]][id] = date
            }
        }
        defaults.set(history, forKey: "recentlyPlayedEvents")
        defaults.set(known, forKey: "playedEventsBySource")
        return played
    }

    func clearStatus(for ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        status = status.filter { !ids.contains($0.key) }
        cooldowns = cooldowns.filter { !ids.contains($0.key.id) }
    }

    private nonisolated static func request(_ request: URLRequest, fetch: Fetch) async -> Outcome {
        struct Header: Decodable { let id: String }
        do {
            let (data, response) = try await fetch(request)
            guard let http = response as? HTTPURLResponse else { return .failed("Invalid response") }
            switch http.statusCode {
            case 200:
                guard let event = try? JSONDecoder().decode(Header.self, from: data), !event.id.isEmpty else {
                    return .failed("Invalid event")
                }
                return .event(event.id, data)
            case 204: return .empty
            case 503, 429:
                if let header = http.value(forHTTPHeaderField: "Retry-After") {
                    let delay = retryDelay(header, now: Date())
                    if delay > 0 { return .retry(Date().addingTimeInterval(delay)) }
                }
                fallthrough
            default: return .failed("HTTP \(http.statusCode)")
            }
        } catch { return .failed(error.localizedDescription) }
    }

    nonisolated static func retryDelay(_ header: String, now: Date) -> TimeInterval {
        let value = header.trimmingCharacters(in: .whitespaces)
        // Keep even an oversized upstream delay representable by the sleep clock.
        let limit = TimeInterval(UInt32.max)
        if !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }) {
            return min(TimeInterval(value) ?? limit, limit)
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["EEE, dd MMM yyyy HH:mm:ss 'GMT'", "EEEE, dd-MMM-yy HH:mm:ss 'GMT'", "EEE MMM d HH:mm:ss yyyy"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return min(max(0, date.timeIntervalSince(now)), limit)
            }
        }
        return 0
    }
}
