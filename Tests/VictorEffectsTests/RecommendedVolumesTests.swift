import Foundation
import XCTest
@testable import VictorEffects

/// 🔺 The ▲ on the tablet's per-tile volume bar (`RecommendedVolumes`).
///
/// Three promises: the FORMULA (a clip at the mean sits on the tick, +4 dB
/// louder sits at ~64), the MEASUREMENT (BS.1770 short-term loudness, calibrated
/// on a sine and cross-checked against ffmpeg's `ebur128`), and COVERAGE — every
/// tile in the live `tiles.json` and every snippet in the live `videos.json` gets
/// a measurement, so a clip added tomorrow cannot silently go without its ▲.
final class RecommendedVolumesTests: XCTestCase {

    // MARK: - Formula

    func testAClipAtTheMeanSitsOnTheTick() {
        XCTAssertEqual(RecommendedVolumes.position(max: -12, reference: -12), 80)
    }

    func testFourDecibelsLouderIsTurnedDownToAbout64() {
        // (p/80)² in amplitude: 80 × 10^(−4/40) = 63.5
        XCTAssertEqual(RecommendedVolumes.position(max: -8, reference: -12), 64)
        XCTAssertEqual(RecommendedVolumes.position(max: -16, reference: -12), 101)
    }

    func testTheGainAtTheRecommendationUndoesTheDifference() {
        // Down only: the ▲ exists for louder clips, whose position is under 80.
        for diff in stride(from: 0.0, through: 9.0, by: 1.5) {
            let p = 80 * pow(10, -diff / 40)
            let gainDb = 20 * log10(Double(SoundGains.gain(position: Int(p.rounded()))))
            XCTAssertEqual(gainDb, -diff, accuracy: 0.15, "clip \(diff) dB off the mean")
        }
    }

    func testPositionIsUnclampedAboveTheBarButNeverNegative() {
        XCTAssertEqual(RecommendedVolumes.position(max: -40, reference: -10), 450)
        XCTAssertEqual(RecommendedVolumes.position(max: 100, reference: -10), 0)
    }

    func testTheReferenceIsThePlainMean() {
        XCTAssertEqual(RecommendedVolumes.reference([-10, -12, -17])!, -13, accuracy: 1e-9)
        XCTAssertNil(RecommendedVolumes.reference([]))
    }

    func testLouderClipsGetATriangleQuieterOnesAPlusAndSilentOnesNothing() {
        let t = RecommendedVolumes.table([
            "a.mp3": .loudness(-10), "b.mp3": .loudness(-14), "c.mp3": .loudness(-12.2), "video:x": .silent,
        ])
        XCTAssertEqual(t.reference!, -12.0667, accuracy: 1e-3)
        XCTAssertEqual(t.positions, ["a.mp3": 71], "▲ only below the tick, for the louder clip")
        XCTAssertEqual(t.boosts, ["b.mp3": 1.5], "2 dB short → one 1.5 dB press")
        XCTAssertNil(t.positions["c.mp3"]); XCTAssertNil(t.boosts["c.mp3"], "0.13 dB short rounds to no press")
    }

    func testTheReferenceIsTheOriginalsButTheClipIsJudgedAsItPlaysNow() {
        // b was 4 dB under; after +3 dB on disk it is 1 dB under: R does not move.
        let t = RecommendedVolumes.table(["a.mp3": .loudness(-10), "b.mp3": .loudness(-14)],
                                         current: ["b.mp3": .loudness(-11)])
        XCTAssertEqual(t.reference!, -12, accuracy: 1e-9)
        XCTAssertEqual(t.positions["b.mp3"], 76, "now LOUDER than R: turn it down a touch")
        XCTAssertNil(t.boosts["b.mp3"])
    }

    func testWholePressesOnly() {
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -15, reference: -12), 3)
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -14.0, reference: -12), 1.5)
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -14.4, reference: -12), 3, "2.4 dB is closer to two presses")
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -12.5, reference: -12), 0)
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -10, reference: -12), 0)
        XCTAssertEqual(RecommendedVolumes.boostDb(max: -40, reference: -12), DiskBoosts.maxDb, "no more than the ＋ gives")
    }

    func testTheRainTrimIsCounted() {
        XCTAssertEqual(RecommendedVolumes.fileTrimDb(RainStorm.soundName), 20 * log10(0.5), accuracy: 1e-6)
        XCTAssertEqual(RecommendedVolumes.fileTrimDb("01_baby.mp3"), 0)
    }

    func testGainsBodyCarriesTheRecommendationsAndTheirHash() {
        let before = SoundGains.publicHash
        RecommendedVolumes.useForTesting(.init(maxima: ["01_baby.mp3": -9], reference: -12,
                                               positions: ["01_baby.mp3": 67, "video:abc": 95]))
        defer { RecommendedVolumes.useForTesting(.init()) }
        let body = SoundGains.responseJSON
        XCTAssertTrue(body.contains("\"recommended\":{\"01_baby.mp3\":67,\"video:abc\":95}"), body)
        XCTAssertTrue(body.contains("\"boosts\":{"), body)
        XCTAssertTrue(body.contains("\"hash\":\"\(SoundGains.publicHash)\""))
        XCTAssertNotEqual(SoundGains.publicHash, before)
        let obj = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any]
        XCTAssertNotNil(obj?["gains"] as? [String: Any], "the tablet's parser reads `gains`")
    }

    // MARK: - Measurement

    private func sine(_ seconds: Double, rate: Double, amplitude: Float, hz: Double = 1000) -> [Float] {
        (0..<Int(seconds * rate)).map { amplitude * Float(sin(2 * Double.pi * hz * Double($0) / rate)) }
    }

    func testAFullScaleSineOnBothChannelsIsZeroLUFS() {
        for rate in [44100.0, 48000.0] {
            let s = sine(10, rate: rate, amplitude: 1)
            XCTAssertEqual(Loudness.maxShortTerm(channels: [s, s], sampleRate: rate)!, 0, accuracy: 0.05, "\(rate)")
        }
    }

    func testMonoCountsAsDualMono() {
        let s = sine(10, rate: 44100, amplitude: 0.5)
        XCTAssertEqual(Loudness.maxShortTerm(channels: [s], sampleRate: 44100)!, -6.02, accuracy: 0.05)
    }

    func testAClipShorterThanTheWindowIsMeasuredOverItsOwnLength() {
        let s = sine(1, rate: 48000, amplitude: 1)
        XCTAssertEqual(Loudness.maxShortTerm(channels: [s, s], sampleRate: 48000)!, 0, accuracy: 0.05, "not padded with silence")
    }

    func testTheLoudestThreeSecondsWin() {
        let quiet = sine(5, rate: 48000, amplitude: 0.1), loud = sine(3, rate: 48000, amplitude: 1)
        let s = quiet + loud + quiet
        XCTAssertEqual(Loudness.maxShortTerm(channels: [s, s], sampleRate: 48000)!, 0, accuracy: 0.1)
    }

    func testSilenceHasNoLoudness() {
        XCTAssertNil(Loudness.maxShortTerm(channels: [[Float](repeating: 0, count: 48000 * 4)], sampleRate: 48000))
    }

    // MARK: - The live folders

    private var videosDir: URL {
        if let d = EffectsConfig.shared.videosDir { return d }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("victor-macos-addons/videos")
    }

    /// Clips with nothing to hear, on purpose: #34's mp3 is a placeholder (the
    /// effect plays the cry), two snippets have no audio track and one a silent one. They get no
    /// hint and stay out of the mean.
    static let silentByDesign: Set<String> = ["34_phoenix.mp3", "video:slopGrenade", "video:npmInstall", "video:seniorDev"]

    /// Every tile and every video snippet is measured — a decode failure or a
    /// clip the inputs forgot fails the build, with its name.
    func testEveryTileAndEveryVideoHasAMeasurement() throws {
        try XCTSkipUnless(EffectsConfig.shared.soundsDirExists, "tablet sounds not on this machine")
        let soundsDir = EffectsConfig.shared.soundsDir
        let tilesData = try XCTUnwrap(FileManager.default.contents(atPath: soundsDir.appendingPathComponent("tiles.json").path))
        let tiles = try XCTUnwrap(TilesManifest.parse(tilesData)).tiles
        var clips = RecommendedVolumes.soundClips(tiles: tiles, soundsDir: soundsDir)
        var expected = Set(tiles.flatMap { [$0.asset] + ($0.under.map { [$0.asset] } ?? []) })
        var videoKeys = Set<String>()
        if let data = FileManager.default.contents(atPath: videosDir.appendingPathComponent("videos.json").path) {
            let v = RecommendedVolumes.videoClips(manifest: data, videosDir: videosDir)
            XCTAssertFalse(v.isEmpty, "videos.json did not parse")
            clips += v
            videoKeys = Set(v.map(\.key))
            expected.formUnion(videoKeys)
        }
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("victor-effects-loudness-test-cache.json")
        let results = RecommendedVolumes.measure(clips, cacheFile: cache)
        XCTAssertEqual(Set(results.keys), expected)
        for (key, r) in results.sorted(by: { $0.key < $1.key }) {
            switch r {
            case .failed(let why): XCTFail("\(key) could not be measured: \(why)")
            case .silent:
                XCTAssertTrue(Self.silentByDesign.contains(key),
                              "\(key) is silent: if that is deliberate, add it to `silentByDesign`")
            case .loudness(let m):
                XCTAssertTrue(m.isFinite && m > -70 && m < 6, "\(key): \(m) LUFS is not a clip's loudness")
            }
        }
        let table = RecommendedVolumes.table(results)
        let r = try XCTUnwrap(table.reference)
        XCTAssertEqual(Set(table.maxima.keys), Set(results.filter { $0.value != .silent }.keys), "every sounding clip is in R")
        for (key, m) in table.maxima {
            if let p = table.positions[key] { XCTAssertTrue(m > r && p < 80, key) }
            if let b = table.boosts[key] { XCTAssertTrue(m < r && b >= DiskBoosts.stepDb, key) }
            if m > r + 0.2 { XCTAssertNotNil(table.positions[key], "\(key) is louder than R and has no ▲") }
            if m < r - 0.75 { XCTAssertNotNil(table.boosts[key], "\(key) is quieter than R and has no ＋") }
        }
        // The table, for whoever is looking at the test log.
        let lines = table.maxima.sorted { $0.value > $1.value }
            .map { String(format: "%-34@ M=%7.2f  ▲=%@  ＋=%@", $0.key as NSString, $0.value,
                          (table.positions[$0.key].map { "\($0)" } ?? "-") as NSString,
                          (table.boosts[$0.key].map { "\($0)" } ?? "-") as NSString) }
        print("🔺 R = \(table.reference ?? .nan) LUFS over \(table.maxima.count) clips\n" + lines.joined(separator: "\n"))
    }

    /// Our short-term meter against ffmpeg's `ebur128` on real clips of 3 s or
    /// more (ffmpeg prints no `S` for a shorter one): a mono and a stereo sound,
    /// long ones, and a video window.
    func testAgreesWithFfmpegWithinHalfALU() throws {
        let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { FileManager.default.isExecutableFile(atPath: $0) }
        try XCTSkipIf(ffmpeg == nil, "no ffmpeg")
        try XCTSkipUnless(EffectsConfig.shared.soundsDirExists, "tablet sounds not on this machine")
        let sounds = EffectsConfig.shared.soundsDir
        var cases: [(URL, Double, Double?)] = ["01_baby.mp3", "03_explosion.mp3", "50_gong.mp3", "14_universal.mp3", "11_fire.mp3"]
            .map { (sounds.appendingPathComponent($0), 0, nil) }
            .filter { FileManager.default.fileExists(atPath: $0.0.path) }
        let video = videosDir.appendingPathComponent("KD_1Z8iUDho.mp4")
        if FileManager.default.fileExists(atPath: video.path) { cases.append((video, 145, 205)) }
        XCTAssertFalse(cases.isEmpty)
        for (url, start, end) in cases {
            let ours = try XCTUnwrap(try Loudness.maxShortTerm(of: url, start: start, end: end))
            let theirs = try XCTUnwrap(ffmpegMaxShortTerm(ffmpeg!, url, start: start, end: end))
            XCTAssertEqual(ours, theirs, accuracy: 0.5, url.lastPathComponent)
            print(String(format: "🔺 %@: ours %.2f, ffmpeg %.2f LUFS", url.lastPathComponent, ours, theirs))
        }
    }

    private func ffmpegMaxShortTerm(_ ffmpeg: String, _ url: URL, start: Double, end: Double?) throws -> Double? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        var args = ["-nostats", "-hide_banner", "-ss", "\(start)"]
        if let end { args += ["-t", "\(end - start)"] }
        args += ["-i", url.path, "-vn", "-af", "ebur128=framelog=info:dualmono=true", "-f", "null", "-"]
        p.arguments = args
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var best: Double?
        for line in text.split(separator: "\n") where line.contains(" S:") {
            guard let r = line.range(of: " S:") else { continue }
            let rest = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
            if let v = Double(rest.split(separator: " ").first ?? ""), v > -100 { best = max(best ?? -.infinity, v) }
        }
        return best
    }
}
