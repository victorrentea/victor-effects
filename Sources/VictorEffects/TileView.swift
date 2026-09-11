import AppKit
import ImageIO

/// Decoded tile pictures, kept for the life of the process.
///
/// The originals are up to 2238 px square and there are 91 of them — several
/// hundred MB of bitmap for tiles about 140 pt across. `ImageIO` makes the
/// thumbnail instead of decoding the full image and throwing most of it away,
/// which is the same trade the tablet makes with `inSampleSize`.
final class TileImageCache {
    static let shared = TileImageCache()

    private var cache: [String: CGImage] = [:]
    private var inFlight: Set<String> = []
    private let queue = DispatchQueue(label: "victor-effects-tiles", qos: .userInitiated)

    /// Main thread only (the dictionary is not locked; every caller is a view).
    func cached(_ relativePath: String) -> CGImage? { cache[relativePath] }

    func clear() {
        cache.removeAll()
        inFlight.removeAll()
    }

    /// Loads off the main thread and calls back on it. Returns immediately if
    /// another tile view already asked for the same picture.
    func load(_ relativePath: String, maxPixel: CGFloat, completion: @escaping (CGImage?) -> Void) {
        if let hit = cache[relativePath] { completion(hit); return }
        guard !inFlight.contains(relativePath) else { return }
        inFlight.insert(relativePath)
        let url = EffectsConfig.shared.soundsDir.appendingPathComponent(relativePath)
        let pixels = max(64, maxPixel * 2)
        queue.async {
            let image = Self.thumbnail(at: url, maxPixel: pixels)
            DispatchQueue.main.async {
                self.inFlight.remove(relativePath)
                if let image { self.cache[relativePath] = image }
                completion(image)
            }
        }
    }

    private static func thumbnail(at url: URL, maxPixel: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxPixel),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

/// One tile: the picture, its `#NN`, an optional word across it, the ↻ badge,
/// and a red border while its sound plays.
///
/// Built out of `CALayer`s rather than `draw(_:)` because the playing border
/// pulses and the press scales — both of which are one animation on a layer and
/// a redraw loop in a drawing method.
final class TileView: NSView {
    let tile: Tile
    var onPress: ((Tile) -> Void)?

    private let imageLayer = CALayer()
    private let hoverRimLayer = CALayer()
    private let hoverLayer = CALayer()
    private let borderLayer = CALayer()
    private let numberLayer = CATextLayer()
    private var labelLayer: CATextLayer?
    private var badgeLayer: CATextLayer?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// The hover outline: a dark rim at the tile's edge with a white ring just
    /// inside it, 7 pt of mark in total — the same footprint as the playing
    /// border, which is added after these layers and so draws straight over
    /// them. A tile that is playing says *that* first.
    ///
    /// It was 4 pt (2 pt of ring over a 4 pt rim) and that was still a guess from
    /// a metre back: an 81 pt tile with a 2 pt edge reads as "a tile with an
    /// edge", not as "THIS one". The ring is what the eye lands on, so the ring
    /// is what grew — 2 → 5 pt — and the dark rim went with it to keep the white
    /// legible on the light half of the board.
    static let hoverRimWidth: CGFloat = 7
    static let hoverRingWidth: CGFloat = 5
    /// How far the white ring sits inside the dark rim: the rim shows as a thin
    /// dark keyline around it, and the ring's corner radius has to match.
    static var hoverRingInset: CGFloat { hoverRimWidth - hoverRingWidth }
    /// Thicker and brighter, and then the tile also comes forward. 1.04 of an
    /// 81 pt cell is 1.6 pt a side — it fits inside the 6 pt `gap`, so a hovered
    /// tile lifts without ever touching its neighbours.
    static let hoverScale: CGFloat = 1.04
    /// The glow around the lifted tile. The root layer clips its *sublayers*
    /// (`masksToBounds`) but never its own shadow, so this is the one mark that
    /// is allowed outside the tile.
    static let hoverGlowRadius: CGFloat = 9
    static let hoverGlowOpacity: Float = 0.75
    /// Short enough to track a mouse crossing tiles, long enough not to strobe.
    static let hoverFade: CFTimeInterval = 0.08

    var isPlaying = false {
        didSet { guard isPlaying != oldValue else { return }; updatePlayingBorder() }
    }

    init(tile: Tile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)

        // Hover is a wash AND a ring. The wash alone (white at 8%) is what was
        // here first and it is invisible on the half of the board whose pictures
        // are already light — but "which tile is the mouse on" is exactly the
        // question a grid of 91 pictures has to answer in one glance. The ring
        // is white over a dark rim for the same reason `#NN` below is white with
        // a black shadow: an outline that vanishes on half the tiles is not an
        // outline. Rim at the very edge, white just inside it.
        hoverRimLayer.borderColor = NSColor(white: 0, alpha: 0.75).cgColor
        hoverRimLayer.borderWidth = Self.hoverRimWidth
        hoverRimLayer.cornerRadius = 6
        hoverRimLayer.opacity = 0
        layer?.addSublayer(hoverRimLayer)

        hoverLayer.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor
        hoverLayer.borderColor = NSColor.white.cgColor
        hoverLayer.borderWidth = Self.hoverRingWidth
        hoverLayer.cornerRadius = 6 - Self.hoverRingInset
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)

        borderLayer.borderColor = NSColor.systemRed.cgColor
        // Tied to the hover rim, not a 4 of its own: this border's job is to
        // cover the hover outline exactly, so the two widths are one decision.
        borderLayer.borderWidth = Self.hoverRimWidth
        borderLayer.cornerRadius = 6
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)

        // The tablet's `numberPaint`: white with a black shadow, because half
        // the pictures are light and half are dark.
        numberLayer.string = "#\(tile.n)"
        numberLayer.foregroundColor = NSColor.white.cgColor
        numberLayer.shadowColor = NSColor.black.cgColor
        numberLayer.shadowOpacity = 0.9
        numberLayer.shadowRadius = 2
        numberLayer.shadowOffset = .zero
        numberLayer.alignmentMode = .left
        layer?.addSublayer(numberLayer)

        if let text = tile.label, !text.isEmpty {
            let l = CATextLayer()
            l.string = text
            l.foregroundColor = NSColor.white.cgColor
            l.alignmentMode = .center
            l.shadowColor = NSColor.black.cgColor
            l.shadowOpacity = 0.9
            l.shadowRadius = 3
            l.shadowOffset = .zero
            layer?.addSublayer(l)
            labelLayer = l
        }

        if tile.restartable {
            // The ↻ badge, bottom-left — the only free corner on the tablet, and
            // kept there so the two grids look like the same grid.
            let badge = CATextLayer()
            badge.string = "↻"
            badge.foregroundColor = NSColor.white.cgColor
            badge.alignmentMode = .center
            badge.backgroundColor = NSColor(white: 0, alpha: 0.65).cgColor
            layer?.addSublayer(badge)
            badgeLayer = badge
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let side = bounds.width
        // Layer geometry is set outside an animation: a resize would otherwise
        // slide every sublayer into place over a quarter second.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        hoverRimLayer.frame = bounds
        hoverLayer.frame = bounds.insetBy(dx: Self.hoverRingInset, dy: Self.hoverRingInset)
        borderLayer.frame = bounds
        let numberSize = max(9, side * 0.10)
        numberLayer.fontSize = numberSize
        numberLayer.font = NSFont.boldSystemFont(ofSize: numberSize)
        numberLayer.frame = NSRect(x: side * 0.04, y: bounds.height - numberSize * 1.5,
                                   width: side * 0.9, height: numberSize * 1.3)
        numberLayer.contentsScale = window?.backingScaleFactor ?? 2
        if let l = labelLayer {
            let size = max(10, side * 0.28)
            l.fontSize = size
            l.font = NSFont.boldSystemFont(ofSize: size)
            l.frame = NSRect(x: 0, y: bounds.midY - size * 0.7, width: bounds.width, height: size * 1.4)
            l.contentsScale = window?.backingScaleFactor ?? 2
        }
        if let badge = badgeLayer {
            let r = side * 0.22
            badge.frame = NSRect(x: side * 0.05, y: side * 0.05, width: r, height: r)
            badge.cornerRadius = r / 2
            badge.fontSize = r * 0.55
            badge.contentsScale = window?.backingScaleFactor ?? 2
        }
        CATransaction.commit()

        if let hit = TileImageCache.shared.cached(tile.image) {
            imageLayer.contents = hit
        } else {
            TileImageCache.shared.load(tile.image, maxPixel: side) { [weak self] image in
                guard let self, let image else { return }
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                self.imageLayer.contents = image
                CATransaction.commit()
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.cursorUpdate` as well as enter/exit: a tile is the TOPMOST tracking
        // area under the pointer, so if it did not answer the cursor question
        // itself, the answer would come from whatever is underneath the panel.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .cursorUpdate,
                                            .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    // MARK: - Interaction

    /// The panel never becomes key, so every click is a "first mouse". Without
    /// this the first click on the panel would be swallowed to focus a window
    /// that refuses focus, and the tile would need pressing twice.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        setHover(true)
        PanelCursor.pinArrow()
    }

    override func mouseExited(with event: NSEvent) { setHover(false) }

    /// AppKit asking "what is the cursor here?" — the one moment it is polite to
    /// answer, and the answer is always the arrow. See `PanelCursor`.
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinArrow() }

    /// Both halves of the outline move together, and they fade rather than snap —
    /// but over `hoverFade`, not CALayer's implicit quarter of a second. The
    /// outline's whole job is to keep up with the mouse sweeping the board; at
    /// 0.25 s it is still arriving on the tile the pointer has already left.
    private func setHover(_ on: Bool) {
        guard on != isHovered else { return }
        isHovered = on
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.hoverFade)
        hoverRimLayer.opacity = on ? 1 : 0
        hoverLayer.opacity = on ? 1 : 0
        layer?.shadowColor = NSColor.white.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = Self.hoverGlowRadius
        layer?.shadowOpacity = on ? Self.hoverGlowOpacity : 0
        applyScale()
        CATransaction.commit()
    }

    /// One place decides the tile's size, because two states claim it: hovering
    /// lifts it and pressing pushes it in. Releasing a press used to snap back to
    /// `.identity`, which threw away the hover the mouse is still inside.
    private func applyScale() {
        let scale: CGFloat = isPressed ? 0.95 : (isHovered ? Self.hoverScale : 1)
        layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.hoverFade)
        applyScale()
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.hoverFade)
        applyScale()
        CATransaction.commit()
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onPress?(tile)
    }

    private func updatePlayingBorder() {
        borderLayer.removeAnimation(forKey: "pulse")
        guard isPlaying else { borderLayer.opacity = 0; return }
        borderLayer.opacity = 1
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1.0
        pulse.toValue = 0.16
        pulse.duration = 0.5
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        borderLayer.add(pulse, forKey: "pulse")
    }
}
