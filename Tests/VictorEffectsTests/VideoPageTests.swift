import XCTest
@testable import VictorEffects

/// The panel's second page: the list it is built from, the shape it lays out
/// in, and what a click on a tile actually says to the other app.
///
/// None of it can be checked by holding two keys — the gesture needs
/// Accessibility and a pair of hands — and the parts that *can* go wrong
/// silently are exactly these: a list that comes back empty and gets cached as
/// the truth, a tile that is the wrong shape, a second click that plays the clip
/// again instead of stopping it.
final class VideoPageTests: XCTestCase {

    // MARK: - The list

    private func body(_ videos: String) -> Data {
        Data("{\"videos\":[\(videos)]}".utf8)
    }

    func testParsingNumbersTilesByTheMacsOwnOrder() {
        let tiles = VideosManifest.parse(body("""
        {"id":"aaa","title":"Argentina","startSeconds":145},
        {"id":"bbb","title":"Kung Fu","startSeconds":13}
        """))
        XCTAssertEqual(tiles.map(\.n), [1, 2])
        XCTAssertEqual(tiles.map(\.id), ["aaa", "bbb"])
        XCTAssertEqual(tiles.map(\.title), ["Argentina", "Kung Fu"])
        XCTAssertEqual(tiles.first?.startSeconds, 145)
    }

    func testTheBadgeNumberIsThePlaceNotAnId() {
        // The tablet draws `index + 1` and renumbers itself when a video is
        // added; `/test/…/press/<n>?page=videos` has to address the same tile the
        // eye is reading, so both sides count places, not keys.
        let tiles = VideosManifest.parse(body("""
        {"id":"zzz","title":"last alphabetically, first on the board"},
        {"id":"aaa","title":"second"}
        """))
        XCTAssertEqual(tiles.first?.n, 1)
        XCTAssertEqual(tiles.first?.id, "zzz")
    }

    func testAnEntryWithoutATitleOrAThumbnailIsStillATile() {
        // The list is written by a repo this one does not own — a missing key
        // must cost a caption, never the whole page.
        let tiles = VideosManifest.parse(body("""
        {"id":"aaa"}
        """))
        XCTAssertEqual(tiles.count, 1)
        XCTAssertEqual(tiles.first?.title, "aaa")
        XCTAssertNil(tiles.first?.thumb)
        XCTAssertEqual(tiles.first?.startSeconds, 0)
    }

    func testAnEntryWithNoIdIsDropped() {
        // The id is the play call. A row without one is a tile that cannot do
        // anything when pressed.
        XCTAssertEqual(VideosManifest.parse(body("""
        {"title":"orphan"},{"id":"aaa","title":"real"}
        """)).map(\.id), ["aaa"])
        // …and the numbering closes up behind it rather than leaving a hole.
        XCTAssertEqual(VideosManifest.parse(body("""
        {"title":"orphan"},{"id":"aaa","title":"real"}
        """)).map(\.n), [1])
    }

    func testTheThumbnailComesInlineAsBase64() {
        // One call carries the list AND its pictures, which is what keeps the
        // two from drifting and what lets the page paint with no network of its
        // own. `Data(base64Encoded:)` is the whole decode.
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let tiles = VideosManifest.parse(body("""
        {"id":"aaa","thumb":"\(jpeg.base64EncodedString())"}
        """))
        XCTAssertEqual(tiles.first?.thumb, jpeg)
    }

    func testGarbageIsAnEmptyListAndNotACrash() {
        XCTAssertEqual(VideosManifest.parse(Data("not json".utf8)).count, 0)
        XCTAssertEqual(VideosManifest.parse(Data("{}".utf8)).count, 0)
    }

    // MARK: - The layout

    private typealias Grid = VideoGridView

    func testFiveToARowAtSixteenByNine() {
        // The tablet's `SNIPPETS_PER_ROW` and `cellWidth * 9 / 16`. Same numbers
        // because it is the same board — a snippet the room was shown from the
        // tablet has to be in the same place here.
        XCTAssertEqual(Grid.columns, 5)
        let m = Grid.metrics(fitting: NSSize(width: 1152, height: 719), count: 18)
        XCTAssertEqual(m.rows, 4)
        XCTAssertEqual(m.cellHeight, (m.cellWidth * 9 / 16).rounded(.down))
    }

    func testAVideoTileIsAboutThreeTimesASoundTile() {
        // 13 sound columns against 5 video columns — the RATIO is what has to
        // match, not a pixel count: both grids are read from the same distance
        // and the eye has already learned one of them.
        let size = NSSize(width: 1152, height: 719)
        let sound = ThumbnailGridView.metrics(fitting: size, count: 91, columns: 13).cell
        let video = Grid.metrics(fitting: size, count: 18).cellWidth
        XCTAssertEqual(video / sound, 13.0 / 5.0, accuracy: 0.15)
    }

    func testTheGridHugsItsOwnHeight() {
        // Page 2 is a different height from page 1 at the same width, which is
        // why the hug is recomputed per page rather than measured once.
        let size = NSSize(width: 1152, height: 719)
        let m = Grid.metrics(fitting: size, count: 18)
        XCTAssertEqual(m.hugHeight, m.size.height + Grid.padding * 2)
        XCTAssertLessThanOrEqual(m.hugHeight, size.height)
    }

    func testHuggingIsStable() {
        // Re-measuring at the hugged height must give the same cell, or a second
        // show creeps the board smaller — the same guard page 1 carries.
        let size = NSSize(width: 1152, height: 719)
        let first = Grid.metrics(fitting: size, count: 18)
        let second = Grid.metrics(fitting: NSSize(width: size.width, height: first.hugHeight),
                                  count: 18)
        XCTAssertEqual(first.cellWidth, second.cellWidth)
        XCTAssertEqual(first.hugHeight, second.hugHeight)
    }

    func testAShortFrameShrinksTheCellRatherThanOverflow() {
        // A panel you hold a key to see is one you never get to scroll, so the
        // height binding is a real case and not a theoretical one.
        let tall = Grid.metrics(fitting: NSSize(width: 1152, height: 200), count: 18)
        XCTAssertLessThanOrEqual(tall.size.height, 200)
    }

    func testOneVideoStillGetsOneRow() {
        let m = Grid.metrics(fitting: NSSize(width: 1152, height: 719), count: 1)
        XCTAssertEqual(m.rows, 1)
        XCTAssertGreaterThan(m.cellWidth, 0)
    }

    // MARK: - The press

    private func tile(_ n: Int, _ id: String) -> VideoTile {
        VideoTile(n: n, id: id, title: id, startSeconds: 0, thumb: nil)
    }

    /// A `VideoPress` whose HTTP is a recorder, so the route sequence — which is
    /// the thing worth asserting — can be read back.
    private func recorder(answer: @escaping (String) -> String?)
        -> (VideoPress, () -> [String]) {
        var calls: [String] = []
        let press = VideoPress()
        press.get = { path in
            calls.append(path)
            return answer(path)
        }
        press.schedule = { _, _ in }   // never fires on its own in a test
        return (press, { calls })
    }

    func testATapPlaysTheClipThroughTheAddonsRoute() {
        let (press, calls) = recorder { _ in "{\"ok\":true,\"startSeconds\":13,\"durationMs\":60000}" }
        let body = press.press(tile(1, "abc"))
        XCTAssertEqual(calls(), ["/video/play/abc"])
        XCTAssertTrue(body.contains("\"action\":\"play\""), body)
        XCTAssertTrue(body.contains("\"durationMs\":60000"), body)
        XCTAssertEqual(press.playing?.id, "abc")
    }

    func testASecondTapOnThePlayingTileStopsIt() {
        // Exactly what the tablet does (`onSnippetTouch`: the tile that is
        // playing IS its own stop button). A tile that stopped the clip there
        // and replayed it here would be a bug in the middle of a session.
        let (press, calls) = recorder { _ in "{\"ok\":true,\"durationMs\":60000}" }
        press.press(tile(1, "abc"))
        let body = press.press(tile(1, "abc"))
        XCTAssertEqual(calls(), ["/video/play/abc", "/video/stop"])
        XCTAssertTrue(body.contains("\"action\":\"stop\""), body)
        XCTAssertNil(press.playing)
    }

    func testADifferentTileReplacesRatherThanStops() {
        // One player, one clip: addons kills the previous IINA before relaunching,
        // so this side must not send a stop that would land after the new play.
        let (press, calls) = recorder { _ in "{\"ok\":true,\"durationMs\":60000}" }
        press.press(tile(1, "abc"))
        press.press(tile(2, "def"))
        XCTAssertEqual(calls(), ["/video/play/abc", "/video/play/def"])
        XCTAssertEqual(press.playing?.id, "def")
    }

    func testAddonsBeingDownIsAnAnswerAndNotAPlayingTile() {
        // The border must not pulse over a clip that never started — the panel
        // would be claiming something is on the projector that is not.
        let (press, _) = recorder { _ in nil }
        let body = press.press(tile(1, "abc"))
        XCTAssertTrue(body.contains("\"reason\":\"addons-down\""), body)
        XCTAssertNil(press.playing)
    }

    func testTheBorderClearsWhenTheClipsOwnDeadlinePasses() {
        // `durationMs` is addons' auto-kill window. Nothing polls for the end
        // here, so this timer IS how the pulsing stops.
        var pending: (() -> Void)?
        let press = VideoPress()
        press.get = { _ in "{\"ok\":true,\"durationMs\":1000}" }
        press.schedule = { _, work in pending = work }
        press.press(tile(1, "abc"))
        XCTAssertEqual(press.playing?.id, "abc")
        pending?()
        XCTAssertNil(press.playing)
    }

    func testALateCompletionIsOutvotedNotObeyed() {
        // The first clip's deadline must not clear the border of the second.
        var pending: [() -> Void] = []
        let press = VideoPress()
        press.get = { _ in "{\"ok\":true,\"durationMs\":1000}" }
        press.schedule = { _, work in pending.append(work) }
        press.press(tile(1, "abc"))
        press.press(tile(2, "def"))
        pending.first?()
        XCTAssertEqual(press.playing?.id, "def")
    }

    // MARK: - The config key behind all of it

    func testTheAddonsBaseUrlDefaultsToTheOtherAppsPort() {
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: nil).addonsBaseURL,
                       "http://127.0.0.1:55123")
    }

    func testTheAddonsBaseUrlIsConfigurable() {
        let v = EffectsConfigValues.parse(
            jsonData: Data("{\"addonsBaseURL\":\"http://192.168.1.9:55123/\"}".utf8))
        XCTAssertEqual(v.addonsBaseURL, "http://192.168.1.9:55123/")
        // Empty is a real setting — a Mac with no addons app on it — and is how
        // the video page is switched off rather than left dialling a dead port.
        XCTAssertEqual(EffectsConfigValues.parse(jsonData: Data("{\"addonsBaseURL\":\"\"}".utf8))
                        .addonsBaseURL, "")
    }
}
