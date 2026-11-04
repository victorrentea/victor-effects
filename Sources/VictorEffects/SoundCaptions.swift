import AppKit
import QuartzCore

/// Closed captions for the soundboard: a half-transparent subtitle at the bottom
/// of the overlay screen, for whoever in the room — or on the call — cannot hear
/// the joke. Songs show the line that is sung, plain (no ♪ in any subtitle,
/// Victor, 2026-11-04), everything else names the noise or the music the way
/// TV captions do ([wolf howling], [piano music]).
///
/// Only while the ✓ Subtitles row is on (`SubtitlesSwitch`, off by default).
///
/// Shown on every PRESS, not on every play: `/sound/pressed/` (and the siren's
/// `/alarm/start`) is where the tablet's presses and the panel's meet, whether
/// the audio then plays on this Mac or on the tablet's own speaker. Hooking
/// `/sound/play` instead would caption only the routed half and caption the
/// panel's presses twice.
///
/// Pure on purpose: the text and the on-screen life are decided here and drawn
/// by `CaptionOverlay`, so the table is testable without a screen.
enum SoundCaptions {

    /// Hand-written, one line per tile. Lyrics were taken from the clips
    /// themselves (a Whisper pass over `soundsDir`), not from memory of the
    /// song — a caption that disagrees with what the room hears is worse than
    /// none.
    static let table: [String: String] = [
        "01_baby.mp3":                "[baby crying]",
        "02_siren.mp3":               "[siren wailing]",
        "03_explosion.mp3":           "[explosion]",
        "04_wolf.mp3":                "[wolf howling]",
        "05_guess_whos_back.mp3":     "Guess who's back, back again",
        "06_copyright_cartoon.mp3":   "[Pink Panther theme]",
        "07_animated_phone.mp3":      "\"What does this button do?\"",
        "08_scream_man.mp3":          "[man screaming]",
        "09_ave_maria.mp3":           "Ave Maria",
        "10_red_phone.mp3":           "[phone ringing]",
        "11_fire.mp3":                "[fire crackling]",
        "12_cricket.mp3":             "[crickets chirping]",
        "13_heartbeat.mp3":           "[heart beating]",
        "14_universal.mp3":           "[Universal fanfare]",
        "15_flatline.mp3":            "[flatline beep]",
        "16_magic_wand.mp3":          "[magic sparkles]",
        "17_my_precious.mp3":         "\"My precious…\"",
        "18_chainsaw.mp3":            "[chainsaw revving]",
        "19_fail.mp3":                "[sad trombone]",
        "20_fail2.mp3":               "[sad trombone]",
        "20_storm.mp3":               "[thunderstorm]",
        "21_sfx_41.mp3":              "\"Isn't that cute? BUT IT'S WRONG!\"",
        "22_minigun.mp3":             "[minigun firing]",
        "23_radar.mp3":               "[radar ping]",
        "24_this_is_sparta.mp3":      "\"THIS IS SPARTA!\"",
        "25_dark_door.mp3":           "[knocking]",
        "26_drum.mp3":                "[drum roll]",
        "27_clapping.mp3":            "[applause]",
        "28_who_let_dogs_out.mp3":    "Who let the dogs out?",
        "29_gangnam_style.mp3":       "Oppa Gangnam Style",
        "30_cow.mp3":                 "[cow mooing]",
        "31_tarzan.mp3":              "[Tarzan yell]",
        "32_sheep.mp3":               "[sheep bleating]",
        "33_yee_har.mp3":             "\"Yee-haw!\"",
        "33b_ay.mp3":                 "\"Ay, ay, ay, ay!\"",
        "34_phoenix.mp3":             "[phoenix screeching]",
        "35_cant_touch_this.mp3":     "Can't touch this",
        "36_bad_habits.mp3":          "My bad habits lead to late nights",
        "37_rainbow.mp3":             "Somewhere over the rainbow",
        "38_imagine.mp3":             "Imagine all the people",
        "38b_dreamer.mp3":            "I'm just a dreamer",
        "39_skull_boom.mp3":          "[boom]",
        "40_joker.mp3":               "[maniacal laughter]",
        "41_love_hearts.mp3":         "[romantic music]",
        "42_saxophone.mp3":           "[sultry saxophone]",
        "43_dun.mp3":                 "[dun dun DUNNN]",
        "44_small_dog.mp3":           "[small dog yapping]",
        "45_the_mask.mp3":            "\"Somebody stop me!\"",
        "46_michael_buble.mp3":       "It's beginning to look a lot like Christmas",
        "46b_my_way.mp3":             "I did it my way",
        "47_dog_bark.mp3":            "[dog barking]",
        "48_rooster.mp3":             "[rooster crowing]",
        "49_wrong.mp3":               "[wrong-answer buzzer]",
        "50_gong.mp3":                "[gong]",
        "51_beethoven.mp3":           "[Da-da-da-DUM]",
        "52_saw.mp3":                 "[sawing]",
        "53_rain.mp3":                "[money raining]",
        "54_piano.mp3":               "[piano music]",
        "55_star_wars.mp3":           "[Star Wars theme]",
        "55b_tsunami.mp3":            "[tsunami]",
        "56_door_open.mp3":           "[door creaking open]",
        "57_checkmark.mp3":           "[success chime]",
        "58_cat.mp3":                 "[cat meowing]",
        "59_game_over.mp3":           "\"Game over\"",
        "60_sfx_100.mp3":             "[dramatic singing]",
        "61_hallelujah.mp3":          "Hallelujah",
        "62_lionel_richie.mp3":       "Hello, is it me you're looking for?",
        "63_air_horn.mp3":            "[air horn]",
        "64_fbi.mp3":                 "\"FBI! Open up!\"",
        "65_school_bell.mp3":         "[bell ringing]",
        "66_toilet.mp3":              "[toilet flushing]",
        "67_sfx_109.mp3":             "\"Eww, brother, eww!\"",
        "68_pig.mp3":                 "[pig oinking]",
        "69_scream_ghost.mp3":        "\"Wazzuuup!\"",
        "70_cavalry.mp3":             "[cavalry bugle charge]",
        "71_one_more_time.mp3":       "One more try…",
        "72_if_tomorrow.mp3":         "If tomorrow never comes",
        "73_counter_strike.mp3":      "\"Go, go, go!\"",
        "74_oops.mp3":                "Oops, I did it again",
        "75_sfx_117.mp3":             "\"May I have your attention, please?\"",
        "76_sfx_118.mp3":             "Wasn't me",
        "77_maui.mp3":                "You're welcome!",
        "78_projector.mp3":           "[film projector whirring]",
        "79_door.mp3":                "[door slams]",
        "80_7_rings.mp3":             "I want it, I got it",
        "81_let_it_be.mp3":           "Let it be",
        "81b_let_go.mp3":             "Let go",
        "82_over_and_out.mp3":        "\"Over and out.\"",
        "83_yummy.mp3":               "Yummy, yummy, yummy",
        "84_eclipse.mp3":             "[epic music]",
        "85_joy.mp3":                 "[Ode to Joy]",
        "86_doorbell.mp3":            "[doorbell]",
        "87_grenade.mp3":             "[grenade explodes]",
        "88_all_you_need_is_love.mp3": "All you need is love",
        "89_fireworks.mp3":           "[fireworks]",
        "90_breaking-glass.mp3":      "[glass shattering]",
        "91_sinking.mp3":             "[ship sinking]",
    ]

    /// Songs whose words are sung line by line: each line goes up at the
    /// second it starts in the clip (a Whisper pass with word timestamps over
    /// `soundsDir`, then checked against the song's real lyrics where Whisper
    /// misheard — "Shaney's back" is Shady's). A song NOT here keeps its one line from `table`, and so
    /// does a clip whose lines would all read the same (who let the dogs out,
    /// can't touch this) — a line that never changes needs no clock.
    static let lyrics: [String: [(at: TimeInterval, text: String)]] = [
        "05_guess_whos_back.mp3": [(0, "Guess who's back, back again"),
                                   (4.0, "Shady's back, tell a friend"),
                                   (7.9, "Guess who's back, guess who's back")],
        // Sung once, slowly: "A" at 1.33, the held "Maria" to 11.2 (2026-10-23
        // review — a second "Ave Maria" at 5.6 was that same held phrase).
        "09_ave_maria.mp3":       [(0, "Ave Maria"),
                                   (12.6, "Jungfrau mild")],
        "36_bad_habits.mp3":      [(0, "My bad habits lead to late nights endin' alone"),
                                   (3.6, "Conversations with a stranger I barely know"),
                                   (7.5, "Swearin' this will be the last, but it probably won't")],
        "37_rainbow.mp3":         [(2.8, "Somewhere over the rainbow"),
                                   (10.0, "Way up high")],
        "38_imagine.mp3":         [(0, "Imagine all the people"),
                                   (5.7, "Living for today")],
        "38b_dreamer.mp3":        [(0, "I'm just a dreamer"),
                                   (3.5, "I dream my life away")],
        // Rammstein, "Sonne", from a slowed edit: the clip is 34.94 s into it,
        // so the opening second stays on the table's [boom], the drop. The
        // words are stretched over the five seconds they are sung in; Whisper
        // only heard them with the edit's own run-up (2026-11-04).
        "39_skull_boom.mp3":      [(2.35, "Hier kommt die Son\u{AD}ne")],
        "46_michael_buble.mp3":   [(0, "It's beginning to look a lot like Christmas"),
                                   (5.8, "Everywhere you go")],
        // The clip ends at 17.1 s (2.5 s fade-out from 14.6 s, 2026-10-22): the
        // loud final climax that began at 17.25 s was cut off. Four slow
        // phrases, at 0.25, 4.35, 8.58 and 12.86 (2026-10-23 review).
        // Sung by the syllable, 'jah' held, so each one is timed (U+00AD).
        "61_hallelujah.mp3":      [(0, "Hal\u{AD}le\u{AD}lu\u{AD}jah! Hal\u{AD}le\u{AD}lu\u{AD}jah!"),
                                   (8.5, "Hal\u{AD}le\u{AD}lu\u{AD}jah! Hal\u{AD}le\u{AD}lu\u{AD}jah!")],
        "62_lionel_richie.mp3":   [(0, "Hello…"),
                                   (4.4, "Is it me you're looking for?")],
        "71_one_more_time.mp3":   [(0, "One more try…"),
                                   (2.3, "I didn't know how much I loved you"),
                                   (6.4, "One more try…"),
                                   (8.7, "Let me put my arms around you")],
        "72_if_tomorrow.mp3":     [(0, "If tomorrow never comes"),
                                   (5.8, "Will she know how much I loved her?")],
        "74_oops.mp3":            [(0, "Oh baby, baby"),
                                   (1.3, "Oops, I did it again"),
                                   (4.1, "I played with your heart"),
                                   (6.8, "Got lost in the game")],
        "76_sfx_118.mp3":         [(0, "Wasn't me"),
                                   (0.7, "Heard the words that I told her"),
                                   (2.4, "Wasn't me"),
                                   (3.3, "Heard the screams getting louder"),
                                   (4.7, "Wasn't me")],
        "77_maui.mp3":            [(0, "Well, anyway, let me say you're welcome"),
                                   (3.3, "For the wonderful world you know"),
                                   (6.5, "Hey, it's okay")],
        "81_let_it_be.mp3":       [(2.3, "When I find myself in times of trouble"),
                                   (6.3, "Mother Mary comes to me"),
                                   (9.0, "Speaking words of wisdom"),
                                   (11.9, "Let it be")],
        "83_yummy.mp3":           [(0, "Yeah, you got that yummy-yum"),
                                   (2.9, "That yummy-yum"),
                                   (4.6, "That yummy-yummy")],
    ]

    /// The caption for a press. A tile added to
    /// `tiles.json` before anyone wrote its line still gets one, made from its
    /// filename (`56_door_open.mp3` → `[door open]`): a vague caption beats a
    /// silent one for someone who cannot hear the room.
    static func caption(for asset: String) -> String? {
        if let line = table[asset] { return line }
        return fallback(for: asset)
    }

    static func fallback(for asset: String) -> String? {
        var stem = (asset as NSString).deletingPathExtension
        // Drop the `NN_` / `NNb_` grid prefix.
        if let underscore = stem.firstIndex(of: "_"),
           stem[..<underscore].allSatisfy({ $0.isNumber || $0.isLowercase }),
           stem[..<underscore].first?.isNumber == true {
            stem = String(stem[stem.index(after: underscore)...])
        }
        let words = stem.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return words.isEmpty ? nil : "[\(words)]"
    }

    /// How long the line stays up: the clip's own length, but never shorter
    /// than it takes to read a line and never longer than a subtitle deserves —
    /// a 37 s theme tune does not get to hang a caption over the slides.
    static let minSeconds: TimeInterval = 2.5
    static let maxSeconds: TimeInterval = 6

    static func lifetime(clipSeconds: TimeInterval?) -> TimeInterval {
        min(max(clipSeconds ?? minSeconds, minSeconds), maxSeconds)
    }
}

/// One line of a caption track: up at `at` seconds into the clip, for
/// `seconds`. A noise or a one-line song is a track of one. `words`: when each
/// word turns yellow, in seconds after the line goes up (the karaoke fill).
struct CaptionLine: Equatable {
    let at: TimeInterval
    let text: String
    var seconds: TimeInterval
    var words: [TimeInterval] = []

    /// The line as it goes on the glass: `SoundCaptions.leadIn` before its
    /// fill starts, whenever its cue is, but not before `earliest` (seconds
    /// into the clip: negative while the clip is still on its way to the
    /// speaker, so an opening line gets its lead too when there is time for
    /// it). `at` stays the reviewed cue everywhere else, the key of
    /// `wordTimes`. A line nobody timed goes up on its cue.
    func ahead(earliest: TimeInterval = 0) -> CaptionLine {
        guard let first = words.first else { return self }
        let up = max(earliest, at + first - SoundCaptions.leadIn)
        let early = at - up
        return CaptionLine(at: up, text: text, seconds: seconds + early, words: words.map { $0 + early })
    }
}

extension SoundCaptions {
    /// A song whose first word comes later than this opens on its `table`
    /// line, so the screen says what is playing while the intro does.
    static let titleLeadIn: TimeInterval = 1
    /// A said line stays up this long after its last word is full (Victor,
    /// 2026-11-04: "to get to read it"). Lines overlap for that second, which
    /// is what the roll-up (`CaptionOverlay`) is for: the next line comes in
    /// under this one instead of taking its place. An untimed sung line,
    /// whose last word nobody knows, gets the same second past the next one.
    static let readHold: TimeInterval = 1
    /// A said line is on the glass this long before its fill starts (Victor,
    /// 2026-11-04: half a second, then "1 s before it starts colouring").
    static let leadIn: TimeInterval = 1
    /// The rows on the glass at once. A fast song would otherwise stack past
    /// the slide's body; the next line pushes the oldest out early.
    static let maxRows = 3

    /// The whole track for a press. Every line ends itself — a sung line when
    /// the next one is due (or after `maxSeconds`, so an instrumental gap goes
    /// blank instead of parking a stale line), the last one when the clip ends,
    /// bounded like a single caption.
    static func schedule(for asset: String, clipSeconds: TimeInterval?) -> [CaptionLine] {
        guard let first = caption(for: asset) else { return [] }
        guard let sung = lyrics[asset], !sung.isEmpty else {
            return [heldToBeRead(withWords(CaptionLine(at: 0, text: first, seconds: lifetime(clipSeconds: clipSeconds)), asset: asset))]
        }
        var cues = sung.map { (at: $0.at, text: $0.text) }
        if cues[0].at >= titleLeadIn { cues.insert((at: 0, text: first), at: 0) }
        return cues.indices.map { i in
            let at = cues[i].at
            let seconds: TimeInterval
            if i + 1 < cues.count {
                let gap = cues[i + 1].at - at
                seconds = gap <= maxSeconds ? gap + readHold : maxSeconds
            } else {
                seconds = lifetime(clipSeconds: clipSeconds.map { $0 - at })
            }
            return CaptionLine(at: at, text: cues[i].text, seconds: seconds)
        }.map { heldToBeRead(withWords($0, asset: asset)) }
    }

    /// A timed line lives by its words, not by the clock of the track: until
    /// its fill ends, plus `readHold` to read it, however long the clip goes
    /// on after (no more words, the line goes) and however soon the next line
    /// arrives (it rolls in underneath). Never under `minSeconds`.
    static func heldToBeRead(_ line: CaptionLine) -> CaptionLine {
        guard let last = line.words.last else { return line }
        var held = line
        held.seconds = max(last + lastWordSweep + readHold, minSeconds)
        return held
    }

    /// Where each row of the roll-up sits, newest at the bottom: `heights`
    /// oldest first, the answer the same way, in points above the stack's
    /// foot. Pure, so the order of the rows is testable without a screen.
    static func rollUp(heights: [CGFloat], gap: CGFloat) -> [CGFloat] {
        var y: CGFloat = 0
        return heights.reversed().map { h in
            defer { y += h + gap }
            return y
        }.reversed()
    }

    // MARK: the karaoke fill (Victor, 2026-10-23: "TikTok style, yellow on
    // white, word by word as it is said" — and, an hour later, "only colour a
    // word at the moment it is pronounced"; then "left to right, progressively")

    /// Where each word of `text` ends, in UTF-16 offsets — a word being a
    /// whitespace-separated token with a letter or digit in it, so a lone
    /// dash is not a word: it lights up with the next word. A soft hyphen (U+00AD,
    /// `syllable`) splits a word into syllables timed one by one — a word sung
    /// over seconds (Victor, 2026-10-23: "split Hallelujah into syllables") —
    /// and draws nothing.
    static func wordEnds(_ text: String) -> [Int] {
        var ends: [Int] = [], offset = 0
        for token in text.split(separator: " ", omittingEmptySubsequences: false) {
            for piece in token.split(separator: syllable, omittingEmptySubsequences: false) {
                offset += piece.utf16.count
                if piece.contains(where: { $0.isLetter || $0.isNumber }) { ends.append(offset) }
                offset += 1
            }
        }
        return ends
    }

    /// The soft hyphen: a syllable break inside a word, invisible on the glass.
    static let syllable: Character = "\u{00AD}"

    /// A word sweeps until the next one is heard — a held note fills slowly,
    /// as it is sung — but no longer than this: a longer gap is a pause, and
    /// the word should be full before it, not crawl through the silence.
    static let maxWordSweep: TimeInterval = 2
    /// The last word has no next one to run to.
    static let lastWordSweep: TimeInterval = 0.6

    /// The karaoke's path through `text`: how far the yellow has reached (a
    /// UTF-16 offset) at each moment, in seconds after the line goes up, to be
    /// joined by straight lines. Every word WIPES left to right over the time
    /// it is said (Victor, 2026-10-23: "progressively, syllable by syllable,
    /// not all at once") — from the end of the previous word, so the space and
    /// an opening quote go with the first word and a closing one with the last.
    static func fill(_ text: String, words: [TimeInterval], seconds: TimeInterval) -> [(t: TimeInterval, offset: Int)] {
        let ends = wordEnds(text)
        guard !words.isEmpty, words.count == ends.count else { return [] }
        var path: [(t: TimeInterval, offset: Int)] = [(0, 0)]
        func add(_ t: TimeInterval, _ offset: Int) {
            let t = max(t, path.last!.t)
            if t == path.last!.t { path.removeLast() }
            path.append((t, offset))
        }
        for (i, at) in words.enumerated() {
            let last = i == words.count - 1
            let sweep = last ? min(lastWordSweep, max(0.1, seconds - at))
                             : min(maxWordSweep, max(0, words[i + 1] - at))
            if at > path.last!.t { add(at, path.last!.offset) }
            add(max(0, at) + sweep, last ? text.utf16.count : ends[i])
        }
        return path
    }

    /// The words of a line, timed as they were reviewed on the voice
    /// (`wordTimes`, generated from `tools/caption-words.json`). A line not
    /// there — a [noise], an instrumental title, a song's intro title — gets
    /// none and stays plain white: nothing is said, so nothing lights up. An
    /// even-paced fill was tried first and read as the captions being wrong.
    static func withWords(_ line: CaptionLine, asset: String) -> CaptionLine {
        let count = wordEnds(line.text).count
        var timed = line
        if let heard = wordTimes[asset]?.first(where: { abs($0.at - line.at) < 0.01 && $0.words.count == count }) {
            timed.words = heard.words.map { max(0, $0 - line.at) }
        }
        return timed
    }

    /// How long from `now` until the room hears a clip this Mac started at
    /// `playedAt`: its paired lead, the Bluetooth silence, then the speaker's
    /// own latency (`SoundTimingConfig`). The word times are seconds into the
    /// CLIP, so the track waits for this before its zero. A play older than
    /// `routedWindow` is not this press's (the client played it itself): 0.
    static func audibleDelay(playedAt: Date, now: Date, lead: TimeInterval,
                             bluetoothCompensation: TimeInterval, outputLatency: TimeInterval) -> TimeInterval {
        guard now.timeIntervalSince(playedAt) < routedWindow else { return 0 }
        return max(0, playedAt.addingTimeInterval(lead + bluetoothCompensation + outputLatency).timeIntervalSince(now))
    }

    /// The press follows its `/sound/play` within milliseconds, on both the
    /// tablet and the panel; the visual's compensation hand-off uses the same.
    static let routedWindow: TimeInterval = 1.5
}

/// The ✓ Subtitles row in the menu: ONE switch for every subtitle on the
/// room's screen — the soundboard captions drawn here AND the `.srt` lines the
/// addons app burns over a video snippet. **Off by default** (Victor,
/// 2026-10-09): a caption is for the room that asked for one, not a default.
///
/// Kept in this app's own defaults domain (`ro.victorrentea.victor-effects`)
/// so it survives a restart, and so addons can read it at the moment a video
/// starts (`CFPreferencesCopyAppValue`, in its `VideoPlayer`) — a local read,
/// no HTTP hop, nothing waits on this app being up. A missing key reads as off
/// on both sides, which is also what addons sees with this app never launched.
enum SubtitlesSwitch {
    static let key = "subtitlesOn"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: key) }

    /// Switching off also takes down the caption on screen: the click is the
    /// answer to "that caption should not be there", and waiting up to 6 s for
    /// it to expire would read as the switch not working.
    static func set(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: key)
        // Flushed now, not on cfprefsd's schedule: addons reads it on the very
        // next video, which may be seconds away.
        UserDefaults.standard.synchronize()
        if !on { CaptionOverlay.hide() }
    }
}

/// The caption's own window class, so a screenshot can tell it from the
/// overlay: every screenshot effect leaves it out of the picture
/// (`CaptionSafeCapture`, `captureScreenExcludingOverlay`), or a press caption
/// would be photographed and then blown up under itself by the effect it
/// captions.
final class CaptionPanel: NSPanel {}

/// The subtitle itself: one borderless panel, reused, near the bottom of the
/// glass, the same size and in the same place whatever else is going on
/// (Victor, 2026-10-14). The pills are a **55 % black** the slide shows
/// through; the letters on them are opaque (until 2026-10-23 the whole caption
/// sat at 50 %, and the karaoke yellow washed out to a cream nobody could
/// tell from the white).
///
/// - **A roll-up, not a swap** (Victor, 2026-11-04: "read from somewhere, don't
///   let it leave the screen fast"). Each line is its own row, its own pill. The
///   first line just fades in, fast, on the standard position; a line arriving
///   over another rises from below and pushes the others up; a row whose
///   time is up fades out where it stands, so a line stays for its `readHold`
///   while the next one is already being sung under it, and the bottom row
///   never moves because of the one above it going (Victor, 2026-11-04: a
///   fade is enough, no swipe). No more words, no more rows.
/// - **Painted last.** Its window level (`windowLevel`) is above every other
///   window this app opens — the overlay, the whip, the edge flash, even the
///   peek mascot — so no effect can cover it. It stays an ordinary window: Zoom
///   and Teams capture it like everything else on the screen.
/// - **Left out of our own screenshots**, so a screenshot effect (💀 #39, 🎼,
///   🚔, 💓…) never zooms a frozen copy of it under the live one.
/// - **Pinned through the zooms.** macOS ⌥-scroll magnifies the framebuffer,
///   this panel included, so the stage is laid out at its rest size and then
///   scaled down by the zoom factor and centred on the slice on the glass —
///   re-placed at 30 Hz while it is up, so a pan or a zoom mid-caption does not
///   leave it behind. The other zoom (⌥⇧, `ShareZoom` in addons) is a window
///   *under* this one, so it needs nothing here.
///
/// A new press clears the rows of the old one; `hide()` is what `stopAll` calls.
/// Neither is what ends a row: every `show` schedules its own removal (the
/// self-termination rule), and a removal that finds its row gone does nothing.
enum CaptionOverlay {
    /// The pill's black. The text is drawn opaque over it.
    static let pillAlpha: CGFloat = 0.55
    static let fontSize: CGFloat = 36
    /// Height of the gap under the caption, as a share of the visible height —
    /// low enough to stay off the slide body (5 %, ~56 pt on the Retina).
    static let bottomInset: CGFloat = 0.05
    /// Above the peek mascot's `EffectsLevel.overlay + 1`, the highest anything else
    /// here goes. `CaptionLevelTests` parses the sources to keep it that way.
    static let windowLevel = NSWindow.Level(rawValue: EffectsLevel.overlay.rawValue + 2)
    static let followInterval: TimeInterval = 1.0 / 30
    static let fadeOutSeconds: TimeInterval = 0.4
    /// How long the rows take to make room for a new one.
    static let rollSeconds: TimeInterval = 0.25
    /// Between two rows.
    static let rowGap: CGFloat = 8
    /// The first row on an empty stage has nothing to push: a quick fade.
    static let firstRowFade: TimeInterval = 0.12
    /// How far a row rises as it comes in under another.
    static let rowTravel: CGFloat = 36
    /// The stage reaches this far under the first row, or a row rising from
    /// below would be cut off by the panel's edge. Taken off the panel's
    /// origin, so the row itself sits at `bottomInset` as it always did.
    static let stageFoot: CGFloat = rowTravel + 4
    /// The said words: a saturated, opaque yellow…
    static let litColor = NSColor(srgbRed: 1, green: 0.8, blue: 0, alpha: 1)
    /// …on words still to come dimmed to a grey, so the step from one to the
    /// other is a change of brightness AND colour (Victor, 2026-10-23: "I
    /// could barely see them turn yellow"). A line with no timing (a noise,
    /// a title) is never dimmed: it is plain white throughout.
    static let upcomingColor = NSColor(white: 1, alpha: 0.55)

    /// One line on the glass.
    private final class Row {
        let box: CALayer
        let height: CGFloat
        init(box: CALayer, height: CGFloat) { self.box = box; self.height = height }
    }

    private static var panel: CaptionPanel?
    /// Oldest first; the last one is the bottom row.
    private static var rows: [Row] = []
    /// Bumped by every new track and every `hide()`: a sung line still queued
    /// from a song that was stopped, or replaced by another press, finds it
    /// moved and stays down.
    private static var track = 0
    /// The clip the current track belongs to: a stop of THAT tile takes the
    /// caption down with its sound (`hide(asset:)`); a stop of another one
    /// (or its natural end, reported late) leaves a newer caption alone.
    private static var trackAsset: String?
    /// What is up now, kept to re-place it when the zoom moves.
    private static var shown: (stage: CALayer, restSize: CGSize, screen: CGRect, visible: CGRect)?
    private static var follower: Timer?

    /// The caption's window while it is on the glass, nil otherwise. Read off
    /// the main thread by the screenshot helpers, hence the lock.
    private static let lock = NSLock()
    private static var _onGlassWindowID: CGWindowID?
    static var onGlassWindowID: CGWindowID? {
        lock.lock(); defer { lock.unlock() }
        return _onGlassWindowID
    }
    private static func setOnGlass(_ id: CGWindowID?) {
        lock.lock(); _onGlassWindowID = id; lock.unlock()
    }

    /// Where a caption of `restSize` (its size unzoomed) goes, and how much it
    /// is shrunk, when `visible` is the part of `screen` on the glass. Pure:
    /// everything scales by the same factor, so on the glass it is the same
    /// box at the same place at any zoom.
    static func placement(restSize: CGSize, visible: CGRect, screen: CGRect) -> (frame: CGRect, scale: CGFloat) {
        let k = visible.width / max(screen.width, 1)
        let size = CGSize(width: restSize.width * k, height: restSize.height * k)
        let frame = CGRect(x: visible.midX - size.width / 2,
                           y: visible.minY + visible.height * bottomInset,
                           width: size.width, height: size.height)
        return (frame, k)
    }

    /// Plays a caption track: each line at its second into the clip, counted
    /// from `delay` from now — when the clip is first heard. Only the lines
    /// are scheduled here — each `show` still ends itself, so a track nobody
    /// stops dies with its last line.
    static func play(_ lines: [CaptionLine], on screen: NSScreen, after delay: TimeInterval = 0,
                     asset: String? = nil) {
        track += 1
        trackAsset = asset
        clearRows(over: 0.15)   // a newer press: the old song's rows do not stay to be read
        let current = track
        let start = DispatchTime.now()
        for line in lines.map({ $0.ahead(earliest: -delay) }) {
            guard line.at + delay > 0 else { show(line.text, seconds: line.seconds, words: line.words, on: screen); continue }
            DispatchQueue.main.asyncAfter(deadline: start + (line.at + delay)) {
                guard current == track, SubtitlesSwitch.isOn else { return }
                show(line.text, seconds: line.seconds, words: line.words, on: screen)
            }
        }
    }

    /// The line in one colour. A timed line is drawn twice, the same layout in
    /// both: dimmed (`upcomingColor`) underneath, yellow on top behind the
    /// sweeping mask (`sweep`); an untimed one once, in white.
    static func label(_ text: String, color: NSColor) -> NSAttributedString {
        let centred = NSMutableParagraphStyle()
        centred.alignment = .center
        return NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: color,
            .paragraphStyle: centred,
        ])
    }

    /// The mask that uncovers the yellow copy: one band per wrapped line, its
    /// width following `SoundCaptions.fill` — the x of each offset measured
    /// with CoreText on the same string in the same box CATextLayer draws in,
    /// so the edge of the yellow sits on the letters, mid-word.
    private static func sweep(_ label: NSAttributedString, in size: CGSize,
                              path: [(t: TimeInterval, offset: Int)]) -> CALayer {
        let mask = CALayer()
        mask.frame = CGRect(origin: .zero, size: size)
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(label),
                                             CFRange(location: 0, length: 0),
                                             CGPath(rect: CGRect(origin: .zero, size: size), transform: nil), nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(location: 0, length: 0), &origins)
        let total = path.last?.t ?? 0
        for (k, line) in lines.enumerated() {
            let range = CTLineGetStringRange(line)
            let x = { (offset: Int) in CTLineGetOffsetForStringIndex(line, offset, nil) }
            let left = x(range.location), right = x(range.location + range.length)
            let widths = path.map { min(max(x(min(max($0.offset, range.location), range.location + range.length)) - left, 0), right - left) }
            // Bands meet halfway between baselines, so a descender or an
            // accent is never cut off by its neighbour's band.
            let top = k == 0 ? size.height : (origins[k - 1].y + origins[k].y) / 2
            let bottom = k == lines.count - 1 ? 0 : (origins[k].y + origins[k + 1].y) / 2
            let band = CALayer()
            band.backgroundColor = NSColor.black.cgColor
            band.anchorPoint = .zero
            band.position = CGPoint(x: origins[k].x + left, y: bottom)
            band.bounds = CGRect(x: 0, y: 0, width: widths.last ?? 0, height: top - bottom)
            if total > 0 {
                let grow = CAKeyframeAnimation(keyPath: "bounds.size.width")
                grow.values = widths
                grow.keyTimes = path.map { NSNumber(value: $0.t / total) }
                grow.duration = total
                grow.beginTime = CACurrentMediaTime()
                grow.fillMode = .both
                grow.isRemovedOnCompletion = false
                band.add(grow, forKey: "sweep")
            }
            mask.addSublayer(band)
        }
        return mask
    }

    static func show(_ text: String, seconds: TimeInterval, words: [TimeInterval] = [], on screen: NSScreen) {
        // Laid out once at the rest size; the zoom only ever scales it.
        let label = Self.label(text, color: words.isEmpty ? .white : upcomingColor)
        let maxTextWidth = screen.frame.width * 0.8
        let textSize = label.boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let padH: CGFloat = 26, padV: CGFloat = 12
        let rowSize = CGSize(width: ceil(textSize.width) + 2 * padH,
                             height: ceil(textSize.height) + 2 * padV)

        let stage = stage(on: screen)
        let box = CALayer()
        box.anchorPoint = CGPoint(x: 0.5, y: 0)
        box.bounds = CGRect(origin: .zero, size: rowSize)
        box.backgroundColor = NSColor.black.withAlphaComponent(pillAlpha).cgColor
        box.cornerRadius = 14
        let textLayer = CATextLayer()
        textLayer.string = label
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.contentsScale = screen.backingScaleFactor
        textLayer.frame = CGRect(x: padH, y: padV, width: ceil(textSize.width), height: ceil(textSize.height))
        box.addSublayer(textLayer)
        let path = SoundCaptions.fill(text, words: words, seconds: seconds)
        if !path.isEmpty {
            let lit = CATextLayer()
            lit.string = Self.label(text, color: litColor)
            lit.alignmentMode = .center
            lit.isWrapped = true
            lit.contentsScale = screen.backingScaleFactor
            lit.frame = textLayer.frame
            lit.mask = sweep(lit.string as! NSAttributedString, in: lit.frame.size, path: path)
            box.addSublayer(lit)
        }

        // The row that has no room leaves now, not when its time is up.
        while rows.count >= SoundCaptions.maxRows { leave(rows[0], over: rollSeconds) }

        let first = rows.isEmpty
        let row = Row(box: box, height: rowSize.height)
        let centre = stage.bounds.midX
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.position = CGPoint(x: centre, y: first ? stageFoot : stageFoot - rowTravel)
        box.opacity = 0
        stage.addSublayer(box)
        CATransaction.commit()
        rows.append(row)
        relay()
        fadeIn(box, over: first ? firstRowFade : rollSeconds)

        panel?.orderFrontRegardless()
        panel.map { setOnGlass(CGWindowID($0.windowNumber)) }
        startFollowing(screen)

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds - fadeOutSeconds)) {
            guard rows.contains(where: { $0 === row }) else { return }
            leave(row, over: fadeOutSeconds)
        }
    }

    /// The layer every row hangs from, made when the first row goes up and
    /// dropped with the last: a full-width canvas, so a row changing width or
    /// a row floating up never resizes the window under the others.
    private static func stage(on screen: NSScreen) -> CALayer {
        if let shown { return shown.stage }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let restSize = CGSize(width: screen.frame.width, height: screen.frame.height * 0.5)
        let view = NSView(frame: NSRect(origin: .zero, size: restSize))
        view.wantsLayer = true
        let stage = CALayer()
        stage.anchorPoint = .zero
        stage.bounds = CGRect(origin: .zero, size: restSize)
        stage.position = .zero
        view.layer?.addSublayer(stage)
        panel.contentView = view
        shown = (stage, restSize, screen.frame, .null)
        place(screen: screen)
        return stage
    }

    /// Slides every row to its place in the stack.
    private static func relay() {
        let ys = SoundCaptions.rollUp(heights: rows.map(\.height), gap: rowGap)
        for (row, y) in zip(rows, ys) { slide(row.box, toY: stageFoot + y) }
    }

    /// Explicit, from wherever the row is now: a roll that starts during the
    /// previous one must carry on from the screen, not jump.
    private static func slide(_ box: CALayer, toY y: CGFloat, over seconds: TimeInterval = rollSeconds) {
        let from = box.presentation()?.position ?? box.position
        let to = CGPoint(x: box.position.x, y: y)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.position = to
        CATransaction.commit()
        let roll = CABasicAnimation(keyPath: "position")
        roll.fromValue = NSValue(point: from)
        roll.toValue = NSValue(point: to)
        roll.duration = seconds
        roll.timingFunction = CAMediaTimingFunction(name: .easeOut)
        box.add(roll, forKey: "roll")
    }

    private static func fadeIn(_ box: CALayer, over seconds: TimeInterval) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        box.opacity = 1
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = seconds
        box.add(fade, forKey: "fade")
    }

    /// A row goes: a fade, where it stands, whatever is below it staying put.
    /// The rows above it, if it was not the top one, close the gap. The panel
    /// leaves the screen with its last row.
    private static func leave(_ row: Row, over seconds: TimeInterval) {
        guard let i = rows.firstIndex(where: { $0 === row }) else { return }
        let hadRowsAbove = i > 0
        rows.remove(at: i)
        if hadRowsAbove { relay() }
        let box = row.box
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            box.removeFromSuperlayer()
            if rows.isEmpty { panelDown() }
        }
        let from = box.presentation()?.opacity ?? box.opacity
        CATransaction.setDisableActions(true)
        box.opacity = 0
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = from
        out.toValue = 0
        out.duration = seconds
        box.add(out, forKey: "fade")
        CATransaction.commit()
    }

    private static func clearRows(over seconds: TimeInterval) {
        for row in rows { leave(row, over: seconds) }
    }

    /// The last row is gone. Unless another press got in during its fade.
    private static func panelDown() {
        guard rows.isEmpty else { return }
        panel?.orderOut(nil)
        panel?.contentView = NSView()
        stopFollowing()
    }

    /// Puts the caption on the slice that is on the glass now. A no-op while
    /// the slice has not moved, so the 30 Hz follow costs one zoom read a tick.
    private static func place(screen: NSScreen) {
        guard let panel, let current = shown else { return }
        let visible = ScreenZoom.visibleRect(in: screen.frame, of: screen)
        guard visible != current.visible else { return }
        shown?.visible = visible
        var (frame, k) = placement(restSize: current.restSize, visible: visible, screen: screen.frame)
        frame.origin.y -= stageFoot * k
        // No implicit animation: a 33 ms correction that eases reads as the
        // caption swimming after the pan.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        current.stage.setAffineTransform(CGAffineTransform(scaleX: k, y: k))
        CATransaction.commit()
        panel.setFrame(frame, display: true)
    }

    private static func startFollowing(_ screen: NSScreen) {
        follower?.invalidate()
        let timer = Timer(timeInterval: followInterval, repeats: true) { _ in place(screen: screen) }
        RunLoop.main.add(timer, forMode: .common)
        follower = timer
    }

    private static func stopFollowing() {
        follower?.invalidate()
        follower = nil
        shown = nil
        setOnGlass(nil)
    }

    /// Take the caption down early — `stop-all`, a re-tap, the 🛑 — along
    /// with any sung lines still to come.
    static func hide() {
        track += 1
        trackAsset = nil
        clearRows(over: 0.2)
    }

    /// One tile stopped (a re-tap, the panel, the tablet's `/sound/stopped`):
    /// its words go with its sound, at once — the rest of a song's lines too.
    /// Only if the caption is that tile's; a newer press's is left up.
    static func hide(asset: String) {
        guard trackAsset == asset else { return }
        hide()
    }

    private static func makePanel() -> CaptionPanel {
        let panel = CaptionPanel(contentRect: .zero,
                                 styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = windowLevel
        // A name the window list shows, so another process (addons' ⌥⇧
        // ShareZoom) can find this window to leave it out of its own capture.
        panel.title = "Victor Effects caption"
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    /// Built at launch rather than at the first press, so the window exists —
    /// and is in the window list — before anything that wants to exclude it
    /// from a capture builds its filter.
    static func prepare() {
        if panel == nil { panel = makePanel() }
    }
}
