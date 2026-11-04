import AppKit
import AVFoundation
import Metal
import XCTest
@testable import VictorEffects

/// 🚽 The flush, checked without a screen, a capture or a speaker: the shape is
/// numbers in `ToiletDrain`, and the frames come off a Metal texture the renderer
/// is handed like any other.
final class ToiletDrainTests: XCTestCase {

    private let g = ToiletDrain.Geometry(width: 3456, height: 2234)
    private let everyMoment = stride(from: -0.1, through: 6.2, by: 0.01).map { $0 }

    // MARK: - The bowl

    /// The size that was decided, from the short side, so a wider screen gets more
    /// black and not a bigger or an oval bowl.
    func testTheBowlIsADecidedShareOfTheShortSide() {
        XCTAssertEqual(ToiletDrain.bowlShare, 0.31)
        XCTAssertEqual(g.bowl, 0.31 * 2234, accuracy: 1e-9)
        let wide = ToiletDrain.Geometry(width: 5120, height: 2160)
        XCTAssertEqual(wide.bowl, 0.31 * 2160, accuracy: 1e-9)
        let tall = ToiletDrain.Geometry(width: 1000, height: 1600)
        XCTAssertEqual(tall.bowl, 310, accuracy: 1e-9)
    }

    // MARK: - Against the clip

    /// The cues are in the order of the clip, and the picture is gone inside it.
    func testTheCuesFollowTheClip() {
        XCTAssertLessThan(ToiletDrain.valve, ToiletDrain.rush)
        XCTAssertLessThan(ToiletDrain.rush, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.first?.from, ToiletDrain.gurgle)
        XCTAssertEqual(ToiletDrain.gulps.last?.to ?? 0, ToiletDrain.drained, accuracy: 0.001)
        XCTAssertLessThan(ToiletDrain.drained, ToiletDrain.clipSeconds)
    }

    /// The bowl sits long enough to be seen, and that is the only reason the end
    /// runs past the audio: by under a second, and the show still ends itself.
    func testTheBowlIsSeenAndTheTailIsShort() {
        XCTAssertGreaterThanOrEqual(ToiletDrain.settled - ToiletDrain.drained, 0.9)
        XCTAssertLessThan(ToiletDrain.settled, ToiletDrain.fadeEnds)
        XCTAssertLessThan(ToiletDrain.fadeEnds - ToiletDrain.clipSeconds, 0.9)
        XCTAssertGreaterThan(ToiletDrain.totalSeconds, ToiletDrain.fadeEnds, "the removal must land after the last frame")
    }

    /// AVFoundation counts the mp3's encoder padding, ffmpeg does not: 5.12 s to
    /// its 5.08 s.
    func testTheClipIsTheOneThatWasMeasured() throws {
        let url = EffectsConfig.shared.soundsDir.appendingPathComponent("66_toilet.mp3")
        guard FileManager.default.fileExists(atPath: url.path) else { throw XCTSkip("no tablet assets here") }
        let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
        XCTAssertEqual(seconds, ToiletDrain.clipSeconds, accuracy: 0.05, "new recording: measure the cues in ToiletDrain again")
    }

    // MARK: - The shrink

    /// Past the corners until the valve, the bowl when the clip goes quiet, and it
    /// only ever closes.
    func testTheCircleCloses() {
        XCTAssertGreaterThan(ToiletDrain.radius(ToiletDrain.valve, g), g.reach)
        XCTAssertEqual(ToiletDrain.radius(ToiletDrain.drained, g), g.bowl, accuracy: 1e-6)
        XCTAssertEqual(ToiletDrain.radius(5.5, g), g.bowl, accuracy: 1e-6)
        let radii = everyMoment.map { ToiletDrain.radius($0, g) }
        XCTAssertEqual(radii, radii.sorted(by: >))
    }

    /// Timed to the clip: moving on the rush, whole on the screen before the
    /// gurgle, and each gulp is seen to tighten it.
    func testTheShrinkFollowsTheRushAndTheGurgle() {
        XCTAssertGreaterThan(ToiletDrain.shrink(ToiletDrain.rush), 0.1)
        XCTAssertLessThan(ToiletDrain.radius(ToiletDrain.gurgle, g), g.height / 2)
        for gulp in ToiletDrain.gulps {
            XCTAssertLessThan(ToiletDrain.radius(gulp.to, g), ToiletDrain.radius(gulp.from, g) - 0.02 * g.bowl)
        }
    }

    /// At rest the warp is the identity, so the photograph lands on the desktop
    /// without a seam.
    func testAtRestEveryPixelIsItself() {
        for t in [-0.1, 0, ToiletDrain.valve] {
            for (x, y) in [(100.0, 50.0), (-1500.0, 900.0), (3.0, -1.0)] {
                let p = ToiletDrain.source(of: x, y, t, g)
                XCTAssertEqual(p.x, x, accuracy: 1e-6)
                XCTAssertEqual(p.y, y, accuracy: 1e-6)
            }
        }
    }

    /// The whole screen fits: on the rim of the bowl the picture has reached its
    /// own edge, in every direction, so nothing is cropped away.
    func testTheWholeScreenFitsInTheCircle() {
        let t = ToiletDrain.gurgle
        let rim = ToiletDrain.radius(t, g)
        for degrees in stride(from: 0.0, to: 360, by: 15) {
            let a = degrees * .pi / 180
            let p = ToiletDrain.source(of: rim * cos(a), rim * sin(a), t, g)
            let reached = (p.x * p.x + p.y * p.y).squareRoot()
            XCTAssertEqual(reached, ToiletDrain.extent(p.x / reached, p.y / reached, g), accuracy: 1, "at \(degrees)°")
        }
    }

    /// No gap inside the circle at any angle: everything that can be seen comes
    /// from inside the picture, however far it has turned.
    func testThereIsNoGapInsideTheCircle() {
        for t in [1.0, 1.6, 2.2, 2.8, 3.3] {
            let rim = ToiletDrain.radius(t, g)
            for x in stride(from: -g.width / 2, through: g.width / 2, by: 90) {
                for y in stride(from: -g.height / 2, through: g.height / 2, by: 90) {
                    let r = (x * x + y * y).squareRoot()
                    guard r > 1, r < rim, r < ToiletDrain.extent(x / r, y / r, g) else { continue }
                    let p = ToiletDrain.source(of: x, y, t, g)
                    XCTAssertLessThanOrEqual(abs(p.x), g.width / 2 + 1, "at \(x),\(y), \(t) s")
                    XCTAssertLessThanOrEqual(abs(p.y), g.height / 2 + 1, "at \(x),\(y), \(t) s")
                }
            }
        }
    }

    // MARK: - The turn

    /// Fewer rotations: a little over one turn in all, more of it inside the circle
    /// than before it, and it stops with the picture.
    func testItTurnsOnlyALittle() {
        XCTAssertEqual(ToiletDrain.turn(ToiletDrain.valve), 0)
        XCTAssertLessThan(ToiletDrain.turn(ToiletDrain.drained), 1.25 * 2 * .pi)
        XCTAssertGreaterThan(ToiletDrain.turn(ToiletDrain.drained), .pi)
        let whole = everyMoment.first { ToiletDrain.radius($0, g) < g.height / 2 } ?? 0
        XCTAssertLessThan(ToiletDrain.turn(whole), 0.5 * ToiletDrain.turn(ToiletDrain.drained))
        XCTAssertEqual(ToiletDrain.turn(5), ToiletDrain.turn(ToiletDrain.drained))
    }

    /// Not a spiral: the middle is ahead of the rim by a fraction of the turn, not
    /// by turns.
    func testItDoesNotWindIntoASpiral() {
        let t = ToiletDrain.gurgle
        let rim = ToiletDrain.radius(t, g)
        XCTAssertLessThan(ToiletDrain.spin(0, t, g) - ToiletDrain.spin(rim, t, g), 0.4 * ToiletDrain.turn(t))
        XCTAssertLessThan(ToiletDrain.spin(0, t, g) - ToiletDrain.spin(rim, t, g), .pi)
    }

    /// Counter-clockwise on the glass: what was right of the centre moves up, so a
    /// pixel above the centre shows what was to its right.
    func testItTurnsCounterClockwise() {
        XCTAssertGreaterThan(ToiletDrain.source(of: 0, -500, 1.5, g).x, 0, "y is down: this pixel is above the centre")
    }

    // MARK: - The water

    /// None until the circle is whole on the screen, all of it on the dead cut, and
    /// each gulp takes a bite.
    func testTheWaterReplacesThePicture() {
        XCTAssertEqual(ToiletDrain.water(2.8), 0)
        XCTAssertEqual(ToiletDrain.water(ToiletDrain.drained), 1, accuracy: 1e-9)
        XCTAssertEqual(ToiletDrain.water(5), 1, accuracy: 1e-9)
        let values = everyMoment.map(ToiletDrain.water)
        XCTAssertEqual(values, values.sorted())
        for gulp in ToiletDrain.gulps {
            XCTAssertGreaterThan(ToiletDrain.water(gulp.to) - ToiletDrain.water(gulp.from), 0.15)
        }
    }

    /// The waves fall from the last gulp to a gentle tremble and stay there: the
    /// bowl never goes flat, not even in the fade.
    func testTheWaterTremblesGentlyForGood() {
        XCTAssertEqual(ToiletDrain.chop(ToiletDrain.drained), 1)
        let heights = stride(from: ToiletDrain.drained, through: ToiletDrain.fadeEnds, by: 0.05).map(ToiletDrain.chop)
        XCTAssertEqual(heights, heights.sorted(by: >))
        XCTAssertLessThan(ToiletDrain.chop(ToiletDrain.settled), ToiletDrain.gentle + 0.05)
        XCTAssertGreaterThanOrEqual(ToiletDrain.chop(ToiletDrain.fadeEnds), ToiletDrain.gentle)
        XCTAssertGreaterThan(ToiletDrain.gentle, 0.2, "too flat to see tremble from the back of a room")
    }

    /// The ring starts with the last of the picture, stays in the bowl and dies.
    func testTheRingWaveDies() {
        for r in [10.0, 300, 600] { XCTAssertEqual(ToiletDrain.ringSlope(r, ToiletDrain.drained, g), 0) }
        XCTAssertNotEqual(ToiletDrain.ringSlope(0.5 * g.bowl, ToiletDrain.drained + 0.4, g), 0)
        XCTAssertEqual(ToiletDrain.ringSlope(0.5 * g.bowl, 20, g), 0, accuracy: 1e-6)
    }

    // MARK: - The table

    private func rows(at t: Double, picture: Bool = true) -> [ToiletDrain.Row] {
        var rows = [ToiletDrain.Row](repeating: .init(), count: 512)
        let step = g.reach * 1.01 / 511
        rows.withUnsafeMutableBufferPointer { ToiletDrain.fill($0, step: step, t: t, geometry: g, picture: picture) }
        return rows
    }

    /// At rest the table says "the photograph, untouched" for every ring out to the
    /// corners: no turn, no mask, no water.
    func testTheFirstFrameIsThePhotographAndNothingElse() {
        let table = rows(at: 0)
        for row in table[0..<Int(Double(table.count - 1) / 1.01)] {
            XCTAssertEqual(row.warp.x, 0, "spin")
            XCTAssertEqual(row.warp.y, 1, "inside the circle")
            XCTAssertEqual(row.warp.w, 0, "ring wave")
            XCTAssertLessThan(row.wash.x, 0.12, "no water")
            XCTAssertEqual(row.wash.y, 1, "alpha")
        }
    }

    /// Outside the bowl the mask is exactly 0 from a pixel past the rim: no glow.
    func testTheMaskStopsDeadAtTheRim() {
        let table = rows(at: 5)
        let step = g.reach * 1.01 / 511
        for (i, row) in table.enumerated() where Double(i) * step > g.bowl + 1 { XCTAssertEqual(row.warp.y, 0) }
        for (i, row) in table.enumerated() where Double(i) * step < g.bowl - 1 { XCTAssertEqual(row.warp.y, 1) }
    }

    /// "At once, uniformly": the fade is one number, for every ring, at every
    /// moment, and only ever goes down.
    func testTheFadeIsTheSameEverywhere() {
        for t in stride(from: ToiletDrain.drained, through: ToiletDrain.fadeEnds + 0.1, by: 0.05) {
            XCTAssertEqual(Set(rows(at: t).map(\.wash.y)), [Float(ToiletDrain.fadeOut(t))], "at \(t) s")
        }
        XCTAssertEqual(ToiletDrain.fadeOut(ToiletDrain.settled), 1)
        XCTAssertEqual(ToiletDrain.fadeOut(ToiletDrain.fadeEnds), 0)
        let values = everyMoment.map(ToiletDrain.fadeOut)
        XCTAssertEqual(values, values.sorted(by: >))
    }

    /// With no photograph the first frame is the live desktop: the black and the
    /// water fade in over it rather than appearing, and leave the same way as ever.
    func testWithNoPictureItFadesIn() {
        for row in rows(at: 0, picture: false) { XCTAssertEqual(row.wash.y, 0) }
        XCTAssertGreaterThan(rows(at: ToiletDrain.rush, picture: false)[400].wash.y, 0.8)
        for row in rows(at: ToiletDrain.fadeEnds, picture: false) { XCTAssertEqual(row.wash.y, 0) }
    }

    // MARK: - Real frames, on a texture

    private func target(_ renderer: ToiletDrainRenderer, _ w: Int, _ h: Int) -> MTLTexture {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        return renderer.device.makeTexture(descriptor: d)!
    }

    private func image(_ w: Int, _ h: Int, _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8)) -> CGImage {
        var data = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                (data[i + 2], data[i + 1], data[i]) = pixel(x, y)
            }
        }
        let context = data.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        }
        return context.makeImage()!
    }

    /// A busy picture: any shift of a pixel changes its value.
    private func picture(_ w: Int, _ h: Int) -> CGImage {
        image(w, h) { x, y in (UInt8((x + y) % 256), UInt8((y * 11) % 256), UInt8((x * 7) % 256)) }
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

    private func frame(_ r: ToiletDrainRenderer, at t: Double, _ w: Int, _ h: Int, picture: CGImage? = nil) throws -> [UInt8] {
        let out = target(r, w, h)
        let texture = try XCTUnwrap(r.texture(from: picture ?? self.picture(w, h)))
        r.draw(t: t, picture: texture, into: out)?.waitUntilCompleted()
        return bytes(out)
    }

    /// The first frame is byte for byte the photograph: the promise that it lands
    /// on the desktop with no seam, checked on the shader rather than on the table.
    func testTheShaderAtRestGivesBackThePhotograph() throws {
        let r = try renderer()
        let shot = picture(320, 200)
        let got = try frame(r, at: 0, 320, 200, picture: shot)

        let context = CGContext(data: nil, width: 320, height: 200, bitsPerComponent: 8, bytesPerRow: 320 * 4,
                                space: shot.colorSpace!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        context.draw(shot, in: CGRect(x: 0, y: 0, width: 320, height: 200))
        let expected = Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: 320 * 200 * 4))
        let off = zip(got, expected).map { abs(Int($0) - Int($1)) }
        XCTAssertEqual(off.max(), 0, "\(off.filter { $0 > 0 }.count) of \(off.count) bytes differ")
    }

    /// The squeeze is the one piece of maths that has to live in the shader as well,
    /// because it depends on the direction. A picture whose colour says where each
    /// pixel came from holds the two copies together.
    func testTheShaderSamplesWhereTheMathsSays() throws {
        let r = try renderer()
        let (w, h) = (1024, 640)
        let ramp = image(w, h) { x, y in (UInt8(x * 255 / (w - 1)), UInt8(y * 255 / (h - 1)), 0) }
        let geometry = ToiletDrain.Geometry(width: Double(w), height: Double(h))
        for t in [1.8, 2.6] {
            let px = try frame(r, at: t, w, h, picture: ramp)
            for (x, y) in [(120, 80), (-160, 90), (60, -150), (-90, -120), (200, -40), (30, 160)] {
                let s = ToiletDrain.source(of: Double(x), Double(y), t, geometry)
                let i = ((y + h / 2) * w + x + w / 2) * 4
                XCTAssertEqual(Double(px[i + 2]), 255 * (s.x + 512) / 1023, accuracy: 6, "red at \(x),\(y), \(t) s")
                XCTAssertEqual(Double(px[i + 1]), 255 * (s.y + 320) / 639, accuracy: 6, "green at \(x),\(y), \(t) s")
            }
        }
    }

    /// **True black around the bowl.** Every pixel past the rim is exactly (0, 0, 0)
    /// and opaque, on a wide screen and a 16:10 one, from the moment the bowl forms
    /// until the fade: no glow and no vignette bleeding out of it.
    func testEverythingOutsideTheBowlIsTrueBlack() throws {
        let r = try renderer()
        for (w, h) in [(960, 400), (480, 300)] {
            let bowl = 0.31 * Double(min(w, h))
            for t in [ToiletDrain.drained, 4.9, ToiletDrain.settled] {
                let px = try frame(r, at: t, w, h)
                var wrong = 0
                for y in 0..<h {
                    for x in 0..<w {
                        let dx = Double(x) + 0.5 - Double(w) / 2, dy = Double(y) + 0.5 - Double(h) / 2
                        guard (dx * dx + dy * dy).squareRoot() > bowl + 1.5 else { continue }
                        let i = (y * w + x) * 4
                        if px[i] != 0 || px[i + 1] != 0 || px[i + 2] != 0 || px[i + 3] != 255 { wrong += 1 }
                    }
                }
                XCTAssertEqual(wrong, 0, "\(w)×\(h) at \(t) s")
            }
        }
    }

    /// Round on a wide screen, counted in pixels: walking out from the centre along
    /// 48 directions, the water stops at the same radius within a pixel and a half,
    /// the decided one. An oval from an aspect ratio would miss by a third.
    func testTheCircleIsRoundOnAWideScreen() throws {
        let r = try renderer()
        let (w, h) = (1600, 660)
        let px = try frame(r, at: 5, w, h)
        let bowl = 0.31 * Double(h)
        for step in 0..<48 {
            let a = Double(step) * 2 * .pi / 48
            var edge = 0.0
            for d in stride(from: bowl * 0.8, to: bowl * 1.3, by: 0.25) {
                let x = Int(Double(w) / 2 + d * cos(a)), y = Int(Double(h) / 2 + d * sin(a))
                let i = (y * w + x) * 4
                if max(px[i], px[i + 1], px[i + 2]) > 8 { edge = d }
            }
            XCTAssertEqual(edge, bowl, accuracy: 1.5, "at \(step * 360 / 48)°")
        }
    }

    /// In the bowl state the screen is water and nothing else: two opposite pictures
    /// give the same frame, and it is blue.
    func testNothingOfThePictureIsLeftInTheBowl() throws {
        let r = try renderer()
        let (w, h) = (240, 150)
        let t = ToiletDrain.drained + 0.3
        let first = try frame(r, at: t, w, h)
        let second = try frame(r, at: t, w, h, picture: image(w, h) { _, _ in (128, 128, 128) })
        XCTAssertTrue(first.elementsEqual(second))
        let centre = ((h / 2 + 20) * w + w / 2) * 4
        XCTAssertGreaterThan(Int(first[centre]), Int(first[centre + 2]) + 60, "BGRA: well more blue than red")
    }

    /// The bowl trembles: moments apart the water differs, and the black does not.
    func testTheWaterMovesAndTheBlackDoesNot() throws {
        let r = try renderer()
        let (w, h) = (480, 300)
        let one = try frame(r, at: 5.2, w, h)
        let two = try frame(r, at: 5.3, w, h)
        var moved = 0
        for x in stride(from: 150, to: 330, by: 3) {
            let i = (150 * w + x) * 4
            if abs(Int(one[i]) - Int(two[i])) > 1 { moved += 1 }
            XCTAssertEqual(one[(5 * w + x) * 4], 0)
            XCTAssertEqual(two[(5 * w + x) * 4], 0)
        }
        XCTAssertGreaterThan(moved, 20)
    }

    /// Spread between the most and the least covered pixel of a frame.
    private func alphaSpread(_ px: [UInt8]) -> Int {
        let alphas = stride(from: 3, to: px.count, by: 4).map { Int(px[$0]) }
        return (alphas.max() ?? 0) - (alphas.min() ?? 0)
    }

    /// The whole screen fades at once on the shader's real frames: the bowl and the
    /// black on one alpha. The control proves the check sees a frame that is not
    /// uniform, such as the return from the centre this replaced.
    func testTheFadeIsUniformOnTheGlass() throws {
        var lopsided = [UInt8](repeating: 255, count: 16)
        lopsided[7] = 40
        XCTAssertGreaterThan(alphaSpread(lopsided), 200, "control")

        let r = try renderer()
        for t in stride(from: ToiletDrain.settled, through: ToiletDrain.fadeEnds, by: 0.1) {
            XCTAssertEqual(alphaSpread(try frame(r, at: t, 480, 300)), 0, "at \(t) s")
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
    /// fragment shader rests on.
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
    /// own render thread presenting real drawables, composited by Core Animation at
    /// Retina over a magenta desktop, so a gap in the overlay cannot pass for black.
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
        let shot = picture(w, h)
        layer.roll(with: r, picture: r.texture(from: shot), space: shot.colorSpace, clock0: CACurrentMediaTime() - t)
        let deadline = Date(timeIntervalSinceNow: 2)
        while layer.framesDrawn < 3, Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01)) }
        XCTAssertGreaterThanOrEqual(layer.framesDrawn, 3, "the render thread never drew")
        CATransaction.flush()
        return (offscreen.render(at: CACurrentMediaTime()), w, h)
    }

    /// Pixels of the overlay's rim and corners where the desktop shows through.
    private func gaps(_ px: [UInt8], _ w: Int, _ h: Int) -> Int {
        var found = 0
        func look(_ x: Int, _ y: Int) {
            let i = (y * w + x) * 4
            if px[i + 2] > 150, px[i] > 150 { found += 1 }
        }
        for y in stride(from: 0, to: h, by: 8) { for x in stride(from: 0, to: w, by: 8) { look(x, y) } }
        for x in 0..<w { look(x, 0); look(x, h - 1) }
        for y in 0..<h { look(0, y); look(w - 1, y) }
        return found
    }

    /// The bowl through Core Animation, with the layer's real drawable size and
    /// alpha: black to the very corners, blue in the middle, no desktop showing
    /// anywhere. The control shrinks the layer: the check does see a gap.
    func testTheBowlOnTheRealPath() throws {
        let size = CGSize(width: 1728, height: 1117)
        let c = try composited(at: 5.0, points: size)
        XCTAssertEqual(gaps(c.px, c.w, c.h), 0)
        for (x, y) in [(0, 0), (c.w - 1, 0), (0, c.h - 1), (c.w - 1, c.h - 1)] {
            let i = (y * c.w + x) * 4
            XCTAssertEqual(Array(c.px[i..<(i + 3)]), [0, 0, 0], "corner \(x),\(y)")
        }
        let centre = ((c.h / 2 + 40) * c.w + c.w / 2) * 4
        XCTAssertGreaterThan(Int(c.px[centre]), Int(c.px[centre + 2]) + 60, "BGRA: blue water in the middle")

        let spoiled = try composited(at: 5.0, points: size) {
            $0.frame = CGRect(x: 400, y: 250, width: size.width - 800, height: size.height - 500)
        }
        XCTAssertGreaterThan(gaps(spoiled.px, spoiled.w, spoiled.h), 1000, "control")
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
