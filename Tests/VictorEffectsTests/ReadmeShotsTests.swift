import AppKit
import XCTest
@testable import VictorEffects

/// Renders the two pages of the right-⌘ panel to PNG for the README — the
/// soundboard (page 1) and the 🎬 videos (page 2).
///
/// **A test, not a tool**, because the package is one executable target and only
/// `@testable import` reaches its internal views. Drawing the real
/// `ThumbnailPanel` rather than a mock-up is the whole point: the picture in the
/// README is then the board, ⭐ and `#NN` and all, and cannot drift from it.
///
/// **Skipped unless `README_SHOTS_OUT` is set**, so an ordinary `swift test` (and
/// with it every `build-app.sh`) never needs the tablet repo or a video list.
/// `tools/readme-shots.sh` sets the three variables; CI runs that script
/// (`.github/workflows/readme-shots.yml`).
///
/// No screen is captured — the panel is never ordered front and its layer tree
/// is drawn straight into a bitmap — so this needs no Screen Recording grant
/// and works on a headless CI runner.
final class ReadmeShotsTests: XCTestCase {
    /// Points, not pixels. About the width GitHub gives a README column, so the
    /// picture is shown close to 1:1 and the `#NN` badges stay legible.
    static let width: CGFloat = 900
    static let scale: CGFloat = 2

    func testRendersBothPanelPagesForTheReadme() throws {
        let env = ProcessInfo.processInfo.environment
        guard let out = env["README_SHOTS_OUT"], !out.isEmpty else {
            throw XCTSkip("README_SHOTS_OUT not set — run tools/readme-shots.sh")
        }
        let soundsDir = try XCTUnwrap(env["README_SHOTS_SOUNDS_DIR"], "README_SHOTS_SOUNDS_DIR")
        let videosJSON = try XCTUnwrap(env["README_SHOTS_VIDEOS"], "README_SHOTS_VIDEOS")
        let outDir = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        let saved = EffectsConfig.shared.values
        var values = saved
        values.soundsDir = soundsDir
        values.addonsBaseURL = ""
        EffectsConfig.shared.override(values)
        TilesManifest.invalidate()
        TileImageCache.shared.clear()
        VideoThumbCache.shared.clear()
        defer {
            EffectsConfig.shared.override(saved)
            TilesManifest.invalidate()
            TileImageCache.shared.clear()
            VideoThumbCache.shared.clear()
        }

        let panel = ThumbnailPanel()

        // Page 1 — the soundboard.
        panel.grid.reload()
        XCTAssertFalse(panel.grid.tiles.isEmpty, "no tiles.json under \(soundsDir)")
        let boardHeight = try XCTUnwrap(panel.grid.hugHeight(fitting: NSSize(width: Self.width, height: 10_000)))
        layOut(panel, page: .effects, height: boardHeight)
        waitForTileImages(panel.grid.tiles, soundsDir: soundsDir)
        try write(panel, to: outDir.appendingPathComponent("soundboard.png"))

        // Page 2 — the videos, from the snapshot of addons' `GET /videos`.
        let videos = VideosManifest.parse(try Data(contentsOf: URL(fileURLWithPath: videosJSON)))
        XCTAssertFalse(videos.isEmpty, "no videos in \(videosJSON)")
        panel.videoGrid.reload(with: videos)
        let videoHeight = try XCTUnwrap(panel.videoGrid.hugHeight(fitting: NSSize(width: Self.width, height: 10_000)))
        layOut(panel, page: .videos, height: videoHeight)
        try write(panel, to: outDir.appendingPathComponent("videos.png"))
    }

    // MARK: - helpers

    private func layOut(_ panel: ThumbnailPanel, page: PanelPage, height: CGFloat) {
        panel.setFrame(NSRect(x: 0, y: 0, width: Self.width, height: height.rounded(.up)), display: false)
        panel.setPage(page)
    }

    /// Tile pictures decode on a background queue and land on the main one, so
    /// the run loop has to turn until every picture that exists has arrived.
    private func waitForTileImages(_ tiles: [Tile], soundsDir: String) {
        let base = URL(fileURLWithPath: (soundsDir as NSString).expandingTildeInPath)
        let expected = tiles.filter {
            FileManager.default.fileExists(atPath: base.appendingPathComponent($0.image).path)
        }
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline,
              !expected.allSatisfy({ TileImageCache.shared.cached($0.image) != nil }) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        let missing = expected.filter { TileImageCache.shared.cached($0.image) == nil }.map(\.image)
        XCTAssertTrue(missing.isEmpty, "tile pictures never decoded: \(missing)")
        // One more turn, so the `imageLayer.contents` assignments queued behind
        // the last decode have run.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    }

    /// The panel's layer tree, drawn into a bitmap at `scale` — transparent
    /// outside the rounded card, so it sits on GitHub's light and dark themes alike.
    private func write(_ panel: ThumbnailPanel, to url: URL) throws {
        // AppKit syncs a view's `isHidden` and frame onto its layer on the next
        // display pass, not on assignment — without a turn of the run loop the
        // page just switched to is drawn as an empty card.
        panel.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let layer = try XCTUnwrap(panel.contentView?.layer)
        let size = layer.bounds.size
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * Self.scale), pixelsHigh: Int(size.height * Self.scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep)).cgContext
        context.scaleBy(x: Self.scale, y: Self.scale)
        layer.render(in: context)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("🖼  \(url.path)")
    }
}
