import Foundation
import Testing
@testable import AvesdOverlay

private struct Reply {
    let code: Int
    let data: Data

    var fields: [String: String] { (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:] }
}

private func request(_ base: URL, _ path: String, method: String = "GET", token: String? = nil,
                     body: Data? = nil) async throws -> Reply {
    var request = URLRequest(url: URL(string: path, relativeTo: base)!, cachePolicy: .reloadIgnoringLocalCacheData,
                             timeoutInterval: 3)
    request.httpMethod = method
    request.httpBody = body
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
    let (data, response) = try await URLSession.shared.data(for: request)
    return Reply(code: try #require(response as? HTTPURLResponse).statusCode, data: data)
}

@MainActor
private func start(_ server: LocalMurmurServer) async throws -> URL {
    server.start()
    let deadline = ContinuousClock.now + .seconds(5)
    while server.state == .starting && ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    guard case .running(let port) = server.state else {
        throw NSError(domain: "LocalServerTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Listener state: \(server.state)"])
    }
    return URL(string: "http://127.0.0.1:\(port)")!
}

@MainActor
@Test func localServerPreparesPollsAndTriggersThroughLoopback() async throws {
    try await withDefaults { defaults in
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appending(path: "events.sqlite")
        let prefs = DaemonPreferences(defaults: defaults)
        var handleTrigger: (String, Data) -> EventPolling.TriggerResult = { _, _ in .unavailable }
        let overlay = OverlaySession()
        var key = "first"
        var presentations = 0
        @MainActor func show(_ data: Data) -> Bool {
            guard overlay.reset(.event(data), reduced: true, duration: 3) else { return false }
            presentations += 1
            return true
        }
        let server = LocalMurmurServer(port: 0, database: database, credential: { reset in
            if reset { key = "second" }
            return key
        }, allowsTrigger: { prefs.allowsTriggers },
           trigger: { handleTrigger($0, $1) }, onReady: prefs.addLocalSourceIfNeeded)
        defer { server.stop() }
        #expect(!prefs.localServerEnabled && !prefs.allowsTriggers)
        let base = try await start(server)
        let polling = EventPolling(defaults: defaults, localServerURL: base)
        handleTrigger = { polling.trigger(id: $0, data: $1, play: show) }
        #expect(prefs.sources.map(\.mode) == [.regional, .local])
        let feed = "/v1/regions/862e6140fffffff/event"
        let note = Data(#"{"id":"build/+42","kind":"note","occurred_at":"2026-01-01T12:00:00Z","data":{"summary":"Build ready","detail":"42 checks passed."}}"#.utf8)
        let put = "/v1/events/build%2F%2B42"
        let trigger = "/v1/trigger"
        #expect(try await request(base, feed).code == 204)
        #expect(try await request(base, put, method: "PUT", body: note).code == 401)
        #expect(try await request(base, trigger, method: "POST", token: key, body: note).code == 403)
        #expect(try await request(base, put, method: "PUT", token: key, body: note).code == 201)
        #expect(try await request(base, put, method: "PUT", token: key, body: note).code == 200)
        #expect(try await request(base, feed).data == note)
        #expect(try await request(base, feed + "?played=other&played=build%2F%2B42").code == 204)
        #expect(try await request(base, "/v1/regions/invalid/event").code == 400)
        #expect(try await request(base, "/v1/events/different", method: "PUT", token: key, body: note).code == 422)
        let malformed = Data(#"{"id":"x","kind":"note","occurred_at":"2026-01-01T12:00:00Z","data":{"summary":" "}}"#.utf8)
        #expect(try await request(base, "/v1/events/x", method: "PUT", token: key, body: malformed).code == 422)
        #expect(presentations == 0)

        let source = try #require(prefs.sources.first { $0.mode == .local })
        let played = await polling.poll(sources: { [source] }, cell: { nil }, play: show)
        #expect(played && presentations == 1)
        _ = await polling.poll(sources: { [source] }, cell: { nil }, play: show)
        #expect(polling.status[source.id] == "No event available")
        #expect(overlay.content?.headline == "Build ready")
        #expect(overlay.content?.rows == [["Detail", "42 checks passed."]])
        #expect(!overlay.frame.icon.isEmpty && overlay.frame.fieldOpacity(1) == 1)

        prefs.moveSource(MurmurSource.local.id, to: 0)
        prefs.sources[0].enabled = false
        prefs.allowsTriggers = true
        #expect(try await request(base, trigger, method: "POST", token: key, body: note).fields["status"] == "already_played")
        try server.resetToken()
        let urgent = Data(#"{"id":"finish","kind":"note","occurred_at":"2026-01-01T12:01:00Z","data":{"summary":"Finished"}}"#.utf8)
        #expect(try await request(base, trigger, method: "POST", token: "first", body: urgent).code == 401)
        #expect(try await request(base, trigger, method: "POST", token: key, body: urgent).fields["status"] == "started")
        #expect(overlay.content?.headline == "Finished")
        #expect(try await request(base, feed + "?played=build%2F%2B42").code == 204)

        server.stop()
        let replay = EventPolling(defaults: defaults, localServerURL: base).trigger(id: "finish", data: urgent, play: show)
        #expect(replay == .alreadyPlayed && presentations == 2)
        let reopened = DaemonPreferences(defaults: defaults)
        #expect(reopened.sources.map(\.mode) == [.local, .regional])
        #expect(!reopened.sources[0].enabled && reopened.allowsTriggers)
        let restarted = try await start(server)
        #expect(prefs.sources.count == 2 && !prefs.sources[0].enabled)
        #expect(try await request(restarted, feed).data == note)
        let later = try await LocalEventStore(url: database).candidate(excluding: [], now: Date.now.addingTimeInterval(4 * 60 * 60))
        #expect(later == nil)
    }
}
