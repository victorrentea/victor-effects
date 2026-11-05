import AppKit
import Foundation

/// 🔴 #7, "What does this button do?" (2026-11-05, Victor). While the clip runs
/// the pointer IS a little red button. A click leaves it on that spot five times
/// bigger and gives the pointer back; passing over it pushes it halfway in, under
/// a 👆 hand; clicking it blows it apart in every direction. Only then does the
/// pointer turn into a new little button, to plant the next one.
///
/// It outlives the clip only as far as it has to: a planted button waits to be
/// hit, and a button just blown up leaves `idleMs` for another. Self-terminating
/// all the same: nobody hitting a planted one takes it away after `standsMs`.
///
/// `WhipPanel` and `ZoomedPanel` like the other pointer overlays, so it keeps its
/// size under ⌥-scroll. Unlike them the window lets go of the mouse while a
/// button stands anywhere but under the pointer: the desktop stays usable.
final class RedButtonController {
    /// ♾️ For the tablet's ring (`OpenEndedTiles`): the animator cannot see this.
    private(set) static var isUp = false

    static let tile = "07_animated_phone.mp3"

    var onEscape: (() -> Void)?

    private var panel: WhipPanel?
    private var view: RedButtonView?
    private var timer: Timer?
    private var screenFrame: NSRect = .zero
    private var screen: NSScreen?
    private var appliedVisible: CGRect = .zero
    private var cursorHide: CursorHide?
    private var game = RedButtonGame(clipEndMs: 0)
    private var hover: CGFloat = 0
    private var escGlobalMonitor: Any?
    private var escLocalMonitor: Any?

    var isShowing: Bool { panel != nil }

    private func nowMs() -> Double { ProcessInfo.processInfo.systemUptime * 1000 }

    func show(clipSeconds: TimeInterval) {
        hide()
        let screen = NSScreen.screens.first { $0.frame.contains(VisibleCursor.location) }
            ?? NSScreen.main ?? NSScreen.screens.first!
        self.screen = screen
        screenFrame = screen.frame
        let p = WhipPanel(screenFrame: screenFrame)
        let v = RedButtonView(frame: NSRect(origin: .zero, size: screenFrame.size))
        v.onMouseDown = { [weak self] in self?.click() }
        p.contentView = v
        appliedVisible = .null
        placeForZoom(p)
        panel = p
        view = v
        game = RedButtonGame(clipEndMs: nowMs() + clipSeconds * 1000)
        hover = 0
        p.orderFrontRegardless()
        Self.isUp = true
        installEscMonitors()
        let t = Timer(timeInterval: 1.0 / 60.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    func hide() {
        timer?.invalidate()
        timer = nil
        removeEscMonitors()
        cursorHide?.release()
        cursorHide = nil
        panel?.orderOut(nil)
        panel = nil
        view = nil
        screen = nil
        Self.isUp = false
    }

    /// A click where the pointer is. Also `/effect/red-button/click`, so the
    /// whole run can be checked without a mouse.
    func click() {
        guard let view else { return }
        if game.click(at: view.pointer, nowMs: nowMs()) == .blownUp { view.shatter() }
        tick()
    }

    @objc private func tick() {
        guard let view, let panel else { return }
        placeForZoom(panel)
        let now = nowMs()
        game.advance(nowMs: now)
        if game.isOver(nowMs: now) { hide(); return }

        let pointer = WhipController.viewPoint(forGlobal: VisibleCursor.location, screen: screenFrame, visible: appliedVisible)
        let over = game.isOverButton(pointer)
        hover += ((over ? 1 : 0) - hover) * 0.3

        // The pointer is ours only as the little button and over a big one.
        let drawnPointer = game.phase == .armed || over
        if drawnPointer, cursorHide == nil { cursorHide = CursorHide() }
        if !drawnPointer { cursorHide?.release(); cursorHide = nil }
        cursorHide?.reassertNearEdge(pointer: VisibleCursor.location, screen: screenFrame)
        panel.ignoresMouseEvents = !drawnPointer

        view.pointer = pointer
        view.phase = game.phase
        view.hover = hover
        view.nowMs = now
        view.needsDisplay = true
    }

    private func placeForZoom(_ panel: NSPanel) {
        let slice = ZoomedPanel.visible(on: screen, fallback: screenFrame)
        guard slice != appliedVisible else { return }
        appliedVisible = slice
        ZoomedPanel.apply(panel,
                          frame: ZoomedPanel.frame(design: screenFrame, screen: screenFrame, visible: slice),
                          designSize: screenFrame.size)
    }

    private func installEscMonitors() {
        escGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { DispatchQueue.main.async { self?.onEscape?() } }
        }
        escLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.onEscape?()
            return nil
        }
    }

    private func removeEscMonitors() {
        if let m = escGlobalMonitor { NSEvent.removeMonitor(m); escGlobalMonitor = nil }
        if let m = escLocalMonitor { NSEvent.removeMonitor(m); escLocalMonitor = nil }
    }
}

// MARK: - The rules

/// One button at a time, in three phases, and when it is all over. Pure, so the
/// rules can be tested without a screen or a mouse.
struct RedButtonGame: Equatable {
    /// The little one on the pointer: the 90 px Victor marked on the Retina.
    static let smallSide: CGFloat = 45
    static let plantedScale: CGFloat = 5
    static var bigSide: CGFloat { smallSide * plantedScale }
    /// How long the pieces fly before the next little button appears.
    static let blastMs = 800.0
    /// After a blast past the clip's end: this long to plant another.
    static let idleMs = 6000.0
    /// A planted button nobody hits goes away after this.
    static let standsMs = 60_000.0

    enum Phase: Equatable {
        case armed
        case planted(at: CGPoint, sinceMs: Double)
        case blast(at: CGPoint, sinceMs: Double)
    }
    enum Outcome: Equatable { case planted, blownUp, nothing }

    private(set) var phase: Phase = .armed
    private var armedUntilMs: Double

    init(clipEndMs: Double) { armedUntilMs = clipEndMs }

    mutating func click(at p: CGPoint, nowMs: Double) -> Outcome {
        switch phase {
        case .armed:
            phase = .planted(at: p, sinceMs: nowMs)
            return .planted
        case .planted(let at, _) where Self.hits(at, p):
            phase = .blast(at: at, sinceMs: nowMs)
            return .blownUp
        default:
            return .nothing
        }
    }

    mutating func advance(nowMs: Double) {
        if case .blast(_, let since) = phase, nowMs - since >= Self.blastMs {
            phase = .armed
            armedUntilMs = max(armedUntilMs, nowMs + Self.idleMs)
        }
    }

    func isOver(nowMs: Double) -> Bool {
        switch phase {
        case .armed: return nowMs >= armedUntilMs
        case .planted(_, let since): return nowMs - since >= Self.standsMs
        case .blast: return false
        }
    }

    func isOverButton(_ p: CGPoint) -> Bool {
        if case .planted(let at, _) = phase { return Self.hits(at, p) }
        return false
    }

    private static func hits(_ at: CGPoint, _ p: CGPoint) -> Bool {
        hypot(p.x - at.x, p.y - at.y) <= bigSide / 2
    }
}

// MARK: - View

private final class RedButtonView: NSView {
    var pointer: CGPoint = .zero
    var phase: RedButtonGame.Phase = .armed
    var hover: CGFloat = 0
    var nowMs = 0.0
    var onMouseDown: (() -> Void)?

    private static let frames = loadFrames()
    private var shards: [Shard] = []

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }

    /// `red_button.gif` from `assetsDir`, up and pushed in. Absent, a plain red
    /// disc: the effect still plays (`docs/assets-and-licences.md`).
    private static func loadFrames() -> (up: CGImage, down: CGImage)? {
        if let url = EffectsResources.url("red_button", "gif"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let up = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return (up, CGImageSourceCreateImageAtIndex(source, 1, nil) ?? up)
        }
        effectsInfo("🔴 red_button.gif not in assetsDir — drawing a plain disc")
        guard let ctx = CGContext(data: nil, width: 450, height: 450, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(NSColor.systemRed.cgColor)
        ctx.fillEllipse(in: CGRect(x: 0, y: 0, width: 450, height: 450))
        return ctx.makeImage().map { ($0, $0) }
    }

    /// The pieces of the button that was hit, cut once.
    func shatter() {
        guard let up = Self.frames?.up else { return }
        shards = Shatter.shards(of: up, columns: 6, rows: 6)
    }

    private func rect(_ image: CGImage, at c: CGPoint, side: CGFloat) -> CGRect {
        let h = side * CGFloat(image.height) / max(1, CGFloat(image.width))
        return CGRect(x: c.x - side / 2, y: c.y - h / 2, width: side, height: h)
    }

    /// An image into this flipped view, which would otherwise draw it upside down.
    private func stamp(_ image: CGImage, _ ctx: CGContext, in r: CGRect, alpha: CGFloat = 1) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.translateBy(x: r.minX, y: r.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: r.size))
        ctx.restoreGState()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let frames = Self.frames else { return }
        switch phase {
        case .armed:
            stamp(frames.up, ctx, in: rect(frames.up, at: pointer, side: RedButtonGame.smallSide))
        case .planted(let at, let since):
            // It lands growing, a beat rather than a pop.
            let grown = CGFloat(min(1, (nowMs - since) / 140))
            let side = RedButtonGame.smallSide + (RedButtonGame.bigSide - RedButtonGame.smallSide) * grown
            let r = rect(frames.up, at: at, side: side)
            stamp(frames.up, ctx, in: r)
            // Halfway in: the gif's pushed frame, half laid over the raised one.
            if hover > 0.01 { stamp(frames.down, ctx, in: r, alpha: hover * 0.5) }
            if hover > 0.5 { drawHand(ctx) }
        case .blast(let at, let since):
            drawShards(at: at, t: CGFloat(min(1, (nowMs - since) / RedButtonGame.blastMs)), image: frames.up, ctx)
        }
    }

    private func drawHand(_ ctx: CGContext) {
        let hand = NSCursor.pointingHand
        let r = NSRect(x: pointer.x - hand.hotSpot.x, y: pointer.y - hand.hotSpot.y,
                       width: hand.image.size.width, height: hand.image.size.height)
        hand.image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawShards(at c: CGPoint, t: CGFloat, image: CGImage, _ ctx: CGContext) {
        let whole = rect(image, at: c, side: RedButtonGame.bigSide)
        let flown = 1 - (1 - t) * (1 - t)          // ease-out: thrown, then slowing
        for s in shards {
            let home = CGPoint(x: whole.minX + s.rect.midX * whole.width, y: whole.minY + s.rect.midY * whole.height)
            let reach = RedButtonGame.bigSide * 3 * s.speed * flown
            let size = CGSize(width: s.rect.width * whole.width, height: s.rect.height * whole.height)
            ctx.saveGState()
            ctx.setAlpha(1 - t * t)
            ctx.translateBy(x: home.x + s.direction.dx * reach, y: home.y + s.direction.dy * reach)
            ctx.rotate(by: s.spin * flown)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(s.image, in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
            ctx.restoreGState()
        }
    }
}
