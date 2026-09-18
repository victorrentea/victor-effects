import XCTest
@testable import VictorEffects

/// ⛈️ Tile #20's geometry, checked without a screen.
///
/// Same bargain as `WazzupCornerTests`: the storm is four numbers tables and a
/// seeded pile of circles, and every way it breaks is *visual* — a gap of clear
/// sky along the top edge, a cloud that stops with a corner still poking off
/// the side, lobes drawn outside their own sprite so the blur clips them into a
/// straight edge. None of that fails to compile and none of it shows up until
/// it is on a projector in front of a room.
final class RainStormTests: XCTestCase {

    private let bounds = CGRect(x: 0, y: 0, width: 1512, height: 982)

    // MARK: - The entrances

    func testTwoCloudsComeFromEachSide() {
        let sides = RainStorm.arrivals(in: bounds).map { $0.fromLeft }
        XCTAssertEqual(sides.filter { $0 }.count, 2)
        XCTAssertEqual(sides.filter { !$0 }.count, 2)
    }

    /// "Slides in from the side" and "is already half on screen when it starts"
    /// are different pictures. Every cloud begins with its trailing edge exactly
    /// on the screen edge — not a corner still inside it.
    func testEveryCloudStartsFullyOffItsOwnSide() {
        for (i, a) in RainStorm.arrivals(in: bounds).enumerated() {
            if a.fromLeft {
                XCTAssertEqual(a.start.maxX, 0, accuracy: 0.001, "cloud \(i) should start off the LEFT edge")
            } else {
                XCTAssertEqual(a.start.minX, bounds.width, accuracy: 0.001, "cloud \(i) should start off the RIGHT edge")
            }
            XCTAssertEqual(a.start.minY, a.rest.minY, accuracy: 0.001,
                           "cloud \(i) arrives horizontally — nothing here may drift it vertically")
            XCTAssertEqual(a.start.size, a.rest.size)
        }
    }

    /// The clouds are a ceiling, so they are **cut by the top edge** rather than
    /// floating below it — a cloud fully inside the frame reads as a sticker.
    func testEveryCloudOverhangsTheTopEdge() {
        for (i, a) in RainStorm.arrivals(in: bounds).enumerated() {
            XCTAssertGreaterThan(a.rest.maxY, bounds.height, "cloud \(i) should be cut by the top edge")
            XCTAssertLessThan(a.rest.minY, bounds.height, "cloud \(i) should still hang into the screen")
        }
    }

    /// The four of them have to overlap into ONE overcast band. A gap anywhere
    /// along the top edge is a strip of bright desktop with rain falling in
    /// front of it and nothing above it.
    func testTheBandCoversTheWholeWidthWithNoGap() {
        let spans = RainStorm.arrivals(in: bounds).map { ($0.rest.minX, $0.rest.maxX) }.sorted { $0.0 < $1.0 }
        XCTAssertLessThanOrEqual(spans.first!.0, 0, "the band must run off the left edge")
        XCTAssertGreaterThanOrEqual(spans.last!.1, bounds.width, "the band must run off the right edge")
        var covered = spans.first!.1
        for span in spans.dropFirst() {
            XCTAssertLessThan(span.0, covered, "a gap of clear sky between \(covered) and \(span.0)")
            covered = max(covered, span.1)
        }
    }

    /// Staggered, or the band arrives as one image cut down the middle.
    func testTheCloudsDoNotAllArriveTogether() {
        let delays = RainStorm.arrivals(in: bounds).map { $0.delay }
        XCTAssertEqual(delays.count, Set(delays).count, "every cloud needs its own head start")
        XCTAssertEqual(delays.min(), 0, "something has to leave immediately")
    }

    func testDegenerateBoundsProduceNoClouds() {
        XCTAssertTrue(RainStorm.arrivals(in: .zero).isEmpty)
        XCTAssertEqual(RainStorm.rainLineY(in: .zero), 0, "no clouds to ask ⇒ the bounds' own top edge")
    }

    // MARK: - Where the rain comes out

    /// Drops are born on the LOWEST cloud base, so none of them is ever born in
    /// open sky above a cloud that is still covering it.
    func testRainFallsFromTheLowestCloudBase() {
        let arrivals = RainStorm.arrivals(in: bounds)
        let line = RainStorm.rainLineY(in: bounds)
        XCTAssertEqual(line, arrivals.map { $0.rest.minY }.min()!)
        for a in arrivals {
            XCTAssertLessThanOrEqual(line, a.rest.minY + 0.001)
        }
        XCTAssertGreaterThan(line, bounds.midY, "the ceiling belongs in the top half of the screen")
    }

    // MARK: - The silhouette

    /// Every lobe has to fit inside the sprite's own box. A lobe that pokes out
    /// is not cropped into a smaller cloud — it is cropped into a cloud with a
    /// **ruler-straight edge** where the blur should have been, which is the one
    /// thing that gives a drawn cloud away.
    func testEveryLobeFitsInsideTheSpriteBox() {
        for seed in 0..<RainStorm.cloudCount {
            for (i, lobe) in RainStorm.lobes(seed: seed).enumerated() {
                let top = lobe.centre.y + lobe.radius
                XCTAssertLessThanOrEqual(top, RainStorm.cloudAspect,
                                         "cloud \(seed) lobe \(i) pokes out of the top of its own sprite")
                XCTAssertGreaterThanOrEqual(lobe.centre.y - lobe.radius, 0,
                                            "cloud \(seed) lobe \(i) hangs below its own base")
                // Sideways the sprite's own blur padding is the budget: a lobe
                // may hang out by less than that and still be blurred rather
                // than sliced.
                XCTAssertGreaterThanOrEqual(lobe.centre.x - lobe.radius, -RainStorm.spritePadding,
                                            "cloud \(seed) lobe \(i) hangs past the blur padding on the left")
                XCTAssertLessThanOrEqual(lobe.centre.x + lobe.radius, 1 + RainStorm.spritePadding,
                                         "cloud \(seed) lobe \(i) hangs past the blur padding on the right")
            }
        }
    }

    /// Four clouds cut from one stencil is exactly what the eye catches where
    /// they overlap, so the seeds have to actually produce different piles.
    func testTheCloudsAreNotTheSameCloudFourTimes() {
        let shapes = (0..<RainStorm.cloudCount).map { seed in
            RainStorm.lobes(seed: seed).map { "\($0.centre.x),\($0.centre.y),\($0.radius)" }.joined(separator: "|")
        }
        XCTAssertEqual(Set(shapes).count, RainStorm.cloudCount)
    }

    /// …but the same seed must always give the same cloud: the sprite cache is
    /// keyed on the index, so a shape that rolled fresh dice would pop on a
    /// re-press or between two screens.
    func testTheSameSeedIsAlwaysTheSameCloud() {
        for seed in 0..<RainStorm.cloudCount {
            let a = RainStorm.lobes(seed: seed).map { $0.radius }
            let b = RainStorm.lobes(seed: seed).map { $0.radius }
            XCTAssertEqual(a, b)
        }
    }

    // MARK: - Lightning

    /// The flash starts and ends at fully transparent, or a strike that is
    /// interrupted (stop-all, a re-press) leaves the desktop under a white
    /// sheet with nothing left running to take it off.
    func testAStrikeBeginsAndEndsInvisible() {
        XCTAssertEqual(RainStorm.flashOpacities.count, RainStorm.flashKeyTimes.count)
        XCTAssertEqual(RainStorm.flashOpacities.first, 0)
        XCTAssertEqual(RainStorm.flashOpacities.last, 0)
        XCTAssertEqual(RainStorm.flashKeyTimes.first, 0)
        XCTAssertEqual(RainStorm.flashKeyTimes.last, 1.0)
        XCTAssertEqual(RainStorm.flashKeyTimes.map { $0.doubleValue },
                       RainStorm.flashKeyTimes.map { $0.doubleValue }.sorted())
    }

    /// Two strikes are separate keyframe animations on ONE layer, so an overlap
    /// would not blend — the later one would simply win and the earlier one
    /// would stop mid-stroke.
    func testStrikesNeverOverlap() {
        let onsets = RainStorm.thunderOnsets
        XCTAssertEqual(onsets, onsets.sorted())
        for (a, b) in zip(onsets, onsets.dropFirst()) {
            XCTAssertGreaterThan(b - a, RainStorm.flashSeconds, "strikes at \(a)s and \(b)s overlap")
        }
    }

    /// Every roll has to be inside the clip: a flash scheduled past the end
    /// fires over a screen the storm has already left.
    func testEveryThunderRollIsInsideTheClip() {
        XCTAssertGreaterThan(RainStorm.thunderOnsets.first ?? 0, 0)
        XCTAssertLessThan((RainStorm.thunderOnsets.last ?? 0) + RainStorm.flashSeconds,
                          RainStorm.fallbackDuration)
    }

    // MARK: - The timeline

    /// The rain must not start before there is a cloud to fall out of, and the
    /// gloom must be all the way in before the first thunder roll.
    func testTheChoreographyIsInOrder() {
        let lastCloudLands = (RainStorm.cloudDelays.max() ?? 0) + RainStorm.cloudSlideSeconds
        XCTAssertLessThan(RainStorm.rainLeadIn, lastCloudLands,
                          "the rain should start while the band is still closing, not after it")
        XCTAssertGreaterThan(RainStorm.rainLeadIn, 0)
        XCTAssertLessThan(RainStorm.darkenSeconds, RainStorm.thunderOnsets.first ?? 0,
                          "the desktop should be dark by the first roll of thunder")
        XCTAssertLessThan(lastCloudLands + RainStorm.rainRampSeconds, RainStorm.fallbackDuration,
                          "the storm must reach full downpour well inside the clip")
    }

    // MARK: - The sprites

    func testACloudRendersAndIsCachedAtTheSizeItWasAskedFor() throws {
        let size = CGSize(width: 400, height: 400 * RainStorm.cloudAspect)
        let image = try XCTUnwrap(RainStorm.cloudImage(index: 0, size: size, scale: 2))
        // The canvas carries the blur's slack on every side — the caller insets
        // the layer frame by exactly that, so the two have to agree.
        let pad = size.width * 2 * RainStorm.spritePadding
        XCTAssertEqual(CGFloat(image.width), (size.width * 2 + pad * 2).rounded(), accuracy: 2)
        XCTAssertTrue(RainStorm.cloudImage(index: 0, size: size, scale: 2) === image, "second ask must hit the cache")
    }

    func testADropIsATallThinStreak() throws {
        let drop = try XCTUnwrap(RainStorm.dropImage(scale: 2))
        XCTAssertGreaterThan(drop.height, drop.width * 4, "rain reads as lines, not as dots")
    }
}
