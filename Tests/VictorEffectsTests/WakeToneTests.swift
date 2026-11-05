import XCTest
@testable import VictorEffects

/// The tone that warms the Bluetooth link plays before every sound, so it has
/// to stay where a palm-sized speaker cannot voice it: at 220 Hz the same level
/// was an audible buzz (`docs/sound-routing.md`).
final class WakeToneTests: XCTestCase {
    private func samples(_ wav: Data) -> [Int16] {
        let pcm = wav.dropFirst(44)
        return stride(from: pcm.startIndex, to: pcm.endIndex - 1, by: 2).map {
            Int16(littleEndian: Int16(bitPattern: UInt16(pcm[$0]) | UInt16(pcm[$0 + 1]) << 8))
        }
    }

    func testPitchIsTheNudgesThirtyHertz() {
        let s = samples(BluetoothOutput.makeSilentToneWav(seconds: 1.0))
        let rising = zip(s, s.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        XCTAssertEqual(rising, 30, accuracy: 1)
    }

    func testLevelStaysAtMinus56dBFS() {
        let s = samples(BluetoothOutput.makeSilentToneWav(seconds: 1.0))
        let peak = Double(s.map { abs(Int($0)) }.max() ?? 0) / 32767
        XCTAssertEqual(20 * log10(peak), -56.5, accuracy: 0.5)
    }

    func testAWakeShorterThanItsFadesStillBuilds() {
        XCTAssertFalse(samples(BluetoothOutput.makeSilentToneWav(seconds: 0.03)).isEmpty)
    }
}
