import AvesdEnvironment
import Foundation
import Combine

@MainActor
final class EventPolling: ObservableObject {
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    typealias Play = (_ data: Data, _ expires: TimeInterval?, _ resolve: @escaping (OverlaySession.Presentation) -> Void) -> Bool
    private struct Destination: Hashable, Sendable {
        let id: UUID
        let url: URL
        let isLocal: Bool

        func pollURL(played: [String]) -> URL {
            guard !played.isEmpty, var address = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
            var query = URLComponents()
            query.queryItems = played.map { URLQueryItem(name: "played", value: $0) }
            // Murmur decodes '+' as a space in a query. Encode literal plus signs in new IDs.
            let history = query.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            address.percentEncodedQuery = [address.percentEncodedQuery, history].compactMap { $0 }
                .filter { !$0.isEmpty }.joined(separator: "&")
            return address.url ?? url
        }

        var historyScope: String {
            "\(id)/\(url.scheme ?? "")/\(url.host ?? "")/\(url.port ?? -1)"
        }
    }
    private enum Outcome: Sendable {
        case event(id: String, data: Data, expires: TimeInterval? = nil), empty, retry(Date), failed(String)

        var summary: String {
            switch self {
            case .event: SettingsText.pollReceived.string
            case .empty: SettingsText.pollEmpty.string
            case .retry(let date): SettingsText.pollRetry(date.formatted()).string
            case .failed(let reason): reason
            }
        }
    }

    private let defaults: UserDefaults
    private let localServerURL: URL
    private let localEvents: LocalEventStore
    private let fetch: Fetch
    private var cooldowns: [Destination: Date] = [:]
    private var lastPlayedSource: UUID?
    private var triggerGeneration: UInt = 0
    private var history: [String: Date]
    private var known: [String: [String: Date]]
    private var pendingSources: [String: Set<String>] = [:]
    @Published private(set) var status: [UUID: String] = [:]

    init(defaults: UserDefaults, localServerURL: URL, localEvents: LocalEventStore,
         fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }) {
        self.defaults = defaults
        self.localServerURL = localServerURL
        self.localEvents = localEvents
        self.fetch = fetch
        history = defaults.dictionary(forKey: "recentlyPlayedEvents") as? [String: Date] ?? [:]
        known = defaults.dictionary(forKey: "playedEventsBySource") as? [String: [String: Date]] ?? [:]
    }

    func run(preferences: DaemonPreferences, region: EventRegion, sources: () -> [MurmurSource], play: Play) async {
        let policy = preferences.polling
        var minutes = policy.base
        while !Task.isCancelled {
            let available = destinations(sources(), cell: region.availableCell)
            let earliest = available.map { cooldowns[$0]?.timeIntervalSinceNow ?? 0 }.min() ?? 0
            do { try await Task.sleep(for: .seconds(max(Double(minutes * 60), earliest))) }
            catch { return }
            if preferences.usesRegion { region.refreshIfNeeded() }
            let played = await poll(sources: sources, cell: { region.availableCell },
                                    cellAfterRefresh: { await region.cellAfterRefresh() }, play: play)
            minutes = policy.nextInterval(after: minutes, played: played)
        }
    }

    private func destinations(_ sources: [MurmurSource], cell: String?) -> [Destination] {
        sources.compactMap { source in
            let isLocal = source.mode == .local
            return source.endpoint(cell: isLocal ? nil : cell, localServerURL: localServerURL)
                .map { Destination(id: source.id, url: $0, isLocal: isLocal) }
        }
    }

    func poll(sources: () -> [MurmurSource], cell: () -> String?, cellAfterRefresh: (() async -> String?)? = nil,
              now: () -> Date = Date.init, play: Play) async -> Bool {
        let generationAtStart = triggerGeneration
        let configuredSources = sources()
        let initialCell = cell()
        var configured = destinations(configuredSources, cell: initialCell)
        pruneHistory()

        let roundStart = now()
        cooldowns = cooldowns.filter { $0.value > roundStart }
        var ready = configured.filter { cooldowns[$0] == nil }
        let results = await withTaskGroup(of: (Destination, Outcome).self) { group in
            @MainActor func request(_ destination: Destination) {
                if destination.isLocal {
                    let played = Set(history.keys)
                    group.addTask { [localEvents] in
                        do {
                            guard let candidate = try await localEvents.nextCandidate(excluding: played, now: roundStart) else {
                                return (destination, .empty)
                            }
                            return (destination, .event(id: candidate.id, data: candidate.data, expires: candidate.expires))
                        } catch {
                            return (destination, .failed("HTTP 503"))
                        }
                    }
                } else {
                    let ids = (known[destination.historyScope] ?? [:]).filter { $0.key.utf8.count <= 256 }
                        .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                        .prefix(64).map(\.key)
                    let request = URLRequest(url: destination.pollURL(played: ids), cachePolicy: .reloadIgnoringLocalCacheData,
                                             timeoutInterval: 30)
                    group.addTask { [fetch] in (destination, await Self.request(request, fetch: fetch)) }
                }
            }

            for destination in ready { request(destination) }
            if initialCell == nil, configuredSources.contains(where: { $0.enabled && $0.mode == .regional }),
               let refreshedCell = await cellAfterRefresh?(), !Task.isCancelled {
                let updated = destinations(configuredSources, cell: refreshedCell)
                let newDestinations = updated.filter { !configured.contains($0) && (cooldowns[$0] ?? .distantPast) <= now() }
                for destination in newDestinations { request(destination) }
                ready = updated.filter { ready.contains($0) || newDestinations.contains($0) }
                configured = updated
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
        var suppliers: [String: Set<String>] = [:]
        for source in order {
            guard let result = results[source] else { continue }
            status[source.id] = result.summary
            switch result {
            case .retry(let date):
                cooldowns[source] = date
            case .event(let id, _, let expires) where expires.map({ $0 > now().timeIntervalSince1970 }) ?? true:
                if registerSupplier(source.historyScope, for: id) == nil {
                    suppliers[id, default: []].insert(source.historyScope)
                }
            default: break
            }
        }
        saveHistory()
        for source in order {
            guard !Task.isCancelled, generationAtStart == triggerGeneration else { return false }
            guard case .event(let id, let data, let expires) = results[source],
                  expires.map({ $0 > now().timeIntervalSince1970 }) ?? true, let scopes = suppliers[id] else { continue }
            let result: OverlaySession.Presentation? = await withCheckedContinuation { reply in
                let accepted = requestPlayback(id: id, data: data, scopes: scopes, expires: expires, play: play) { result in
                    if result == .shown {
                        self.lastPlayedSource = source.id
                        if self.status[source.id] != nil { self.status[source.id] = SettingsText.pollPlayed.string }
                    }
                    reply.resume(returning: result)
                }
                if !accepted { reply.resume(returning: nil) }
            }
            if result == .shown { return true }
            if result == .superseded { return false }
        }
        return false
    }

    enum TriggerResult: String { case started, alreadyPlayed = "already_played", unavailable }

    func trigger(id: String, data: Data, play: Play) -> TriggerResult {
        pruneHistory()
        let scope = Destination(id: MurmurSource.local.id, url: localServerURL, isLocal: true).historyScope
        let existing = registerSupplier(scope, for: id)
        if existing == .alreadyPlayed {
            saveHistory()
            return .alreadyPlayed
        }
        if existing == nil, !requestPlayback(id: id, data: data, scopes: [scope], play: play) {
            return .unavailable
        }
        triggerGeneration &+= 1
        return .started
    }

    private func registerSupplier(_ scope: String, for id: String) -> TriggerResult? {
        if let date = history[id] {
            known[scope, default: [:]][id] = date
            return .alreadyPlayed
        }
        if pendingSources[id] != nil {
            pendingSources[id]?.insert(scope)
            return .started
        }
        return nil
    }

    private func requestPlayback(id: String, data: Data, scopes: Set<String>, expires: TimeInterval? = nil, play: Play,
                                 onResolution: @escaping (OverlaySession.Presentation) -> Void = { _ in }) -> Bool {
        pendingSources[id] = scopes
        let accepted = play(data, expires) { [self] result in
            let suppliers = pendingSources.removeValue(forKey: id) ?? []
            if result == .shown {
                let date = Date()
                history[id] = date
                for scope in suppliers { known[scope, default: [:]][id] = date }
                saveHistory()
            }
            onResolution(result)
        }
        if !accepted { pendingSources[id] = nil }
        return accepted
    }

    private func pruneHistory() {
        let cutoff = Date().addingTimeInterval(-3 * 60 * 60)
        history = history.filter { $0.value > cutoff }
        known = known.mapValues { $0.filter { $0.value > cutoff } }.filter { !$0.value.isEmpty }
    }

    private func saveHistory() {
        defaults.set(history, forKey: "recentlyPlayedEvents")
        defaults.set(known, forKey: "playedEventsBySource")
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
            guard let http = response as? HTTPURLResponse else { return .failed(SettingsText.pollInvalidResponse.string) }
            switch http.statusCode {
            case 200:
                guard let event = try? JSONDecoder().decode(Header.self, from: data), !event.id.isEmpty else {
                    return .failed(SettingsText.pollInvalidEvent.string)
                }
                return .event(id: event.id, data: data)
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
