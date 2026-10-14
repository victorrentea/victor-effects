import XCTest
@testable import VictorEffects

/// Every player is built through `SoundManager.player(…)`, which refuses until
/// the background warm-up is done — a player built on the main thread before
/// that froze the whole app for minutes after a boot (2026-10-14). A new
/// `AVAudioPlayer(` anywhere else reopens that hole, so the sources are parsed.
final class AudioGateTests: XCTestCase {
    func testNoPlayerIsBuiltOutsideTheGate() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/VictorEffects")
        var offenders: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path) where file.hasSuffix(".swift") {
            let lines = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
                .components(separatedBy: "\n")
            for (i, line) in lines.enumerated() where line.contains("AVAudioPlayer(") {
                let code = line.trimmingCharacters(in: .whitespaces)
                if code.hasPrefix("//") { continue }
                // The gate itself, and the warm-up that opens it.
                if file == "SoundManager.swift",
                   code.contains("return try AVAudioPlayer(") || code.contains("let player = try? AVAudioPlayer(contentsOf: url) else { return }") {
                    continue
                }
                offenders.append("\(file):\(i + 1): \(code)")
            }
        }
        XCTAssertEqual(offenders, [], "build players with SoundManager.player(contentsOf:) / player(data:)")
    }

    func testThePlayerRefusesUntilWarm() {
        let was = SoundManager.audioReady
        defer { SoundManager.audioReady = was }
        SoundManager.audioReady = false
        XCTAssertThrowsError(try SoundManager.player(data: Data()))
    }
}
