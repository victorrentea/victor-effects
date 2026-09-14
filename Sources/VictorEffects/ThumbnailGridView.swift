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
            let frame = NSRect(x: x, y: y, width: cell, height: cell)
            // The grid is the only thing that knows where the rim is: the margin
            // left of column 0 is `padding` PLUS whatever centring a floored
            // cell left over, not one gap. Set before the frame so the tile's
            // own `layout()` has it first time.
            view.highlightOutsets = TileView.highlightOutsets(
                cell: frame, in: bounds, row: row, col: col, rows: m.rows, cols: cols)
            view.frame = frame
        }
        // The board has just been laid out under a pointer that may not have
        // moved — re-resolve which tile it is on rather than wait for an enter
        // that is not coming.
        syncHoverToMouse()
    }

    // MARK: - Hover, resolved from where the pointer IS

    /// Light the tile containing `point` and no other; `nil` lights none.
    ///
    /// Hover used to be `mouseEntered`/`mouseExited` on the tiles and nothing
    /// else, which answers "the pointer crossed into this tile" — a different
    /// question from "which tile is the pointer on". They differ exactly when
    /// the BOARD moves instead of the mouse: a panel sliding in, hugging to a
    /// new height, or flipping page under a held key delivers no enter at all.
    /// On one screen the board takes the bottom-right two thirds, so the pointer
    /// is usually outside it and has to travel in — the enter arrives and the
    /// bug hides. On two screens the board FILLS the second screen, so it lands
    /// under wherever the pointer already was and nothing ever lit up.
    func hover(at point: NSPoint?) {
        for view in tileViews {
            view.setHovered(point.map { view.frame.contains($0) } ?? false)
        }
    }

    /// Re-resolve the hover against the real pointer, with no event to hand.
    /// Called after every move of the window the grid is in, and from `layout`.
    func syncHoverToMouse() {
        guard let window, window.isVisible, !isHidden else { hover(at: nil); return }
        let local = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        hover(at: bounds.contains(local) ? local : nil)
    }

    /// A window ordering out owes its views no `mouseExited`, so without this the
    /// tile the pointer was on stays green and is still green on the next show.
    func clearHover() { hover(at: nil) }

    /// `GET /test/thumbnail-panel/hover[?x=&y=]` — resolve the hover (at a given
    /// point in view coordinates, or against the real pointer) and report what
    /// the mark actually became. The geometry unit tests cannot see a layer; this
    /// can, from a shell, with nobody looking at the screen.
    func hoverProbeJSON(at point: NSPoint?) -> String {
        if let point { hover(at: point) } else { syncHoverToMouse() }
        let marked = tileViews.filter { $0.hoverProbe.hovered }.map { $0.hoverProbe.json }
        return "{\"page\":\"effects\",\"tiles\":\(tileViews.count),"
            + "\"bounds\":{\"w\":\(Int(bounds.width)),\"h\":\(Int(bounds.height))},"
            + "\"hovered\":[\(marked.joined(separator: ","))]}"
    }

    // MARK: - The cursor is a pointing hand, and stays one

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

    override func mouseEntered(with event: NSEvent) {
        PanelCursor.pinHand()
        hover(at: convert(event.locationInWindow, from: nil))
    }
    /// Re-asserted on every move: the panel appearing *under* a stationary mouse
    /// is the normal case for a hold gesture, and that delivers moves without an
    /// enter. The hover rides along for the same reason — the grid sees the
    /// pointer's position on every move, which is the only reading that cannot
    /// go stale.
    override func mouseMoved(with event: NSEvent) {
        PanelCursor.pinHand()
        hover(at: convert(event.locationInWindow, from: nil))
    }
    override func cursorUpdate(with event: NSEvent) { PanelCursor.pinHand() }
    override func mouseExited(with event: NSEvent) {
        releaseCursor()
        clearHover()
    }

    /// Hand the cursor back to whoever is underneath. An imperative `set()`
    /// bypasses AppKit's own cursor restoration, so both ways out have to say so
    /// explicitly: leaving the grid, and the panel being ordered out from under a
    /// cursor that then never gets a `mouseExited` at all. The arrow here is not
    /// the board's shape — it is the neutral shape to leave behind now that the
    /// board shows a hand; the window underneath reasserts its own on the next
    /// move.
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

/// The panel's cursor policy, in one place: **over the board it is a pointing
/// hand**.
///
/// A borderless non-activating panel does not own the pointer's shape by being
/// on top of the screen. The shape is decided by whoever answers the cursor
/// question for the spot under the pointer, and with no answer from us that is
/// the window UNDER the overlay — so the board used to show an I-beam over a
/// terminal and a pointing hand over a browser link, a pointer reacting to a
/// window the user cannot even see. That part of the policy is unchanged: we
/// must answer, every time, or somebody else does.
///
/// **The answer was the arrow until 14 Sep 2026, and Victor reversed it.** The
/// old reasoning was that the board is one continuous surface, so a shape that
/// changed as the pointer crossed it would be noise. The board it describes no
/// longer exists: every cell is a button, the hover mark now lights the cell
/// under the pointer, and a hand is what says "this thing is clickable" to a
/// room watching over a shoulder. The shape no longer flickers *within* the
/// board either — the hand is pinned by the grid and by the panel itself, not
/// only by the tiles, so crossing a gap between two cells never drops it.
enum PanelCursor {
    /// The one shape the board shows. Named once so the pin, the release and
    /// the test all mean the same cursor.
    static var cursor: NSCursor { .pointingHand }

    /// True when the last `pinHand()` found the hand already in place, i.e.
    /// nothing underneath had taken the cursor. Read by the test hook and
    /// reported by `/test/thumbnail-panel`, because this is the one fact about
    /// the cursor a headless check can actually observe.
    private(set) static var lastFoundHand = true
    /// How many times the pin had to CORRECT the cursor rather than confirm it.
    /// One or two is the panel opening under a pointer somebody else had shaped;
    /// a number that climbs while the mouse sits still is a fight.
    private(set) static var corrections = 0

    /// Re-asserts the hand on a timer for as long as the board is up.
    ///
    /// **A `set()` from this app does not stick.** Victor Effects is an
    /// accessory app and the panel deliberately never becomes key, so the
    /// ACTIVE application still owns the pointer's shape: it re-asserts its own
    /// cursor on its own schedule and ours is wiped between our events. That
    /// went unnoticed for as long as the board's answer was `NSCursor.arrow`,
    /// because losing the fight and the default look identical. Ask for a hand
    /// and the loss is suddenly visible.
    ///
    /// Events alone cannot win it — `cursorUpdate` and `mouseMoved` only fire
    /// when the pointer MOVES, and the pointer resting on a tile is the normal
    /// case for a held key. So the pin repeats while the panel is visible and
    /// the pointer is over it, and stops the moment it is not.
    private static var pinTimer: Timer?
    /// Set by the panel: is the pointer over the board at this instant?
    static var pointerIsOverBoard: () -> Bool = { false }

    static func startPinning() {
        stopPinning()
        // `.common` because the gesture that raises the board is a key being
        // HELD, and a default-mode timer stops running during event tracking.
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            guard pointerIsOverBoard() else { return }
            cursor.set()
        }
        RunLoop.main.add(timer, forMode: .common)
        pinTimer = timer
    }

    static func stopPinning() {
        pinTimer?.invalidate()
        pinTimer = nil
    }

    /// Idempotent, and called on every move — so it logs the corrections, not
    /// the confirmations, or a single hover would fill the log.
    static func pinHand() {
        let wasHand = NSCursor.current == cursor
        lastFoundHand = wasHand
        if !wasHand {
            corrections += 1
            effectsInfo("panel cursor: found \(NSCursor.current) under the pointer, pinned the hand (correction #\(corrections))")
        }
        cursor.set()
    }

    /// For tests: the counters are process-wide.
    static func resetForTesting() {
        lastFoundHand = true
        corrections = 0
    }
}
