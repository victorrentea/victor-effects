import XCTest
@testable import VictorEffects

/// The ⭐ badge on the tablet is a PROMISE: "press this tile and something also
/// happens on the desktop". Nothing in the compiler keeps that promise true —
/// `SoundEffectMap` is a dictionary of strings on one side and `fireEffect` is a
/// switch over strings on the other, so every way this drifts is silent:
///
///  - a new special case added to `EffectsEngine.playSound` (the tiles whose cue
///    sits inside the clip) is a tile that animates the desktop and shows no star;
///  - an effect deleted from `playSound` (as the saw was) leaves a star with
///    nothing behind it;
///  - a renamed effect ("blood-drip" → "blood") leaves `fireEffect` logging
///    "unknown effect" while the tile still wears a star;
///  - a renamed/removed mp3 leaves an entry that matches no tile at all.
///
/// These tests read THE SOURCE of the other halves rather than a copy of them,
/// so the guard cannot be satisfied by updating a second list — the only way to
/// make them pass is to make the real thing true. They are deliberately in one
/// file, named after the fear: whoever breaks one gets told which list to fix.
final class SoundEffectMapDriftTests: XCTestCase {

    // MARK: - Reading the source tree

    /// Source file contents, from the checkout this test file lives in. Same
    /// trick as `PeekMascotChoiceTests`: the test bundle carries no Swift source,
    /// and what is being asserted here IS the source.
    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // VictorEffectsTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
        return try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// The body of a top-level method, cut from `marker` to the next
    /// declaration at the same (4-space) indentation. Nested helpers (`func
    /// remember` inside `playSound`) are indented deeper and so stay inside.
    private func body(of marker: String, in swift: String) throws -> String {
        let start = try XCTUnwrap(swift.range(of: marker), "\(marker) is gone — see the note on parser rot below")
        let rest = swift[start.upperBound...]
        for terminator in ["\n    func ", "\n    private func ", "\n    @discardableResult", "\n    /// "] {
            if let end = rest.range(of: terminator) {
                return String(rest[..<end.lowerBound])
            }
        }
        return String(rest)
    }

    /// Every `"..."` literal in `text`. The pattern tolerates escapes because
    /// this file's own source contains JSON literals (`"{\"ok\":true}"`), and a
    /// naive pattern pairs THEIR quotes with the next literal's — silently
    /// swallowing the names being looked for.
    private func quotedStrings(in text: String) -> [String] {
        matches(#""((?:[^"\\]|\\.)*)""#, in: text)
    }

    private func matches(_ pattern: String, in text: String) -> [String] {
        let re = try! NSRegularExpression(pattern: pattern)
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { r in String(text[r]) }
        }
    }

    // MARK: - The star must be backed by an effect that exists

    /// Every effect name the map can fire must be a `case` in `fireEffect`'s
    /// switch. Its `default` only logs "unknown effect", so a typo or a rename
    /// costs nothing at compile time and everything in the room: the tile wears
    /// a star and the desktop does nothing.
    func testEveryMappedEffectNameIsHandledByFireEffect() throws {
        let swift = try source("Sources/VictorEffects/EffectsEngine.swift")
        let fire = try body(of: "private func fireEffect(_ name: String) {", in: swift)
        let handled = Set(
            fire.split(separator: "\n")
                .filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("case ") }
                .flatMap { quotedStrings(in: String($0)) }
        )
        // Parser rot: if this ever comes back empty the test would "pass" while
        // guarding nothing, which is worse than no test at all.
        XCTAssertGreaterThan(handled.count, 30, "fireEffect's switch no longer parses — fix this test, do not delete it")

        for (asset, effect) in SoundEffectMap.onPress {
            XCTAssertTrue(handled.contains(effect),
                          "\(asset) is mapped to '\(effect)', which fireEffect does not handle — the tile would wear a ⭐ over a no-op")
        }
        for (asset, effect) in SoundEffectMap.onStop {
            XCTAssertTrue(handled.contains(effect),
                          "\(asset) stops with '\(effect)', which fireEffect does not handle — the effect would never be torn down")
        }
    }

    /// A stop mapping for a sound nothing starts is dead weight that reads like
    /// a second source of truth for "which sounds have effects".
    func testEveryStopMappingHasAMatchingPress() {
        for asset in SoundEffectMap.onStop.keys {
            XCTAssertNotNil(SoundEffectMap.onPress[asset],
                            "\(asset) has an onStop entry but no onPress — nothing ever starts what it stops")
        }
    }

    // MARK: - The hand-written half: play-path visuals

    /// `playPathVisuals` is the ONE part of `visualAssets` a human types, because
    /// those effects are started from `EffectsEngine.playSound` rather than from
    /// the map. This test reads `playSound` itself: every sound special-cased
    /// there must either be starred (via `onPress` or `playPathVisuals`) or be
    /// declared below as deliberately sound-only. Adding the next inside-the-clip
    /// effect therefore cannot silently skip the tablet.
    func testEverySoundSpecialCasedInPlaySoundIsStarredOrDeclaredSoundOnly() throws {
        // The escape hatch, kept HERE rather than in the app: a special case in
        // playSound that changes only the AUDIO (a clipped tail, a lead-in) and
        // draws nothing. Empty today — every special case currently animates
        // something. Adding a name here is a deliberate "no star", and the diff
        // says so out loud.
        let soundOnly: Set<String> = []

        let swift = try source("Sources/VictorEffects/EffectsEngine.swift")
        let play = try body(of: "func playSound(_ name: String, volumePct: Int?) -> String? {", in: swift)
        // The `if name == "..."` conditions specifically, not every mp3 literal
        // in the body: playSound also NAMES sounds it plays on another tile's
        // behalf (the gong standing in for the silent iris, the checkmark
        // layered under the money), and those are not special-cased tiles.
        let specialCased = Set(matches(#"name == "([^"]+)""#, in: play))
        XCTAssertGreaterThan(specialCased.count, 5, "playSound no longer parses — fix this test, do not delete it")

        let starred = SoundEffectMap.visualAssets
        for asset in specialCased.subtracting(soundOnly) {
            XCTAssertTrue(starred.contains(asset),
                          """
                          \(asset) is special-cased in EffectsEngine.playSound but carries no ⭐. \
                          If it animates the desktop, add it to SoundEffectMap.playPathVisuals; \
                          if it only changes the audio, add it to `soundOnly` in this test.
                          """)
        }
    }

    /// The other direction, which is how the saw would have been caught: a star
    /// for an effect that was removed. Every hand-listed play-path visual must
    /// still be special-cased in `playSound` — nothing else starts them.
    func testEveryPlayPathVisualIsStillSpecialCasedInPlaySound() throws {
        let swift = try source("Sources/VictorEffects/EffectsEngine.swift")
        let play = try body(of: "func playSound(_ name: String, volumePct: Int?) -> String? {", in: swift)
        for asset in SoundEffectMap.playPathVisuals {
            XCTAssertTrue(play.contains("\"\(asset)\""),
                          "\(asset) is listed as a play-path visual but playSound no longer mentions it — stale ⭐")
        }
    }

    /// `playPathVisuals` exists only for effects the map cannot express. One
    /// that ALSO sits in `onPress` would fire twice — the very thing the
    /// comments in both files warn about.
    func testPlayPathVisualsAndOnPressDoNotOverlap() {
        let overlap = SoundEffectMap.playPathVisuals.intersection(SoundEffectMap.onPress.keys)
        XCTAssertTrue(overlap.isEmpty, "\(overlap.sorted()) are in BOTH onPress and playPathVisuals — double trigger")
    }

    // MARK: - The star must be on a tile that exists

    /// A renamed or deleted mp3 leaves an entry matching no tile: no star, no
    /// effect, no error. Checked against the real `tiles.json` when this machine
    /// has the tablet assets (the mp3s and the grid are not in this public repo),
    /// skipped otherwise so CI stays honest rather than green-by-omission.
    func testEveryStarredSoundIsARealTile() throws {
        let tilesJSON = EffectsConfig.shared.soundsDir.appendingPathComponent("tiles.json")
        guard let data = try? Data(contentsOf: tilesJSON),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tiles = obj["tiles"] as? [[String: Any]] else {
            throw XCTSkip("no tiles.json under soundsDir (\(tilesJSON.path)) — tablet assets not on this machine")
        }
        let assets = Set(tiles.compactMap { $0["asset"] as? String })
        XCTAssertGreaterThan(assets.count, 50, "tiles.json parsed but looks empty")

        for asset in SoundEffectMap.visualAssets {
            XCTAssertTrue(assets.contains(asset),
                          "\(asset) has an effect mapped but is not a tile in tiles.json — renamed or deleted mp3")
        }
    }
}
