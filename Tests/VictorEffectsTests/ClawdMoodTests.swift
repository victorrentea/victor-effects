import XCTest
import ImageIO
import UniformTypeIdentifiers
@testable import VictorEffects

/// 🦀 The drawn Clawd has to be a drop-in for `claude-icon.png` — same canvas,
/// same silhouette where the hit-mask and the hat expect it — and each mood has
/// to actually look different. Leaves `clawd-moods.png` in `$TMPDIR` to look at.
final class ClawdMoodTests: XCTestCase {

    func testEveryMoodDrawsOnTheIconsCanvas() throws {
        for mood in ClawdMood.allCases {
            for boil in 0..<ClawdArt.boilFrames {
                let image = try XCTUnwrap(ClawdArt.picture(mood, boil: boil), "\(mood) #\(boil)")
                XCTAssertEqual(image.width, 461)
                XCTAssertEqual(image.height, 363)
            }
        }
    }

    /// The whip's hit-mask is read off the picture: the body must be solid,
    /// the gaps between the legs and the corners above the arms see-through.
    func testTheSilhouetteIsClawds() throws {
        let frame = CGRect(x: 0, y: 0, width: 461, height: 363)   // y up
        for mood in ClawdMood.allCases {
            let mask = try XCTUnwrap(PeekAlphaMask(image: try XCTUnwrap(ClawdArt.picture(mood))))
            XCTAssertTrue(mask.isOpaque(CGPoint(x: 230, y: 363 - 140), in: frame), "\(mood): mid-body")
            XCTAssertTrue(mask.isOpaque(CGPoint(x: 62, y: 363 - 330), in: frame), "\(mood): a leg")
            XCTAssertFalse(mask.isOpaque(CGPoint(x: 230, y: 363 - 335), in: frame), "\(mood): between the legs")
            XCTAssertFalse(mask.isOpaque(CGPoint(x: 6, y: 363 - 330), in: frame), "\(mood): bottom-left corner")
        }
    }

    func testTheMoodsLookDifferent() throws {
        let pictures = try ClawdMood.allCases.map { try XCTUnwrap(ClawdArt.picture($0)) }
        let bytes = pictures.map { $0.dataProvider?.data as Data? }
        XCTAssertEqual(Set(bytes.compactMap { $0 }).count, ClawdMood.allCases.count)
        for emote in [ClawdEmote.music, .spark, .sweat, .stars] {
            XCTAssertNotNil(ClawdArt.emotePicture(emote))
        }
        try writeContactSheet()
    }

    func testTheEntranceNeverRepeatsAndIsAGreeting() {
        var previous: ClawdMood? = nil
        for roll in 0..<50 {
            let next = ClawdMood.entrance(after: previous, roll: roll * 7 + 3)
            XCTAssertTrue(ClawdMood.entrances.contains(next))
            XCTAssertNotEqual(next, previous)
            previous = next
        }
        XCTAssertEqual(Set(ClawdMood.entrances), [.cool, .happy, .excited])
    }

    // MARK: -

    private func writeContactSheet() throws {
        let moods = ClawdMood.allCases
        let cell = CGSize(width: 520, height: 520)
        let ctx = try XCTUnwrap(CGContext(
            data: nil, width: Int(cell.width) * moods.count, height: Int(cell.height) * 2,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        for (row, bg) in [CGColor(gray: 0.95, alpha: 1), CGColor(gray: 0.12, alpha: 1)].enumerated() {
            ctx.setFillColor(bg)
            ctx.fill(CGRect(x: 0, y: CGFloat(row) * cell.height, width: cell.width * CGFloat(moods.count), height: cell.height))
            for (i, mood) in moods.enumerated() {
                let pic = try XCTUnwrap(ClawdArt.picture(mood, boil: row))
                let shown = PeekMascotOutline.outlined(pic) ?? pic
                let x = CGFloat(i) * cell.width + 20, y = CGFloat(row) * cell.height + 40
                ctx.draw(shown, in: CGRect(x: x, y: y, width: 461, height: 363 + 14))
                if let emote = mood.emote, let e = ClawdArt.emotePicture(emote) {
                    ctx.draw(e, in: CGRect(x: x + 370, y: y + 360, width: 120, height: 120))
                }
            }
        }
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("clawd-moods.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try XCTUnwrap(ctx.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
