import Foundation
import Testing
@testable import AvesdOverlay

@MainActor
private func withDefaults(_ test: (UserDefaults) async throws -> Void) async rethrows {
    let suite = "AvesdTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try await test(defaults)
}

@MainActor
@Test func legacySettingsSurviveUpgradeAndSourceRemoval() async throws {
    try await withDefaults { defaults in
        defaults.set("http://legacy.test/feed?area=x", forKey: "eventPollingURL")
        defaults.set(8, forKey: "flyoverDuration")
        defaults.set(false, forKey: "prefetchCommonAirlines")
        let prefs = DaemonPreferences(defaults: defaults)
        let source = try #require(prefs.sources.first)
        #expect(prefs.sources.count == 1)
        #expect(source.endpoint(cell: nil)?.absoluteString == "http://legacy.test/feed?area=x")
        #expect(!prefs.usesRegion && prefs.displaySeconds == 8 && !prefs.preloadLogos)
        var policy = PollingPolicy()
        policy.base = 12
        policy.maximum = 8
        prefs.setPolling(policy)
        prefs.sources = []
        let reopened = DaemonPreferences(defaults: defaults)
        #expect(reopened.sources.isEmpty)
        #expect(reopened.polling.maximum == 12 && reopened.polling.base == 12)
    }
}

@Test func intervalsFollowPlayback() {
    var policy = PollingPolicy()
    #expect(policy.nextInterval(after: 5, played: true) == 10)
    #expect(policy.nextInterval(after: 15, played: true) == 15)
    #expect(policy.nextInterval(after: 15, played: false) == 5)
    policy.increasesAfterPlayback = false
    #expect(policy.nextInterval(after: 10, played: true) == 5)
}

private actor Feeds {
    struct Call {
        let host: String
        let played: [String]
    }
    private(set) var calls: [Call] = []
    private(set) var peakConcurrency = 0
    private var active = 0

    func fetch(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let url = try #require(request.url)
        let host = try #require(url.host)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let ids = query.filter { $0.name == "played" }.compactMap(\.value)
        calls.append(Call(host: host, played: ids))
        active += 1
        peakConcurrency = max(active, peakConcurrency)
        defer { active -= 1 }
        try await Task.sleep(for: .milliseconds(40))
        let limited = host == "cooldown.test"
        let http = try #require(HTTPURLResponse(url: url, statusCode: limited ? 503 : 200, httpVersion: nil,
                                              headerFields: limited ? ["Retry-After": "7200"] : [:]))
        return (Data("{\"id\":\"\(host)-\(ids.count)\"}".utf8), http)
    }
}

@MainActor
@Test func concurrentSourcesRotateAndRespectIndividualCooldowns() async throws {
    await withDefaults { defaults in
        let sources = ["cooldown.test", "first.test", "second.test"].map {
            MurmurSource(name: $0, address: "https://\($0)/event", mode: .fixed)
        }
        let feeds = Feeds()
        let polling = EventPolling(defaults: defaults, fetch: { try await feeds.fetch($0) })
        var played: [Data] = []
        for _ in 0..<2 {
            let didPlay = await polling.poll(sources: { sources }, cell: { nil }) {
                played.append($0)
                return true
            }
            #expect(didPlay)
        }
        #expect(played.map { String(decoding: $0, as: UTF8.self) } ==
                    ["{\"id\":\"first.test-0\"}", "{\"id\":\"second.test-0\"}"])
        let calls = await feeds.calls
        #expect(await feeds.peakConcurrency == 3)
        #expect(calls.filter { $0.host == "cooldown.test" }.count == 1)
        #expect(calls.last { $0.host == "first.test" }?.played == ["first.test-0"])
        #expect(calls.last { $0.host == "second.test" }?.played == [])
    }
}

