import CAvesdCore
import SwiftUI

enum PreviewKind: String, CaseIterable {
    case flyover = "Flyover", rain = "Rain", sunrise = "Sunrise", bridge = "Bridge Lift"
    case tide = "Turning Tide", lastTrain = "Last Train"

    static let worldEvents: [Self] = [.sunrise, .bridge, .tide, .lastTrain]

    var code: Int {
        switch self {
        case .flyover: AVESD_PREVIEW_FLYOVER
        case .rain: AVESD_PREVIEW_RAIN
        case .sunrise: AVESD_PREVIEW_SUNRISE
        case .bridge: AVESD_PREVIEW_BRIDGE_LIFT
        case .tide: AVESD_PREVIEW_TURNING_TIDE
        case .lastTrain: AVESD_PREVIEW_LAST_TRAIN
        }
    }
}

enum OverlayLayout {
    static let panelSize = CGSize(width: 368, height: 238)
    static let origin = CGPoint(x: 43, y: 10)
    static let width: CGFloat = 285
    static let headerHeight: CGFloat = 42
    static let inset: CGFloat = 12
    static let markSize: CGFloat = 20
    static var markCenter: CGPoint { CGPoint(x: origin.x + inset + markSize / 2, y: origin.y + headerHeight / 2) }
}

struct OverlayContent: Decodable {
    let headline, secondary, trailing, title, caption, accessibility: String
    let icon: String
    let routeDestination, airlineCode, airlineMark: String?
    let rows: [[String]]
}

struct OverlayFrame {
    var panel = AvesdPanel()
    var icon: [AvesdCommand] = []
    var scenery: [AvesdCommand] = []

    mutating func update(_ source: AvesdOverlayFrame, changes: AvesdFrameChanges) {
        panel = source.panel
        if changes.icon {
            icon = Array(UnsafeBufferPointer(start: source.icon, count: source.icon_count))
        }
        if changes.scenery {
            scenery = Array(UnsafeBufferPointer(start: source.scenery, count: source.scenery_count))
        }
    }
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
    let value: OpaquePointer
    let content: OverlayContent

    init?(_ pointer: OpaquePointer?) {
        guard let pointer else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let bytes = Data(String(cString: avesd_overlay_content(pointer)).utf8)
        guard let content = try? decoder.decode(OverlayContent.self, from: bytes) else {
            avesd_overlay_destroy(pointer)
            return nil
        }
        self.value = pointer
        self.content = content
    }

    deinit { avesd_overlay_destroy(value) }
}

@MainActor
final class OverlaySession: ObservableObject {
    enum Input { case preview(PreviewKind), event(Data) }
    private var handle: PlaybackHandle?
    @Published private(set) var frame = OverlayFrame()
    @Published private(set) var logo: NSImage?
    var content: OverlayContent? { handle?.content }
    var cardHeight = OverlayLayout.headerHeight
    var animating: Bool { frame.panel.animating }

    @discardableResult
    func reset(_ input: Input, reduced: Bool, duration: TimeInterval, seed: UInt64 = .random(in: .min ... .max)) -> Bool {
        let options = AvesdOverlayOptions(seed: seed, hold_ms: duration * 1000, width: OverlayLayout.panelSize.width,
                                          anchor_x: OverlayLayout.markCenter.x, reduced: reduced)
        let pointer: OpaquePointer?
        switch input {
        case .preview(let kind): pointer = avesd_overlay_preview(UInt32(kind.code), options)
        case .event(let data):
            pointer = data.withUnsafeBytes {
                avesd_overlay_create($0.bindMemory(to: UInt8.self).baseAddress, $0.count, options)
            }
        }
        guard let next = PlaybackHandle(pointer) else { return false }
        handle = next
        logo = nil
        frame.update(avesd_overlay_frame(next.value), changes: AvesdFrameChanges(panel: true, icon: true, scenery: true))
        return true
    }

    func offerLogo(_ data: Data) {
        guard content?.airlineCode != nil, frame.panel.reveal_edge < OverlayLayout.origin.x + OverlayLayout.inset else { return }
        logo = NSImage(data: data)
    }

    func advance(elapsed: TimeInterval, pointer: CGPoint) -> Bool {
        guard let handle else { return false }
        let height = frame.panel.expansion > 0 ? cardHeight : OverlayLayout.headerHeight
        let bounds = CGRect(origin: OverlayLayout.origin, size: CGSize(width: OverlayLayout.width, height: height))
        let changes = avesd_overlay_advance_changes(handle.value, elapsed * 1000, bounds.contains(pointer))
        if changes.panel || changes.icon || changes.scenery {
            frame.update(avesd_overlay_frame(handle.value), changes: changes)
        }
        return frame.panel.alive
    }
}
