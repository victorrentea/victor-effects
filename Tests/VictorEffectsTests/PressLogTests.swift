import XCTest
@testable import VictorEffects

final class PressLogTests: XCTestCase {
    private let doc = TilesDocument(columns: 13, tiles: [
        Tile(n: 53, asset: "53_money.mp3", image: "a.jpg",
             under: Tile(n: 53, asset: "53b_7_rings.mp3", image: "b.jpg")),
        Tile(n: 1, asset: "01_baby.mp3", image: "c.jpg"),
    ])

    func testResolvesLayerAAndLayerB() {
        XCTAssertTrue(PressLog.resolve("01_baby.mp3", in: doc) == (1, "a"))
        XCTAssertTrue(PressLog.resolve("53_money.mp3", in: doc) == (53, "a"))
        XCTAssertTrue(PressLog.resolve("53b_7_rings.mp3", in: doc) == (53, "b"))
        XCTAssertNil(PressLog.resolve("nope.mp3", in: doc).n)
        XCTAssertNil(PressLog.resolve("nope.mp3", in: nil).layer)
    }

    func testLineFormatIsExact() {
        let line = PressLog.format(ts: Date(timeIntervalSince1970: 1_700_000_000.123),
                                   file: "53b_7_rings.mp3", n: 53, layer: "b", source: .tablet)
        let pattern = #"^\{"ts":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}[+-]\d\d:\d\d","file":"53b_7_rings\.mp3","n":53,"layer":"b","source":"tablet"\}$"#
        XCTAssertNotNil(line.range(of: pattern, options: .regularExpression), line)
        let off = PressLog.format(ts: Date(), file: "x\".mp3", n: nil, layer: nil, source: .other)
        XCTAssertTrue(off.hasSuffix(#""file":"x\".mp3","n":null,"layer":null,"source":"other"}"#), off)
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(off.utf8)))
    }

    func testAppendWritesOneLinePerPressToFile() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("presses-\(UUID().uuidString).jsonl")
        PressLog.overrideURL = url
        defer { PressLog.overrideURL = nil; try? FileManager.default.removeItem(at: url) }
        PressLog.append(file: "a.mp3", source: .panel)
        PressLog.append(file: "b.mp3", source: .tablet)
        PressLog.flush()
        let lines = ((try? String(contentsOf: url)) ?? "").split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("\"source\":\"panel\""))
    }

    func testConfigKeyAndEnvOverride() {
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: nil).pressLogFile, "~/.victor-effects/presses.jsonl")
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: Data(#"{"pressLogFile":"/x"}"#.utf8)).pressLogFile, "/x")
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: Data(#"{"pressLogFile":"/x"}"#.utf8),
                                                 env: ["VICTOR_EFFECTS_PRESS_LOG": "/y"]).pressLogFile, "/y")
    }

    func testRouteParses() {
        XCTAssertEqual(EffectsRouter.route(forPath: "/sounds/captions"), .soundsCaptions)
    }
}

final class CaptionsExportTests: XCTestCase {
    private let silentAsset = "-.mp3" // no words: caption(for:) is nil whatever the silent list holds

    func testBuildMatchesScheduleAndSilentIsEmpty() throws {
        let doc = TilesDocument(columns: 13, tiles: [
            Tile(n: 1, asset: "01_baby.mp3", image: "a.jpg",
                 under: Tile(n: 1, asset: silentAsset, image: "b.jpg")),
        ])
        XCTAssertEqual(CaptionsExport.assets(in: doc), ["01_baby.mp3", silentAsset])
        let out = CaptionsExport.build(assets: CaptionsExport.assets(in: doc)) { _ in 4.0 }
        let baby = try XCTUnwrap(out["01_baby.mp3"] as? [String: Any])
        XCTAssertEqual(baby["durationSeconds"] as? Double, 4.0)
        let expected = SoundCaptions.schedule(for: "01_baby.mp3", clipSeconds: 4.0)
        let cues = try XCTUnwrap(baby["cues"] as? [[String: Any]])
        XCTAssertEqual(cues.count, expected.count)
        XCTAssertEqual(cues.first?["start"] as? Double, expected.first?.at)
        XCTAssertEqual(cues.first?["end"] as? Double, expected.first.map { $0.at + $0.seconds })
        XCTAssertEqual(cues.first?["text"] as? String, expected.first?.text)
        let silent = try XCTUnwrap(out[silentAsset] as? [String: Any])
        XCTAssertNil(SoundCaptions.caption(for: silentAsset))
        XCTAssertEqual((silent["cues"] as? [Any])?.count, 0)
        print("CAPTIONS-SAMPLE", CaptionsExport.json(out))
    }
}
