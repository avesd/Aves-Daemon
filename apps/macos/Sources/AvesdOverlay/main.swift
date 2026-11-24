import Combine
import SwiftUI

final class OverlayPanel: NSPanel {
    init(size: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayApp: NSObject, NSApplicationDelegate {
    private let state = OverlaySession()
    private let updates = SoftwareUpdates()
    private let region = EventRegion()
    private let preferences = DaemonPreferences()
    private let eventPolling = EventPolling()
    private let navigation = SettingsNavigation()
    private var scheduleSubscription: AnyCancellable?
    private let panel = OverlayPanel(size: OverlayLayout.panelSize)
    private lazy var host = NSHostingView(rootView: OverlayView(state: state))
    private let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first.map {
        AirlineLogoCache(directory: $0.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ai.avesd.daemon")
            .appendingPathComponent("airline-logos"))
    }
    private var statusItem: NSStatusItem?
    private var polling: Task<Void, Never>?
    private var playback: Task<Void, Never>?
    private var logoLookup: Task<Void, Never>?
    private var didWarmCache = false
    private var prefetchTask: Task<Void, Never>?
    private var settingsController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = MenuBarBrand.image(showsUpdate: false)
        status.button?.toolTip = "Aves Daemon"
        status.button?.setAccessibilityLabel("Aves Daemon")
        let menu = NSMenu()
        menu.addItem(withTitle: "Preview Flyover", action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preview Rain", action: #selector(previewRain), keyEquivalent: "").target = self
        for event in PreviewKind.worldEvents {
            let item = menu.addItem(withTitle: "Preview " + event.rawValue, action: #selector(previewWorld(_:)), keyEquivalent: "")
            item.representedObject = event.rawValue
            item.target = self
        }
        let locationItem = menu.addItem(withTitle: "Use My Location for Nearby Flights",
                                        action: #selector(useMyLocation), keyEquivalent: "")
        locationItem.target = self
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        updates.attach(to: menu, button: status.button)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Aves Daemon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        statusItem = status
        if preferences.usesRegion { region.refreshIfNeeded() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        var previousSources = preferences.sources
        scheduleSubscription = preferences.$sources.removeDuplicates()
            .combineLatest(preferences.$polling.removeDuplicates(), region.$selection.map(\.cell).removeDuplicates())
            .sink { [weak self] sources, _, _ in
                guard let self else { return }
                locationItem.isHidden = !sources.contains { $0.enabled && $0.mode == .regional }
                let changed = previousSources.filter { old in
                    !sources.contains { $0.id == old.id && $0.address == old.address && $0.mode == old.mode }
                }
                eventPolling.clearStatus(for: Set(changed.map(\.id)))
                previousSources = sources
                polling?.cancel()
                polling = Task { [weak self] in
                    guard let self else { return }
                    await eventPolling.run(preferences: preferences, region: region) { [weak self] in
                        self?.showOverlay(.event($0)) ?? false
                    }
                }
            }
    }

    @objc private func didWake() {
        if preferences.usesRegion { region.refreshIfNeeded(afterWake: true) }
    }

    @objc private func useMyLocation() {
        navigation.page = .sources
        showSettings()
        region.useMyLocation()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        polling?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc private func showSettings() {
        if settingsController == nil {
            let settings = SettingsView(region: region, preferences: preferences, polling: eventPolling, updates: updates, cache: cache,
                                        preview: { [weak self] event in self?.present(event) },
                                        changePrefetch: { [weak self] enabled in self?.setPrefetch(enabled) },
                                        clearCache: { [weak self] in try await self?.clearLogos() }, navigation: navigation)
            let window = NSWindow(contentViewController: NSHostingController(rootView: settings))
            window.title = "Aves Daemon Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 530))
            window.isReleasedWhenClosed = false
            window.standardWindowButton(.closeButton)?.keyEquivalent = "w"
            window.standardWindowButton(.closeButton)?.keyEquivalentModifierMask = .command
            window.center()
            settingsController = NSWindowController(window: window)
        } else if let window = settingsController?.window, !window.isVisible,
                  let host = window.contentViewController as? NSHostingController<SettingsView> {
            host.rootView.brandPresentation += 1
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsController?.showWindow(nil)
        settingsController?.window?.makeKeyAndOrderFront(nil)
    }

    private func setPrefetch(_ enabled: Bool) {
        prefetchTask?.cancel()
        didWarmCache = false
        if enabled { warmLogos() }
    }

    private func warmLogos() {
        guard let cache, !didWarmCache, preferences.preloadLogos else { return }
        didWarmCache = true
        prefetchTask = Task(priority: .utility) {
            for mark in AirlineMark.common {
                guard !Task.isCancelled else { return }
                _ = await cache.logo(for: mark)
            }
        }
    }

    private func clearLogos() async throws {
        prefetchTask?.cancel()
        logoLookup?.cancel()
        didWarmCache = false
        try await cache?.clear()
    }

    @objc private func preview() { present(.flyover) }
    @objc private func previewRain() { present(.rain) }

    @objc private func previewWorld(_ item: NSMenuItem) {
        guard let name = item.representedObject as? String, let event = PreviewKind(rawValue: name) else { return }
        present(event)
    }

    private func present(_ event: PreviewKind) {
        _ = showOverlay(.preview(event))
    }

    private func showOverlay(_ input: OverlaySession.Input) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return false }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard state.reset(input, reduced: reduced, duration: TimeInterval(preferences.displaySeconds)) else { return false }
        playback?.cancel()
        logoLookup?.cancel()
        let frame = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width, y: frame.maxY - 32))
        panel.orderFrontRegardless()

        if let slug = state.content?.airlineMark, let mark = AirlineMark(slug: slug), let cache {
            logoLookup = Task {
                if let data = await cache.logo(for: mark), !Task.isCancelled {
                    state.offerLogo(data)
                }
            }
            warmLogos()
        }

        playback = Task {
            let clock = ContinuousClock()
            let start = clock.now
            while !Task.isCancelled {
                let now = clock.now
                let elapsed = start.duration(to: now).timeInterval
                let location = panel.mouseLocationOutsideOfEventStream
                let mouse = CGPoint(x: location.x, y: panel.frame.height - location.y)
                guard state.advance(elapsed: elapsed, pointer: mouse) else {
                    panel.orderOut(nil)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(state.animating ? 16 : 60)) }
                catch { return }
            }
        }
        return true
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
BrandTypography.registerBundledFonts()
let delegate = OverlayApp()
app.delegate = delegate
app.run()
