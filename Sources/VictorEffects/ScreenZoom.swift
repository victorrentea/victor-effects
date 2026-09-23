import AppKit

/// Where the room is actually looking when macOS screen zoom (⌥-scroll) is on.
///
/// An overlay that hugs "the edges of the screen" is drawing on the framebuffer,
/// and screen zoom magnifies the framebuffer — so at 2× the alarm's red border
/// sits a full screen's width outside the glass and nobody sees the alarm at
/// all. The only fix is to ask the window server *which slice* of the display is
/// currently blown up and draw the border around that slice instead.
///
/// Nothing public answers that. `UAZoomEnabled()` says whether zoom is on and
/// `UAZoomChangeFocus` only *moves* it; the getter lives in SkyLight as
/// `SLSGetZoomParametersForDisplay(cid, display, &center, &factor, &smoothing)`,
/// where `center` is the middle of the visible slice in global CG points (y down
/// from the top-left of the arrangement) and `factor` is the magnification —
/// 1.0, and `center` the display's own middle, while that display is at rest.
///
/// It is a private symbol, so every lookup here is a `dlsym` that is allowed to
/// fail: a macOS that renames it costs us the zoom-awareness and nothing else,
/// because `visibleRect` then answers the full rect it was handed — exactly the
/// behaviour of the code that existed before this file.
enum ScreenZoom {
    private typealias MainConnectionID = @convention(c) () -> Int32
    private typealias GetParametersForDisplay = @convention(c) (
        Int32, CGDirectDisplayID,
        UnsafeMutablePointer<CGPoint>, UnsafeMutablePointer<Double>, UnsafeMutablePointer<Bool>
    ) -> Int32

    private static let skyLight: UnsafeMutableRawPointer? =
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY)

    private static let connectionID: Int32? = {
        guard let handle = skyLight, let sym = dlsym(handle, "SLSMainConnectionID") else { return nil }
        return unsafeBitCast(sym, to: MainConnectionID.self)()
    }()

    private static let getParameters: GetParametersForDisplay? = {
        guard let handle = skyLight,
              let sym = dlsym(handle, "SLSGetZoomParametersForDisplay") else { return nil }
        return unsafeBitCast(sym, to: GetParametersForDisplay.self)
    }()

    /// Below this the zoom is off (it reports exactly 1.0 at rest) or so slight
    /// that cutting the overlay down would only be a rounding artefact.
    static let minimumFactor: Double = 1.01

    /// The slice of `full` that is on the glass right now.
    ///
    /// `full` is whatever rect covers the whole of `screen` in the CALLER's own
    /// coordinates — the overlay layer's `bounds`, a panel's frame in global
    /// AppKit points — and the answer comes back in those same coordinates,
    /// because the viewport is worked out as a fraction of the display and only
    /// then mapped onto `full`. Not zoomed, or no window server to ask: `full`.
    static func visibleRect(in full: CGRect, of screen: NSScreen?) -> CGRect {
        guard let unit = unitViewport(of: screen) else { return full }
        return CGRect(
            x: full.minX + unit.minX * full.width,
            y: full.minY + unit.minY * full.height,
            width: unit.width * full.width,
            height: unit.height * full.height
        )
    }

    /// The zoom viewport of `screen` as fractions of the display, y counted UP
    /// from its bottom the way AppKit and CALayer count it. `nil` when that
    /// screen is at rest.
    static func unitViewport(of screen: NSScreen?) -> CGRect? {
        guard let screen,
              let display = Screens.displayID(of: screen),
              let get = getParameters,
              let cid = connectionID else { return nil }

        var center = CGPoint.zero
        var factor = 1.0
        var smoothing = false
        guard get(cid, display, &center, &factor, &smoothing) == 0 else { return nil }

        return unitViewport(displayBounds: CGDisplayBounds(display), center: center, factor: factor)
    }

    /// The arithmetic, split out so it can be tested without a zoomed Mac.
    ///
    /// `center` arrives in global CG points (y down, origin at the top-left of
    /// the whole arrangement) and the result counts y up from the bottom of this
    /// display, which is the flip in the middle of this function.
    ///
    /// The clamp is not defensive dressing: macOS keeps the viewport inside the
    /// display, so a centre reported near an edge describes a slice that would
    /// otherwise hang off it. Clamping reproduces what the user is really seeing
    /// — and, as a bonus, is what makes the rest of this correct even if a
    /// future macOS starts reporting an unclamped focus point.
    static func unitViewport(displayBounds: CGRect, center: CGPoint, factor: Double) -> CGRect? {
        guard factor >= minimumFactor,
              displayBounds.width > 0, displayBounds.height > 0 else { return nil }

        let width = 1.0 / factor
        let height = 1.0 / factor
        let centreX = (center.x - displayBounds.minX) / displayBounds.width
        // CG counts y down from the top of the display, CALayer up from the bottom.
        let centreY = 1.0 - (center.y - displayBounds.minY) / displayBounds.height

        return CGRect(
            x: min(max(centreX - width / 2, 0), 1 - width),
            y: min(max(centreY - height / 2, 0), 1 - height),
            width: width,
            height: height
        )
    }
}

/// Re-pins layers to the zoom viewport while they are on screen.
///
/// `visibleRect` is a snapshot, and the viewport moves under the pointer: an
/// alarm that runs for the best part of three seconds would be left behind by
/// one ⌥-scroll or one pan. So a layer is handed over here instead of merely
/// being positioned once.
///
/// Every entry is weak and is dropped the moment its layer is gone or off its
/// superlayer, and the timer stops with the last entry — this follower must
/// never be the thing that keeps an effect alive, nor the thing that has to be
/// told an effect ended (the self-termination rule: `CLAUDE.md`).
final class ZoomFollower {
    static let shared = ZoomFollower()

    private struct Entry {
        weak var layer: CALayer?
        let full: CGRect
        /// Shrink the whole layer into the slice instead of resizing it.
        let stage: Bool
    }

    /// 30 Hz. The viewport moves with the pointer, so anything slower reads as
    /// the border lagging behind the hand.
    private static let interval: TimeInterval = 1.0 / 30

    private var entries: [Entry] = []
    private var timer: Timer?

    /// Pins `layer` inside the zoom viewport of the overlay screen, now and for
    /// as long as it stays on screen. `full` is the rect it would have covered
    /// unzoomed, in its superlayer's coordinates.
    func track(_ layer: CALayer, full: CGRect) {
        layer.frame = ScreenZoom.visibleRect(in: full, of: Screens.overlayScreen())
        follow(Entry(layer: layer, full: full, stage: false))
    }

    /// Pins a CONTAINER whose children are laid out over the whole of `full`:
    /// instead of being resized (which only a border survives), it is scaled
    /// down by the zoom factor and centred on the slice, so after the
    /// magnification every cloud, drop and stamp in it is exactly the size and
    /// in exactly the place it is unzoomed — just on the glass. The children
    /// never learn about the zoom. `full` must have its origin at zero in the
    /// superlayer, which the overlay's `bounds` has.
    func stage(_ layer: CALayer, full: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        Self.applyStage(layer, full: full, screen: Screens.overlayScreen())
        CATransaction.commit()
        follow(Entry(layer: layer, full: full, stage: true))
    }

    private static func applyStage(_ layer: CALayer, full: CGRect, screen: NSScreen?) {
        let visible = ScreenZoom.visibleRect(in: full, of: screen)
        let scale = full.width > 0 ? visible.width / full.width : 1
        layer.bounds = CGRect(origin: .zero, size: full.size)
        layer.position = CGPoint(x: visible.midX, y: visible.midY)
        layer.transform = scale == 1 ? CATransform3DIdentity : CATransform3DMakeScale(scale, scale, 1)
    }

    private func follow(_ entry: Entry) {
        guard let layer = entry.layer else { return }
        entries.removeAll { $0.layer === layer || $0.layer == nil }
        entries.append(entry)
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func untrack(_ layer: CALayer) {
        entries.removeAll { $0.layer === layer || $0.layer == nil }
        stopIfIdle()
    }

    private func tick() {
        let screen = Screens.overlayScreen()
        entries.removeAll { $0.layer == nil || $0.layer?.superlayer == nil }
        for entry in entries {
            guard let layer = entry.layer else { continue }
            // Without this the implicit animation turns every 33 ms correction
            // into a quarter-second slide, and the border swims behind the pan.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            if entry.stage {
                Self.applyStage(layer, full: entry.full, screen: screen)
            } else {
                let target = ScreenZoom.visibleRect(in: entry.full, of: screen)
                if layer.frame != target { layer.frame = target }
            }
            CATransaction.commit()
        }
        stopIfIdle()
    }

    private func stopIfIdle() {
        guard entries.isEmpty else { return }
        timer?.invalidate()
        timer = nil
    }
}

/// The zoom viewport frozen at the moment an effect starts, for the effects
/// that are drawn once rather than followed.
///
/// A screenshot effect is the reason this exists. The capture is the UNZOOMED
/// framebuffer, and the overlay that shows it is magnified along with the rest
/// — so a full-screen screenshot lines up with the desktop fine, but the
/// effect's *motion* does not: a knock that scales about the middle of the
/// display, or a crack that starts at a random point of it, happens mostly off
/// the glass. Laying the layer over `rect` and showing only `crop(_:)` of the
/// capture moves the whole effect into the slice, where the magnification then
/// blows it back up to exactly the size it has when nobody is zoomed.
///
/// One snapshot per effect, and it is the SAME snapshot for the frame and the
/// crop: two reads either side of a pan would hand the layer one slice and the
/// picture another.
struct ZoomSlice {
    /// The viewport as fractions of the display, y up; nil while unzoomed.
    let unit: CGRect?
    /// The visible part of the rect it was taken for, in that rect's coordinates.
    let rect: CGRect

    static func current(in full: CGRect) -> ZoomSlice {
        let unit = ScreenZoom.unitViewport(of: Screens.overlayScreen())
        guard let unit else { return ZoomSlice(unit: nil, rect: full) }
        return ZoomSlice(unit: unit, rect: CGRect(
            x: full.minX + unit.minX * full.width,
            y: full.minY + unit.minY * full.height,
            width: unit.width * full.width,
            height: unit.height * full.height))
    }

    /// `rect` with its origin moved to zero — for code that lays out children
    /// inside a container already placed at `rect`.
    var local: CGRect { CGRect(origin: .zero, size: rect.size) }

    /// The part of a whole-display capture that is on the glass. Unzoomed, the
    /// image itself.
    func crop(_ image: CGImage?) -> CGImage? {
        guard let image, let unit else { return image }
        let w = CGFloat(image.width), h = CGFloat(image.height)
        // The image counts y down from the top, the unit rect up from the bottom.
        let pixels = CGRect(x: unit.minX * w, y: (1 - unit.maxY) * h,
                            width: unit.width * w, height: unit.height * h).integral
        return image.cropping(to: pixels) ?? image
    }
}
