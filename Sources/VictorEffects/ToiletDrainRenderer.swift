import CoreGraphics
import Foundation
import Metal
import QuartzCore

/// 🚽 Draws one frame of `ToiletDrain`, on any Metal texture: the glass in the
/// app, an offscreen target in the tests and nowhere else differently.
///
/// **Why a fragment shader on the GPU**, measured at 3456×2234 on an M5 Max: this
/// pass takes **~0.7 ms** a frame (worst of 240, 1.9 ms) and filling its table
/// 0.03 ms; a bare `CIVortexDistortion` of the same picture takes 3.9–7.3 ms, and has
/// no way to fit a rectangle in a circle and no water. A mesh would crease along
/// the squeeze and cost a rebuild on the CPU every frame.
///
/// What is a function of the radius comes from the frame's table of rings
/// (`ToiletDrain.Row`). The shader adds what depends on the direction, the squeeze
/// (held to `ToiletDrain.source` by a test), and the waves on the water.
final class ToiletDrainRenderer {

    /// Built once, off the main thread (`EmojiAnimator.init`): compiling the shader
    /// takes longer than the clip's first second can spare. Nil with no Metal
    /// device: the clip then plays over an untouched desktop.
    static let shared: ToiletDrainRenderer? = ToiletDrainRenderer()

    static let tableRows = 2048
    /// Frames the GPU may be behind by, each with its own table.
    private static let inFlight = 3

    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let gate = DispatchSemaphore(value: ToiletDrainRenderer.inFlight)
    private let tables: [MTLBuffer]
    private var nextTable = 0
    private let tableLock = NSLock()

    /// The layout of the shader's `Uniforms`.
    private struct Uniforms {
        var size: SIMD2<Float>
        var ringsPerPixel: Float
        var rows: Int32
        var hasPicture: Int32
        var atRest: Int32
        var time: Float
        var chop: Float
        var rim: Float
        var bowl: Float
        var corner: Float
    }

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue(),
              let library = try? device.makeLibrary(source: Self.shader, options: nil),
              let vertex = library.makeFunction(name: "drainVertex"),
              let fragment = library.makeFunction(name: "drainFragment") else { return nil }

        let describe = MTLRenderPipelineDescriptor()
        describe.vertexFunction = vertex
        describe.fragmentFunction = fragment
        describe.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: describe) else { return nil }

        let samples = MTLSamplerDescriptor()
        samples.minFilter = .linear
        samples.magFilter = .linear
        samples.mipFilter = .linear
        // A turned rectangle shows its corners: past the picture's edge is the same
        // black as around the circle, not a repeat of the desktop.
        samples.sAddressMode = .clampToBorderColor
        samples.tAddressMode = .clampToBorderColor
        samples.borderColor = .opaqueBlack
        samples.maxAnisotropy = 8
        guard let sampler = device.makeSamplerState(descriptor: samples) else { return nil }

        let bytes = Self.tableRows * MemoryLayout<ToiletDrain.Row>.stride
        let tables = (0..<Self.inFlight).compactMap { _ in device.makeBuffer(length: bytes, options: .storageModeShared) }
        guard tables.count == Self.inFlight else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.sampler = sampler
        self.tables = tables
    }

    /// The photograph as a texture with its mip chain, on the calling thread (a
    /// few tens of ms at Retina size, so not on the main one).
    ///
    /// **Bytes untouched:** they stay in the image's own colour space, and the
    /// layer is told that space (`ToiletDrainLayer`), so at rest the first frame
    /// is pixel-identical to the desktop it lands on. A conversion here would be a
    /// visible shift the moment the effect begins.
    func texture(from image: CGImage) -> MTLTexture? {
        let w = image.width, h = image.height
        let bytesPerRow = w * 4
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard w > 0, h > 0,
              let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let staging = device.makeBuffer(length: bytesPerRow * h, options: .storageModeShared),
              let context = CGContext(data: staging.contents(), width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: bytesPerRow, space: space, bitmapInfo: info) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        let describe = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h,
                                                                mipmapped: true)
        describe.storageMode = .private
        describe.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: describe),
              let commands = queue.makeCommandBuffer(),
              let blit = commands.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: staging, sourceOffset: 0, sourceBytesPerRow: bytesPerRow, sourceBytesPerImage: bytesPerRow * h,
                  sourceSize: MTLSize(width: w, height: h, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.generateMipmaps(for: texture)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        return texture
    }

    /// Draws the frame `t` seconds into the effect. With no `picture`, a sheet of
    /// water stands in for the photograph. Answers the finished command buffer.
    @discardableResult
    func draw(t: Double, picture: MTLTexture?, into target: MTLTexture,
              present: MTLDrawable? = nil) -> MTLCommandBuffer? {
        gate.wait()
        // A re-press can have the old run's last frame and the new run's first
        // here together: they must not share a table.
        tableLock.lock()
        let table = tables[nextTable]
        nextTable = (nextTable + 1) % tables.count
        tableLock.unlock()

        let geometry = ToiletDrain.Geometry(width: Double(target.width), height: Double(target.height))
        // A ring past the corner never lands on a pixel.
        let step = geometry.reach * 1.01 / Double(Self.tableRows - 1)
        let rows = UnsafeMutableBufferPointer(start: table.contents().assumingMemoryBound(to: ToiletDrain.Row.self),
                                              count: Self.tableRows)
        ToiletDrain.fill(rows, step: step, t: t, geometry: geometry, picture: picture != nil)

        // Before the valve the warp is the identity, and the sampler would still
        // wander a hair off the texels and into the next mip on a hard edge. The
        // photograph is read straight, so it lands on the desktop to the byte.
        let atRest = t <= ToiletDrain.valve && picture?.width == target.width && picture?.height == target.height
        var uniforms = Uniforms(size: SIMD2(Float(target.width), Float(target.height)),
                                ringsPerPixel: Float(1 / step),
                                rows: Int32(Self.tableRows),
                                hasPicture: picture == nil ? 0 : 1,
                                atRest: atRest ? 1 : 0,
                                time: Float(t),
                                chop: Float(ToiletDrain.chop(t)),
                                rim: Float(ToiletDrain.radius(t, geometry)),
                                bowl: Float(geometry.bowl),
                                corner: Float(ToiletDrain.cornerPower))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        guard let commands = queue.makeCommandBuffer(),
              let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { gate.signal(); return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        encoder.setFragmentBuffer(table, offset: 0, index: 1)
        encoder.setFragmentTexture(picture, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let present { commands.present(present) }
        commands.addCompletedHandler { [gate] _ in gate.signal() }
        commands.commit()
        return commands
    }

    private static let shader = """
    #include <metal_stdlib>
    using namespace metal;

    struct Row { float4 warp; float4 wash; };
    struct Uniforms { float2 size; float ringsPerPixel; int rows; int hasPicture; int atRest;
                      float time; float chop; float rim; float bowl; float corner; };

    vertex float4 drainVertex(uint id [[vertex_id]]) {
        float2 p = float2((id << 1) & 2, id & 2);
        return float4(p * 2 - 1, 0, 1);
    }

    /// The water at `p` px from the centre, in units of the bowl: circular ripples
    /// from a few points scattered over it, interfering. Straight waves crossing at
    /// fixed angles would weave a plaid; a bowl's waves are rounds. Lit by their
    /// slope, `ring` being what a ring wave adds along `out`. `patch` is their height
    /// before `chop`.
    static float3 sea(float2 p, float bowl, float time, float chop, float2 out, float ring, thread float& patch) {
        const float4 drops[6] = {
            float4(-0.62,  0.38, 17.0, 5.3), float4( 0.71, -0.27, 23.0, 6.1), float4( 0.19,  0.83, 29.0, 7.3),
            float4(-0.33, -0.91, 37.0, 8.9), float4( 1.37,  0.74, 13.0, 4.1), float4(-1.21, -0.58, 47.0, 10.7),
        };
        float2 unit = p / bowl;
        float rise = 0;
        float2 slope = 0;
        for (int i = 0; i < 6; i++) {
            float2 from = unit - drops[i].xy;
            float away = length(from) + 0.001;
            float phase = drops[i].z * away - drops[i].w * time;
            float height = 0.34 / (1.0 + float(i) * 0.25);
            rise += height * sin(phase);
            slope += height * cos(phase) * drops[i].z * 0.035 * from / away;
        }
        patch = rise;
        slope = slope * chop + out * ring;
        float towards = dot(slope, float2(0.55, -0.83));
        float3 colour = mix(float3(0.02, 0.16, 0.46), float3(0.08, 0.40, 0.80), saturate(0.5 + 0.10 * rise * chop + 0.55 * towards));
        return colour + 0.70 * pow(saturate(0.46 + 0.42 * towards), 10.0) * float3(0.80, 0.92, 1.0);
    }

    fragment float4 drainFragment(float4 position [[position]],
                                  constant Uniforms& u [[buffer(0)]],
                                  constant Row* table [[buffer(1)]],
                                  texture2d<float> picture [[texture(0)]],
                                  sampler filter [[sampler(0)]]) {
        if (u.atRest != 0) { return float4(picture.read(uint2(position.xy)).rgb, 1); }

        float2 p = position.xy - u.size * 0.5;
        float r = length(p);
        float at = clamp(r * u.ringsPerPixel, 0.0, float(u.rows) - 1.001);
        int below = int(at);
        float part = at - float(below);
        constant Row& a = table[below];
        constant Row& b = table[below + 1];
        float4 warp = mix(a.warp, b.warp, part);
        float4 wash = mix(a.wash, b.wash, part);
        float alpha = wash.y;
        if (warp.y <= 0.0) { return float4(0, 0, 0, alpha); }

        float2 z = r > 0.001 ? p / r : float2(1, 0);
        float c = cos(warp.x), s = sin(warp.x);
        float2 turned = float2(z.x * c - z.y * s, z.x * s + z.y * c);

        // `ToiletDrain.extent` and `squeeze`: the edge of what can be seen this way,
        // the circle or the screen, lands on the picture's edge.
        float2 half_size = u.size * 0.5;
        float2 across = pow(abs(turned) / half_size, float2(u.corner));
        float2 screen = pow(abs(z) / half_size, float2(u.corner));
        float extent = pow(across.x + across.y, -1.0 / u.corner);
        float visible = min(u.rim, pow(screen.x + screen.y, -1.0 / u.corner));
        float2 q = turned * r * extent / visible;

        float patch;
        float3 water = sea(p, u.bowl, u.time, u.chop, z, warp.w, patch);
        float flood = smoothstep(0.12, 0.88, wash.x + 0.12 * patch);

        float3 colour = water;
        if (u.hasPicture != 0 && flood < 1.0) {
            colour = mix(picture.sample(filter, (q + half_size) / u.size).rgb, water, flood);
        }

        // The bowl's side, all of it inside the rim: the water deepens against the
        // wall and catches the light on the far side. Only on water, so the
        // picture's edge stays the picture's.
        float light = saturate(dot(z, float2(-0.5, 0.87)));
        float wall = warp.z * flood;
        colour *= 1.0 - 0.55 * wall * wall;
        colour += 0.30 * wall * wall * wall * light * light * float3(0.75, 0.90, 1.0);

        return float4(saturate(colour) * warp.y * alpha, alpha);
    }
    """
}

/// The glass end of the renderer: a transparent Metal layer on the overlay that
/// draws itself on its own thread, so nothing on the main thread can put a
/// stutter into the whirlpool.
///
/// **Every frame is computed from the clock**, never from the last frame, so a
/// late one is a skipped moment and not a slower flush, and the picture stays on
/// the clip. The loop is paced by `nextDrawable`, which waits for the display at
/// whatever rate the panel runs.
///
/// **It cannot outlive what owns it.** `removeFromSuperlayer` stops the loop, so
/// the paths that end an effect (`trackEffect`'s timer, a stop-all, a suspend, a
/// re-press) need to know nothing about threads; and the loop ends by itself at
/// the end of the clip if none of them ever comes.
final class ToiletDrainLayer: CAMetalLayer {

    private let run = RunState()
    private var rolling = false

    /// Shared between main and the render thread.
    private final class RunState: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        private var drawn = 0
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        func frameDrawn() { lock.lock(); drawn += 1; lock.unlock() }
        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
        var frames: Int { lock.lock(); defer { lock.unlock() }; return drawn }
    }

    var isStopped: Bool { run.isStopped }
    var framesDrawn: Int { run.frames }

    override func removeFromSuperlayer() {
        run.stop()
        super.removeFromSuperlayer()
    }

    /// Shapes the layer for `slice`-sized glass at `scale`.
    func fit(_ frame: CGRect, scale: CGFloat, device: MTLDevice) {
        self.frame = frame
        self.device = device
        contentsScale = scale
        pixelFormat = .bgra8Unorm
        isOpaque = false
        drawableSize = CGSize(width: frame.width * scale, height: frame.height * scale)
    }

    /// Starts the frames, the first one whatever the clock says now: `clock0` is
    /// the moment the clip is heard from, and a capture that took its time simply
    /// joins the flush a little way in. With a `picture`, `space` is its colour
    /// space, so the frames at rest come out as the desktop they cover.
    func roll(with renderer: ToiletDrainRenderer, picture: MTLTexture?, space: CGColorSpace?, clock0: CFTimeInterval) {
        guard !rolling, !isStopped else { return }
        rolling = true
        if let space { colorspace = space }
        let thread = Thread { [self, run] in
            while !run.isStopped {
                let t = CACurrentMediaTime() - clock0
                if t < 0 { Thread.sleep(forTimeInterval: min(-t, 0.005)); continue }
                let last = t >= ToiletDrain.fadeEnds
                autoreleasepool {
                    guard let drawable = nextDrawable() else { return }
                    renderer.draw(t: last ? ToiletDrain.fadeEnds : t, picture: picture,
                                  into: drawable.texture, present: drawable)
                    run.frameDrawn()
                }
                if last { break }
                // A layer no window is showing hands drawables back at once.
                Thread.sleep(forTimeInterval: 0.002)
            }
        }
        thread.name = "toilet-flush"
        thread.qualityOfService = .userInteractive
        thread.start()
    }
}
