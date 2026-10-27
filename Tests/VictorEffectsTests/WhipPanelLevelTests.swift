import AppKit
import XCTest
@testable import VictorEffects

/// The whip has to be drawn above the ⌥ zoom (addons' `ShareZoom`, at
/// `maximumWindow + 3` since 2026-10-27, `.screenSaver` before). `isFloatingPanel = true` once reset the level to
/// `.floating` behind the explicit one and the rope vanished under the zoom.
final class WhipPanelLevelTests: XCTestCase {
    func testWhipPanelSitsAtTheEffectsLevel() {
        let panel = WhipPanel(screenFrame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(panel.level, EffectsLevel.overlay)
        XCTAssertGreaterThan(panel.level.rawValue, Int(CGWindowLevelForKey(.maximumWindow)) + 3)
    }
}
