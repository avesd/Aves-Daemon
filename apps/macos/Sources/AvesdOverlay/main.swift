import AppKit
import CAvesdCore

@MainActor
final class OverlayApp: NSObject, NSApplicationDelegate {
    private let ringPanel = OverlayPanel(size: NSSize(width: 68, height: 68))
    private let captionPanel = OverlayPanel(size: NSSize(width: 162, height: 52))
    private let ring = RingView()
    private let caption = CaptionView()
    private var menuItem: NSStatusItem?
    private var clickCount: UInt64 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        ringPanel.contentView = ring
        captionPanel.contentView = caption
        captionPanel.ignoresMouseEvents = true
        ring.onClick = { [weak self] in
            guard let self else { return }
            clickCount = avesd_next_click_count(clickCount)
            caption.showCount(clickCount)
        }
        ring.onMove = { [weak self] origin in self?.move(to: origin) }

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.title = "Avesd"
        let menu = NSMenu()
        let resetItem = menu.addItem(withTitle: "Reset Position", action: #selector(resetPosition), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Avesd", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        status.menu = menu
        menuItem = status

        resetPosition()
        captionPanel.orderFrontRegardless()
        ringPanel.orderFrontRegardless()
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        let frame = screen.visibleFrame
        move(to: NSPoint(x: frame.maxX - 100, y: frame.maxY - 112))
    }

    private func move(to origin: NSPoint) {
        ringPanel.setFrameOrigin(origin)
        captionPanel.setFrameOrigin(NSPoint(
            x: origin.x - captionPanel.frame.width - 4,
            y: origin.y + (ringPanel.frame.height - captionPanel.frame.height) / 2
        ))
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = OverlayApp()
app.delegate = delegate
app.run()
