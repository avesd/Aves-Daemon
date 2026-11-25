import Foundation

package struct ChannelProfile: Decodable, Sendable {
    package let name: String
    package let appName: String
    package let bundleIdentifier: String
    package let badge: String
    package let localPort: UInt16
    package let includesUpdater: Bool
    package let allowsUsageStatistics: Bool
    package let restartsOnRun: Bool

    package static let all: [String: Self] = {
        do { return try JSONDecoder().decode([String: Self].self, from: Data(PackageResources.channels_json)) }
        catch { preconditionFailure("Invalid bundled channel profiles: \(error)") }
    }()

    package var localServerURL: URL { URL(string: "http://127.0.0.1:\(localPort)")! }
}

package struct AppEnvironment {
    package let channel: ChannelProfile
    package let version: String
    package let preferences: UserDefaults
    package let updatesConfigured: Bool

    package init(bundle: Bundle = .main) {
        let profiles = ChannelProfile.all
        guard let local = profiles["local"] else { preconditionFailure("Missing Local channel profile") }
        let channel = profiles.values.first { $0.bundleIdentifier == bundle.bundleIdentifier } ?? local
        self.channel = channel
        if channel.bundleIdentifier == Bundle.main.bundleIdentifier {
            preferences = .standard
        } else {
            preferences = UserDefaults(suiteName: channel.bundleIdentifier)!
        }
        updatesConfigured = channel.includesUpdater && bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil
            && bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil
        version = Self.version(in: bundle)
    }

    private static func version(in bundle: Bundle) -> String {
        let release = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        if let release, !release.isEmpty {
            if let build, !build.isEmpty { return "Version \(release) (\(build))" }
            return "Version \(release)"
        }
        if let build, !build.isEmpty { return "Build \(build)" }
        return "Development build"
    }

    package var statusLabel: String { "Aves Daemon \(channel.name) · \(version)" }
    package var supportDirectory: URL { URL.applicationSupportDirectory.appending(path: channel.bundleIdentifier) }
    package var cachesDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appending(path: channel.bundleIdentifier)
    }
    package var localTokenService: String { "\(channel.bundleIdentifier).local-server" }
}
