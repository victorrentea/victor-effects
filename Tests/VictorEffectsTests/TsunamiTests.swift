import CoreGraphics
import XCTest
@testable import VictorEffects

final class TsunamiTests: XCTestCase {

    private let screen = CGSize(width: 1728, height: 1117)

    /// The sweep's edge sits behind the water on every row — the frontmost
    /// row exactly `margin` behind the lip, a trailing row as far behind as
    /// its water trails — from the top row down to the bottom one.
    func testTheSweptEdgeRidesBehindTheWaterOnEveryRow() {
        let frame = try! XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let sprite = Tsunami.Sprite(frames: [frame], front: [0.5, 1.0])
        let edge = sprite.edge(size: CGSize(width: 200, height: 100), margin: 4)
        XCTAssertEqual(edge.map(\.x), [-104, -4])
        XCTAssertEqual(edge.map(\.y), [75, 25])
    }

    /// Self-termination: the effect ends with the clip, but never before the
    /// wave has crossed, left and dried.
    func testLivesForTheClipButNeverCutsTheWaveShort() {
        XCTAssertEqual(Tsunami.totalDuration(clip: 7.3), 7.3)
        XCTAssertGreaterThanOrEqual(Tsunami.totalDuration(clip: 1),
                                    Tsunami.frontEnters + Tsunami.frontCrosses * Double(1 + Tsunami.bodyShare))
    }

    /// The filmed wave's front, read off its frames: the rightmost pixel each
    /// row has opaque in most frames, and the sky rows above take the crest's.
    func testFrontProfileFollowsTheWaterAndFillsTheSky() {
        // 4×3, top to bottom: sky, crest reaching x=1, sea reaching x=3.
        let a: [UInt8] = [0, 0, 0, 0,
                          255, 255, 0, 0,
                          255, 255, 255, 255]
        XCTAssertEqual(Tsunami.frontProfile(alpha: [a, a], width: 4, height: 3), [0.5, 0.5, 1])
        // A splash in one frame of three is not the front.
        var splash = a; splash[7] = 255
        XCTAssertEqual(Tsunami.frontProfile(alpha: [a, a, splash], width: 4, height: 3)[1], 0.5)
    }
}
