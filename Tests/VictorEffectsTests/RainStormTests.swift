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

    /// The band has to close from BOTH sides at once — all of them entering
    /// from one edge is a wipe, not weather. With an odd count the extra one
    /// comes from the left, so the two sides are never more than one apart.
    func testTheCloudsSplitEvenlyBetweenTheTwoSides() {
        let sides = RainStorm.arrivals(in: bounds).map { $0.fromLeft }
        let left = sides.filter { $0 }.count
        let right = sides.count - left
        XCTAssertEqual(sides.count, RainStorm.cloudCount)
        XCTAssertLessThanOrEqual(abs(left - right), 1, "\(left) from the left, \(right) from the right")
        XCTAssertGreaterThan(left, 0)
        XCTAssertGreaterThan(right, 0)
    }

    /// Every per-cloud table has to be as long as the band, or a seventh cloud
    /// would read the sixth's numbers — or crash on the subscript.
    func testEveryPerCloudTableIsAsLongAsTheBand() {
        XCTAssertEqual(RainStorm.cloudCentres.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.cloudOverhang.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.cloudDip.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.cloudDelays.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.driftX.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.driftY.count, RainStorm.cloudCount)
        XCTAssertEqual(RainStorm.driftSeconds.count, RainStorm.cloudCount)
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

    /// The band hangs in the TOP QUARTER or so. This is what "a bit higher"
    /// was: seven smaller clouds instead of four big ones, so the ceiling stops
    /// eating a third of the desktop under it.
    func testTheBandStaysOutOfTheTopThird() {
        let lowest = RainStorm.arrivals(in: bounds).map { $0.rest.minY }.min()!
        let depth = (bounds.height - lowest) / bounds.height
        XCTAssertLessThan(depth, 0.28, "the ceiling hangs \(Int(depth * 100))% down — too much of the demo is under cloud")
        XCTAssertGreaterThan(depth, 0.12, "the ceiling hangs \(Int(depth * 100))% down — too thin to read as overcast")
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

    // MARK: - The drift that never stops

    /// A cloud that parks is a picture. Every one of them has to keep moving,
    /// and by an amount that is noticeable only if you look for it.
    func testEveryCloudKeepsDriftingByALittle() {
        for i in 0..<RainStorm.cloudCount {
            let drift = RainStorm.drift(for: i, in: bounds)
            XCTAssertNotEqual(drift.dx, 0, "cloud \(i) parks")
            XCTAssertLessThan(abs(drift.dx), bounds.width * 0.035, "cloud \(i) sways far enough to be a slide")
            XCTAssertLessThan(abs(drift.dy), bounds.height * 0.02, "cloud \(i) bobs far enough to be a bounce")
            XCTAssertGreaterThan(drift.seconds, 5, "cloud \(i) sways fast enough to read as a wobble")
        }
    }

    /// Seven clouds breathing in step is one object wobbling, which is more
    /// obviously artificial than not moving at all. Distinct periods, and no
    /// pair a small multiple of the other.
    func testTheCloudsDoNotBreatheInStep() {
        let periods = RainStorm.driftSeconds
        XCTAssertEqual(Set(periods).count, periods.count)
        for (i, a) in periods.enumerated() {
            for b in periods[(i + 1)...] {
                let ratio = max(a, b) / min(a, b)
                XCTAssertGreaterThan(abs(ratio - ratio.rounded()), 0.04,
                                     "\(a)s and \(b)s resynchronise every few cycles")
            }
        }
    }

    /// Consecutive clouds must not sway the same way, or their overlap opens
    /// and closes as one seam instead of the band churning.
    func testNeighbouringCloudsSwayAgainstEachOther() {
        for (a, b) in zip(RainStorm.driftX, RainStorm.driftX.dropFirst()) {
            XCTAssertLessThan(a * b, 0, "\(a) and \(b) sway together")
        }
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

    // MARK: - The flight of one drop
    //
    // This is the bug the emitter had, written down. It expressed the fall as
    // `emissionLongitude` — an angle whose zero and whose sign are a convention
    // rather than a coordinate — and on this layer it came out sideways: a dense
    // band of streaks sliding LEFT under the cloud base, never reaching the
    // floor. A start and an end point cannot be misread, and these assert it
    // without opening a window.

    func testADropActuallyFallsToTheFloor() {
        for depth in stride(from: CGFloat(0), through: 1, by: 0.25) {
            let drop = RainStorm.drop(in: bounds, lineY: RainStorm.rainLineY(in: bounds),
                                      depth: depth, atX: bounds.midX)
            XCTAssertLessThan(drop.end.y, drop.start.y, "depth \(depth): the drop must go DOWN")
            XCTAssertLessThanOrEqual(drop.end.y, 0, "depth \(depth): it must leave through the bottom edge")
            XCTAssertGreaterThan(drop.start.y, bounds.midY, "depth \(depth): it must be born up at the cloud base")
        }
    }

    /// Down first, sideways second — the whole point. The vertical travel has
    /// to dwarf the horizontal one, and the lean has to be to the LEFT (Victor,
    /// 2026-09-19: "fall down… and perhaps slightly diagonally to left a bit").
    func testTheDropLeansLeftAndOnlyALittle() {
        let drop = RainStorm.drop(in: bounds, lineY: RainStorm.rainLineY(in: bounds),
                                  depth: 0.5, atX: bounds.midX)
        let dx = drop.end.x - drop.start.x
        let dy = drop.start.y - drop.end.y
        XCTAssertLessThan(dx, 0, "the wind blows left")
        XCTAssertGreaterThan(dy, abs(dx) * 8, "it is falling, not drifting: \(dy) down for \(abs(dx)) across")
    }

    /// The streak has to lie ALONG its path. A vertical sprite travelling at an
    /// angle reads as a drop sliding sideways, which is the other half of what
    /// the emitter got wrong.
    func testTheStreakIsTiltedOntoItsOwnPath() {
        let drop = RainStorm.drop(in: bounds, lineY: RainStorm.rainLineY(in: bounds),
                                  depth: 0.5, atX: bounds.midX)
        let dx = drop.end.x - drop.start.x
        let dy = drop.start.y - drop.end.y
        XCTAssertEqual(drop.angle, atan2(dx, dy), accuracy: 0.0001)
        XCTAssertLessThan(abs(drop.angle), 0.2, "a 12° lean is weather; more is a gale")
    }

    /// Near drops are bigger, faster and brighter than far ones — one number
    /// carries all of it, so a drop can never read as a contradiction.
    func testDepthDrivesSizeSpeedAndBrightnessTogether() {
        let line = RainStorm.rainLineY(in: bounds)
        let far = RainStorm.drop(in: bounds, lineY: line, depth: 0, atX: bounds.midX)
        let near = RainStorm.drop(in: bounds, lineY: line, depth: 1, atX: bounds.midX)
        XCTAssertGreaterThan(near.size.height, far.size.height)
        XCTAssertGreaterThan(near.size.width, far.size.width)
        XCTAssertGreaterThan(near.opacity, far.opacity)
        XCTAssertLessThan(near.seconds, far.seconds, "the near drop covers more ground in less time")
        XCTAssertGreaterThan(far.seconds, 0.2)
        XCTAssertLessThan(far.seconds, 3.0, "a drop that hangs for seconds is snow")
    }

    /// The entry span has to reach past the UPWIND edge by as much as the lean
    /// carries a drop across, or the far side of the screen is visibly drier
    /// than the near side.
    func testTheEntrySpanCoversBothEdgesOnceTheWindHasHadItsWay() {
        var landedLeft = false, landedRight = false
        for _ in 0..<4000 {
            let drop = RainStorm.randomDrop(in: bounds)
            if min(drop.start.x, drop.end.x) <= 0 { landedLeft = true }
            if max(drop.start.x, drop.end.x) >= bounds.width { landedRight = true }
        }
        XCTAssertTrue(landedLeft, "nothing rains past the left edge")
        XCTAssertTrue(landedRight, "nothing rains past the right edge")
    }

    /// The downpour must be a downpour, and the spawner must be able to deliver
    /// it in whole drops per tick.
    func testTheDownpourIsDenseEnoughToReadAsRain() {
        XCTAssertGreaterThan(RainStorm.dropsPerSecond, 100)
        XCTAssertGreaterThan(RainStorm.dropsPerSecond / RainStorm.dropSpawnHz, 2,
                             "fewer than a couple of drops a tick and the rain arrives in visible pulses")
        XCTAssertGreaterThanOrEqual(RainStorm.dropSpawnHz, 20, "the spawn tick would be visible as a stutter")
    }
}
