import AppKit
import XCTest
@testable import VictorEffects

/// The subtitle is the same box in the same place on the glass whatever is
/// going on (Victor, 2026-10-14): drawn over every effect, and pinned through
/// macOS's ⌥-scroll zoom.
final class CaptionPinTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let rest = CGSize(width: 420, height: 68)

    func testUnzoomedItSitsCentredNearTheBottom() {
        let (frame, k) = CaptionOverlay.placement(restSize: rest, visible: screen, screen: screen)
        XCTAssertEqual(k, 1)
        XCTAssertEqual(frame.size, rest)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.001)
        XCTAssertEqual(frame.minY, screen.height * CaptionOverlay.bottomInset, accuracy: 0.001)
    }

    /// The point of the counter-scaling: magnify the slice back up to the
    /// display, as the glass does, and the caption lands exactly where and as
    /// big as it is unzoomed — wherever the slice is.
    func testZoomedItLooksTheSameOnTheGlass() {
        let unzoomed = CaptionOverlay.placement(restSize: rest, visible: screen, screen: screen).frame
        for (factor, origin) in [(2.0, CGPoint(x: 300, y: 200)), (3.0, CGPoint(x: 0, y: 0)),
                                 (1.5, CGPoint(x: 576, y: 372))] {
            let slice = CGRect(origin: origin, size: CGSize(width: screen.width / factor,
                                                            height: screen.height / factor))
            let (frame, k) = CaptionOverlay.placement(restSize: rest, visible: slice, screen: screen)
            XCTAssertEqual(k, 1 / factor, accuracy: 0.0001)
            let onGlass = CGRect(x: (frame.minX - slice.minX) * factor, y: (frame.minY - slice.minY) * factor,
                                 width: frame.width * factor, height: frame.height * factor)
            XCTAssertEqual(onGlass.minX, unzoomed.minX, accuracy: 0.01, "×\(factor) at \(origin)")
            XCTAssertEqual(onGlass.minY, unzoomed.minY, accuracy: 0.01, "×\(factor) at \(origin)")
            XCTAssertEqual(onGlass.width, unzoomed.width, accuracy: 0.01, "×\(factor) at \(origin)")
            XCTAssertEqual(onGlass.height, unzoomed.height, accuracy: 0.01, "×\(factor) at \(origin)")
        }
    }

    /// "Painted last" is a window level, and a level is only the highest while
    /// nobody raises another window past it. This PARSES every `level =` in the
    /// sources rather than keeping a second list, so the peek mascot moving to
    /// `maximumWindow + 2` fails here, not in front of the room.
    func testTheCaptionIsAboveEveryOtherWindowWeOpen() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VictorEffects")
        let files = try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" && $0.lastPathComponent != "SoundCaptions.swift" }
        let named: [String: Int] = [
            "floating": NSWindow.Level.floating.rawValue, "statusBar": NSWindow.Level.statusBar.rawValue,
            "popUpMenu": NSWindow.Level.popUpMenu.rawValue, "screenSaver": NSWindow.Level.screenSaver.rawValue,
            "modalPanel": NSWindow.Level.modalPanel.rawValue, "mainMenu": NSWindow.Level.mainMenu.rawValue,
            "normal": NSWindow.Level.normal.rawValue,
        ]
        let max = Int(CGWindowLevelForKey(.maximumWindow))
        let assignment = try NSRegularExpression(pattern: #"\blevel\s*=\s*(.+)$"#)
        let offset = try NSRegularExpression(pattern: #"maximumWindow\)\)\s*([+-])\s*(\d+)"#)
        var seen = 0
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for line in text.components(separatedBy: "\n") {
                let ns = line as NSString
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//"),
                      let m = assignment.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
                else { continue }
                let rhs = ns.substring(with: m.range(at: 1))
                let value: Int
                if rhs.contains("maximumWindow") {
                    let r = rhs as NSString
                    if let o = offset.firstMatch(in: rhs, range: NSRange(location: 0, length: r.length)) {
                        let n = Int(r.substring(with: o.range(at: 2)))!
                        value = r.substring(with: o.range(at: 1)) == "+" ? max + n : max - n
                    } else {
                        value = max
                    }
                } else if let name = named.first(where: { rhs.contains(".\($0.key)") }) {
                    value = name.value
                } else {
                    continue      // not a window level (`cup.level = level`, a volume…)
                }
                seen += 1
                XCTAssertGreaterThan(CaptionOverlay.windowLevel.rawValue, value,
                                     "\(file.lastPathComponent): `\(line.trimmingCharacters(in: .whitespaces))` "
                                     + "is not below the caption — raise CaptionOverlay.windowLevel")
            }
        }
        XCTAssertGreaterThanOrEqual(seen, 5, "the parser found too few window levels to mean anything")
    }
}
