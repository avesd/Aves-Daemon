// swift-tools-version: 6.2
import Foundation
import PackageDescription

let rustLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".build/rust").path
struct ChannelDependencies: Decodable { let includesUpdater: Bool }
let channelFile = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("Sources/AvesdEnvironment/channels.json")
let channels = try JSONDecoder().decode([String: ChannelDependencies].self, from: Data(contentsOf: channelFile))
let selectedChannel = Context.environment["AVESD_BUILD_CHANNEL"] ?? "local"
guard let channel = channels[selectedChannel] else { fatalError("Unknown macOS channel '\(selectedChannel)'") }
let updaterTargets: [Target] = channel.includesUpdater ? [
    .binaryTarget(
        name: "Sparkle",
        url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
        checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
    )
] : []

let package = Package(
    name: "AvesdOverlay",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/PostHog/posthog-ios.git", exact: "4.0.11")],
    targets: updaterTargets + [
        .plugin(name: "CompileLocalizations", capability: .buildTool()),
        .target(name: "AvesdEnvironment", resources: [.embedInCode("channels.json")], plugins: ["CompileLocalizations"]),
        .systemLibrary(name: "CAvesdCore"),
        .executableTarget(
            name: "AvesdOverlay",
            dependencies: ["AvesdEnvironment", "CAvesdCore", .product(name: "PostHog", package: "posthog-ios")]
                + (channel.includesUpdater ? ["Sparkle"] : []),
            resources: [.copy("Fonts")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
                .unsafeFlags(["-L", "\(rustLibraryDirectory)/debug", "-Xlinker", "-rpath", "-Xlinker",
                              "@loader_path/../../rust/debug", "-Xlinker", "-rpath", "-Xlinker",
                              "@loader_path/../../../rust/debug"], .when(configuration: .debug)),
                .unsafeFlags(["-L", "\(rustLibraryDirectory)/release"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AvesdOverlayTests",
            dependencies: ["AvesdEnvironment", "AvesdOverlay", .product(name: "PostHog", package: "posthog-ios")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(rustLibraryDirectory)/debug"], .when(configuration: .debug)),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(rustLibraryDirectory)/release"], .when(configuration: .release))
            ]
        )
    ]
)
