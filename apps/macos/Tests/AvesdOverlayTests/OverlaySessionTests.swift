import Foundation
import Testing
@testable import AvesdOverlay

@MainActor
@Test func flyoverClearsSceneryAndPreservesEarlierFrames() throws {
    let overlay = OverlaySession()
    try #require(overlay.reset(.preview, reduced: false, duration: 10, seed: 1))
    try #require(overlay.advance(elapsed: 1, pointer: .zero))
    let inFlight = overlay.frame
    let positions = inFlight.scenery.map(\.x)
    try #require(!positions.isEmpty)

    try #require(overlay.advance(elapsed: 1.5, pointer: .zero))
    #expect(overlay.frame.scenery.map(\.x) != positions)
    try #require(overlay.advance(elapsed: 5, pointer: .zero))
    #expect(overlay.frame.scenery.isEmpty)
    #expect(inFlight.scenery.map(\.x) == positions)
}
