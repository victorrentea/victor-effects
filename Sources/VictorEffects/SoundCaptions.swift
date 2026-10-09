import AppKit
import QuartzCore

/// Closed captions for the soundboard: a half-transparent subtitle at the bottom
/// of the overlay screen, for whoever in the room — or on the call — cannot hear
/// the joke. Songs show the line that is sung (♪ … ♪), everything else names the
/// noise the way TV captions do ([wolf howling]).
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
        "05_guess_whos_back.mp3":     "♪ Guess who's back, back again ♪",
        "06_copyright_cartoon.mp3":   "♪ Pink Panther theme ♪",
        "07_animated_phone.mp3":      "\"What does this button do?\"",
        "08_scream_man.mp3":          "[man screaming]",
        "09_ave_maria.mp3":           "♪ Ave Maria ♪",
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
        "28_who_let_dogs_out.mp3":    "♪ Who let the dogs out? ♪",
        "29_gangnam_style.mp3":       "♪ Oppa Gangnam Style ♪",
        "30_cow.mp3":                 "[cow mooing]",
        "31_tarzan.mp3":              "[Tarzan yell]",
        "32_sheep.mp3":               "[sheep bleating]",
        "33_yee_har.mp3":             "\"Yee-haw!\"",
        "34_phoenix.mp3":             "[phoenix screeching]",
        "35_cant_touch_this.mp3":     "♪ Can't touch this ♪",
        "36_bad_habits.mp3":          "♪ My bad habits lead to late nights ♪",
        "37_rainbow.mp3":             "♪ Somewhere over the rainbow ♪",
        "38_imagine.mp3":             "♪ Imagine all the people ♪",
        "39_skull_boom.mp3":          "[boom]",
        "40_joker.mp3":               "[maniacal laughter]",
        "41_love_hearts.mp3":         "[romantic music]",
        "42_saxophone.mp3":           "[sultry saxophone]",
        "43_dun.mp3":                 "[dun dun DUNNN]",
        "44_small_dog.mp3":           "[small dog yapping]",
        "45_the_mask.mp3":            "\"Somebody stop me!\"",
        "46_michael_buble.mp3":       "♪ It's beginning to look a lot like Christmas ♪",
        "47_dog_bark.mp3":            "[dog barking]",
        "48_rooster.mp3":             "[rooster crowing]",
        "49_wrong.mp3":               "[wrong-answer buzzer]",
        "50_gong.mp3":                "[gong]",
        "51_beethoven.mp3":           "♪ Da-da-da-DUM ♪",
        "52_saw.mp3":                 "[sawing]",
        "53_rain.mp3":                "[money raining]",
        "54_piano.mp3":               "[piano music]",
        "55_star_wars.mp3":           "♪ Star Wars theme ♪",
        "56_door_open.mp3":           "[door creaking open]",
        "57_checkmark.mp3":           "[success chime]",
        "58_cat.mp3":                 "[cat meowing]",
        "59_game_over.mp3":           "\"Game over\"",
        "60_sfx_100.mp3":             "[dramatic singing]",
        "61_hallelujah.mp3":          "♪ Hallelujah ♪",
        "62_lionel_richie.mp3":       "♪ Hello, is it me you're looking for? ♪",
        "63_air_horn.mp3":            "[air horn]",
        "64_fbi.mp3":                 "\"FBI! Open up!\"",
        "65_school_bell.mp3":         "[bell ringing]",
        "66_toilet.mp3":              "[toilet flushing]",
        "67_sfx_109.mp3":             "\"Eww, brother, eww!\"",
        "68_pig.mp3":                 "[pig oinking]",
        "69_scream_ghost.mp3":        "\"Wazzuuup!\"",
        "70_cavalry.mp3":             "[cavalry bugle charge]",
        "71_one_more_time.mp3":       "♪ One more try… ♪",
        "72_if_tomorrow.mp3":         "♪ If tomorrow never comes ♪",
        "73_counter_strike.mp3":      "\"Counter-Terrorists win\"",
        "74_oops.mp3":                "♪ Oops, I did it again ♪",
        "75_sfx_117.mp3":             "\"May I have your attention, please?\"",
        "76_sfx_118.mp3":             "♪ It wasn't me ♪",
        "77_maui.mp3":                "♪ You're welcome! ♪",
        "78_projector.mp3":           "[film projector whirring]",
        "79_door.mp3":                "[door slams]",
        "81_let_it_be.mp3":           "♪ Let it be ♪",
        "81b_let_go.mp3":             "♪ Let go, let go ♪",
        "82_over_and_out.mp3":        "\"Over and out.\"",
        "83_yummy.mp3":               "♪ Yummy, yummy, yummy ♪",
        "84_eclipse.mp3":             "[epic music]",
        "85_joy.mp3":                 "♪ Ode to Joy ♪",
        "86_doorbell.mp3":            "[doorbell]",
        "87_grenade.mp3":             "[grenade explodes]",
        "88_all_you_need_is_love.mp3": "♪ All you need is love ♪",
        "89_fireworks.mp3":           "[fireworks]",
        "90_breaking-glass.mp3":      "[glass shattering]",
        "91_sinking.mp3":             "[ship sinking]",
    ]

    /// Tiles that make no sound of their own (the minion crowd is a silent
    /// placeholder on the client) — a caption there would describe nothing.
    static let silent: Set<String> = ["80_badumtss.mp3"]

    /// The caption for a press, or nil for a silent tile. A tile added to
    /// `tiles.json` before anyone wrote its line still gets one, made from its
    /// filename (`56_door_open.mp3` → `[door open]`): a vague caption beats a
    /// silent one for someone who cannot hear the room.
    static func caption(for asset: String) -> String? {
        if silent.contains(asset) { return nil }
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

/// The subtitle itself: one borderless panel, reused, centred near the bottom of
/// the visible slice of the overlay screen. The whole caption — pill and text —
/// sits at **50 % opacity** so it reads without covering the slide under it.
///
/// A new caption replaces the one on screen; `hide()` is what `stopAll` calls.
/// Neither is what ends it: every `show` schedules its own removal (the
/// self-termination rule), and a removal that finds a newer caption up does
/// nothing.
enum CaptionOverlay {
    static let opacity: Float = 0.5
    static let fontSize: CGFloat = 36
    /// Height of the gap under the caption, as a share of the visible height —
    /// low enough to stay off the slide body (5 %, ~56 pt on the Retina).
    static let bottomInset: CGFloat = 0.05

    private static var panel: NSPanel?
    private static var generation = 0

    static func show(_ text: String, seconds: TimeInterval, on screen: NSScreen) {
        generation += 1
        let gen = generation

        let visible = ScreenZoom.visibleRect(in: screen.frame, of: screen)
        let label = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: NSColor.white,
        ])
        let maxTextWidth = visible.width * 0.8
        let textSize = label.boundingRect(
            with: NSSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]).size
        let padH: CGFloat = 26, padV: CGFloat = 12
        let size = NSSize(width: ceil(textSize.width) + 2 * padH,
                          height: ceil(textSize.height) + 2 * padV)
        let frame = NSRect(x: visible.midX - size.width / 2,
                           y: visible.minY + visible.height * bottomInset,
                           width: size.width, height: size.height)

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = NSView(frame: NSRect(origin: .zero, size: size))
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        layer.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        layer.cornerRadius = 14
        let textLayer = CATextLayer()
        textLayer.string = label
        textLayer.alignmentMode = .center
        textLayer.isWrapped = true
        textLayer.contentsScale = screen.backingScaleFactor
        textLayer.frame = CGRect(x: padH, y: padV, width: ceil(textSize.width), height: ceil(textSize.height))
        layer.addSublayer(textLayer)

        // A fresh view per caption, so a fade still running on the previous
        // one (the pre-press stop-all hides it) cannot touch this one.
        panel.contentView = view
        panel.setFrame(frame, display: true)
        layer.opacity = opacity
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = opacity
        fadeIn.duration = 0.15
        layer.add(fadeIn, forKey: "fadeIn")
        panel.orderFrontRegardless()

        let fadeOut: TimeInterval = 0.4
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, seconds - fadeOut)) {
            guard gen == generation else { return }
            fade(over: fadeOut, generation: gen)
        }
    }

    /// Take the caption down early — `stop-all`, a re-tap, the 🛑.
    static func hide() {
        guard let panel, panel.isVisible else { return }
        generation += 1
        fade(over: 0.2, generation: generation)
    }

    private static func fade(over seconds: TimeInterval, generation gen: Int) {
        guard let panel, let layer = panel.contentView?.layer else { return }
        // Explicit, not implicit: a view's backing layer has its implicit
        // animations switched off, so a bare `opacity = 0` would just blink out.
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            guard gen == generation else { return }
            panel.orderOut(nil)
        }
        let out = CABasicAnimation(keyPath: "opacity")
        out.fromValue = layer.presentation()?.opacity ?? layer.opacity
        out.toValue = 0
        out.duration = seconds
        layer.opacity = 0
        layer.add(out, forKey: "fadeOut")
        CATransaction.commit()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}
