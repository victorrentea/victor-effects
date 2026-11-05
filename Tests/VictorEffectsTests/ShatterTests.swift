import XCTest
@testable import VictorEffects

final class ShatterTests: XCTestCase {
    private func area(_ t: [CGPoint]) -> CGFloat {
        abs((t[1].x - t[0].x) * (t[2].y - t[0].y) - (t[2].x - t[0].x) * (t[1].y - t[0].y)) / 2
    }

    func testThePiecesCoverThePictureExactly() {
        let triangles = Shatter.triangles(columns: 6, rows: 6)
        XCTAssertEqual(triangles.count, 72)
        XCTAssertEqual(triangles.map(area).reduce(0, +), 1, accuracy: 0.0001)
    }

    func testEveryPieceFliesAwayFromTheMiddle() throws {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let shards = Shatter.shards(of: try XCTUnwrap(ctx.makeImage()), columns: 4, rows: 4)
        XCTAssertEqual(shards.count, 32)
        for s in shards {
            XCTAssertEqual(hypot(s.direction.dx, s.direction.dy), 1, accuracy: 0.001)
            let out = (s.rect.midX - 0.5) * s.direction.dx + (s.rect.midY - 0.5) * s.direction.dy
            XCTAssertGreaterThan(out, -0.1, "a piece heads back through the middle")
        }
    }
}

/// 🔴 The rules of #7: one button at a time, each one the reward for the last.
final class RedButtonGameTests: XCTestCase {
    private let spot = CGPoint(x: 500, y: 400)

    func testPlantedFiveTimesBiggerThanThePointer() {
        XCTAssertEqual(RedButtonGame.bigSide, RedButtonGame.smallSide * 5)
    }

    func testAClickPlantsWhereThePointerIs() {
        var game = RedButtonGame(clipEndMs: 8000)
        XCTAssertEqual(game.click(at: spot, nowMs: 0), .planted)
        XCTAssertTrue(game.isOverButton(spot))
    }

    func testAClickBesideThePlantedButtonDoesNothing() {
        var game = RedButtonGame(clipEndMs: 8000)
        _ = game.click(at: spot, nowMs: 0)
        XCTAssertEqual(game.click(at: CGPoint(x: 900, y: 400), nowMs: 10), .nothing)
    }

    func testTheNextLittleButtonComesOnlyAfterTheBlast() {
        var game = RedButtonGame(clipEndMs: 8000)
        _ = game.click(at: spot, nowMs: 0)
        XCTAssertEqual(game.click(at: spot, nowMs: 100), .blownUp)
        game.advance(nowMs: 100 + RedButtonGame.blastMs - 1)
        XCTAssertNotEqual(game.phase, .armed)
        game.advance(nowMs: 100 + RedButtonGame.blastMs)
        XCTAssertEqual(game.phase, .armed)
    }

    func testUntouchedItEndsWithTheClip() {
        let game = RedButtonGame(clipEndMs: 8000)
        XCTAssertFalse(game.isOver(nowMs: 7999))
        XCTAssertTrue(game.isOver(nowMs: 8000))
    }

    func testAPlantedButtonOutlivesTheClipButNotTheBackstop() {
        var game = RedButtonGame(clipEndMs: 8000)
        _ = game.click(at: spot, nowMs: 7000)
        XCTAssertFalse(game.isOver(nowMs: 30_000))
        XCTAssertTrue(game.isOver(nowMs: 7000 + RedButtonGame.standsMs))
    }

    func testABlastPastTheClipLeavesTimeToPlantAnother() {
        var game = RedButtonGame(clipEndMs: 8000)
        _ = game.click(at: spot, nowMs: 7000)
        _ = game.click(at: spot, nowMs: 20_000)
        game.advance(nowMs: 21_000)
        XCTAssertFalse(game.isOver(nowMs: 26_000))
        XCTAssertTrue(game.isOver(nowMs: 27_000))
    }
}
