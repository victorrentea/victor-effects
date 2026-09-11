import CryptoKit
import XCTest
@testable import VictorEffects

/// The manifest's canonical form is a wire contract: a client computes the same
/// hash over its own copy of the sounds and compares. Change the joining, the
/// sorting or the case of the hex here and every client concludes "the Mac's
/// copy differs" and stops routing its sounds — with nothing failing anywhere.
final class SoundsManifestTests: XCTestCase {
    private func makeSoundsDir(_ files: [String: String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sounds-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try Data(contents.utf8).write(to: dir.appendingPathComponent(name))
        }
        return dir
    }

    private func expectedHash(_ files: [String: String]) -> String {
        func sha(_ s: String) -> String {
            SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
        }
        let joined = files.keys.sorted()
            .filter { $0.lowercased().hasSuffix(".mp3") }
            .map { "\($0):\(sha(files[$0]!))\n" }
            .joined()
        return sha(joined)
    }

    func testCanonicalFormOverTwoFiles() throws {
        let files = ["01_baby.mp3": "aaa", "02_siren.mp3": "bbb"]
        let dir = try makeSoundsDir(files)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(SoundsManifest.combinedHash(ofDirectory: dir), expectedHash(files))
    }

    func testOnlyMp3FilesCount() throws {
        // The folder is shared with a tablet build: it also holds
        // `sound-timing.json`, `tiles.json` and a `tiles/` directory of images.
        // None of those may move the hash, or every tile edit would be reported
        // as a sound mismatch.
        let sounds = ["01_baby.mp3": "aaa"]
        let dir = try makeSoundsDir(sounds)
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = SoundsManifest.combinedHash(ofDirectory: dir)

        try Data(#"{"columns":13}"#.utf8).write(to: dir.appendingPathComponent("tiles.json"))
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("tiles"),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(SoundsManifest.combinedHash(ofDirectory: dir), before)
    }

    func testChangingOneByteChangesTheHash() throws {
        let dir = try makeSoundsDir(["01_baby.mp3": "aaa"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = SoundsManifest.combinedHash(ofDirectory: dir)
        try Data("aab".utf8).write(to: dir.appendingPathComponent("01_baby.mp3"))
        XCTAssertNotEqual(SoundsManifest.combinedHash(ofDirectory: dir), before)
    }

    func testHashIsOrderIndependentOfTheFilesystem() throws {
        // `contentsOfDirectory` does not promise an order; the manifest sorts.
        let a = try makeSoundsDir(["b.mp3": "1", "a.mp3": "2"])
        let b = try makeSoundsDir(["a.mp3": "2", "b.mp3": "1"])
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        XCTAssertEqual(SoundsManifest.combinedHash(ofDirectory: a),
                       SoundsManifest.combinedHash(ofDirectory: b))
    }

    func testHashIs64LowercaseHexCharacters() throws {
        let dir = try makeSoundsDir(["01_baby.mp3": "aaa"])
        defer { try? FileManager.default.removeItem(at: dir) }
        let hash = SoundsManifest.combinedHash(ofDirectory: dir)
        XCTAssertEqual(hash.count, 64)
        XCTAssertEqual(hash, hash.lowercased())
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit })
    }
}
