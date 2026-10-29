import AppKit

/// ✋ Tile #35 (`35_cant_touch_this.mp3`, MC Hammer): **the pointer IS a stop
/// hand, and a click stamps one where it lands** (2026-10-30, Victor: *"dacă
/// apăs cu mouse-ul o să lase în urmă semnul acesta … clipește de trei ori unde
/// am lăsat, plus unde e mouse-ul meu"*).
///
/// - The real cursor is hidden and the sign rides the mouse, centred on it.
/// - Every click is **taken from the app underneath** — the joke is that the
///   desktop can't be touched — and leaves a copy of the sign on that spot.
/// - On every stamp **all the signs blink three times in unison**: the ones
///   already on the desktop, the new one and the one on the pointer. One shared
///   animation, added to every layer in one transaction, so they cannot drift.
/// - Lives for the clip, Escape ends it early, a re-press or stop-all too.
///
/// The picture is the lit frame of Wikimedia's *Blinking Stop hand.gif*
/// (CC BY-SA 3.0, `Resources/CREDITS.md`); the GIF's own blink (1 s on, 1 s off)
/// is far too slow for a click, so the blink is drawn here instead.
///
/// Not a `trackEffect` client, for the chainsaw's reason: it owns a follow
/// timer, a tap swallowing clicks and a hidden system cursor, which a generic
/// sweep of `activeEffects` would strand.
final class CantTouchThisSession {

    // MARK: Tuning (pure, asserted in CantTouchThisTests)

    /// The sign's width on screen. 120 pt = the GIF's 240 px at Retina 2×, so
    /// it is drawn pixel for pixel.
    static let signWidth: CGFloat = 120
    static let blinkCount = 3
    /// One blink = this long dark, then this long lit. Fast enough to read as a
    /// flash answering the click, slow enough to count three on a projector.
    static let blinkHalfPeriod: Double = 0.14
    /// Ceiling on stamps, for a stuck button: past it the oldest goes.
    static let maxStamps = 60
    static let fadeOut: Double = 0.35
    /// The clip's length if it cannot be read from `soundsDir`.
    static let fallbackDuration: Double = 8.9
    /// Above the fireball's 9 350, so a hand stamped over a fire is seen.
    static let zPosition: CGFloat = 9_400

    /// Lit → dark → lit, `blinkCount` times, ending lit. Discrete, so each
    /// state is a clean on/off like the GIF's, never a cross-fade.
    static func blinkAnimation() -> CAKeyframeAnimation {
        var values: [Float] = []
        for _ in 0..<blinkCount { values += [0, 1] }
        let anim = CAKeyframeAnimation(keyPath: "opacity")
        anim.values = values
        anim.keyTimes = (0..<values.count).map { NSNumber(value: Double($0) / Double(values.count)) }
        anim.calculationMode = .discrete
        anim.duration = Double(values.count) * blinkHalfPeriod
        return anim
    }

    // MARK: State

    private let hostLayer: CALayer
    private let mousePoint: () -> CGPoint
    private let image: CGImage
    private let baseSize: CGSize
    private var pointer: CALayer?
    private var stamps: [CALayer] = []
    private var timer: Timer?
    private var hidCursor = false
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var swallowingPress = false
    private var ended = false
    /// Called once, after the last layer is gone and the cursor is back.
    var onEnded: (() -> Void)?

    var isRunning: Bool { !ended }

    init?(hostLayer: CALayer, mousePoint: @escaping () -> CGPoint) {
        guard let url = EffectsResources.url("stop-hand", "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            overlayError("stop-hand.png not found in bundle")
            return nil
        }
        self.hostLayer = hostLayer
        self.mousePoint = mousePoint
        self.image = image
        self.baseSize = CGSize(width: Self.signWidth,
                               height: Self.signWidth * CGFloat(image.height) / CGFloat(image.width))
    }

    func start(duration: Double) {
        let sign = makeSign()
        EmojiAnimator.fitPointerSprite(sign, base: baseSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sign.position = mousePoint()
        hostLayer.addSublayer(sign)
        CATransaction.commit()
        pointer = sign

        EmojiAnimator.armBackgroundCursorHiding()
        NSCursor.hide()
        CGDisplayHideCursor(CGMainDisplayID())
        hidCursor = true

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self, self.timer === t, let sign = self.pointer else { t.invalidate(); return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            sign.position = self.mousePoint()
            EmojiAnimator.fitPointerSprite(sign, base: self.baseSize)
            CATransaction.commit()
        }
        startInputCapture()
        // The self-termination rule: the clip's length is the end, whatever
        // the tablet does or doesn't report.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.stop()
        }
        effectsInfo("✋ can't touch this — up for \(String(format: "%.1f", duration)) s")
    }

    private func makeSign() -> CALayer {
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: baseSize)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        layer.zPosition = Self.zPosition
        return layer
    }

    /// A click: a sign stays where the pointer's was, then every sign on screen
    /// blinks together.
    private func stamp() {
        guard let pointer else { return }
        let sign = makeSign()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sign.position = pointer.position
        // Glued to the desktop like the planted fires: drawn at its unzoomed
        // size, so under ⌥-scroll zoom it grows with what it was stamped on.
        hostLayer.insertSublayer(sign, below: pointer)
        CATransaction.commit()
        stamps.append(sign)
        if stamps.count > Self.maxStamps { stamps.removeFirst().removeFromSuperlayer() }
        effectsInfo("✋ stamp #\(stamps.count) at \(Int(sign.position.x)),\(Int(sign.position.y))")

        // One transaction, one animation object copied onto every layer: they
        // all start on the same frame, so the blink is in unison by
        // construction. A stamp mid-blink restarts it for all of them.
        let blink = Self.blinkAnimation()
        CATransaction.begin()
        for layer in stamps + [pointer] { layer.add(blink, forKey: "blink") }
        CATransaction.commit()
    }

    /// Idempotent: Escape, the clip's end, the tablet's stop, a re-press and
    /// stop-all all land here.
    func stop(fade: Double = CantTouchThisSession.fadeOut) {
        guard !ended else { return }
        ended = true
        timer?.invalidate(); timer = nil
        stopInputCapture()
        let layers = stamps + [pointer].compactMap { $0 }
        stamps = []
        pointer = nil

        let teardown = { [weak self] in
            for layer in layers { layer.removeAllAnimations(); layer.removeFromSuperlayer() }
            guard let self else { return }
            if self.hidCursor {
                NSCursor.unhide()
                CGDisplayShowCursor(CGMainDisplayID())
                self.hidCursor = false
            }
            effectsInfo("✋ can't touch this — put away")
            self.onEnded?()
        }
        guard fade > 0, !layers.isEmpty else { teardown(); return }
        for layer in layers {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = layer.presentation()?.opacity ?? 1
            fadeOut.toValue = 0
            fadeOut.duration = fade
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "fadeOut")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: teardown)
    }

    // MARK: The tap — the AK-47's rule (`minigunMouseDecision`), reused as is

    private func startInputCapture() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let session = Unmanaged<CantTouchThisSession>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = session.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                guard CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == 53 else {   // Esc
                    return Unmanaged.passUnretained(event)
                }
                DispatchQueue.main.async { session.stop() }
                return nil
            }
            let phase: EmojiAnimator.MinigunMousePhase = type == .leftMouseDown ? .down
                : type == .leftMouseUp ? .up : .dragged
            switch EmojiAnimator.minigunMouseDecision(phase, armed: session.pointer != nil,
                                                      swallowingPress: session.swallowingPress) {
            case .pullTrigger:
                session.swallowingPress = true
                session.stamp()
                return nil
            case .releaseTrigger:
                session.swallowingPress = false
                return nil
            case .moveOnly:
                // A drag of a press we took: still moves the pointer (and the
                // sign on it), never reaches the app as half a click.
                event.type = .mouseMoved
                return Unmanaged.passUnretained(event)
            case .pass:
                return Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: refcon) else {
            overlayError("✋ could not install the click tap (Accessibility?) — clicks won't stamp")
            return
        }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = src
    }

    private func stopInputCapture() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
        swallowingPress = false
    }
}
