import AppKit
import AVFoundation
import Metal
import XCTest
@testable import VictorEffects

/// 🚽 The flush, checked without a screen, a capture or a speaker: the flow is
/// numbers in `ToiletDrain`, and the frames come off a Metal texture the renderer
/// is handed like any other.
final class ToiletDrainTests: XCTestCase {

    private let g = ToiletDrain.Geometry(width: 3456, height: 2234)
    private let everyMoment = stride(from: -0.1, through: 5.3, by: 0.01).map { $0 }

    // MARK: - Against the clip

    /// The cues are in the order of the clip, and the picture is gone inside it.
    func testTheCuesFollowTheClip() {
        XCTAssertLessThan(ToiletDrain.valve, ToiletDrain.rush)
        XCTAssertLessThan(ToiletDrain.rush, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.first?.from, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.last?.to ?? 0, ToiletDrain.drained, accuracy: 0.001)
        XCTAssertLessThan(ToiletDrain.drained, ToiletDrain.clipSeconds)
    }

    /// The calming does not fit in the 0.6 s of room tone, so it runs past the
    /// audio, knowingly: by under a second, and the show still ends itself.
    func testTheEndingRunsPastTheClipByUnderASecond() {
        XCTAssertLessThan(ToiletDrain.drained, ToiletDrain.settled)
        XCTAssertLessThan(ToiletDrain.settled, ToiletDrain.fadeEnds)
        XCTAssertGreaterThan(ToiletDrain.fadeEnds, ToiletDrain.clipSeconds)
        XCTAssertLessThan(ToiletDrain.fadeEnds - ToiletDrain.clipSeconds, 1)
        XCTAssertGreaterThan(ToiletDrain.totalSeconds, ToiletDrain.fadeEnds, "the removal must land after the last frame")
    }

    /// The clip on this machine is the one that was measured. Skipped where the
    /// tablet's assets are not.
    /// AVFoundation counts the mp3's encoder padding, ffmpeg does not: 5.12 s to
    /// its 5.08 s.
    func testTheClipIsTheOneThatWasMeasured() throws {
        let url = EffectsConfig.shared.soundsDir.appendingPathComponent("66_toilet.mp3")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no tablet assets here") }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        XCTAssertEqual(seconds, ToiletDrain.clipSeconds, accuracy: 0.05, "new recording: measure the cues in ToiletDrain again")
    }

    /// Nothing is gone before the valve, everything is the moment the clip goes
    /// quiet, and water never comes back up.
    func testTheDrainOnlyEverGoesDown() {
        XCTAssertEqual(ToiletDrain.drain(ToiletDrain.valve), 0)
        XCTAssertEqual(ToiletDrain.drain(ToiletDrain.drained), 1)
        XCTAssertEqual(ToiletDrain.drain(ToiletDrain.drained - 1e-9), 1, accuracy: 1e-6, "no jump into the last frame")
        let values = everyMoment.map(ToiletDrain.drain)
        XCTAssertEqual(values, values.sorted())
    }

    /// The picture goes down on the gulps: each takes more per second than the
    /// hiss before it did, and most of the screen is still there when the gurgle
    /// starts, or there would be nothing left to swallow.
    func testThePictureGoesDownOnTheGulps() {
        let hissRate = (ToiletDrain.drain(ToiletDrain.gurgle) - ToiletDrain.drain(ToiletDrain.rush))
            / (ToiletDrain.gurgle - ToiletDrain.rush)
        for gulp in ToiletDrain.gulps {
            let rate = (ToiletDrain.drain(gulp.to) - ToiletDrain.drain(gulp.from)) / (gulp.to - gulp.from)
            XCTAssertGreaterThan(rate, 2 * hissRate)
        }
        XCTAssertLessThan(ToiletDrain.drain(ToiletDrain.gurgle), 0.45)
    }

    // MARK: - The flow

    /// Before the valve the warp is the identity, so the photograph lands on the
    /// desktop without a seam.
    func testAtRestEveryPixelIsItself() {
        for t in [-0.1, 0, ToiletDrain.valve] {
            for (x, y) in [(100.0, 50.0), (-1500.0, 900.0), (3.0, -1.0)] {
                let p = ToiletDrain.source(of: x, y, t, g)
                XCTAssertEqual(p.x, x, accuracy: 1e-6)
                XCTAssertEqual(p.y, y, accuracy: 1e-6)
            }
        }
    }

    /// Incompressible: every ring has lost the same area. A plain zoom-out would
    /// lose area in proportion to the radius.
    func testTheSuctionConservesArea() {
        let t = 3.0
        let lost = { (r: Double) in pow(ToiletDrain.sourceRadius(r, t, self.g), 2) - r * r }
        XCTAssertGreaterThan(lost(300), 0)
        XCTAssertEqual(lost(300), lost(1500), accuracy: 1e-3)
    }

    /// Faster towards the middle, at every moment the water is moving: with no hole
    /// to look at, this is what says "drain".
    func testItTurnsFasterTowardsTheMiddle() {
        for t in [1.5, 2.5, 3.5, 4.2] {
            let radii = stride(from: g.reach, to: g.core, by: -100).map { $0 }.reversed().map { $0 }
            let speeds = radii.map { ToiletDrain.angularSpeed($0, t, g) }
            XCTAssertEqual(speeds, speeds.sorted(by: >), "at \(t) s")
            XCTAssertGreaterThan(speeds[0], 3 * speeds[speeds.count - 1], "at \(t) s")
        }
    }

    /// Grows over the clip at every radius, and even the corners go around, or the
    /// whole picture would not be seen to turn.
    func testTheSpinGrowsOverTheClip() {
        let times = stride(from: 1.0, to: ToiletDrain.gurgle, by: 0.25).map { $0 }
        for r in [g.core, 5 * g.core, g.reach] {
            let speeds = times.map { ToiletDrain.angularSpeed(r, $0, g) }
            XCTAssertEqual(speeds, speeds.sorted(), "at r = \(r)")
        }
        XCTAssertGreaterThan(ToiletDrain.spin(g.reach, ToiletDrain.drained, g), .pi)
    }

    /// The difference from a rotation: two radii turned by different angles, so
    /// straight lines have wound into a spiral.
    func testItWindsARotationWouldNot() {
        let twist = ToiletDrain.spin(0.1 * g.reach, 3, g) - ToiletDrain.spin(0.4 * g.reach, 3, g)
        XCTAssertGreaterThan(twist, 2 * .pi, "not one full turn between the two rings")
    }

    /// The spiral tightens into the middle and all the way in: each halving of the
    /// radius winds more than the one outside it, and the middle does not go flat.
    func testTheSpiralTightensIntoTheMiddle() {
        let t = 3.7
        let radii = (0..<6).map { g.reach / pow(2, Double($0)) }
        let wound = zip(radii, radii.dropFirst()).map { ToiletDrain.spin($1, t, g) - ToiletDrain.spin($0, t, g) }
        XCTAssertEqual(wound, wound.sorted(), "\(wound)")
        XCTAssertGreaterThan(wound[wound.count - 1], 3)
    }

    /// Counter-clockwise on the glass: the water right of the centre moves up, so
    /// a pixel above the centre shows what was to its right.
    func testItTurnsCounterClockwise() {
        // Soon after the valve the angle is still small enough to read.
        let t = ToiletDrain.valve + 0.1
        let p = ToiletDrain.source(of: 0, -500, t, g)
        XCTAssertGreaterThan(p.x, 0, "y is down: this pixel is above the centre")
    }

    /// The picture's edge starts at the corners and ends at a point: it goes down
    /// the middle without anything there to go down.
    func testTheShorelineClosesToAPoint() {
        XCTAssertGreaterThanOrEqual(ToiletDrain.shoreline(0, g), g.reach)
        XCTAssertEqual(ToiletDrain.shoreline(ToiletDrain.drained, g), 0)
        let edge = everyMoment.map { ToiletDrain.shoreline($0, g) }
        XCTAssertEqual(edge, edge.sorted(by: >))
    }

    // MARK: - The ending

    /// Waves on the water left behind fall from the last gulp, and "settled a
    /// little" is not flat: they are small but still moving when the fade starts.
    func testTheWavesCalmDown() {
        XCTAssertEqual(ToiletDrain.chop(ToiletDrain.drained), 1)
        let moments = stride(from: ToiletDrain.drained, through: ToiletDrain.fadeEnds, by: 0.05).map { $0 }
        let heights = moments.map(ToiletDrain.chop)
        XCTAssertEqual(heights, heights.sorted(by: >))
        XCTAssertLessThan(ToiletDrain.chop(ToiletDrain.settled), 0.25)
        XCTAssertGreaterThan(ToiletDrain.chop(ToiletDrain.settled), 0.05)
    }

    /// The whirlpool's foam is gone long before the fade: the ending is a surface
    /// settling, not a spiral dimming.
    func testTheFoamIsGoneBeforeTheWaterSettles() {
        XCTAssertEqual(ToiletDrain.foamLeft(ToiletDrain.drained), 1)
        XCTAssertLessThan(ToiletDrain.foamLeft(ToiletDrain.drained + 0.5), 0.05)
    }

    /// The ring wave starts with the last of the picture and reaches the corners
    /// while there is still water to see it on.
    func testTheRingWaveCrossesTheScreenBeforeTheFade() {
        for r in [10.0, 500, 2000] { XCTAssertEqual(ToiletDrain.ringSlope(r, ToiletDrain.drained, g), 0) }
        XCTAssertNotEqual(ToiletDrain.ringSlope(g.reach * 0.9, ToiletDrain.settled, g), 0)
        XCTAssertEqual(ToiletDrain.ringSlope(g.reach, ToiletDrain.drained + 0.1, g), 0, "it has not got there yet")
    }

    /// "At once, uniformly": the fade is one number, for every ring, at every
    /// moment, and only ever goes down.
    func testTheFadeIsTheSameEverywhere() {
        for t in stride(from: ToiletDrain.drained, through: ToiletDrain.fadeEnds + 0.1, by: 0.05) {
            let alphas = Set(rows(at: t).map(\.mix.z))
            XCTAssertEqual(alphas, [Float(ToiletDrain.fadeOut(t))], "at \(t) s")
        }
        XCTAssertEqual(ToiletDrain.fadeOut(ToiletDrain.settled), 1)
        XCTAssertEqual(ToiletDrain.fadeOut(ToiletDrain.fadeEnds), 0)
        let values = everyMoment.map(ToiletDrain.fadeOut)
        XCTAssertEqual(values, values.sorted(by: >))
    }

    // MARK: - The table

    private func rows(at t: Double, picture: Bool = true) -> [ToiletDrain.Row] {
        var rows = [ToiletDrain.Row](repeating: .init(), count: 512)
        let step = g.reach * 1.01 / 511
        rows.withUnsafeMutableBufferPointer { ToiletDrain.fill($0, step: step, t: t, geometry: g, picture: picture) }
        return rows
    }

    /// At rest the table says "the photograph, untouched" for every ring out to
    /// the corners: no water tint, no foam, no shadow, nothing of the water.
    func testTheFirstFrameIsThePhotographAndNothingElse() {
        let table = rows(at: 0)
        // The last rows of the table are past the corners, where no pixel lands.
        for row in table[0..<Int(Double(table.count - 1) / 1.01)] {
            XCTAssertEqual(row.warp.z, 1, "light")
            XCTAssertEqual(row.warp.w, 0, "tint")
            XCTAssertEqual(row.wave.x, 0, "foam")
            XCTAssertEqual(row.wave.z, 0, "ripple")
            XCTAssertEqual(row.mix.x, 1, "water cover")
            XCTAssertEqual(row.mix.y, 0, accuracy: 1e-6, "edge foam")
            XCTAssertEqual(row.mix.z, 1, "alpha")
            XCTAssertEqual(row.mix.w, 0, "ring wave")
        }
    }

    /// Nothing is darkened by ring: a dark centre would stand in for a hole.
    func testNoRingIsLitDifferently() {
        for t in stride(from: 0, through: ToiletDrain.drained, by: 0.1) {
            XCTAssertEqual(Set(rows(at: t).map(\.warp.z)).count, 1, "at \(t) s")
        }
    }

    /// With no photograph the first frame is the live desktop, and the water fades
    /// in over it rather than appearing, and leaves the same way as ever.
    func testWithNoPictureTheWaterFadesIn() {
        for row in rows(at: 0, picture: false) { XCTAssertEqual(row.mix.z, 0) }
        XCTAssertGreaterThan(rows(at: ToiletDrain.rush, picture: false)[400].mix.z, 0.8)
        for row in rows(at: ToiletDrain.fadeEnds, picture: false) { XCTAssertEqual(row.mix.z, 0) }
    }

    // MARK: - Real frames, on a texture

    private func target(_ renderer: ToiletDrainRenderer, _ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return renderer.device.makeTexture(descriptor: d)!
    }

    /// A busy picture: a gradient, so that any shift of a pixel changes its value.
    private func picture(_ w: Int, _ h: Int) -> CGImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                data[i] = UInt8((x * 7) % 256)
                data[i + 1] = UInt8((y * 11) % 256)
                data[i + 2] = UInt8((x + y) % 256)
            }
        }
        let context = data.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        }
        return context.makeImage()!
    }

    private func bytes(_ t: MTLTexture) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: t.width * t.height * 4)
        t.getBytes(&out, bytesPerRow: t.width * 4, from: MTLRegionMake2D(0, 0, t.width, t.height), mipmapLevel: 0)
        return out
    }

    private func renderer() throws -> ToiletDrainRenderer {
        guard let r = ToiletDrainRenderer.shared else { throw XCTSkip("no Metal device") }
        return r
    }

    /// The first frame is byte for byte the photograph: the promise that it lands
    /// on the desktop with no seam, checked on the shader rather than on the table.
    func testTheShaderAtRestGivesBackThePhotograph() throws {
        let r = try renderer()
        let image = picture(320, 200)
        let texture = try XCTUnwrap(r.texture(from: image))
        let out = target(r, 320, 200)
        r.draw(t: 0, picture: texture, into: out)?.waitUntilCompleted()

        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 320 * 4,
                                space: image.colorSpace!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: 320, height: 200))
        let expected = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 320 * 200 * 4))
        let got = bytes(out)
        let off = zip(got, expected).map { abs(Int($0) - Int($1)) }
        XCTAssertEqual(off.max(), 0, "\(off.filter { $0 > 0 }.count) of \(off.count) bytes differ")
    }

    /// One grey over the whole picture, so whatever is dark in a frame was put there
    /// by the effect.
    private func grey(_ w: Int, _ h: Int) -> CGImage {
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()!
    }

    /// The darkest pixel of a frame, undoing the alpha: a fading frame is not dark.
    private func darkest(_ px: [UInt8]) -> Int {
        var least = 255
        for i in stride(from: 0, to: px.count, by: 4) {
            let alpha = max(Int(px[i + 3]), 1)
            least = min(least, max(Int(px[i]), Int(px[i + 1]), Int(px[i + 2])) * 255 / alpha)
        }
        return least
    }

    /// **There is no hole, at any moment.** On a flat grey desktop every pixel of
    /// every frame stays bright: no dark disc, no dark ring, nowhere on the screen.
    /// The control is a real dark disc in the picture: the check does see one.
    func testThereIsNoDarkDiscOrRingAtAnyMoment() throws {
        let r = try renderer()
        let (w, h) = (480, 300)
        let out = target(r, w, h)

        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(grey(w, h), in: CGRect(x: 0, y: 0, width: w, height: h))
        context.setFillColor(gray: 0, alpha: 1)
        context.fillEllipse(in: CGRect(x: 190, y: 100, width: 100, height: 100))
        r.draw(t: 0, picture: r.texture(from: context.makeImage()!), into: out)?.waitUntilCompleted()
        XCTAssertLessThan(darkest(bytes(out)), 100, "control")

        let texture = try XCTUnwrap(r.texture(from: grey(w, h)))
        for t in stride(from: 0, through: ToiletDrain.fadeEnds, by: 0.1) {
            r.draw(t: t, picture: texture, into: out)?.waitUntilCompleted()
            XCTAssertGreaterThan(darkest(bytes(out)), 100, "at \(t) s")
        }
    }

    /// Once the last of the picture has gone, the screen is water and nothing else:
    /// two opposite pictures give the same frame, and it is blue.
    func testNothingOfThePictureIsLeftOnTheWater() throws {
        let r = try renderer()
        let (w, h) = (240, 150)
        let one = try XCTUnwrap(r.texture(from: picture(w, h)))
        let other = try XCTUnwrap(r.texture(from: grey(w, h)))
        let out = target(r, w, h)
        let t = ToiletDrain.drained + 0.3
        r.draw(t: t, picture: one, into: out)?.waitUntilCompleted()
        let first = bytes(out)
        r.draw(t: t, picture: other, into: out)?.waitUntilCompleted()
        XCTAssertEqual(first.elementsEqual(bytes(out)), true)
        let centre = (h / 2 * w + w / 2) * 4
        XCTAssertGreaterThan(first[centre], first[centre + 2], "BGRA: more blue than red")
    }

    /// Spread between the most and the least covered pixel of a frame.
    private func alphaSpread(_ px: [UInt8]) -> Int {
        let alphas = stride(from: 3, to: px.count, by: 4).map { Int(px[$0]) }
        return (alphas.max() ?? 0) - (alphas.min() ?? 0)
    }

    /// The whole screen fades at once, on the shader's real frames, waves and all;
    /// and the frame before the fade covers everything. The control proves the
    /// check sees a frame that is not uniform: the return from the centre this
    /// replaced would have failed it.
    func testTheFadeIsUniformOnTheGlass() throws {
        var lopsided = [UInt8](repeating: 255, count: 16)
        lopsided[7] = 40
        XCTAssertGreaterThan(alphaSpread(lopsided), 200, "control")

        let r = try renderer()
        let (w, h) = (480, 300)
        let texture = try XCTUnwrap(r.texture(from: picture(w, h)))
        let out = target(r, w, h)
        for t in stride(from: ToiletDrain.drained, through: ToiletDrain.fadeEnds, by: 0.05) {
            r.draw(t: t, picture: texture, into: out)?.waitUntilCompleted()
            XCTAssertEqual(alphaSpread(bytes(out)), 0, "at \(t) s")
        }
    }

    /// The last frame on the glass is transparent, alpha and colour both, so taking
    /// the layer away changes nothing.
    func testTheLastFrameOnTheGlassIsEmpty() throws {
        let r = try renderer()
        let out = target(r, 160, 100)
        r.draw(t: ToiletDrain.fadeEnds, picture: nil, into: out)?.waitUntilCompleted()
        XCTAssertEqual(bytes(out).max(), 0)
    }

    /// What a frame costs at the full Retina size: the number the choice of a
    /// fragment shader rests on. A few frames of the clip are left in `$TMPDIR`
    /// to look at.
    func testFrameTimeAtRetinaSize() throws {
        let r = try renderer()
        let (w, h) = (3456, 2234)
        let texture = try XCTUnwrap(r.texture(from: picture(w, h)))
        let out = target(r, w, h)
        var ms: [Double] = []
        for i in 0..<120 {
            let t = ToiletDrain.fadeEnds * Double(i) / 120
            let start = CACurrentMediaTime()
            r.draw(t: t, picture: texture, into: out)?.waitUntilCompleted()
            ms.append((CACurrentMediaTime() - start) * 1000)
        }
        let mean = ms.reduce(0, +) / Double(ms.count)
        print("🚽 \(w)×\(h): mean \(String(format: "%.2f", mean)) ms, worst \(String(format: "%.2f", ms.max() ?? 0)) ms")
        XCTAssertLessThan(mean, EffectsRenderCostTests.budget)
    }

    // MARK: - On the overlay (no capture, no sound: the layer is added directly)

    private func animator() throws -> (host: CALayer, animator: EmojiAnimator, device: MTLDevice) {
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 1000, height: 600)
        return (host, EmojiAnimator(hostLayer: host), try renderer().device)
    }

    /// The photograph's layer is the size of the slice on the glass, and alpha
    /// passes: it is laid over a live desktop.
    func testTheLayerFitsTheSliceAndIsTransparent() throws {
        let (host, animator, device) = try animator()
        defer { animator.stopAllActiveEffects() }
        let slice = ZoomSlice(unit: nil, rect: host.bounds)
        let layer = animator.addToiletFlushLayer(slice: slice, device: device, lasting: 10)
        XCTAssertEqual(layer.frame, host.bounds)
        XCTAssertEqual(layer.drawableSize.width, 1000 * layer.contentsScale)
        XCTAssertFalse(layer.isOpaque)
        XCTAssertTrue(host.sublayers?.last === animator.stageLayer, "the holder landed over the stage")
    }

    /// It shows up in `activeEffectNames`, which is what lights the 🛑.
    func testItCountsAsRunning() throws {
        let (host, animator, device) = try animator()
        defer { animator.stopAllActiveEffects() }
        _ = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 10)
        XCTAssertEqual(animator.activeEffectNames, ["toilet-flush"])
    }

    /// The self-termination rule: nobody has to come and take it off, and the
    /// render thread goes with it.
    func testItRemovesItself() throws {
        let (host, animator, device) = try animator()
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 0.05)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        XCTAssertNil(layer.superlayer)
        XCTAssertTrue(layer.isStopped)
        XCTAssertEqual(animator.activeEffectNames, [])
    }

    /// A stop-all (and so a suspend, which goes through it) takes the frozen
    /// desktop off at once and stops the frames.
    func testAStopAllTakesItOffAtOnce() throws {
        let (host, animator, device) = try animator()
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 10)
        layer.roll(with: try renderer(), picture: nil, space: nil, clock0: CACurrentMediaTime())
        animator.stopAllActiveEffects()
        XCTAssertNil(layer.superlayer)
        XCTAssertTrue(layer.isStopped)
    }

    /// The loop on real drawables, entered near the end of the clock: it draws, and
    /// it ends by itself with nobody asking.
    func testTheLoopDrawsAndEndsWithTheClip() throws {
        let (host, animator, device) = try animator()
        defer { animator.stopAllActiveEffects() }
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 10)
        layer.roll(with: try renderer(), picture: nil, space: CGColorSpace(name: CGColorSpace.displayP3),
                   clock0: CACurrentMediaTime() - ToiletDrain.fadeEnds + 0.1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.4))
        let drawn = layer.framesDrawn
        XCTAssertGreaterThan(drawn, 1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertEqual(layer.framesDrawn, drawn, "still drawing after the clip's end")
    }

    /// Re-pressing the one tile ends this effect and leaves the others alone.
    func testAStopByNameEndsIt() throws {
        let (host, animator, device) = try animator()
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 10)
        animator.stopEffect(named: "toilet-flush")
        XCTAssertNil(layer.superlayer)
        XCTAssertTrue(layer.isStopped)
    }

    /// A capture that comes back after a stop finds the layer gone: it must not
    /// start a thread with nothing to draw on.
    func testAStoppedLayerNeverRolls() throws {
        let (host, animator, device) = try animator()
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: device, lasting: 10)
        animator.stopAllActiveEffects()
        layer.roll(with: try renderer(), picture: nil, space: nil, clock0: CACurrentMediaTime())
        XCTAssertTrue(layer.isStopped)
    }

    // MARK: - The real path: the layer, its thread, its drawables, composited

    /// The layer as the app runs it: `ToiletDrainLayer` on an `EmojiAnimator`, its
    /// own render thread presenting real drawables with `fit`'s real drawable size,
    /// composited by Core Animation at Retina over a magenta desktop, so a gap in
    /// the overlay cannot pass for water. The offscreen frames above stop at the
    /// texture; this is the part of the road between that and the window server.
    /// `spoil` is for the control.
    private func composited(at t: Double, points: CGSize, spoil: (ToiletDrainLayer) -> Void = { _ in }) throws -> (px: [UInt8], w: Int, h: Int) {
        let r = try renderer()
        let scale: CGFloat = 2
        let w = Int(points.width * scale), h = Int(points.height * scale)
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: w, height: h)
        root.backgroundColor = CGColor(red: 1, green: 0, blue: 1, alpha: 1)
        root.actions = ["sublayers": NSNull()]
        let host = CALayer()
        host.anchorPoint = .zero
        host.bounds = CGRect(origin: .zero, size: points)
        host.position = .zero
        host.transform = CATransform3DMakeScale(scale, scale, 1)
        host.actions = ["sublayers": NSNull()]
        root.addSublayer(host)
        let animator = EmojiAnimator(hostLayer: host)
        defer { animator.stopAllActiveEffects() }

        let offscreen = OffscreenRenderer(device: r.device, root: root, width: w, height: h)
        let layer = animator.addToiletFlushLayer(slice: ZoomSlice(unit: nil, rect: host.bounds), device: r.device, lasting: 10)
        spoil(layer)
        let image = picture(w, h)
        layer.roll(with: r, picture: r.texture(from: image), space: image.colorSpace, clock0: CACurrentMediaTime() - t)
        let deadline = Date(timeIntervalSinceNow: 2)
        while layer.framesDrawn < 3, Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        XCTAssertGreaterThanOrEqual(layer.framesDrawn, 3, "the render thread never drew")
        CATransaction.flush()
        return (offscreen.render(at: CACurrentMediaTime()), w, h)
    }

    /// Pixels of a composited frame that are not water: `gaps` is the magenta
    /// desktop showing through, `black` is opaque nothing. Every 8th pixel, plus the
    /// outermost rows and columns, where a mis-sized layer would show first.
    private func notWater(_ px: [UInt8], _ w: Int, _ h: Int) -> (gaps: Int, black: Int) {
        var gaps = 0, black = 0
        func look(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            let (b, g, r) = (Int(px[i]), Int(px[i + 1]), Int(px[i + 2]))
            if r > 150, b > 150, g < 110 { gaps += 1 }
            if max(r, g, b) < 60 { black += 1 }
        }
        for y in stride(from: 0, to: h, by: 8) { for x in stride(from: 0, to: w, by: 8) { look(x, y) } }
        for x in 0..<w { look(x, 0); look(x, h - 1) }
        for y in 0..<h { look(0, y); look(w - 1, y) }
        return (gaps, black)
    }

    /// The sizes that matter: the screen's, and the 1694×1095 the overlay window was
    /// seen at on 2026-11-04, which no offscreen frame had been drawn at.
    private let overlaySizes = [CGSize(width: 1728, height: 1117), CGSize(width: 1694, height: 1095)]

    /// **At the end the water covers the whole overlay, on the real path.** Reported
    /// on the glass as water in a circle with black around it, which the offscreen
    /// sheets did not show. Not reproduced here; this holds the layer, its drawable
    /// size, its alpha and its compositing to the promise, so that those are ruled
    /// out for good. The control shrinks the layer, as a wrong size would: the check
    /// does see a gap, and a pass means something.
    func testTheWaterCoversTheWholeOverlayOnTheRealPath() throws {
        for size in overlaySizes {
            for t in [ToiletDrain.drained + 0.1, 5.0, ToiletDrain.settled - 0.05] {
                let c = try composited(at: t, points: size)
                let wrong = notWater(c.px, c.w, c.h)
                XCTAssertEqual(wrong.gaps, 0, "\(size) at \(t) s")
                XCTAssertEqual(wrong.black, 0, "\(size) at \(t) s")
            }
        }
        let size = overlaySizes[0]
        let c = try composited(at: 5.0, points: size) {
            $0.frame = CGRect(x: 400, y: 250, width: size.width - 800, height: size.height - 500)
        }
        XCTAssertGreaterThan(notWater(c.px, c.w, c.h).gaps, 1000, "control")
    }

    /// The end state on the shader alone, at both real sizes: from the moment the
    /// picture has gone, every pixel out to the corners and edges is opaque water,
    /// bluer than it is red, at the same height of tone in the corners as in the
    /// middle. A circle of water would fail the corners.
    func testTheEndStateIsWaterToTheVeryCorners() throws {
        let r = try renderer()
        for size in overlaySizes {
            let (w, h) = (Int(size.width) * 2, Int(size.height) * 2)
            let texture = try XCTUnwrap(r.texture(from: picture(w, h)))
            let out = target(r, w, h)
            for t in [ToiletDrain.drained, 4.8, 5.1, ToiletDrain.settled] {
                r.draw(t: t, picture: texture, into: out)?.waitUntilCompleted()
                let px = bytes(out)
                XCTAssertEqual(notWater(px, w, h).black, 0, "\(size) at \(t) s")
                for (x, y) in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w / 2, 0), (0, h / 2), (w / 2, h / 2)] {
                    let i = (y * w + x) * 4
                    XCTAssertEqual(px[i + 3], 255, "alpha at \(x),\(y), \(t) s")
                    XCTAssertGreaterThan(px[i], px[i + 2], "blue over red at \(x),\(y), \(t) s")
                    XCTAssertGreaterThan(px[i], 90, "tone at \(x),\(y), \(t) s")
                }
            }
        }
    }

    // MARK: - The promise

    /// In the play path, not the press path: a second trigger would flush twice.
    func testItIsAPlayPathVisual() {
        XCTAssertEqual(SoundEffectMap.playPathVisuals["66_toilet.mp3"], "toilet-flush")
        XCTAssertNil(SoundEffectMap.onPress["66_toilet.mp3"])
        XCTAssertEqual(EffectsCatalog.effectName(forAsset: "66_toilet.mp3"), "toilet-flush")
    }

    /// The caption stays what it was: the flush changes the desktop, not the words.
    func testTheCaptionIsUnchanged() {
        XCTAssertEqual(SoundCaptions.table["66_toilet.mp3"], "[toilet flushing]")
    }
}
