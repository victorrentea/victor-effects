import AppKit
import Foundation

/// 🙏 Pray — the whip's polite sibling (2026-10-19, Victor: *"another feature
/// called pray instead of whip … displays [a praying man] … appearing instead
/// of the whip. And I click to play some short clip of a religious hymn"*).
///
/// While active:
///   • a man with his hands together follows the cursor where the rope would,
///   • a **click** plays a few seconds of a hymn (`pray-hymn.mp3`) and lights a
///     golden glow behind him for as long as it sings — nothing is typed, this
///     is the gesture that ASKS the agent, the whip's click is the one that
///     tells it,
///   • Esc, ⌃⇧W again, the menu row or stop-all dismisses it.
///
/// **Exclusive with the whip**: `EffectsEngine.togglePray` puts the whip away
/// and `toggleWhip` puts him away — one mode at a time under the pointer.
///
/// The same window and geometry as the whip — `WhipPanel` (the level fix
/// included), `ZoomedPanel` every frame — so he keeps his size under ⌥-scroll.
final class PrayController {

    /// Called when the user presses Esc.
    var onEscape: (() -> Void)?

    private var panel: WhipPanel?
    private var view: PrayView?
    private var displayTimer: Timer?
    private var screenFrame: NSRect = .zero
    private var screen: NSScreen?
    private var appliedVisible: CGRect = .zero

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    /// The hymn rides the tablet's volume wedge like the whip's crack, a bit
    /// under it: it is a punchline, not a concert.
    static let hymn = "pray-hymn.mp3"
    static let hymnVolumeFactor: Float = 0.8
    /// How long the glow stays lit after a click — the length of the excerpt
    /// in `assetsDir` (8 s, with its own fade-out over the last 1.2 s).
    static let singMs = 8000.0

    var isShowing: Bool { panel != nil }

    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000.0 }

    // MARK: - Show / hide

    func show() {
        guard panel == nil else { return }

        let screen = screenUnderMouse()
        self.screen = screen
        screenFrame = screen.frame

        let p = WhipPanel(screenFrame: screenFrame)
        let v = PrayView(frame: NSRect(origin: .zero, size: screenFrame.size))
        v.figure = Self.loadFigure()
        v.onMouseDown = { [weak self] in self?.sing() }
        p.contentView = v
        appliedVisible = .null
        placeForZoom(p)
        v.at = viewPoint(forGlobal: VisibleCursor.location)

        panel = p
        view = v
        p.orderFrontRegardless()

        // The hymn may start at any click; keep the A2DP link warm so it does
        // not arrive a beat after the glow (no-op off Bluetooth).
        BluetoothOutput.startContinuousWarm()

        installEscMonitors()
        startTimer()
    }

    func hide() {
        displayTimer?.invalidate()
        displayTimer = nil
        removeEscMonitors()
        if view?.singingSinceMs != nil {
            SoundManager.shared.stopOverlapping(Self.hymn, fade: SoundManager.interruptFade)
        }
        BluetoothOutput.stopContinuousWarm()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        screen = nil
    }

    /// The cut-out from `assetsDir`, or nil — then the view draws a 🙏 and the
    /// mode still works (`docs/assets-and-licences.md`: degrade quietly).
    private static func loadFigure() -> NSImage? {
        guard let url = EffectsResources.url("praying-man", "png"),
              let image = NSImage(contentsOf: url) else {
            effectsInfo("🙏 praying-man.png not in assetsDir — drawing 🙏 instead")
            return nil
        }
        return image
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
        let now = nowMs()
        // Eased, not glued: he drifts after the pointer, which reads as a
        // person following rather than a cursor image.
        let target = viewPoint(forGlobal: VisibleCursor.location)
        view.at = CGPoint(x: view.at.x + (target.x - view.at.x) * Self.follow,
                          y: view.at.y + (target.y - view.at.y) * Self.follow)
        if let since = view.singingSinceMs, now - since > Self.singMs { view.singingSinceMs = nil }
        view.nowMs = now
        view.needsDisplay = true
    }

    static let follow: CGFloat = 0.35

    // MARK: - Input

    /// A click sings, from the top — a second click mid-hymn starts it over
    /// rather than stacking a second choir on the first. Also
    /// `/effect/pray/sing`, so the click can be checked without a mouse.
    func sing() {
        guard let view else { return }
        SoundManager.shared.stopOverlapping(Self.hymn)
        let volume = SoundManager.shared.currentTabletVolume * Self.hymnVolumeFactor
        SoundManager.shared.playOverlapping(Self.hymn, volume: volume, bluetoothCompensated: false)
        view.singingSinceMs = nowMs()
        effectsInfo("🙏 pray — hymn")
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

// MARK: - View

/// The man, centred on the pointer, breathing slowly; while the hymn sings, a
/// golden glow behind him and a ray of light falling on him from the top of
/// the screen, both easing in and out. (A halo over his head came first and
/// went on 2026-10-20 — Victor: *"a ray of light … falling from the sky,
/// rather than this angelic circle on top of my head"*.)
private final class PrayView: NSView {

    var figure: NSImage?
    var at: CGPoint = .zero
    var nowMs = 0.0
    var singingSinceMs: Double?
    var onMouseDown: (() -> Void)?

    static let figureHeight: CGFloat = 200
    static let glowColor = NSColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
    static let beamColor = NSColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1)
    /// How long the ray takes to come down from the top edge to him.
    static let beamFallMs = 450.0

    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    /// 0…1: up over the first half second of the hymn, down over its last
    /// second, nothing while silent.
    private var glow: CGFloat {
        guard let since = singingSinceMs else { return 0 }
        let t = nowMs - since
        let up = min(1, t / 500)
        let down = min(1, max(0, (PrayController.singMs - t) / 1000))
        return CGFloat(min(up, down))
    }

    override func draw(_ dirtyRect: NSRect) {
        let breathe = 1 + 0.02 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 3.2))
        let h = Self.figureHeight * breathe
        let aspect = figure.map { $0.size.width / max(1, $0.size.height) } ?? 1
        let w = h * aspect
        let rect = CGRect(x: at.x - w / 2, y: at.y - h / 2, width: w, height: h)

        let g = glow
        if g > 0, let ctx = NSGraphicsContext.current?.cgContext {
            drawBeam(ctx, onto: rect, strength: g)
            let pulse = 1 + 0.06 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 1.6))
            let radius = h * 0.85 * pulse
            let colors = [Self.glowColor.withAlphaComponent(0.75 * g).cgColor,
                          Self.glowColor.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: at.x, y: at.y - h * 0.1)
                ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: radius, options: [])
            }
        }

        if let figure {
            figure.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            let str = NSAttributedString(string: "🙏", attributes: [.font: NSFont.systemFont(ofSize: h * 0.7)])
            let s = str.size()
            str.draw(at: CGPoint(x: at.x - s.width / 2, y: at.y - s.height / 2))
        }
    }

    /// A ray from the top of the screen down onto him: narrow up there, wider
    /// than him where it lands, drawn BEHIND him so his outline sits in it.
    /// Three nested passes, the widest the faintest, stand in for a soft edge;
    /// it falls from the top in `beamFallMs` and shimmers slightly while lit.
    /// It follows him as he follows the pointer — the light is on him, not on
    /// a spot of the screen.
    private func drawBeam(_ ctx: CGContext, onto rect: CGRect, strength g: CGFloat) {
        guard let since = singingSinceMs, rect.maxY > 0 else { return }
        let f = CGFloat(min(1, (nowMs - since) / Self.beamFallMs))
        let land = rect.maxY - rect.height * 0.15
        let reach = land * (1 - (1 - f) * (1 - f))          // ease-out
        guard reach > 1 else { return }
        let shimmer = 1 + 0.08 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 0.9))
        let topW = rect.width * 0.4, landW = rect.width * 1.3
        let space = CGColorSpaceCreateDeviceRGB()
        for (k, a) in [(CGFloat(1.0), CGFloat(0.16)), (0.7, 0.2), (0.4, 0.28)] {
            let tw = topW * k
            let bw = tw + (landW * k - tw) * (reach / land)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: at.x - tw / 2, y: 0))
            path.addLine(to: CGPoint(x: at.x + tw / 2, y: 0))
            path.addLine(to: CGPoint(x: at.x + bw / 2, y: reach))
            path.addLine(to: CGPoint(x: at.x - bw / 2, y: reach))
            path.closeSubpath()
            let alpha = a * g * shimmer
            let colors = [Self.beamColor.withAlphaComponent(alpha * 0.7).cgColor,
                          Self.beamColor.withAlphaComponent(alpha).cgColor,
                          Self.beamColor.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.8, 1]) else { continue }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: CGPoint(x: at.x, y: 0), end: CGPoint(x: at.x, y: reach), options: [])
            ctx.restoreGState()
        }
    }
}
