import AppKit
import CoreImage
import QuartzCore

/// 🔴 The big red button that grows out of the cursor and waits to be pressed.
///
/// Every other effect in this app is something the room *watches*. This one is
/// something Victor **does**: the button appears under the pointer, lights up
/// when he hovers it, goes down when he presses it, and then shrinks back into
/// the exact pixel it came from. The whole point is the beat between "there is a
/// big red button on the screen" and "he actually pressed it", so the effect is
/// deliberately **not** glued to its clip's length the way the others are — it
/// outlives the sound and waits (`maxLifetime`) for the press.
///
/// Everything here is a pure function of the overlay bounds, the image and the
/// pointer, for `WazzupCorner`'s reason: geometry, hit-testing and the phase
/// order can then be tested without a screen, a window server or an event tap.
/// `RedButtonController` (below) is the only part that needs any of those.
enum RedButton {

    // MARK: - The asset

    /// The GIF, expected in `EffectsConfig.assetsDir` — a stock arcade button
    /// whose background was flood-filled to alpha and alpha-trimmed, so it is
    /// deliberately **not in this repo** (same rule as `wazzup.png`,
    /// `brother_full.gif` and `scared_cat.gif`). Missing ⇒ one log line and no
    /// overlay; the clip still plays.
    ///
    /// Its **first** frame is the button raised and its **last** frame is the
    /// button pressed in — that is the whole animation, and it is why the press
    /// needs no synthetic squash. A one-frame replacement still works: see
    /// `Frames.hasPressFrame`.
    static let assetName = "red_button.gif"

    /// Tile 7. The clip plays down the ordinary routed path; this side is
    /// silent, and outlives it.
    static let soundName = "07_animated_phone.mp3"

    // MARK: - Numbers

    /// "About a sixth of the screen height" — a third of the half it started at.
    /// The button is a prop Victor presses in front of a room, not a takeover of
    /// the slide: at half the height it covered whatever it grew out of, and the
    /// click it now passes through lands on something nobody could see. Height
    /// and not width, because the height is the dimension a projector's aspect
    /// ratio does not change: the same fraction gives the same apparent size in
    /// the room on 16:10 and on 16:9.
    static let heightFraction: CGFloat = 0.5 / 3

    /// Grow out of the cursor — deliberately twice as slow as it used to be.
    /// The old 0.35 s was tuned for a button half the screen high, which is a
    /// big movement and reads even when it is quick; a sixth of the screen is
    /// small enough that a fast zoom is over before the room has found it, so
    /// the arrival is given the time the size no longer buys it.
    static let zoomInDuration: Double = 0.70

    /// Shrink back into the cursor. Slightly quicker than the entrance: the
    /// entrance is an arrival and wants to be seen, the exit is a dismissal.
    static let shrinkDuration: Double = 0.30

    /// Hover: 6 % bigger and 12 % brighter. Both, rather than either — the scale
    /// carries from the back of a room and the brightness carries on a mirrored
    /// projector that has flattened the contrast.
    static let hoverScale: CGFloat = 1.06
    static let hoverBrightness: Double = 0.12

    /// The press, when the asset has no pressed frame to show instead.
    static let fallbackPressScale: CGFloat = 0.92
    static let fallbackPressBrightness: Double = -0.15

    /// How long the button waits to be pressed before leaving on its own.
    ///
    /// This is the self-termination rule (`CLAUDE.md`) for an effect that has no
    /// clip length to inherit: tile 7's sound is a couple of seconds and the
    /// button is supposed to still be there afterwards, so "the sound ended" is
    /// explicitly NOT the deadline. 20 s is long enough to say a sentence over
    /// and then press it, and short enough that a button nobody pressed does not
    /// sit on the slide for the rest of the session.
    static let maxLifetime: Double = 20.0

    /// A pixel counts as the button when it is at least half opaque. The GIF's
    /// alpha is binary (flood-filled from the edges), so the threshold only
    /// matters for a replacement asset with a feathered edge.
    static let alphaThreshold: UInt8 = 128

    // MARK: - Geometry

    /// The button's resting frame in overlay-layer coordinates: `heightFraction`
    /// of the bounds' height, the image's own aspect, centred **exactly** on the
    /// pointer.
    ///
    /// Deliberately not clamped onto the screen. The effect's promise is that
    /// the button grows out of P and shrinks back into P; a button nudged inwards
    /// to fit would shrink into somewhere the click did not happen, which is a
    /// worse lie than a button hanging off the edge when the pointer was parked
    /// in a corner.
    static func frame(imageSize: CGSize, in bounds: CGRect, centredOn p: CGPoint) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.height > 0 else {
            return CGRect(origin: p, size: .zero)
        }
        let h = bounds.height * heightFraction
        let w = h * (imageSize.width / imageSize.height)
        return CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h)
    }

    /// `CGEvent` lives in a top-origin world and everything else here does not,
    /// so one function owns the flip — the hover tap reads a point out of it and
    /// the pass-through click writes a point into it, and neither can pick a
    /// different `maxY` than the other.
    ///
    /// `screensMaxY` is the top of the union of all screen frames, which is what
    /// the window server flips about on a multi-screen Mac — not the height of
    /// the screen the button happens to be on.
    static func flipY(_ p: CGPoint, screensMaxY: CGFloat) -> CGPoint {
        CGPoint(x: p.x, y: screensMaxY - p.y)
    }

    // MARK: - Alpha hit-test

    /// The button's opaque pixels, as a grid small enough to keep in memory and
    /// ask 60 times a second.
    ///
    /// Row 0 is the **top** row, the way `CGImage` stores it — the flip into the
    /// bottom-origin world of layers and `NSEvent.mouseLocation` happens once, in
    /// [isOpaque], rather than at every call site.
    struct AlphaMask {
        let width: Int
        let height: Int
        /// `width * height` alpha bytes, row-major from the top.
        let alpha: [UInt8]

        init(width: Int, height: Int, alpha: [UInt8]) {
            self.width = width
            self.height = height
            self.alpha = alpha
        }

        /// Redraw the image into an 8-bit alpha-only bitmap. One allocation per
        /// effect run, not per event.
        init?(cgImage: CGImage) {
            let w = cgImage.width, h = cgImage.height
            guard w > 0, h > 0 else { return nil }
            var bytes = [UInt8](repeating: 0, count: w * h)
            let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress,
                                          width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
                else { return false }
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard ok else { return nil }
            self.init(width: w, height: h, alpha: bytes)
        }

        /// Alpha at a unit position, `(0,0)` = **top-left**. Out of range ⇒ 0.
        func alpha(atUnitX ux: CGFloat, unitY uy: CGFloat) -> UInt8 {
            guard ux >= 0, ux < 1, uy >= 0, uy < 1 else { return 0 }
            let col = min(width - 1, max(0, Int(ux * CGFloat(width))))
            let row = min(height - 1, max(0, Int(uy * CGFloat(height))))
            return alpha[row * width + col]
        }
    }

    /// Is `point` on the button itself rather than in the transparent corners of
    /// its bounding box?
    ///
    /// `point` and `frame` must be in the same **bottom-origin** space (both
    /// global screen coordinates, or both overlay-layer coordinates); the mask's
    /// rows are top-origin, hence the `1 -` on the vertical axis.
    ///
    /// Note which rectangle the caller is expected to pass: the **resting**
    /// frame, never the hovered one. Hit-testing the grown rectangle makes the
    /// edge bistable — the pointer crosses in, the button grows out to meet it,
    /// the pointer is now comfortably inside; the pointer leaves, the button
    /// shrinks away from it, it is outside again — and the boundary flickers at
    /// the frame rate.
    static func isOpaque(at point: CGPoint,
                         restingFrame frame: CGRect,
                         mask: AlphaMask,
                         threshold: UInt8 = alphaThreshold) -> Bool {
        guard frame.width > 0, frame.height > 0 else { return false }
        let ux = (point.x - frame.minX) / frame.width
        let uy = 1 - (point.y - frame.minY) / frame.height
        return mask.alpha(atUnitX: ux, unitY: uy) >= threshold
    }

    // MARK: - The state machine

    /// Where the button is in its one-way life. `zoomIn → idle ⇄ hover → pressed
    /// → shrink → done`, with every phase able to jump straight to `shrink`.
    enum Phase: Equatable {
        case zoomIn
        case idle
        case hover
        case pressed
        case shrink
        case done
    }

    enum Event: Equatable {
        /// The 0→1 zoom finished; the button is now clickable.
        case zoomDone
        /// The pointer moved onto the button's opaque pixels.
        case hoverEnter
        /// …and off them again (or off the screen).
        case hoverExit
        case mouseDown
        case mouseUp
        /// `maxLifetime` elapsed without a press.
        case timeout
        /// Esc, `/effect/stop-all`, or a second press of the tile.
        case dismiss
        /// The 1→0 shrink finished.
        case shrinkDone
    }

    enum Action: Equatable {
        case highlightOn
        case highlightOff
        case showPressedFrame
        case showRaisedFrame
        /// Call `onButtonClicked(origin:)`. The payoff hook — see the doc on
        /// `RedButtonController.onButtonClicked`.
        case click
        /// Shrink back into P **still pressed** — the button was clicked.
        case shrinkPressed
        /// Shrink back into P un-pressed — nobody pressed it.
        case shrinkRaised
        /// Tear everything down: the layer, the hit panel and the event tap.
        case end
    }

    /// The whole lifecycle as one pure function, so the order — and especially
    /// the "clicked ⇒ stays pressed, timed out ⇒ comes back up" distinction — is
    /// asserted without a screen.
    static func next(_ phase: Phase, _ event: Event) -> (Phase, [Action]) {
        switch (phase, event) {

        case (.zoomIn, .zoomDone):
            return (.idle, [])

        case (.idle, .hoverEnter):
            return (.hover, [.highlightOn])
        case (.hover, .hoverExit):
            return (.idle, [.highlightOff])

        case (.hover, .mouseDown):
            return (.pressed, [.showPressedFrame])
        // A press dragged off the button is a cancelled press, exactly like every
        // other button on the machine: it comes back up and nothing fires.
        case (.pressed, .hoverExit):
            return (.idle, [.showRaisedFrame, .highlightOff])
        case (.pressed, .mouseUp):
            return (.shrink, [.click, .shrinkPressed])

        // Nobody pressed it: it leaves the way it came, raised.
        case (.zoomIn, .timeout), (.idle, .timeout), (.hover, .timeout),
             (.zoomIn, .dismiss), (.idle, .dismiss), (.hover, .dismiss):
            return (.shrink, [.shrinkRaised])
        // Held down when the clock ran out. The finger was on it but the click
        // never completed, so the hook does NOT fire — and it still leaves.
        case (.pressed, .timeout), (.pressed, .dismiss):
            return (.shrink, [.shrinkRaised])

        case (.shrink, .shrinkDone):
            return (.done, [.end])
        // Esc during the shrink: skip the rest of the animation rather than
        // queue a second teardown.
        case (.shrink, .dismiss):
            return (.done, [.end])

        default:
            return (phase, [])
        }
    }
}

// MARK: - The clickable rectangle

/// The button's hit target: a second, small panel laid exactly over the artwork,
/// for `PeekHitPanel`'s reason — the desktop overlay is `ignoresMouseEvents =
/// true` so that effects can be drawn over a Mac somebody is still working on,
/// and flipping that for the whole screen would make the entire desktop deaf.
///
/// Two things it does that the mascot's panel does not:
///
///  - **It is only listening while the pointer is on an opaque pixel.**
///    `RedButtonController` flips `ignoresMouseEvents` from its event tap, so a
///    click in the transparent corners of the bounding box reaches the app
///    underneath instead of being eaten by a rectangle nobody can see. A circle
///    in a square wastes 21 % of its own area on those corners, and the button is
///    half the screen high.
///  - **The cursor is the pointing hand**, where the thumbnail panel's
///    `PanelCursor` pins the arrow. Same mechanism (a tracking area's
///    `cursorUpdate`, because a borderless non-activating panel does not own the
///    pointer's shape just by being on top), opposite answer: the board is a
///    surface, this is a button, and it has to *look* pressable before anyone
///    risks pressing it.
final class RedButtonHitPanel: NSPanel {
    private final class HitView: NSView {
        var onDown: (() -> Void)?
        var onUp: (() -> Void)?

        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeAlways],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseMoved(with event: NSEvent) { NSCursor.pointingHand.set() }
        override func mouseDown(with event: NSEvent) { onDown?() }
        override func mouseUp(with event: NSEvent) { onUp?() }
    }

    init(frame: NSRect, onDown: @escaping () -> Void, onUp: @escaping () -> Void) {
        super.init(contentRect: frame,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Deaf until the tap says the pointer is on an opaque pixel.
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        // Above the overlay it is a target for; a hit panel underneath the thing
        // it stands in front of would never see the click.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = HitView(frame: NSRect(origin: .zero, size: frame.size))
        view.onDown = onDown
        view.onUp = onUp
        contentView = view
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Take it down, restoring the pointer if it is still sitting on us — the
    /// hand must not outlive the button it was pointing at.
    func dismiss() {
        if frame.contains(NSEvent.mouseLocation) { NSCursor.arrow.set() }
        ignoresMouseEvents = true
        orderOut(nil)
    }
}

// MARK: - The run

/// One run of the red button: the layer, the hit panel, the event tap and the
/// phase it is in.
///
/// Not a `trackEffect` client on its own — like the fire cursor and the
/// bombardment it holds a tap and a real window, so it must be torn down through
/// [stop] and never only by the generic `activeEffects` sweep, which would drop
/// the artwork and leave an invisible rectangle eating clicks in the middle of
/// the screen. `EmojiAnimator.showRedButton` registers the layer with
/// `trackEffect` anyway so that `GET /state` can say it is up.
final class RedButtonController {

    /// **The extension point.** What happens at P after the button is pressed.
    ///
    /// `EmojiAnimator.showRedButton` assigns it to [deliverClickBelow], so the
    /// shipped payoff is "the click the button ate reaches the app underneath" —
    /// the button is a prop over a working Mac, and pressing a prop should not
    /// cost the press. Anything louder (a crack, a blast, a webhook) is a
    /// decision about the *room* and is wired at that one call site, touching
    /// nothing here — `origin` is the **global screen point** the button grew
    /// out of, which is the pixel the payoff is supposed to happen at.
    var onButtonClicked: ((_ origin: CGPoint) -> Void)?

    /// Called once, when the run is over, so the animator can forget it.
    var onFinished: (() -> Void)?

    /// The artwork. Handed to `trackEffect` so `/state` and `/effect/stop-all`
    /// can see the effect at all.
    let layer: CALayer

    /// Where the pointer was when the effect started, in global screen
    /// coordinates. The button grows out of it, shrinks back into it, and it is
    /// what [onButtonClicked] is handed.
    let origin: CGPoint

    private let raised: CGImage
    private let pressedImage: CGImage?
    private let mask: RedButton.AlphaMask
    /// The resting frame, in **global screen** coordinates — what the hit test
    /// and the hit panel both use.
    private let screenFrame: CGRect

    private var phase: RedButton.Phase = .zoomIn
    private var hitPanel: RedButtonHitPanel?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var lifetimeTimer: Timer?
    private var hovering = false

    /// The frames of the button GIF, decoded once per run.
    struct Frames {
        let raised: CGImage
        let pressed: CGImage?
        var hasPressFrame: Bool { pressed != nil }
        var size: CGSize { CGSize(width: raised.width, height: raised.height) }

        /// First frame raised, last frame pressed. A single-frame asset is
        /// legal — the press then falls back to squash-and-darken, which is why
        /// this returns `pressed: nil` rather than refusing to load.
        static func load(from url: URL) -> Frames? {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let count = CGImageSourceGetCount(src)
            guard count > 0, let first = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
            let last = count > 1 ? CGImageSourceCreateImageAtIndex(src, count - 1, nil) : nil
            return Frames(raised: first, pressed: last)
        }
    }

    /// `nil` when the asset is missing or unreadable — the caller logs one line
    /// and does nothing, and the clip still plays.
    init?(hostLayer: CALayer, origin: CGPoint, screenOrigin: CGPoint) {
        guard let url = EffectsConfig.shared.assetURL(RedButton.assetName),
              let frames = Frames.load(from: url),
              let mask = RedButton.AlphaMask(cgImage: frames.raised) else { return nil }

        self.raised = frames.raised
        self.pressedImage = frames.pressed
        self.mask = mask
        self.origin = origin

        // The overlay layer's bounds map 1:1 onto the overlay screen's frame, so
        // the only difference between the two coordinate systems is the screen's
        // origin — both are bottom-origin.
        let p = CGPoint(x: origin.x - screenOrigin.x, y: origin.y - screenOrigin.y)
        let box = RedButton.frame(imageSize: frames.size, in: hostLayer.bounds, centredOn: p)
        self.screenFrame = box.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y)

        let l = CALayer()
        l.bounds = CGRect(origin: .zero, size: box.size)
        l.position = CGPoint(x: box.midX, y: box.midY)
        l.contents = frames.raised
        l.contentsGravity = .resizeAspect
        l.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        // Above the ambient effects: it is a control, and something has to be
        // clickable on top of whatever else is on the desktop.
        l.zPosition = 9_800
        self.layer = l
        hostLayer.addSublayer(l)
    }

    var frameOnScreen: CGRect { screenFrame }
    var hasPressFrame: Bool { pressedImage != nil }

    // MARK: Start

    func start() {
        overlayInfo(String(format: "🔴 red button: %.0f×%.0f at P=(%.0f, %.0f), %.0fs to press it",
                           screenFrame.width, screenFrame.height, origin.x, origin.y,
                           RedButton.maxLifetime))

        // Zoom out of P: the anchor point is the layer's centre and the centre is
        // P, so a plain scale about the centre IS a zoom out of the pointer.
        let zoom = CABasicAnimation(keyPath: "transform.scale")
        zoom.fromValue = 0.0
        zoom.toValue = 1.0
        zoom.duration = RedButton.zoomInDuration
        zoom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        zoom.fillMode = .forwards
        layer.add(zoom, forKey: "redButtonZoom")

        startInputCapture()

        lifetimeTimer = Timer.scheduledTimer(withTimeInterval: RedButton.maxLifetime,
                                             repeats: false) { [weak self] _ in
            self?.handle(.timeout)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + RedButton.zoomInDuration) { [weak self] in
            guard let self, self.phase == .zoomIn else { return }
            self.handle(.zoomDone)
            self.hitPanel = RedButtonHitPanel(
                frame: self.screenFrame,
                onDown: { [weak self] in self?.handle(.mouseDown) },
                onUp: { [weak self] in self?.handle(.mouseUp) })
            // The pointer is almost certainly ALREADY on the button — it is
            // centred on the pointer — so evaluate the hover once instead of
            // waiting for a move that may never come.
            self.updateHover(at: NSEvent.mouseLocation)
        }
    }

    // MARK: Events

    /// Esc dismisses, and the pointer's position decides the hover.
    ///
    /// A tap and not an `NSEvent` global monitor for the fire cursor's reason: a
    /// monitor can only observe, and Escape has to be *taken away* from the app
    /// underneath — an Esc that also closed the user's dialog would make
    /// dismissing the button cost something. Mouse moves are only observed, so
    /// they go straight back out.
    private func startInputCapture() {
        stopInputCapture()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.mouseMoved.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let c = Unmanaged<RedButtonController>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let t = c.tap { CGEvent.tapEnable(tap: t, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown,
               CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == 53 {   // Esc
                DispatchQueue.main.async { c.handle(.dismiss) }
                return nil   // consume — the user is dismissing the button, not their app
            }
            if type == .mouseMoved || type == .leftMouseDragged {
                let p = event.location
                DispatchQueue.main.async { c.updateHover(atFlipped: p) }
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                        options: .defaultTap, eventsOfInterest: mask,
                                        callback: callback, userInfo: refcon) else {
            overlayError("🔴 red button: could not create the event tap — Esc will not dismiss it")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t
        tapSource = src
    }

    private func stopInputCapture() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        if let s = tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        tapSource = nil
    }

    /// A `CGEvent`'s location is top-origin; everything else here is not.
    private func updateHover(atFlipped p: CGPoint) {
        updateHover(at: RedButton.flipY(p, screensMaxY: RedButtonController.screensMaxY))
    }

    /// The top of the union of every screen — what `CGEvent` measures down from.
    static var screensMaxY: CGFloat {
        NSScreen.screens.map(\.frame).reduce(CGRect.null, { $0.union($1) }).maxY
    }

    /// Pass the press on to whatever the button was standing in front of.
    ///
    /// The button is a prop laid over a Mac somebody is still working on, so the
    /// press has to end where the pointer already was: a real left click at P,
    /// synthesised because the click the user actually made was consumed by the
    /// hit panel and can no longer be forwarded.
    ///
    /// **Posted a runloop turn late, on purpose.** `.click` fires before
    /// `.shrinkPressed` in the same `perform` loop, so at the moment the hook
    /// runs the hit panel is still up and still listening on the pixel the click
    /// is aimed at — posting there would hand the event straight back to us and
    /// press the button a second time. One `async` puts the post after
    /// `shrink()` has called `hitPanel.dismiss()`, which sets
    /// `ignoresMouseEvents = true` immediately, so the event falls through to
    /// the app below. The artwork is still shrinking over that pixel and does
    /// not care: the overlay panel ignores mouse events by construction.
    static func deliverClickBelow(at origin: CGPoint) {
        DispatchQueue.main.async {
            let p = RedButton.flipY(origin, screensMaxY: screensMaxY)
            let src = CGEventSource(stateID: .combinedSessionState)
            guard let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                     mouseCursorPosition: p, mouseButton: .left),
                  let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                                   mouseCursorPosition: p, mouseButton: .left) else {
                overlayError("🔴 red button: could not synthesise the pass-through click")
                return
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            overlayInfo(String(format: "🔴 red button: click passed through to P=(%.0f, %.0f)",
                               origin.x, origin.y))
        }
    }

    /// The one place `ignoresMouseEvents` is decided: the panel listens exactly
    /// while the pointer is on a pixel of the button, so its transparent corners
    /// stay click-through and the pointing hand appears on the artwork rather
    /// than on its bounding box.
    private func updateHover(at global: CGPoint) {
        guard phase == .idle || phase == .hover || phase == .pressed else { return }
        let inside = RedButton.isOpaque(at: global, restingFrame: screenFrame, mask: mask)
        // The hand is re-asserted on EVERY move that is on the button, not only
        // on the move that arrived there. The app underneath still owns the
        // pointer's shape and restores its own cursor on each move it sees, so a
        // single `.set()` at the boundary survives exactly until the next mouse
        // event — which is why the hand used to flicker back to an I-beam or an
        // arrow while the pointer was sitting on the artwork. `PanelCursor` in
        // `ThumbnailGridView` pins the arrow the same way, for the same reason.
        if inside { NSCursor.pointingHand.set() }
        guard inside != hovering else { return }
        hovering = inside
        hitPanel?.ignoresMouseEvents = !inside
        if inside {
            handle(.hoverEnter)
        } else {
            NSCursor.arrow.set()
            handle(.hoverExit)
        }
    }

    func dismiss() { handle(.dismiss) }

    private func handle(_ event: RedButton.Event) {
        let (next, actions) = RedButton.next(phase, event)
        phase = next
        for action in actions { perform(action) }
    }

    private func perform(_ action: RedButton.Action) {
        switch action {
        case .highlightOn:  setLook(scale: RedButton.hoverScale, brightness: RedButton.hoverBrightness)
        case .highlightOff: setLook(scale: 1.0, brightness: 0)
        case .showPressedFrame:
            if let pressedImage {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.contents = pressedImage
                CATransaction.commit()
                setLook(scale: 1.0, brightness: 0)
            } else {
                // No pressed frame in the asset: squash and darken instead, so a
                // one-frame replacement still *feels* like a button going down.
                setLook(scale: RedButton.fallbackPressScale,
                        brightness: RedButton.fallbackPressBrightness)
            }
        case .showRaisedFrame:
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = raised
            CATransaction.commit()
            setLook(scale: 1.0, brightness: 0)
        case .click:
            overlayInfo(String(format: "🔴 red button clicked — origin P=(%.0f, %.0f)",
                               origin.x, origin.y))
            onButtonClicked?(origin)
        case .shrinkPressed:
            shrink()
        case .shrinkRaised:
            perform(.showRaisedFrame)
            shrink()
        case .end:
            stop()
        }
    }

    /// Hover/press look. The scale rides on top of whatever the zoom left behind,
    /// so it is set on the layer's own transform rather than animated from a
    /// `fromValue` that a half-finished zoom would make wrong.
    private func setLook(scale: CGFloat, brightness: Double) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        layer.transform = CATransform3DMakeScale(scale, scale, 1)
        if brightness == 0 {
            layer.filters = nil
        } else if let f = CIFilter(name: "CIColorControls") {
            f.setValue(brightness, forKey: "inputBrightness")
            layer.filters = [f]
        }
        CATransaction.commit()
    }

    /// Back into P, and then gone. The pointer goes back to the arrow and the hit
    /// panel is taken down *first*: the button is leaving, and a hand hovering
    /// over a shrinking picture — or worse, an invisible rectangle still eating
    /// clicks at full size — outlives what it belonged to.
    private func shrink() {
        lifetimeTimer?.invalidate()
        lifetimeTimer = nil
        hitPanel?.dismiss()
        hitPanel = nil
        hovering = false

        let out = CABasicAnimation(keyPath: "transform.scale")
        out.fromValue = layer.presentation()?.value(forKeyPath: "transform.scale") ?? 1.0
        out.toValue = 0.0
        out.duration = RedButton.shrinkDuration
        out.timingFunction = CAMediaTimingFunction(name: .easeIn)
        out.fillMode = .forwards
        out.isRemovedOnCompletion = false
        layer.add(out, forKey: "redButtonShrink")

        DispatchQueue.main.asyncAfter(deadline: .now() + RedButton.shrinkDuration) { [weak self] in
            self?.handle(.shrinkDone)
        }
    }

    /// Idempotent: the click, the timeout, Escape and `stop-all` all funnel here,
    /// which is the only reason it is safe for four callers to race.
    func stop() {
        phase = .done
        lifetimeTimer?.invalidate()
        lifetimeTimer = nil
        stopInputCapture()
        hitPanel?.dismiss()
        hitPanel = nil
        layer.removeAllAnimations()
        layer.removeFromSuperlayer()
        let finished = onFinished
        onFinished = nil
        finished?()
    }
}
