import AppKit

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

final class RingView: NSView {
    var onClick: (() -> Void)?
    var onMove: ((NSPoint) -> Void)?
    private var press: (screen: NSPoint, origin: NSPoint)?
    private var dragging = false

    private var shape: NSBezierPath {
        let outer = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
        outer.appendOval(in: bounds.insetBy(dx: 17, dy: 17))
        outer.windingRule = .evenOdd
        return outer
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        let shape = shape
        let teal = NSColor(srgbRed: 0.10, green: 0.81, blue: 0.69, alpha: 1)
        let blue = NSColor(srgbRed: 0.18, green: 0.38, blue: 0.84, alpha: 1)
        NSGradient(starting: press == nil ? teal : .white, ending: blue)?.draw(in: shape, angle: -55)
        NSColor.black.withAlphaComponent(0.55).setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        press = (window.convertPoint(toScreen: event.locationInWindow), window.frame.origin)
        dragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let press else { return }
        let position = window.convertPoint(toScreen: event.locationInWindow)
        let dx = position.x - press.screen.x
        let dy = position.y - press.screen.y
        guard dragging || hypot(dx, dy) >= 3 else { return }
        dragging = true
        onMove?(NSPoint(x: press.origin.x + dx, y: press.origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if press != nil && !dragging && shape.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
        press = nil
        dragging = false
        needsDisplay = true
    }
}

final class CaptionView: NSView {
    private let title = NSTextField(labelWithString: "Avesd")
    private let detail = NSTextField(labelWithString: "Click or drag the ring")

    init() {
        super.init(frame: .zero)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.textColor = .white
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = NSColor(white: 0.88, alpha: 1)
        addSubview(title)
        addSubview(detail)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        title.frame = NSRect(x: 13, y: 25, width: bounds.width - 26, height: 19)
        detail.frame = NSRect(x: 13, y: 8, width: bounds.width - 26, height: 16)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(srgbRed: 0.06, green: 0.10, blue: 0.15, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 13, yRadius: 13).fill()
    }

    func showCount(_ count: UInt64) {
        detail.stringValue = count == 1 ? "1 ring click" : "\(count) ring clicks"
    }
}
