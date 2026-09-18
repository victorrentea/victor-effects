import XCTest
import ImageIO
import QuartzCore
@testable import VictorEffects

final class EmojiAnimatorTests: XCTestCase {
    // NOTE: `testMonitorEmojiUsesBreakingGlassSound` and `testHeartEmojiHasNoSoundEffect`
    // were removed — they referenced `EmojiAnimator.soundEffect(for:)`, which no longer
    // exists (the emoji→sound mapping was refactored into the show* effect methods,
    // which now play "90_breaking-glass.mp3" directly). The stale references broke
    // compilation of the whole test target on master.

    // MARK: - 🐘 Elephant in the room (⌘⌃O)

    func testElephantStandsOnTheBottomEdgeOfTheLeftHalf() {
        let bounds = CGRect(x: 0, y: 0, width: 1920, height: 1200)
        let frame = EmojiAnimator.elephantFrame(in: bounds, aspect: 1082.0 / 881.0)

        // Never crosses the middle: the right half is where the thing being
        // talked about lives.
        XCTAssertLessThanOrEqual(frame.maxX, bounds.midX)
        // Left edge and bottom edge, one margin off each.
        XCTAssertEqual(frame.minX, bounds.width * 0.015, accuracy: 0.01)
        XCTAssertEqual(frame.minY, bounds.width * 0.015, accuracy: 0.01)
        XCTAssertEqual(frame.width / frame.height, 1082.0 / 881.0, accuracy: 0.001)
    }

    func testElephantIsHeightCappedOnAScreenTooShortForHalfItsWidth() {
        // A wide, short screen: half the width would be taller than the screen,
        // and an elephant cropped at the knees is only ever seen on the projector.
        let bounds = CGRect(x: 0, y: 0, width: 3840, height: 1080)
        let aspect: CGFloat = 1082.0 / 881.0
        let frame = EmojiAnimator.elephantFrame(in: bounds, aspect: aspect)

        XCTAssertEqual(frame.height, bounds.height * 0.62, accuracy: 0.01)
        XCTAssertEqual(frame.width / frame.height, aspect, accuracy: 0.001)
        XCTAssertLessThan(frame.maxY, bounds.height)
    }

    /// The point of the picture is that it has no background of its own — a
    /// white rectangle on the desktop reads as "an image opened", not as an
    /// elephant standing in the room. Guards a future re-export from losing it.
    func testElephantShipsCutOutWithAnAlphaChannel() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "elephant.png", withExtension: nil, subdirectory: "Resources"))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertNotEqual(image.alphaInfo, .none)
        XCTAssertNotEqual(image.alphaInfo, .noneSkipFirst)
        XCTAssertNotEqual(image.alphaInfo, .noneSkipLast)
        // Cropped to the animal itself, so the frame it is placed in is the
        // elephant and not a transparent border around one.
        XCTAssertGreaterThan(image.width, 500)
        XCTAssertGreaterThan(image.height, 500)
    }

    /// The broken-glass sound is one of the 99 soundboard files, which are NOT
    /// in this repo — they live in the folder `EffectsConfig.soundsDir` names.
    /// So the assertion is about resolution, not about shipping: if this machine
    /// has a sounds folder configured, the app must be able to find the file in
    /// it. With no folder there is nothing to assert, and a red test for a
    /// missing private asset would be noise on every fresh clone.
    func testBreakingGlassResolvesFromTheConfiguredSoundsDir() throws {
        try XCTSkipUnless(EffectsConfig.shared.soundsDirExists,
                          "no soundsDir configured on this machine")
        XCTAssertNotNil(SoundManager.shared.soundURL(for: "90_breaking-glass.mp3"))
    }

    func testNukeLockedReticleGrowsAndRotatesSlowlyUntilStrike() {
        let animations = EmojiAnimator.makeBombReticleLockAnimations(remaining: 0.75)

        let grow = animations.grow
        XCTAssertEqual(grow.keyPath, "transform.scale")
        XCTAssertEqual(grow.fromValue as? Double, 1.0)
        XCTAssertEqual(grow.toValue as? Double, 2.2)
        XCTAssertEqual(grow.duration, 0.75, accuracy: 0.001)

        let rotate = animations.rotate
        XCTAssertEqual(rotate.keyPath, "transform.rotation.z")
        XCTAssertEqual(rotate.fromValue as? Double, 0.0)
        XCTAssertEqual(rotate.toValue as? Double ?? 0, EmojiAnimator.bombReticleRotationSpeed * 0.75, accuracy: 0.001)
        XCTAssertEqual(rotate.duration, grow.duration, accuracy: 0.001)
        XCTAssertEqual(rotate.timingFunction, CAMediaTimingFunction(name: .linear))
        XCTAssertEqual(rotate.fillMode, CAMediaTimingFillMode.forwards)
        XCTAssertFalse(rotate.isRemovedOnCompletion)
    }

    /// Every planted target must sit under EVERY blast, not just the one that
    /// lands on it: targets clicked on top of each other still each get a bomb,
    /// and a ring drawn over a neighbour's fireball is the artefact that shows.
    /// Sibling layers sort by zPosition, so one comparison covers all pairings.
    func testBombBlastsAlwaysRenderAboveEveryPlantedReticle() {
        XCTAssertGreaterThan(EmojiAnimator.bombBlastZ, EmojiAnimator.bombReticleZ)
    }

    /// The planted target turns counter-clockwise (trigonometric) while its fuse
    /// runs down — positive rotation.z in the host layer's y-up space.
    func testBombReticleTurnsCounterClockwise() {
        XCTAssertGreaterThan(EmojiAnimator.bombReticleRotationSpeed, 0)
    }

    func testBombReticleUsesThreeFilledTrianglesOnCircle() {
        let layer = EmojiAnimator.makeBombReticleLayer()
        let shapes = layer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
        let stroked = shapes.filter { $0.strokeColor != nil }
        let filled = shapes.filter { ($0.fillColor?.alpha ?? 0) > 0 }

        XCTAssertEqual(layer.bounds.width, 180, accuracy: 0.001)
        XCTAssertEqual(layer.bounds.height, 180, accuracy: 0.001)
        XCTAssertEqual(stroked.count, 3)
        XCTAssertEqual(filled.count, 3)
    }

    func testBombReticleRingIsThinSegmentedAndTriangleCentersSitOnCirclePointingInward() {
        let layer = EmojiAnimator.makeBombReticleLayer()
        let shapes = layer.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
        let ringSegments = shapes.filter { $0.strokeColor != nil }
        let triangles = shapes.filter { ($0.fillColor?.alpha ?? 0) > 0 }
        let center = CGPoint(x: layer.bounds.midX, y: layer.bounds.midY)

        XCTAssertEqual(ringSegments.count, 3)
        XCTAssertTrue(ringSegments.allSatisfy { abs($0.lineWidth - 3.85) < 0.001 })
        XCTAssertEqual(triangles.count, 3)
        for triangle in triangles {
            let points = triangle.path?.testPoints() ?? []
            XCTAssertEqual(points.count, 3)
            let centroid = CGPoint(
                x: points.map(\.x).reduce(0, +) / 3,
                y: points.map(\.y).reduce(0, +) / 3
            )
            let distances = points.map { hypot($0.x - center.x, $0.y - center.y) }
            XCTAssertEqual(hypot(centroid.x - center.x, centroid.y - center.y), 54, accuracy: 0.001)
            XCTAssertEqual((distances.max() ?? 0) - (distances.min() ?? 0), 28.834, accuracy: 0.001)
            XCTAssertEqual(distances.min() ?? 0, distances[0], accuracy: 0.001, "the triangle tip should point inward")
        }
    }

    func testBombReticleIsGrayWhenAimingAndRedWhenLocked() {
        let aiming = EmojiAnimator.makeBombReticleLayer()
        let locked = EmojiAnimator.makeBombReticleLayer(armed: true)
        let aimingRing = aiming.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.strokeColor != nil }
        let lockedRing = locked.sublayers?.compactMap { $0 as? CAShapeLayer }.first { $0.strokeColor != nil }

        XCTAssertEqual(aimingRing?.strokeColor, NSColor.systemGray.cgColor)
        XCTAssertEqual(lockedRing?.strokeColor, NSColor.systemRed.cgColor)
    }

    func testBombStrikeContinuesRotationFromCurrentAngleDuringFade() {
        let rotate = EmojiAnimator.makeBombReticleStrikeRotateAnimation(from: -0.2, duration: 0.45)

        XCTAssertEqual(rotate.keyPath, "transform.rotation.z")
        XCTAssertEqual(rotate.fromValue as? Double ?? 0, -0.2, accuracy: 0.001)
        XCTAssertEqual(rotate.toValue as? Double ?? 0, -0.2 + EmojiAnimator.bombReticleRotationSpeed * 0.45, accuracy: 0.001)
        XCTAssertEqual(rotate.duration, 0.45, accuracy: 0.001)
        XCTAssertEqual(rotate.timingFunction, CAMediaTimingFunction(name: .linear))
        XCTAssertEqual(rotate.fillMode, CAMediaTimingFillMode.forwards)
        XCTAssertFalse(rotate.isRemovedOnCompletion)
    }

    // MARK: - ☢️ The bomb that falls into the blast

    func testFallingBombResourceIsBundled() {
        XCTAssertNotNil(Bundle.module.url(forResource: "falling-bomb.png", withExtension: nil, subdirectory: "Resources"))
    }

    /// The bug this fixes: the full-screen fireball used to start on the clip's
    /// loudest sample (~2.20 s), two thirds of a second after the ear already
    /// heard the explosion. Its first frame belongs on the blast's ONSET, and
    /// that has to survive anyone re-tuning the click deadline — which is why the
    /// assertion is written as the sum the code actually walks: wait for the
    /// deadline, then fall.
    func testFullScreenFireballStartsOnTheBlastInTheClip() {
        let fall = EmojiAnimator.explosionBlastOnset - EmojiAnimator.explosionWhistleForeground
        XCTAssertEqual(EmojiAnimator.bombAutoDropDelay + fall,
                       EmojiAnimator.explosionBlastOnset, accuracy: 0.0001)
        XCTAssertGreaterThan(fall, 0, "the big bomb needs time on screen before it lands")
    }

    /// An aimed bomb's boom copy is seeked to `bombBoomLead`, so the fuse is
    /// scored by the tail of the whistle and the copy's blast arrives with the
    /// fireball. Both facts are the same equation.
    func testAimedBoomCopyWhistlesForExactlyItsFuseThenBlasts() {
        XCTAssertEqual(EmojiAnimator.bombBoomLead + EmojiAnimator.explosionStrikeDelay,
                       EmojiAnimator.explosionBlastOnset, accuracy: 0.0001)
        XCTAssertGreaterThan(EmojiAnimator.bombBoomLead, 0,
                             "seeking before the start of the file would silence the copy")
    }

    /// Why the first aimed bomb TAKES the head clip over instead of being left
    /// uncovered under it (Victor, 2026-09-17: one bomb, two booms).
    ///
    /// The head clip only scores an aimed bomb whose fireball lands on its own
    /// blast — i.e. one planted within `bombBoomLead` of the press. But aiming
    /// stays open until `bombAutoDropDelay`, and every click in between produced
    /// a head blast with nothing under it plus the bomb's own, a beat apart. The
    /// gap is not a tuning accident: `bombAutoDropDelay` is the instant the big
    /// bomb clears the top edge and `bombBoomLead` is a property of the clip, so
    /// nothing keeps them equal and no re-tuning can close it. Hence the
    /// handover, which does not depend on either number.
    func testHeadClipCannotScoreEveryBombTheAimingWindowAllows() {
        XCTAssertGreaterThan(EmojiAnimator.bombAutoDropDelay, EmojiAnimator.bombBoomLead,
                             "if this ever failed, ducking the copy by arithmetic would suffice")
    }

    /// The big bomb crosses the top edge of the screen exactly on the deadline for
    /// aiming — "once you can see it falling it is too late to click". Stated as
    /// geometry: at the shared speed, its whole fall covers exactly the distance
    /// from the top edge down to the full-screen impact point.
    func testBigBombEntersTheScreenPreciselyAtTheAimingDeadline() {
        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let impact = EmojiAnimator.bombBlastImpactPoint(in: bounds, fullScreen: true, at: .zero)
        let fall = EmojiAnimator.explosionBlastOnset - EmojiAnimator.explosionWhistleForeground
        let start = impact.y + CGFloat(fall) * EmojiAnimator.bombFallSpeed(in: bounds)

        XCTAssertEqual(start, bounds.maxY, accuracy: 0.001)
        XCTAssertEqual(impact.x, bounds.midX, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.bombAutoDropDelay, EmojiAnimator.explosionWhistleForeground, accuracy: 0.0001)
    }

    /// One speed for the whole raid, so a target high on the screen has less
    /// screen to fall through and its bomb appears LATER — Victor's "va intra în
    /// ecran mai târziu la unele mai spre partea de sus a ecranului".
    func testAimedBombsShareOneSpeedSoHigherTargetsAreEnteredLater() {
        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let speed = EmojiAnimator.bombFallSpeed(in: bounds)
        let fuse = CGFloat(EmojiAnimator.explosionStrikeDelay)

        // Time from the click until the nose crosses the top edge, for a target
        // near the dock and one near the menu bar.
        func entry(atY y: CGFloat) -> CGFloat { fuse - (bounds.maxY - y) / speed }

        XCTAssertGreaterThan(entry(atY: 900), entry(atY: 150))
        XCTAssertGreaterThan(speed, 0)
        // Both still enter within their own fuse, i.e. under their own whistle —
        // a bomb that enters before its click would be a bomb from nowhere.
        XCTAssertGreaterThanOrEqual(entry(atY: 150), 0)
        XCTAssertLessThanOrEqual(entry(atY: 900), fuse)
    }

    /// "Bomba e mare pt explozia full screen și proporțional mai mică pt
    /// exploziile țintite": each bomb is a fraction of the blast it belongs to, so
    /// the two sizes can never drift apart — with one deliberate exception below.
    func testBombIsSizedInProportionToItsOwnBlast() {
        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let big = EmojiAnimator.bombBlastFrame(in: bounds, fullScreen: true, at: .zero).width
        let small = EmojiAnimator.bombBlastFrame(in: bounds, fullScreen: false, at: CGPoint(x: 800, y: 500)).width

        XCTAssertEqual(big / small, EmojiAnimator.aimedScaleDivisor, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.fallingBombHeight(forBlast: small, fullScreen: false),
                       small * EmojiAnimator.fallingBombHeightPerBlast, accuracy: 0.001)
    }

    /// The exception, asked for by name: the full-screen bomb is kept BELOW
    /// proportional, because at that scale a proportional bomb fills a quarter of
    /// the screen for the whole fall and reads as an object being lowered rather
    /// than one arriving from very far away. It is still comfortably the bigger of
    /// the two — halving it must not overshoot into "smaller than the aimed ones".
    func testFullScreenBombIsHeldBelowProportionalButStillTheBiggerOne() {
        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let big = EmojiAnimator.bombBlastFrame(in: bounds, fullScreen: true, at: .zero).width
        let small = EmojiAnimator.bombBlastFrame(in: bounds, fullScreen: false, at: CGPoint(x: 800, y: 500)).width

        let bigBomb = EmojiAnimator.fallingBombHeight(forBlast: big, fullScreen: true)
        let smallBomb = EmojiAnimator.fallingBombHeight(forBlast: small, fullScreen: false)

        XCTAssertEqual(bigBomb, big * EmojiAnimator.fallingBombHeightPerBlast * 0.5, accuracy: 0.001)
        XCTAssertEqual(bigBomb / smallBomb, EmojiAnimator.aimedScaleDivisor / 2, accuracy: 0.001)
        XCTAssertGreaterThan(bigBomb, smallBomb)
        XCTAssertLessThan(bigBomb, bounds.height * 0.15, "a falling bomb should not dominate the screen")
    }

    /// An aimed blast is placed around its impact point, so the bomb's nose and
    /// the fireball's centre of impact are the same pixel.
    func testAimedBlastIsAnchoredOnTheImpactPointTheBombFallsTo() {
        let bounds = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let target = CGPoint(x: 800, y: 500)
        let frame = EmojiAnimator.bombBlastFrame(in: bounds, fullScreen: false, at: target)

        XCTAssertEqual(frame.midX, target.x, accuracy: 0.001)
        XCTAssertEqual(frame.minY + frame.height * EmojiAnimator.bombImpactFractionFromBottom, target.y, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.bombBlastImpactPoint(in: bounds, fullScreen: false, at: target), target)
    }

    /// The bomb in the air is above every crosshair (it is what they are waiting
    /// for) and below every fireball (it is consumed by its own).
    func testFallingBombLayersBetweenCrosshairsAndFireballs() {
        XCTAssertGreaterThan(EmojiAnimator.bombFallingZ, EmojiAnimator.bombReticleZ)
        XCTAssertLessThan(EmojiAnimator.bombFallingZ, EmojiAnimator.bombBlastZ)
    }

    /// There is no aiming beat: the gun is drawn mid-burst, so the moment it is
    /// on screen the bullets have to be flying and the noise sounding (Victor,
    /// 2026-09-17 — it was 0.5 s, then 1.0 s of gun-only silence). The same
    /// number delays the routed clip, which is why reticle, first hole and first
    /// frame of noise coincide however it is set.
    func testMinigunFiresTheInstantTheGunAppears() {
        XCTAssertEqual(EmojiAnimator.minigunAimLeadIn, 0, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.minigunBulletHoleScale, 0.7, accuracy: 0.001)
    }

    /// The weapon is deliberately a left-side emplacement, not a rotating FPS
    /// view-model: its rest pose is W/4 and half-speed tracking keeps its entire
    /// horizontal travel in the left half.
    func testMinigunGunRestsAtOneQuarterAndStaysInTheLeftHalf() {
        let width: CGFloat = 1600

        XCTAssertEqual(EmojiAnimator.minigunBodyX(forMouseX: 0, inWidth: width),
                       0, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.minigunBodyX(forMouseX: width / 2, inWidth: width),
                       width * 0.25, accuracy: 0.001)
        XCTAssertEqual(EmojiAnimator.minigunBodyX(forMouseX: width, inWidth: width),
                       width * 0.5, accuracy: 0.001)

        // Half travel, measured between two cursor positions.
        let near = EmojiAnimator.minigunBodyX(forMouseX: 300, inWidth: width)
        let far = EmojiAnimator.minigunBodyX(forMouseX: 700, inWidth: width)
        XCTAssertEqual(far - near, 200, accuracy: 0.001)

        for mouseX in stride(from: CGFloat(0), through: width, by: 50) {
            let bodyX = EmojiAnimator.minigunBodyX(forMouseX: mouseX, inWidth: width)
            XCTAssertLessThanOrEqual(bodyX, width / 2 + 0.001)
        }
    }

    /// Holding an FPS crosshair still does not stop aiming. The reticle remains
    /// the shot target for the whole burst; only an off-screen pointer falls back
    /// to the effect's unaimed full-screen spray.
    func testMinigunShotTargetIsTheOnScreenReticleWithoutAMovementTimeout() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let reticle = CGPoint(x: 1180, y: 620)

        XCTAssertEqual(EmojiAnimator.minigunShotTarget(forMouse: reticle, in: bounds), reticle)
        XCTAssertNil(EmojiAnimator.minigunShotTarget(forMouse: CGPoint(x: 1700, y: 620), in: bounds))
    }

    /// The 🔥 Phoenix asset must bundle into the app AND decode as the full
    /// 28-frame transparent animation the effect loops — this calls the exact
    /// `CGImageSource` loader `showPhoenix()` uses, so we catch a missing,
    /// corrupt, or flattened asset headlessly (no on-screen firing). The art is
    /// cropped tight to the flame's changing-pixel bounding box (226×350).
    func testPhoenixAssetBundlesAsTransparentMultiFrame() {
        let frames = EmojiAnimator.loadPhoenixFrames()
        XCTAssertEqual(frames.count, 28, "phoenix.png should decode to 28 frames")
        let first = frames.first
        XCTAssertEqual(first?.width, 226)
        XCTAssertEqual(first?.height, 340)
        // Transparent (luminance-keyed) frames carry an alpha channel — not opaque.
        XCTAssertNotEqual(first?.alphaInfo, CGImageAlphaInfo.none)
    }

    /// Regression guard for the lingering-white-background bug: a previous APNG
    /// build left frames 1…27 with an *opaque white* sub-rectangle (only frame 0
    /// was transparent), so the rising flame dragged a white box behind it. Every
    /// frame's four corners must now be fully transparent.
    func testPhoenixEveryFrameHasTransparentCorners() {
        let frames = EmojiAnimator.loadPhoenixFrames()
        XCTAssertEqual(frames.count, 28)
        for (i, cg) in frames.enumerated() {
            let w = cg.width, h = cg.height
            // Buffer starts fully transparent (0); drawing source-over keeps the
            // source's own alpha — so a transparent background reads back as 0.
            var px = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: &px, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                XCTFail("ctx for frame \(i)"); return
            }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
            for (x, y) in corners {
                let a = px[(y * w + x) * 4 + 3]   // alpha byte (premultipliedLast)
                XCTAssertEqual(a, 0, "frame \(i) corner (\(x),\(y)) not transparent (alpha=\(a))")
            }
            // Sanity: the flame itself IS present/opaque somewhere — guards the
            // corner check from passing vacuously (e.g. if the draw drew nothing).
            let maxAlpha = stride(from: 3, to: px.count, by: 4).map { px[$0] }.max() ?? 0
            XCTAssertGreaterThan(maxAlpha, 200, "frame \(i) has no opaque flame pixels")
        }
    }

    // MARK: - Per-participant emoji glow

    func testGlowColorParsesHex() {
        let c = EmojiAnimator.nsColor(fromHex: "#36e264")?.usingColorSpace(.sRGB)
        XCTAssertNotNil(c)
        XCTAssertEqual(c!.redComponent,   CGFloat(0x36) / 255, accuracy: 0.005)
        XCTAssertEqual(c!.greenComponent, CGFloat(0xe2) / 255, accuracy: 0.005)
        XCTAssertEqual(c!.blueComponent,  CGFloat(0x64) / 255, accuracy: 0.005)
        // Accepts a bare (no-#) form; rejects malformed input.
        XCTAssertNotNil(EmojiAnimator.nsColor(fromHex: "36e264"))
        XCTAssertNil(EmojiAnimator.nsColor(fromHex: "nope"))
        XCTAssertNil(EmojiAnimator.nsColor(fromHex: "#12"))
    }

    func testSpawnEmojiAppliesParticipantGlowHalo() {
        let host = CALayer()
        let animator = EmojiAnimator(hostLayer: host)
        animator.spawnEmoji("❤️", glow: "#36e264")
        guard let layer = host.sublayers?.last else { XCTFail("no emoji layer added"); return }
        XCTAssertGreaterThan(layer.shadowOpacity, 0, "glow should set a visible shadow")
        XCTAssertEqual(layer.shadowColor, EmojiAnimator.nsColor(fromHex: "#36e264")?.cgColor)
    }

    // MARK: - 🔥 The match that strikes the fires (2026-09-18, bare since 09-19)

    /// The head is the layer's anchor, so it is the pixel that rides the
    /// pointer — and it is the pixel a click strikes a fire on. If this drifts,
    /// the fire lands somewhere the user did not point at, which is the whole
    /// gesture. Near the top-left because the stick hangs down-RIGHT, where a
    /// right hand holds it.
    func testMatchHeadIsTheAnchorAtTheTopLeft() {
        let (size, head) = EmojiAnimator.matchGeometry(length: 600)
        XCTAssertTrue(size.width > 0 && size.height > 0, "the match has to have a box")
        XCTAssertTrue((0...1).contains(head.x) && (0...1).contains(head.y),
                      "the head must be INSIDE the drawing, or the anchor is off the layer")
        XCTAssertLessThan(head.x, 0.25, "the head sits at the left edge; the stick runs right")
        XCTAssertGreaterThan(head.y, 0.80, "the head sits at the top; the stick hangs down")
    }

    /// The tilt is 32° from vertical — a hand holding a match up. Flatter and it
    /// reads as a cigarette, so the box must stay taller than it is wide.
    func testMatchHangsMoreDownThanSideways() {
        let (size, _) = EmojiAnimator.matchGeometry(length: 600)
        XCTAssertGreaterThan(size.height, size.width,
                             "a match tilted past 45° stops reading as held up")
    }

    /// One flame width in, one proportional match out — the whole drawing
    /// scales, so the single call the pointer makes (`forFlameWidth:` the
    /// DEFAULT flame width, since 2026-09-19 the wheel belongs to the fire on
    /// the ground rather than to the match) lands on exactly the proportion a
    /// default-sized fire was held at. A stick that scaled on one axis only is
    /// the proportion breaking in front of the room.
    func testMatchScalesWithTheFlame() {
        let small = EmojiAnimator.matchBounds(forFlameWidth: 280)
        let big = EmojiAnimator.matchBounds(forFlameWidth: 560)
        XCTAssertEqual(big.width, small.width * 2, accuracy: 0.001)
        XCTAssertEqual(big.height, small.height * 2, accuracy: 0.001)
        XCTAssertEqual(small.height / small.width, big.height / big.width, accuracy: 0.001,
                       "the drawing's aspect has to survive the resize")
    }

    /// The stick is 0.75 × the flame's width. At the default 280 pt flame that
    /// is a 210 pt match under a ~467 pt flame — held up under it, rather than a
    /// twig lost beneath a bonfire.
    func testMatchLengthIsThreeQuartersOfTheFlameWidth() {
        let box = EmojiAnimator.matchBounds(forFlameWidth: 280)
        // The box is the stick's own bounding box plus a margin on each side, so
        // its diagonal is at least the stick's length and not much more.
        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        XCTAssertGreaterThan(diagonal, 280 * 0.75)
        XCTAssertLessThan(diagonal, 280 * 0.75 * 1.35)
    }

    func testSpawnEmojiWithoutGlowHasNoHalo() {
        let host = CALayer()
        let animator = EmojiAnimator(hostLayer: host)
        animator.spawnEmoji("❤️")   // no glow → unchanged look
        guard let layer = host.sublayers?.last else { XCTFail("no emoji layer added"); return }
        XCTAssertEqual(layer.shadowOpacity, 0, "no glow should leave the default (0) shadow opacity")
    }
}

private extension CGPath {
    func testPoints() -> [CGPoint] {
        var points: [CGPoint] = []
        applyWithBlock { element in
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint:
                points.append(element.pointee.points[0])
            default:
                break
            }
        }
        return points
    }
}
