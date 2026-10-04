import AppKit

/// Which robot leans in from the left on ⌘⌃Q.
///
/// The raw value is the bundle resource name, so a mascot is one thing rather
/// than a name plus a lookup table that can disagree with it.
enum PeekMascot: String, CaseIterable {
    case claude = "claude-icon"
    case copilot = "copilot-icon"

    /// The other one. A two-case enum is the whole reason the click is a
    /// *toggle* and not a menu: there is nothing to choose between.
    var flipped: PeekMascot { self == .claude ? .copilot : .claude }
}

/// Who waves on ⌘⌃Q, as pure functions over what is stored.
///
/// **It used to alternate press by press** — Claude, Copilot, Claude — which
/// made the mascot a coin toss: at any given press Victor could not say which
/// robot the room was about to see, and during a Claude course the wrong one
/// arrives half the time. So the rotation is gone (2026-09-10) and the key has
/// a *state* instead:
///
/// - **Every day starts as Claude.** The default is not "whatever was last
///   used" because the courses are mostly Claude courses; a day that opens on
///   Copilot would be a surprise inherited from a day that is over.
/// - **Clicking the mascot while it is on screen flips it**, and the flip is
///   sticky for the rest of that calendar day — a Copilot day is declared once
///   and stays declared, rather than being re-declared before every press.
/// - **Clicking again flips back.** The gesture is its own undo, which is what
///   makes it safe to try mid-session in front of a room.
///
/// Day-scoping is the same trick as `BreakCountries.savedToday()`: store the
/// pick *and* the `yyyy-MM-dd` it was made on, and treat a stamp that is not
/// today as nothing stored. No timer has to fire at midnight and no state has
/// to be cleaned up — a stale pick simply stops being true.
///
/// The functions here take the stored pair rather than reading `UserDefaults`
/// so the day rollover can be tested by passing a date instead of by waiting
/// for one; `PeekMascotStore` is the thin layer that actually persists.
enum PeekMascotChoice {
    /// What a day opens with, before anybody clicks anything.
    static let dayDefault: PeekMascot = .claude

    /// The local calendar day, `yyyy-MM-dd`, used to scope a pick to one day.
    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The mascot a stored pick means at `now` — the default whenever nothing
    /// is stored, the stamp belongs to another day, or the stored name is not a
    /// mascot any more (a rename must not leave the key showing nothing).
    static func resolve(stored: String?, storedDay: String?, now: Date) -> PeekMascot {
        guard let stored, let storedDay,
              storedDay == dayKey(now),
              let mascot = PeekMascot(rawValue: stored) else { return dayDefault }
        return mascot
    }

    /// Where a click lands: the other one, computed from what is showing rather
    /// than from what is stored, so a click on a *stale* pick flips away from
    /// the robot on screen instead of back onto it.
    static func flipped(stored: String?, storedDay: String?, now: Date) -> PeekMascot {
        resolve(stored: stored, storedDay: storedDay, now: now).flipped
    }
}

/// `PeekMascotChoice` with `UserDefaults` behind it.
///
/// Persisting rather than holding the pick in memory is deliberate: this app is
/// rebuilt and restarted several times an hour, and a choice that a `pkill`
/// undoes is not a choice that survives a course day.
enum PeekMascotStore {
    private static let kMascot = "ClaudePeek.mascot"
    private static let kDay = "ClaudePeek.mascot.day"

    private static func stored() -> (String?, String?) {
        let d = UserDefaults.standard
        return (d.string(forKey: kMascot), d.string(forKey: kDay))
    }

    /// Who waves on the next press.
    static func current(now: Date = Date()) -> PeekMascot {
        let (mascot, day) = stored()
        return PeekMascotChoice.resolve(stored: mascot, storedDay: day, now: now)
    }

    /// Flip, persist, and hand back who is on duty now.
    @discardableResult
    static func flip(now: Date = Date()) -> PeekMascot {
        let (mascot, day) = stored()
        let next = PeekMascotChoice.flipped(stored: mascot, storedDay: day, now: now)
        let d = UserDefaults.standard
        d.set(next.rawValue, forKey: kMascot)
        d.set(PeekMascotChoice.dayKey(now), forKey: kDay)
        return next
    }
}

/// The one clickable rectangle on an otherwise click-through overlay.
///
/// The desktop overlay (`OverlayPanel`) sets `ignoresMouseEvents = true` for
/// everything, which is what lets effects be drawn over a Mac somebody is still
/// working on. Flipping that flag while the mascot shows would make the *whole
/// screen* deaf for five seconds, so instead this is a second, tiny panel laid
/// exactly over the icon: a click-target the size of the thing being clicked.
///
/// It costs what it costs — for the mascot's ~5 s a click in that rectangle
/// does not reach the app underneath, and since 2026-09-21 the rectangle is
/// four times the area it was. That is affordable only because of where the
/// mascot lands: the top-left quarter is the **last** one
/// `TerminalTileLayout.fillOrder` hands out, so of the whole screen it is the
/// least likely to have anything under it worth clicking.
///
/// It is `.nonactivatingPanel` and never becomes key, so clicking the mascot
/// does not take focus off whatever Victor was typing in — the same requirement
/// the Break timer's panel has, and the reason the cursor is set imperatively
/// from a tracking area rather than only through `resetCursorRects`.
/// 🎅 Clawd wears a Santa hat on every other entrance (2026-10-04): *"alternativ
/// când intră pe ecran (o dată cu, o dată fără)"*.
///
/// **The hat is Victor's picture, not a drawing.** Five hats were drawn first —
/// blocky, tilted, Codex's — and all of them *"arată rău"*; the one that stuck
/// is a 46×41 pixel-art hat he supplied, sampled back to its own grid and
/// blown up ×5 with nearest-neighbour so its pixels stay as square as Clawd's.
///
/// **Big, and slumped over the right hand.** At least a third of the head's
/// width was the floor (*"măcar o treime"*), then *"mai mare"* than 48%, with
/// *"moțul căciulii să vină peste mânuța dreaptă"* — so it is 230 px over a
/// 376 px head (61%), the pompom on the top edge of the right hand, then
/// nudged right by 10% of its own width so the brim clears the right eye.
///
/// **Only Clawd wears it.** Copilot has no head corner to put it on, and an
/// entrance as Copilot does not use up a turn of the alternation.
enum PeekSantaHat {
    static let resource = "santa-hat"

    /// Where the hat's top-left corner lands, in `claude-icon.png` pixels with
    /// y DOWN (the way an image editor counts): 64 px above the head, so the
    /// picture grows upwards and never pushes the body down.
    static let origin = CGPoint(x: 264, y: -64)

    /// The union of the body and the hat, in the same y-down icon pixels.
    static func canvas(icon: CGSize, hat: CGSize) -> CGRect {
        CGRect(origin: .zero, size: icon)
            .union(CGRect(origin: origin, size: hat))
    }

    /// Where the hatted picture goes so the **body inside it lands exactly
    /// where the bare one would** — same scale, same left edge, same feet. Sized
    /// off its own taller height instead, Clawd would shrink by a sixth the
    /// moment he put a hat on. `plainFrame` is the bare icon's
    /// `claudePeekFrame`; `pad` is the rim both pictures wear. y-up, like the
    /// host layer.
    static func frame(plainFrame: CGRect, icon: CGSize, hat: CGSize, pad: CGFloat) -> CGRect {
        let c = canvas(icon: icon, hat: hat)
        let s = plainFrame.height / (icon.height + 2 * pad)
        return CGRect(
            x: plainFrame.minX + c.minX * s,
            y: plainFrame.minY - (c.maxY - icon.height) * s,
            width: (c.width + 2 * pad) * s,
            height: (c.height + 2 * pad) * s)
    }

    /// Bare icon + hat, flattened into one picture so the white rim goes round
    /// the pair as one silhouette — a hat outlined on its own would draw a white
    /// seam across Clawd's forehead.
    static func composite(icon: CGImage, hat: CGImage) -> CGImage? {
        let iconSize = CGSize(width: icon.width, height: icon.height)
        let hatSize = CGSize(width: hat.width, height: hat.height)
        let c = canvas(icon: iconSize, hat: hatSize)
        guard let ctx = CGContext(
            data: nil, width: Int(c.width), height: Int(c.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // CGContext is y-up: a y-down top `t` becomes a bottom of height - t - h.
        func draw(_ image: CGImage, at topLeft: CGPoint, _ size: CGSize) {
            ctx.draw(image, in: CGRect(
                x: topLeft.x - c.minX,
                y: c.height - (topLeft.y - c.minY) - size.height,
                width: size.width, height: size.height))
        }
        ctx.interpolationQuality = .none
        draw(icon, at: .zero, iconSize)
        draw(hat, at: origin, hatSize)
        return ctx.makeImage()
    }

    /// Whether this entrance wears the hat, given what was stored after the
    /// last one. Nothing stored means yes: the first entrance after the hat
    /// shipped is the one that shows it exists.
    static func wears(stored: Bool?) -> Bool { stored ?? true }
}

/// The alternation, kept in `UserDefaults` so a restart — several an hour —
/// does not reset it to "hat" every time and turn "every other" into "always".
enum PeekSantaHatStore {
    private static let kWearsNext = "ClaudePeek.santa.wearsNext"

    /// This entrance's answer, flipping the stored one for the next.
    static func takeTurn() -> Bool {
        let d = UserDefaults.standard
        let wears = PeekSantaHat.wears(stored: d.object(forKey: kWearsNext) as? Bool)
        d.set(!wears, forKey: kWearsNext)
        return wears
    }
}

final class PeekHitPanel: NSPanel {
    private final class HitView: NSView {
        var onClick: (() -> Void)?

        // Cursor rectangles are AppKit's standard per-region hover cursor and
        // work with the window un-key; the tracking area's `cursorUpdate` is the
        // belt to that braces, because a borderless non-activating panel is
        // exactly the case where cursor rects are least reliable.
        override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

        override func cursorUpdate(with event: NSEvent) { NSCursor.pointingHand.set() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: bounds,
                options: [.cursorUpdate, .mouseEnteredAndExited, .activeAlways],
                owner: self
            ))
        }

        override func mouseEntered(with event: NSEvent) { NSCursor.pointingHand.set() }

        // Put the plain arrow back by hand: nothing else will, because the
        // panel is not the active app's key window and the mascot can also
        // vanish from under the pointer when its five seconds are up.
        override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

        override func mouseDown(with event: NSEvent) { onClick?() }
    }

    init(frame: NSRect, onClick: @escaping () -> Void) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        // Above the overlay it sits on: the overlay is at the maximum window
        // level, and a hit target under the thing it is a target for would
        // never see the click.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = HitView(frame: NSRect(origin: .zero, size: frame.size))
        view.onClick = onClick
        contentView = view
        setFrame(frame, display: false)
        orderFrontRegardless()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Take it down, restoring the pointer if it is still sitting on us — the
    /// hand cursor must not outlive the thing it was pointing at.
    func dismiss() {
        if frame.contains(NSEvent.mouseLocation) { NSCursor.arrow.set() }
        orderOut(nil)
    }
}

/// The white rim the mascot wears on its way in.
///
/// Both PNGs are cut-outs with a real alpha channel, which is what lets the
/// robot float over the desktop instead of arriving on a card — but a cut-out
/// only reads as well as the desktop behind it lets it. The Claude mark is a
/// mid-orange (#D97757) and the Copilot one is near-black line art; on a dark
/// editor, a dark slide or a terminal filling the top-left quarter, the
/// silhouette dissolves into the background and the wave lands on nobody.
///
/// So the mascot is stroked in white before it is ever shown — the same trick a
/// sticker uses, and the reason stickers survive being put on any surface. A
/// white rim is the one colour that separates from a dark background *and* from
/// the two mascots, which are warm-orange and near-black; the alternative,
/// tinting the background, would mean a card, and the card is precisely what the
/// cut-out was for.
///
/// The rim is built from the image's own alpha: the silhouette is stamped in
/// white at a ring of offsets and the original is drawn on top, which is the
/// cheap approximation of a morphological dilate. **Two rings, not one** — a
/// single ring at the full radius leaves gaps in features thinner than the rim
/// (the robot's legs and arms are only a few dozen pixels wide), because a point
/// just outside a thin limb is not reachable by shifting that limb by the full
/// radius in any one direction.
///
/// Pure functions over a `CGImage` so the geometry can be asserted off-screen.
enum PeekMascotOutline {
    /// Rim thickness as a fraction of the source image's **height**, matching
    /// how `claudePeekFrame` sizes the mascot: the icon is drawn at a fixed
    /// fraction of the screen height, so a rim measured off the height is the
    /// same number of projected points whichever mascot is on duty and whatever
    /// the PNG's own resolution turns out to be. It is left **proportional** —
    /// when the icon doubled to 42% of the height on 2026-09-21 the rim doubled
    /// with it, ~4 pt to ~8 pt on the projector, because a sticker twice the
    /// size wears a border twice as thick; a rim pinned to its old thickness on
    /// a mascot this big would read as a hairline, not as a cut-out.
    static let widthFraction: CGFloat = 0.02

    /// Rim thickness in source pixels, never below 3 so a small PNG still gets
    /// a rim rather than a suggestion of one.
    static func ringWidth(forHeight height: Int) -> Int {
        max(3, Int((CGFloat(height) * widthFraction).rounded()))
    }

    /// The mascot with a white rim around it, padded by the rim on all four
    /// sides so the stroke has somewhere to live. Nil only if a bitmap context
    /// cannot be made, in which case the caller shows the bare cut-out.
    ///
    /// `pad` overrides the rim: the hatted Clawd is taller than the bare one,
    /// and a rim measured off *its* height would come out thicker around the
    /// very same body.
    static func outlined(_ image: CGImage, pad: Int? = nil) -> CGImage? {
        let pad = pad ?? ringWidth(forHeight: image.height)
        let size = CGSize(width: image.width, height: image.height)
        guard let silhouette = whiteSilhouette(image),
              let ctx = context(width: image.width + 2 * pad, height: image.height + 2 * pad)
        else { return nil }

        let steps = 16
        for ring in [CGFloat(pad), CGFloat(pad) / 2] {
            for i in 0..<steps {
                let angle = 2 * CGFloat.pi * CGFloat(i) / CGFloat(steps)
                ctx.draw(silhouette, in: CGRect(
                    x: CGFloat(pad) + cos(angle) * ring,
                    y: CGFloat(pad) + sin(angle) * ring,
                    width: size.width, height: size.height))
            }
        }
        ctx.draw(image, in: CGRect(x: CGFloat(pad), y: CGFloat(pad), width: size.width, height: size.height))
        return ctx.makeImage()
    }

    /// The image's alpha channel painted solid white: draw it, then fill white
    /// through `.sourceIn`, which keeps the destination's alpha and replaces
    /// every colour under it. Cheaper and more faithful than re-deriving the
    /// shape, because it is literally the shape that will be drawn on top.
    private static func whiteSilhouette(_ image: CGImage) -> CGImage? {
        guard let ctx = context(width: image.width, height: image.height) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.draw(image, in: rect)
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        return ctx.makeImage()
    }

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}
