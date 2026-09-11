import AppKit

/// The soundboard grid: the tablet's board, on the Mac, in the same order.
///
/// "Same order" is the whole point — the number under Victor's finger on the
/// tablet has to be the number in the same place here, so the layout is driven
/// by `tiles.json`'s array order and `columns`, never by `n` and never by a
/// sort of its own.
final class ThumbnailGridView: NSView {
    private(set) var tiles: [Tile] = []
    private(set) var columns = 13
    private var tileViews: [TileView] = []
    private var emptyLabel: NSTextField?

    var onPress: ((Tile) -> Void)?

    static let padding: CGFloat = 10
    static let gap: CGFloat = 6

    /// The layout arithmetic, as a pure rule.
    ///
    /// Pulled out of `layout()` because the panel now has to ask the question
    /// *before* it has a window to measure: "at this width, how tall does the
    /// grid actually come out?" — which is what lets the panel hug the tiles
    /// instead of framing them in black.
    struct Metrics: Equatable {
        let cell: CGFloat
        let rows: Int
        let size: NSSize
        /// The panel height at which the grid exactly fills the content view:
        /// the tiles plus the ordinary padding, and no dead band.
        var hugHeight: CGFloat { size.height + ThumbnailGridView.padding * 2 }
    }

    /// Square cells that fit BOTH ways. The plan reached for a scroll view when
    /// the rows overflow, but a panel you hold a key to see is one you never
    /// get to scroll — shrinking the cell keeps every tile reachable in the one
    /// glance the gesture affords.
    ///
    /// When the width is what binds — 13 columns across a wide panel, 7 rows
    /// down a tall one — the grid ends up shorter than the panel, and the
    /// difference used to be black. `hugHeight` is that difference, handed to
    /// `ThumbnailPanelPlacement.hug`.
    static func metrics(fitting size: NSSize, count: Int, columns: Int) -> Metrics {
        let cols = max(1, columns)
        let rows = max(1, Int(ceil(Double(max(count, 1)) / Double(cols))))
        let byWidth = (size.width - padding * 2 - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let byHeight = (size.height - padding * 2 - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let cell = max(24, floor(min(byWidth, byHeight)))
        return Metrics(cell: cell,
                       rows: rows,
                       size: NSSize(width: cell * CGFloat(cols) + gap * CGFloat(cols - 1),
                                    height: cell * CGFloat(rows) + gap * CGFloat(rows - 1)))
    }

    /// How tall the panel should be for the grid to hug it at this size, or
    /// `nil` when there are no tiles — the "no tiles.json" message wants the
    /// room it was given.
    func hugHeight(fitting size: NSSize) -> CGFloat? {
        guard !tiles.isEmpty else { return nil }
        return Self.metrics(fitting: size, count: tiles.count, columns: columns).hugHeight
    }

    override var isFlipped: Bool { false }

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Rebuild from the manifest. Cheap enough to call on every show: the
    /// pictures are cached, the views are 91 empty layers.
    func reload() {
        tileViews.forEach { $0.removeFromSuperview() }
        tileViews.removeAll()
        emptyLabel?.removeFromSuperview()
        emptyLabel = nil

        guard let loaded = TilesManifest.load(), !loaded.doc.tiles.isEmpty else {
            tiles = []
            showEmptyMessage()
            return
        }
        tiles = loaded.doc.tiles
        columns = max(1, loaded.doc.columns)
        for tile in tiles {
            let view = TileView(tile: tile)
            view.onPress = { [weak self] t in self?.onPress?(t) }
            addSubview(view)
            tileViews.append(view)
        }
        needsLayout = true
    }

    /// Red border follows the sound, not the click: a tile whose sound ended on
    /// its own has to stop pulsing without anyone pressing anything.
    func setPlaying(asset: String?) {
        for view in tileViews {
            view.isPlaying = view.tile.asset == asset
        }
    }

    /// The grid as laid out right now — cell size and the rectangle it occupies.
    /// Reported by the test hook so a headless check can tell "the panel is up"
    /// from "the panel is up and empty".
    private(set) var gridFrame: NSRect = .zero
    private(set) var cellSide: CGFloat = 0

    override func layout() {
        super.layout()
        guard !tileViews.isEmpty else {
            emptyLabel?.frame = NSRect(x: Self.padding, y: bounds.midY - 40,
                                       width: max(0, bounds.width - Self.padding * 2), height: 80)
            return
        }
        let cols = max(1, columns)
        let m = Self.metrics(fitting: bounds.size, count: tileViews.count, columns: cols)
        let cell = m.cell
        cellSide = cell

        let gridWidth = m.size.width
        let gridHeight = m.size.height
        let originX = ((bounds.width - gridWidth) / 2).rounded()
        let originY = ((bounds.height - gridHeight) / 2).rounded()
        gridFrame = NSRect(x: originX, y: originY, width: gridWidth, height: gridHeight)

        for (index, view) in tileViews.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = originX + CGFloat(col) * (cell + Self.gap)
            // Row 0 is the TOP row (the tablet's first row), and this view is
            // not flipped, so rows count down from the top of the grid.
            let y = originY + gridHeight - CGFloat(row + 1) * cell - CGFloat(row) * Self.gap
            view.frame = NSRect(x: x, y: y, width: cell, height: cell)
        }
    }

    private func showEmptyMessage() {
        let label = NSTextField(labelWithString:
            "no tiles.json in \(EffectsConfig.shared.soundsDir.path)")
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
