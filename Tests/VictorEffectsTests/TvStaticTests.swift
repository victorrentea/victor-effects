import XCTest
import QuartzCore
@testable import VictorEffects

/// 📺 The game-over backdrop is television static, and the two things that make
/// it read as static — square hard pixels and an actually-random, boiling grain —
/// are both easy to lose in a refactor and invisible in a code review.
final class TvStaticTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1920, height: 1200)

    func testNoiseIsRenderedAtAQuarterSizeInGrey() throws {
        let image = try XCTUnwrap(TvStatic.noiseImage(width: 480, height: 300))
        XCTAssertEqual(image.width, 480)
        XCTAssertEqual(image.height, 300)
        XCTAssertEqual(image.bitsPerPixel, 8)
        // Interpolation off at the image level as well as on the layer: a blurred
        // blow-up is grey mush, not speckle.
        XCTAssertFalse(image.shouldInterpolate)
    }

    /// Black and white, and roughly half of each — a roll that drifted to all-one
    /// value would render a flat rectangle and nothing would look broken until
    /// someone saw it on a projector.
    func testNoiseIsBlackAndWhiteAndMixed() throws {
        var values: [UInt8] = []
        var i = 0
        // Deterministic alternating source: proves the generator writes what it
        // is given, per pixel, rather than filling a constant.
        _ = try XCTUnwrap(TvStatic.noiseImage(width: 4, height: 4, random: {
            let v: UInt8 = i % 2 == 0 ? 0 : 255
            i += 1
            values.append(v)
            return v
        }))
        XCTAssertEqual(values.count, 16)
        XCTAssertEqual(values.filter { $0 == 0 }.count, 8)
        XCTAssertEqual(values.filter { $0 == 255 }.count, 8)
    }

    func testFramesAreCachedPerSize() {
        let first = TvStatic.frames(for: screen.size)
        let again = TvStatic.frames(for: screen.size)
        XCTAssertEqual(first.count, TvStatic.frameCount)
        // Same CGImages back, not a fresh render: the press has to be instant.
        XCTAssertTrue(first.elementsEqual(again) { $0 === $1 })
    }

    func testLayerCyclesTheFramesDiscretelyAndForever() throws {
        let layer = try XCTUnwrap(TvStatic.makeLayer(in: screen))
        XCTAssertEqual(layer.frame, screen)
        XCTAssertEqual(layer.magnificationFilter, .nearest)
        XCTAssertEqual(layer.opacity, TvStatic.defaultAlpha)      // translucent: the desktop reads through
        XCTAssertLessThan(layer.opacity, 1.0)

        let flicker = try XCTUnwrap(layer.animation(forKey: "tvStatic") as? CAKeyframeAnimation)
        XCTAssertEqual(flicker.values?.count, TvStatic.frameCount)
        XCTAssertEqual(flicker.calculationMode, .discrete)        // swapped, never cross-faded
        XCTAssertEqual(flicker.repeatCount, .infinity)
        XCTAssertEqual(flicker.duration, Double(TvStatic.frameCount) / TvStatic.fps, accuracy: 0.0001)
        // 12–20 fps: slower reads as a slideshow, faster averages into grey.
        XCTAssertGreaterThanOrEqual(TvStatic.fps, 12)
        XCTAssertLessThanOrEqual(TvStatic.fps, 20)
    }
}
