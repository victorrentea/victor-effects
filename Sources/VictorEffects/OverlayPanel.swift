import AppKit

/// Where every window of this app sits: **above Victor Addons' 🔎 ShareZoom**, which
/// is above everything else (`maximumWindow + 3` since 2026-10-27, so Walkie Talkie's
/// panels at `+ 1` are magnified with the rest of the screen — Victor: *"zoom-ul cel
/// mai topmost; deasupra lui sunt doar efectele speciale"*). ShareZoom leaves these
/// windows out of what it films, so each one is drawn once, unzoomed, over the
/// magnified picture: the alarm's red edges are the Retina's edges, zoomed or not.
/// Was `maximumWindow` (−1 … +2) until then. 🪞 Victor Mirror's silhouette sits at
/// `+ 4`, between the zoom and these.
enum EffectsLevel {
    static let overlay = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 5)
}

class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = EffectsLevel.overlay
        ignoresMouseEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        contentView = view
    }

    func refreshScreenFrame() {
        guard !NSScreen.screens.isEmpty else { return }
        let builtIn = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.screens[0]
        let target = builtIn.frame
        if frame != target {
            setFrame(target, display: false)
        }
    }
}
