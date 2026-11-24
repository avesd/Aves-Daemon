// swift-tools-version: 6.0
import Foundation
import PackageDescription

let rustLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".build/rust").path

let package = Package(
    name: "AvesdOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .binaryTarget(
            name: "Sparkle",
            url: "https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-for-Swift-Package-Manager.zip",
            checksum: "4c2e48a3e50ebcc2c88a58a4c7264a1a99c3c31857ce754357afb9cdb323022a"
        ),
        .systemLibrary(name: "CAvesdCore"),
        .executableTarget(
            name: "AvesdOverlay",
            dependencies: ["CAvesdCore", "Sparkle"],
            resources: [.copy("Fonts")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path/../Frameworks"]),
                .unsafeFlags(["-L", "\(rustLibraryDirectory)/debug", "-Xlinker", "-rpath", "-Xlinker",
                              "@loader_path/../../rust/debug"], .when(configuration: .debug)),
                .unsafeFlags(["-L", "\(rustLibraryDirectory)/release"], .when(configuration: .release))
            ]
        ),
        .testTarget(
            name: "AvesdOverlayTests",
            dependencies: ["AvesdOverlay"],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(rustLibraryDirectory)/debug"], .when(configuration: .debug)),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "\(rustLibraryDirectory)/release"], .when(configuration: .release))
            ]
        )
    ]
)
