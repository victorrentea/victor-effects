import AppKit
import ImageIO

/// Decoded video thumbnails, kept for the life of the process.
///
/// The pictures arrive as base64 JPEGs inside `GET /videos` (480 px wide, ~30 KB
/// each), so unlike `TileImageCache` there is no file to read and no reason to
/// go off the main thread: eighteen small JPEGs decode in the time the panel
/// takes to slide in. Keyed by the video id, which is also what makes a refresh
/// that returns the same list cost nothing.
final class VideoThumbCache {
    static let shared = VideoThumbCache()
    private var cache: [String: CGImage] = [:]

    func image(for tile: VideoTile) -> CGImage? {
        if let hit = cache[tile.id] { return hit }
        guard let data = tile.thumb,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        cache[tile.id] = image
        return image
    }

    func clear() { cache.removeAll() }
}

/// The panel's **second page**: the tablet's 🎬 video snippets, on the Mac.
///
/// It is the same board, so it is the same arithmetic: **five tiles to a row**
/// at **16:9** (`MainActivity.renderVideoTiles`, `SNIPPETS_PER_ROW`), which
/// against the soundboard's 13 columns makes a video tile **2.6× the width of a
/// sound tile** — the ratio, not a number, is what has to match, because the two
/// grids are read from the same distance and the eye has learned one of them.
///
/// Everything else is shared with page 1 on purpose — `padding`, `gap`, the
/// `#NN` badge, the pulsing red border — so that flipping between them under a
/// held key looks like one board changing its mind rather than two apps.
final class VideoGridView: NSView {
    private(set) var tiles: [VideoTile] = []
    private var tileViews: [VideoTileView] = []
    private var emptyLabel: NSTextField?

    var onPress: ((VideoTile) -> Void)?

    /// The tablet's `SNIPPETS_PER_ROW`.
    static let columns = 5
    /// The tablet's `cellWidth * 9 / 16`.
    static let aspect: CGFloat = 9.0 / 16.0
    static var padding: CGFloat { ThumbnailGridView.padding }
    static var gap: CGFloat { ThumbnailGridView.gap }
    /// Below this a 16:9 tile is a smear rather than a picture; the panel would
    /// rather overflow than pretend. A multiple of `widthQuantum`, like every
    /// other width here.
    static let minCellWidth: CGFloat = 80
    /// **Tile widths are whole multiples of 16.**
    ///
    /// Not tidiness — it is what makes hugging *stable*. The panel measures the
    /// grid, shortens its frame to the answer, and the grid is then measured
    /// again at that height; with a cell whose height was `floor(width × 9/16)`
    /// the round trip loses the fraction and comes back one point smaller, so a
    /// second show creeps the board down. On a multiple of 16 the height is
    /// exact, and re-measuring gives back the same cell. Page 1 has the same
    /// scar, solved there by writing ⅔ as a division rather than `0.666…`.
    static let widthQuantum: CGFloat = 16

    /// The layout arithmetic, pure — the panel asks it *before* there is a
    /// window, to hug the grid the same way page 1 does.
    struct Metrics: Equatable {
        let cellWidth: CGFloat
        let cellHeight: CGFloat
        let rows: Int
        let size: NSSize
        var hugHeight: CGFloat { size.height + VideoGridView.padding * 2 }
    }

    /// Fits **both ways**, like the square cells of page 1: the width binds in
    /// the normal case (five across a wide panel), but three rows of 16:9 down a
    /// short frame binds on height instead, and a tile that overflowed the panel
    /// would be a tile the gesture can never reach.
    static func metrics(fitting size: NSSize, count: Int, columns: Int = VideoGridView.columns) -> Metrics {
        let cols = max(1, columns)
        let rows = max(1, Int(ceil(Double(max(count, 1)) / Double(cols))))
        let byWidth = (size.width - padding * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let byHeight = ((size.height - padding * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)) / aspect
        let quantised = floor(min(byWidth, byHeight) / widthQuantum) * widthQuantum
        let cellWidth = max(minCellWidth, quantised)
        let cellHeight = cellWidth * aspect   // exact: cellWidth is a multiple of 16
        return Metrics(cellWidth: cellWidth,
                       cellHeight: cellHeight,
                       rows: rows,
                       size: NSSize(width: cellWidth * CGFloat(cols) + gap * CGFloat(cols - 1),
                                    height: cellHeight * CGFloat(rows) + gap * CGFloat(rows - 1)))
    }

    /// The `#NN` badge is scaled off the **soundboard** tile, never off the video
    /// tile it is drawn on — `TileNumberBadge` on the tablet says the same thing
    /// in the same words. A video tile is nearly three times wider, and scaling
    /// the badge with it would produce a different badge, not the same one.
    static func badgeUnit(fitting size: NSSize) -> CGFloat {
        let doc = TilesManifest.load()?.doc
        return ThumbnailGridView.metrics(fitting: size,
                                         count: doc?.tiles.count ?? 91,
                                         columns: doc?.columns ?? 13).cell
    }

    func hugHeight(fitting size: NSSize) -> CGFloat? {
        guard !tiles.isEmpty else { return nil }
        return Self.metrics(fitting: size, count: tiles.count).hugHeight
    }

    override var isFlipped: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuild from a list already fetched. Takes the list rather than fetching
    /// one, because the fetch blocks and the caller is the only one who knows
    /// whether this show can afford it.
    func reload(with videos: [VideoTile]) {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        emptyLabel?.removeFromSuperview()
        emptyLabel = nil

        tiles = videos
        guard !tiles.isEmpty else {
            showEmptyMessage()
            return
        }
        for tile in tiles {
            let view = VideoTileView(tile: tile)
            view.onPress = { [weak self] t in self?.onPress?(t) }
            addSubview(view)
            tileViews.append(view)
        }
        needsLayout = true
    }

    /// The border follows the player, not the click — same rule as the
    /// soundboard's, and here it matters more: the clip is auto-killed after
    /// about a minute whether or not anybody pressed anything.
    func setPlaying(id: String?) {
        for view in tileViews { view.isPlaying = view.tile.id == id }
    }

    private(set) var gridFrame: NSRect = .zero

    override func layout() {
        super.layout()
        guard !tileViews.isEmpty else {
            emptyLabel?.frame = NSRect(x: Self.padding, y: bounds.midY - 40,
                                       width: max(0, bounds.width - Self.padding * 2), height: 80)
            return
        }
        let cols = Self.columns
        let m = Self.metrics(fitting: bounds.size, count: tileViews.count, columns: cols)
        let badgeUnit = Self.badgeUnit(fitting: bounds.size)

        let originX = ((bounds.width - m.size.width) / 2).rounded()
        let originY = ((bounds.height - m.size.height) / 2).rounded()
        gridFrame = NSRect(x: originX, y: originY, width: m.size.width, height: m.size.height)

        for (index, view) in tileViews.enumerated() {
            let row = index / cols
            let col = index % cols
            view.badgeUnit = badgeUnit
            let x = originX + CGFloat(col) * (m.cellWidth + Self.gap)
            // Row 0 is the TOP row (the tablet's first row); this view is not
            // flipped, so rows count down from the top of the grid.
            let y = originY + m.size.height - CGFloat(row + 1) * m.cellHeight - CGFloat(row) * Self.gap
            view.frame = NSRect(x: x, y: y, width: m.cellWidth, height: m.cellHeight)
        }
    }

    // MARK: - The cursor is an arrow, and stays one

    /// Same policy and the same reasons as `ThumbnailGridView` — see the note
    /// there. `.cursorUpdate` is what stops the window *underneath* the panel
    /// from deciding the pointer's shape.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited,
                                                 .mouseMoved, .cursorUpdate, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { PanelCursor.pinArrow() }
    override func mouseMoved(with event: NSEvent) { PanelCursor.pinArrow() }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinArrow() }
    override func mouseExited(with event: NSEvent) { releaseCursor() }

    func releaseCursor() { NSCursor.arrow.set() }

    /// One tile, not an empty page: "the panel is up" and "the panel is up and
    /// the other app is down" have to be tellable apart at a glance, from a
    /// metre back, with a key still held.
    private func showEmptyMessage() {
        let base = EffectsConfig.shared.addonsBaseURL
        let label = NSTextField(labelWithString:
            base.isEmpty ? "no addonsBaseURL configured" : "no videos (addons down?)\n\(base)")
        label.alignment = .center
        label.font = .systemFont(ofSize: 18)
        label.textColor = .white
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 3
        addSubview(label)
        emptyLabel = label
        needsLayout = true
    }
}

/// One video tile: the thumbnail, its `#NN`, the title across it, and a red
/// border while the clip is on the projector.
///
/// A near-copy of `TileView` rather than a shared superclass: the two differ in
/// shape (16:9 against square), in what the label means (a snippet's name
/// against an optional word) and in what a press talks to (another process
/// against this one's router), and the hover/press choreography they *do* share
/// is four lines that are better read twice than indirected once.
final class VideoTileView: NSView {
    let tile: VideoTile
    var onPress: ((VideoTile) -> Void)?

    private let imageLayer = CALayer()
    private let hoverRimLayer = CALayer()
    private let hoverLayer = CALayer()
    private let borderLayer = CALayer()
    private let numberLayer = CATextLayer()
    private let titleLayer = CATextLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// The soundboard tile width, handed down by the grid — see
    /// `VideoGridView.badgeUnit`.
    var badgeUnit: CGFloat = 0 { didSet { if badgeUnit != oldValue { needsLayout = true } } }

    var isPlaying = false {
        didSet { guard isPlaying != oldValue else { return }; updatePlayingBorder() }
    }

    init(tile: VideoTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        // Not `masksToBounds` — the hover glow is this layer's own shadow, and a
        // layer clips its shadow along with its sublayers.
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.black.cgColor

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = 6
        imageLayer.contents = VideoThumbCache.shared.image(for: tile)
        layer?.addSublayer(imageLayer)

        hoverRimLayer.borderColor = NSColor(white: 0, alpha: 0.75).cgColor
        hoverRimLayer.borderWidth = TileView.hoverRimWidth
        hoverRimLayer.cornerRadius = 6
        hoverRimLayer.opacity = 0
        layer?.addSublayer(hoverRimLayer)

        hoverLayer.backgroundColor = NSColor(white: 1, alpha: 0.20).cgColor
        hoverLayer.borderColor = NSColor.white.cgColor
        hoverLayer.borderWidth = TileView.hoverRingWidth
        hoverLayer.cornerRadius = 6 - TileView.hoverRingInset
        hoverLayer.opacity = 0
        layer?.addSublayer(hoverLayer)

        borderLayer.borderColor = NSColor.systemRed.cgColor
        borderLayer.borderWidth = TileView.hoverRimWidth
        borderLayer.cornerRadius = 6
        borderLayer.opacity = 0
        layer?.addSublayer(borderLayer)

        numberLayer.string = "#\(tile.n)"
        numberLayer.foregroundColor = NSColor.white.cgColor
        numberLayer.shadowColor = NSColor.black.cgColor
        numberLayer.shadowOpacity = 0.9
        numberLayer.shadowRadius = 2
        numberLayer.shadowOffset = .zero
        numberLayer.alignmentMode = .left
        layer?.addSublayer(numberLayer)

        // The title sits **across** the thumbnail, centred, exactly where the
        // tablet puts it — a frame grabbed at the snippet's own start second is
        // rarely legible enough to name the clip on its own, and a caption under
        // the picture would cost a line of height on every row.
        titleLayer.string = tile.title
        titleLayer.foregroundColor = NSColor.white.cgColor
        titleLayer.alignmentMode = .center
        titleLayer.shadowColor = NSColor.black.cgColor
        titleLayer.shadowOpacity = 0.9
        titleLayer.shadowRadius = 3
        titleLayer.shadowOffset = .zero
        titleLayer.truncationMode = .end
        layer?.addSublayer(titleLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        hoverRimLayer.frame = bounds
        hoverLayer.frame = bounds.insetBy(dx: TileView.hoverRingInset, dy: TileView.hoverRingInset)
        borderLayer.frame = bounds
        let scale = window?.backingScaleFactor ?? 2

        // `TileNumberBadge`: text at 10% of the SOUNDBOARD tile, 4% of it in from
        // the left. The fallback keeps the badge sane on a Mac with no
        // `tiles.json` at all, where there is no soundboard to scale against.
        let unit = badgeUnit > 0 ? badgeUnit : bounds.width / 2.6
        let numberSize = max(9, unit * 0.10)
        numberLayer.fontSize = numberSize
        numberLayer.font = NSFont.boldSystemFont(ofSize: numberSize)
        numberLayer.frame = NSRect(x: unit * 0.04, y: bounds.height - numberSize * 1.5,
                                   width: bounds.width - unit * 0.08, height: numberSize * 1.3)
        numberLayer.contentsScale = scale

        // The tablet's 48 px on a ~494 px cell — a tenth of the tile's width.
        let titleSize = max(11, bounds.width * 0.10)
        titleLayer.fontSize = titleSize
        titleLayer.font = NSFont.boldSystemFont(ofSize: titleSize)
        titleLayer.frame = NSRect(x: 4, y: bounds.midY - titleSize * 0.7,
                                  width: bounds.width - 8, height: titleSize * 1.4)
        titleLayer.contentsScale = scale
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        // `.cursorUpdate` for the same reason as `TileView`: a tile is the
        // topmost tracking area under the pointer, and silence here hands the
        // cursor's shape to the window beneath the panel.
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .cursorUpdate,
                                            .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) {
        setHover(true)
        PanelCursor.pinArrow()
    }

    override func mouseExited(with event: NSEvent) { setHover(false) }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinArrow() }

    private func setHover(_ on: Bool) {
        guard on != isHovered else { return }
        isHovered = on
        CATransaction.begin()
        CATransaction.setAnimationDuration(TileView.hoverFade)
        hoverRimLayer.opacity = on ? 1 : 0
        hoverLayer.opacity = on ? 1 : 0
        layer?.shadowColor = NSColor.white.cgColor
        layer?.shadowOffset = .zero
        layer?.shadowRadius = TileView.hoverGlowRadius
        layer?.shadowOpacity = on ? TileView.hoverGlowOpacity : 0
        layer?.zPosition = on ? 1 : 0
        applyScale()
        CATransaction.commit()
    }

    private func applyScale() {
        let scale: CGFloat = isPressed ? 0.95 : (isHovered ? TileView.hoverScale : 1)
        layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        CATransaction.begin()
        CATransaction.setAnimationDuration(TileView.hoverFade)
        applyScale()
        CATransaction.commit()
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(TileView.hoverFade)
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
