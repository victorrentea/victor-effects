import Foundation

/// 🎵 The `.srt` lines of a video snippet played **soundtrack-only** (the ♪ on
/// the tablet's video page), sung karaoke-style at the bottom of the glass like
/// any soundboard press (Victor, 2026-11-12).
///
/// The clip plays in addons (`VideoSoundtrackPlayer`) with no window, so nothing
/// draws its subtitles over there. Addons owns the `.srt` and the play window;
/// it slices the cues of that window, rebases them to the moment the audio
/// starts and sends them here (`/caption/video/<id>?cues=<json>`), because this
/// app already owns everything a caption on the room's screen needs: the ✓
/// Subtitles switch, the roll-up, the zoom pinning, the screenshot exclusion.
///
/// **The fill is paced, not heard.** A subtitle cue says when a line starts and
/// ends, not when each word is said. Across a 1–2 s cue, sharing its span by the
/// letters in each word lands every word within a beat of the voice — unlike a
/// whole soundboard clip, where an even pace over many seconds read as the
/// captions being wrong (`SoundCaptions.withWords`).
enum VideoCaptions {
    struct Cue: Decodable, Equatable {
        /// Seconds after the soundtrack is first heard.
        let at: TimeInterval
        let end: TimeInterval
        let text: String
    }

    /// The asset key of a snippet's track: a stop of THAT soundtrack takes its
    /// lines down, a newer press's caption is left alone (`hide(asset:)`).
    static func asset(_ id: String) -> String { "video:\(id)" }

    /// The `cues` query parameter: a JSON array of `Cue`. Nil when it is not one.
    static func decode(_ json: String) -> [Cue]? {
        try? JSONDecoder().decode([Cue].self, from: Data(json.utf8))
    }

    /// One line per cue, each word lighting up over its share of the cue.
    static func lines(_ cues: [Cue]) -> [CaptionLine] {
        cues.compactMap { cue in
            // A two-line cue is one sentence; `wordEnds` splits on spaces only.
            let text = cue.text.split(whereSeparator: \.isNewline).joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            let span = max(0.3, cue.end - cue.at)
            let line = CaptionLine(at: max(0, cue.at), text: text, seconds: span,
                                   words: wordStarts(text, span: span), lastWordEnd: span)
            return SoundCaptions.heldToBeRead(line)
        }
    }

    /// When each word of `text` starts, in seconds after the line's cue: the
    /// span shared by the letters and digits in each word, so "Mayday!" takes
    /// longer than "a". Same units as `SoundCaptions.wordEnds`.
    static func wordStarts(_ text: String, span: TimeInterval) -> [TimeInterval] {
        let ends = SoundCaptions.wordEnds(text)
        let utf16 = Array(text.utf16)
        var weights: [Double] = [], from = 0
        for end in ends {
            let piece = String(utf16CodeUnits: Array(utf16[from..<end]), count: end - from)
            weights.append(Double(max(1, piece.filter { $0.isLetter || $0.isNumber }.count)))
            from = end
        }
        let total = weights.reduce(0, +)
        guard total > 0 else { return [] }
        var starts: [TimeInterval] = [], run = 0.0
        for w in weights {
            starts.append(span * run / total)
            run += w
        }
        return starts
    }
}
