import XCTest
@testable import VictorEffects

/// 🎚️ The ceiling: an effect's loudness ≤ the voice + offset, only ever lower.
final class VoiceCeilingTests: XCTestCase {
    override func tearDown() {
        VoiceCeiling.receive(sharing: false, ref: nil, source: "")
        VoiceCeiling.fileLoudness = [:]
        super.tearDown()
    }

    /// A clip at −11 LUFS, voice −24, offset −3 → it may reach −27: 16 dB down.
    func testMaxVolumeIsTheDistanceToTheVoice() {
        let v = VoiceCeiling.maxVolume(clipLufs: -11, voiceRef: -24, offset: -3)
        XCTAssertEqual(20 * log10(Double(v)), -16, accuracy: 0.01)
        // The macOS volume on Zoom's share device already takes 6 dB off: 10 left.
        let withSys = VoiceCeiling.maxVolume(clipLufs: -11, voiceRef: -24, offset: -3, systemDb: -6)
        XCTAssertEqual(20 * log10(Double(withSys)), -10, accuracy: 0.01)
    }

    /// The tile bar and the blue wedge are already in the asked volume:
    /// clip −11 at vol 0.5 (−6 dB) is a −17 clip, so the cut is 10 dB, not 16.
    func testCapCountsTheGainsAlreadyApplied() {
        let r = VoiceCeiling.capped(0.5, clipLufs: -11, voiceRef: -24, offset: -3)
        XCTAssertEqual(r.takenDb, 20 * log10(0.5) + 16, accuracy: 0.01)
        XCTAssertEqual(-11 + 20 * log10(Double(r.volume)), -27, accuracy: 0.01)
    }

    /// Only ever lower: a clip already under the voice keeps its own level, and
    /// a quiet one is never raised to meet it.
    func testNeverRaises() {
        for asked: Float in [0, 0.05, 0.3, 0.7, 1] {
            for clip in stride(from: -50.0, through: 0, by: 2.5) {
                let r = VoiceCeiling.capped(asked, clipLufs: clip, voiceRef: -24, offset: -3)
                XCTAssertLessThanOrEqual(r.volume, asked)
                XCTAssertGreaterThanOrEqual(r.takenDb, 0)
            }
        }
        let quiet = VoiceCeiling.capped(0.8, clipLufs: -40, voiceRef: -24, offset: -3)
        XCTAssertEqual(quiet.volume, 0.8)
        XCTAssertEqual(quiet.takenDb, 0)
        XCTAssertEqual(VoiceCeiling.maxVolume(clipLufs: -60, voiceRef: -24, offset: 6), 1)
    }

    func testClampOnlyWhileSharing() {
        let url = URL(fileURLWithPath: "/tmp/voice-ceiling-test/03_explosion.mp3")
        VoiceCeiling.fileLoudness = [VoiceCeiling.key(url): -8.0]
        XCTAssertEqual(VoiceCeiling.clamp(0.9, url: url, log: false), 0.9)          // no share
        VoiceCeiling.receive(sharing: true, ref: -24, source: "test")
        XCTAssertTrue(VoiceCeiling.active)
        let offset = EffectsConfig.shared.voiceCeilingOffsetDb
        let expected = min(0.9, pow(10, (-24 + offset + 8 - VoiceCeiling.systemDb()) / 20))
        XCTAssertEqual(Double(VoiceCeiling.clamp(0.9, url: url, log: false)), expected, accuracy: 0.0001)
        // A silent file is never too loud; an unmeasured one is assumed −10 LUFS.
        let silent = URL(fileURLWithPath: "/tmp/voice-ceiling-test/34_phoenix.mp3")
        VoiceCeiling.fileLoudness[VoiceCeiling.key(silent)] = .some(nil)
        XCTAssertEqual(VoiceCeiling.clamp(0.9, url: silent, log: false), 0.9)
        let unknown = URL(fileURLWithPath: "/tmp/voice-ceiling-test/never-measured.mp3")
        XCTAssertEqual(VoiceCeiling.loudness(of: unknown).lufs, VoiceCeiling.unmeasuredLufs)
        XCTAssertFalse(VoiceCeiling.loudness(of: unknown).measured)
        VoiceCeiling.receive(sharing: false, ref: nil, source: "")
        XCTAssertFalse(VoiceCeiling.active)
        XCTAssertEqual(VoiceCeiling.clamp(0.9, url: url, log: false), 0.9)
    }

    func testRoutesParse() {
        XCTAssertEqual(EffectsRouter.route(forPath: "/voice/ref?sharing=1&ref=-24.50&src=live"),
                       .voiceRef(sharing: true, ref: -24.5, source: "live"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/voice/ref?sharing=0"),
                       .voiceRef(sharing: false, ref: nil, source: ""))
        XCTAssertEqual(EffectsRouter.route(forPath: "/voice/ceiling?key=video:mortal&volume=0.5"),
                       .voiceCeiling(key: "video:mortal", file: nil, volume: 0.5))
    }

    func testOffsetIsConfigurable() {
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: nil).voiceCeilingOffsetDb, -3)
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: Data("{\"voiceCeilingOffsetDb\": -6}".utf8)).voiceCeilingOffsetDb, -6)
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: Data("{\"voiceCeilingOffsetDb\": 99}".utf8)).voiceCeilingOffsetDb, -3)
    }

    /// Every player goes through the ceiling, including one nobody gave a level.
    func testThePlayerFactoryBuildsCeilingPlayers() throws {
        let src = try String(contentsOfFile: #filePath.replacingOccurrences(of: "Tests/VictorEffectsTests/VoiceCeilingTests.swift",
                                                                            with: "Sources/VictorEffects/SoundManager.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("return try CeilingPlayer(contentsOf: url)"))
        XCTAssertFalse(src.contains("return try AVAudioPlayer(contentsOf: url)"))
    }
}
