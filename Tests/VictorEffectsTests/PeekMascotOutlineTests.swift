import XCTest
import CoreGraphics
@testable import VictorEffects

/// The mascot's white rim (`PeekMascotOutline`), asserted on a synthetic
/// cut-out rather than on the bundled PNGs: the question is whether the alpha
/// channel gets stroked, and a square with a known silhouette answers that
/// without tying the test to artwork that can be redrawn.
final class PeekMascotOutlineTests: XCTestCase {

    /// A `size`×`size` transparent image with an opaque black square of
    /// `inset`…`size-inset` in the middle.
    private func cutout(size: Int, inset: Int) -> CGImage {
        let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset))
        return ctx.makeImage()!
    }

    /// RGBA at a pixel, with y measured from the BOTTOM as Core Graphics does.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = CGContext(
            data: &data, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // Row 0 of the buffer is the TOP row; flip so callers can think in CG coordinates.
        let i = ((image.height - 1 - y) * image.width + x) * 4
        return (data[i], data[i + 1], data[i + 2], data[i + 3])
    }

    func testRimIsTwoPercentOfHeightButNeverThinnerThanThreePixels() {
        XCTAssertEqual(PeekMascotOutline.ringWidth(forHeight: 400), 8)
        XCTAssertEqual(PeekMascotOutline.ringWidth(forHeight: 50), 3, "a small PNG still gets a real rim")
    }

    func testOutlinePadsTheImageByTheRimOnAllFourSides() {
        let image = cutout(size: 100, inset: 20)
        let out = PeekMascotOutline.outlined(image)!
        let pad = PeekMascotOutline.ringWidth(forHeight: 100)
        XCTAssertEqual(out.width, 100 + 2 * pad)
        XCTAssertEqual(out.height, 100 + 2 * pad)
    }

    func testPixelsJustOutsideTheSilhouetteTurnWhiteAndOpaque() {
        let image = cutout(size: 100, inset: 20)
        let pad = PeekMascotOutline.ringWidth(forHeight: 100)
        let out = PeekMascotOutline.outlined(image)!

        // The square's left edge sits at x = pad + 20 in the padded image; one
        // pixel to its left is rim, and must be solid white or the mascot has
        // no border on a dark screen.
        let rim = pixel(out, x: pad + 20 - 1, y: pad + 50)
        XCTAssertEqual(rim.a, 255)
        XCTAssertEqual(rim.r, 255)
        XCTAssertEqual(rim.g, 255)
        XCTAssertEqual(rim.b, 255)

        // The artwork itself is untouched: the middle is still the black square.
        let body = pixel(out, x: pad + 50, y: pad + 50)
        XCTAssertEqual(body.a, 255)
        XCTAssertEqual(body.r, 0)
    }

    func testTheRimStopsAndTheCornerStaysTransparent() {
        let image = cutout(size: 100, inset: 20)
        let out = PeekMascotOutline.outlined(image)!

        // Far corner of the padded canvas: the rim reaches `pad` beyond the
        // square, never the whole sheet — a rim that filled the canvas would be
        // the white card the cut-out exists to avoid.
        XCTAssertEqual(pixel(out, x: 0, y: 0).a, 0)
    }
}
