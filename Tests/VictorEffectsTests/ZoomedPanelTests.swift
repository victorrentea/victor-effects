import AppKit
import XCTest
@testable import VictorEffects

/// The three clickable panels — the thumbnail board, the 🔥 whip, the peek
/// mascot's click target — keep their size and place on the glass under macOS
/// ⌥-scroll zoom, and a click still lands on what is drawn under it.
///
/// "On the glass" is checked the way `CaptionPinTests` does it: take the
/// framebuffer frame, magnify the slice back up to the display the way the zoom
/// does, and compare with the unzoomed frame.
final class ZoomedPanelTests: XCTestCase {

    /// The built-in retina, and a second display to its right that does not
    /// start at the origin (so "global, not display-local" is exercised).
    private let retina = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let asus = CGRect(x: 1728, y: -200, width: 1920, height: 1080)

    private func slice(of screen: CGRect, factor: CGFloat, at unitOrigin: CGPoint) -> CGRect {
        let w = screen.width / factor, h = screen.height / factor
        return CGRect(x: screen.minX + unitOrigin.x * (screen.width - w),
                      y: screen.minY + unitOrigin.y * (screen.height - h), width: w, height: h)
    }

    /// What the glass shows of a framebuffer rect: the slice blown up to the display.
    private func onGlass(_ r: CGRect, screen: CGRect, visible: CGRect) -> CGRect {
        let m = screen.width / visible.width
        return CGRect(x: screen.minX + (r.minX - visible.minX) * m,
                      y: screen.minY + (r.minY - visible.minY) * m,
                      width: r.width * m, height: r.height * m)
    }

    private let zooms: [(CGFloat, CGPoint)] = [
        (2, CGPoint(x: 0.5, y: 0.5)), (2, CGPoint(x: 0, y: 1)), (3, CGPoint(x: 1, y: 0)),
        (1.5, CGPoint(x: 0.3, y: 0.7)), (8, CGPoint(x: 0.9, y: 0.1)),
    ]

    // MARK: - The pure map

    /// At rest the map must hand back the very same rect — not one within an
    /// ulp — or a follower ticking on an unzoomed Mac re-frames the window
    /// every tick.
    func testAtRestTheFrameIsUntouched() {
        let design = CGRect(x: 1728 + 0.1, y: -200 + 1.0 / 3, width: 1151.7, height: 623.3)
        XCTAssertEqual(ZoomedPanel.frame(design: design, screen: asus, visible: asus), design)
        let p = CGPoint(x: 1999.123, y: 17.25)
        XCTAssertEqual(ZoomedPanel.designPoint(p, screen: asus, visible: asus), p)
    }

    /// The single-screen board (bottom-right ⅔ of the retina, hugged) is the
    /// same rectangle on the glass at every zoom and pan.
    func testTheCornerBoardLooksTheSameOnTheGlass() {
        let board = CGRect(x: 560, y: 16, width: 1152, height: 623)
        for (factor, at) in zooms {
            let v = slice(of: retina, factor: factor, at: at)
            let f = ZoomedPanel.frame(design: board, screen: retina, visible: v)
            XCTAssertEqual(f.width, board.width / factor, accuracy: 1e-6, "×\(factor)")
            let g = onGlass(f, screen: retina, visible: v)
            for (a, b) in [(g.minX, board.minX), (g.minY, board.minY), (g.width, board.width), (g.height, board.height)] {
                XCTAssertEqual(a, b, accuracy: 0.01, "×\(factor) at \(at)")
            }
            // …and, shrunk, it is inside the slice — on the glass, not off it.
            XCTAssertTrue(v.insetBy(dx: -0.01, dy: -0.01).contains(f), "×\(factor) at \(at)")
        }
    }

    /// The board that owns the second screen, and the whip that covers a whole
    /// screen: zoomed, the window IS the slice.
    func testAWholeScreenPanelBecomesTheSlice() {
        for (factor, at) in zooms {
            let v = slice(of: asus, factor: factor, at: at)
            let f = ZoomedPanel.frame(design: asus, screen: asus, visible: v)
            XCTAssertEqual(f.minX, v.minX, accuracy: 1e-6)
            XCTAssertEqual(f.minY, v.minY, accuracy: 1e-6)
            XCTAssertEqual(f.width, v.width, accuracy: 1e-6)
            XCTAssertEqual(f.height, v.height, accuracy: 1e-6)
        }
    }

    /// The click: the pointer is wherever the glass shows the tile, i.e. at the
    /// mapped point in the framebuffer. Taken back through `designPoint` it must
    /// be the tile's own point on the unzoomed screen — and that is also what the
    /// content view sees once its bounds are the design size: window-local
    /// framebuffer offset ÷ the shrink.
    func testAClickOnTheGlassLandsOnTheTileDrawnThere() {
        let board = CGRect(x: 560, y: 16, width: 1152, height: 623)
        let tileCentre = CGPoint(x: 560 + 41, y: 16 + 623 - 41)   // top-left tile
        for (factor, at) in zooms {
            let v = slice(of: retina, factor: factor, at: at)
            let f = ZoomedPanel.frame(design: board, screen: retina, visible: v)
            let k = f.width / board.width
            let pointer = CGPoint(x: f.minX + (tileCentre.x - board.minX) * k,
                                  y: f.minY + (tileCentre.y - board.minY) * k)
            let back = ZoomedPanel.designPoint(pointer, screen: retina, visible: v)
            XCTAssertEqual(back.x, tileCentre.x, accuracy: 1e-6, "×\(factor) at \(at)")
            XCTAssertEqual(back.y, tileCentre.y, accuracy: 1e-6, "×\(factor) at \(at)")
            let inContent = CGPoint(x: (pointer.x - f.minX) / k, y: (pointer.y - f.minY) / k)
            XCTAssertEqual(inContent.x, tileCentre.x - board.minX, accuracy: 1e-6)
            XCTAssertEqual(inContent.y, tileCentre.y - board.minY, accuracy: 1e-6)
        }
    }

    // MARK: - AppKit really scales hit-testing with the drawing

    /// The whole approach rests on AppKit mapping window points through a
    /// content view whose bounds are larger than its frame. Proved on a real
    /// panel: shrunk to half, a click at the window point where a tile is DRAWN
    /// hits that tile; and after a factor change the bounds are re-asserted
    /// (AppKit keeps the old ratio through a resize).
    func testAShrunkPanelStillHitsTheTileUnderThePointer() {
        _ = NSApplication.shared
        let design = CGRect(x: 100, y: 100, width: 400, height: 200)
        let panel = NSPanel(contentRect: design, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        let content = NSView(frame: CGRect(origin: .zero, size: design.size))
        content.wantsLayer = true
        panel.contentView = content
        let tile = NSView(frame: CGRect(x: 300, y: 100, width: 80, height: 80))
        content.addSubview(tile)

        for factor in [2.0, 4.0, 1.0] as [CGFloat] {
            let v = slice(of: retina, factor: factor, at: CGPoint(x: 0.1, y: 0.2))
            let visible = factor == 1 ? retina : v
            let f = ZoomedPanel.frame(design: design, screen: retina, visible: visible)
            ZoomedPanel.apply(panel, frame: f, designSize: design.size, display: false)
            XCTAssertEqual(panel.frame.width, design.width / factor, accuracy: 0.5, "×\(factor)")
            XCTAssertEqual(content.bounds.size, design.size, "×\(factor): bounds stay the design size")
            // The tile's centre, as drawn: design offset × shrink, in window points.
            let k = panel.frame.width / design.width
            let inWindow = CGPoint(x: 340 * k, y: 140 * k)
            let local = content.convert(inWindow, from: nil)
            XCTAssertEqual(local.x, 340, accuracy: 1, "×\(factor)")
            XCTAssertEqual(local.y, 140, accuracy: 1, "×\(factor)")
            XCTAssertTrue(content.superview?.hitTest(inWindow) === tile, "×\(factor)")
            XCTAssertFalse(content.superview?.hitTest(CGPoint(x: 100 * k, y: 40 * k)) === tile, "×\(factor)")
        }
        XCTAssertEqual(panel.frame, design, "back at rest it is the design frame again")
    }

    // MARK: - 🔥 Whip

    /// At rest the whip's pointer conversion is the one it always had.
    func testTheWhipPointerIsUnchangedAtRest() {
        let g = CGPoint(x: 2000, y: 300)
        let p = WhipController.viewPoint(forGlobal: g, screen: asus, visible: asus)
        XCTAssertEqual(p, CGPoint(x: g.x - asus.minX, y: asus.maxY - g.y))
    }

    /// Zoomed, the whip's view counts in GLASS points (the panel is the slice,
    /// its bounds the whole screen): the pointer at the middle of the slice is
    /// the middle of the view, and the slice's top-left is the view's origin.
    func testTheWhipPointerIsInGlassPointsWhenZoomed() {
        for (factor, at) in zooms {
            let v = slice(of: asus, factor: factor, at: at)
            let mid = WhipController.viewPoint(forGlobal: CGPoint(x: v.midX, y: v.midY), screen: asus, visible: v)
            XCTAssertEqual(mid.x, asus.width / 2, accuracy: 1e-6, "×\(factor)")
            XCTAssertEqual(mid.y, asus.height / 2, accuracy: 1e-6, "×\(factor)")
            let topLeft = WhipController.viewPoint(forGlobal: CGPoint(x: v.minX, y: v.maxY), screen: asus, visible: v)
            XCTAssertEqual(topLeft.x, 0, accuracy: 1e-6)
            XCTAssertEqual(topLeft.y, 0, accuracy: 1e-6, "y counts DOWN from the top of the glass")
        }
    }

    // MARK: - 🤖 Peek click target

    /// A mascot straight on the host layer: the target is its frame, moved to
    /// the overlay screen's origin — what it always was.
    func testThePeekTargetOverAnUnstagedMascotIsItsFrame() {
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: asus.size)
        let mascot = CALayer()
        mascot.frame = CGRect(x: 86, y: 500, width: 380, height: 300)
        root.addSublayer(mascot)
        XCTAssertEqual(PeekHitPanel.globalFrame(of: mascot, in: root, screenOrigin: asus.origin),
                       mascot.frame.offsetBy(dx: asus.minX, dy: asus.minY))
    }

    /// A mascot on the zoom stage: the target lands where the stage draws it,
    /// which is `ZoomedPanel.frame` of the unstaged frame — the same place the
    /// other two panels go — so on the glass it covers the robot the room sees.
    func testThePeekTargetFollowsAStagedMascotOntoTheGlass() {
        let root = CALayer()
        root.bounds = CGRect(origin: .zero, size: retina.size)
        let design = CGRect(x: 78, y: 474, width: 365, height: 286)
        for (factor, at) in zooms {
            let v = slice(of: retina, factor: factor, at: at)
            let stage = CALayer()
            let g = ZoomFollower.stageGeometry(visible: v, laidOut: retina)
            stage.bounds = g.bounds
            stage.position = g.position
            stage.transform = CATransform3DMakeScale(g.scale, g.scale, 1)
            root.addSublayer(stage)
            let mascot = CALayer()
            mascot.frame = design
            stage.addSublayer(mascot)

            let target = PeekHitPanel.globalFrame(of: mascot, in: root, screenOrigin: retina.origin)
            let expected = ZoomedPanel.frame(design: design, screen: retina, visible: v)
            XCTAssertEqual(target.minX, expected.minX, accuracy: 0.01, "×\(factor) at \(at)")
            XCTAssertEqual(target.minY, expected.minY, accuracy: 0.01, "×\(factor) at \(at)")
            XCTAssertEqual(target.width, expected.width, accuracy: 0.01, "×\(factor) at \(at)")
            XCTAssertEqual(target.height, expected.height, accuracy: 0.01, "×\(factor) at \(at)")
            stage.removeFromSuperlayer()
        }
    }
}
