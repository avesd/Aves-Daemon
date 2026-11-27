import Combine
import Foundation
import PostHog

@MainActor
final class UsageAnalytics: ObservableObject {
    private enum Kind: String, Decodable {
        case flyover, rain, sunrise, note
        case bridgeLift = "bridge_lift", turningTide = "turning_tide", lastTrain = "last_train"
    }
    private struct EventHeader: Decodable { let kind: Kind }

    let isAvailable: Bool
    let isDisabledByDoNotTrack: Bool
    @Published private(set) var isEnabled: Bool
    private let defaults: UserDefaults
    private let makeConfiguration: () -> PostHogConfig
    private var client: PostHogSDK?
    private static let preferenceKey = "shareAnonymousUsageStatistics"

    init(isAvailable: Bool, defaults: UserDefaults,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         makeConfiguration: @escaping () -> PostHogConfig = {
             PostHogConfig(projectToken: "phc_AuP59cx4oqoooHueYQuyq8jriHN2zFnMBFM7C6rprfx7",
                           host: "https://us.i.posthog.com")
         }) {
        self.defaults = defaults
        self.makeConfiguration = makeConfiguration
        self.isAvailable = isAvailable
        isDisabledByDoNotTrack = environment["DO_NOT_TRACK"] == "1"
        isEnabled = isAvailable && !isDisabledByDoNotTrack && defaults.bool(forKey: Self.preferenceKey)
    }

    func appStarted() {
        guard isEnabled else { return }
        enableClient()
        client?.capture("app_started")
    }

    func setEnabled(_ enabled: Bool) {
        guard isAvailable, !isDisabledByDoNotTrack, enabled != isEnabled else { return }
        defaults.set(enabled, forKey: Self.preferenceKey)
        isEnabled = enabled
        if enabled { enableClient() } else { client?.optOut() }
    }

    func overlayShown(_ input: OverlaySession.Input) -> (() -> Void)? {
        guard isEnabled, let client else { return nil }
        let properties: [String: String]
        switch input {
        case .preview:
            properties = ["source": "preview", "event_kind": Kind.flyover.rawValue]
        case .event(let data, let source):
            let header = try? JSONDecoder().decode(EventHeader.self, from: data)
            properties = ["source": source.rawValue, "event_kind": header?.kind.rawValue ?? "unknown"]
        }
        client.capture("overlay_shown", properties: properties)
        return { client.capture("overlay_expanded", properties: properties) }
    }

    private func enableClient() {
        if client == nil {
            let config = makeConfiguration()
            config.captureApplicationLifecycleEvents = false
            config.captureScreenViews = false
            config.capturePushNotificationOpened = false
            config.enableSwizzling = false
            config.preloadFeatureFlags = false
            config.personProfiles = .never
            config.setDefaultPersonProperties = false
            config.disableGeoIp = true
            config.setBeforeSend(Self.filterEvent)
            client = PostHogSDK.with(config)
        }
        client?.optIn()
    }

    private nonisolated static func filterEvent(_ event: PostHogEvent) -> PostHogEvent? {
        guard ["app_started", "overlay_shown", "overlay_expanded"].contains(event.event) else { return nil }
        let allowed = ["source", "event_kind", "$app_version", "$app_build", "$session_id", "$lib", "$lib_version",
                       "$is_identified", "$process_person_profile", "$geoip_disable"]
        event.properties = event.properties.filter { allowed.contains($0.key) }
        return event
    }
}
