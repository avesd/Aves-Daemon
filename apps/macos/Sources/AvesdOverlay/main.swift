import AvesdEnvironment
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
    private let environment: AppEnvironment
    private let state = OverlaySession()
    private let analytics: UsageAnalytics
    private let updates: SoftwareUpdates
    private let region: EventRegion
    private let preferences: DaemonPreferences
    private let eventPolling: EventPolling
    private let localEvents: LocalEventStore
    private let navigation = SettingsNavigation()
    private lazy var localServer = LocalMurmurServer(
        port: environment.channel.localPort,
        events: localEvents,
        credential: LocalServerToken(service: environment.localTokenService).value(reset:),
        allowsTrigger: { [weak self] in self?.preferences.allowsTriggers == true },
        trigger: { [weak self] id, event in
            guard let self else { return .unavailable }
            return eventPolling.trigger(id: id, data: event) { data, expires, resolve in
                showOverlay(.event(data, source: .localTrigger), expires: expires, resolve: resolve)
            }
        },
        onReady: { [weak self] in self?.preferences.addLocalSourceIfNeeded() }
    )
    private var serverSubscription: AnyCancellable?
    private var scheduleSubscription: AnyCancellable?
    private let panel = OverlayPanel(size: OverlayLayout.panelSize)
    private lazy var host = NSHostingView(rootView: OverlayView(state: state))
    private let cache: AirlineLogoCache?
    private var statusItem: NSStatusItem?
    private var polling: Task<Void, Never>?
    private var playback: Task<Void, Never>?
    private var logoLookup: Task<Void, Never>?
    private var didWarmCache = false
    private var prefetchTask: Task<Void, Never>?
    private var settingsController: NSWindowController?

    init(environment: AppEnvironment) {
        self.environment = environment
        let defaults = environment.preferences
        region = EventRegion(defaults: defaults)
        preferences = DaemonPreferences(defaults: defaults)
        localEvents = LocalEventStore(url: environment.supportDirectory.appending(path: "local-server/events.sqlite"))
        eventPolling = EventPolling(defaults: defaults, localServerURL: environment.channel.localServerURL, localEvents: localEvents)
        analytics = UsageAnalytics(isAvailable: environment.channel.allowsUsageStatistics, defaults: defaults)
        updates = SoftwareUpdates(environment: environment)
        cache = environment.cachesDirectory.map { AirlineLogoCache(directory: $0.appending(path: "airline-logos")) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        host.sizingOptions = []
        panel.contentView = host
        panel.ignoresMouseEvents = true
        let channel = environment.channel
        let status = NSStatusBar.system.statusItem(withLength: channel.badge.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength)
        status.button?.image = MenuBarBrand.image(showsUpdate: false)
        if !channel.badge.isEmpty {
            status.button?.imagePosition = .imageLeading
            status.button?.font = .systemFont(ofSize: 10, weight: .semibold)
            status.button?.title = channel.badge
        }
        status.button?.toolTip = environment.statusLabel
        status.button?.setAccessibilityLabel(environment.statusLabel)
        let menu = NSMenu()
        let locationItem = menu.addItem(withTitle: SettingsText.menuLocation.string,
                                        action: #selector(useMyLocation), keyEquivalent: "")
        locationItem.target = self
        menu.addItem(withTitle: SettingsText.menuSettings.string, action: #selector(showSettings), keyEquivalent: ",").target = self
        updates.attach(to: menu, button: status.button)
        menu.addItem(.separator())
        menu.addItem(withTitle: SettingsText.menuQuit(channel.appName).string, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        statusItem = status
        analytics.appStarted()
        if preferences.usesRegion { region.refreshIfNeeded() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        serverSubscription = preferences.$localServerEnabled.removeDuplicates().sink { [weak self] enabled in
            guard let self else { return }
            if enabled { localServer.start() } else { localServer.stop() }
        }
        var previousSources = preferences.sources
        scheduleSubscription = preferences.$sources.removeDuplicates()
            .combineLatest(preferences.$polling.removeDuplicates(), region.$selection.map(\.cell).removeDuplicates(),
                           localServer.$state.map(\.isRunning).removeDuplicates())
            .sink { [weak self] sources, _, _, _ in
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
                    await eventPolling.run(preferences: preferences, region: region, sources: {
                        preferences.sources.filter { $0.mode != .local || localServer.state.isRunning }
                    }) { [weak self] data, expires, resolve in
                        self?.showOverlay(.event(data), expires: expires, resolve: resolve) ?? false
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
        serverSubscription?.cancel()
        scheduleSubscription?.cancel()
        localServer.stop()
        polling?.cancel()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    @objc func showSettings() {
        if settingsController == nil {
            let settings = SettingsView(environment: environment, region: region, preferences: preferences, polling: eventPolling, localServer: localServer,
                                        updates: updates, analytics: analytics, cache: cache,
                                        preview: { [weak self] in _ = self?.showOverlay(.preview) },
                                        changePrefetch: { [weak self] enabled in self?.setPrefetch(enabled) },
                                        clearCache: { [weak self] in try await self?.clearLogos() }, navigation: navigation)
            let window = NSWindow(contentViewController: NSHostingController(rootView: settings))
            window.title = SettingsText.windowSettings(environment.channel.appName).string
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

    private func showOverlay(_ input: OverlaySession.Input, expires: TimeInterval? = nil,
                             resolve: @escaping (OverlaySession.Presentation) -> Void = { _ in }) -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return false }
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard state.play(input, reduced: reduced, duration: TimeInterval(preferences.displaySeconds), expires: expires,
                         resolve: { [weak self] result in
            if result == .shown { self?.presentOverlay(input, on: screen) }
            resolve(result)
        }) else { return false }
        playback?.cancel()
        playback = Task {
            while !Task.isCancelled {
                let location = panel.mouseLocationOutsideOfEventStream
                let mouse = CGPoint(x: location.x, y: panel.frame.height - location.y)
                guard state.advance(pointer: mouse) else {
                    panel.orderOut(nil)
                    return
                }
                do { try await Task.sleep(for: .milliseconds(state.animating ? 16 : 60)) }
                catch { return }
            }
        }
        return true
    }

    private func presentOverlay(_ input: OverlaySession.Input, on screen: NSScreen) {
        logoLookup?.cancel()
        let frame = screen.visibleFrame
        panel.setFrameTopLeftPoint(NSPoint(x: frame.maxX - panel.frame.width, y: frame.maxY - 32))
        panel.orderFrontRegardless()
        state.onFirstExpansion = analytics.overlayShown(input)

        if let slug = state.content?.airlineMark, let mark = AirlineMark(slug: slug), let cache {
            logoLookup = Task {
                if let data = await cache.logo(for: mark), !Task.isCancelled {
                    state.offerLogo(data)
                }
            }
            warmLogos()
        }
    }
}

private let environment = AppEnvironment()
do {
    try runOverlayApplication(environment: environment)
} catch {
    NSLog("Could not start %@: %@", environment.channel.appName, error.localizedDescription)
    exit(EXIT_FAILURE)
}
