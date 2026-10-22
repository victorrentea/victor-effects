import XCTest

/// 🎬 Guardrail: every Video Snippet the tablet can play (page 2) is on YouTube, as the
/// version the room sees — and a snippet added or changed since its upload fails the build
/// until it is published again. The workshop summary links each played snippet through
/// that upload as an emotional anchor, so a snippet without one is a hole in the summary.
///
/// The snippets live in the sibling `victor-macos-addons/videos/videos.json`; the publisher
/// and its ledger in the sibling `victor-vibe-board/tools/youtube-publish`. This test asks
/// the publisher itself (`python3 -m ytpub status`) instead of re-deriving its fingerprint
/// here, so the two can never disagree about what "changed" means. Skipped, with the reason,
/// where those checkouts are absent (CI, a clone without the private repos).
/// Override the locations with `YTPUB_TOOL_DIR` / `YTPUB_VIDEOS_DIR`.
final class VideoSnippetsOnYouTubeTests: XCTestCase {

    private var workspace: URL {
        URL(fileURLWithPath: #filePath)            // …/victor-effects/Tests/VictorEffectsTests/<this>
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
    }

    func testEverySnippetIsPublishedInItsCurrentVersion() throws {
        let env = ProcessInfo.processInfo.environment
        let tool = URL(fileURLWithPath: env["YTPUB_TOOL_DIR"]
            ?? workspace.appendingPathComponent("victor-vibe-board/tools/youtube-publish").path)
        let videos = URL(fileURLWithPath: env["YTPUB_VIDEOS_DIR"]
            ?? workspace.appendingPathComponent("victor-macos-addons/videos").path)
        guard FileManager.default.fileExists(atPath: tool.appendingPathComponent("ytpub").path) else {
            throw XCTSkip("no publisher at \(tool.path)")
        }
        guard FileManager.default.fileExists(atPath: videos.appendingPathComponent("videos.json").path) else {
            throw XCTSkip("no videos.json at \(videos.path)")
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["python3", "-m", "ytpub", "status"]
        p.currentDirectoryURL = tool
        var childEnv = env
        childEnv["YTPUB_VIDEOS_DIR"] = videos.path
        p.environment = childEnv
        let out = Pipe()
        p.standardOutput = out
        p.standardError = out
        try p.run()
        p.waitUntilExit()
        let text = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(p.terminationStatus, 0, "ytpub status failed:\n\(text)")

        let pending = Self.pending(in: text)
        XCTAssert(pending.isEmpty, """
            Video Snippets not on YouTube in their current version: \(pending.joined(separator: ", ")).
            Publish them (public unless the copyright check blocks them everywhere):
              cd \(tool.path) && python3 -m ytpub publish --upload
            """)
    }

    /// The ids listed under `new (N):` and `changed (N):` in `ytpub status`.
    static func pending(in status: String) -> [String] {
        var ids: [String] = []
        var collecting = false
        for line in status.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("new (") || line.hasPrefix("changed (") { collecting = true; continue }
            if !line.hasPrefix(" ") { collecting = false; continue }
            if collecting { ids.append(line.trimmingCharacters(in: .whitespaces)) }
        }
        return ids
    }

    func testPendingParsesTheStatusBuckets() {
        let status = "new (1):\n  jsonClip\nchanged (1):\n  KD_1Z8iUDho\npublished (2):\n  a\n  b\n"
        XCTAssertEqual(Self.pending(in: status), ["jsonClip", "KD_1Z8iUDho"])
    }
}
