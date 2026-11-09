import AVFoundation
import CryptoKit
import XCTest
@testable import VictorEffects

/// ＋ A clip made louder on disk (`DiskBoosts`). The promises: each press is
/// 1.5 dB more, always rendered from the ORIGINAL (which is never touched), the
/// limiter holds −1 dBFS and says when it worked hard, reset gives the original
/// back, and the render is what the Mac plays.
final class DiskBoostsTests: XCTestCase {
    private var root: URL!
    private var boosts: DiskBoosts!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("diskboosts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        boosts = DiskBoosts(storage: root.appendingPathComponent("disk-boosts.json"),
                            dir: root.appendingPathComponent("boosted"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    /// A 4 s 1 kHz stereo sine at `amplitude`, as a 16-bit WAV.
    private func writeSine(_ name: String, amplitude: Float, seconds: Double = 4) throws -> URL {
        let url = root.appendingPathComponent(name)
        let rate = 44100.0
        let n = Int(seconds * rate)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 2, interleaved: false)!
        let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n))!
        buf.frameLength = AVAudioFrameCount(n)
        for c in 0..<2 { for i in 0..<n { buf.floatChannelData![c][i] = amplitude * Float(sin(2 * Double.pi * 1000 * Double(i) / rate)) } }
        let file = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: rate, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ], commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buf)
        return url
    }

    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func use(_ url: URL, key: String) {
        boosts.filesOf = { $0 == key ? [key] : [] }
        boosts.sourceOf = { $0 == key ? DiskBoosts.Source(key: key, name: key, url: url) : nil }
    }

    func testEachPressIsOneAndAHalfDecibelsMoreFromTheUntouchedOriginal() throws {
        let original = try writeSine("q.wav", amplitude: 0.1)
        let before = try sha(original)
        use(original, key: "q.wav")
        let m0 = try XCTUnwrap(try Loudness.maxShortTerm(of: original))

        XCTAssertTrue(boosts.press("q.wav"))
        XCTAssertTrue(boosts.isBusy("q.wav"))
        boosts.waitForRenders()
        XCTAssertFalse(boosts.isBusy("q.wav"))
        let first = try XCTUnwrap(boosts.renderURL(forFile: "q.wav"), "the Mac plays the render")
        XCTAssertEqual(try XCTUnwrap(try Loudness.maxShortTerm(of: first)) - m0, 1.5, accuracy: 0.05)

        boosts.press("q.wav")
        boosts.waitForRenders()
        let second = try XCTUnwrap(boosts.renderURL(forFile: "q.wav"))
        XCTAssertEqual(try XCTUnwrap(try Loudness.maxShortTerm(of: second)) - m0, 3.0, accuracy: 0.05)
        XCTAssertTrue(second.lastPathComponent.contains("+3.0dB"), "rendered at the total, from the original")
        XCTAssertFalse(FileManager.default.fileExists(atPath: first.path), "the superseded render is gone")
        XCTAssertEqual(try sha(original), before, "the original is never written")
        XCTAssertEqual(boosts.tabletFile("q.wav"), second)
    }

    func testTheLimiterHoldsMinusOneDBFSAndSaysWhenItWorkedHard() throws {
        let original = try writeSine("loud.wav", amplitude: 0.8)
        use(original, key: "loud.wav")
        for _ in 0..<4 { boosts.press("loud.wav") }      // +6 dB on a −2 dBFS sine
        boosts.waitForRenders()
        let render = try XCTUnwrap(boosts.renderURL(forFile: "loud.wav"))
        let pcm = try XCTUnwrap(try Loudness.decode(render))
        let peak = pcm.channels.flatMap { $0 }.map(abs).max()!
        XCTAssertLessThanOrEqual(peak, DiskBoosts.ceiling + 0.001)
        XCTAssertTrue(boosts.jsonFields.contains("\"limited\":true"), boosts.jsonFields)
    }

    func testResetGivesTheOriginalBack() throws {
        let original = try writeSine("r.wav", amplitude: 0.1)
        use(original, key: "r.wav")
        boosts.press("r.wav")
        boosts.waitForRenders()
        let render = try XCTUnwrap(boosts.renderURL(forFile: "r.wav"))
        boosts.reset("r.wav")
        XCTAssertNil(boosts.renderURL(forFile: "r.wav"), "the original plays again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: render.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertEqual(boosts.boostDb("r.wav"), 0)
    }

    func testAPressOnSomethingUnknownDoesNothing() {
        boosts.filesOf = { _ in [] }
        XCTAssertFalse(boosts.press("nope.mp3"))
        XCTAssertEqual(boosts.boostDb("nope.mp3"), 0)
    }

    func testAVideoRenderIsTheWindowOnly() throws {
        let original = try writeSine("v.wav", amplitude: 0.1, seconds: 6)
        boosts.filesOf = { $0 == "video:v" ? ["video:v"] : [] }
        boosts.sourceOf = { $0 == "video:v" ? DiskBoosts.Source(key: "video:v", name: "v.wav", url: original, start: 2, end: 5) : nil }
        boosts.press("video:v")
        boosts.waitForRenders()
        let r = try XCTUnwrap(boosts.renders("video:v").values.first)
        let pcm = try XCTUnwrap(try Loudness.decode(r))
        XCTAssertEqual(Double(pcm.channels[0].count) / pcm.sampleRate, 3, accuracy: 0.01)
        XCTAssertTrue(boosts.infoJSON("video:v").contains("\"start\":2"), boosts.infoJSON("video:v"))
    }

    func testTheBoostIsRememberedAcrossARelaunch() throws {
        let original = try writeSine("p.wav", amplitude: 0.1)
        use(original, key: "p.wav")
        boosts.press("p.wav")
        boosts.waitForRenders()
        let again = DiskBoosts(storage: boosts.storageURL, dir: boosts.dir)
        again.filesOf = boosts.filesOf
        again.sourceOf = boosts.sourceOf
        XCTAssertEqual(again.boostDb("p.wav"), 1.5)
        XCTAssertNotNil(again.renderURL(forFile: "p.wav"))
    }

    /// Two tiles heard as one file (the gong: #31 and #50) share ONE boost, and a
    /// tile alternating between two takes (#19) raises both.
    func testABoostIsPerFileSoSharedFilesMoveTogetherAndPairsBothRise() throws {
        let gong = try writeSine("gong.wav", amplitude: 0.1), a = try writeSine("a.wav", amplitude: 0.1),
            b = try writeSine("b.wav", amplitude: 0.1)
        let urls = ["gong.wav": gong, "a.wav": a, "b.wav": b]
        boosts.filesOf = { ["31": ["gong.wav"], "50": ["gong.wav"], "19": ["a.wav", "b.wav"]][$0] ?? [] }
        boosts.sourceOf = { k in urls[k].map { DiskBoosts.Source(key: k, name: k, url: $0) } }
        boosts.press("31")
        boosts.press("19")
        boosts.waitForRenders()
        XCTAssertEqual(boosts.boostDb("50"), 1.5, "a ＋ on #31 is heard on #50")
        XCTAssertNotNil(boosts.renderURL(forFile: "a.wav"))
        XCTAssertNotNil(boosts.renderURL(forFile: "b.wav"))
        XCTAssertTrue(boosts.jsonFields(tiles: ["31", "50", "19"]).contains("\"50\":{\"db\":1.5"))
        XCTAssertNil(boosts.tabletFile("31"), "the tablet plays #31's own mp3, which is not boosted")
    }

    func testTheRoutesParse() {
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/boost/01_baby.mp3/up"), .soundBoostUp("01_baby.mp3"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/boost/video:abc/reset"), .soundBoostReset("video:abc"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/boost/01_baby.mp3/file"), .soundBoostFile("01_baby.mp3"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/boost/video:abc"), .soundBoostInfo("video:abc"))
        XCTAssertEqual(EffectsRouter.route(forPath: "/sound/boost/x/sideways"), .unknown)
    }
}
