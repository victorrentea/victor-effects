import AppKit

/// One display, as the placement rule sees it.
///
/// A value type and not `NSScreen` because `NSScreen` cannot be constructed: a
/// rule that took real screens could only ever be tested on the machine it was
/// written on, and the interesting layouts (a venue where the projector is the
/// primary, a three-screen desk) are exactly the ones that machine does not
/// have at the moment the rule is being written.
struct PanelScreen: Equatable {
    let name: String
    let visibleFrame: NSRect
    /// The WHOLE display, menu bar and Dock included — what a panel that owns
    /// the screen covers. `visibleFrame` is the polite area an ordinary window
    /// gets; this panel is not an ordinary window.
    let fullFrame: NSRect
    /// `NSScreen.screens[0]` — the one macOS calls main, with the menu bar.
    let isPrimary: Bool
    /// The screen the effects overlay covers (`Screens.overlayScreen()`), which
    /// on this rig is the built-in retina — the one mirrored to the room.
    let isOverlay: Bool

    /// `fullFrame` defaults to `visibleFrame` so the corner layout's tests, which
    /// only ever cared about the polite area, keep describing one rectangle.
    init(name: String, visibleFrame: NSRect, fullFrame: NSRect? = nil,
         isPrimary: Bool, isOverlay: Bool) {
        self.name = name
        self.visibleFrame = visibleFrame
        self.fullFrame = fullFrame ?? visibleFrame
        self.isPrimary = isPrimary
        self.isOverlay = isOverlay
    }
}

/// Where the thumbnail panel goes. Pure, so the four layouts that matter are
/// unit tests instead of a trip to a venue with a projector.
///
/// The rule is "**not the projected screen, and preferably not the primary**",
/// not the simpler "not the main screen". At home the built-in retina is both
/// primary and the projected screen, so the two rules agree. At a venue the
/// ASUS is made primary while the retina is mirrored to the room — and there
/// the literal "non-main" rule puts the soundboard on the projector, in front
/// of the audience, which is the one place it must never be.
enum ThumbnailPanelPlacement {
    /// Gap between the panel and the screen edges when it fills a screen.
    ///
    /// **Zero since 14 Sep 2026.** It was 24 pt of breathing room, and what
    /// Victor saw on the second screen was a band of desktop down each side of
    /// a board that is supposed to BE that screen while the key is held. When
    /// the panel has a screen to itself there is nothing to breathe away from.
    static let inset: CGFloat = 0
    /// Gap in the single-screen, bottom-right corner layout.
    static let margin: CGFloat = 16
    /// Fraction of a shared screen the panel takes, as a numerator over 3.
    /// Written as a division rather than a decimal because `1728 * 0.666…`
    /// floors to 1151 and `1728 * 2 / 3` is 1152 — one pixel of arithmetic
    /// noise that a test asserting the two thirds would trip over.
    static let soloNumerator: CGFloat = 2

    /// Where the panel keeps its edge when it is shortened to hug the grid.
    enum VerticalAnchor: Equatable {
        /// The bottom-right corner layout: the bottom edge is the fixed one,
        /// so shortening the panel lowers its top and the corner stays put.
        case bottom
        /// The filled-screen layout: nothing anchors it, so it stays centred.
        case centred
    }

    struct Placement: Equatable {
        let screen: PanelScreen
        let frame: NSRect
        let anchor: VerticalAnchor
    }

    /// Shorten a placed frame to the height the grid actually draws at.
    ///
    /// The cells are square and fit both ways, so whenever the **width** is
    /// what binds — 13 columns is usually is — the grid comes out shorter than
    /// the frame and the remainder is black. This trims it. It only ever
    /// shrinks: a grid taller than its frame is already the shrunk-cell case
    /// and wants every point it was given.
    static func hug(_ frame: NSRect, toContentHeight height: CGFloat,
                    anchor: VerticalAnchor) -> NSRect {
        // A panel that owns its screen is never hugged: trimming it to the grid
        // is the OTHER way the second screen ended up with desktop showing
        // around the board. Hugging is for the corner layout, where the panel
        // shares a screen and every point it does not need belongs to the slide
        // behind it.
        guard anchor != .centred else { return frame }
        let h = min(frame.height, max(0, height)).rounded(.down)
        guard h < frame.height else { return frame }
        let y: CGFloat
        switch anchor {
        case .bottom: y = frame.minY
        case .centred: y = (frame.minY + (frame.height - h) / 2).rounded()
        }
        return NSRect(x: frame.minX, y: y, width: frame.width, height: h)
    }

    static func choose(screens: [PanelScreen], mouse: NSPoint? = nil) -> Placement? {
        guard !screens.isEmpty else { return nil }

        // One screen: the panel has to share it with whatever is being shown,
        // so it takes two thirds and sits in the bottom-right corner — away
        // from the menu bar and from the top-left of a slide.
        if screens.count == 1 {
            let s = screens[0]
            let w = (s.visibleFrame.width * soloNumerator / 3).rounded(.down)
            let h = (s.visibleFrame.height * soloNumerator / 3).rounded(.down)
            let origin = NSPoint(x: s.visibleFrame.maxX - w - margin,
                                 y: s.visibleFrame.minY + margin)
            return Placement(screen: s,
                             frame: NSRect(origin: origin, size: NSSize(width: w, height: h)),
                             anchor: .bottom)
        }

        // Never the projected screen. If every screen is projected (a mirrored
        // single-display rig reported as two), fall back rather than draw
        // nowhere — a panel on the projector beats no panel at all.
        var pool = screens.filter { !$0.isOverlay }
        if pool.isEmpty { pool = screens }

        // Prefer a screen that is not the primary: the primary is where the
        // work happens. If the only non-projected screen IS the primary (the
        // venue rig: ASUS primary + mirrored retina), take it.
        let nonPrimary = pool.filter { !$0.isPrimary }
        if !nonPrimary.isEmpty { pool = nonPrimary }

        // The whole display, not the polite `visibleFrame`: with a screen to
        // itself the panel covers the menu bar and the Dock too, which is what
        // "full screen" means to the person holding the key down.
        let chosen = pick(from: pool, mouse: mouse)
        return Placement(screen: chosen,
                         frame: chosen.fullFrame.insetBy(dx: inset, dy: inset),
                         anchor: .centred)
    }

    /// Tie-break among equally eligible screens: the one the mouse is on (the
    /// hand is already there), else the largest (most tiles legible).
    private static func pick(from pool: [PanelScreen], mouse: NSPoint?) -> PanelScreen {
        if let mouse, let under = pool.first(where: { $0.visibleFrame.contains(mouse) }) {
            return under
        }
        return pool.max { a, b in
            a.visibleFrame.width * a.visibleFrame.height < b.visibleFrame.width * b.visibleFrame.height
        } ?? pool[0]
    }

    // MARK: - The live machine

    /// This Mac's screens right now, tagged for the rule above.
    static func currentScreens() -> [PanelScreen] {
        let overlay = Screens.overlayScreen()
        return NSScreen.screens.enumerated().map { index, screen in
            PanelScreen(name: screen.localizedName,
                        visibleFrame: screen.visibleFrame,
                        fullFrame: screen.frame,
                        isPrimary: index == 0,
                        isOverlay: screen == overlay)
        }
    }
}
