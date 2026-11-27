import CAvesdCore
import SwiftUI

enum OverlayLayout {
    static let panelSize = CGSize(width: 368, height: 238)
    static let origin = CGPoint(x: 43, y: 10)
    static let width: CGFloat = 285
    static let headerHeight: CGFloat = 42
    static let inset: CGFloat = 12
    static let markSize: CGFloat = 20
    static var markCenter: CGPoint { CGPoint(x: origin.x + inset + markSize / 2, y: origin.y + headerHeight / 2) }
}

struct OverlayFrame {
    var panel = AvesdPanel()
    var icon: [AvesdCommand] = []
    var scenery: [AvesdCommand] = []

    func fieldOpacity(_ index: Int) -> Double {
        switch index {
        case 0: panel.fields.0
        case 1: panel.fields.1
        case 2: panel.fields.2
        default: panel.fields.3
        }
    }
}

private final class PlaybackHandle {
    private let pointer: OpaquePointer
    private(set) var frame = OverlayFrame()
    let content: OverlayContent

    init?(_ input: OverlaySession.Input, reduced: Bool, duration: TimeInterval, seed: UInt64) {
        let options = AvesdOverlayOptions(seed: seed, hold_ms: duration * 1000, width: OverlayLayout.panelSize.width,
                                          anchor_x: OverlayLayout.markCenter.x, reduced: reduced)
        let pointer: OpaquePointer?
        switch input {
        case .preview: pointer = avesd_overlay_preview(UInt32(AVESD_PREVIEW_FLYOVER), options)
        case .event(let data, _):
            pointer = data.withUnsafeBytes {
                avesd_overlay_create($0.bindMemory(to: UInt8.self).baseAddress, $0.count, options)
            }
        }
        guard let pointer else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bytes = Data(String(cString: avesd_overlay_content(pointer)).utf8)
        guard let presentation = try? decoder.decode(OverlayPresentation.self, from: bytes) else {
            avesd_overlay_destroy(pointer)
            return nil
        }
        self.pointer = pointer
        self.content = presentation.localized()
        copyFrame(changes: AvesdFrameChanges(panel: true, icon: true, scenery: true))
    }

    deinit { avesd_overlay_destroy(pointer) }

    func beginReplacement(elapsed: TimeInterval) {
        avesd_overlay_begin_replacement(pointer, elapsed * 1000)
    }

    func advance(elapsed: TimeInterval, inside: Bool) -> OverlayFrame? {
        let changes = avesd_overlay_advance_changes(pointer, elapsed * 1000, inside)
        guard changes.panel || changes.icon || changes.scenery else { return nil }
        copyFrame(changes: changes)
        return frame
    }

    private func copyFrame(changes: AvesdFrameChanges) {
        let source = avesd_overlay_frame(pointer)
        frame.panel = source.panel
        if changes.icon {
            frame.icon = Array(UnsafeBufferPointer(start: source.icon, count: source.icon_count))
        }
        if changes.scenery {
            frame.scenery = Array(UnsafeBufferPointer(start: source.scenery, count: source.scenery_count))
        }
    }
}

@MainActor
final class OverlaySession: ObservableObject {
    enum Input {
        enum Source: String { case poll, localTrigger = "local_trigger" }
        case preview
        case event(Data, source: Source = .poll)
    }
    enum Presentation { case shown, superseded, expired }

    private let now: () -> Date
    private var handle: PlaybackHandle?
    private var pending: (handle: PlaybackHandle, expires: TimeInterval?, resolve: (Presentation) -> Void)?
    private var started = ContinuousClock.now
    var onFirstExpansion: (() -> Void)?
    @Published private(set) var frame = OverlayFrame()
    @Published private(set) var logo: NSImage?
    var content: OverlayContent? { handle?.content }
    var cardHeight = OverlayLayout.headerHeight
    var animating: Bool { frame.panel.animating }

    init(now: @escaping () -> Date = Date.init) { self.now = now }

    /// Each accepted request resolves once when it appears, expires, or a newer request supersedes it.
    @discardableResult
    func play(_ input: Input, reduced: Bool, duration: TimeInterval, seed: UInt64 = .random(in: .min ... .max),
              at time: ContinuousClock.Instant = .now, expires: TimeInterval? = nil,
              resolve: @escaping (Presentation) -> Void = { _ in }) -> Bool {
        guard let next = PlaybackHandle(input, reduced: reduced, duration: duration, seed: seed) else { return false }
        let displaced = pending
        pending = (next, expires, resolve)
        displaced?.resolve(.superseded)
        if let handle, frame.panel.alive, frame.panel.progress > 0, !reduced {
            handle.beginReplacement(elapsed: started.duration(to: time).timeInterval)
        } else {
            startPending(at: time)
        }
        return true
    }

    @discardableResult
    private func startPending(at time: ContinuousClock.Instant) -> Bool {
        guard let pending else { return false }
        self.pending = nil
        if let expires = pending.expires, expires <= now().timeIntervalSince1970 {
            pending.resolve(.expired)
            return false
        }
        handle = pending.handle
        started = time
        onFirstExpansion = nil
        logo = nil
        frame = pending.handle.frame
        pending.resolve(.shown)
        return true
    }

    func offerLogo(_ data: Data) {
        guard content?.airlineCode != nil, frame.panel.reveal_edge < OverlayLayout.origin.x + OverlayLayout.inset else { return }
        logo = NSImage(data: data)
    }

    func advance(to time: ContinuousClock.Instant = .now, pointer: CGPoint) -> Bool {
        guard let handle else { return false }
        let header = OverlayLayout.headerHeight
        let height = header + (cardHeight - header) * frame.panel.open_fraction
        let bounds = CGRect(origin: OverlayLayout.origin, size: CGSize(width: OverlayLayout.width, height: height))
        if let next = handle.advance(elapsed: started.duration(to: time).timeInterval, inside: bounds.contains(pointer)) {
            if !next.panel.alive, startPending(at: time) { return true }
            frame = next
            if pending == nil, next.panel.open_fraction > 0, let onFirstExpansion {
                self.onFirstExpansion = nil
                onFirstExpansion()
            }
        }
        return frame.panel.alive
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
