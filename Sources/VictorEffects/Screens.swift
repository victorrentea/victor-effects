import AppKit

/// One answer to "which screen do the effects draw on?".
///
/// Four places used to each pick the built-in display with their own copy of the
/// `CGDisplayIsBuiltin` loop, which was fine while the answer was hardcoded.
/// It is configurable now (`overlayScreen`), and a setting that four call sites
/// only three of which consult is worse than no setting at all — so they all go
/// through here.
enum Screens {
    /// The display the overlays cover. `builtin` (the default) is the laptop's
    /// own panel, which is what gets mirrored to a projector; `main` follows
    /// whichever screen macOS calls main; anything else is matched as a
    /// case-insensitive substring of a screen's `localizedName`.
    static func overlayScreen() -> NSScreen? {
        let want = EffectsConfig.shared.overlayScreen
        switch want {
        case "main":
            return NSScreen.main ?? NSScreen.screens.first
        case "builtin", "":
            return builtIn() ?? NSScreen.main ?? NSScreen.screens.first
        default:
            if let named = NSScreen.screens.first(where: {
                $0.localizedName.range(of: want, options: .caseInsensitive) != nil
            }) {
                return named
            }
            // A name that matches nothing means a screen was unplugged or
            // renamed — fall back rather than draw nowhere.
            return builtIn() ?? NSScreen.main ?? NSScreen.screens.first
        }
    }

    static func builtIn() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
