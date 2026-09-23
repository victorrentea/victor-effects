import XCTest
@testable import VictorEffects

/// The ✅/⚪️/🚫 row is the keep-alive's only visible surface — the tone it
/// controls is inaudible by design — so the mapping from the three facts to the
/// three glyphs is the whole contract, and it is pure precisely so it can be
/// held to a table here without a speaker in the room.
final class BluetoothKeepAliveStateTests: XCTestCase {
    private typealias KA = BluetoothKeepAlive

    func testRunningOnlyWhenTheToneIsActuallyPlaying() {
        XCTAssertEqual(KA.state(enabled: true, configured: true, playing: true), .running)
        XCTAssertEqual(KA.state(enabled: true, configured: true, playing: false), .idle)
    }

    func testTheSwitchWinsOverEverythingElse() {
        // Off is off even mid-tone: the row's job on the way down is to say the
        // speaker is being left alone now, not at the next 30 s tick.
        XCTAssertEqual(KA.state(enabled: false, configured: true, playing: true), .off)
        XCTAssertEqual(KA.state(enabled: false, configured: false, playing: false), .off)
    }

    /// An empty `bluetoothSpeakerNameMatch` reads as `off`, never `idle`: idle
    /// promises "the moment a JBL becomes the output this starts", and with no
    /// name to match against, nothing ever will.
    func testNoSpeakerNameConfiguredReadsAsOffNotIdle() {
        XCTAssertEqual(KA.state(enabled: true, configured: false, playing: false), .off)
    }

    /// The row is a checkbox over the *switch*: armed-but-idle is still ticked.
    func testCheckmarkFollowsTheSwitchNotThePlayer() {
        XCTAssertEqual([KA.State.running, .idle, .off].map(\.isChecked), [true, true, false])
    }
}
