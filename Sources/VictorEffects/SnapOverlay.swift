import AppKit
import Foundation
import ImageIO

/// 🫰 Snap — the whip's third mode (2026-10-20, Victor: *"another way to whip …
/// a snap of the fingers … an animated transparent GIF … and on click it
/// actually snaps, a hand snapping its fingers"*).
///
/// While active:
///   • a hand, thumb pressed to the middle finger, IS the pointer — glued to
///     it by the fingertips (`hotspot`), the real arrow hidden,
///   • a **click** snaps: the frames after the first play once (the hand goes
///     black, then white, then lands with the finger down on the palm), a snap
///     is heard, a few short lines fly off the fingertips — and the hand is
///     back to ready. Clicking again mid-snap starts it over. Nothing is typed,
///   • Esc, ⌃W, the menu row or stop-all dismisses it; ⌃⇧W moves on to the whip.
///
/// The same window and geometry as the whip and 🙏 pray — `WhipPanel`,
/// `ZoomedPanel` every frame — so it keeps its size under ⌥-scroll.
final class SnapController {

    /// Called when the user presses Esc.
    var onEscape: (() -> Void)?
    /// Every snap: 🦀 Clawd turns cool.
    var onSnap: (() -> Void)?

    private var panel: WhipPanel?
    private var view: SnapView?
    private var displayTimer: Timer?
    private var screenFrame: NSRect = .zero
    private var screen: NSScreen?
    private var appliedVisible: CGRect = .zero
    private var cursorHide: CursorHide?

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    /// A photo, so three takes of the same snap rather than one played over
    /// and over: a room hears a repeated sample long before it sees one.
    static let sounds = ["finger-snap-1.mp3", "finger-snap-2.mp3", "finger-snap-3.mp3"]
    /// A snap is quieter than a crack; at the whip's 0.64 it sounded like a
    /// second whip.
    static let volumeFactor: Float = 0.8

    var isShowing: Bool { panel != nil }

    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000.0 }

    // MARK: - Show / hide

    func show() {
        guard panel == nil else { return }

        let screen = screenUnderMouse()
        self.screen = screen
        screenFrame = screen.frame

        let p = WhipPanel(screenFrame: screenFrame)
        let v = SnapView(frame: NSRect(origin: .zero, size: screenFrame.size))
        v.frames = SnapFrames.load()
        v.onMouseDown = { [weak self] in self?.snap() }
        p.contentView = v
        appliedVisible = .null
        placeForZoom(p)
        v.at = viewPoint(forGlobal: VisibleCursor.location)

        panel = p
        view = v
        p.orderFrontRegardless()
        cursorHide = CursorHide()

        // A snap answers a click; keep the A2DP link warm so it is not heard
        // a beat after it is seen (no-op off Bluetooth).
        BluetoothOutput.startContinuousWarm()

        installEscMonitors()
        startTimer()
    }

    func hide() {
        displayTimer?.invalidate()
        displayTimer = nil
        removeEscMonitors()
        BluetoothOutput.stopContinuousWarm()
        cursorHide?.release()
        cursorHide = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
        screen = nil
    }

    // MARK: - Frame loop

    private func startTimer() {
        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        displayTimer = t
    }

    @objc private func tick() {
        guard let view else { return }
        if let panel { placeForZoom(panel) }
        cursorHide?.reassertNearEdge(pointer: VisibleCursor.location, screen: screenFrame)
        // Glued, not eased: this hand is the pointer, and a snap has to land
        // where the click was.
        view.at = viewPoint(forGlobal: VisibleCursor.location)
        view.nowMs = nowMs()
        view.needsDisplay = true
    }

    // MARK: - Input

    /// A click: play the snap from its first moving frame, with a sound. Also
    /// `/effect/snap/click`, so the click can be checked without a mouse.
    func snap() {
        guard let view else { return }
        view.snappedAtMs = nowMs()
        view.needsDisplay = true
        onSnap?()
        guard let sound = Self.sounds.randomElement() else { return }
        SoundManager.shared.playOverlapping(
            sound, volume: SoundManager.shared.currentTabletVolume * Self.volumeFactor,
            bluetoothCompensated: false)
        effectsInfo("🫰 snap (\(sound))")
    }

    private func installEscMonitors() {
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Esc
                DispatchQueue.main.async { self?.onEscape?() }
            }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onEscape?()
                return nil
            }
            return event
        }
    }

    private func removeEscMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
    }

    // MARK: - Geometry (the whip's, verbatim)

    private func screenUnderMouse() -> NSScreen {
        let loc = VisibleCursor.location
        return NSScreen.screens.first { $0.frame.contains(loc) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    private func viewPoint(forGlobal g: NSPoint) -> CGPoint {
        WhipController.viewPoint(forGlobal: g, screen: screenFrame, visible: appliedVisible)
    }

    private func placeForZoom(_ panel: NSPanel) {
        let slice = ZoomedPanel.visible(on: screen, fallback: screenFrame)
        guard slice != appliedVisible else { return }
        appliedVisible = slice
        ZoomedPanel.apply(panel,
                          frame: ZoomedPanel.frame(design: screenFrame, screen: screenFrame, visible: slice),
                          designSize: screenFrame.size)
    }
}

// MARK: - Frames

/// The snapping hand, as frames with their delays — pure, so the timing can be
/// tested without a screen.
///
/// **Frame 0 is the hand at rest**, the one that follows the pointer; a click
/// plays every frame after it once, each for its own delay, then rests again.
/// `finger-snap.gif` in `assetsDir` wins over the shipped `finger-snap.png`
/// (an APNG: a GIF has one bit of alpha, and a photographed hand cut out at one
/// bit has a jagged rim on any dark desktop), so a nicer animation can be
/// dropped in without a build — as long as it keeps that frame-0 rule.
struct SnapFrames {
    var images: [CGImage]
    /// Per frame, in ms. Frame 0's own delay is never used.
    var delaysMs: [Double]

    /// How long one snap runs, from the click back to rest.
    var snapMs: Double { delaysMs.dropFirst().reduce(0, +) }

    /// The frame to draw `sinceSnapMs` after a click — nil when not snapping
    /// (rest, frame 0).
    func frameIndex(sinceSnapMs t: Double?) -> Int {
        guard let t, t >= 0, images.count > 1 else { return 0 }
        var end = 0.0
        for i in 1..<images.count {
            end += delaysMs[i]
            if t < end { return i }
        }
        return 0
    }

    static func load() -> SnapFrames? {
        guard let url = EffectsResources.url("finger-snap", "gif") ?? EffectsResources.url("finger-snap", "png") else {
            effectsInfo("🫰 finger-snap not found — drawing 🫰 instead")
            return nil
        }
        return load(url)
    }

    static func load(_ url: URL) -> SnapFrames? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        var images: [CGImage] = []
        var delays: [Double] = []
        for i in 0..<CGImageSourceGetCount(source) {
            guard let image = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(image)
            delays.append(delayMs(source, i))
        }
        return images.isEmpty ? nil : SnapFrames(images: images, delaysMs: delays)
    }

    /// GIF or APNG, unclamped first: ImageIO clamps anything under 100 ms to
    /// 100 ms in the plain key, and the impact frames are 50–60 ms.
    private static func delayMs(_ source: CGImageSource, _ i: Int) -> Double {
        let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
        for (dict, keys) in [
            (kCGImagePropertyGIFDictionary, [kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime]),
            (kCGImagePropertyPNGDictionary, [kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime]),
        ] {
            guard let d = props?[dict] as? [CFString: Any] else { continue }
            for key in keys {
                if let s = (d[key] as? NSNumber)?.doubleValue, s > 0 { return s * 1000 }
            }
        }
        return 100
    }
}

// MARK: - View

/// The hand, placed by its fingertips on the pointer, and on a click the snap
/// frames plus a few short white lines thrown off the fingertips.
private final class SnapView: NSView {

    var frames: SnapFrames?
    var at: CGPoint = .zero
    var nowMs = 0.0
    var snappedAtMs: Double?
    var onMouseDown: (() -> Void)?

    /// 340 since 2026-10-30 (was 170): Victor wanted the snap twice as big.
    /// The burst and the emoji fallback scale with it (`scale`).
    static let handHeight: CGFloat = 340
    static let scale: CGFloat = handHeight / 170
    /// Where thumb meets middle finger in the rest frame, in unit coordinates
    /// of the picture (y down) — the point that sits on the pointer. Measured
    /// on the shipped 370×520 cut-out; a dropped-in GIF is placed by it too.
    static let hotspot = CGPoint(x: 0.16, y: 0.20)
    /// The lines off the fingertips: how many, and how long they live.
    static let burstLines = 9
    static let burstMs = 320.0

    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let since = snappedAtMs.map { nowMs - $0 }

        guard let frames else {
            let pop = since.map { $0 < 200 ? 1.25 - 0.25 * $0 / 200 : 1 } ?? 1
            let str = NSAttributedString(string: "🫰", attributes: [.font: NSFont.systemFont(ofSize: 64 * Self.scale * pop)])
            let s = str.size()
            str.draw(at: CGPoint(x: at.x - s.width / 2, y: at.y - s.height / 2))
            drawBurst(ctx, since: since)
            return
        }
        let image = frames.images[frames.frameIndex(sinceSnapMs: since)]
        // Every frame in the size of the first, so a cropped frame in a
        // dropped-in GIF cannot make the hand jump.
        let first = frames.images[0]
        let h = Self.handHeight
        let w = h * CGFloat(first.width) / CGFloat(max(1, first.height))
        let rect = CGRect(x: at.x - w * Self.hotspot.x, y: at.y - h * Self.hotspot.y, width: w, height: h)
        ctx.saveGState()
        ctx.interpolationQuality = .high
        // CGContext draws y-up; this view is flipped.
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: w, height: h))
        ctx.restoreGState()
        drawBurst(ctx, since: since)
    }

    /// Short strokes flying out of the fingertips, the comic "snap!" — up and
    /// to the left mostly, away from the hand.
    private func drawBurst(_ ctx: CGContext, since: Double?) {
        guard let since, since >= 0, since < Self.burstMs else { return }
        let f = CGFloat(since / Self.burstMs)
        let ease = 1 - (1 - f) * (1 - f)
        ctx.saveGState()
        ctx.setLineCap(.round)
        ctx.setLineWidth(3.5 * Self.scale)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(1 - f).cgColor)
        ctx.setShadow(offset: .zero, blur: 3, color: NSColor.black.withAlphaComponent(0.6 * (1 - f)).cgColor)
        for k in 0..<Self.burstLines {
            // A fan from straight left (π) round to straight up (1.5π), wider
            // than the hand leaves room for.
            let a = CGFloat.pi * (0.85 + 0.8 * CGFloat(k) / CGFloat(Self.burstLines - 1))
            let r0 = (16 + 30 * ease) * Self.scale, r1 = r0 + (18 * (1 - f) + 6) * Self.scale
            ctx.move(to: CGPoint(x: at.x + cos(a) * r0, y: at.y + sin(a) * r0))
            ctx.addLine(to: CGPoint(x: at.x + cos(a) * r1, y: at.y + sin(a) * r1))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }
}
