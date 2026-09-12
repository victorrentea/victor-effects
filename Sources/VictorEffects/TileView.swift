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
    private let gutterLayer = CALayer()
    private let borderLayer = CALayer()
    private let numberLayer = CATextLayer()
    private var labelLayer: CATextLayer?
    private var badgeLayer: CATextLayer?
    private var starLayer: CATextLayer?
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// **The picture never moves.** Hover and press are painted in the BLACK
    /// GUTTER around the tile, not on the tile.
    ///
    /// What was here before — a 1.04 scale-up, a white glow, a wash and a ring
    /// inside the tile's own edge — moved the artwork a pixel or two under the
    /// pointer. On a board of 91 photographs that reads as the picture twitching
    /// rather than as "the mouse is here", and the ring ate the outer few
    /// percent of an image that is already only ~80 pt across. The gap between
    /// tiles is dead black space that belongs to nobody; lighting it up is a
    /// bigger, brighter mark than any outline that fits inside a tile, and it
    /// costs the artwork nothing.
    ///
    /// The fill reaches exactly one `gap` outwards — up to the neighbours'
    /// edges, so the whole gutter around the cell goes green with no black
    /// hairline left in the middle of it. (At the edges of the grid it eats 6 of
    /// the 10 pt of `padding`, which is the same mark seen from the outside.)
    static var highlightGutter: CGFloat { ThumbnailGridView.gap }
    /// Hover: bright, saturated green — nothing else on the board is this
    /// colour (the usage dots are a darker green, the star amber, the playing
    /// border red), so it cannot be read as a state the tile is *in*.
    static let hoverColor = NSColor(srgbRed: 0.224, green: 1.0, blue: 0.078, alpha: 1)   // #39FF14
    /// Mouse-down: the same shape in red. The press used to be a 0.95 scale —
    /// again the picture moving — and this keeps the feedback while leaving the
    /// artwork alone.
    static let pressColor = NSColor(srgbRed: 1.0, green: 0.13, blue: 0.13, alpha: 1)     // #FF2121
    /// Short enough to track a mouse crossing tiles, long enough not to strobe.
    static let hoverFade: CFTimeInterval = 0.08
    /// The red border that pulses while the tile's sound plays. Its own number
    /// now: with the hover mark outside the tile there is no longer an outline
    /// underneath for it to cover.
    static let playingBorderWidth: CGFloat = 7

    /// The ⭐'s type size and corner margin **as fractions of the tile**, taken
    /// straight off the tablet (`starPaint.textSize = w * 0.22f`,
    /// `margin = width * 0.05f` in `TileImageView.onDraw`). Fractions and not
    /// points because the panel's cell is whatever 13 columns leave on the
    /// screen it opens on, and the two boards have to look like one board.
    static let starSizeRatio: CGFloat = 0.22
    static let starMarginRatio: CGFloat = 0.05

    var isPlaying = false {
        didSet { guard isPlaying != oldValue else { return }; updatePlayingBorder() }
    }

    /// The desktop effect this tile's asset fires, or nil — **the catalogue's
    /// answer, in process**. The panel used to be the one surface that drew the
    /// board without the ⭐ the tablet has had for weeks: same grid, same
    /// `tiles.json`, a star on one screen and not on the other. There is no
    /// second list here and no HTTP hop to `/tiles` — both stars are
    /// `EffectsCatalog.effectName(forAsset:)` answering twice.
    static func desktopEffect(for tile: Tile) -> String? {
        EffectsCatalog.effectName(forAsset: tile.asset)
    }

    /// True when this tile wears the ⭐.
    var hasDesktopEffect: Bool { Self.desktopEffect(for: tile) != nil }

    init(tile: Tile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        // NOT `masksToBounds`: the hover mark is painted OUTSIDE these bounds,
        // in the gutter between the tiles, and a layer clips its sublayers to
        // itself. The rounding lives on `imageLayer`, which is the only sublayer
        // with anything to clip.
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 1).cgColor

        // Below everything: the hover/press fill of the surrounding gutter. It
        // is the first sublayer so the picture always sits ON it — the mark is a
        // frame around the artwork, never a wash over it.
        gutterLayer.cornerRadius = 6 + Self.highlightGutter
        gutterLayer.opacity = 0
        layer?.addSublayer(gutterLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = 6
        layer?.addSublayer(imageLayer)

        borderLayer.borderColor = NSColor.systemRed.cgColor
        borderLayer.borderWidth = Self.playingBorderWidth
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

        if hasDesktopEffect {
            // ⭐ TOP-RIGHT, the tablet's badge reproduced glyph for glyph: the
            // solid star "★" (not the emoji, which would arrive as a colour
            // sprite in a different metric), amber `#FFC400` so it is the only
            // non-white/green mark on a tile, a black shadow so it survives a
            // bright thumbnail, and right-aligned against a 5 % margin. The
            // corner is the last free one — `#NN` top-left, ↻ bottom-left, the
            // usage dots bottom-right.
            let star = CATextLayer()
            star.string = "★"
            star.foregroundColor = NSColor(srgbRed: 1, green: 0.769, blue: 0, alpha: 1).cgColor
            star.alignmentMode = .right
            star.shadowColor = NSColor.black.cgColor
            star.shadowOpacity = 0.9
            star.shadowRadius = 2
            star.shadowOffset = CGSize(width: 1, height: -1)
            layer?.addSublayer(star)
            starLayer = star
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
        // Outwards by one gap, into the gutter this cell owns.
        gutterLayer.frame = bounds.insetBy(dx: -Self.highlightGutter, dy: -Self.highlightGutter)
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
        if let star = starLayer {
            // Right edge at the tablet's `width - margin`, top at its `margin`.
            // The glyph is laid out from the TOP of a text layer, so the box is
            // pinned by its top and given a line's worth of height.
            let size = max(9, side * Self.starSizeRatio)
            let margin = side * Self.starMarginRatio
            star.fontSize = size
            star.font = NSFont.boldSystemFont(ofSize: size)
            star.frame = NSRect(x: margin, y: bounds.height - margin - size * 1.3,
                                width: bounds.width - margin * 2, height: size * 1.3)
            star.contentsScale = window?.backingScaleFactor ?? 2
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

    private func setHover(_ on: Bool) {
        guard on != isHovered else { return }
        isHovered = on
        updateHighlight()
    }

    /// One place decides the mark, because two states claim it: hovering paints
    /// the gutter green, pressing paints it red, and releasing a press has to
    /// fall back to the hover the mouse is still inside rather than to nothing.
    ///
    /// It fades over `hoverFade` rather than CALayer's implicit quarter second:
    /// the mark's whole job is to keep up with a mouse sweeping the board, and
    /// at 0.25 s it is still arriving on the tile the pointer has already left.
    ///
    /// **Nothing here touches the tile's transform, its shadow or its frame.**
    /// The artwork is exactly where it was before the mouse arrived.
    private func updateHighlight() {
        let color: NSColor? = isPressed ? Self.pressColor : (isHovered ? Self.hoverColor : nil)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.hoverFade)
        gutterLayer.backgroundColor = (color ?? .clear).cgColor
        gutterLayer.opacity = color == nil ? 0 : 1
        // The fill reaches OUTSIDE this view, into ground the neighbours' own
        // layers are painted over. Tiles are siblings and the later ones draw on
        // top, so without this the mark would be clipped away on two sides out
        // of four. `zPosition` and NOT a reorder of the subviews:
        // `ThumbnailGridView` lays out by the INDEX of its `tileViews` array,
        // and moving a view under the pointer churns tracking areas.
        layer?.zPosition = color == nil ? 0 : 1
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        updateHighlight()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        updateHighlight()
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
