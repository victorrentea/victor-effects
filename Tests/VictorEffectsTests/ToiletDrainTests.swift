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

    // MARK: - The hole

    /// "Round, 10 % of the screen": an area, so it holds on any aspect ratio.
    func testTheHoleIsATenthOfTheScreen() {
        for (w, h) in [(3456.0, 2234.0), (1728.0, 1117.0), (3840.0, 1600.0), (1000.0, 1000.0)] {
            let geometry = ToiletDrain.Geometry(width: w, height: h)
            let area = Double.pi * pow(geometry.holeRadius, 2)
            XCTAssertEqual(area / (w * h), 0.10, accuracy: 1e-9)
            XCTAssertLessThan(geometry.holeRadius, h / 2, "the hole must fit on the screen")
        }
    }

    /// Shut until the valve, all the way open when the rush arrives.
    func testTheHoleOpensWithTheValve() {
        XCTAssertEqual(ToiletDrain.holeRadius(ToiletDrain.valve, g), 0)
        XCTAssertEqual(ToiletDrain.holeRadius(ToiletDrain.rush, g), g.holeRadius)
        XCTAssertEqual(ToiletDrain.holeRadius(4, g), g.holeRadius)
    }

    // MARK: - Against the clip

    /// The cues are in the order of the clip, and inside it.
    func testTheCuesFollowTheClip() {
        XCTAssertLessThan(ToiletDrain.valve, ToiletDrain.rush)
        XCTAssertLessThan(ToiletDrain.rush, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.first?.from, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.last?.to ?? 0, ToiletDrain.drained, accuracy: 0.001)
        XCTAssertLessThan(ToiletDrain.drained, ToiletDrain.refillEnds)
        XCTAssertEqual(ToiletDrain.refillEnds, ToiletDrain.clipSeconds)
        XCTAssertGreaterThan(ToiletDrain.totalSeconds, ToiletDrain.clipSeconds, "the removal must land after the last frame")
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

    /// Faster near the hole, at every moment the water is moving.
    func testItTurnsFasterNearTheHole() {
        for t in [1.5, 2.5, 3.5, 4.2] {
            let radii = stride(from: g.holeRadius, through: g.reach, by: 100).map { $0 }
            let speeds = radii.map { ToiletDrain.angularSpeed($0, t, g) }
            XCTAssertEqual(speeds, speeds.sorted(by: >), "at \(t) s")
            XCTAssertGreaterThan(speeds[0], 2.5 * speeds[speeds.count - 1])
        }
    }

    /// Grows over the clip, up to the moment it ends. And even the corners go
    /// around, or the whole picture would not be seen to turn.
    func testTheSpinGrowsOverTheClip() {
        let times = stride(from: 1.0, to: ToiletDrain.gurgle, by: 0.25).map { $0 }
        for r in [g.holeRadius, 2 * g.holeRadius, g.reach] {
            let speeds = times.map { ToiletDrain.angularSpeed(r, $0, g) }
            XCTAssertEqual(speeds, speeds.sorted(), "at r = \(r)")
        }
        XCTAssertGreaterThan(ToiletDrain.spin(g.reach, ToiletDrain.drained, g), .pi)
    }

    /// The difference from a rotation: two radii turned by different angles, so
    /// straight lines have wound into a spiral.
    func testItWindsARotationWouldNot() {
        let t = 3.0
        let twist = ToiletDrain.spin(g.holeRadius, t, g) - ToiletDrain.spin(2.5 * g.holeRadius, t, g)
        XCTAssertGreaterThan(twist, 2 * .pi, "not one full turn between the rim and a little outside it")
    }

    /// Counter-clockwise on the glass: the water right of the centre moves up, so
    /// a pixel above the centre shows what was to its right.
    func testItTurnsCounterClockwise() {
        // Soon after the valve the angle is still small enough to read.
        let t = ToiletDrain.valve + 0.1
        let p = ToiletDrain.source(of: 0, -500, t, g)
        XCTAssertGreaterThan(p.x, 0, "y is down: this pixel is above the centre")
    }

    /// The water's edge starts past the corners and ends on the rim of the hole.
    func testTheShorelineClosesOnTheHole() {
        XCTAssertGreaterThanOrEqual(ToiletDrain.shoreline(0, g), g.reach)
        XCTAssertEqual(ToiletDrain.shoreline(ToiletDrain.drained, g), g.holeRadius, accuracy: 1e-6)
        let edge = everyMoment.map { ToiletDrain.shoreline($0, g) }
        XCTAssertEqual(edge, edge.sorted(by: >))
    }

    // MARK: - The table

    private func rows(at t: Double, picture: Bool = true) -> [ToiletDrain.Row] {
        var rows = [ToiletDrain.Row](repeating: .init(), count: 512)
        let step = g.reach * 1.01 / 511
        rows.withUnsafeMutableBufferPointer { ToiletDrain.fill($0, step: step, t: t, geometry: g, picture: picture) }
        return rows
    }

    /// At rest the table says "the photograph, untouched" for every ring out to
    /// the corners: no water tint, no foam, no shadow, nothing of the bowl.
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
        }
    }

    /// The last frame covers nothing, so the removal that follows changes nothing:
    /// that is the whole of "no flash".
    func testTheLastFrameIsEmpty() {
        for row in rows(at: ToiletDrain.refillEnds) { XCTAssertEqual(row.mix.z, 0, "alpha") }
    }

    /// Between the two, the desktop comes back only after the picture has gone,
    /// from the middle outwards.
    func testTheDesktopComesBackFromTheMiddle() {
        for row in rows(at: ToiletDrain.drained) { XCTAssertEqual(row.mix.z, 1, "the bowl stands empty first") }
        let half = rows(at: (ToiletDrain.drained + ToiletDrain.refillEnds) / 2).map(\.mix.z)
        XCTAssertLessThan(half[0], half[half.count - 1])
        XCTAssertEqual(half, half.sorted())
    }

    /// With no photograph the first frame is the live desktop, and the water fades
    /// in over it rather than appearing.
    func testWithNoPictureTheWaterFadesIn() {
        for row in rows(at: 0, picture: false) { XCTAssertEqual(row.mix.z, 0) }
        XCTAssertGreaterThan(rows(at: ToiletDrain.rush, picture: false)[400].mix.z, 0.8)
        for row in rows(at: ToiletDrain.refillEnds, picture: false) { XCTAssertEqual(row.mix.z, 0) }
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

    /// The hole on the glass, counted in pixels: round, in the middle, a tenth of
    /// the screen. And with the clip quiet there is none of the picture left.
    func testTheHoleOnTheGlass() throws {
        let r = try renderer()
        let (w, h) = (480, 300)
        let texture = try XCTUnwrap(r.texture(from: picture(w, h)))
        let out = target(r, w, h)
        r.draw(t: ToiletDrain.drained, picture: texture, into: out)?.waitUntilCompleted()
        let px = bytes(out)

        var dark = 0
        var sumX = 0, sumY = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if max(px[i], px[i + 1], px[i + 2]) < 30 { dark += 1; sumX += x; sumY += y }
            }
        }
        XCTAssertEqual(Double(dark) / Double(w * h), 0.10, accuracy: 0.015)
        XCTAssertEqual(Double(sumX) / Double(dark), Double(w) / 2, accuracy: 2)
        XCTAssertEqual(Double(sumY) / Double(dark), Double(h) / 2, accuracy: 2)

        // The corners are the dry bowl: pale and grey, with nothing of the
        // gradient's colours left in them.
        let corner = (5 * w + 5) * 4
        XCTAssertGreaterThan(px[corner], 150)
        XCTAssertLessThan(abs(Int(px[corner]) - Int(px[corner + 2])), 16)
    }

    /// The last frame on the glass is transparent, alpha and colour both.
    func testTheLastFrameOnTheGlassIsEmpty() throws {
        let r = try renderer()
        let out = target(r, 160, 100)
        r.draw(t: ToiletDrain.refillEnds, picture: nil, into: out)?.waitUntilCompleted()
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
            let t = ToiletDrain.refillEnds * Double(i) / 120
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
                   clock0: CACurrentMediaTime() - ToiletDrain.refillEnds + 0.1)
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
