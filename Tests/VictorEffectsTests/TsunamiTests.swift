import CoreGraphics
import XCTest
@testable import VictorEffects

final class TsunamiTests: XCTestCase {

    private let screen = CGSize(width: 1728, height: 1117)

    /// The pieces are the screen until they are ripped off: together they must
    /// cover it exactly, or the first frame shows a seam over the real desktop.
    func testPiecesTileTheScreenExactly() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 3456, height: 2234, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let shot = try XCTUnwrap(ctx.makeImage())
        let pieces = Tsunami.pieces(of: shot, size: screen)
        XCTAssertEqual(pieces.count % Tsunami.columns, 0)
        let area = pieces.reduce(CGFloat(0)) { $0 + $1.frame.width * $1.frame.height }
        XCTAssertEqual(area, screen.width * screen.height, accuracy: 1)
        let union = pieces.reduce(CGRect.null) { $0.union($1.frame) }
        XCTAssertEqual(union.width, screen.width, accuracy: 0.01)
        XCTAssertEqual(union.height, screen.height, accuracy: 0.01)
    }

    /// The lip crosses left to right on the clip's roar; the hollow face below
    /// it trails, so low pieces go a little after high ones at the same x.
    func testTheWaveReachesLeftBeforeRightAndHighBeforeLow() {
        let left = Tsunami.launchTime(x: 0, y: screen.height * 0.9, size: screen)
        let right = Tsunami.launchTime(x: screen.width, y: screen.height * 0.9, size: screen)
        XCTAssertEqual(left, Tsunami.frontEnters, accuracy: 1e-9)
        XCTAssertEqual(right, Tsunami.frontEnters + Tsunami.frontCrosses, accuracy: 1e-9)
        XCTAssertGreaterThan(Tsunami.launchTime(x: 500, y: 0, size: screen),
                             Tsunami.launchTime(x: 500, y: screen.height * 0.9, size: screen))
    }

    /// Self-termination: the effect ends with the clip, but never before the
    /// wave has crossed, left and dried.
    func testLivesForTheClipButNeverCutsTheWaveShort() {
        XCTAssertEqual(Tsunami.totalDuration(clip: 7.3), 7.3)
        XCTAssertGreaterThanOrEqual(Tsunami.totalDuration(clip: 1),
                                    Tsunami.frontEnters + Tsunami.frontCrosses * Double(1 + Tsunami.bodyShare))
    }
}
