import AppKit
import AVFoundation
import Foundation

/// 🙏 Pray — the whip's polite sibling (2026-10-19, Victor: *"another feature
/// called pray instead of whip … displays [a praying man] … appearing instead
/// of the whip. And I click to play some short clip of a religious hymn"*).
///
/// While active:
///   • only his two hands, joined, follow the cursor where the rope would, and
///     the real arrow is hidden (2026-10-20, Victor: *"instead of the man
///     praying just … his two hands"*),
///   • a **click** leaves a man praying on that spot: the hands stay there, the
///     rest of him fades in around them, and a beat later a ray of light falls
///     from the sky onto him, with a golden glow; 9.5 s later he fades away.
///     The pointer keeps a fresh pair of hands, so more clicks plant more men
///     (2026-10-20, Victor: *"I can click multiple times to put multiple people
///     praying"*). ONE Ave Maria sings for all of them — a later click does not
///     restart it or add a second voice, it only pushes its end out to that
///     man's end. Nothing is typed — this is the gesture that ASKS the agent,
///     the whip's click is the one that tells it,
///   • Esc, the menu row or stop-all dismisses it; ⌃W moves on to 🫰 snap
///     (it cycles whip → pray → snap since 2026-10-20; ⌃⇧W was his key for a day).
///
/// **Exclusive with the whip and 🫰 snap**: every `EffectsEngine.toggle…` puts
/// the other modes away — one mode at a time under the pointer.
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
    private var cursorHide: CursorHide?

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    private var choir = PrayChoir()
    /// The one hymn all the planted men share. Our own player, not
    /// `playOverlapping`: a later click has to reach THIS voice to push its
    /// end out (or take back a fade already under way), and a by-name stop
    /// would hit any other copy.
    private var hymnPlayer: AVAudioPlayer?
    private var hymnFading = false

    /// The hymn rides the tablet's volume wedge like the whip's crack, a bit
    /// under it: it is a punchline, not a concert. A long take of the Ave
    /// Maria, so a few clicks in a row only ever stretch it. First choice is
    /// the very recording the tablet's `09_ave_maria.mp3` was cut from
    /// (2026-10-21, Victor: *"find exactly that melody"*), a drop-in, as it may
    /// not be published; then the shipped CC BY take — the same Schubert, but
    /// another singer, and the room hears the difference; then the old 9.5 s
    /// cut, which simply ends early.
    static let tabletHymn = "pray-hymn-tablet.mp3"
    static let hymn = "pray-hymn-long.mp3"
    static let shortHymn = "pray-hymn.mp3"
    static let hymnVolumeFactor: Float = 0.8
    /// The hymn fades to silence over this long, ending as the last man does.
    static let hymnFadeMs = 1200.0
    /// How long one man prays, from his click to gone (9.5 s since
    /// 2026-10-20, was 8 — Victor: *"prolong a bit the Ave Maria … 10–20%
    /// more"*).
    static let singMs = 9500.0
    /// The man fades in around his hands over this long after a click…
    static let manFadeInMs = 800.0
    /// …and the light starts to fall once he is there, a beat later.
    static let lightDelayMs = 1500.0
    /// Man, ray and glow all fade out together over the clip's last second.
    static let fadeOutMs = 1000.0

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
        cursorHide = CursorHide()

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
        if let player = hymnPlayer {
            player.setVolume(0, fadeDuration: SoundManager.interruptFade)
            DispatchQueue.main.asyncAfter(deadline: .now() + SoundManager.interruptFade + 0.05) { player.stop() }
        }
        hymnPlayer = nil
        hymnFading = false
        choir.clear()
        BluetoothOutput.stopContinuousWarm()
        cursorHide?.release()
        cursorHide = nil
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
        cursorHide?.reassertNearEdge(pointer: VisibleCursor.location, screen: screenFrame)
        let now = nowMs()
        // Eased, not glued: he drifts after the pointer, which reads as a
        // person following rather than a cursor image.
        let target = viewPoint(forGlobal: VisibleCursor.location)
        view.at = CGPoint(x: view.at.x + (target.x - view.at.x) * Self.follow,
                          y: view.at.y + (target.y - view.at.y) * Self.follow)
        choir.expire(nowMs: now)
        view.prayers = choir.prayers
        steerHymn(now: now)
        view.nowMs = now
        view.needsDisplay = true
    }

    static let follow: CGFloat = 0.35

    // MARK: - Input

    /// A click plants a man where the hands are and starts the hymn — or, if
    /// it is already singing, lets it run on until he is done too (and takes
    /// back a fade that had begun). Also `/effect/pray/sing`, so the click can
    /// be checked without a mouse.
    func sing() {
        guard let view else { return }
        choir.plant(at: view.at, nowMs: nowMs())
        view.prayers = choir.prayers
        let level = max(0, min(1, SoundManager.shared.currentTabletVolume * Self.hymnVolumeFactor))
        if let player = hymnPlayer, player.isPlaying {
            if hymnFading {
                player.setVolume(level, fadeDuration: 0.3)
                hymnFading = false
            }
            effectsInfo("🙏 pray — \(choir.prayers.count) praying, the hymn runs on")
            return
        }
        hymnPlayer?.stop()
        hymnPlayer = nil
        hymnFading = false
        let sounds = SoundManager.shared
        guard let url = sounds.soundURL(for: Self.tabletHymn) ?? sounds.soundURL(for: Self.hymn)
                ?? sounds.soundURL(for: Self.shortHymn) else {
            effectsInfo("🙏 \(Self.hymn) not in assetsDir — the light falls in silence")
            return
        }
        do {
            let player = try SoundManager.player(contentsOf: url)
            player.volume = level
            player.prepareToPlay()
            player.play()
            hymnPlayer = player
            effectsInfo("🙏 pray — hymn (\(url.lastPathComponent))")
        } catch {
            overlayError("🙏 hymn failed: \(error)")
        }
    }

    /// Every frame: fade the hymn out so it falls silent as the last man
    /// goes, and let go of it once nobody is left.
    private func steerHymn(now: Double) {
        guard let player = hymnPlayer else { return }
        guard let end = choir.endMs, let fadeAt = choir.fadeStartMs else {
            player.stop()
            hymnPlayer = nil
            hymnFading = false
            return
        }
        if !hymnFading, now >= fadeAt {
            player.setVolume(0, fadeDuration: max(0.05, (end - now) / 1000))
            hymnFading = true
        }
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

// MARK: - Choir

/// Who is praying where, and until when — pure, so the timing can be tested
/// without a screen or a speaker. Kept in click order, so the last one is the
/// one the hymn has to last for.
struct PrayChoir {
    struct Prayer: Equatable {
        /// Where his hands were when clicked, in view points.
        var at: CGPoint
        var sinceMs: Double
    }

    /// More than this and the oldest goes — a punchline, not a congregation.
    static let maxPrayers = 8

    private(set) var prayers: [Prayer] = []

    mutating func plant(at: CGPoint, nowMs: Double) {
        prayers.append(Prayer(at: at, sinceMs: nowMs))
        if prayers.count > Self.maxPrayers { prayers.removeFirst() }
    }

    mutating func expire(nowMs: Double) {
        prayers.removeAll { nowMs - $0.sinceMs > PrayController.singMs }
    }

    mutating func clear() { prayers.removeAll() }

    /// When the last of them is done — when the hymn must be silent.
    var endMs: Double? { prayers.last.map { $0.sinceMs + PrayController.singMs } }
    /// When the hymn starts fading so that it reaches silence at `endMs`.
    var fadeStartMs: Double? { endMs.map { $0 - PrayController.hymnFadeMs } }
}

// MARK: - View

/// His joined hands, centred on the pointer, breathing slowly. A click leaves
/// a man on that spot: the rest of him fades in around the hands, then a ray
/// of light falls on him from the top of the screen with a golden glow behind
/// him, and all of him eases out together 9.5 s after his click. Each planted
/// man runs on his own clock; the pointer's hands are drawn over them all. (A halo over his head came first and went on
/// 2026-10-20 — Victor: *"a ray of light … falling from the sky, rather than
/// this angelic circle on top of my head"*.)
///
/// The hands are not a second picture: they are the same figure drawn through
/// `handsOutline`, on top of the whole man at full opacity, so as he fades in
/// they are the very pixels he grows around — no seam, no jump.
private final class PrayView: NSView {

    var figure: NSImage?
    var at: CGPoint = .zero
    var nowMs = 0.0
    var prayers: [PrayChoir.Prayer] = []
    var onMouseDown: (() -> Void)?

    static let figureHeight: CGFloat = 200
    static let glowColor = NSColor(red: 1.0, green: 0.84, blue: 0.35, alpha: 1)
    static let beamColor = NSColor(red: 1.0, green: 0.96, blue: 0.78, alpha: 1)
    /// How long the ray takes to come down from the top edge to him — three
    /// times the first 450 ms (Victor, 2026-10-20: *"three times slower"*).
    static let beamFallMs = 1350.0
    /// The glow on him comes up only once the ray has landed, and slower
    /// still than the ray fell.
    static let glowUpMs = 2000.0
    /// The ray comes in from up and to the LEFT, not straight down (Victor,
    /// 2026-10-20: *"slightly from the left up"*) — this many degrees off
    /// the vertical, its source sliding left the further he is from the top.
    static let beamTiltDegrees: CGFloat = 18
    /// The joined hands in `praying-man.png`, in unit coordinates of the
    /// picture (y down): fingertips under his nose, down to the wrists. Traced
    /// on the 265×324 cut-out; a different picture needs a new trace.
    static let handsOutline: [CGPoint] = [
        (0.502, 0.343), (0.536, 0.340), (0.558, 0.370), (0.592, 0.432), (0.626, 0.509),
        (0.645, 0.602), (0.645, 0.685), (0.604, 0.710), (0.528, 0.719), (0.445, 0.710),
        (0.408, 0.685), (0.408, 0.602), (0.426, 0.509), (0.460, 0.432), (0.483, 0.370),
    ].map { CGPoint(x: $0.0, y: $0.1) }
    /// The middle of `handsOutline` — the point that sits on the pointer.
    static let handsCentre = CGPoint(x: 0.527, y: 0.53)

    override var isFlipped: Bool { true }
    override var wantsDefaultClipping: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    /// 0…1 ramp: up over `upMs` from `start` ms after his click, down over
    /// his last `fadeOutMs`.
    private func ramp(_ p: PrayChoir.Prayer, from start: Double, upMs: Double) -> CGFloat {
        let t = nowMs - p.sinceMs
        guard t > start else { return 0 }
        return min(CGFloat(min(1, (t - start) / upMs)), fadingOut(p))
    }

    /// 1 until his last `fadeOutMs`, then down to 0 — all of him, hands too.
    private func fadingOut(_ p: PrayChoir.Prayer) -> CGFloat {
        CGFloat(min(1, max(0, (PrayController.singMs - (nowMs - p.sinceMs)) / PrayController.fadeOutMs)))
    }

    /// The rest of him, around the hands.
    private func man(_ p: PrayChoir.Prayer) -> CGFloat { ramp(p, from: 0, upMs: PrayController.manFadeInMs) }
    /// The ray.
    private func light(_ p: PrayChoir.Prayer) -> CGFloat { ramp(p, from: PrayController.lightDelayMs, upMs: 500) }
    /// The glow behind him, after the ray lands.
    private func glow(_ p: PrayChoir.Prayer) -> CGFloat {
        ramp(p, from: PrayController.lightDelayMs + Self.beamFallMs, upMs: Self.glowUpMs)
    }

    override func draw(_ dirtyRect: NSRect) {
        let breathe = 1 + 0.02 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 3.2))
        let h = Self.figureHeight * breathe
        let aspect = figure.map { $0.size.width / max(1, $0.size.height) } ?? 1
        let w = h * aspect
        // Placed by his hands, not his middle: they are what follows the
        // pointer, and they must not move when the rest of him appears.
        func figureRect(at p: CGPoint) -> CGRect {
            CGRect(x: p.x - w * Self.handsCentre.x, y: p.y - h * Self.handsCentre.y, width: w, height: h)
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Every ray and every glow first, so no man stands behind another's light.
        for p in prayers {
            let g = light(p)
            if g > 0 { drawBeam(ctx, onto: figureRect(at: p.at), for: p, strength: g) }
        }
        for p in prayers {
            let gl = glow(p)
            guard gl > 0 else { continue }
            let rect = figureRect(at: p.at)
            let pulse = 1 + 0.06 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 1.6))
            let radius = h * 0.85 * pulse
            let colors = [Self.glowColor.withAlphaComponent(0.75 * gl).cgColor,
                          Self.glowColor.withAlphaComponent(0).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                let c = CGPoint(x: rect.midX, y: rect.midY - h * 0.1)
                ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0,
                                       endCenter: c, endRadius: radius, options: [])
            }
        }

        guard let figure else {
            let str = NSAttributedString(string: "🙏", attributes: [.font: NSFont.systemFont(ofSize: h * 0.4)])
            let s = str.size()
            str.draw(at: CGPoint(x: at.x - s.width / 2, y: at.y - s.height / 2))
            return
        }
        for p in prayers {
            let rect = figureRect(at: p.at)
            let m = man(p)
            if m > 0 { drawFigure(figure, in: rect, fraction: m) }
            drawHands(figure, ctx, in: rect, fraction: fadingOut(p))
        }
        drawHands(figure, ctx, in: figureRect(at: at), fraction: 1)
    }

    private static let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high]

    private func drawFigure(_ figure: NSImage, in rect: CGRect, fraction: CGFloat) {
        figure.draw(in: rect, from: .zero, operation: .sourceOver, fraction: fraction,
                    respectFlipped: true, hints: Self.hints)
    }

    /// The figure through `handsOutline` — just the joined hands.
    private func drawHands(_ figure: NSImage, _ ctx: CGContext, in rect: CGRect, fraction: CGFloat) {
        guard fraction > 0 else { return }
        let hands = CGMutablePath()
        hands.addLines(between: Self.handsOutline.map {
            CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + $0.y * rect.height)
        })
        hands.closeSubpath()
        ctx.saveGState()
        ctx.addPath(hands)
        ctx.clip()
        drawFigure(figure, in: rect, fraction: fraction)
        ctx.restoreGState()
    }

    /// A ray from the top of the screen, slanting in from the left, down onto him: narrow up there, wider
    /// than him where it lands, drawn BEHIND him so his outline sits in it.
    /// Three nested passes, the widest the faintest, stand in for a soft edge;
    /// it falls from the top in `beamFallMs` and shimmers slightly while lit.
    /// It is on him wherever he was planted.
    private func drawBeam(_ ctx: CGContext, onto rect: CGRect, for p: PrayChoir.Prayer, strength g: CGFloat) {
        guard rect.maxY > 0 else { return }
        let fallen = nowMs - p.sinceMs - PrayController.lightDelayMs
        let f = CGFloat(min(1, max(0, fallen) / Self.beamFallMs))
        let land = rect.maxY - rect.height * 0.15
        let reach = land * (1 - (1 - f) * (1 - f))          // ease-out
        guard reach > 1 else { return }
        let shimmer = 1 + 0.08 * CGFloat(sin(nowMs / 1000 * 2 * .pi / 0.9))
        let topW = rect.width * 0.4, landW = rect.width * 1.3
        // The axis: from the top edge, up-left of him, down onto him.
        let topX = rect.midX - land * tan(Self.beamTiltDegrees * .pi / 180)
        let reachX = topX + (rect.midX - topX) * (reach / land)
        let space = CGColorSpaceCreateDeviceRGB()
        for (k, a) in [(CGFloat(1.0), CGFloat(0.16)), (0.7, 0.2), (0.4, 0.28)] {
            let tw = topW * k
            let bw = tw + (landW * k - tw) * (reach / land)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: topX - tw / 2, y: 0))
            path.addLine(to: CGPoint(x: topX + tw / 2, y: 0))
            path.addLine(to: CGPoint(x: reachX + bw / 2, y: reach))
            path.addLine(to: CGPoint(x: reachX - bw / 2, y: reach))
            path.closeSubpath()
            let alpha = a * g * shimmer
            let colors = [Self.beamColor.withAlphaComponent(alpha * 0.7).cgColor,
                          Self.beamColor.withAlphaComponent(alpha).cgColor,
                          Self.beamColor.withAlphaComponent(0).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 0.8, 1]) else { continue }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: CGPoint(x: topX, y: 0), end: CGPoint(x: reachX, y: reach), options: [])
            ctx.restoreGState()
        }
    }
}
