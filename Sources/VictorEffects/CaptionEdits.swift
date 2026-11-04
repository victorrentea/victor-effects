import Foundation

/// The karaoke tuner's work: a track per clip, retimed or rewritten on the web
/// (`victorrentea.ro/karaoke`, its code in that repo) and fetched by
/// `tools/karaoke-sync.py` into `captionEditsFile`.
///
/// It is Victor's own data, like `sound-gains.json`: it lives next to the
/// config and not in the repo, so a retimed word is on the next press with no
/// build, and the code keeps saying what the app ships with
/// (`SoundCaptions.schedule`, which the tests pin and this never touches). A
/// clip listed here shows exactly these lines: no title line is added, the
/// tuner already shows it as a line of its own.
///
/// Read on every press, parsed again only when the file moved. Anything wrong
/// with the file means no edits, never a press without a caption.
enum CaptionEdits {
    struct Cue: Decodable, Equatable {
        let at: TimeInterval
        let text: String
        var words: [TimeInterval] = []

        enum CodingKeys: String, CodingKey { case at, text, words }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            at = try c.decode(TimeInterval.self, forKey: .at)
            text = try c.decode(String.self, forKey: .text)
            words = try c.decodeIfPresent([TimeInterval].self, forKey: .words) ?? []
        }
    }

    private struct Entry: Decodable { let cues: [Cue] }

    static func parse(_ data: Data) -> [String: [Cue]] {
        guard let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all.mapValues(\.cues).filter { !$0.value.isEmpty }
    }

    /// The lines of an edited track, with the Mac's own rules for how long each stays up.
    static func lines(_ cues: [Cue], clipSeconds: TimeInterval?) -> [CaptionLine] {
        let sorted = cues.sorted { $0.at < $1.at }
        let track = SoundCaptions.track(sorted.map { (at: $0.at, text: $0.text) }, clipSeconds: clipSeconds)
        return zip(track, sorted).map { line, cue in
            guard !cue.words.isEmpty, cue.words.count == SoundCaptions.wordEnds(cue.text).count else { return line }
            var timed = line
            timed.words = cue.words.map { max(0, $0 - cue.at) }
            return SoundCaptions.heldToBeRead(timed)
        }
    }

    private static let lock = NSLock()
    private static var loaded: (moved: Date?, table: [String: [Cue]]) = (nil, [:])

    private static var file: URL {
        URL(fileURLWithPath: EffectsConfig.expand(EffectsConfig.shared.values.captionEditsFile))
    }

    private static func current() -> (moved: Date?, table: [String: [Cue]]) {
        lock.lock(); defer { lock.unlock() }
        let moved = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        guard moved != loaded.moved else { return loaded }
        loaded = (moved, (try? Data(contentsOf: file)).map(parse) ?? [:])
        effectsInfo("💬 caption edits: \(loaded.table.count) clip(s)")
        return loaded
    }

    static func cues(for asset: String) -> [Cue]? { current().table[asset] }

    /// Changes whenever the edits do: part of the `/sounds/captions` cache key.
    static var stamp: String { current().moved.map { String($0.timeIntervalSince1970) } ?? "-" }
}

extension SoundCaptions {
    /// What a press shows: the tuner's track when the clip has one, else the app's own.
    static func live(for asset: String, clipSeconds: TimeInterval?) -> [CaptionLine] {
        CaptionEdits.cues(for: asset).map { CaptionEdits.lines($0, clipSeconds: clipSeconds) }
            ?? schedule(for: asset, clipSeconds: clipSeconds)
    }
}
