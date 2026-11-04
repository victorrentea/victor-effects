import QuartzCore
import XCTest
@testable import VictorEffects

/// ☢️ The blast's shake, checked without a screen, a capture or the raid's event
/// tap: everything that can be wrong with it is a number in `BombShake`.
final class BombShakeTests: XCTestCase {

    private let width: CGFloat = 1728

    private func reach(at t: Double) -> Double {
        let p = BombShake.offset(at: t, width: width)
        return max(abs(Double(p.x)), abs(Double(p.y)))
    }

    private func maxReach(from a: Double, to b: Double) -> Double {
        stride(from: a, to: b, by: 0.002).map(reach).max() ?? 0
    }

    /// It hangs off the one measurement of the clip, and it ends inside the clip.
    func testItStartsOnTheBlastInTheClip() {
        XCTAssertEqual(BombShake.startsInClip, EmojiAnimator.explosionBlastOnset)
        XCTAssertEqual(BombShake.seconds, 0.5)
        XCTAssertLessThan(BombShake.startsInClip + BombShake.seconds, 3.28)
    }

    /// Rests on the blast's first frame, so the photograph lands on the desktop
    /// with no jump, and is at it within the frames the ear hears the step in.
    func testItHitsAtOnceFromRest() {
        XCTAssertEqual(reach(at: 0), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(maxReach(from: 0, to: 0.05), 0.5 * Double(width * BombShake.amplitude))
    }

    /// Dies away, and dies completely: a last twitch at the end would be the
    /// photograph snapping back to the desktop under it.
    func testItDecaysToExactlyNothing() {
        XCTAssertLessThan(maxReach(from: 0.4, to: 0.5), 0.2 * maxReach(from: 0, to: 0.1))
        XCTAssertEqual(reach(at: BombShake.seconds), 0)
        XCTAssertEqual(reach(at: BombShake.seconds + 1), 0)
        XCTAssertEqual(reach(at: -0.01), 0)
        let steps = stride(from: 0, to: BombShake.seconds, by: 0.05).map(BombShake.envelope)
        XCTAssertEqual(steps, steps.sorted(by: >))
    }

    /// "A little": it never leaves ~1 % of the screen.
    func testItIsSmall() {
        XCTAssertLessThanOrEqual(maxReach(from: 0, to: BombShake.seconds), Double(width) * 0.01)
        XCTAssertGreaterThanOrEqual(BombShake.amplitude * width, 8, "too small to see from the back of a room")
    }

    /// Both axes move, so it rattles rather than slides.
    func testItShakesInBothDirections() {
        let points = stride(from: 0, to: BombShake.seconds, by: 0.01).map { BombShake.offset(at: $0, width: width) }
        XCTAssertLessThan(points.map(\.x).min() ?? 0, -1)
        XCTAssertGreaterThan(points.map(\.x).max() ?? 0, 1)
        XCTAssertLessThan(points.map(\.y).min() ?? 0, -1)
        XCTAssertGreaterThan(points.map(\.y).max() ?? 0, 1)
    }

    /// The photograph is taken before the bomb can be in it, with time left for the
    /// capture, and after the press.
    func testThePhotographIsTakenBeforeTheBombEnters() {
        XCTAssertGreaterThan(BombShake.captureDelay, 0)
        XCTAssertEqual(BombShake.captureDelay + BombShake.captureLead, EmojiAnimator.bombAutoDropDelay, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(BombShake.captureLead, 0.2)
    }

    /// One additive animation, no fill: it fits any layer, and when it ends there
    /// is nothing to undo. Starts and ends on the layer's own place.
    func testTheAnimationLeavesNothingBehind() throws {
        let a = BombShake.animation(width: width)
        XCTAssertTrue(a.isAdditive)
        XCTAssertEqual(a.keyPath, "position")
        XCTAssertEqual(a.duration, BombShake.seconds)
        XCTAssertEqual(a.beginTime, 0, "stamped by the fireball's own commit, not by a second clock")
        XCTAssertEqual(a.fillMode, .removed)

        let values = try XCTUnwrap(a.values as? [NSValue]).map(\.pointValue)
        XCTAssertEqual(values.count, a.keyTimes?.count)
        XCTAssertEqual(a.keyTimes?.first, 0)
        XCTAssertEqual(a.keyTimes?.last, 1)
        XCTAssertEqual(values.first, .zero)
        XCTAssertEqual(values.last, .zero)
    }

    /// The fireball and the photograph are in different coordinates under a zoom;
    /// a shake stated as a fraction of each one's own width comes out equal on the glass.
    func testTheShakeScalesWithTheWidthItIsGiven() {
        let full = BombShake.offset(at: 0.1, width: 1600)
        let slice = BombShake.offset(at: 0.1, width: 800)
        XCTAssertEqual(full.x, slice.x * 2, accuracy: 1e-6)
        XCTAssertEqual(full.y, slice.y * 2, accuracy: 1e-6)
    }

    // MARK: - The picture on the overlay (no capture, no tap: the shot is handed in)

    private func scene() -> (host: CALayer, animator: EmojiAnimator, fireball: CALayer, image: CGImage) {
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let animator = EmojiAnimator(hostLayer: host)
        let fireball = CALayer()
        animator.stageLayer.addSublayer(fireball)
        let image = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        return (host, animator, fireball, image)
    }

    private func picture(under host: CALayer, showing image: CGImage) -> CALayer? {
        for holder in host.sublayers ?? [] {
            if let hit = holder.sublayers?.first(where: { $0.contents as AnyObject? === image }) { return hit }
        }
        return nil
    }

    /// The fireball stays in front of the photograph, and both run the shake.
    func testThePictureGoesUnderTheFireballAndBothShake() throws {
        let (host, animator, fireball, image) = scene()
        defer { animator.stopAllActiveEffects() }
        animator.shakeTheWholePicture(fireball: fireball,
                                      shot: (image, ZoomSlice(unit: nil, rect: host.bounds)))

        let picture = try XCTUnwrap(self.picture(under: host, showing: image))
        XCTAssertEqual(picture.frame, host.bounds)
        XCTAssertNotNil(picture.animation(forKey: BombShake.animationKey))
        XCTAssertNotNil(fireball.animation(forKey: BombShake.animationKey))
        XCTAssertTrue(host.sublayers?.last === animator.stageLayer, "the holder landed over the fireball")
    }

    /// No capture (refused, failed, late): the fireball shakes alone and nothing
    /// goes over the desktop.
    func testWithNoPhotographTheFireballShakesAlone() {
        let (host, animator, fireball, image) = scene()
        defer { animator.stopAllActiveEffects() }
        animator.shakeTheWholePicture(fireball: fireball, shot: nil)
        XCTAssertNotNil(fireball.animation(forKey: BombShake.animationKey))
        XCTAssertNil(picture(under: host, showing: image))
    }

    /// The self-termination rule: nobody has to come and take the picture off.
    func testThePictureRemovesItself() throws {
        let (host, animator, fireball, image) = scene()
        defer { animator.stopAllActiveEffects() }
        animator.shakeTheWholePicture(fireball: fireball,
                                      shot: (image, ZoomSlice(unit: nil, rect: host.bounds)))
        let picture = try XCTUnwrap(self.picture(under: host, showing: image))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: BombShake.seconds + 0.1))
        XCTAssertNil(picture.superlayer)
    }

    /// A stop-all (and so a suspend, which goes through it) takes the frozen
    /// desktop off at once: it must not sit over a live one for a moment longer.
    func testAStopAllTakesThePictureOffAtOnce() throws {
        let (host, animator, fireball, image) = scene()
        animator.shakeTheWholePicture(fireball: fireball,
                                      shot: (image, ZoomSlice(unit: nil, rect: host.bounds)))
        let picture = try XCTUnwrap(self.picture(under: host, showing: image))
        animator.stopAllActiveEffects()
        XCTAssertNil(picture.superlayer)
    }
}
