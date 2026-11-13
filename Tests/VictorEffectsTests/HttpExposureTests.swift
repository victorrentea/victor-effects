import XCTest
@testable import VictorEffects

/// The HTTP surface has no password, so two things must hold: it is not offered
/// to the network unless asked, and a request cannot name a file outside the
/// sound folders.
final class HttpExposureTests: XCTestCase {
    func testLanAccessIsOffUnlessTheConfigAsks() {
        XCTAssertFalse(EffectsConfigValues.parse(jsonData: nil, env: [:]).lanAccess)
        let on = EffectsConfigValues.parse(jsonData: Data(#"{"lanAccess":true}"#.utf8), env: [:])
        XCTAssertTrue(on.lanAccess)
    }

    func testSoundNamesCannotClimbOutOfTheFolder() {
        XCTAssertTrue(SoundManager.isContainedName("gong.mp3"))
        XCTAssertTrue(SoundManager.isContainedName("pack/gong.mp3"))
        XCTAssertFalse(SoundManager.isContainedName("../../Documents/meeting.m4a"))
        XCTAssertFalse(SoundManager.isContainedName("pack/../../x.mp3"))
        XCTAssertFalse(SoundManager.isContainedName("/etc/passwd"))
        XCTAssertFalse(SoundManager.isContainedName("~/x.mp3"))
        XCTAssertFalse(SoundManager.isContainedName(""))
    }
}
