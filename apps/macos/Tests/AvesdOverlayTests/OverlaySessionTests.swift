import CAvesdCore
import Foundation
import Testing
@testable import AvesdOverlay

@MainActor
@Test func flyoverClearsSceneryAndPreservesEarlierFrames() throws {
    let overlay = OverlaySession()
    let start = ContinuousClock.now
    try #require(overlay.play(.preview, reduced: false, duration: 10, seed: 1, at: start))
    try #require(overlay.advance(to: start + .milliseconds(1), pointer: .zero))
    let plane = try #require(overlay.frame.scenery.first { $0.op == AVESD_OP_SYMBOL })
    #expect(OverlayLayout.markCenter.x + plane.x + plane.a / 2 <= 0)

    try #require(overlay.advance(to: start + .seconds(1), pointer: .zero))
    let inFlight = overlay.frame
    let positions = inFlight.scenery.map(\.x)
    try #require(!positions.isEmpty)

    try #require(overlay.advance(to: start + .seconds(1.5), pointer: .zero))
    #expect(overlay.frame.scenery.map(\.x) != positions)

    var lastTrailStart: Double?
    for ms in stride(from: 1516, through: 3500, by: 16) {
        try #require(overlay.advance(to: start + .milliseconds(ms), pointer: .zero))
        if overlay.frame.scenery.isEmpty { break }
        lastTrailStart = overlay.frame.scenery.filter { $0.op == AVESD_OP_GRADIENT }.map(\.x).min()
    }
    let trail = try #require(lastTrailStart)
    #expect(OverlayLayout.markCenter.x + trail >= OverlayLayout.panelSize.width)
    #expect(overlay.frame.scenery.isEmpty)
    #expect(inFlight.scenery.map(\.x) == positions)
}

@MainActor
@Test func earlyHoverRevealsTheTideSummaryAndKeepsItReadableAfterLeaving() throws {
    let tide = Data(#"{"id":"tide","kind":"turning_tide","occurred_at":"2026-11-22T15:08:00Z","data":{"place":"Saint-Malo","time_zone":"Europe/Paris","turn":"high_to_falling"}}"#.utf8)
    let overlay = OverlaySession()
    let start = ContinuousClock.now
    try #require(overlay.play(.event(tide), reduced: false, duration: 5, at: start))
    #expect(overlay.frame.fieldOpacity(0) == 0)
    let inside = OverlayLayout.markCenter
    try #require(overlay.advance(to: start + .milliseconds(100), pointer: inside))
    #expect(0 < overlay.frame.fieldOpacity(0) && overlay.frame.fieldOpacity(0) < 1)
    try #require(overlay.advance(to: start + .milliseconds(200), pointer: inside))
    #expect(overlay.frame.panel.expansion == 0 && overlay.frame.fieldOpacity(1) == 0)
    try #require(overlay.advance(to: start + .milliseconds(400), pointer: inside))
    #expect(0 < overlay.frame.fieldOpacity(1) && overlay.frame.fieldOpacity(1) < 1)
    #expect(overlay.frame.scenery.isEmpty)
    try #require(overlay.advance(to: start + .milliseconds(430), pointer: .zero))
    try #require(overlay.advance(to: start + .milliseconds(750), pointer: .zero))
    #expect(overlay.frame.panel.expansion == 0 && overlay.frame.fieldOpacity(1) == 1)
    #expect(overlay.frame.scenery.isEmpty)
    try #require(overlay.advance(to: start + .milliseconds(800), pointer: inside))
    try #require(overlay.advance(to: start + .milliseconds(1500), pointer: inside))
    #expect(overlay.frame.panel.open_fraction == 1 && overlay.frame.scenery.isEmpty)
}

@MainActor
@Test func hoverPicksUpTheDisplayedOpacityDuringDismissal() throws {
    let overlay = OverlaySession()
    let start = ContinuousClock.now
    try #require(overlay.play(.preview, reduced: true, duration: 5, at: start))
    try #require(overlay.advance(to: start + .milliseconds(4900), pointer: .zero))
    let dim = overlay.frame.panel.opacity
    #expect(abs(dim - 0.2) < 0.001)
    let inside = OverlayLayout.markCenter
    try #require(overlay.advance(to: start + .milliseconds(4916), pointer: inside))
    #expect(overlay.frame.panel.opacity == dim)
    try #require(overlay.advance(to: start + .milliseconds(5000), pointer: inside))
    #expect(overlay.frame.panel.opacity > dim && overlay.frame.panel.opacity < 1)
    try #require(overlay.advance(to: start + .milliseconds(5150), pointer: .zero))
    #expect(overlay.frame.panel.opacity == 1)
    #expect(!overlay.advance(to: start + .seconds(7), pointer: .zero))
}

@MainActor
@Test func replacementsKeepOneFadeAndPresentOnlyTheNewestValidEvent() throws {
    let overlay = OverlaySession()
    let start = ContinuousClock.now
    var first: OverlaySession.Presentation?
    var displaced: [OverlaySession.Presentation] = []
    var last: OverlaySession.Presentation?
    try #require(overlay.play(.preview, reduced: false, duration: 5, at: start) { first = $0 })
    let swap = start + .seconds(3)
    try #require(overlay.advance(to: swap, pointer: .zero))
    try #require(overlay.play(.preview, reduced: false, duration: 5, at: swap) { displaced.append($0) })
    try #require(overlay.advance(to: swap + .milliseconds(80), pointer: .zero))
    let outgoing = overlay.frame.panel.opacity
    #expect(0 < outgoing && outgoing < 1)

    let note = Data(#"{"id":"note","kind":"note","occurred_at":"2026-01-01T12:00:00Z","data":{"summary":"Hello"}}"#.utf8)
    try #require(overlay.play(.event(note), reduced: false, duration: 5, at: swap + .milliseconds(81)) { last = $0 })
    #expect(!overlay.play(.event(Data()), reduced: false, duration: 5, at: swap + .milliseconds(85)))
    try #require(overlay.advance(to: swap + .milliseconds(110), pointer: OverlayLayout.markCenter))
    #expect(overlay.frame.panel.opacity < outgoing && overlay.content?.airlineCode != nil)
    #expect(first == .shown && displaced == [.superseded] && last == nil)
    try #require(overlay.advance(to: swap + .milliseconds(165), pointer: .zero))
    #expect(displaced == [.superseded] && last == .shown)
    #expect(overlay.content?.headline == "Hello" && overlay.frame.fieldOpacity(1) == 0)

    try #require(overlay.advance(to: swap + .milliseconds(500), pointer: .zero))
    try #require(overlay.play(.preview, reduced: true, duration: 5, at: swap + .milliseconds(505)))
    #expect(overlay.content?.airlineCode != nil && overlay.frame.fieldOpacity(1) == 1)
    #expect(overlay.frame.scenery.isEmpty)
}
