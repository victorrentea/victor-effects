import XCTest
@testable import VictorEffects

/// Which connected outputs the keep-alive holds awake. Names are this Mac's.
final class BluetoothKeepAliveTargetsTests: XCTestCase {
    private typealias Dev = BluetoothOutput.OutputDevice

    private func dev(_ name: String, bt: Bool = true, mic: Bool = false) -> Dev {
        Dev(id: 1, name: name, isBluetooth: bt, uid: "uid-\(name)", hasInput: mic)
    }

    func testBothBoxesAreHeldEvenIfOnlyOneIsTheDefault() {
        let names = BluetoothKeepAlive.targets(
            [dev("MacBook Pro Speakers", bt: false), dev("Victor's JBL Go 4"), dev("JBL")],
            match: "JBL").map(\.name)
        XCTAssertEqual(names, ["Victor's JBL Go 4", "JBL"])
    }

    /// A headset carries its HFP mic on the same CoreAudio device: the JBL
    /// headphones match the name and must still get no 30 Hz nudge.
    func testJBLHeadphonesAreNotHeld() {
        XCTAssertTrue(BluetoothKeepAlive.targets([dev("JBL TUNE500BT", mic: true)], match: "JBL").isEmpty)
    }

    func testWiredOrLoopbackDevicesAreNeverHeld() {
        XCTAssertTrue(BluetoothKeepAlive.targets([dev("JBL USB", bt: false)], match: "JBL").isEmpty)
    }

    func testNoNameConfiguredHoldsNothing() {
        XCTAssertTrue(BluetoothKeepAlive.targets([dev("Victor's JBL Go 4")], match: "").isEmpty)
    }
}
