import XCTest
@testable import VictorEffects

/// A stop takes the picture AND its sound. Nothing in the compiler holds that
/// together: the picture lives in `activeEffects` under a string, and the sound in
/// one of three pools, and `cancelIfRunning` touches only the first. So a re-press
/// on tile #34 (2026-11-05) took the phoenix off and left 5 s of wing beats over
/// an empty desktop. The sources are parsed for the
/// `SoundEffectMapDriftTests` reason: the only way to pass is to make it true. No
/// sound is played here, `build-app.sh` runs this file while a room may be listening.
final class StopSilencesTheSoundTests: XCTestCase {

    private func source(_ file: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("Sources/VictorEffects/\(file)"), encoding: .utf8)
    }

    /// A method's text, up to its closing brace at the 4-space indentation.
    private func body(of marker: String, in swift: String) throws -> String {
        let start = try XCTUnwrap(swift.range(of: marker), "\(marker) is gone")
        let end = try XCTUnwrap(swift.range(of: "\n    }\n", range: start.upperBound..<swift.endIndex))
        return String(swift[start.lowerBound..<end.lowerBound])
    }

    /// `stopEffect` and `stopAllActiveEffects`, with the raid's helper unfolded,
    /// because that is where the booms are named.
    private func stops() throws -> (one: String, all: String) {
        let swift = try source("EmojiAnimator.swift")
        let booms = try body(of: "private func stopBombBooms()", in: swift)
        let unfold = { (text: String) in text.replacingOccurrences(of: "stopBombBooms()", with: booms) }
        return (unfold(try body(of: "func stopEffect(named name: String)", in: swift)),
                unfold(try body(of: "func stopAllActiveEffects()", in: swift)))
    }

    /// The overlapping pool is stopped by name or not at all, so every file put
    /// into it from an effect is either named by BOTH stops or is on this list:
    /// `confetti.mp3` and the opus claw are gone in ~0.6 s, and the 27_clapping
    /// branch of `showApplause` has no caller that reaches it. A new `playClip`
    /// long enough to be heard after a stop fails here, by name.
    func testEverySoundInTheOverlappingPoolIsNamedByBothStops() throws {
        let tooShortToOutliveAStop: Set<String> = ["\"confetti.mp3\"", "Self.opusClawSound", "\"27_clapping.mp3\""]
        let swift = try source("EmojiAnimator.swift")
        let regex = try NSRegularExpression(
            pattern: #"SoundManager\.shared\.(?:playClip|playOverlapping)\(\s*("[^"]+"|Self\.\w+)"#)
        let started = Set(regex.matches(in: swift, range: NSRange(swift.startIndex..., in: swift))
            .compactMap { Range($0.range(at: 1), in: swift).map { String(swift[$0]) } })
        XCTAssertTrue(started.isSuperset(of: ["\"phoenix.mp3\"", "\"03_explosion.mp3\""]), "the pattern went stale: \(started)")

        let (one, all) = try stops()
        for sound in started.subtracting(tooShortToOutliveAStop) {
            XCTAssertTrue(one.contains(sound), "\(sound) plays on after a tile re-press: name it in stopEffect(named:)")
            XCTAssertTrue(all.contains(sound), "\(sound) plays on after the 🛑: name it in stopAllActiveEffects")
        }
    }

    /// The radar is the one tile sound in the `players` pool: `stopAll` sweeps that
    /// pool, `stopTile` does not, and the tile has no routed clip to find.
    func testARePressSilencesTheRadar() throws {
        XCTAssertTrue(try stops().one.contains("\"23_radar.mp3\""))
    }

    /// A raid outlives its head clip, and with no `activeEffects` key
    /// `stopEffect` would find nothing to cancel: re-press took the sound, left the
    /// nuke falling in silence and the tap eating clicks.
    func testARePressEndsTheRaid() throws {
        XCTAssertTrue(try stops().one.contains("stopBombSession"))
    }

    /// The 🛑 has to be lit for as long as a click on it has something to clear.
    func testTheStopIconSeesARaid() throws {
        let engine = try source("EffectsEngine.swift")
        XCTAssertTrue(try body(of: "var isAnythingRunning: Bool", in: engine).contains("isBombRunning"))
    }

    /// Escape stops its own effect's sound and nobody else's: tiles overlap.
    func testEscapeLeavesTheOtherTilesPlaying() throws {
        let swift = try source("EmojiAnimator.swift")
        let bomb = try body(of: "private func startBombInputCapture()", in: swift)
        let fire = try body(of: "fileprivate func escapeFire()", in: swift)
        for path in [bomb, fire] {
            XCTAssertFalse(path.contains("stopTabletSound()"))
            XCTAssertFalse(path.contains("stopAllPlayers()"))
        }
    }

    /// ✋ Escape takes the song with the hands.
    func testEscapeOnTheStopHandTakesTheSong() throws {
        let swift = try source("CantTouchThis.swift")
        let esc = try XCTUnwrap(swift.range(of: "// Esc"))
        XCTAssertTrue(swift[esc.upperBound...].prefix(500).contains("stopWherever(CantTouchThisSession.clip)"))
    }

    /// `stopTile` reaches an effect by its CATALOGUE name, and `stopEffect` drops
    /// a name it can neither match to a `case` nor to an `activeEffects` key: the
    /// re-press then stops nothing on the desktop, silently. The list is what is
    /// left of that today, and is a to-do, not a feature: `fear`'s face and
    /// `broken-glass` are not tracked (they run out in under 5 s), `alarm` is
    /// stopped by the clients' own `/alarm/stop`, and `money` stacks.
    func testEveryTileCanBeReachedByItsName() throws {
        let knownGaps: Set<String> = ["fear", "broken-glass", "alarm", "money"]
        let swift = try source("EmojiAnimator.swift")
        let one = try body(of: "func stopEffect(named name: String)", in: swift)
        let unreachable = Set(EffectsCatalog.assets.compactMap(EffectsCatalog.effectName(forAsset:)))
            .filter { name in
                name != CricketMoon.effectName   // tracked under that constant, not a literal
                    && !one.contains("case \"\(name)\"")
                    && !swift.contains("trackEffect(\"\(name)\"")
                    && !swift.contains("activeEffects[\"\(name)\"]")
            }
        XCTAssertEqual(unreachable, knownGaps, "a re-press on these tiles stops nothing on the desktop")
    }
}
