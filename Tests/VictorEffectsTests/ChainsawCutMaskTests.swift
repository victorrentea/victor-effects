import XCTest
@testable import VictorEffects

/// The 🪚 chainsaw's one rule, pinned down: the screen is anchored by its
/// periphery, and a piece falls exactly when the kerf has severed its last
/// connection to that border. Every case below is a shape a hand can actually
/// saw, because the interesting failures are all "it looked enclosed but wasn't"
/// and the reverse.
final class ChainsawCutMaskTests: XCTestCase {

    private let screen = CGSize(width: 300, height: 200)
    private let kerf: CGFloat = 7          // radius, i.e. a 14 pt-wide slot

    private func mask() -> ChainsawCutMask {
        ChainsawCutMask(size: screen, cellSize: 3)
    }

    private func saw(_ mask: ChainsawCutMask, _ points: [CGPoint]) {
        for (a, b) in zip(points, points.dropFirst()) {
            mask.saw(from: a, to: b, radius: kerf)
        }
    }

    private func detached(_ mask: ChainsawCutMask) -> [ChainsawCutMask.Piece] {
        mask.detachedPieces(minCells: 24)
    }

    // MARK: The two halves of the rule

    func testAStrokeRightAcrossTheScreenDropsNothing() {
        // Edge to edge through the middle. It *looks* like the screen was cut in
        // two, and it was — but both halves are still hanging from the border.
        let m = mask()
        saw(m, [CGPoint(x: 0, y: 100), CGPoint(x: 300, y: 100)])
        XCTAssertTrue(detached(m).isEmpty)
    }

    func testAClosedLoopInTheMiddleDropsWhatIsInsideIt() {
        let m = mask()
        saw(m, [CGPoint(x: 80, y: 60), CGPoint(x: 200, y: 60),
                CGPoint(x: 200, y: 140), CGPoint(x: 80, y: 140),
                CGPoint(x: 80, y: 60)])
        let pieces = detached(m)
        XCTAssertEqual(pieces.count, 1)
        guard let piece = pieces.first else { return }
        // The hole is the loop's interior, inset by the kerf's own half-width.
        let rect = m.rect(of: piece)
        XCTAssertEqual(rect.midX, 140, accuracy: 6)
        XCTAssertEqual(rect.midY, 100, accuracy: 6)
        XCTAssertEqual(rect.width, 120 - 2 * kerf, accuracy: 8)
        XCTAssertEqual(rect.height, 80 - 2 * kerf, accuracy: 8)
    }

    func testALoopLeftOpenByAThreadHoldsOn() {
        // Same rectangle, but the last side stops 30 pt short. It reads as a
        // closed loop from across the room and it must still hold — otherwise
        // "cut all the way round" would not be a thing you can fail at.
        let m = mask()
        saw(m, [CGPoint(x: 80, y: 60), CGPoint(x: 200, y: 60),
                CGPoint(x: 200, y: 140), CGPoint(x: 80, y: 140),
                CGPoint(x: 80, y: 90)])
        XCTAssertTrue(detached(m).isEmpty)
    }

    // MARK: The corner — the case Victor asked about by name

    func testCuttingStraightAcrossACornerDropsNothing() {
        // Left edge to top edge, slicing the top-left corner off. The triangle
        // is *made of* border, so it is still anchored and stays put.
        let m = mask()
        saw(m, [CGPoint(x: 0, y: 140), CGPoint(x: 90, y: 200)])
        XCTAssertTrue(detached(m).isEmpty)
    }

    func testACornerFallsOnlyOnceTheSawHasBeenRoundItAlongTheEdgesToo() {
        // The same diagonal, plus a pass down the left edge and along the top:
        // now the corner's own border cells are gone and nothing holds it.
        let m = mask()
        saw(m, [CGPoint(x: 90, y: 200), CGPoint(x: 0, y: 140),
                CGPoint(x: 0, y: 200), CGPoint(x: 90, y: 200)])
        let pieces = detached(m)
        XCTAssertEqual(pieces.count, 1)
        guard let piece = pieces.first else { return }
        let rect = m.rect(of: piece)
        XCTAssertLessThan(rect.minX, 30)
        XCTAssertGreaterThan(rect.maxY, screen.height - 30)
    }

    // MARK: Consequences

    func testAHoleLeftByOnePieceCanSeverTheNext() {
        // Drop a square, then cut a three-sided pen against the hole it left:
        // the new region is fenced by kerf on three sides and by MISSING
        // material on the fourth. A hole in a hanging sheet holds nothing up,
        // and the mask has to agree — otherwise the second cut would need a
        // fourth side that the user can see is already gone.
        let m = mask()
        saw(m, [CGPoint(x: 100, y: 40), CGPoint(x: 240, y: 40),
                CGPoint(x: 240, y: 160), CGPoint(x: 100, y: 160),
                CGPoint(x: 100, y: 40)])
        for piece in detached(m) { m.drop(piece) }
        XCTAssertGreaterThan(m.cells.filter { $0 == ChainsawCutMask.fallen }.count, 0)

        // Three sides only; the right-hand one is the hole's own edge.
        saw(m, [CGPoint(x: 105, y: 130), CGPoint(x: 50, y: 130),
                CGPoint(x: 50, y: 70), CGPoint(x: 105, y: 70)])
        let pieces = detached(m)
        XCTAssertEqual(pieces.count, 1)
        guard let piece = pieces.first else { return }
        let rect = m.rect(of: piece)
        XCTAssertEqual(rect.midX, 79, accuracy: 8)
        XCTAssertEqual(rect.midY, 100, accuracy: 8)
    }

    func testCrumbsSmallerThanTheThresholdAreLeftAlone() {
        // A loop barely wider than the kerf encloses a few cells. Dropping those
        // would read as the renderer glitching, not as a piece of screen.
        let m = mask()
        saw(m, [CGPoint(x: 140, y: 90), CGPoint(x: 160, y: 90),
                CGPoint(x: 160, y: 110), CGPoint(x: 140, y: 110),
                CGPoint(x: 140, y: 90)])
        XCTAssertTrue(detached(m).isEmpty)
    }

    func testTwoSeparateLoopsBothComeLooseInOneSweep() {
        // The sweep answers for the whole screen at once, so a stroke that frees
        // two regions at the same instant must not drop only the first.
        let m = mask()
        saw(m, [CGPoint(x: 40, y: 60), CGPoint(x: 110, y: 60),
                CGPoint(x: 110, y: 140), CGPoint(x: 40, y: 140),
                CGPoint(x: 40, y: 60)])
        saw(m, [CGPoint(x: 190, y: 60), CGPoint(x: 260, y: 60),
                CGPoint(x: 260, y: 140), CGPoint(x: 190, y: 140),
                CGPoint(x: 190, y: 60)])
        XCTAssertEqual(detached(m).count, 2)
    }

    // MARK: Bookkeeping the renderer relies on

    func testDirtyOnlyReportsActualRemoval() {
        let m = mask()
        XCTAssertFalse(m.dirty)
        m.saw(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 100), radius: kerf)
        XCTAssertTrue(m.dirty)
        _ = detached(m)
        XCTAssertFalse(m.dirty)
        // Sawing the same slot again removes nothing that is still there.
        m.saw(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 140, y: 100), radius: kerf)
        XCTAssertFalse(m.dirty)
    }

    func testSilhouetteCoversExactlyThePiecesCellsAndIsEmittedTopDown() {
        let m = mask()
        saw(m, [CGPoint(x: 80, y: 60), CGPoint(x: 200, y: 60),
                CGPoint(x: 200, y: 140), CGPoint(x: 80, y: 140),
                CGPoint(x: 80, y: 60)])
        guard let piece = detached(m).first else { return XCTFail("nothing came loose") }
        let rgba = m.silhouetteRGBA(of: piece)
        XCTAssertEqual(rgba.count, piece.cols * piece.rows * 4)
        XCTAssertEqual(rgba.enumerated().filter { $0.offset % 4 == 3 && $0.element == 255 }.count,
                       piece.cells.count)
        // Bottom-up grid, top-down image: the piece's bottom-left cell has to
        // land on the LAST row of the buffer, or every falling piece is mirrored.
        let bottomLeft = piece.cells.min { ($0 / m.cols, $0 % m.cols) < ($1 / m.cols, $1 % m.cols) }!
        let col = bottomLeft % m.cols - piece.minCol
        XCTAssertEqual(rgba[((piece.rows - 1) * piece.cols + col) * 4 + 3], 255)
    }
}
