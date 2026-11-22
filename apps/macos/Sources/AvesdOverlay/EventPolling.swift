import Foundation

@MainActor
struct EventPolling {
    let endpoint: URL
    let defaults: UserDefaults
    let session: URLSession
    private(set) var delayMinutes = 5
    private var retryAfterSeconds: TimeInterval = 0
    var nextDelaySeconds: TimeInterval {
        max(TimeInterval(delayMinutes * 60), retryAfterSeconds)
    }
    private let historyKey = "recentlyPlayedEvents"

    init(endpoint: URL, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.defaults = defaults
        self.session = session
    }

    mutating func run(play: (Data) -> Bool) async {
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(nextDelaySeconds)) }
            catch { return }
            await poll(play: play)
        }
    }

    mutating func poll(play: (Data) -> Bool) async {
        let cutoff = Date().addingTimeInterval(-3 * 60 * 60)
        var history = (defaults.dictionary(forKey: historyKey) as? [String: Date] ?? [:])
            .filter { $0.value > cutoff }
        defaults.set(history, forKey: historyKey)
        let query = history.keys.sorted().map { URLQueryItem(name: "played", value: $0) }
        let request = URLRequest(url: endpoint.appending(queryItems: query),
                                 cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        struct Header: Decodable { let id: String }
        let previousDelay = delayMinutes
        delayMinutes = 5
        retryAfterSeconds = 0
        guard let (data, response) = try? await session.data(for: request),
              !Task.isCancelled, let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 503, let header = http.value(forHTTPHeaderField: "Retry-After") {
            retryAfterSeconds = Self.retryDelay(header, now: Date())
            return
        }
        guard http.statusCode == 200,
              let event = try? JSONDecoder().decode(Header.self, from: data),
              !event.id.isEmpty, history[event.id] == nil, play(data) else { return }

        history[event.id] = Date()
        defaults.set(history, forKey: historyKey)
        delayMinutes = min(previousDelay + 5, 15)
    }

    static func retryDelay(_ header: String, now: Date) -> TimeInterval {
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
