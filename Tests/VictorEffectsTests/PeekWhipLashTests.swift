import XCTest
@testable import VictorEffects

/// 🔥 The ⌘⌃Q mascot jumps only when the rope HITS him — through his drawn
/// pixels, moving fast, and not with the handle he is merely being pointed at
/// with (Victor, 2026-10-16). Before that every crack anywhere made him jump.
final class PeekWhipLashTests: XCTestCase {

    /// A 100×50 picture whose right half is opaque and left half transparent.
    private func halfOpaqueImage() -> CGImage {
        let ctx = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 50, y: 0, width: 50, height: 50))
        return ctx.makeImage()!
    }

    func testTheMaskSeesThePictureNotTheBox() {
        let mask = PeekAlphaMask(image: halfOpaqueImage())!
        let frame = CGRect(x: 200, y: 100, width: 200, height: 100)
        XCTAssertTrue(mask.isOpaque(CGPoint(x: 350, y: 150), in: frame), "right half is drawn")
        XCTAssertFalse(mask.isOpaque(CGPoint(x: 230, y: 150), in: frame), "left half is a transparent corner")
        XCTAssertFalse(mask.isOpaque(CGPoint(x: 450, y: 150), in: frame), "outside the box")
    }

    func testTheMaskFollowsAspectFit() {
        // A 2:1 picture in a 200×200 frame is drawn 200×100, centred vertically.
        let mask = PeekAlphaMask(image: halfOpaqueImage())!
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertTrue(mask.isOpaque(CGPoint(x: 150, y: 100), in: frame))
        XCTAssertFalse(mask.isOpaque(CGPoint(x: 150, y: 20), in: frame), "letterbox above/below is empty")
    }

    private let target = CGRect(x: 100, y: 100, width: 50, height: 50)
    private func onTarget(_ p: CGPoint) -> Bool { target.contains(p) }

    func testAFastLinkThroughHimIsAHit() {
        let points = (0..<9).map { CGPoint(x: CGFloat($0) * 20, y: 120) }
        let speeds = [CGFloat](repeating: 40, count: 9)
        let hit = EmojiAnimator.firstLashHit(points: points, speeds: speeds, minSpeed: 18, from: 3, isOpaque: onTarget)
        XCTAssertNotNil(hit)
        XCTAssertTrue(target.contains(hit!))
    }

    func testADrapedRopeIsNotAHit() {
        let points = (0..<9).map { CGPoint(x: CGFloat($0) * 20, y: 120) }
        let speeds = [CGFloat](repeating: 3, count: 9)
        XCTAssertNil(EmojiAnimator.firstLashHit(points: points, speeds: speeds, minSpeed: 18, from: 3, isOpaque: onTarget))
    }

    func testTheHandleEndNeverCounts() {
        // Only links 0…2 are over him; the hand is resting the pointer on him.
        var points = (0..<9).map { CGPoint(x: 500 + CGFloat($0) * 20, y: 400) }
        points[0] = CGPoint(x: 110, y: 110); points[1] = CGPoint(x: 120, y: 120); points[2] = CGPoint(x: 130, y: 130)
        let speeds = [CGFloat](repeating: 40, count: 9)
        XCTAssertNil(EmojiAnimator.firstLashHit(points: points, speeds: speeds, minSpeed: 18, from: 3, isOpaque: onTarget))
    }

    func testAThinLimbBetweenTwoLinksIsNotSteppedOver() {
        // Links at x = 60 and x = 120 straddle a 10 pt limb at x 85…95.
        let limb = CGRect(x: 85, y: 0, width: 10, height: 300)
        let points = [CGPoint(x: 0, y: 100), CGPoint(x: 60, y: 100), CGPoint(x: 120, y: 100)]
        let hit = EmojiAnimator.firstLashHit(points: points, speeds: [40, 40, 40], minSpeed: 18, from: 1,
                                             isOpaque: { limb.contains($0) })
        XCTAssertNotNil(hit)
    }
}
