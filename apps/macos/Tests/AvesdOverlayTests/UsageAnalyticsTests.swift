import AvesdEnvironment
import Foundation
import PostHog
import Testing
@testable import AvesdOverlay

@MainActor
@Test func statisticsStayOffWithoutReleaseConsent() async throws {
    let release = try #require(ChannelProfile.all["release"])
    await withDefaults { defaults in
        func unexpectedConfiguration() -> PostHogConfig {
            Issue.record("The SDK started without Release consent")
            return PostHogConfig(projectToken: "")
        }
        let fresh = UsageAnalytics(isAvailable: release.allowsUsageStatistics, defaults: defaults, makeConfiguration: unexpectedConfiguration)
        fresh.appStarted()
        #expect(!fresh.isEnabled && fresh.overlayShown(.preview) == nil)

        defaults.set(true, forKey: "shareAnonymousUsageStatistics")
        for (key, channel) in ChannelProfile.all where key != "release" {
            let analytics = UsageAnalytics(isAvailable: channel.allowsUsageStatistics, defaults: defaults, makeConfiguration: unexpectedConfiguration)
            analytics.setEnabled(true)
            analytics.appStarted()
            #expect(!analytics.isEnabled && analytics.overlayShown(.preview) == nil)
        }
    }
}

@MainActor
@Test func postHogReceivesOnlyConsentedPlaybackStatistics() async throws {
    let release = try #require(ChannelProfile.all["release"])
    try await withDefaults { defaults in
        let token = "avesd-test-\(UUID().uuidString)"
        var events: [[String: Any]] = []
        let receiver = try LoopbackHTTPListener(port: 0) { request in
            let captureV1 = request.url.path == "/i/v1/analytics/events"
            if request.method == "POST" && (captureV1 || request.url.path == "/batch") {
                let body = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any]
                let batch = body?["batch"] as? [[String: Any]] ?? []
                for event in batch {
                    let flags = event[captureV1 ? "options" : "properties"] as? [String: Any]
                    #expect(flags?[captureV1 ? "process_person_profile" : "$process_person_profile"] as? Bool == false)
                }
                events += batch
                if captureV1 {
                    #expect(request.authorization == "Bearer \(token)")
                    return LocalHTTPResponse(status: 200, body: Data(#"{"results":{}}"#.utf8))
                }
                #expect(body?["api_key"] as? String == token)
            }
            return LocalHTTPResponse.json(200, [:])
        }
        defer { receiver.stop() }
        var port: UInt16?
        var failure: Error?
        receiver.start(ready: { port = $0 }, failed: { failure = $0 })
        let readyDeadline = ContinuousClock.now + .seconds(5)
        while port == nil && failure == nil && ContinuousClock.now < readyDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        if let failure { throw failure }
        let host = "http://127.0.0.1:\(try #require(port))"
        let sdkStorage = URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "com.posthog.unknown")
            .appending(path: token)
        defer { try? FileManager.default.removeItem(at: sdkStorage) }
        defaults.set(true, forKey: "shareAnonymousUsageStatistics")
        let analytics = UsageAnalytics(isAvailable: release.allowsUsageStatistics, defaults: defaults) {
            let config = PostHogConfig(projectToken: token, host: host)
            config.compression = .none
            config.flushIntervalSeconds = 0.1
            return config
        }
        analytics.appStarted()

        let note = Data(#"{"id":"private-id","kind":"note","occurred_at":"2026-01-01T12:00:00Z","data":{"summary":"private text"}}"#.utf8)
        let overlay = OverlaySession()
        let input = OverlaySession.Input.event(note, source: .localTrigger)
        try #require(overlay.reset(input, reduced: true, duration: 5))
        overlay.onFirstExpansion = analytics.overlayShown(input)
        let inside = CGPoint(x: OverlayLayout.origin.x + 1, y: OverlayLayout.origin.y + 1)
        for (time, point) in [(0.3, inside), (0.6, .zero), (0.9, inside)] {
            try #require(overlay.advance(elapsed: time, pointer: point))
        }
        let expandPreview = analytics.overlayShown(.preview)
        analytics.setEnabled(false)
        expandPreview?()
        #expect(analytics.overlayShown(.preview) == nil)
        #expect(!UsageAnalytics(isAvailable: release.allowsUsageStatistics, defaults: defaults).isEnabled)
        analytics.setEnabled(true)
        _ = analytics.overlayShown(.event(note, source: .poll))

        let sentDeadline = ContinuousClock.now + .seconds(5)
        while events.count < 5 && ContinuousClock.now < sentDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let names = events.compactMap { $0["event"] as? String }
        #expect(names == ["app_started", "overlay_shown", "overlay_expanded", "overlay_shown", "overlay_shown"])
        let properties = try events.map { try #require($0["properties"] as? [String: Any]) }
        #expect(properties.compactMap { $0["source"] as? String } == ["local_trigger", "local_trigger", "preview", "poll"])
        #expect(properties.compactMap { $0["event_kind"] as? String } == ["note", "note", "flyover", "note"])
        #expect(properties.allSatisfy { $0["$geoip_disable"] as? Bool == true })
        let ids = events.compactMap { $0["distinct_id"] as? String }
        #expect(ids.count == events.count && Set(ids).count == 1 && ids.allSatisfy { UUID(uuidString: $0) != nil })
        let wire = String(decoding: try JSONSerialization.data(withJSONObject: events), as: UTF8.self)
        #expect(!wire.contains("private-id") && !wire.contains("private text"))
        analytics.setEnabled(false)
    }
}
