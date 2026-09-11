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

    // MARK: - The cursor is an arrow, and stays one

    /// Every tile is clickable, so the cursor belongs to the grid and not to the
    /// tiles: with 6 pt of `gap` between them, a per-tile cursor would flick back
    /// to whatever is underneath every time the mouse crossed from one tile to
    /// the next. `TileView` pins it too, but only because a tile is the topmost
    /// tracking area under the pointer and would otherwise answer the cursor
    /// question with silence.
    ///
    /// `.cursorUpdate` is the option that matters. Without it the panel never
    /// answers "what is the cursor here?", the window UNDER the overlay answers
    /// instead, and the pointer morphs to that window's idea of the spot — an
    /// I-beam over a terminal, a hand over a link in a browser. The board is one
    /// surface of 91 buttons; the pointer has no business changing shape as it
    /// crosses it.
    ///
    /// `.activeAlways` is what keeps all of these arriving while this app is
    /// inactive, which it always is. `NSCursor.set()` is imperative rather than
    /// `resetCursorRects`/`addCursorRect`, because cursor *rects* are a
    /// key-window mechanism and this panel deliberately never becomes key
    /// (`ThumbnailPanel.canBecomeKey`) — hovering the board must not pull the
    /// caret out of the app being demonstrated. That is the same scar
    /// `BreakTimerOverlay` carries in the other app.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                       options: [.activeAlways, .mouseEnteredAndExited,
                                                 .mouseMoved, .cursorUpdate, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// The panel is never key, so every click on it is a "first mouse". Said here
    /// as well as on `TileView` because the gaps between tiles are the grid.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseEntered(with event: NSEvent) { PanelCursor.pinArrow() }
    /// Re-asserted on every move: the panel appearing *under* a stationary mouse
    /// is the normal case for a hold gesture, and that delivers moves without an
    /// enter.
    override func mouseMoved(with event: NSEvent) { PanelCursor.pinArrow() }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinArrow() }
    override func mouseExited(with event: NSEvent) { releaseCursor() }

    /// Hand the cursor back to whoever is underneath. An imperative `set()`
    /// bypasses AppKit's own cursor restoration, so both ways out have to say so
    /// explicitly: leaving the grid, and the panel being ordered out from under a
    /// cursor that then never gets a `mouseExited` at all. The arrow is also what
    /// the panel itself shows now, so this no longer *changes* anything the eye
    /// can see — it hands ownership back, and the window underneath reasserts its
    /// own cursor on the next move.
    func releaseCursor() { NSCursor.arrow.set() }

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

/// The panel's cursor policy, in one place: **over the board it is an arrow**.
///
/// A borderless non-activating panel does not own the pointer's shape by being
/// on top of the screen. The shape is decided by whoever answers the cursor
/// question for the spot under the pointer, and with no answer from us that is
/// the window UNDER the overlay — so the board used to show an I-beam over a
/// terminal and a pointing hand over a browser link, a pointer reacting to a
/// window the user cannot even see.
enum PanelCursor {
    /// True when the last `pinArrow()` found the arrow already in place, i.e.
    /// nothing underneath had taken the cursor. Read by the test hook and
    /// reported by `/test/thumbnail-panel`, because this is the one fact about
    /// the cursor a headless check can actually observe.
    private(set) static var lastFoundArrow = true
    /// How many times the pin had to CORRECT the cursor rather than confirm it.
    /// One or two is the panel opening under a pointer somebody else had shaped;
    /// a number that climbs while the mouse sits still is a fight.
    private(set) static var corrections = 0

    /// Idempotent, and called on every move — so it logs the corrections, not
    /// the confirmations, or a single hover would fill the log.
    static func pinArrow() {
        let wasArrow = NSCursor.current == NSCursor.arrow
        lastFoundArrow = wasArrow
        if !wasArrow {
            corrections += 1
            effectsInfo("panel cursor: found \(NSCursor.current) under the pointer, pinned the arrow (correction #\(corrections))")
        }
        NSCursor.arrow.set()
    }

    /// For tests: the counters are process-wide.
    static func resetForTesting() {
        lastFoundArrow = true
        corrections = 0
    }
}
