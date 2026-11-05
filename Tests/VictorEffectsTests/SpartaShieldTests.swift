import QuartzCore
import XCTest
@testable import VictorEffects

/// 🛡️ Every way this effect can go wrong in front of a room is a number in
/// `SpartaShield`: a shield during "Madness?", a blow beside its word, a picture
/// outliving its clip.
final class SpartaShieldTests: XCTestCase {
    typealias S = SpartaShield
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)

    /// Victor: *"când zice madness nu apare nimic"*.
    func testNothingIsOnTheGlassBeforeTheWords() {
        for t in stride(from: 0.0, through: 3.42, by: 0.01) {
            XCTAssertEqual(S.shieldAlpha(t), 0, "shield at \(t)")
            XCTAssertEqual(S.bed(t), 0, "bed at \(t)")
            XCTAssertEqual(S.sun(t), 0, "sun at \(t)")
            XCTAssertEqual(S.shake(t, width: 1728), .zero, "shake at \(t)")
        }
    }

    /// A fade, but one the room still reads as landing on the word.
    func testTheShieldFadesInOverThis() {
        XCTAssertLessThan(S.fadeIn.lowerBound, S.thisBeat)
        XCTAssertGreaterThan(S.fadeIn.upperBound, S.thisBeat)
        XCTAssertGreaterThan(S.shieldAlpha(S.thisBeat), 0.5)
        XCTAssertEqual(S.shieldAlpha(S.fadeIn.upperBound), 1)
    }

    func testTheSunWaitsForSparta() {
        XCTAssertEqual(S.sun(S.spartaBeat), 0)
        XCTAssertGreaterThan(S.sun(S.vowelPeak), 0.8)
        XCTAssertGreaterThan(S.sun(S.impact + 0.01), S.sun(S.impact - 0.01), "the impact flares it")
        let highest = stride(from: 3.0, to: 9.6, by: 0.01).map(S.sun).max() ?? 0
        XCTAssertLessThanOrEqual(highest, S.sunPeak, "the sprites are baked for this peak")
    }

    func testEachBlowHitsOnItsWord() {
        for beat in [S.isBeat, S.impact] {
            XCTAssertGreaterThan(S.shieldScale(beat), S.shieldScale(beat - 0.02) + 0.02, "kick at \(beat)")
        }
        XCTAssertEqual(S.rings.map(\.t0), [S.thisBeat, S.isBeat, S.spartaBeat, S.impact])
    }

    /// The self-termination rule: nothing depends on a stop arriving.
    func testItIsAllOverBeforeTheClipIs() {
        XCTAssertLessThan(S.lastVisible, S.fallbackDuration)
        for t in stride(from: S.lastVisible, through: 12, by: 0.1) {
            XCTAssertEqual(S.shieldAlpha(t), 0)
            XCTAssertEqual(S.bed(t), 0)
            XCTAssertEqual(S.sun(t), 0)
            XCTAssertEqual(S.shake(t, width: 1728), .zero)
            XCTAssertEqual(S.zoomPunch(t), 1)
        }
        for ring in S.rings { XCTAssertLessThan(ring.t0 + ring.seconds, S.lastVisible) }
    }

    /// Outside these the desktop is live; inside them it has to be free to move.
    func testThePhotographIsThereForEveryShake() {
        for t in stride(from: 3.0, to: 9.6, by: 0.005) where S.shake(t, width: 1728) != .zero {
            XCTAssertTrue(S.shakeWindows.contains { $0.contains(t) }, "unphotographed shake at \(t)")
        }
        XCTAssertLessThan(S.captureAt, S.firstVisible, "the picture must not hold the shield")
    }

    func testTheShakeRestsOnTheDesktop() {
        XCTAssertLessThan(abs(S.shake(S.impact + 0.6, width: 1728).x), 0.001)
        XCTAssertEqual(S.zoomPunch(S.impact + 0.5), 1)
    }

    /// The rings keep the proportion of their bitmap for life, so one scale is enough.
    func testTheRingStaysTheShapeItWasBaked() {
        for ring in S.rings {
            let early = S.ringShape(ring, u: 0.05, bounds: screen)
            let late = S.ringShape(ring, u: 0.95, bounds: screen)
            XCTAssertGreaterThan(late.crest, early.crest)
            XCTAssertGreaterThan(S.ringAlpha(ring, u: 0), S.ringAlpha(ring, u: 0.9))
            XCTAssertEqual(S.ringAlpha(ring, u: 1), 0)
        }
        XCTAssertEqual(S.ringThickness, 8.5, "Victor's")
        XCTAssertEqual(S.ringOpacity, 0.7, "Victor's")
    }

    /// The same rays Victor picked in the prototype: values from the JS generator.
    func testTheRaysAreTheApprovedOnes() {
        XCTAssertEqual(S.seeded(11), 0.19148686644621193, accuracy: 1e-12)
        XCTAssertEqual(S.seeded(77), 0.37791110528633, accuracy: 1e-12)
        XCTAssertEqual(S.seeded(911), 0.3290146724320948, accuracy: 1e-12)
        XCTAssertEqual(S.seeded(1000), 0.3640799643471837, accuracy: 1e-12)
        XCTAssertEqual(S.rays(of: S.fans[0], reach: 100).count, 14)
        XCTAssertEqual(S.rays(of: S.fans[1], reach: 100).count, 22)
    }

    func testEverythingBakes() throws {
        let sprites = try XCTUnwrap(S.bake(bounds: screen, scale: 2))
        XCTAssertEqual(sprites.fans.count, S.fans.count * S.fanHalves)
        XCTAssertEqual(sprites.rings.count, S.rings.count)
    }

    /// Victor saw the ring before the shield: rings start at their brightest, and a
    /// fill backwards put them on the glass from the press, over "Madness?". With
    /// every layer at opacity 0 and no fill backwards, nothing can show early.
    func testNoLayerIsHeldOnTheGlassBeforeItsTurn() throws {
        let sprites = try XCTUnwrap(S.bake(bounds: screen, scale: 1))
        let container = CALayer()
        S.build(in: container, bounds: screen, begin: 100, sprites: sprites)
        S.addDesktop(sprites.flash, to: container, bounds: screen, begin: 100)

        func walk(_ layer: CALayer) {
            for key in layer.animationKeys() ?? [] {
                let a = layer.animation(forKey: key)
                XCTAssertEqual(a?.fillMode, .forwards, "\(key) reaches back before its start")
                XCTAssertGreaterThanOrEqual((a?.beginTime ?? 0) - 100, S.firstVisible - 0.02, "\(key) starts early")
            }
            layer.sublayers?.forEach(walk)
        }
        walk(container)
        let shown = (container.sublayers ?? []).filter { $0.opacity != 0 }
        XCTAssertTrue(shown.isEmpty, "a top layer is visible with no animation running")
        let inShield = container.sublayers?.last?.sublayers?.filter { $0.opacity != 0 } ?? []
        XCTAssertEqual(inShield.count, 2, "only the shadow and the face, and their holder is at 0")
    }

    func testBuildingLaysTheShieldOverTheSun() throws {
        let sprites = try XCTUnwrap(S.bake(bounds: screen, scale: 1))
        let container = CALayer()
        S.build(in: container, bounds: screen, begin: 100, sprites: sprites)
        let layers = try XCTUnwrap(container.sublayers)
        XCTAssertEqual(layers.count, 1 + 4 + 1 + 4 + 1, "bed, fans, corona, rings, shield")
        XCTAssertEqual(layers.last?.sublayers?.count, 8, "shadow, face, band, 2 blows, Λ, rim, flash")
        XCTAssertEqual(layers.first?.opacity, 0, "nothing shows until its keyframes say so")
    }
}
