import XCTest
@testable import VictorEffects

/// The names in docs/assets-and-licences.md's drop-in list.
enum AssetsDoc {
    static func dropInNames() throws -> Set<String> {
        let doc = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/assets-and-licences.md")
        let text = try String(contentsOf: doc, encoding: .utf8)
        let regex = try NSRegularExpression(pattern: "`([A-Za-z0-9_.-]+\\.(?:png|gif|mp3|mov))`")
        let range = NSRange(text.startIndex..., in: text)
        return Set(regex.matches(in: text, range: range).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        })
    }
}

/// Every image or sound the code asks `EffectsResources.url` for must be either
/// shipped in Resources or a documented drop-in — so a pulled file is never a
/// silent, undocumented hole (2026-10-14).
final class AssetsDocTests: XCTestCase {
    func testEveryLiteralAssetTheCodeAsksForIsShippedOrDocumented() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/VictorEffects")
        let resources = sources.appendingPathComponent("Resources")
        let dropIns = try AssetsDoc.dropInNames()
        let regex = try NSRegularExpression(pattern: #"EffectsResources\.url\("([^"\\]+)", "([a-z0-9]+)"\)"#)
        var missing: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for m in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let n = Range(m.range(at: 1), in: text), let e = Range(m.range(at: 2), in: text) else { continue }
                let name = "\(text[n]).\(text[e])"
                let shipped = FileManager.default.fileExists(atPath: resources.appendingPathComponent(name).path)
                if !shipped && !dropIns.contains(name) { missing.append("\(file): \(name)") }
            }
        }
        XCTAssertEqual(missing, [], "add these to the drop-in list in docs/assets-and-licences.md, or ship them")
    }

    func testTheDropInListIsReadable() throws {
        XCTAssertGreaterThan(try AssetsDoc.dropInNames().count, 30)
    }
}
