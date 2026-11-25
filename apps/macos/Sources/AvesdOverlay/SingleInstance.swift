import AppKit
import AvesdEnvironment
import Darwin

final class InstanceLock {
    private let descriptor: Int32

    init?(at file: URL) throws {
        let fd = open(file.path, O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            let error = errno
            if error == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(error), userInfo: [NSFilePathErrorKey: file.path])
        }
        descriptor = fd
    }

    deinit {
        // A child process may briefly inherit the descriptor until exec.
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

@MainActor
func runOverlayApplication(environment: AppEnvironment) throws {
    let channel = environment.channel
    let center = DistributedNotificationCenter.default()
    let reopen = Notification.Name("\(channel.bundleIdentifier).reopen")
    let restart = Notification.Name("\(channel.bundleIdentifier).restart")
    let observer = center.addObserver(forName: reopen, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { (NSApp?.delegate as? OverlayApp)?.showSettings() }
    }
    defer { center.removeObserver(observer) }

    let directory = environment.supportDirectory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "instance.lock")
    var lock = try InstanceLock(at: file)
    if channel.restartsOnRun && CommandLine.arguments.dropFirst().contains("--restart-local") {
        let deadline = ContinuousClock.now + .seconds(5)
        while lock == nil {
            guard ContinuousClock.now < deadline else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ETIMEDOUT),
                              userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for \(channel.appName) to quit."])
            }
            center.postNotificationName(restart, object: nil, userInfo: nil, deliverImmediately: true)
            Thread.sleep(forTimeInterval: 0.1)
            lock = try InstanceLock(at: file)
        }
    }
    guard let lock else {
        center.postNotificationName(reopen, object: nil, userInfo: nil, deliverImmediately: true)
        return
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    BrandTypography.registerBundledFonts()
    let delegate = OverlayApp(environment: environment)
    app.delegate = delegate
    if channel.restartsOnRun {
        center.addObserver(app, selector: #selector(NSApplication.terminate(_:)), name: restart,
                           object: nil, suspensionBehavior: .deliverImmediately)
    }
    withExtendedLifetime((lock, delegate)) { app.run() }
}
