import AppKit
import Foundation

/// Everything the app can be asked to *do*, behind one object.
///
/// This is the `onEffect` / `onSoundPlay` half of the app it was extracted from,
/// lifted out of an AppDelegate that also owned transcription, hotspots and a
/// break timer. Two things did NOT come along: `training-end` and
/// `focus-playlist`, which are training-session features and stayed with the
/// session; and the coffee *payoff*, which now leaves as a webhook (see
/// `CoffeeChargeMonitor`).
final class EffectsEngine {
    let overlayPanel: OverlayPanel
    let animator: EmojiAnimator
    let progressBar: ProgressBarOverlay

    /// Fixed run time for looping effects fired from the menu, where no sound's
    /// length can decide it.
    private let menuEffectDuration: TimeInterval = 8

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
        // is playing, stop it — a long sound would otherwise blare on with no
        // way to stop it from the device that started it.
        soundWatchdog = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self, SoundManager.shared.isTabletSoundPlaying,
                  let last = self.lastPingAt, Date().timeIntervalSince(last) > 12 else { return }
            effectsInfo("Client ping lost >12s — stopping routed sound")
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
        overlayPanel.refreshScreenFrame()
        for _ in 0..<count { animator.spawnEmoji(emoji, glow: glow) }
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
        case "bullet-holes":  animator.showBulletHoles(playSound: false)
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
        case "cavalry":       animator.showCavalry(playSound: false)
        case "counter-strike": animator.showCounterStrike(playSound: false)
        case "wasnt-me":      animator.showWasntMe(playSound: false)
        case "chainsaw":      animator.showChainsawCursor(playSound: false)
        case "chainsaw/stop": animator.stopChainsawCursor()
        case "fire":          animator.showFireCursor(playSound: false)
        case "fire/stop":     animator.stopFireCursor()
        // Like the sonar: the door's cue lives INSIDE the clip, so the effect
        // owns its own audio rather than trusting a separate routed play to land
        // on the same millisecond.
        case "microwave":     animator.showMicrowave(playSound: true)
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
        case "red-button":    animator.showRedButton()
        case "red-button/stop": animator.stopRedButton()
        case "coffee":
            // Spawn a few rising ☕ so the hold-charge gesture can be exercised
            // headlessly — hover one, hold 3 s, watch it freeze, grow and pop.
            for emoji in EffectsConfig.shared.chargeEmoji.prefix(1) {
                for _ in 0..<3 { animator.spawnEmoji(emoji) }
            }
        case "coffee/pop":
            // Skip the hold entirely: pop a fully charged ☕ mid-screen and fire
            // the same event a real pop fires, so the whole chain can be checked
            // without holding a cursor still for three seconds.
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

    /// The ⭐️ Effects menu. Silent (`playSound: false`) and fixed-length:
    /// nothing here is paired with a routed sound whose duration could decide
    /// when a looping effect ends, so looping ones are stopped after
    /// `menuEffectDuration` and one-shots keep their natural length.
    func menuEffect(_ name: String) {
        // When the Mac's own output is Bluetooth, warm the A2DP link and shift
        // the whole effect later by the compensation, so the leading edge is not
        // clipped.
        let comp = SoundTimingConfig.shared.currentBluetoothCompensation
        if comp > 0 { BluetoothOutput.playWakeTone(seconds: comp) }
        let fire = { [weak self] in
            guard let self else { return }
            self.overlayPanel.refreshScreenFrame()
            let stopAfter: (@escaping () -> Void) -> Void = { stop in
                DispatchQueue.main.asyncAfter(deadline: .now() + self.menuEffectDuration, execute: stop)
            }
            switch name {
            case "applause":      self.animator.showApplause(playSound: false); stopAfter { self.animator.stopApplause() }
            case "spiral-hearts": self.animator.showSpiralHearts(); stopAfter { self.animator.stopSpiralHearts() }
            case "game-over":     self.animator.showGameOver(); stopAfter { self.animator.stopGameOver() }
            case "pulse":         self.animator.startPulseOverlay(playSound: false); stopAfter { self.animator.stopPulseOverlay() }
            case "brother":       self.animator.showBrother(playSound: false); stopAfter { self.animator.stopBrother() }
            case "gangnam":       self.animator.showGangnam(playSound: false); stopAfter { self.animator.stopGangnam() }
            case "love-hands":    self.animator.showLoveHands(playSound: false); stopAfter { self.animator.stopLoveHands() }
            case "star-wars":     self.animator.showStarWars(playSound: false); stopAfter { self.animator.stopStarWars() }
            case "rainbow":       self.animator.showRainbow(playSound: false); stopAfter { self.animator.stopRainbow() }
            case "snow":          self.animator.showSnow(); stopAfter { self.animator.stopSnow() }
            case "drum-roll":     self.animator.showDrumRoll(playSound: false); stopAfter { self.animator.stopDrumRoll() }
            // No stopAfter for the chainsaw and the fire cursor: both self-stop
            // at their clip's length, so a silent menu run lasts exactly as long
            // as a routed one. The fire cursor's Escape is the only early way out
            // of the 36 s it would otherwise run for.
            default:              self.fireEffect(name)
            }
        }
        if comp > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + comp, execute: fire)
        } else {
            fire()
        }
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
        controller.show()
    }

    // MARK: - Sound

    /// `GET /sound/play/<file>`. Returns the JSON body, or nil for 404.
    ///
    /// Seven tiles are not plain playback: their visual has to start from the
    /// same call as their audio because the cue lives at a fixed offset INSIDE
    /// the clip, and a separately-clocked visual slides off it.
    func playSound(_ name: String, volumePct: Int?) -> String? {
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
        // Tile #61 (⏲️ kitchen timer): the door swings open ON the bing, a fixed
        // 2.695 s into the clip.
        if name == "61_dinner.mp3" {
            let duration = animator.showMicrowave(playSound: true, volume: volume)
            guard duration > 0 else { return nil }
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
        // Tile #22 (🔫 minigun): the gun is on screen ALONE for
        // `minigunAimLeadIn`, then the reticle, the first bullet hole and the
        // noise arrive together. The visual half of that silence is inside
        // `showBulletHoles` (the press path), but the audio is started here, by
        // the client's *other* HTTP request — so the same lead-in is applied to
        // the clip, and only then do the three coincide. Unlike the FBI knock
        // this tile stays in `SoundEffectMap`: nothing here needs the capture,
        // so the visual can keep starting from the press.
        if name == "22_minigun.mp3" {
            guard let duration = SoundManager.shared.playTabletSound(
                "22_minigun.mp3", volume: volume,
                lead: EmojiAnimator.minigunAimLeadIn) else { return nil }
            effectsInfo("🔫 minigun audio scheduled +\(EmojiAnimator.minigunAimLeadIn)s, durationMs \(Int(duration * 1000))")
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
