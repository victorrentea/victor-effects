import AppKit

/// The soundboard grid: the tablet's board, on the Mac, in the same order.
///
/// "Same order" is the whole point — the number under Victor's finger on the
/// tablet has to be the number in the same place here, so the layout is driven
/// by `tiles.json`'s array order and `columns`, never by `n` and never by a
/// sort of its own.
final class ThumbnailGridView: NSView {
    private(set) var tiles: [Tile] = []
    private var columns = 13
    private var tileViews: [TileView] = []
    private var emptyLabel: NSTextField?

    var onPress: ((Tile) -> Void)?

    private let padding: CGFloat = 10
    private let gap: CGFloat = 6

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
            emptyLabel?.frame = NSRect(x: padding, y: bounds.midY - 40,
                                       width: max(0, bounds.width - padding * 2), height: 80)
            return
        }
        let cols = max(1, columns)
        let rows = Int(ceil(Double(tileViews.count) / Double(cols)))
        let availableWidth = bounds.width - padding * 2
        let availableHeight = bounds.height - padding * 2
        // Square cells that fit BOTH ways. The plan reached for a scroll view
        // when the rows overflow, but a panel you hold a key to see is one you
        // never get to scroll — shrinking the cell keeps every tile reachable
        // in the one glance the gesture affords.
        let byWidth = (availableWidth - gap * CGFloat(cols - 1)) / CGFloat(cols)
        let byHeight = (availableHeight - gap * CGFloat(rows - 1)) / CGFloat(rows)
        let cell = max(24, floor(min(byWidth, byHeight)))
        cellSide = cell

        let gridWidth = cell * CGFloat(cols) + gap * CGFloat(cols - 1)
        let gridHeight = cell * CGFloat(rows) + gap * CGFloat(rows - 1)
        let originX = ((bounds.width - gridWidth) / 2).rounded()
        let originY = ((bounds.height - gridHeight) / 2).rounded()
        gridFrame = NSRect(x: originX, y: originY, width: gridWidth, height: gridHeight)

        for (index, view) in tileViews.enumerated() {
            let row = index / cols
            let col = index % cols
            let x = originX + CGFloat(col) * (cell + gap)
            // Row 0 is the TOP row (the tablet's first row), and this view is
            // not flipped, so rows count down from the top of the grid.
            let y = originY + gridHeight - CGFloat(row + 1) * cell - CGFloat(row) * gap
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
