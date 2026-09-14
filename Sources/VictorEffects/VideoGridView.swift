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
            let frame = NSRect(x: x, y: y, width: m.cellWidth, height: m.cellHeight)
            // Page 2 needs this more than page 1 does: cell widths here are
            // quantised to multiples of 16, so the centring leaves tens of points
            // of black beside the outer columns — 42 pt on a 1400 pt panel — and
            // a 6 pt gutter covered almost none of it.
            view.highlightOutsets = TileView.highlightOutsets(
                cell: frame, in: bounds, row: row, col: col, rows: m.rows, cols: cols)
            view.frame = frame
        }
        syncHoverToMouse()
    }

    // MARK: - Hover, resolved from where the pointer IS

    /// The same rule as page 1 and for the same reason — see
    /// `ThumbnailGridView.hover(at:)`. It is one pointer over one panel, and the
    /// board landing under a mouse that never moved is the normal case.
    func hover(at point: NSPoint?) {
        for view in tileViews {
            view.setHovered(point.map { view.frame.contains($0) } ?? false)
        }
    }

    func syncHoverToMouse() {
        guard let window, window.isVisible, !isHidden else { hover(at: nil); return }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        hover(at: bounds.contains(local) ? local : nil)
    }

    func clearHover() { hover(at: nil) }

    /// The hook's answer for this page — see `ThumbnailGridView.hoverProbeJSON`.
    func hoverProbeJSON(at point: NSPoint?) -> String {
        if let point { hover(at: point) } else { syncHoverToMouse() }
        let marked = tileViews.filter { $0.hoverProbe.hovered }.map { $0.hoverProbe.json }
        return "{\"page\":\"videos\",\"tiles\":\(tileViews.count),"
            + "\"bounds\":{\"w\":\(Int(bounds.width)),\"h\":\(Int(bounds.height))},"
            + "\"hovered\":[\(marked.joined(separator: ","))]}"
    }

    // MARK: - The cursor is a pointing hand, and stays one

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

    override func mouseEntered(with event: NSEvent) {
        PanelCursor.pinHand()
        hover(at: convert(event.locationInWindow, from: nil))
    }
    override func mouseMoved(with event: NSEvent) {
        PanelCursor.pinHand()
        hover(at: convert(event.locationInWindow, from: nil))
    }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinHand() }
    override func mouseExited(with event: NSEvent) {
        releaseCursor()
        clearHover()
    }

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
    private let gutterLayer = CALayer()
    private let borderLayer = CALayer()
    private let numberLayer = CATextLayer()
    private let titleLayer = CATextLayer()
    private var trackingArea: NSTrackingArea?
    private var isHovered = false
    private var isPressed = false

    /// Per-side reach of the hover/press fill, handed down by the grid — see
    /// `TileView.highlightOutsets`.
    var highlightOutsets = NSEdgeInsets(top: TileView.highlightGutter,
                                        left: TileView.highlightGutter,
                                        bottom: TileView.highlightGutter,
                                        right: TileView.highlightGutter) {
        didSet { needsLayout = true }
    }

    /// The soundboard tile width, handed down by the grid — see
    /// `VideoGridView.badgeUnit`.
    var badgeUnit: CGFloat = 0 { didSet { if badgeUnit != oldValue { needsLayout = true } } }

    /// The title's type size **as a fraction of the tile's width**, matched to
    /// the tablet.
    ///
    /// This was 0.10, from a comment reading "the tablet's 48 px on a ~494 px
    /// cell" — and the 48 in `buildSnippetTile` is `textSize = 48f` on a
    /// `TextView`, which is **sp, not px**. On the board (density override 200,
    /// i.e. 1.25, and Victor's font scale 1.3) that is 48 × 1.625 ≈ 78 px of
    /// type on a cell of (2000 − 2×13 − 4×15) / 5 ≈ 382 px: **0.20 of the tile**,
    /// twice what the panel was drawing. The same clip has to be namable from
    /// the same distance on either screen, so the panel takes the ratio, not the
    /// number.
    static let titleSizeRatio: CGFloat = 0.20

    var isPlaying = false {
        didSet { guard isPlaying != oldValue else { return }; updatePlayingBorder() }
    }

    /// The same live reading as `TileView.hoverProbe`, for the same hook.
    var hoverProbe: TileView.HoverProbe {
        TileView.HoverProbe(n: tile.n, hovered: isHovered,
                            opacity: gutterLayer.opacity,
                            gutter: gutterLayer.frame, cell: frame,
                            clipped: TileView.clipsAnywhere(self),
                            clippers: TileView.clippers(self),
                            z: layer?.zPosition ?? 0)
    }

    init(tile: VideoTile) {
        self.tile = tile
        super.init(frame: .zero)
        wantsLayer = true
        // Not `masksToBounds`: like `TileView`, the hover mark is painted
        // OUTSIDE these bounds, and a layer clips its sublayers to itself.
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor.black.cgColor

        // The hover/press fill of the gutter, under the picture — see
        // `TileView.highlightGutter`. Page 2 gets the same mark as page 1
        // because it is the same pointer over the same panel.
        gutterLayer.cornerRadius = 6 + TileView.highlightGutter
        gutterLayer.opacity = 0
        layer?.addSublayer(gutterLayer)

        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        imageLayer.cornerRadius = 6
        imageLayer.contents = VideoThumbCache.shared.image(for: tile)
        layer?.addSublayer(imageLayer)

        borderLayer.borderColor = NSColor.systemRed.cgColor
        borderLayer.borderWidth = TileView.playingBorderWidth
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
        // The tablet's `setShadowLayer(8f, 2f, 2f, BLACK)`, down-and-right.
        titleLayer.shadowRadius = 4
        titleLayer.shadowOffset = CGSize(width: 2, height: -2)
        titleLayer.truncationMode = .end
        layer?.addSublayer(titleLayer)

        // After the sublayers, so the backing layer exists — the same macOS 14
        // `clipsToBounds` trap documented at the end of `TileView.init`.
        clipsToBounds = false
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        // See `TileView.layout()`: a re-created backing layer comes back clipping.
        clipsToBounds = false
        layer?.masksToBounds = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        gutterLayer.frame = NSRect(x: bounds.minX - highlightOutsets.left,
                                   y: bounds.minY - highlightOutsets.bottom,
                                   width: bounds.width + highlightOutsets.left + highlightOutsets.right,
                                   height: bounds.height + highlightOutsets.bottom + highlightOutsets.top)
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

        let titleSize = max(11, bounds.width * Self.titleSizeRatio)
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
        setHovered(true)
        PanelCursor.pinHand()
    }

    override func mouseExited(with event: NSEvent) { setHovered(false) }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinHand() }

    /// Callable by the grid, which resolves the hover from the pointer's
    /// position — see `TileView.setHovered`.
    func setHovered(_ on: Bool) {
        guard on != isHovered else { return }
        isHovered = on
        updateHighlight()
    }

    /// The picture does not move — see `TileView.updateHighlight`, of which this
    /// is the same four lines on a 16:9 cell.
    private func updateHighlight() {
        let color: NSColor? = isPressed ? TileView.pressColor : (isHovered ? TileView.hoverColor : nil)
        CATransaction.begin()
        CATransaction.setAnimationDuration(TileView.hoverFade)
        gutterLayer.backgroundColor = (color ?? .clear).cgColor
        gutterLayer.opacity = color == nil ? 0 : 1
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
