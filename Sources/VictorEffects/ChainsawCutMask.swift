import CoreGraphics

/// The screen seen as a sheet of material that the 🪚 chainsaw cursor saws
/// through: a coarse grid of cells, each `intact`, `cut` (the kerf the saw left)
/// or `fallen` (already dropped out of the screen).
///
/// **The rule the whole effect hangs on: the image is anchored by the screen's
/// periphery.** Anything still connected to a border cell through intact
/// material stays up; the moment a stroke severs that last connection, the
/// orphaned piece falls. That is why cutting a corner off needs the saw to go
/// around it *including along the screen edges* — a single edge-to-edge stroke
/// leaves the corner holding on to the border it is made of. There is no
/// "closed loop" test anywhere: enclosure is just the special case of
/// disconnection, so a region hanging by one uncut thread correctly stays up
/// even though it *looks* enclosed.
///
/// Kept as a class, not a struct: the cell array is a few hundred KB and the
/// 60 fps follow timer mutates it on every mouse move.
final class ChainsawCutMask {
    static let intact: UInt8 = 0
    static let cut: UInt8 = 1
    static let fallen: UInt8 = 2

    /// A run of orphaned cells, ready to be turned into a falling sprite.
    /// Cell indices are into `cells`; the bounds are inclusive cell coordinates.
    struct Piece {
        let cells: [Int]
        let minCol: Int, maxCol: Int, minRow: Int, maxRow: Int
        var cols: Int { maxCol - minCol + 1 }
        var rows: Int { maxRow - minRow + 1 }
    }

    let cols: Int
    let rows: Int
    /// Side of one cell in points. Coarse on purpose — it is what gives a fallen
    /// piece its ragged, torn edge instead of a machined one, and it keeps the
    /// connectivity sweep cheap enough to run while the saw is moving.
    let cellSize: CGFloat

    private(set) var cells: [UInt8]
    /// True when material has been removed since the last `detachedPieces()`.
    /// Nothing can come loose without a cut, so an unchanged mask is skipped.
    private(set) var dirty = false

    /// Row 0 is the BOTTOM row, matching `hostLayer`'s y-up geometry, so a cell
    /// maps to a rect with no flip anywhere in the drawing path.
    init(size: CGSize, cellSize: CGFloat) {
        self.cellSize = max(1, cellSize)
        cols = max(1, Int((size.width / self.cellSize).rounded(.up)))
        rows = max(1, Int((size.height / self.cellSize).rounded(.up)))
        cells = [UInt8](repeating: Self.intact, count: cols * rows)
    }

    func state(col: Int, row: Int) -> UInt8 {
        guard col >= 0, col < cols, row >= 0, row < rows else { return Self.fallen }
        return cells[row * cols + col]
    }

    /// Saw a straight kerf of `radius` points from `a` to `b` (both in points,
    /// y-up). Called once per mouse sample, so the segment is short; the disc
    /// stamped at each step is what gives the kerf its width and its round ends.
    ///
    /// `radius` should stay a shade UNDER half the stroke drawn on screen: the
    /// drawn kerf then always covers the cells this removes, so a piece can
    /// never fall and leave a hairline of live desktop showing along the cut.
    func saw(from a: CGPoint, to b: CGPoint, radius: CGFloat) {
        let r = radius / cellSize
        let ax = a.x / cellSize, ay = a.y / cellSize
        let bx = b.x / cellSize, by = b.y / cellSize
        let dx = bx - ax, dy = by - ay
        let steps = max(1, Int((max(abs(dx), abs(dy))).rounded(.up)))
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            stampDisc(col: ax + dx * t, row: ay + dy * t, radius: r)
        }
    }

    private func stampDisc(col: CGFloat, row: CGFloat, radius: CGFloat) {
        let r2 = radius * radius
        let c0 = max(0, Int((col - radius).rounded(.down)))
        let c1 = min(cols - 1, Int((col + radius).rounded(.up)))
        let r0 = max(0, Int((row - radius).rounded(.down)))
        let r1 = min(rows - 1, Int((row + radius).rounded(.up)))
        guard c0 <= c1, r0 <= r1 else { return }
        for rr in r0...r1 {
            let dy = CGFloat(rr) + 0.5 - row
            let base = rr * cols
            for cc in c0...c1 {
                let dx = CGFloat(cc) + 0.5 - col
                guard dx * dx + dy * dy <= r2 else { continue }
                // A cell that has already dropped out of the screen cannot be
                // sawn again — it is not there any more.
                if cells[base + cc] == Self.intact {
                    cells[base + cc] = Self.cut
                    dirty = true
                }
            }
        }
    }

    /// Every intact region that no longer reaches the screen border, i.e. that
    /// is no longer holding on to anything. Pieces smaller than `minCells` are
    /// left alone — a two-cell crumb dropping out of a kerf reads as a glitch,
    /// not as a piece of screen falling.
    ///
    /// Flood from the border and keep what the flood never reached: one sweep
    /// answers the question for the whole screen at once, however many pieces
    /// came loose on the same stroke.
    func detachedPieces(minCells: Int) -> [Piece] {
        dirty = false
        var reached = [Bool](repeating: false, count: cells.count)
        var stack: [Int] = []

        func seed(_ index: Int) {
            if cells[index] == Self.intact && !reached[index] {
                reached[index] = true
                stack.append(index)
            }
        }
        for col in 0..<cols {
            seed(col)                        // bottom edge
            seed((rows - 1) * cols + col)    // top edge
        }
        for row in 0..<rows {
            seed(row * cols)                 // left edge
            seed(row * cols + cols - 1)      // right edge
        }
        flood(from: &stack, into: &reached)

        var pieces: [Piece] = []
        for start in 0..<cells.count where cells[start] == Self.intact && !reached[start] {
            var component: [Int] = []
            stack = [start]
            reached[start] = true
            flood(from: &stack, into: &reached, collectingInto: &component)
            guard component.count >= minCells else { continue }
            var minCol = cols, maxCol = 0, minRow = rows, maxRow = 0
            for index in component {
                let c = index % cols, r = index / cols
                minCol = min(minCol, c); maxCol = max(maxCol, c)
                minRow = min(minRow, r); maxRow = max(maxRow, r)
            }
            pieces.append(Piece(cells: component,
                                minCol: minCol, maxCol: maxCol,
                                minRow: minRow, maxRow: maxRow))
        }
        return pieces
    }

    /// 4-connected flood over intact cells. Explicit stack, not recursion: a
    /// whole-screen region is ~200k cells deep and would blow the stack.
    private func flood(from stack: inout [Int], into reached: inout [Bool],
                       collectingInto component: inout [Int]) {
        while let index = stack.popLast() {
            component.append(index)
            let col = index % cols, row = index / cols
            if col > 0 { visit(index - 1, &stack, &reached) }
            if col < cols - 1 { visit(index + 1, &stack, &reached) }
            if row > 0 { visit(index - cols, &stack, &reached) }
            if row < rows - 1 { visit(index + cols, &stack, &reached) }
        }
    }

    private func flood(from stack: inout [Int], into reached: inout [Bool]) {
        var discard: [Int] = []
        flood(from: &stack, into: &reached, collectingInto: &discard)
    }

    private func visit(_ index: Int, _ stack: inout [Int], _ reached: inout [Bool]) {
        guard !reached[index], cells[index] == Self.intact else { return }
        reached[index] = true
        stack.append(index)
    }

    /// Take a piece out of the sheet. Its cells become `fallen`, which is
    /// impassable — so the hole it leaves can itself sever the next piece,
    /// exactly as a real hole in a hanging sheet would.
    func drop(_ piece: Piece) {
        for index in piece.cells { cells[index] = Self.fallen }
    }

    /// The piece's footprint on screen, in points (y-up, same space as
    /// `hostLayer`), so the falling sprite starts exactly where the material was.
    func rect(of piece: Piece) -> CGRect {
        CGRect(x: CGFloat(piece.minCol) * cellSize,
               y: CGFloat(piece.minRow) * cellSize,
               width: CGFloat(piece.cols) * cellSize,
               height: CGFloat(piece.rows) * cellSize)
    }

    /// A cell-resolution RGBA buffer of the piece's silhouette: opaque black
    /// inside, fully transparent outside. It serves twice — as the black hole
    /// left behind, and (drawn `.destinationIn`) as the stencil that cuts the
    /// falling sprite out of the screenshot — so the two can never disagree
    /// about where the piece's edge is.
    ///
    /// Rows are emitted top-down (CGImage order) from a bottom-up grid.
    func silhouetteRGBA(of piece: Piece) -> [UInt8] {
        let w = piece.cols, h = piece.rows
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        for index in piece.cells {
            let col = index % cols - piece.minCol
            let row = index / cols - piece.minRow
            let offset = ((h - 1 - row) * w + col) * 4
            bytes[offset + 3] = 255      // premultiplied black: RGB stays 0
        }
        return bytes
    }
}
