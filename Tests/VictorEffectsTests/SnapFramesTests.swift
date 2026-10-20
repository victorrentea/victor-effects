import XCTest
@testable import VictorEffects

/// 🫰 The shipped snapping hand (2026-10-20): frame 0 at rest, the rest played
/// once per click with their own delays — the impact frames are shorter than
/// 100 ms, which only survives if the unclamped delay is the one read.
final class SnapFramesTests: XCTestCase {

    private func shipped() throws -> SnapFrames {
        let url = try XCTUnwrap(EffectsResources.bundle.url(forResource: "finger-snap", withExtension: "png")
            ?? EffectsResources.bundle.url(forResource: "finger-snap", withExtension: "png", subdirectory: "Resources"))
        return try XCTUnwrap(SnapFrames.load(url))
    }

    func testTheShippedHandIsFourFramesWithItsOwnShortImpacts() throws {
        let frames = try shipped()
        XCTAssertEqual(frames.images.count, 4)
        XCTAssertEqual(frames.delaysMs[1], 50, accuracy: 1)
        XCTAssertEqual(frames.delaysMs[2], 60, accuracy: 1)
        XCTAssertEqual(frames.snapMs, 560, accuracy: 3)
    }

    func testTheHandIsCutOut() throws {
        // A corner of the rest frame must be transparent: the photo's grey
        // wall around the hand is exactly what the cut-out took away.
        let image = try shipped().images[0]
        XCTAssertNotEqual(image.alphaInfo, .none)
        XCTAssertNotEqual(image.alphaInfo, .noneSkipLast)
        XCTAssertNotEqual(image.alphaInfo, .noneSkipFirst)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Top-right corner, scaled into the 1×1 probe.
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width) + 1, y: -CGFloat(image.height) + 1,
                                   width: CGFloat(image.width), height: CGFloat(image.height)))
        let alpha = try XCTUnwrap(ctx.data).load(fromByteOffset: 3, as: UInt8.self)
        XCTAssertEqual(alpha, 0)
    }

    func testAClickPlaysEachFrameOnceThenRests() {
        let img = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let frames = SnapFrames(images: [img, img, img, img], delaysMs: [500, 50, 60, 450])
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: nil), 0)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 0), 1)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 49), 1)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 50), 2)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 110), 3)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 559), 3)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 560), 0)
        XCTAssertEqual(frames.frameIndex(sinceSnapMs: 10_000), 0)
    }
}
