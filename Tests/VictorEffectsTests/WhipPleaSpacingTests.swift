import XCTest
@testable import VictorEffects

/// Rapid clicks throw word after word near the same spot; none may land on
/// top of another still flying (2026-11-27, Victor: *"the labels should never
/// overlap each other as they show up"*).
final class WhipPleaSpacingTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    func testAClearSpotIsKept() {
        let fp = WhipPleas.footprint("te rog 🇷🇴", explained: true)
        let p = CGPoint(x: 800, y: 500)
        XCTAssertEqual(WhipPleas.freeSpot(near: p, footprint: fp, avoiding: [], in: bounds), p)
    }

    func testTenClicksOnOneSpotNeverOverlap() {
        var pleas: [WhipPleas.Plea] = []
        let now = 10_000.0
        for (k, text) in WhipPleas.phrases.prefix(10).enumerated() {
            let t = now + Double(k) * 170           // just past the 160 ms debounce
            let taken = pleas.map { WhipPleas.track(of: $0, now: t, in: bounds) }
            let fp = WhipPleas.footprint(text, explained: true)
            let at = WhipPleas.freeSpot(near: CGPoint(x: 900, y: 600), footprint: fp, avoiding: taken, in: bounds)
            let mine = WhipPleas.track(center: at, footprint: fp, from: 0, in: bounds)
            for other in taken { XCTAssertFalse(mine.intersects(other), "\(text) lands on another word") }
            pleas.append(WhipPleas.Plea(text: text, at: at, bornMs: t, explainedMs: t))
        }
    }

    /// At the bezel the search still finds room inside the screen.
    func testInACornerTheWordsStayApartAndOnScreen() {
        let fp = WhipPleas.footprint("alsjeblieft 🇳🇱", explained: true)
        let corner = CGPoint(x: 5, y: 5)
        let first = WhipPleas.track(center: corner, footprint: fp, from: 0, in: bounds)
        let at = WhipPleas.freeSpot(near: corner, footprint: fp, avoiding: [first], in: bounds)
        let second = WhipPleas.track(center: at, footprint: fp, from: 0, in: bounds)
        XCTAssertFalse(second.intersects(first))
        XCTAssertTrue(bounds.contains(second))
    }
}
