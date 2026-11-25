import AvesdEnvironment
import Foundation
import Testing

@Test func packagedChannelsResolveTheirPortsAndUpdatePolicy() throws {
    let macOS = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    for (key, expectedPort) in [("release", 28373), ("local", 28375), ("test", 28378)] {
        let app = directory.appending(path: "\(key).app")
        let contents = app.appending(path: "Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let configure = Process()
        configure.executableURL = URL(filePath: "/usr/bin/env")
        configure.arguments = ["node", macOS.appending(path: "configure-bundle.ts").path, key, contents.appending(path: "Info.plist").path]
        var variables = ProcessInfo.processInfo.environment
        variables["UPDATE_FEED_URL"] = "https://updates.example.test/appcast.xml"
        variables["UPDATE_PUBLIC_KEY"] = Data(repeating: 0, count: 32).base64EncodedString()
        configure.environment = variables
        try configure.run()
        configure.waitUntilExit()
        try #require(configure.terminationStatus == 0)

        let bundle = try #require(Bundle(url: app))
        let profile = try #require(ChannelProfile.all[key])
        let environment = AppEnvironment(bundle: bundle)
        #expect(bundle.bundleIdentifier == profile.bundleIdentifier)
        #expect(environment.channel.bundleIdentifier == bundle.bundleIdentifier)
        #expect(environment.channel.localServerURL.port == expectedPort)
        #expect(environment.updatesConfigured == (key == "release"))
        #expect((bundle.object(forInfoDictionaryKey: "SUFeedURL") != nil) == environment.updatesConfigured)
        #expect((bundle.object(forInfoDictionaryKey: "SUPublicEDKey") != nil) == environment.updatesConfigured)
    }
}
