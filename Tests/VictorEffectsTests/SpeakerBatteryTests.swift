import XCTest
@testable import VictorEffects

/// The JBL battery frames, as Victor's Go 4 sent them on 2026-10-29 in answer
/// to `AA 11 00`, and the choice of which speaker the tablet is shown.
final class SpeakerBatteryTests: XCTestCase {
    private func bytes(_ hex: String) -> [UInt8] {
        hex.split(separator: " ").map { UInt8($0, radix: 16)! }
    }

    func testGo4InfoBurstGivesBatteryAndMac() {
        var info: [UInt8: [UInt8]] = [:]
        for n in ["aa 12 04 00 42 20 e4", "aa 12 03 00 44 64", "aa 12 08 00 48 e8 26 cf c6 97 0b"] {
            info.merge(SpeakerBattery.parseInfo(bytes(n))) { _, new in new }
        }
        XCTAssertEqual(SpeakerBattery.battery(info)?.pct, 100)
        XCTAssertEqual(SpeakerBattery.battery(info)?.charging, false)
        XCTAssertEqual(SpeakerBattery.mac(info), "E8-26-CF-C6-97-0B")
    }

    func testTopBitIsCharging() {
        let b = SpeakerBattery.battery(SpeakerBattery.parseInfo(bytes("aa 12 03 00 44 ce")))
        XCTAssertEqual(b?.pct, 78)
        XCTAssertEqual(b?.charging, true)
    }

    func testSeveralFramesInOneNotification() {
        let info = SpeakerBattery.parseInfo(bytes("aa 12 03 00 43 01 aa 12 03 00 44 2a"))
        XCTAssertEqual(info[0x43], [0x01])
        XCTAssertEqual(SpeakerBattery.battery(info)?.pct, 42)
    }

    func testTruncatedFrameIsIgnored() {
        XCTAssertTrue(SpeakerBattery.parseInfo(bytes("aa 12 08 00 48 e8 26")).isEmpty)
    }

    func testMacFromCoreAudioUID() {
        XCTAssertEqual(SpeakerBattery.mac(fromUID: "E8-26-CF-C6-97-0B:output"), "E8-26-CF-C6-97-0B")
        XCTAssertNil(SpeakerBattery.mac(fromUID: "BuiltInSpeakerDevice"))
        XCTAssertNil(SpeakerBattery.mac(fromUID: "10ACF141-0000-0000-0F1F-010380351E78"))
    }

    private let a = "E8-26-CF-C6-97-0B", b = "E8-26-CF-C6-F3-69"
    private func r(_ pct: Int) -> SpeakerBattery.Reading { .init(pct: pct, charging: false, at: Date()) }

    func testDefaultOutputWins() {
        let got = SpeakerBattery.pick(readings: [a: r(80), b: r(20)], connectedMacs: [a, b], defaultMac: a)
        XCTAssertEqual(got?.pct, 80)
    }

    func testOtherwiseTheEmptiestConnectedOne() {
        let got = SpeakerBattery.pick(readings: [a: r(80), b: r(20)], connectedMacs: [a, b], defaultMac: nil)
        XCTAssertEqual(got?.pct, 20)
    }

    func testDisconnectedSpeakerIsNotShown() {
        XCTAssertNil(SpeakerBattery.pick(readings: [a: r(80)], connectedMacs: [b], defaultMac: nil))
    }

    func testStrangersAreVisitedOnceThenLeftAlone() {
        let mine = UUID(), stranger = UUID(), fresh = UUID()
        // Our speaker is identified: visit only it, never the known stranger nor unknowns.
        XCTAssertEqual(SpeakerBattery.toVisit(found: [mine, stranger, fresh],
                                              macById: [mine: a, stranger: "00-11-22-33-44-55"],
                                              connectedMacs: [a]), [mine])
        // A second speaker of ours is not identified yet: unknowns are worth one visit.
        XCTAssertEqual(SpeakerBattery.toVisit(found: [mine, stranger, fresh],
                                              macById: [mine: a, stranger: "00-11-22-33-44-55"],
                                              connectedMacs: [a, b]), [mine, fresh])
    }
}
