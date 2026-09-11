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
    /// `NSScreen.screens[0]` — the one macOS calls main, with the menu bar.
    let isPrimary: Bool
    /// The screen the effects overlay covers (`Screens.overlayScreen()`), which
    /// on this rig is the built-in retina — the one mirrored to the room.
    let isOverlay: Bool
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
    static let inset: CGFloat = 24
    /// Gap in the single-screen, bottom-right corner layout.
    static let margin: CGFloat = 16
    /// Fraction of a shared screen the panel takes, as a numerator over 3.
    /// Written as a division rather than a decimal because `1728 * 0.666…`
    /// floors to 1151 and `1728 * 2 / 3` is 1152 — one pixel of arithmetic
    /// noise that a test asserting the two thirds would trip over.
    static let soloNumerator: CGFloat = 2

    struct Placement: Equatable {
        let screen: PanelScreen
        let frame: NSRect
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
            return Placement(screen: s, frame: NSRect(origin: origin, size: NSSize(width: w, height: h)))
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

        let chosen = pick(from: pool, mouse: mouse)
        return Placement(screen: chosen, frame: chosen.visibleFrame.insetBy(dx: inset, dy: inset))
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
                        isPrimary: index == 0,
                        isOverlay: screen == overlay)
        }
    }
}
