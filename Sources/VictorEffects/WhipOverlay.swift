import AppKit
import Foundation

/// Fullscreen overlay that hosts the "🔥 Whip Claude" feature — the OpenWhip
/// experience ported to native Swift/AppKit.
///
/// While active:
///   • a physics whip (WhipPhysics) follows the cursor across the screen,
///   • a fast left-right flick **cracks** the whip (one of 5 sounds),
///   • a **click** fires the macro: Ctrl+C + a scolding phrase + Return at the
///     focused terminal (WhipMacro),
///   • Esc (or unchecking the menu item) dismisses it.
///
/// Deliberately self-contained: it tracks the mouse by polling
/// `NSEvent.mouseLocation` each frame and captures clicks/Esc via its own panel
/// + `NSEvent` monitors, so it does NOT touch the global event tap — the
/// Mouse-5 → mute path stays completely untouched.
final class WhipController {

    /// Called when the user presses Esc — AppDelegate uses this to also uncheck
    /// the menu item so UI state stays consistent.
    var onEscape: (() -> Void)?

    /// Fired on every show (true) / hide (false) so the event tap knows when to
    /// let the Enter-button crack the whip (see `forceCrack`).
    var onVisibilityChanged: ((Bool) -> Void)?

    /// Fired on **every** crack, whatever made it — a real flick, Return, the
    /// thumb buttons or `/effect/whip/crack`. The whip has no idea what listens
    /// (nobody since 2026-10-16: the claude-peek mascot now jumps on a HIT, via
    /// `onRope`), which is why this is a callback and not a direct call into
    /// the animator: the overlay stays a rope and a sound.
    var onCrack: (() -> Void)?

    /// Fired every frame with the rope's links in **global framebuffer points**
    /// (handle first) and how far each moved this frame, in the whip's own
    /// points — so a listener can tell what the rope actually touched. The
    /// claude-peek mascot jumps only when it is hit (`EmojiAnimator.whipLash`).
    var onRope: ((_ points: [CGPoint], _ speeds: [CGFloat]) -> Void)?

    private var panel: WhipPanel?
    private var view: WhipView?
    private var physics: WhipPhysics?
    private var displayTimer: Timer?
    private var screenFrame: NSRect = .zero
    /// The display the whip is on, whose ⌥-scroll zoom it follows.
    private var screen: NSScreen?
    /// The slice of `screenFrame` on the glass that the panel was last mapped
    /// into (`ZoomedPanel`). The pointer is converted with this SAME rect each
    /// frame, so the rope's handle and the window can never disagree by a pan.
    private var appliedVisible: CGRect = .zero
    /// The real arrow is hidden while the whip is up — the handle IS the
    /// pointer (Victor, 2026-10-20).
    private var cursorHide: CursorHide?

    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    private var lastForceCrackMs = 0.0
    private var suppressNaturalCrackUntilMs = 0.0
    /// Scripted handle positions (view coords) consumed one per frame — a fake
    /// fast mouse sweep that cracks the whip on a button press (see forceCrack).
    private var flickQueue: [CGPoint] = []

    /// Handle-offset profile of the scripted flick, as fractions of `peak`:
    /// accelerate out, then snap back to the start (seamless hand-off to the
    /// real cursor). ~8 frames ≈ 130 ms — a quick, whip-worthy flick.
    private static let flickProfile: [Double] = [0.0, 0.45, 0.85, 1.0, 0.7, 0.35, 0.12, 0.0]
    private static let flickPeakMin = 140.0   // min sweep distance (px)
    private static let flickPeakMax = 460.0   // max sweep distance (px)

    private let crackSounds = ["whip_A.mp3", "whip_B.mp3", "whip_C.mp3", "whip_D.mp3", "whip_E.mp3"]

    /// Seconds of built-in lead-in before each sample's actual SNAP (measured at
    /// -18 dB, minus a ~10ms pre-roll so the attack stays punchy). We seek each
    /// crack player here so its transient bangs the instant the whip visually
    /// cracks — otherwise whip_B/D bury the snap behind ~140-170ms of wind-up
    /// swish and the crack you hear trails the visual by that much, at random.
    private static let crackOnset: [String: TimeInterval] = [
        "whip_A.mp3": 0.0,
        "whip_B.mp3": 0.13,
        "whip_C.mp3": 0.0,
        "whip_D.mp3": 0.155,
        "whip_E.mp3": 0.06,
    ]

    /// The crack rides the **tablet's** volume wedge like every soundboard
    /// sound — one knob for everything the room hears — but at 64% of it: at
    /// the wedge's full level the crack is loud enough to genuinely startle the
    /// audience, which is not the joke we're going for. (Was 80%; still too
    /// loud in the room, cut by another fifth on 1 Oct 2026.)
    private static let crackVolumeFactor: Float = 0.64

    /// Play a random crack sample, seeked to its snap onset and with no BT delay
    /// (the overlay keeps the A2DP link warm), so the crack lands as tightly as
    /// possible on the on-screen crack.
    private func playCrack() {
        guard let sound = crackSounds.randomElement() else { return }
        let volume = SoundManager.shared.currentTabletVolume * Self.crackVolumeFactor
        SoundManager.shared.playOverlapping(
            sound, volume: volume, bluetoothCompensated: false, startAt: Self.crackOnset[sound] ?? 0)
    }

    /// **The one funnel every crack passes through**, scripted or natural: sound
    /// first, then whoever is listening. Both callers used to call `playCrack()`
    /// directly, and a second thing to do per crack would have had to be
    /// remembered at two sites — exactly the divergence this exists to prevent.
    private func cracked() {
        playCrack()
        pleaOwed = true
        onCrack?()
    }

    // MARK: - Pleas

    /// A crack owes the room one polite word, thrown off the TIP. It is owed
    /// rather than thrown here because a Return/thumb crack passes through the
    /// funnel *before* its scripted flick, while the tip still hangs by the
    /// pointer — `tick` pays it on the frame the rope actually snaps, or when
    /// the flick runs out, whichever comes first.
    private var pleaOwed = false
    /// While a plea is owed: where the handle and tip were on the frame the
    /// tip moved fastest — the lash. A scripted flick often ends without a
    /// snap, and by then the tip has swung back to the pointer, so the word is
    /// thrown from here rather than from wherever the tip happens to be.
    private var pleaLash: (speed: Double, handle: CGPoint, tip: CGPoint, heading: CGVector)?
    private var pleaBag = WhipPleas.Bag()
    /// The handle's last `WhipPleas.headingWindowMs` of positions: where the
    /// pointer was heading when the rope snapped, which is where the word goes.
    private var handleTrail: [(ms: Double, at: CGPoint)] = []

    private var heading: CGVector {
        guard let first = handleTrail.first, let last = handleTrail.last else { return .zero }
        return CGVector(dx: last.at.x - first.at.x, dy: last.at.y - first.at.y)
    }

    private func throwPlea(now: Double) {
        pleaOwed = false
        let lash = pleaLash
        pleaLash = nil
        guard let view, let handle = physics?.points.first, let tip = physics?.points.last else { return }
        let from = lash.map { ($0.handle, $0.tip, $0.heading) }
            ?? (CGPoint(x: handle.x, y: handle.y), CGPoint(x: tip.x, y: tip.y), heading)
        view.pleas.append(WhipView.Plea(
            text: pleaBag.next(), at: WhipPleas.launchPoint(handle: from.0, tip: from.1, heading: from.2),
            bornMs: now))
    }

    /// The ROPE is up. The panel can outlive it for a moment: the words
    /// already thrown finish their flight on it after `hide()`.
    var isShowing: Bool { physics != nil }

    /// Monotonic milliseconds for deterministic-style timing (grace/cooldown).
    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000.0 }

    // MARK: - Show / hide

    /// Show the whip overlay on the screen under the cursor. Keystrokes are sent
    /// to whatever app currently has keyboard focus at click time — the panel is
    /// non-activating, so showing it never steals focus and there is no app to
    /// re-activate (and no stale menu-open snapshot to chase).
    func show() {
        guard !isShowing else { return }

        let screen = screenUnderMouse()
        // Words still flying from the last whip keep flying on the new panel —
        // on the same screen; elsewhere they would jump, so they go.
        let carried = self.screen == screen ? view?.pleas ?? [] : []
        tearDownPanel()
        self.screen = screen
        screenFrame = screen.frame

        let p = WhipPanel(screenFrame: screenFrame)
        let v = WhipView(frame: NSRect(origin: .zero, size: screenFrame.size))
        v.pleas = carried
        v.onMouseDown = { [weak self] in self?.handleClick() }
        p.contentView = v
        // Before the first pointer read: the spawn below converts the pointer
        // with the slice this places the panel on.
        appliedVisible = .null
        placeForZoom(p)

        let sim = WhipPhysics(width: Double(screenFrame.width), height: Double(screenFrame.height))
        let mouse = viewPoint(forGlobal: VisibleCursor.location)
        sim.spawn(mouseX: Double(mouse.x), mouseY: Double(mouse.y), now: nowMs())
        v.points = sim.points

        panel = p
        view = v
        physics = sim

        p.orderFrontRegardless()
        cursorHide = CursorHide()

        // On Bluetooth output, keep the A2DP amp continuously warm for the whole
        // time the whip is on screen. A crack can fire at any instant, so rather
        // than delay each crack sound to cover BT spin-up (which would trail it
        // behind the visual crack), we warm the link now and play cracks with no
        // delay — they stay in sync with the on-screen crack. No-op off Bluetooth.
        BluetoothOutput.startContinuousWarm()

        installEscMonitors()
        startTimer()
        onVisibilityChanged?(true)
    }

    /// Takes the rope down. The words it already threw stay up to the end of
    /// their own clock (2026-10-21, Victor: *"if I cancel the whip, the label
    /// should still be there for people to have fun"*), on a panel that no
    /// longer catches clicks; `tick` takes the panel away with the last one.
    /// `keepingPleas: false` is the emergency stop's — 🛑 clears them too.
    func hide(keepingPleas: Bool = true) {
        let wasShowing = isShowing
        removeEscMonitors()
        BluetoothOutput.stopContinuousWarm()
        cursorHide?.release()
        cursorHide = nil
        physics = nil
        flickQueue = []
        pleaOwed = false
        pleaLash = nil
        handleTrail = []
        if keepingPleas, let panel, let view, !view.pleas.isEmpty {
            panel.ignoresMouseEvents = true
            view.points = []
            view.needsDisplay = true
        } else {
            tearDownPanel()
        }
        if wasShowing { onVisibilityChanged?(false) }
    }

    private func tearDownPanel() {
        displayTimer?.invalidate()
        displayTimer = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
        screen = nil
    }

    /// Crack the whip programmatically — driven by the Enter-button (or Return
    /// key) while the overlay is up. Rather than nudge the physics directly, it
    /// *pretends you flicked the mouse*: it scripts a fast horizontal sweep of
    /// the handle (toward whichever side of the screen has more room) that the
    /// real physics whips into a genuine crack, and plays a crack sound. The
    /// sweep returns to the cursor so control hands back seamlessly. Debounced
    /// so a press seen as both a key and a mouse event cracks only once.
    func forceCrack() {
        guard isShowing else { return }
        let now = nowMs()
        if now - lastForceCrackMs < 160 { return }
        lastForceCrackMs = now
        cracked()
        suppressNaturalCrackUntilMs = now + 500
        startScriptedFlick()
    }

    /// Build the fake mouse sweep: from the cursor, out toward the side with
    /// more space and back, following `flickProfile`.
    private func startScriptedFlick() {
        let start = viewPoint(forGlobal: VisibleCursor.location)
        let w = Double(screenFrame.width)
        let spaceRight = w - Double(start.x)
        let spaceLeft = Double(start.x)
        let dir: Double = spaceRight >= spaceLeft ? 1.0 : -1.0   // flick toward more room
        let room = Swift.max(spaceRight, spaceLeft) - 40.0
        let peak = Swift.min(Self.flickPeakMax, Swift.max(Self.flickPeakMin, room))
        flickQueue = Self.flickProfile.map { frac in
            CGPoint(x: start.x + CGFloat(dir * peak * frac), y: start.y)
        }
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
        guard let physics else {
            // The rope is down; only its last words are still flying.
            view.pleas.removeAll { now - $0.bornMs > WhipPleas.lifeMs }
            if view.pleas.isEmpty { tearDownPanel(); return }
            view.nowMs = now
            view.needsDisplay = true
            return
        }
        cursorHide?.reassertNearEdge(pointer: VisibleCursor.location, screen: screenFrame)
        // A scripted flick (forceCrack) drives the handle for a few frames to
        // imitate a fast mouse sweep; otherwise follow the real cursor.
        let m = flickQueue.isEmpty ? viewPoint(forGlobal: VisibleCursor.location) : flickQueue.removeFirst()
        physics.setMouse(Double(m.x), Double(m.y))
        handleTrail.append((now, m))
        handleTrail.removeAll { now - $0.ms > WhipPleas.headingWindowMs }
        let didCrack = physics.update(now: now)
        // Announce the natural crack — but not during a scripted flick, whose
        // own forceCrack already announced one (avoid doubling).
        if didCrack && now > suppressNaturalCrackUntilMs {
            cracked()
        }
        if pleaOwed, let handle = physics.points.first, let tip = physics.points.last {
            let speed = ((tip.x - tip.px) * (tip.x - tip.px) + (tip.y - tip.py) * (tip.y - tip.py)).squareRoot()
            if speed > (pleaLash?.speed ?? -1) {
                pleaLash = (speed, CGPoint(x: handle.x, y: handle.y), CGPoint(x: tip.x, y: tip.y), heading)
            }
        }
        if pleaOwed && (didCrack || flickQueue.isEmpty) { throwPlea(now: now) }
        view.pleas.removeAll { now - $0.bornMs > WhipPleas.lifeMs }
        view.nowMs = now
        view.points = physics.points
        view.needsDisplay = true
        if let onRope, let panel { reportRope(physics.points, view: view, panel: panel, to: onRope) }
    }

    /// The view's points go through AppKit's own conversion, which knows the
    /// ⌥-scroll shrink (`ZoomedPanel` keeps the design size as the bounds) and
    /// the flip, so the listener gets where each link really is on the screen.
    private func reportRope(_ points: [WhipPhysics.Point], view: NSView, panel: NSPanel,
                            to listener: ([CGPoint], [CGFloat]) -> Void) {
        guard !points.isEmpty else { return }
        var global: [CGPoint] = []
        var speeds: [CGFloat] = []
        global.reserveCapacity(points.count)
        speeds.reserveCapacity(points.count)
        for p in points {
            let inWindow = view.convert(NSPoint(x: p.x, y: p.y), to: nil)
            global.append(panel.convertPoint(toScreen: inWindow))
            speeds.append(CGFloat(((p.x - p.px) * (p.x - p.px) + (p.y - p.py) * (p.y - p.py)).squareRoot()))
        }
        listener(global, speeds)
    }

    // MARK: - Input

    private func handleClick() {
        // A click = interrupt: Ctrl+C + a scolding phrase + Return, delivered to
        // whatever app currently has keyboard focus (no focus stealing, no stale
        // target — the user keeps Claude focused; the keys land there).
        WhipMacro.sendCrackMacro()
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

    // MARK: - Geometry

    private func screenUnderMouse() -> NSScreen {
        let loc = VisibleCursor.location
        return NSScreen.screens.first { $0.frame.contains(loc) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    /// Convert a global (y-up) screen point to the flipped overlay view's space
    /// (origin top-left, y-down) — matching the physics/HTML-canvas coordinates.
    ///
    /// Under ⌥-scroll zoom the view's space is the GLASS: the panel covers only
    /// the slice on the glass and its view keeps the whole screen's size as its
    /// bounds, so the point is first taken to where it is seen on the unzoomed
    /// screen. At rest that step is the identity.
    private func viewPoint(forGlobal g: NSPoint) -> CGPoint {
        Self.viewPoint(forGlobal: g, screen: screenFrame, visible: appliedVisible)
    }

    /// Pure half of `viewPoint`, for the tests.
    static func viewPoint(forGlobal g: NSPoint, screen: CGRect, visible: CGRect) -> CGPoint {
        let d = ZoomedPanel.designPoint(g, screen: screen, visible: visible)
        return CGPoint(x: d.x - screen.minX, y: screen.maxY - d.y)
    }

    /// Keep the panel on the slice that is on the glass, shrunk by the zoom, so
    /// the rope is the thickness and length it is unzoomed (`ZoomedPanel`).
    /// Called every frame from `tick` — the pointer that pans the zoom is the
    /// pointer that swings the whip — and a no-op while the slice holds still.
    /// The physics never learns about the zoom: it runs on the whole screen's
    /// size, which is what the view's bounds stay.
    private func placeForZoom(_ panel: NSPanel) {
        let slice = ZoomedPanel.visible(on: screen, fallback: screenFrame)
        guard slice != appliedVisible else { return }
        appliedVisible = slice
        ZoomedPanel.apply(panel,
                          frame: ZoomedPanel.frame(design: screenFrame, screen: screenFrame, visible: slice),
                          designSize: screenFrame.size)
    }
}

// MARK: - Panel

/// Transparent, borderless, always-on-top, non-activating panel. Interactive
/// (receives clicks) but never becomes key — so keyboard focus stays on the
/// terminal and the Ctrl+C macro reaches it.
final class WhipPanel: NSPanel {
    init(screenFrame: NSRect) {
        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false // we poll NSEvent.mouseLocation each frame
        hidesOnDeactivate = false
        // NOT `isFloatingPanel = true`: its setter resets `level` to `.floating`
        // (3), and set after the line below it quietly sank the whip under the
        // ⌥⇧ zoom's `.screenSaver` window — the rope vanished the moment the
        // zoom's first frame came in (2026-10-19). Every window of ours sits at
        // `maximumWindow`; `WhipPanelLevelTests` holds this one to it.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - View (Core Graphics whip rendering)

/// Renders the whip from `points` using the same Catmull-Rom → cubic-Bézier
/// spline + white-halo/dark-core styling as OpenWhip's overlay.html `draw()`.
private final class WhipView: NSView {

    var points: [WhipPhysics.Point] = []
    var onMouseDown: (() -> Void)?

    /// A polite word thrown off the tip on a crack (`WhipPleas`), in view
    /// coords. Each one dies on its own clock — `tick` prunes it at `lifeMs`.
    struct Plea {
        let text: String
        let at: CGPoint
        let bornMs: Double
    }
    var pleas: [Plea] = []
    var nowMs = 0.0

    // Visual constants (the non-physics fields of overlay.html's `P`).
    private let lineWidthHandle: CGFloat = 7
    private let lineWidthTip: CGFloat = 5
    private let outlineWidth: CGFloat = 3
    private let handleExtraWidth: CGFloat = 5
    private let handleThickSegments = 2

    override var isFlipped: Bool { true }       // origin top-left, y down (matches physics)
    override var wantsDefaultClipping: Bool { false }

    // Deliver the click even though the panel isn't the active window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    private func p(_ i: Int) -> CGPoint { CGPoint(x: points[i].x, y: points[i].y) }

    /// Catmull-Rom control point with extrapolated ends (mirrors `catmullPoint`).
    private func catmull(_ i: Int) -> CGPoint {
        let n = points.count
        if n == 0 { return .zero }
        if i < 0 {
            if n >= 2 { return CGPoint(x: 2 * points[0].x - points[1].x, y: 2 * points[0].y - points[1].y) }
            return p(0)
        }
        if i >= n {
            if n >= 2 {
                let a = points[n - 2], b = points[n - 1]
                return CGPoint(x: 2 * b.x - a.x, y: 2 * b.y - a.y)
            }
            return p(n - 1)
        }
        return p(i)
    }

    /// Cubic Bézier control points for segment i (mirrors `whipSegmentBezier`).
    private func segmentBezier(_ i: Int) -> (cp1: CGPoint, cp2: CGPoint, end: CGPoint) {
        let p0 = catmull(i - 1)
        let p1 = p(i)
        let p2 = p(i + 1)
        let p3 = catmull(i + 2)
        let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
        let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
        return (cp1, cp2, p2)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    override func draw(_ dirtyRect: NSRect) {
        drawRope()
        for plea in pleas { drawPlea(plea) }
    }

    private func drawRope() {
        guard points.count >= 2 else { return }

        // ── White halo: thin over the whole spline, extra-thick over handle links.
        let white = NSColor.white
        white.setStroke()

        let halo = NSBezierPath()
        halo.lineCapStyle = .round
        halo.lineJoinStyle = .round
        halo.move(to: p(0))
        for i in 0..<(points.count - 1) {
            let s = segmentBezier(i)
            halo.curve(to: s.end, controlPoint1: s.cp1, controlPoint2: s.cp2)
        }
        halo.lineWidth = lineWidthTip + outlineWidth * 2
        halo.stroke()

        let thickLinks = min(handleThickSegments, points.count - 1)
        if thickLinks > 0 && handleExtraWidth > 0 {
            let handleHalo = NSBezierPath()
            handleHalo.lineCapStyle = .round
            handleHalo.lineJoinStyle = .round
            handleHalo.move(to: p(0))
            for i in 0..<thickLinks {
                let s = segmentBezier(i)
                handleHalo.curve(to: s.end, controlPoint1: s.cp1, controlPoint2: s.cp2)
            }
            handleHalo.lineWidth = lineWidthHandle + handleExtraWidth + outlineWidth * 2
            handleHalo.stroke()
        }

        // ── Dark core: tapered width per segment.
        let dark = NSColor(red: 0x11 / 255.0, green: 0x11 / 255.0, blue: 0x11 / 255.0, alpha: 1.0)
        dark.setStroke()
        for i in 0..<(points.count - 1) {
            let t = CGFloat(i) / CGFloat(max(1, points.count - 2))
            let extra: CGFloat = i < handleThickSegments ? handleExtraWidth : 0
            let seg = NSBezierPath()
            seg.lineCapStyle = .round
            seg.lineJoinStyle = .round
            seg.lineWidth = lerp(lineWidthHandle, lineWidthTip, t) + extra
            seg.move(to: p(i))
            let s = segmentBezier(i)
            seg.curve(to: s.end, controlPoint1: s.cp1, controlPoint2: s.cp2)
            seg.stroke()
        }
    }

    /// Pops out of the snap point, floats up and fades: a quick overshoot to
    /// 115% in the first 12% of its life, then a rise of `riseDistance`, fading
    /// over the last 40%. Black outline + dark shadow so it reads on any
    /// backdrop (white until 2026-10-20 — Victor asked for a black border).
    private func drawPlea(_ plea: Plea) {
        let t = CGFloat(min(1, max(0, (nowMs - plea.bornMs) / WhipPleas.lifeMs)))
        let pop: CGFloat = t < 0.12 ? lerp(0.5, 1.15, t / 0.12)
            : t < 0.22 ? lerp(1.15, 1.0, (t - 0.12) / 0.1) : 1.0
        let alpha: CGFloat = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4
        let font = NSFont.systemFont(ofSize: WhipPleas.fontSize * pop, weight: .heavy)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.55 * alpha)
        shadow.shadowBlurRadius = 6
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        // Two passes, outline UNDER the fill. A one-pass fill+stroke
        // (`strokeWidth` < 0) strokes every contour of the glyph, and the heavy
        // system font is built of overlapping ones — so black seams ran
        // through the inside of e, a, k, E (2026-10-20, Victor: *"A, K and E
        // … somehow cut off"*), and a centred stroke ate half the pink. Here
        // the outline is drawn alone, with round joins (no spikes off A's apex
        // or K's arms), and the clean fill lands on top of it.
        let outline = NSAttributedString(string: plea.text, attributes: [
            .font: font,
            .strokeColor: NSColor.black.withAlphaComponent(alpha),
            .strokeWidth: WhipPleas.outlineWidth,   // positive = stroke only
            .shadow: shadow,
        ])
        let fill = NSAttributedString(string: plea.text, attributes: [
            .font: font,
            .foregroundColor: WhipPleas.color.withAlphaComponent(alpha),
        ])
        let size = fill.size()
        let center = CGPoint(x: plea.at.x, y: plea.at.y - WhipPleas.riseDistance * t)
        let origin = WhipPleas.clamp(
            CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                   width: size.width, height: size.height),
            into: bounds).origin
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.setLineJoin(.round)
            outline.draw(at: origin)
            ctx.restoreGState()
        }
        fill.draw(at: origin)
    }
}

/// The polite words the whip throws where it cracks — the whip asks nicely now.
enum WhipPleas {
    static let phrases = [
        "please", "pretty please", "kindly", "I beg you", "thank you!",
        "with a cherry on top", "if it's no trouble", "sorry!", "🙏 please",
        "would you mind?", "much obliged", "pleeease",
        // The room is European: the polite words everyone knows, wherever they flew in from.
        "por favor 💃", "per favore 🤌", "prego, prego!", "bitte schön 🥨",
        "s'il vous plaît 🥐", "merci beaucoup 💋", "grazie mille 🍝",
        "danke! 🍺", "gracias, amigo 🌮", "obrigado 🙏", "proszę 🥟",
        "mulțumesc! 🍷", "pretty por favor", "bitte bitte bitte 🥺",
        // ...and the British, who apologise while being whipped.
        "terribly sorry ☕", "cheers, mate 🍻", "be a dear 🫖", "lovely jubbly",
        "chop chop, old bean", "jolly good! 🎩", "awfully kind 💂",
        "fancy a cuppa? ☕", "bloody brilliant", "pip pip! 🇬🇧",
        "sorry, sorry, sorry", "with a biscuit on top 🍪",
    ]
    /// 1.95 s = 1.3 s + 50% (2026-10-21: *"stay for fifty percent more
    /// time"*) — the room needs the time to read *chop chop, old bean*.
    static let lifeMs = 1950.0
    static let riseDistance: CGFloat = 70
    /// 41 = 34 + 20% (2026-10-20: *"twenty percent larger"*).
    static let fontSize: CGFloat = 41
    /// The black outline pass, in % of the font size (stroke-only, so half of
    /// it shows outside the letters: ~3 pt of border at 41 pt).
    static let outlineWidth: CGFloat = 16
    /// How far past the tip, away from the handle, the word is thrown — at the
    /// tip itself it sat in the rope's own scribble, too close to the pointer
    /// (2026-10-20: *"pop out a bit further away from where the mouse is"*).
    static let throwBeyondTip: CGFloat = 60

    /// The pointer's heading is read over this long before the lash.
    static let headingWindowMs = 200.0
    /// Less movement than this over the window is no heading at all.
    static let minHeading: CGFloat = 15
    /// The word never lands closer to the pointer than this plus `throwBeyondTip`.
    static let minReach: CGFloat = 100

    /// Where a plea appears: AHEAD of the pointer, the way it was moving when
    /// the rope snapped, as far out as the tip was plus `throwBeyondTip`
    /// (2026-10-20, Victor: *"if it was heading … west, then the kind word
    /// should appear … towards the tip of that whip as it … cracked towards
    /// the west"*). The line handle→tip alone was wrong on a flick: the tip
    /// trails BEHIND a pointer swung west until the very end, so the word
    /// flew east. Without a heading, the line from the handle through the tip
    /// still decides; a tip curled back onto the handle sends it straight up.
    static func launchPoint(handle: CGPoint, tip: CGPoint, heading: CGVector = .zero) -> CGPoint {
        let dx = tip.x - handle.x, dy = tip.y - handle.y
        let len = (dx * dx + dy * dy).squareRoot()
        let hl = (heading.dx * heading.dx + heading.dy * heading.dy).squareRoot()
        if hl >= minHeading {
            let reach = max(len, minReach) + throwBeyondTip
            return CGPoint(x: handle.x + heading.dx / hl * reach, y: handle.y + heading.dy / hl * reach)
        }
        guard len > 20 else { return CGPoint(x: tip.x, y: tip.y - throwBeyondTip) }
        return CGPoint(x: tip.x + dx / len * throwBeyondTip, y: tip.y + dy / len * throwBeyondTip)
    }
    static let color = NSColor(red: 1.0, green: 0.36, blue: 0.62, alpha: 1)

    /// A shuffle-bag, not `randomElement()`: a random pick repeats itself often
    /// enough to be noticed, and this one visits every phrase before any comes
    /// back — never the same word twice in a row, even across refills.
    struct Bag {
        private var queue: [String] = []
        private var last: String?

        mutating func next() -> String {
            if queue.isEmpty {
                queue = phrases.shuffled()
                if queue.count > 1, queue.first == last { queue.swapAt(0, queue.count - 1) }
            }
            let word = queue.removeFirst()
            last = word
            return word
        }
    }

    /// Slide `rect` inside `bounds` — cracks happen at the screen's edges too,
    /// and half a "please" off the glass reads as a bug.
    static func clamp(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        var r = rect
        r.origin.x = min(max(r.origin.x, bounds.minX), bounds.maxX - r.width)
        r.origin.y = min(max(r.origin.y, bounds.minY), bounds.maxY - r.height)
        return r
    }
}
