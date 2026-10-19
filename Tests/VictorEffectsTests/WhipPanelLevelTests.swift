import AppKit
import XCTest
@testable import VictorEffects

/// The whip has to be drawn above the ⌥⇧ zoom (addons' `ShareZoom`, a
/// `.screenSaver` window). `isFloatingPanel = true` once reset the level to
/// `.floating` behind the explicit one and the rope vanished under the zoom.
final class WhipPanelLevelTests: XCTestCase {
    func testWhipPanelSitsAtMaximumWindowLevel() {
        let panel = WhipPanel(screenFrame: NSRect(x: 0, y: 0, width: 800, height: 600))
        XCTAssertEqual(panel.level.rawValue, Int(CGWindowLevelForKey(.maximumWindow)))
        XCTAssertGreaterThan(panel.level, .screenSaver)
    }
}
