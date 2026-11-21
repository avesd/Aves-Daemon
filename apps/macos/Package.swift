// swift-tools-version: 6.0
import Foundation
import PackageDescription

let rustLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent(".build/rust/debug").path

let package = Package(
    name: "AvesdOverlay",
    platforms: [.macOS(.v13)],
    targets: [
        .systemLibrary(name: "CAvesdCore"),
        .executableTarget(
            name: "AvesdOverlay",
            dependencies: ["CAvesdCore"],
            linkerSettings: [
                .unsafeFlags(["-L", rustLibraryDirectory, "-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../rust/debug"])
            ]
        )
    ]
)
