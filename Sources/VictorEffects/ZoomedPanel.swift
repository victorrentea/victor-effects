import AppKit

/// A whole `NSPanel` kept the same size and in the same place on the glass
/// while macOS ⌥-scroll zoom magnifies the framebuffer under it.
///
/// The layers on the overlay are handled by `ZoomFollower`; a separate window
/// cannot be, because it is not a layer of that overlay. The trick is the same
/// one `CaptionOverlay.placement` plays on the subtitle: the panel's frame is
/// its unzoomed (*design*) frame mapped into the slice that is on the glass and
/// shrunk by 1/factor, and its content view keeps the design size as its
/// `bounds` — so AppKit scales drawing **and** hit-testing together (it backs a
/// scaled bounds with `layer.transform`, and `convert(_:from: nil)`, tracking
/// areas and `hitTest` all go through it). Magnified back up by the zoom, the
/// panel is pixel for pixel where and as big as it is unzoomed, and a click on
/// a tile lands on that tile.
///
/// **Identity at rest**: with no zoom `visibleRect` hands back the screen
/// itself and `frame(design:…)` returns `design` untouched (not "within an
/// ulp"), so a follower ticking on an unzoomed Mac never dirties a frame.
enum ZoomedPanel {
    /// Where a panel laid out at `design` (global AppKit points, for the
    /// unzoomed `screen`) must sit in the framebuffer so the glass, which is
    /// showing `visible` of that screen, shows it exactly at `design`. Pure.
    static func frame(design: CGRect, screen: CGRect, visible: CGRect) -> CGRect {
        guard visible != screen, screen.width > 0, visible.width > 0 else { return design }
        // One factor both ways: the zoom viewport keeps the display's aspect,
        // and a panel scaled by two slightly different numbers would no longer
        // be the panel it was laid out as.
        let k = visible.width / screen.width
        return CGRect(x: visible.minX + (design.minX - screen.minX) * k,
                      y: visible.minY + (design.minY - screen.minY) * k,
                      width: design.width * k,
                      height: design.height * k)
    }

    /// The inverse, for a point: where on the unzoomed `screen` a framebuffer
    /// point `p` (global, y up — `NSEvent.mouseLocation`) is SEEN on the glass.
    /// It is what a panel drawn in design coordinates needs to put something
    /// under the pointer. Pure.
    static func designPoint(_ p: CGPoint, screen: CGRect, visible: CGRect) -> CGPoint {
        guard visible != screen, screen.width > 0, visible.width > 0 else { return p }
        let k = visible.width / screen.width
        return CGPoint(x: screen.minX + (p.x - visible.minX) / k,
                       y: screen.minY + (p.y - visible.minY) / k)
    }

    /// The part of `screen` (global AppKit points) on the glass now; the whole
    /// screen while it is at rest or when there is no screen to ask about.
    static func visible(on screen: NSScreen?, fallback: CGRect) -> CGRect {
        guard let screen else { return fallback }
        return ScreenZoom.visibleRect(in: screen.frame, of: screen)
    }

    /// Put `window` at `frame` and give its content view `designSize` as its
    /// bounds. The bounds must be re-asserted after every `setFrame`: AppKit
    /// keeps the bounds-to-frame RATIO through a resize, so a zoom that changed
    /// factor would otherwise leave the content at the old scale.
    static func apply(_ window: NSWindow, frame: CGRect, designSize: CGSize, display: Bool = true) {
        if window.frame != frame { window.setFrame(frame, display: display) }
        guard let content = window.contentView else { return }
        if content.bounds.size != designSize { content.setBoundsSize(designSize) }
        if content.bounds.origin != .zero { content.setBoundsOrigin(.zero) }
    }
}
