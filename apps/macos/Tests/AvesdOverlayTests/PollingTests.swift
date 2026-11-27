import AvesdEnvironment
import Foundation
import Testing
@testable import AvesdOverlay

@MainActor
func withDefaults(_ test: (UserDefaults) async throws -> Void) async rethrows {
    let suite = "AvesdTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    try await test(defaults)
}

private actor Feeds {
    struct Call {
        let host: String
        let path: String
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
        calls.append(Call(host: host, path: url.path, played: ids))
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
        let sources = ["cooldown.test", "first.test", "second.test"].map { (host: String) in
            MurmurSource(name: host, address: "https://\(host)/event", mode: .fixed)
        }
        let feeds = Feeds()
        let events = LocalEventStore(url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString))
        let polling = EventPolling(defaults: defaults, localServerURL: URL(string: "http://localhost")!, localEvents: events,
                                   fetch: { try await feeds.fetch($0) })
        var played: [Data] = []
        for _ in 0..<2 {
            let didPlay = await polling.poll(sources: { sources }, cell: { nil }) { data, _, resolve in
                played.append(data)
                resolve(.shown)
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

@MainActor
@Test func supersededPollCanBeTriggeredAgainAndOnlyShownEventsSurviveRestart() async throws {
    try await withDefaults { defaults in
        func note(_ id: String) -> Data {
            Data(#"{"id":"\#(id)","kind":"note","occurred_at":"2026-01-01T00:00:00Z","data":{"summary":"\#(id)"}}"#.utf8)
        }
        let base = URL(string: "http://127.0.0.1:28375")!
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = LocalEventStore(url: directory.appending(path: "events.sqlite"))
        let b = note("B")
        _ = try await events.put(id: "B", event: b, expires: nil)
        let polling = EventPolling(defaults: defaults, localServerURL: base, localEvents: events)
        let overlay = OverlaySession()
        var now = ContinuousClock.now
        var shown: [String] = []
        var requests = 0
        @MainActor func display(_ data: Data, expires: TimeInterval?, resolve: @escaping (OverlaySession.Presentation) -> Void) -> Bool {
            requests += 1
            return overlay.play(.event(data), reduced: false, duration: 5, at: now, expires: expires) { result in
                if result == .shown, let content = overlay.content { shown.append(content.headline) }
                resolve(result)
            }
        }
        @MainActor func trigger(_ id: String) -> EventPolling.TriggerResult {
            polling.trigger(id: id, data: note(id), play: display)
        }

        try #require(trigger("A") == .started)
        now += .seconds(1)
        try #require(overlay.advance(to: now, pointer: .zero))
        let (queued, signal) = AsyncStream<Void>.makeStream()
        let round = Task {
            defer { signal.finish() }
            return await polling.poll(sources: { [.local] }, cell: { nil }) { data, expires, resolve in
                let accepted = display(data, expires: expires, resolve: resolve)
                signal.yield(())
                return accepted
            }
        }
        var queue = queued.makeAsyncIterator()
        try #require(await queue.next() != nil)
        #expect(trigger("B") == .started && requests == 2)
        now += .milliseconds(40)
        try #require(trigger("C") == .started)
        now += .milliseconds(160)
        try #require(overlay.advance(to: now, pointer: .zero))
        #expect(await round.value == false)
        #expect(shown == ["A", "C"])
        #expect(polling.status[MurmurSource.local.id] == SettingsText.pollReceived.string)

        let restarted = EventPolling(defaults: defaults, localServerURL: base, localEvents: events)
        #expect(restarted.trigger(id: "C", data: note("C"), play: display) == .alreadyPlayed)
        #expect(restarted.trigger(id: "B", data: b) { _, _, _ in false } == .unavailable)
        #expect(trigger("B") == .started)
        #expect(shown == ["A", "C", "B"])
        #expect(trigger("B") == .alreadyPlayed)
    }
}

@MainActor
@Test func localQueueUsesCompletePlaybackHistory() async throws {
    try await withDefaults { defaults in
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = LocalEventStore(url: directory.appending(path: "events.sqlite"))
        let polling = EventPolling(defaults: defaults, localServerURL: URL(string: "http://localhost")!, localEvents: events)
        let notes = (1...66).map { Data(#"{"id":"note-\#($0)"}"#.utf8) }
        for (index, note) in notes.enumerated() {
            _ = try await events.put(id: "note-\(index + 1)", event: note, expires: nil)
        }

        var played: [Data] = []
        for _ in 0..<notes.count {
            let displayed = await polling.poll(sources: { [.local] }, cell: { nil }) { data, _, resolve in
                played.append(data)
                resolve(.shown)
                return true
            }
            #expect(displayed)
        }
        #expect(played == Array(notes.reversed()))
        #expect(try await events.candidate(excluding: []) == notes.last)
        let repeated = await polling.poll(sources: { [.local] }, cell: { nil }) { _, _, _ in
            Issue.record("A played note re-entered the queue")
            return false
        }
        #expect(!repeated)
    }
}

@MainActor
private final class PollClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
@Test(arguments: [true, false])
func localCandidateExpiringDuringTheRoundLeavesAnotherSourceEligible(explicitExpiry: Bool) async throws {
    try await withDefaults { defaults in
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = LocalEventStore(url: directory.appending(path: "events.sqlite"))
        let prepared = Date()
        let deadline = prepared.addingTimeInterval(explicitExpiry ? 10 : 3 * 60 * 60)
        let start = deadline.addingTimeInterval(-1)
        let local = Data(#"{"id":"local"}"#.utf8)
        _ = try await events.put(id: "local", event: local, expires: explicitExpiry ? deadline : nil, now: prepared)
        _ = try await events.put(id: "local", event: local, expires: nil, now: start)
        #expect(try await events.nextCandidate(excluding: [], now: start)?.expires == deadline.timeIntervalSince1970)

        let other = Data(#"{"id":"other"}"#.utf8)
        let fixed = MurmurSource(name: "Fixed", address: "https://fixed.test/event", mode: .fixed)
        let clock = PollClock(start)
        let polling = EventPolling(defaults: defaults, localServerURL: URL(string: "http://localhost")!, localEvents: events) { request in
            await MainActor.run { clock.date = deadline }
            return (other, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        var played: [Data] = []
        let displayed = await polling.poll(sources: { [.local, fixed] }, cell: { nil }, now: { clock.date }) { data, _, resolve in
            played.append(data)
            resolve(.shown)
            return true
        }
        #expect(displayed && played == [other])
        #expect(defaults.dictionary(forKey: "recentlyPlayedEvents")?["local"] == nil)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func localCandidateExpiringDuringReplacementLetsAnotherSourcePlay() async throws {
    try await withDefaults { defaults in
        func note(_ id: String) -> Data {
            Data(#"{"id":"\#(id)","kind":"note","occurred_at":"2026-01-01T00:00:00Z","data":{"summary":"\#(id)"}}"#.utf8)
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let events = LocalEventStore(url: directory.appending(path: "events.sqlite"))
        let clock = PollClock(Date())
        let deadline = clock.date.addingTimeInterval(1)
        let local = note("Local")
        _ = try await events.put(id: "Local", event: local, expires: deadline, now: clock.date)

        let other = note("Other")
        let fixed = MurmurSource(name: "Fixed", address: "https://fixed.test/event", mode: .fixed)
        let polling = EventPolling(defaults: defaults, localServerURL: URL(string: "http://localhost")!, localEvents: events) { request in
            (other, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let overlay = OverlaySession(now: { clock.date })
        var time = ContinuousClock.now
        try #require(overlay.play(.event(note("Current")), reduced: false, duration: 5, at: time))
        time += .seconds(1)
        try #require(overlay.advance(to: time, pointer: .zero))

        let (queued, signal) = AsyncStream<Void>.makeStream()
        var shown: [String] = []
        let round = Task {
            defer { signal.finish() }
            return await polling.poll(sources: { [.local, fixed] }, cell: { nil }, now: { clock.date }) { data, expires, resolve in
                let accepted = overlay.play(.event(data), reduced: false, duration: 5, at: time, expires: expires) { result in
                    if result == .shown, let content = overlay.content { shown.append(content.headline) }
                    resolve(result)
                }
                if data == local { signal.yield(()) }
                return accepted
            }
        }
        var pending = queued.makeAsyncIterator()
        try #require(await pending.next() != nil)
        #expect(overlay.content?.headline == "Current")
        clock.date = deadline
        time += .seconds(1)
        _ = overlay.advance(to: time, pointer: .zero)
        #expect(await round.value)
        #expect(shown == ["Other"])
        #expect(defaults.dictionary(forKey: "recentlyPlayedEvents")?["Local"] == nil)
    }
}
