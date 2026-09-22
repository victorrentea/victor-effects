import Foundation

/// Single source of truth mapping a tablet sound file to the Mac overlay effect
/// it should trigger. The tablet no longer decides which sound drives which
/// effect — it just reports every press (`/sound/pressed/<file>`) and stop
/// (`/sound/stopped/<file>`), and the Mac looks the mapping up here. Change a
/// mapping (or add a brand-new effect) by editing this file and rebuilding the
/// Mac app — no tablet rebuild/redeploy needed.
///
/// The mapped strings are effect names understood by `AppDelegate`'s `onEffect`
/// switch (e.g. "explosion", "blood-drip", "rainbow/stop").
///
/// Note: `02_siren.mp3` is intentionally absent — the siren maps to the alarm
/// overlay (`/alarm/start`,`/alarm/stop`), a distinct toggled overlay with its
/// own lifecycle, and stays special-cased on the tablet.
enum SoundEffectMap {
    /// Effect to start when a sound button is pressed.
    static let onPress: [String: String] = [
        "03_explosion.mp3":      "explosion",
        "90_breaking-glass.mp3": "broken-glass",
        "59_game_over.mp3":      "game-over",
        "15_flatline.mp3":       "pulse",
        "27_clapping.mp3":       "applause",
        "42_saxophone.mp3":      "spiral-hearts",
        "89_fireworks.mp3":      "fireworks",
        "08_scream_man.mp3":     "fear",
        "22_minigun.mp3":        "bullet-holes",
        "65_school_bell.mp3":    "fire-alarm",
        "10_red_phone.mp3":      "phone-ring",
        "19_fail.mp3":           "fail",
        // 20_fail2.mp3 is NOT here any more. It is still #19's second take
        // (`AlternatingSounds`), but since the ⛈️ storm took over square #20 it
        // is no longer a tile anybody can press — and the press path reports the
        // KEY of a pair, never the file that was actually played, so the entry
        // could only ever have fired for a direct press that can no longer
        // happen. Leaving it would have put a ⭐ on an asset with no tile, which
        // `SoundEffectMapDriftTests` reads as a renamed or deleted mp3.
        "78_projector.mp3":      "sepia",
        "67_sfx_109.mp3":        "brother",
        "70_cavalry.mp3":        "cavalry",
        "73_counter_strike.mp3": "counter-strike",
        "76_sfx_118.mp3":        "wasnt-me",
        // Tile 69 (👻 scream ghost) is the Scary Movie "wazzuuup" bit, so the
        // overlay is the mask that says it: the tongue-out Ghostface leaning in
        // from the bottom-left corner for the length of the clip. Press-driven
        // and self-terminating, so no onStop entry — nothing here loops.
        "69_scream_ghost.mp3":   "wazzup",
        // Tile 71 (🔁 "one more time"): the replay arrow off the tile's own
        // artwork is sketched across the desktop in cyan. Silent on this side —
        // the clip plays down the ordinary routed path — and it self-terminates
        // at the clip's length, so no onStop entry is needed.
        "71_one_more_time.mp3":  "sketch-arrow",
        // Tile 7 (☎️ animated phone): 🔴 the big red button grows out of the
        // pointer and waits to be PRESSED. The only effect in the catalogue that
        // deliberately outlives its clip — the clip is a couple of seconds, the
        // button is a prop Victor talks over and then presses — so there is no
        // onStop entry: the tablet's /sound/stopped must NOT take it away. It
        // ends on the click, on Escape, on a stop-all, or on its own 20 s
        // deadline (`RedButton.maxLifetime`), which is the self-termination rule
        // for an effect with no clip length to inherit.
        "07_animated_phone.mp3": "red-button",
        // Tile 18 (🪚 chainsaw): the mouse pointer itself becomes a running
        // chainsaw for the length of the clip. Press starts it, stop puts the
        // real pointer back (see onStop) — and the effect self-stops at the
        // clip's length regardless, because a lost /sound/stopped here would
        // leave the desktop with no visible cursor at all.
        "18_chainsaw.mp3":       "chainsaw",
        // Tile 11 (🔥 fire): the same cursor-replacement idea as the chainsaw —
        // the pointer becomes a flame for the length of the clip. Two things are
        // its own: Escape puts it out early (the clip is 36 s, far too long to
        // sit through if it lands at the wrong moment), and the scroll wheel
        // resizes it while it burns. onStop is still mapped: the tablet's stop is
        // the polite exit, the clip's length is the guaranteed one.
        "11_fire.mp3":           "fire",
        // Tile 6 (©️ the Pink Panther theme): the tile's own artwork is
        // Inspector Clouseau stooped over a magnifying glass, so the desktop
        // gets the glass. It follows the pointer and magnifies only what is
        // inside its lens, for the length of the clip; the stop below is the
        // polite exit, the clip's length is the guaranteed one.
        "06_copyright_cartoon.mp3": "magnifier",
        "29_gangnam_style.mp3":  "gangnam",
        "41_love_hearts.mp3":    "love-hands",
        "55_star_wars.mp3":      "star-wars",
        "37_rainbow.mp3":        "rainbow",
        "49_wrong.mp3":          "wrong-x",
        "50_gong.mp3":           "gong",
        "26_drum.mp3":           "drum-roll",
        "44_laugh_emoji.mp3":    "laugh",
        "40_joker.mp3":          "blood-drip",
        // Tile 46 IS the Christmas tile — Michael Bublé's "It's Beginning to Look
        // a Lot Like Christmas", snow already falling in the artwork. The desktop
        // now snows for as long as the clip plays.
        "46_michael_buble.mp3":  "snow",
        // Tile 20 (⛈️ storm) — the square #19's second trombone take used to
        // hold. Four clouds slide in from both sides onto the top edge, the
        // desktop darkens under them and it rains for the length of the clip,
        // with lightning on the thunder rolls. Press-driven on purpose: the
        // rolls in this recording swell over ~300 ms, so nothing here needs the
        // sample accuracy that puts the FBI knock on the play path — and this
        // way the desktop still storms when the tablet plays the clip through
        // its own speaker and the Mac never sees a /sound/play.
        "20_storm.mp3":          "storm",
        // Tile 34: a phoenix rises up the desktop with its cry. The tablet's
        // paired `34_phoenix.mp3` is silent; the real sound (`phoenix.mp3`) is a
        // Mac-owned resource played inside showPhoenix and faded out in unison
        // with the visual fade. The routed /sound/play path is neutralized in
        // onSoundPlay (like iris) so the silent clip isn't played.
        "34_phoenix.mp3":        "phoenix",
        // Tile 31 repurposed (was Tarzan): 🕳️ iris close. The paired mp3 keeps
        // its id "31_tarzan.mp3" for protocol/manifest stability but is now a
        // silent clip — the shrinking-circle blackout is the whole effect. A
        // second press toggles it back off (showIrisClose handles the cancel),
        // which is why it stays out of onSoundPlay's special cases (no
        // double-trigger).
        "31_tarzan.mp3":         "iris",
        // Tile 80 (🍌 badumtss): 🟡 animated minion CROWD, SILENT. The press path
        // drives the looping crowd; onSoundPlay neutralizes the routed clip (plays
        // nothing) and returns the effect's duration so the NON-restartable tile
        // stays "playing" — a re-tap within that window fires /effect/stop-all,
        // which stops the tracked minion layer (stop-on-re-tap).
        "80_badumtss.mp3":       "minion",
        // Tile 52 (🪚 saw) is intentionally absent: the desktop saw animation was
        // removed, leaving only the sound. The real saw SFX (`52_saw.mp3`) still
        // plays normally on the routed /sound/play path (it was never special-cased
        // in onSoundPlay), so dropping the press→visual mapping here keeps the
        // sound but fires no overlay.
        // 61_dinner.mp3 is NOT here either, for the same reason: the clip is now
        // a kitchen timer whose BING lands 2.695s in, and the ⏲️ microwave's door
        // must swing open on exactly that edge. Sound and visual therefore start
        // from one call on the routed /sound/play path (onSoundPlay); mapping the
        // press too would open a second door with no bell behind it.
        // 13_heartbeat.mp3 is NOT here either. The zoom has to peak ON each
        // thump, and the press path cannot know when the thump happens: it is a
        // different HTTP request from the one that starts the audio, and the
        // visual then waited on an async screencapture before starting its clock
        // — so the beat landed a few hundred variable ms late, every time. Driven
        // from the routed /sound/play path (onSoundPlay), which plays the clip and
        // stamps the pulse clock in the same call; mapping the press too would
        // double-trigger it.
        // 64_fbi.mp3 is NOT here either, for the heartbeat's reason: the first
        // door bang is 22ms into the clip, so the visual must both own the audio
        // and already hold the screen capture when it starts. Driven from the
        // routed /sound/play path (onSoundPlay); mapping the press too would
        // double-trigger it.
        // 25_dark_door.mp3 is NOT here either, for the FBI knock's reason: the
        // first of its seven knocks is 24ms into the clip, so the visual must
        // both own the audio and already hold the screen capture when it starts.
        // Driven from the routed /sound/play path (onSoundPlay); mapping the
        // press too would double-trigger it. (Until 2026-09-11 the tile was
        // mentioned NOWHERE in the app and simply played a clip over an
        // untouched desktop.)
        // 51_beethoven.mp3 is NOT here, for the heartbeat's reason: the motif is
        // six hits 0.11s apart inside the clip, and the screen has to lunge ON
        // each of them. Driven from the routed /sound/play path (onSoundPlay),
        // which plays the clip and stamps the zoom clock in one call; mapping the
        // press too would double-trigger it.
        // 23_radar.mp3 is NOT here: the Mac owns the radar SFX, so the sonar
        // effect is driven from the routed /sound/play path (onSoundPlay),
        // which plays the beep-synced audio itself — mapping the press too
        // would double-trigger it.
    ]

    /// Effect to stop when a sound finishes / is stopped (long-running effects:
    /// looping overlays, or emissions like spiral-hearts that otherwise keep
    /// spawning/lingering past the sound).
    static let onStop: [String: String] = [
        "15_flatline.mp3":       "pulse/stop",
        "42_saxophone.mp3":      "spiral-hearts/stop",
        "41_love_hearts.mp3":    "love-hands/stop",
        "37_rainbow.mp3":        "rainbow/stop",
        "67_sfx_109.mp3":        "brother/stop",
        "29_gangnam_style.mp3":  "gangnam/stop",
        "06_copyright_cartoon.mp3": "magnifier/stop",
        "55_star_wars.mp3":      "star-wars/stop",
        "26_drum.mp3":           "drum-roll/stop",
        "59_game_over.mp3":      "game-over/stop",
        "46_michael_buble.mp3":  "snow/stop",
        "20_storm.mp3":          "storm/stop",
        "18_chainsaw.mp3":       "chainsaw/stop",
        "11_fire.mp3":           "fire/stop",
    ]

    /// Sounds whose desktop visual is driven from the routed `/sound/play` path
    /// (`EffectsEngine.playSound`) instead of the press path, because their cue
    /// sits at a fixed offset INSIDE the clip and a separately-clocked visual
    /// slides off it. They are deliberately absent from [onPress] (mapping them
    /// there would double-trigger), but from the room's point of view they are
    /// exactly as visual as the rest — so they have to be listed by hand.
    /// Keep in step with the special cases in `EffectsEngine.playSound`.
    ///
    /// The VALUE is the effect's name, the same spelling `fireEffect` answers
    /// to, so `EffectsCatalog.effectName(forAsset:)` can say what the ⭐ on the
    /// tile actually promises instead of only that there is one. Nothing calls
    /// `fireEffect` with it on the routed path — `playSound` runs the animation
    /// directly, because it also owns the audio — but `SoundEffectMapDriftTests`
    /// checks the name against that switch anyway: a name that is not a real
    /// effect is a name that lies to the client.
    static let playPathVisuals: [String: String] = [
        "23_radar.mp3":       "sonar",       // 🛰️ sonar (owns its beep-synced audio)
        "53_rain.mp3":        "money",       // 💸 money rise
        "61_dinner.mp3":      "microwave",   // ⏲️ door on the BING, 2.695 s in
        "13_heartbeat.mp3":   "heartbeat",   // 💓 zoom peaking on each measured onset
        "64_fbi.mp3":         "fbi-knock",   // 🚪 lurch on each bang, the first 22 ms in
        "25_dark_door.mp3":   "dark-door",   // 🚪 punch-in on each of seven knocks
        "51_beethoven.mp3":   "beethoven",   // 🎼 six hits 0.11 s apart
    ]

    /// Every sound that makes something happen ON THE DESKTOP when its tile is
    /// pressed. Now just the catalogue's answer, kept as a name because the
    /// drift tests and the legacy `GET /sound/effects` route read like English
    /// with it.
    static var visualAssets: Set<String> { Set(EffectsCatalog.assets) }

    /// The effect name a pressed sound should start, or nil if the sound has no
    /// paired visual.
    static func pressEffect(for soundFile: String) -> String? { onPress[soundFile] }

    /// The effect name a stopped sound should stop, or nil.
    static func stopEffect(for soundFile: String) -> String? { onStop[soundFile] }
}
