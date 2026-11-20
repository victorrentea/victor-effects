import XCTest
import ImageIO
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

    /// Three edges, not one. Seven clouds all sliding in horizontally read as a
    /// curtain being drawn; the sky has to close from the sides AND from above.
    /// The two sides stay balanced, or the band visibly arrives lopsided.
    func testTheCloudsComeFromAllThreeEdges() {
        let entries = RainStorm.arrivals(in: bounds).map { $0.from }
        XCTAssertEqual(entries.count, RainStorm.cloudCount)
        let left = entries.filter { $0 == .left }.count
        let right = entries.filter { $0 == .right }.count
        let top = entries.filter { $0 == .top }.count
        XCTAssertGreaterThan(left, 0, "nothing comes in from the left")
        XCTAssertGreaterThan(right, 0, "nothing comes in from the right")
        XCTAssertGreaterThan(top, 0, "nothing drops out of the top")
        XCTAssertLessThanOrEqual(abs(left - right), 1, "\(left) from the left, \(right) from the right")
    }

    /// A falling cloud always has a sliding one beside it. Three in a row
    /// dropping together is still one thing happening several times, which is
    /// the failure the mixed entrances exist to avoid.
    func testNoTwoNeighboursComeFromTheSameEdge() {
        let entries = RainStorm.cloudEntries
        for (i, (a, b)) in zip(entries, entries.dropFirst()).enumerated() {
            XCTAssertNotEqual(a, b, "clouds \(i) and \(i + 1) both come from \(a)")
        }
    }

    /// The clouds that fall are the INNER ones — from a side they would have to
    /// cross most of the screen to reach the middle, which is both the longest
    /// journey and the one that reads as a wipe.
    func testTheInnerCloudsAreTheOnesThatFall() {
        for (i, entry) in RainStorm.cloudEntries.enumerated() where entry.isSide {
            let centre = RainStorm.cloudCentres[i]
            let nearestEdge = min(centre, 1 - centre)
            XCTAssertLessThan(nearestEdge, 0.4, "cloud \(i) sits at \(centre) and still slides in from a side")
        }
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
    func testEveryCloudStartsFullyOutsideOnItsOwnEdge() {
        for (i, a) in RainStorm.arrivals(in: bounds).enumerated() {
            switch a.from {
            case .left:
                XCTAssertEqual(a.start.maxX, 0, accuracy: 0.001, "cloud \(i) should start off the LEFT edge")
            case .right:
                XCTAssertEqual(a.start.minX, bounds.width, accuracy: 0.001, "cloud \(i) should start off the RIGHT edge")
            case .top:
                XCTAssertGreaterThanOrEqual(a.start.minY, bounds.height - 0.001,
                                            "cloud \(i) should start ABOVE the top edge")
            }
            XCTAssertEqual(a.start.size, a.rest.size)
        }
    }

    /// One axis each. A cloud that arrived diagonally would be the only thing on
    /// screen moving in two directions at once, and it is the kind of thing a
    /// refactor of the start frames would introduce silently.
    func testEveryCloudTravelsInOneAxisOnly() {
        for (i, a) in RainStorm.arrivals(in: bounds).enumerated() {
            if a.isVertical {
                XCTAssertEqual(a.start.minX, a.rest.minX, accuracy: 0.001, "cloud \(i) falls AND slides")
                XCTAssertGreaterThan(a.start.minY, a.rest.minY, "cloud \(i) should come DOWN")
            } else {
                XCTAssertEqual(a.start.minY, a.rest.minY, accuracy: 0.001, "cloud \(i) slides AND falls")
                XCTAssertNotEqual(a.start.minX, a.rest.minX, "cloud \(i) does not move at all")
            }
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

    // MARK: - The timeline

    /// The rain must not start before there is a cloud to fall out of.
    func testTheChoreographyIsInOrder() {
        let lastCloudLands = (RainStorm.cloudDelays.max() ?? 0) + RainStorm.cloudSlideSeconds
        XCTAssertLessThan(RainStorm.rainLeadIn, lastCloudLands,
                          "the rain should start while the band is still closing, not after it")
        XCTAssertGreaterThan(RainStorm.rainLeadIn, 0)
        XCTAssertLessThan(lastCloudLands + RainStorm.rainRampSeconds, RainStorm.fallbackDuration,
                          "the storm must reach full downpour well inside the clip")
    }

    // MARK: - The sprites

    /// The drawn cloud has to render at exactly the size asked for, with the
    /// blur's slack on every side, because the caller insets the layer frame by
    /// exactly that.
    func testTheDrawnCloudRendersAtTheSizeItWasAskedFor() throws {
        let size = CGSize(width: 400, height: 400 * RainStorm.cloudAspect)
        let image = try XCTUnwrap(RainStorm.drawnCloud(index: 0, size: size, scale: 2))
        let pad = size.width * 2 * RainStorm.spritePadding
        XCTAssertEqual(CGFloat(image.width), (size.width * 2 + pad * 2).rounded(), accuracy: 2)
    }

    func testTheSecondAskHitsTheCache() throws {
        let size = CGSize(width: 400, height: 400 * RainStorm.cloudAspect)
        let image = try XCTUnwrap(RainStorm.cloudImage(index: 0, size: size, scale: 2))
        XCTAssertTrue(RainStorm.cloudImage(index: 0, size: size, scale: 2) === image, "second ask must hit the cache")
    }

    /// A cartoon teardrop: taller than wide but nowhere near a streak, its
    /// sprite the aspect every drop is laid out at (or the layer squashes it),
    /// and transparent in the top corners — the pointed end, not a box.
    func testADropIsACartoonTeardrop() throws {
        let sprite = try XCTUnwrap(RainStorm.dropImage(scale: 2))
        let aspect = CGFloat(sprite.height) / CGFloat(sprite.width)
        XCTAssertGreaterThan(aspect, 1.2)
        XCTAssertLessThan(aspect, 2.2, "that is a streak, not a drop")
        let drop = RainStorm.drop(in: bounds, lineY: RainStorm.rainLineY(in: bounds), depth: 0.5, atX: 100)
        XCTAssertEqual(drop.size.height / drop.size.width, aspect, accuracy: 0.05)
        let w = sprite.width, h = sprite.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(sprite, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Memory row 0 is the TOP of the image: the tip's corners are empty,
        // the middle of the bulb is not.
        XCTAssertEqual(px[3], 0, "top-left corner should be clear")
        XCTAssertEqual(px[(w - 1) * 4 + 3], 0, "top-right corner should be clear")
        let mid = ((h * 3 / 4) * w + w / 2) * 4
        XCTAssertEqual(px[mid + 3], 255, "the bulb should be solid")
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

    /// A shower, not a blue wall, and the spawner must be able to deliver it
    /// in whole drops per tick.
    func testTheShowerIsRainButNotAWall() {
        XCTAssertGreaterThan(RainStorm.dropsPerSecond, 30)
        XCTAssertLessThan(RainStorm.dropsPerSecond, 150, "cartoon drops this thick are a wall")
        XCTAssertGreaterThan(RainStorm.dropsPerSecond / RainStorm.dropSpawnHz, 2,
                             "fewer than a couple of drops a tick and the rain arrives in visible pulses")
        XCTAssertGreaterThanOrEqual(RainStorm.dropSpawnHz, 20, "the spawn tick would be visible as a stutter")
    }

    // MARK: - Fluffy, not menacing

    /// Victor, 2026-11-20: *"make the clouds fluffy… fun and joyful, not dark
    /// and evil"*. The clouds before this were photographs graded to
    /// storm-grey. This holds the brightness, so a later "make it more stormy"
    /// pass has to come and change a number here on purpose. It also leaves
    /// `storm-clouds.png` (the band and its drops over a dark editor and a white slide) in `$TMPDIR`.
    func testTheCloudsAreBrightWhiteAndPastelNotGrey() throws {
        var sumR = 0.0, sumG = 0.0, sumB = 0.0, weight = 0.0
        for i in 0..<RainStorm.cloudCount {
            let size = CGSize(width: 400, height: 400 * RainStorm.cloudAspect)
            let image = try XCTUnwrap(RainStorm.drawnCloud(index: i, size: size, scale: 1))
            let w = image.width, h = image.height
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = try XCTUnwrap(CGContext(data: &px, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            for p in stride(from: 0, to: px.count, by: 4) where px[p + 3] > 250 {
                let a = Double(px[p + 3])
                sumR += Double(px[p]) / a; sumG += Double(px[p + 1]) / a; sumB += Double(px[p + 2]) / a
                weight += 1
            }
        }
        XCTAssertGreaterThan(weight, 0)
        let r = sumR / weight, g = sumG / weight, b = sumB / weight
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        XCTAssertGreaterThan(luma, 0.85, "a cloud this dim is a storm cloud again")
        XCTAssertGreaterThanOrEqual(b, r, "the shade is sky-blue; warmer than that reads as smog")
        try writeBandPreview()
    }

    private func writeBandPreview() throws {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let ctx = try XCTUnwrap(CGContext(data: nil, width: Int(screen.width), height: Int(screen.height),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Left half a dark editor, right half a white slide: both must read.
        ctx.setFillColor(CGColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: screen.midX, height: screen.height))
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1))
        ctx.fill(CGRect(x: screen.midX, y: 0, width: screen.midX, height: screen.height))
        if let sprite = RainStorm.dropImage(scale: 1) {
            for _ in 0..<70 {
                let d = RainStorm.randomDrop(in: screen)
                let t = CGFloat.random(in: 0...1)
                let c = CGPoint(x: d.start.x + (d.end.x - d.start.x) * t, y: d.start.y + (d.end.y - d.start.y) * t)
                ctx.saveGState()
                ctx.translateBy(x: c.x, y: c.y)
                ctx.rotate(by: -d.angle)
                ctx.setAlpha(CGFloat(d.opacity))
                ctx.draw(sprite, in: CGRect(x: -d.size.width / 2, y: -d.size.height / 2,
                                            width: d.size.width, height: d.size.height))
                ctx.restoreGState()
            }
        }
        // Clouds over the drops, as in the app: every drop comes out of one.
        for (i, a) in RainStorm.arrivals(in: screen).enumerated() {
            guard let img = RainStorm.cloudImage(index: i, size: a.rest.size, scale: 1) else { continue }
            let pad = a.rest.width * RainStorm.spritePadding
            ctx.draw(img, in: a.rest.insetBy(dx: -pad, dy: -pad))
        }
        let out = try XCTUnwrap(ctx.makeImage())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("storm-clouds.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, out, nil)
        CGImageDestinationFinalize(dest)
    }
}
