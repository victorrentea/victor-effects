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

    private var panel: WhipPanel?
    private var view: WhipView?
    private var physics: WhipPhysics?
    private var displayTimer: Timer?
    private var screenFrame: NSRect = .zero

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
    /// sound — one knob for everything the room hears — but at 80% of it: at
    /// the wedge's full level the crack is loud enough to genuinely startle the
    /// audience, which is not the joke we're going for.
    private static let crackVolumeFactor: Float = 0.8

    /// Play a random crack sample, seeked to its snap onset and with no BT delay
    /// (the overlay keeps the A2DP link warm), so the crack lands as tightly as
    /// possible on the on-screen crack.
    private func playCrack() {
        guard let sound = crackSounds.randomElement() else { return }
        let volume = SoundManager.shared.currentTabletVolume * Self.crackVolumeFactor
        SoundManager.shared.playOverlapping(
            sound, volume: volume, bluetoothCompensated: false, startAt: Self.crackOnset[sound] ?? 0)
    }

    var isShowing: Bool { panel != nil }

    /// Monotonic milliseconds for deterministic-style timing (grace/cooldown).
    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000.0 }

    // MARK: - Show / hide

    /// Show the whip overlay on the screen under the cursor. Keystrokes are sent
    /// to whatever app currently has keyboard focus at click time — the panel is
    /// non-activating, so showing it never steals focus and there is no app to
    /// re-activate (and no stale menu-open snapshot to chase).
    func show() {
        guard panel == nil else { return }

        let screen = screenUnderMouse()
        screenFrame = screen.frame

        let p = WhipPanel(screenFrame: screenFrame)
        let v = WhipView(frame: NSRect(origin: .zero, size: screenFrame.size))
        v.onMouseDown = { [weak self] in self?.handleClick() }
        p.contentView = v

        let sim = WhipPhysics(width: Double(screenFrame.width), height: Double(screenFrame.height))
        let mouse = viewPoint(forGlobal: NSEvent.mouseLocation)
        sim.spawn(mouseX: Double(mouse.x), mouseY: Double(mouse.y), now: nowMs())
        v.points = sim.points

        panel = p
        view = v
        physics = sim

        p.orderFrontRegardless()

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

    func hide() {
        let wasShowing = panel != nil
        displayTimer?.invalidate()
        displayTimer = nil
        removeEscMonitors()
        BluetoothOutput.stopContinuousWarm()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        physics = nil
        flickQueue = []
        if wasShowing { onVisibilityChanged?(false) }
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
        playCrack()
        suppressNaturalCrackUntilMs = now + 500
        startScriptedFlick()
    }

    /// Build the fake mouse sweep: from the cursor, out toward the side with
    /// more space and back, following `flickProfile`.
    private func startScriptedFlick() {
        let start = viewPoint(forGlobal: NSEvent.mouseLocation)
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
        guard let physics, let view else { return }
        let now = nowMs()
        // A scripted flick (forceCrack) drives the handle for a few frames to
        // imitate a fast mouse sweep; otherwise follow the real cursor.
        let m = flickQueue.isEmpty ? viewPoint(forGlobal: NSEvent.mouseLocation) : flickQueue.removeFirst()
        physics.setMouse(Double(m.x), Double(m.y))
        let cracked = physics.update(now: now)
        // Play the natural crack sound — but not during a scripted flick, whose
        // own forceCrack already played one (avoid doubling).
        if cracked && now > suppressNaturalCrackUntilMs {
            playCrack()
        }
        view.points = physics.points
        view.needsDisplay = true
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
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
    }

    /// Convert a global (y-up) screen point to the flipped overlay view's space
    /// (origin top-left, y-down) — matching the physics/HTML-canvas coordinates.
    private func viewPoint(forGlobal g: NSPoint) -> CGPoint {
        CGPoint(x: g.x - screenFrame.minX, y: screenFrame.maxY - g.y)
    }
}

// MARK: - Panel

/// Transparent, borderless, always-on-top, non-activating panel. Interactive
/// (receives clicks) but never becomes key — so keyboard focus stays on the
/// terminal and the Ctrl+C macro reaches it.
private final class WhipPanel: NSPanel {
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
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false // we poll NSEvent.mouseLocation each frame
        isFloatingPanel = true
        hidesOnDeactivate = false
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
}
