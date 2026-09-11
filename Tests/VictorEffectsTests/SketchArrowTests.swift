import XCTest
import QuartzCore
@testable import VictorEffects

/// 🔁 The replay arrow is built by pure functions over a normalised glyph, so
/// the things that decide whether it still looks like tile #71's artwork — the
/// direction of the sweep, where the point looks, how much of the screen it
/// fills, whether it is centred — are all checkable without a screen.
final class SketchArrowTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    // MARK: - The silhouette

    /// The ring is drawn tail → head **the long way round**, through the bottom
    /// of the screen: a 294° sweep with the gap at the top. Sweeping the short
    /// way would be a 66° comma with an arrowhead on it.
    func testRingSweepsTheLongWayRoundAndLeavesTheGapAtTheTop() {
        let pts = SketchArrow.ringPoints(seed: 1, wobble: 0, samples: 360)

        let first = atan2(pts[0].y, pts[0].x)
        let last = atan2(pts[pts.count - 1].y, pts[pts.count - 1].x)
        XCTAssertEqual(first, SketchArrow.tailAngle, accuracy: 0.001)
        XCTAssertEqual(last, SketchArrow.headAngle, accuracy: 0.001)

        // Bottom of the ring reached: the sweep really goes round, it does not
        // cut across the gap.
        XCTAssertLessThan(pts.map(\.y).min() ?? 0, -0.99)
        // …and nothing is drawn in the gap between head and tail.
        let gapAngles = pts.map { atan2($0.y, $0.x) }
            .filter { $0 > SketchArrow.tailAngle + 0.02 && $0 < SketchArrow.headAngle - 0.02 }
        XCTAssertTrue(gapAngles.isEmpty)
    }

    /// With no wobble the ring is a circle of radius exactly 1 — the wobble is
    /// the only thing allowed to move it, so a bug in the sampling shows here
    /// rather than as "it looks a bit off".
    func testUnwobbledRingIsAUnitCircle() {
        for p in SketchArrow.ringPoints(seed: 3, wobble: 0, samples: 120) {
            XCTAssertEqual(sqrt(p.x * p.x + p.y * p.y), 1, accuracy: 0.0001)
        }
    }

    /// The wobble stays a wobble: a pass that strayed by a third of the radius
    /// would not read as a sketched circle at all.
    func testWobbleStaysWithinItsAmplitude() {
        let amp: CGFloat = 0.052
        for p in SketchArrow.ringPoints(seed: 47, wobble: amp, samples: 400) {
            XCTAssertEqual(sqrt(p.x * p.x + p.y * p.y), 1, accuracy: amp + 0.0001)
        }
        // …and it does move: an amplitude that produced a perfect circle would
        // mean the noise had been silently zeroed.
        let radii = SketchArrow.ringPoints(seed: 47, wobble: amp, samples: 400)
            .map { sqrt($0.x * $0.x + $0.y * $0.y) }
        XCTAssertGreaterThan((radii.max() ?? 1) - (radii.min() ?? 1), amp * 0.5)
    }

    /// Both barbs start on the apex however far they stray later — a chevron
    /// whose two lines miss each other at the point is a different drawing.
    func testBothBarbsStartExactlyOnTheApex() {
        for tip in [SketchArrow.barbOuter, SketchArrow.barbInner] {
            let pts = SketchArrow.barbPoints(to: tip, seed: 5, wobble: 0.05)
            XCTAssertEqual(pts[0].x, SketchArrow.apex.x, accuracy: 0.0001)
            XCTAssertEqual(pts[0].y, SketchArrow.apex.y, accuracy: 0.0001)
            XCTAssertEqual(pts[pts.count - 1].x, tip.x, accuracy: 0.06)
            XCTAssertEqual(pts[pts.count - 1].y, tip.y, accuracy: 0.06)
        }
    }

    /// The head points up and to the right, along the ring's clockwise tangent —
    /// that is what makes the loop read as "again" rather than "undo". The point
    /// direction is the bisector of the two barbs, reversed.
    func testTheHeadLooksUpAndToTheRightAlongTheSweep() {
        func unit(_ from: CGPoint, _ to: CGPoint) -> CGPoint {
            let dx = to.x - from.x, dy = to.y - from.y
            let l = sqrt(dx * dx + dy * dy)
            return CGPoint(x: dx / l, y: dy / l)
        }
        let a = unit(SketchArrow.apex, SketchArrow.barbOuter)
        let b = unit(SketchArrow.apex, SketchArrow.barbInner)
        let point = CGPoint(x: -(a.x + b.x), y: -(a.y + b.y))
        let deg = atan2(point.y, point.x) * 180 / .pi
        XCTAssertEqual(deg, 48, accuracy: 8)

        // …and the barbs really do straddle it, at roughly a right angle.
        let included = acos(a.x * b.x + a.y * b.y) * 180 / .pi
        XCTAssertEqual(included, 91, accuracy: 6)
    }

    /// The apex sits just outside the ring's centre line but inside its outer
    /// edge, so the chevron lands ON the end of the sweep instead of floating
    /// off it or being swallowed by it.
    func testApexSitsOnTheEndOfTheRing() {
        let r = sqrt(SketchArrow.apex.x * SketchArrow.apex.x + SketchArrow.apex.y * SketchArrow.apex.y)
        XCTAssertGreaterThan(r, 1)
        XCTAssertLessThan(r, 1 + SketchArrow.strokeRatio / 2)
        let angle = atan2(SketchArrow.apex.y, SketchArrow.apex.x)
        XCTAssertEqual(angle, SketchArrow.headAngle, accuracy: 0.06)
    }

    /// The declared glyph box really contains the glyph, stroke included — it is
    /// what both the scale and the centring are computed from, so a box that
    /// lied would push part of the drawing off screen.
    func testDeclaredGlyphBoundsContainEveryStroke() {
        let half = SketchArrow.strokeRatio / 2
        var pts = SketchArrow.ringPoints(seed: 11, wobble: 0.012, samples: 400)
        pts += SketchArrow.barbPoints(to: SketchArrow.barbOuter, seed: 11, wobble: 0.012)
        pts += SketchArrow.barbPoints(to: SketchArrow.barbInner, seed: 11, wobble: 0.012)
        for p in pts {
            XCTAssertGreaterThanOrEqual(p.x + half, SketchArrow.glyphBounds.minX - 0.001)
            XCTAssertLessThanOrEqual(p.x - half, SketchArrow.glyphBounds.maxX + 0.001)
            XCTAssertGreaterThanOrEqual(p.y + half, SketchArrow.glyphBounds.minY - 0.001)
            XCTAssertLessThanOrEqual(p.y - half, SketchArrow.glyphBounds.maxY + 0.001)
        }
    }

    // MARK: - On a screen

    /// Three quarters of the screen's height, centred — the two things asked of
    /// it that a reader cannot check in the geometry above.
    func testLayerIsThreeQuartersOfTheScreenHighAndCentred() throws {
        let layer = try XCTUnwrap(SketchArrow.makeLayer(in: screen, scale: 2))
        let box = drawnBox(layer)

        XCTAssertEqual(box.height, screen.height * SketchArrow.heightFraction,
                       accuracy: screen.height * 0.04)
        XCTAssertEqual(box.midX, screen.midX, accuracy: screen.width * 0.03)
        XCTAssertEqual(box.midY, screen.midY, accuracy: screen.height * 0.03)
        XCTAssertLessThan(box.width, screen.width)
    }

    /// Nine strokes: three passes over the ring and both barbs. Every one of
    /// them unfilled — a `CAShapeLayer` fills with BLACK unless told not to, and
    /// a filled ring is an opaque disc over the desktop.
    func testEveryPassIsAnUnfilledStrokeWithItsOwnPen() throws {
        let layer = try XCTUnwrap(SketchArrow.makeLayer(in: screen, scale: 2))
        let shapes = (layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        XCTAssertEqual(shapes.count, SketchArrow.passes.count * 3)
        for shape in shapes {
            XCTAssertNil(shape.fillColor)
            XCTAssertNotNil(shape.strokeColor)
            XCTAssertNotNil(shape.path)
            XCTAssertGreaterThan(shape.lineWidth, 0)
            // The pen: strokeEnd 0 → 1 is the drawing, and the boil keeps the
            // line alive through the hold.
            XCTAssertNotNil(shape.animation(forKey: "draw"))
            XCTAssertNotNil(shape.animation(forKey: "boil"))
        }
    }

    /// Every stroke is drawn before the hold begins, and the boil never starts
    /// while a pen is still moving.
    func testAllPensAreDownAndUpInsideTheDrawWindow() throws {
        let layer = try XCTUnwrap(SketchArrow.makeLayer(in: screen, scale: 2))
        let shapes = (layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        let t0 = shapes.compactMap { $0.animation(forKey: "draw")?.beginTime }.min() ?? 0
        for shape in shapes {
            let draw = try XCTUnwrap(shape.animation(forKey: "draw"))
            let boil = try XCTUnwrap(shape.animation(forKey: "boil"))
            XCTAssertLessThanOrEqual(draw.beginTime + draw.duration - t0,
                                     SketchArrow.drawDuration + 0.001)
            XCTAssertGreaterThanOrEqual(boil.beginTime - t0,
                                        draw.beginTime + draw.duration - t0 - 0.001)
        }
    }

    /// The fade lands exactly on the deadline the caller tracks the layer for,
    /// so the removal takes away something already invisible.
    func testTheFadeEndsOnTheTrackedDeadline() throws {
        let layer = try XCTUnwrap(SketchArrow.makeLayer(in: screen, scale: 2))
        let fade = try XCTUnwrap(layer.animation(forKey: "fade"))
        let shapes = (layer.sublayers ?? []).compactMap { $0 as? CAShapeLayer }
        let t0 = shapes.compactMap { $0.animation(forKey: "draw")?.beginTime }.min() ?? 0

        XCTAssertEqual(fade.duration, SketchArrow.fadeOut, accuracy: 0.001)
        XCTAssertEqual(fade.beginTime + fade.duration - t0, SketchArrow.totalDuration, accuracy: 0.001)
        XCTAssertGreaterThan(fade.beginTime - t0, SketchArrow.drawDuration)
    }

    /// A screen with no area builds nothing rather than a degenerate path.
    func testDegenerateBoundsBuildNothing() {
        XCTAssertNil(SketchArrow.makeLayer(in: .zero, scale: 2))
        XCTAssertNil(SketchArrow.makeLayer(in: CGRect(x: 0, y: 0, width: 800, height: 0), scale: 2))
    }

    /// The wobble is a pure function of its seed: the boil cycles a fixed set of
    /// variants, and a stroke that regenerated itself differently on every build
    /// would shimmer instead of breathe.
    func testWobbleIsRepeatableForASeedAndDiffersBetweenSeeds() {
        let a = SketchArrow.ringPoints(seed: 42, wobble: 0.03, samples: 64)
        let b = SketchArrow.ringPoints(seed: 42, wobble: 0.03, samples: 64)
        let c = SketchArrow.ringPoints(seed: 43, wobble: 0.03, samples: 64)
        XCTAssertEqual(a.map(\.x), b.map(\.x))
        XCTAssertNotEqual(a.map(\.x), c.map(\.x))
    }

    // MARK: - Helper

    /// The union of every stroke's path box, inflated by half its own line
    /// width — i.e. the ink actually on the screen.
    private func drawnBox(_ layer: CALayer) -> CGRect {
        var box = CGRect.null
        for shape in (layer.sublayers ?? []).compactMap({ $0 as? CAShapeLayer }) {
            guard let path = shape.path else { continue }
            box = box.union(path.boundingBox.insetBy(dx: -shape.lineWidth / 2,
                                                     dy: -shape.lineWidth / 2))
        }
        return box
    }
}
