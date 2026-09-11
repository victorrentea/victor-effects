import XCTest
@testable import VictorEffects

final class EffectsConfigTests: XCTestCase {
    private func parse(_ json: String, env: [String: String] = [:]) -> EffectsConfigValues {
        EffectsConfigValues.parse(jsonData: json.data(using: .utf8), env: env)
    }

    func testDefaultsWhenNoFile() {
        let v = EffectsConfigValues.parse(jsonData: nil, env: [:])
        XCTAssertEqual(v.port, 55124)
        XCTAssertEqual(v.soundsDir, "~/.victor-effects/sounds")
        XCTAssertEqual(v.assetsDir, "~/.victor-effects/assets")
        XCTAssertEqual(v.eventWebhook, "")
        // Empty on purpose: the keep-alive must stay off for anyone who did not
        // ask for it by naming their speaker.
        XCTAssertEqual(v.bluetoothSpeakerNameMatch, "")
        XCTAssertEqual(v.overlayScreen, "builtin")
        XCTAssertEqual(v.chargeEmoji, ["☕"])
    }

    func testFullFileIsRead() {
        let v = parse("""
        {"port":55999,"soundsDir":"/tmp/s","assetsDir":"/tmp/a",
         "eventWebhook":"http://127.0.0.1:1/e","bluetoothSpeakerNameMatch":"SPK",
         "overlayScreen":"main","chargeEmoji":["☕","🍺"]}
        """)
        XCTAssertEqual(v.port, 55999)
        XCTAssertEqual(v.soundsDir, "/tmp/s")
        XCTAssertEqual(v.assetsDir, "/tmp/a")
        XCTAssertEqual(v.eventWebhook, "http://127.0.0.1:1/e")
        XCTAssertEqual(v.bluetoothSpeakerNameMatch, "SPK")
        XCTAssertEqual(v.overlayScreen, "main")
        XCTAssertEqual(v.chargeEmoji, ["☕", "🍺"])
    }

    func testPartialFileKeepsDefaultsForTheRest() {
        let v = parse(#"{"soundsDir":"/tmp/only"}"#)
        XCTAssertEqual(v.soundsDir, "/tmp/only")
        XCTAssertEqual(v.port, 55124)
        XCTAssertEqual(v.overlayScreen, "builtin")
    }

    func testGarbageFileFallsBackToDefaults() {
        let v = parse("not json at all")
        XCTAssertEqual(v.port, 55124)
        XCTAssertEqual(v.soundsDir, "~/.victor-effects/sounds")
    }

    func testEnvironmentWinsOverFile() {
        let v = parse(#"{"port":55999,"soundsDir":"/tmp/from-file"}"#,
                      env: ["VICTOR_EFFECTS_PORT": "55001",
                            "VICTOR_EFFECTS_SOUNDS_DIR": "/tmp/from-env"])
        XCTAssertEqual(v.port, 55001)
        XCTAssertEqual(v.soundsDir, "/tmp/from-env")
    }

    func testNonsensePortIsIgnored() {
        XCTAssertEqual(parse(#"{"port":0}"#).port, 55124)
        XCTAssertEqual(parse(#"{"port":99999}"#).port, 55124)
        XCTAssertEqual(parse(#"{"port":55124}"#, env: ["VICTOR_EFFECTS_PORT": "abc"]).port, 55124)
    }

    func testEmptyChargeEmojiListIsIgnored() {
        // An empty list would silently disable the ☕ gesture with no way to tell
        // it apart from a typo, so it falls back to the default.
        XCTAssertEqual(parse(#"{"chargeEmoji":[]}"#).chargeEmoji, ["☕"])
    }

    func testTildeExpansion() {
        let expanded = EffectsConfig.expand("~/x")
        XCTAssertFalse(expanded.hasPrefix("~"))
        XCTAssertTrue(expanded.hasSuffix("/x"))
        XCTAssertEqual(EffectsConfig.expand("/abs/path"), "/abs/path")
    }
}
