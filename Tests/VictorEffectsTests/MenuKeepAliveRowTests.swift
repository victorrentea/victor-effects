import AppKit
import XCTest
@testable import VictorEffects

/// The BT Keepalive row draws its own tick in the title (a real `state` shifts
/// every row right). Two ways that has already gone wrong, both only visible by
/// looking: the emoji ✔️/✖️ were black glyphs that vanished on the dark menu,
/// and a text glyph narrower than the 🔥/✨/🎦 above it pulls its words out of
/// line. So the row is rendered here, in both appearances, and measured.
///
/// Every run also leaves `menu-rows-<appearance>.png` in the temp directory
/// (the path is printed) — open them to eyeball the whole menu before a deploy.
final class MenuKeepAliveRowTests: XCTestCase {
    private let font = NSFont.menuFont(ofSize: 0)
    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private func width(_ s: String) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }

    /// The part of the title that stands where the other rows have an emoji.
    private func markColumn(_ title: String) -> String {
        String(title.prefix { $0 != " " })
    }

    func testTheMarkIsAsWideAsTheEmojiAboveIt() {
        for checked in [true, false] {
            let mark = markColumn(MenuBar.keepAliveTitle(checked: checked))
            XCTAssertEqual(width(mark), width("🔥"), accuracy: 1.0, "checked=\(checked)")
        }
    }

    func testTheMarkStandsOutFromTheMenuInBothAppearances() throws {
        for name in appearances {
            for checked in [true, false] {
                let mark = markColumn(MenuBar.keepAliveTitle(checked: checked))
                let contrast = try maxContrast(of: mark, in: name)
                XCTAssertGreaterThan(contrast, 0.5, "\(name.rawValue) checked=\(checked): mark barely visible")
            }
        }
    }

    func testRendersTheMenuForEyeballing() throws {
        let titles = ["✨ Effects", "🎦 Videos", "🔥 Whip",
                      MenuBar.keepAliveTitle(checked: true),
                      MenuBar.keepAliveTitle(checked: false)]
        for name in appearances {
            let rep = try render(titles, in: name)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("menu-rows-\(name == .darkAqua ? "dark" : "light").png")
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
            print("🖼  \(url.path)")
        }
    }

    // MARK: - rendering

    private let rowHeight: CGFloat = 22
    private let scale: CGFloat = 2

    private func render(_ titles: [String], in name: NSAppearance.Name) throws -> NSBitmapImageRep {
        let size = NSSize(width: 180, height: rowHeight * CGFloat(titles.count))
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = size
        let appearance = try XCTUnwrap(NSAppearance(named: name))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        appearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (i, title) in titles.enumerated() {
                let y = size.height - rowHeight * CGFloat(i + 1)
                (title as NSString).draw(at: NSPoint(x: 10, y: y + 3),
                                         withAttributes: [.font: font, .foregroundColor: NSColor.labelColor])
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// Largest luminance distance between any pixel of the drawn text and the
    /// menu background, 0…1. A black glyph on the dark menu scores ~0.2.
    private func maxContrast(of text: String, in name: NSAppearance.Name) throws -> CGFloat {
        let rep = try render([text], in: name)
        func luminance(_ c: NSColor?) -> CGFloat {
            guard let c = c?.usingColorSpace(.deviceRGB) else { return 0 }
            return 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        }
        let background = luminance(rep.colorAt(x: 0, y: 0))
        var best: CGFloat = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                best = max(best, abs(luminance(rep.colorAt(x: x, y: y)) - background))
            }
        }
        return best
    }
}
