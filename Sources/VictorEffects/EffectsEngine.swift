import AppKit
import Foundation

/// Everything the app can be asked to *do*, behind one object.
///
/// This is the `onEffect` / `onSoundPlay` half of the app it was extracted from,
/// lifted out of an AppDelegate that also owned transcription, hotspots and a
/// break timer. Two things did NOT come along: `training-end` and
/// `focus-playlist`, which are training-session features and stayed with the
/// session; and the coffee *payoff*, which now leaves as a webhook (see
/// `CoffeePourMonitor`).
final class EffectsEngine {
    let overlayPanel: OverlayPanel
    let animator: EmojiAnimator
    let progressBar: ProgressBarOverlay

    /// Last `/ping`, for the watchdog below.
    private var lastPingAt: Date?
    private var soundWatchdog: Timer?

    /// What `/state` reports about the current sound.
    private(set) var playing: (asset: String, durationMs: Int, startedAt: Date)?

    // MARK: whip

    /// Lazy: the whip allocates a panel and decodes five crack sounds, and most
    /// sessions never press ⌃W.
    private var whipController: WhipController?
    var whip: WhipController? { whipController }
    var whipIsShowing: Bool { whipController?.isShowing ?? false }

    init(overlayPanel: OverlayPanel) {
        self.overlayPanel = overlayPanel
        guard let hostLayer = overlayPanel.contentView?.layer else {
            fatalError("Overlay panel content view has no layer")
        }
        animator = EmojiAnimator(hostLayer: hostLayer)
        // The bar is a CALayer on the same host layer as the effects: a plain
        // subview on this manually-populated layer-backed view does not
        // composite.
        progressBar = ProgressBarOverlay(hostLayer: hostLayer)
    }

    // MARK: - Lifecycle

    func startWatchdog() {
        // If a client stops pinging (crash, network drop) while a routed sound
        // it started is playing, stop it — a long sound would otherwise blare
        // on with no way to stop it from the device that started it. Only a
        // sound that HAD a pinging client behind it: see `PingWatchdog`.
        soundWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, SoundManager.shared.isTabletSoundPlaying,
                  PingWatchdog.shouldStop(now: Date(), lastPing: self.lastPingAt,
                                          soundStartedAt: SoundManager.shared.tabletSoundStartedAt)
            else { return }
            effectsInfo("Client ping lost >\(Int(PingWatchdog.timeout))s — stopping routed sound")
            SoundManager.shared.stopTabletSound()
            self.playing = nil
        }
    }

    // MARK: - /ping and /state

    func pingJSON(panelMonitor: Bool) -> String {
        lastPingAt = Date()
        let vol = Int((SoundManager.shared.currentTabletVolume * 100).rounded())
        // A FLAT object, and no recomputation. The app that proxies this route
        // splices its own keys in by string manipulation before the closing
        // brace, so a nested object at the top level would corrupt the merged
        // body; and it allows this route ~1.5 s, which is less than a cold
        // sounds hash takes — hence the cached, never-blocking accessor.
        return "{\"ok\":true,\"app\":\"victor-effects\",\"effectsVersion\":\"\(MenuBar.BUILD_TIME)\","
            + "\"soundsHash\":\"\(SoundsManifest.cachedCombinedHash)\",\"tilesHash\":\"\(TilesManifest.tilesHash)\","
            // Cheap (a hash of ~43 short strings, no I/O), so unlike soundsHash
            // it needs no cache to stay inside the proxy's 1.5 s.
            + "\"effectsHash\":\"\(EffectsCatalog.effectsHash)\","
            // Same reasoning as effectsHash, and the same cost: the dots the
            // tablet draws are these numbers, so it needs to know they moved —
            // including when the move came from the Mac's own panel.
            + "\"usageHash\":\"\(UsageCounts.hash)\","
            + "\"tabletVolume\":\(vol),\"panelMonitor\":\(panelMonitor)}"
    }

    func stateJSON(panelMonitor: Bool, panelVisible: Bool) -> String {
        let playingJSON: String
        if let p = playing, SoundManager.shared.isTabletSoundPlaying {
            playingJSON = "{\"asset\":\"\(p.asset)\",\"durationMs\":\(p.durationMs),"
                + "\"startedAt\":\(Int(p.startedAt.timeIntervalSince1970 * 1000))}"
        } else {
            playingJSON = "null"
        }
        let effects = animator.activeEffectNames.map { "\"\($0)\"" }.joined(separator: ",")
        return "{\"playing\":\(playingJSON),\"activeEffects\":[\(effects)],"
            + "\"whipShowing\":\(whipIsShowing),"
            + "\"panelMonitor\":\(panelMonitor),\"panelVisible\":\(panelVisible),"
            + "\"config\":\(EffectsConfig.shared.asJSON)}"
    }

    // MARK: - Effects

    func spawnEmoji(_ emoji: String, count: Int, glow: String?) {
        if isSuspended { effectsInfo("⏸️ suspended — dropping \(count)× \(emoji)"); return }
        overlayPanel.refreshScreenFrame()
        for _ in 0..<count { animator.spawnEmoji(emoji, glow: glow) }
    }

    // MARK: - ⏸️ Suspension (Walkie Talkie's wheel-held crop)

    private var suspension = EffectsSuspension()

    var isSuspended: Bool { suspension.isSuspended(at: Date().timeIntervalSince1970) }

    /// Clear the screen and keep it clear for `seconds` — see `EffectsSuspension`
    /// for why this is a deadline and not a flag. Returns the seconds granted.
    @discardableResult
    func suspendEffects(seconds: TimeInterval) -> TimeInterval {
        let granted = suspension.suspend(for: seconds, at: Date().timeIntervalSince1970)
        // Clear what is already on screen as well as holding back what is next:
        // "suspend" with a storm still raging would be half the job.
        stopAll()
        effectsInfo("⏸️ effects suspended for \(String(format: "%.1f", granted))s")
        return granted
    }

    func resumeEffects() {
        guard isSuspended else { return }
        suspension.resume()
        effectsInfo("▶️ effects resumed")
    }

    func startProgressBar(seconds: Int, rider: String?) {
        overlayPanel.refreshScreenFrame()
        progressBar.start(seconds: TimeInterval(seconds), rider: rider)
    }

    func cancelProgressBar() { progressBar.cancel() }

    func startAlarm() {
        overlayPanel.refreshScreenFrame()
        animator.startAlarmOverlay()
    }

    func stopAlarm() { animator.stopAlarmOverlay() }

    /// Run one effect by its route name, with the Bluetooth visual delay that
    /// keeps it in sync with a sound that was just routed here.
    func runEffect(_ name: String) {
        // ⏸️ The two control words are always heard — a suspend that could not be
        // lifted, or extended, would be the exact trap the deadline exists to
        // avoid. `stop-all` too: "clear the screen" can never be the thing a
        // clear screen refuses.
        // `/effect/suspend/<seconds>` — the caller says how long it needs. Read
        // before the gate below, so an already-suspended app can still be asked
        // to hold longer.
        if name.hasPrefix("suspend/"), let n = Double(name.dropFirst("suspend/".count)) {
            suspendEffects(seconds: n)
            return
        }
        switch name {
        case "suspend":
            suspendEffects(seconds: EffectsSuspension.defaultSeconds)
            return
        case "resume":
            resumeEffects()
            return
        case "stop-all":
            break
        default:
            if isSuspended {
                effectsInfo("⏸️ suspended — dropping effect '\(name)'")
                return
            }
        }
        // If a routed sound was just started on THIS Mac with Bluetooth
        // compensation, delay the paired visual by the same amount so it stays
        // in sync with the silence-prepended audio. 0 for stop/utility signals
        // and on non-Bluetooth output → fires now.
        //
        // The green-flash is the VISUAL half of an audible "the link works" tap,
        // and the Mac plays that with the wake-up silence prepended — so it
        // carries the same compensation as the beep it belongs to. Firing it now
        // lit the border up to 1.2 s before the sound reached the speaker, which
        // reads as two separate events.
        let comp = name == "green-flash"
            ? SoundTimingConfig.shared.currentBluetoothCompensation
            : SoundManager.consumePendingVisualCompensation(for: name)
        let fire: () -> Void = { [weak self] in self?.fireEffect(name) }
        if comp > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + comp, execute: fire)
        } else {
            fire()
        }
    }

    private func fireEffect(_ name: String) {
        overlayPanel.refreshScreenFrame()
        switch name {
        case "earthquake":    animator.showBrokenGlass(playSound: false)
        case "explosion":     animator.showExplosionGif(playSound: false)
        case "game-over":     animator.showGameOver()
        case "game-over/stop": animator.stopGameOver()
        case "broken-glass":  animator.showBrokenGlass(playSound: false)
        case "pulse":         animator.startPulseOverlay(playSound: false)
        case "pulse/stop":    animator.stopPulseOverlay()
        case "applause":      animator.showApplause(playSound: false)
        case "applause/stop": animator.stopApplause()
        case "heartbeat":     animator.showHeartbeat()
        // 🔍 Tile #6 (Pink Panther): a drawn magnifying glass rides the pointer
        // and magnifies ONLY what is inside its lens, for the length of the clip.
        case "magnifier":     animator.showMagnifier()
        case "magnifier/stop": animator.stopMagnifier()
        case "spiral-hearts": animator.showSpiralHearts()
        case "spiral-hearts/stop": animator.stopSpiralHearts()
        case "fireworks":     animator.showFireworks(playSound: false)
        case "fear":          animator.showFear(playSound: false)
        case "fail":          animator.showFail(playSound: false)
        case "wazzup":        animator.showWazzup(playSound: false)
        case "blood-drip":    animator.showBloodDrip(playSound: false)
        case "sonar":         animator.showSonar(playSound: true)
        case "sepia":         animator.showSepia(playSound: false)
        case "fire-alarm":    animator.showFireAlarm(playSound: false)
        case "bullet-holes":  animator.showBulletHoles()
        case "phone-ring":    animator.showPhoneRing(playSound: false)
        case "fbi-knock":     animator.showFbiKnock(playSound: false)
        case "dark-door":     animator.showDarkDoor(playSound: false)
        // Beethoven owns its audio for the same reason the microwave does — the
        // cue is INSIDE the clip — so unlike every other silent effect this one
        // is fired WITH sound.
        case "beethoven":     animator.showBeethoven(playSound: true)
        case "brother":       animator.showBrother(playSound: false)
        case "brother/stop":  animator.stopBrother()
        case "gangnam":       animator.showGangnam(playSound: false)
        case "gangnam/stop":  animator.stopGangnam()
        case "love-hands":    animator.showLoveHands(playSound: false)
        case "love-hands/stop": animator.stopLoveHands()
        case "star-wars":     animator.showStarWars(playSound: false)
        case "star-wars/stop": animator.stopStarWars()
        case "gong":          animator.showGong(playSound: false)
        case "rainbow":       animator.showRainbow(playSound: false)
        case "rainbow/stop":  animator.stopRainbow()
        case "snow":          animator.showSnow()
        case "snow/stop":     animator.stopSnow()
        case "storm":         animator.showStorm()
        case "storm/stop":    animator.stopStorm()
        case "cavalry":       animator.showCavalry(playSound: false)
        case "counter-strike": animator.showCounterStrike(playSound: false)
        case "wasnt-me":      animator.showWasntMe(playSound: false)
        case "chainsaw":      animator.showChainsawCursor()
        case "chainsaw/stop": animator.stopChainsawCursor()
        case "fire":          animator.showFireCursor(playSound: false)
        case "fire/stop":     animator.stopFireCursor()
        // Like the sonar: the door's cue lives INSIDE the clip, so the effect
        // owns its own audio rather than trusting a separate routed play to land
        // on the same millisecond.
        case "microwave":     animator.showMicrowave(playSound: true)
        // Like the microwave: the minions' cue sits 23.83 s inside the combined
        // clip, so the effect owns its audio — the routed /sound/play path plays
        // the clip and starts the visual itself; a direct trigger plays both.
        case "universal-minions": animator.showUniversalMinions(playSound: true)
        // Same effect, audio started 1 s before the cue — for checking the
        // animation without sitting through the 24 s fanfare.
        case "universal-minions/preview":
            animator.showUniversalMinions(playSound: true, skip: EmojiAnimator.universalMinionsCue - 1)
        case "wrong-x":       animator.showWrongX(playSound: false)
        case "drum-roll":     animator.showDrumRoll(playSound: false)
        case "drum-roll/stop": animator.stopDrumRoll()
        case "phoenix":       animator.showPhoenix()
        case "money":         animator.showMoneyRise()
        case "iris":          animator.showIrisClose()
        // 📺 The tail of game-over, addressable on its own so the closing can be
        // rehearsed without sitting through the picture and the clip first.
        case "crt-shutdown":  animator.showCrtShutdown()
        case "minion":        animator.showMinion()
        case "elephant":      animator.showElephant()
        case "elephant/stop": animator.stopElephant()
        case "claude-peek":   animator.showClaudePeek()
        case "claude-peek/stop": animator.stopClaudePeek()
        case "heart":         animator.spawnEmoji("❤️")
        case "confetti":      animator.spawnConfetti()
        case "corner-confetti": animator.spawnCornerConfetti()
        case "zorro":         animator.showZorro()
        case "laugh":         animator.showLaugh()
        case "sketch-arrow":  animator.showSketchArrow()
        case "coffee":
            // Spawn a few rising ☕ so the pour can be exercised headlessly —
            // move the cursor onto one: it becomes a pot and fills the cup,
            // which pops (small) when full. Three at once is NOT a salvo (that
            // needs more than three inside one second), so these fill and pop
            // rather than shake and burst.
            for emoji in EffectsConfig.shared.chargeEmoji.prefix(1) {
                for _ in 0..<3 { animator.spawnEmoji(emoji) }
            }
        case "coffee/storm":
            // A salvo past the more-than-3-per-second threshold: the cups rise
            // like any other, but explosions are ARMED — touch one with the
            // pot and it grows, shakes and bursts. Disarms on its own once the
            // screen is empty (or 10 s after the salvo).
            animator.spawnCoffeeStormForTest()
        case "coffee/pop":
            // Skip the salvo and the pot entirely: burst a ☕ mid-screen and fire
            // the same event a real payoff fires, so the whole chain can be
            // checked headlessly.
            if let at = animator.popCoffeeForTest() {
                EventWebhook.coffeePopped(at: at)
            }
        case "green-flash":
            // Link-confirmation: a green screenshot-style border.
            if let screen = EdgeFlash.builtInScreen {
                EdgeFlash.flash(on: screen, duration: 4.5, color: .systemGreen)
            }
        case "click":
            // Audible tap, paired with the green-flash as "the link works".
            SoundManager.shared.playOverlapping("click.wav", volume: 0.7)
        case "whip":
            toggleWhip()
        case "whip/crack":
            whipController?.forceCrack()
        case "stop-all":
            stopAll()
        default:
            effectsInfo("unknown effect '\(name)'")
        }
    }

    /// Is anything running that a `stopAll()` would take down? The ⭐/🛑 status
    /// item asks this a few times a second.
    ///
    /// Deliberately **the same four things `stopAll` below touches, in the same
    /// order** — and nothing else. The icon is a promise that clicking it
    /// clears the screen, so the set it watches and the set it clears have to
    /// be one set; a fifth thing here would mean a 🛑 that a click cannot
    /// honour. All four are state that already existed and that `GET /state`
    /// already publishes (`playing`, `activeEffects`, `whipShowing`), so there
    /// is no second copy of "what is running" to drift.
    ///
    /// `whipIsShowing` is in there as a full member, not as an afterthought: an
    /// armed whip is a *mode*, not an animation — while it is up, Return and
    /// mouse buttons 6/7 crack it and a click types the scold macro into the
    /// front app (`EffectsHotkeyTap` gates all three on exactly this flag). So
    /// it is the one thing here that can still be "running" with nothing
    /// moving on screen, and the one a person is most likely to want killed
    /// from the menu bar. `stopAll()` disarms it through `WhipController.hide()`,
    /// which takes the panel down, drops the Esc monitors and stops the
    /// Bluetooth warm — after which `isShowing` is false and the tap stops
    /// gating on it. Trade-off, deliberately accepted: the whip has no deadline
    /// of its own, so the status item shows 🛑 for as long as it is out.
    ///
    /// What it does NOT see is the handful of overlays kept outside
    /// `activeEffects` on purpose (the 🕳️ iris, the spiral hearts…) and the
    /// short spawns that were never tracked at all (rising emoji, confetti).
    /// The 🪚 chainsaw is the exception, asked for by name since it stopped
    /// ending on its own (2026-09-23): a saw that runs until Escape is exactly
    /// what someone reaches for the 🛑 to kill. The first group is a real gap of at most one
    /// icon; the second is gone before a hand could reach the menu bar.
    var isAnythingRunning: Bool {
        SoundManager.shared.isTabletSoundPlaying
            || !animator.activeEffectNames.isEmpty
            || progressBar.isRunning
            || whipIsShowing
            || animator.isChainsawRunning
    }

    func stopAll() {
        SoundManager.shared.stopTabletSound()
        playing = nil
        animator.stopAllActiveEffects()
        progressBar.cancel()
        // The whip is an overlay like any other: "silence everything" takes it
        // down too.
        whipController?.hide()
    }

    // MARK: - Whip

    /// ⌃W is a toggle: a first press shows the whip, a second dismisses it
    /// through the exact path Esc takes. The show edge never types — the
    /// Ctrl+C + scold macro only fires on a click while the overlay is up, into
    /// whatever app has keyboard focus.
    func toggleWhip() {
        if let controller = whipController, controller.isShowing {
            controller.hide()
            return
        }
        let controller = whipController ?? WhipController()
        whipController = controller
        controller.onEscape = { [weak self] in self?.whipController?.hide() }
        // Every crack makes the claude-peek mascot flinch, if he is on screen.
        // Wired here rather than inside the whip so the overlay keeps knowing
        // nothing about the effects it triggers; a no-op the rest of the time.
        controller.onCrack = { [weak self] in self?.animator.whipClaudePeek() }
        controller.show()
    }

    // MARK: - Sound

    /// `GET /sound/play/<file>`. Returns the JSON body, or nil for 404.
    ///
    /// Seven tiles are not plain playback: their visual has to start from the
    /// same call as their audio because the cue lives at a fixed offset INSIDE
    /// the clip, and a separately-clocked visual slides off it.
    func playSound(_ name: String, volumePct: Int?) -> String? {
        // 🔀 A few tiles are a PAIR behind one press (#19 fail alternates with
        // #20 fail2, run by run — `AlternatingSounds`). Resolved here, before
        // anything else, so the whole method and everything downstream of it —
        // the special cases, the duration handed back, `playing`, the log —
        // speak about the file that is really being played rather than the one
        // that was asked for. An unpaired asset comes back unchanged.
        let requested = name
        let name = AlternatingSounds.shared.next(for: requested)
        if name != requested {
            effectsInfo("🔀 \(requested) → playing \(name) (alternating pair)")
        }

        let volume = volumePct.map { Float($0) / 100 }

        func remember(_ ms: Int) -> String {
            playing = (name, ms, Date())
            return "{\"ok\":true,\"durationMs\":\(ms)}"
        }

        // The radar sound drives the full 🛰️ sonar effect (animation + its own
        // beep-synced audio) instead of plain routed playback.
        if name == "23_radar.mp3" {
            animator.showSonar(playSound: true)
            return remember(5459)
        }
        // Tile #53 was repurposed into 💸 money: every press fires one round of
        // rising dollars and layers the checkmark "ching" (overlapping, not
        // preempting) so hammering the tile stacks both.
        if name == "53_rain.mp3" {
            animator.showMoneyRise()
            guard let duration = SoundManager.shared.playOverlappingTabletSound("57_checkmark.mp3", volume: volume) else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #31 (🕳️ iris close): silent by design, so it plays the gong
        // (~8.6 s ≈ the iris length) to keep every tile audible. The blackout is
        // driven by the press path.
        if name == "31_tarzan.mp3" {
            guard let duration = SoundManager.shared.playTabletSound("50_gong.mp3", volume: volume) else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #13 (💓 heartbeat): the zoom peaks on each measured onset.
        if name == "13_heartbeat.mp3" {
            let duration = animator.showHeartbeat(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #64 (🚪 FBI): the screen lurches on each bang, the first 22 ms in.
        if name == "64_fbi.mp3" {
            let duration = animator.showFbiKnock(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #25 (🚪 dark door): the desktop is punched in on each of the
        // seven knocks, the first 24 ms in — so the visual must already hold the
        // capture when the audio starts, and therefore owns it.
        if name == "25_dark_door.mp3" {
            let duration = animator.showDarkDoor(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #51 (🎼 Beethoven): six hits 0.11 s apart.
        if name == "51_beethoven.mp3" {
            let duration = animator.showBeethoven(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #14 (🌍 Universal fanfare): the matted minions animation enters
        // at a fixed point INSIDE the combined clip — the tile's fanfare gives
        // way to the clip's own tail 23.83 s in — so the effect owns the audio,
        // same reason as the microwave. The tablet never plays its own copy.
        if name == "14_universal.mp3" {
            let duration = animator.showUniversalMinions(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
            return remember(Int(duration * 1000))
        }
        // Tile #34 (🔥 phoenix): the Mac owns the cry (`phoenix.mp3`, faded in
        // unison with the visual) and the client's own file is a silent
        // placeholder, so nothing is routed here. Report the phoenix's ON-SCREEN
        // life, not the placeholder's ~0: a non-restartable tile only stops on a
        // re-tap while the client still thinks it is playing, and a 1 ms answer
        // ended that window instantly.
        if name == "34_phoenix.mp3" {
            return remember(Int(EmojiAnimator.phoenixDuration * 1000))
        }
        // Tile #80 (🍌 badumtss → the looping minion crowd): silent by design,
        // driven by the press path. Same duration reasoning as the phoenix.
        if name == "80_badumtss.mp3" {
            return remember(Int(EmojiAnimator.minionDuration * 1000))
        }
        // Tile #22 (🔫 minigun → the Counter-Strike AK-47): SILENT on the
        // press since 2026-09-23. The gun comes up at rest and the noise is the
        // trigger's — it plays only while the left button is held
        // (`EmojiAnimator.pullMinigunTrigger`), so the client's play request
        // must not start it. The tile stays lit for the gun's idle lifetime.
        // Unlike the FBI knock this tile stays in `SoundEffectMap`: the visual
        // still starts from the press.
        if name == "22_minigun.mp3" {
            return remember(Int(EmojiAnimator.minigunIdleLifetime * 1000))
        }
        // Tile #18 (🪚 chainsaw): SILENT on the press since 2026-09-23, same
        // reasoning as the AK-47 above. The saw now idles until Escape and
        // screams only while the button is held, so its engine noise is the
        // animator's own (`ChainsawSound`) and a clip that ends by itself has
        // nothing to add. The tile stays lit for the clip's old length; its
        // completion stop maps to nothing (no `onStop` entry), so the saw
        // outlives it.
        if name == "18_chainsaw.mp3" {
            return remember(Int(EmojiAnimator.chainsawTileLitDuration * 1000))
        }
        // Tile #69 (👻 wazzup ghost): the mask starts sliding in immediately
        // (`showWazzup`, fired by the client's separate `/sound/pressed`
        // request), but the SCREAM must wait until the slide has settled and
        // the stillness beat has run out — Victor's ask, and the whole point of
        // the rework: silence after the slide is what sells the scare, not the
        // scream landing over a still-moving image. Same mechanism as tile
        // #22's aim lead-in: the number is owned by the animation's own
        // timeline (`EmojiAnimator.wazzupLeadIn`), not by the tablet-tunable
        // `sound-timing.json`.
        if name == WazzupCorner.soundName {
            guard let duration = SoundManager.shared.playTabletSound(
                name, volume: volume,
                lead: EmojiAnimator.wazzupLeadIn) else { return nil }
            effectsInfo("👻 wazzup scream scheduled +\(EmojiAnimator.wazzupLeadIn)s (before any BT compensation), durationMs \(Int(duration * 1000))")
            return remember(Int(duration * 1000))
        }
        // Tile #27 (👏 applause): the clip is played 30 % shorter (tail faded)
        // so the audible clapping matches the trimmed GIF.
        if name == "27_clapping.mp3" {
            guard let duration = SoundManager.shared.playTabletSoundClipped("27_clapping.mp3", fraction: 0.7, volume: volume) else { return nil }
            return remember(Int(duration * 1000))
        }
        guard let duration = SoundManager.shared.playTabletSound(name, volume: volume) else { return nil }
        return remember(Int(duration * 1000))
    }
}
