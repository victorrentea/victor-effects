import XCTest
@testable import VictorEffects

final class VoiceRecorderTests: XCTestCase {
    func testClockCountsMinutesThenHours() {
        XCTAssertEqual(VoiceRecorder.clock(0), "0:00")
        XCTAssertEqual(VoiceRecorder.clock(65.9), "1:05")
        XCTAssertEqual(VoiceRecorder.clock(3725), "1:02:05")
        XCTAssertEqual(VoiceRecorder.clock(-3), "0:00")
    }

    func testFileNameSortsByTimeAndHasNoColons() {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 12; c.hour = 9; c.minute = 5; c.second = 7
        let date = Calendar.current.date(from: c)!
        XCTAssertEqual(VoiceRecorder.fileName(for: date), "Voice 2026-11-12 09.05.07.m4a")
    }

    func testRecordingsDirIsConfigurable() {
        let v = EffectsConfigValues.parse(jsonData: Data(#"{"recordingsDir":"/x/rec"}"#.utf8))
        XCTAssertEqual(v.recordingsDir, "/x/rec")
    }
}
