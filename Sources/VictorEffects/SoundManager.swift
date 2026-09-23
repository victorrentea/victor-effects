import AVFoundation
import Foundation

/// Manages sound effects for overlay effects. Prevents overlapping plays of the same sound.
/// All operations run on the main thread (AVAudioPlayer is not thread-safe).
class SoundManager {
    static let shared = SoundManager()

    private var players: [String: AVAudioPlayer] = [:]
    private var overlappingPlayers: [AVAudioPlayer] = []

    /// How long an INTERRUPTED sound takes to die away. Every way of cutting a
    /// sound short goes through this: pressing its own tile again, pressing a
    /// different tile (which preempts), `/effect/stop-all`, the ping watchdog.
    /// An abrupt `stop()` is a hard edge the whole room hears — in a quiet lecture
    /// room the silence lands harder than the sound did — so the clip is faded
    /// instead. It stays audible for these 0.2 seconds *under* whatever was pressed
    /// next, which is the point: a short crossfade, not a gap — long enough to
    /// take the edge off, short enough that the room hears the new sound clean.
    static let interruptFade: TimeInterval = 0.2

    /// Run `work` on the main thread — **inline when we are already on it.**
    ///
    /// Every stop below used to be a bare `DispatchQueue.main.async`, which is
    /// correct for a caller arriving off-thread and a REORDERING BUG for one
    /// that is already on the main thread: the block does not run when it is
    /// asked for, it runs when the main thread next drains, which is after the
    /// caller has finished everything else it came to do.
    ///
    /// That is what silenced the soundboard. `SoundboardPress.press` is
    /// deliberately sequential — `/effect/stop-all`, then `/sound/play`, then
    /// `/sound/pressed` — and it calls `EffectsRouter.dispatch` **directly on
    /// the main thread**, with no socket in between. So the stop only *enqueued*
    /// a fade, the play then installed the new `tabletPlayer` in the same turn,
    /// and the deferred block woke up afterwards, found the tile's brand-new
    /// sound in `tabletPlayer` and faded it out over `interruptFade`. A clip
    /// that started and died 0.2 s later, every press, from the panel only —
    /// the tablet's identical sequence arrives as three separate HTTP requests,
    /// and the main queue drains between them, so the stop lands where it was
    /// meant to and the bug never showed in the room.
    ///
    /// This is the same scar `SoundboardPress` already carries in its own note
    /// ("firing stop-all and the paired effect from two threads lets the stop
    /// land *after* the effect and wipe it") — the press was made sequential and
    /// the sound manager was still free to defer.
    static func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    /// Players that are mid-fade and no longer reachable from `players` /
    /// `tabletPlayer`. They live here purely so ARC does not deallocate them —
    /// a released AVAudioPlayer stops dead, which is the exact hard cut the fade
    /// exists to avoid. Drained as each fade completes.
    private var fadingOut: [AVAudioPlayer] = []


    /// Player for the single tablet-routed sound. The tablet routes its
    /// soundboard here when "play on Mac" is active: one sound at a time, a
    /// new play preempts the current one (mirrors the tablet's local
    /// MediaPlayer semantics: same button = stop, other button = preempt).
    private var tabletPlayer: AVAudioPlayer?

    /// When the current tablet-routed sound was started — the lost-ping
    /// watchdog needs it to tell "the client that started this went quiet"
    /// from "no pinging client was ever behind this sound" (`PingWatchdog`).
    private(set) var tabletSoundStartedAt: Date?

    /// Playback volume (0..1) for tablet-routed sounds, controlled from the
    /// tablet's volume buttons/wedge. Player-level only — the macOS system
    /// volume is never touched.
    private var tabletVolume: Float = 1.0

    /// Fade `player` to silence over `seconds`, then stop it and let it go.
    /// Retains it for the duration — the caller has already dropped its own
    /// reference (see `fadingOut`). A zero/negative fade stops it immediately,
    /// which is what a genuine "silence this now" caller wants.
    /// Main thread only.
    private func fadeOutAndStop(_ player: AVAudioPlayer, over seconds: TimeInterval) {
        guard seconds > 0, player.isPlaying else {
            player.stop()
            return
        }
        fadingOut.append(player)
        player.setVolume(0, fadeDuration: seconds)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { [weak self] in
            player.stop()
            self?.fadingOut.removeAll { $0 === player }
        }
    }

    /// Per-sound playback start delay (seconds) for sounds paired with a
    /// visual effect: the animation gets a head start so it is on screen
    /// before the audio kicks in. Applied in the tablet-routed path
    /// (playTabletSound) and the Mac-local path (EmojiAnimator). Sourced from
    /// the shared sound-timing.json (animationLeadMs) so the Mac and tablet
    /// agree; see SoundTimingConfig.
    static var pairedEffectStartDelays: [String: TimeInterval] {
        SoundTimingConfig.shared.animationLeads
    }

    // MARK: - Bluetooth visual sync (tablet-routed path)

    /// When a tablet-routed sound is started with Bluetooth compensation, the
    /// paired Mac visual (delivered as a separate /effect request right after)
    /// must be delayed by the same amount to stay in sync with the
    /// silence-prepended audio. Set by playTabletSound, consumed once by the
    /// next show-effect. Main-thread only — both the sound and the effect HTTP
    /// handlers run inside TabletHttpServer's DispatchQueue.main.sync.
    private static var pendingVisualCompensation: TimeInterval = 0
    private static var pendingVisualCompensationAt: Date?

    /// Returns (and clears) the Bluetooth compensation that the imminent paired
    /// visual `name` should be delayed by, or 0. Only a fresh (<1.5s) pending
    /// compensation tied to a just-routed sound applies, and never to
    /// stop/utility signals (those must fire immediately).
    ///
    /// `green-flash` is excluded here because it is never paired with a routed
    /// tablet sound — it is paired with the Mac's own click tone, so its
    /// compensation is taken straight from `SoundTimingConfig` by the caller.
    static func consumePendingVisualCompensation(for name: String) -> TimeInterval {
        guard pendingVisualCompensation > 0,
              let at = pendingVisualCompensationAt,
              Date().timeIntervalSince(at) < 1.5 else { return 0 }
        if name == "stop-all" || name.hasSuffix("/stop")
            || name == "green-flash" || name.hasPrefix("progress-bar/") {
            return 0
        }
        let comp = pendingVisualCompensation
        pendingVisualCompensation = 0
        pendingVisualCompensationAt = nil
        return comp
    }

    private init() {}

    /// The soundboard folder: `EffectsConfig.soundsDir`.
    ///
    /// In the app this was extracted from, this function hunted for a symlink
    /// through three candidate paths (the bundle, an env root, one hardcoded
    /// home directory) because the sounds shipped as a *resource* of the app and
    /// `swift build` kept putting the verbatim symlink back where it did not
    /// resolve. None of that survives here: the folder is named in the config,
    /// read live, and never copied into a bundle — so a changed mp3 needs no
    /// rebuild and there is no state in which the app answers 404 while the
    /// files are right there.
    ///
    /// Logged once, not on every lookup: a missing folder is a setup mistake
    /// worth one line, not one line per `/sound/play`.
    private static var loggedMissingSoundsDir = false
    static func sharedSoundsDir() -> URL? {
        let dir = EffectsConfig.shared.soundsDir
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
            return dir
        }
        if !loggedMissingSoundsDir {
            loggedMissingSoundsDir = true
            effectsError("soundsDir does not exist: \(dir.path) — set it in \(EffectsConfig.configPath)")
        }
        return nil
    }

    /// Called by `/config/reload` so a corrected path is reported again.
    static func resetSoundsDirWarning() { loggedMissingSoundsDir = false }

    /// Resolve a sound file: the configured `soundsDir` first, then `assetsDir`
    /// (Mac-owned effect media that is deliberately not in the public repo —
    /// the same precedence `EffectsConfig.assetURL` applies), then the handful
    /// of sounds bundled with the app itself (click, phoenix, confetti, the
    /// whip cracks).
    func soundURL(for filename: String) -> URL? {
        if let dir = Self.sharedSoundsDir() {
            let shared = dir.appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: shared.path) { return shared }
        }
        let external = EffectsConfig.shared.assetsDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: external.path) { return external }
        // bundleURL, not resourceURL: NSBundle reports <bundle>/Resources as
        // the resource dir for this flat SPM bundle, which would double the
        // "Resources" path component.
        let local = Bundle.module.bundleURL.appendingPathComponent("Resources/\(filename)")
        if FileManager.default.fileExists(atPath: local.path) { return local }
        return nil
    }

    /// Duration (seconds) of a bundled sound file, or nil if unavailable.
    func soundDuration(_ filename: String) -> TimeInterval? {
        guard let url = soundURL(for: filename) else { return nil }
        return try? AVAudioPlayer(contentsOf: url).duration
    }

    /// Start `player` with the same Bluetooth latency compensation the
    /// tablet-routed path (`playTabletSound`) already applies: when the Mac's
    /// default output is Bluetooth, warm the A2DP link with an inaudible wake
    /// tone and shift the start by the configured compensation
    /// (`sound-timing.json` → `bluetoothCompensationMs`, mirroring the tablet's
    /// `BT_WAKE_MS`) so the leading edge isn't clipped during codec/amp
    /// spin-up. On built-in/wired output it starts immediately — a no-op that
    /// leaves the previous behaviour untouched. Returns the applied delay
    /// (seconds) so callers can shift any follow-up timers (fade-out, stop,
    /// cleanup) to match. Main thread only (AVAudioPlayer is not thread-safe).
    @discardableResult
    private func startWithBluetoothCompensation(_ player: AVAudioPlayer) -> TimeInterval {
        let comp = SoundTimingConfig.shared.currentBluetoothCompensation
        if comp > 0 {
            BluetoothOutput.playWakeTone(seconds: comp)
            player.play(atTime: player.deviceCurrentTime + comp)
        } else {
            player.play()
        }
        return comp
    }

    /// Play a sound from the bundle Resources folder, looping indefinitely.
    /// If the same sound is already playing, does nothing.
    func playLooping(_ filename: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let existing = self.players[filename], existing.isPlaying { return }
            guard let url = self.soundURL(for: filename) else {
                overlayError("Sound file not found: \(filename)")
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1
                player.volume = 1.0
                player.prepareToPlay()
                self.players[filename] = player
                self.startWithBluetoothCompensation(player)
            } catch {
                overlayError("Sound play failed \(filename): \(error)")
            }
        }
    }

    /// Play a sound from the bundle Resources folder.
    /// If the same sound is already playing, does nothing (no restart).
    ///
    /// `bluetoothCompensated` (default true) applies the standard A2DP warm-up +
    /// start delay when the Mac's output is Bluetooth (see
    /// `startWithBluetoothCompensation`). Pass `false` when the CALLER already
    /// owns the Bluetooth timing — e.g. the 🛰️ sonar, which delays both its
    /// audio AND its visual by the compensation itself; letting this method add
    /// the delay a second time would push the beeps 2×btComp late and desync
    /// them from the sweep again.
    func play(_ filename: String, volume: Float = 1.0, bluetoothCompensated: Bool = true) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Already playing? Skip.
            if let existing = self.players[filename], existing.isPlaying {
                return
            }

            guard let url = self.soundURL(for: filename) else {
                overlayError("Sound file not found: \(filename)")
                return
            }

            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = max(0.0, min(1.0, volume))
                player.prepareToPlay()
                self.players[filename] = player
                if bluetoothCompensated {
                    self.startWithBluetoothCompensation(player)
                } else {
                    player.play()
                }
            } catch {
                overlayError("Sound play failed \(filename): \(error)")
            }
        }
    }

    /// Play a new instance of the sound every time, layering over any already-playing copies.
    /// The player is released automatically when playback finishes.
    ///
    /// `bluetoothCompensated` (default true) applies the standard A2DP warm-up +
    /// start delay when the Mac's output is Bluetooth (see
    /// `startWithBluetoothCompensation`). Pass `false` when the sound must land
    /// **now**, in sync with an on-screen event — e.g. the 🔥 whip crack, whose
    /// overlay keeps the A2DP link continuously warm (`BluetoothOutput.startContinuousWarm`)
    /// for its whole lifetime, so the amp is already spun up and the delay would
    /// only push the crack sound late behind the visual crack.
    ///
    /// `startAt` (seconds) seeks past the head of the file before playing —
    /// used to skip a sample's built-in lead-in so its transient bangs
    /// immediately (e.g. the whip cracks, whose samples carry up to ~170ms of
    /// wind-up swish before the actual snap). Clamped inside the clip.
    ///
    /// `fadeIn` (seconds) swells the copy up from silence to `volume` instead of
    /// starting it at full level — for a sound that layers over copies of ITSELF
    /// (the ☢️ bombardment plays one boom per bomb), where several hard starts a
    /// beat apart stack into noise rather than into a rhythm. The ramp begins when
    /// the sound actually starts, i.e. after any Bluetooth compensation.
    func playOverlapping(_ filename: String, volume: Float = 1.0, bluetoothCompensated: Bool = true, startAt: TimeInterval = 0, fadeIn: TimeInterval = 0) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let url = self.soundURL(for: filename) else {
                overlayError("Sound file not found: \(filename)")
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                let level = max(0.0, min(1.0, volume))
                player.volume = fadeIn > 0 ? 0 : level
                player.prepareToPlay()
                if startAt > 0 { player.currentTime = min(startAt, max(0, player.duration - 0.05)) }
                self.overlappingPlayers.append(player)
                let comp: TimeInterval
                if bluetoothCompensated {
                    comp = self.startWithBluetoothCompensation(player)
                } else {
                    player.play()
                    comp = 0
                }
                if fadeIn > 0 {
                    // Scheduled, not immediate: with a Bluetooth start delay the
                    // player isn't sounding yet, and a ramp that ran during the
                    // silence would be over before the first sample is audible.
                    DispatchQueue.main.asyncAfter(deadline: .now() + comp) {
                        player.setVolume(level, fadeDuration: fadeIn)
                    }
                }
                // Clean up finished players after this one ends
                DispatchQueue.main.asyncAfter(deadline: .now() + comp + player.duration + 0.1) { [weak self] in
                    self?.overlappingPlayers.removeAll { !$0.isPlaying }
                }
            } catch {
                overlayError("Sound play failed \(filename): \(error)")
            }
        }
    }

    /// Play a sound as a fixed-length "clip": it plays for `seconds`, fading out
    /// over the final `fade` seconds so the cut is clean. Layers over other sounds.
    /// `volume` (0..1) sets the playback level; the fade-out goes from it to 0.
    func playClip(_ filename: String, seconds: TimeInterval, fade: TimeInterval = 0.6, volume: Float = 1.0) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard let url = self.soundURL(for: filename) else {
                overlayError("Sound file not found: \(filename)")
                return
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = max(0.0, min(1.0, volume))
                player.prepareToPlay()
                self.overlappingPlayers.append(player)
                let comp = self.startWithBluetoothCompensation(player)
                let fadeStart = comp + max(0, seconds - fade)
                DispatchQueue.main.asyncAfter(deadline: .now() + fadeStart) {
                    if player.isPlaying { player.setVolume(0, fadeDuration: fade) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + comp + seconds + 0.05) { [weak self] in
                    player.stop()
                    self?.overlappingPlayers.removeAll { !$0.isPlaying }
                }
            } catch {
                overlayError("Sound clip failed \(filename): \(error)")
            }
        }
    }

    // MARK: - Tablet-routed sounds (GET /sound/play/<file>, /sound/stop)

    /// Play a tablet-routed sound, preempting any currently playing tablet
    /// sound. `volume` (0..1) accompanies each play from the tablet and is
    /// remembered as the new tablet volume. Returns the sound duration in
    /// seconds (the tablet schedules its effect-stop chain from it), or nil
    /// if the file is unknown/unplayable. Synchronous — must be called on the
    /// main thread (TabletHttpServer dispatches handlers via DispatchQueue.main.sync).
    /// `lead` overrides the shared `sound-timing.json` head start for this one
    /// call, for a sound whose paired visual owns the number in code rather than
    /// in the config file (tile #69 passes `EmojiAnimator.wazzupLeadIn`: the
    /// number belongs to the animation's own timeline). It is added to the returned duration exactly as a
    /// configured lead is, so the client's completion timer still covers the
    /// whole clip.
    /// `startAt` skips into the clip (seconds) — the test-preview paths use it
    /// to jump straight to a cue instead of sitting through a long lead-in.
    func playTabletSound(_ filename: String, volume: Float? = nil, lead: TimeInterval? = nil,
                         startAt: TimeInterval = 0) -> TimeInterval? {
        if let volume { tabletVolume = max(0.0, min(1.0, volume)) }
        // Preempt by fading, not by cutting: the outgoing clip keeps playing
        // under the new one for `interruptFade` seconds.
        if let outgoing = tabletPlayer { fadeOutAndStop(outgoing, over: Self.interruptFade) }
        tabletPlayer = nil
        guard let url = soundURL(for: filename) else {
            overlayError("Tablet sound not found: \(filename)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = tabletVolume
            player.prepareToPlay()
            if startAt > 0 { player.currentTime = min(startAt, player.duration) }
            tabletPlayer = player
            tabletSoundStartedAt = Date()
            let lead = lead ?? Self.pairedEffectStartDelays[filename] ?? 0
            // When this Mac's own output is Bluetooth, prepend silence to warm
            // the A2DP link (so the sound isn't clipped) and remember the
            // compensation so the paired visual — a separate /effect request
            // right after — is delayed to match. Zero on non-Bluetooth output,
            // leaving the previous behaviour untouched.
            let btComp = SoundTimingConfig.shared.currentBluetoothCompensation
            let total = lead + btComp
            if btComp > 0 {
                BluetoothOutput.playWakeTone(seconds: total)
                Self.pendingVisualCompensation = btComp
                Self.pendingVisualCompensationAt = Date()
            }
            if total > 0 {
                player.play(atTime: player.deviceCurrentTime + total)
            } else {
                player.play()
            }
            // Include the lead + Bluetooth compensation so the tablet's
            // completion timer (durationMs + 100ms → effect-stop chain) doesn't
            // cut the tail of the sound.
            return player.duration - player.currentTime + total
        } catch {
            overlayError("Tablet sound play failed \(filename): \(error)")
            return nil
        }
    }

    /// Like `playTabletSound`, but plays only the first `fraction` (0..1) of the
    /// clip — fading the tail out over `fade` seconds, then stopping — so a routed
    /// sound can be trimmed shorter than its file. Used by the 👏 Applause tile
    /// (`27_clapping.mp3`, clipped to 70% so the clapping runs 30% shorter and
    /// matches the trimmed GIF visual). Routes through the single `tabletPlayer`
    /// like `playTabletSound` (preempts, honours tablet volume, is stopped by
    /// stop-all) and returns the clipped duration (incl. any BT lead) for the
    /// tablet's effect-stop chain. Main thread only.
    func playTabletSoundClipped(_ filename: String, fraction: Double, fade: TimeInterval = 0.6, volume: Float? = nil) -> TimeInterval? {
        if let volume { tabletVolume = max(0.0, min(1.0, volume)) }
        // Preempt by fading, not by cutting: the outgoing clip keeps playing
        // under the new one for `interruptFade` seconds.
        if let outgoing = tabletPlayer { fadeOutAndStop(outgoing, over: Self.interruptFade) }
        tabletPlayer = nil
        guard let url = soundURL(for: filename) else {
            overlayError("Tablet sound not found: \(filename)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = tabletVolume
            player.prepareToPlay()
            tabletPlayer = player
            let lead = Self.pairedEffectStartDelays[filename] ?? 0
            let btComp = SoundTimingConfig.shared.currentBluetoothCompensation
            let total = lead + btComp
            if btComp > 0 {
                BluetoothOutput.playWakeTone(seconds: total)
                Self.pendingVisualCompensation = btComp
                Self.pendingVisualCompensationAt = Date()
            }
            if total > 0 {
                player.play(atTime: player.deviceCurrentTime + total)
            } else {
                player.play()
            }
            let clipped = player.duration * max(0.0, min(1.0, fraction))
            let fadeStart = total + max(0, clipped - fade)
            DispatchQueue.main.asyncAfter(deadline: .now() + fadeStart) { [weak player] in
                if player?.isPlaying == true { player?.setVolume(0, fadeDuration: fade) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + total + clipped + 0.05) { [weak self, weak player] in
                player?.stop()
                if self?.tabletPlayer === player { self?.tabletPlayer = nil }
            }
            return clipped + total
        } catch {
            overlayError("Tablet sound play failed \(filename): \(error)")
            return nil
        }
    }

    /// Play a tablet-routed sound that LAYERS over its previous copies instead
    /// of preempting them — used by the 💸 Money tile (53_rain.mp3 →
    /// 57_checkmark.mp3) so rapid repeated presses STACK overlapping "ching"s
    /// (matching the stacking rounds of rising dollars) rather than cutting the
    /// previous sound off. Honours/remembers the tablet volume like
    /// playTabletSound, but routes through the overlapping-players pool — never
    /// the single `tabletPlayer` — so it neither preempts nor is wiped by
    /// stopTabletSound / `/effect/stop-all` (which the tablet fires before every
    /// press). Returns the clip duration for the tablet's effect-stop chain.
    /// Synchronous — main thread only (TabletHttpServer handlers run on it).
    @discardableResult
    func playOverlappingTabletSound(_ filename: String, volume: Float? = nil) -> TimeInterval? {
        if let volume { tabletVolume = max(0.0, min(1.0, volume)) }
        guard let url = soundURL(for: filename) else {
            overlayError("Tablet sound not found: \(filename)")
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = tabletVolume
            player.prepareToPlay()
            overlappingPlayers.append(player)
            player.play()
            let duration = player.duration
            // Release finished players after this one ends (same cleanup as playOverlapping).
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak self] in
                self?.overlappingPlayers.removeAll { !$0.isPlaying }
            }
            return duration
        } catch {
            overlayError("Tablet sound play failed \(filename): \(error)")
            return nil
        }
    }

    /// Live-adjust the tablet-routed volume (applies to the sound currently
    /// playing too) and play the tablet's click tone at the new level as
    /// audible feedback — the same generated 1800Hz tap the tablet uses.
    func setTabletVolume(_ volume: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tabletVolume = max(0.0, min(1.0, volume))
            self.tabletPlayer?.volume = self.tabletVolume
            self.playOverlapping("click.wav", volume: self.tabletVolume)
        }
    }

    /// The tablet's current volume level (0..1), for Mac-local sounds that
    /// should follow the tablet's wedge even though they aren't routed from it
    /// — e.g. the 🔥 whip crack. Main thread only (`tabletVolume` is only ever
    /// mutated on main).
    var currentTabletVolume: Float { tabletVolume }

    /// Stop the tablet-routed sound, fading it out over `interruptFade` (0.2s)
    /// rather than cutting it. Every route into here is an interruption — a
    /// re-press of the playing tile, `/effect/stop-all` (which the tablet fires
    /// before every press), the lost-ping watchdog — so they all get the fade.
    /// `fade: 0` forces the old abrupt stop for a caller that truly needs silence
    /// on the instant.
    func stopTabletSound(fade: TimeInterval = SoundManager.interruptFade) {
        Self.onMain { [weak self] in
            guard let self else { return }
            if let player = self.tabletPlayer { self.fadeOutAndStop(player, over: fade) }
            self.tabletPlayer = nil
        }
    }

    /// Silence one clip wherever it happens to be playing from: this Mac's own
    /// one-shot pool (`play`) **or** the tablet-routed player. The two paths are
    /// normally a caller's own business — it knows which one it started — but not
    /// for a sound the *tablet* starts in its own HTTP request while the Mac owns
    /// the visual (`03_explosion.mp3`: `showExplosionGif` gets `playSound: false`
    /// on the routed path and `true` from a local trigger). An animation that has
    /// to cut that clip short cannot know which pool holds it, and guessing wrong
    /// leaves the sound running — which is exactly the bug this exists for, the
    /// ☢️ head boom blasting a second time over an aimed bomb's own.
    ///
    /// The tablet player is only touched when it is *this* file: it holds
    /// whatever tile was last pressed, and stopping it blind would silence an
    /// unrelated sound.
    func stopWherever(_ filename: String, fade: TimeInterval = SoundManager.interruptFade) {
        Self.onMain { [weak self] in
            guard let self else { return }
            let url = self.soundURL(for: filename)
            if let player = self.players[filename] {
                self.players[filename] = nil
                self.fadeOutAndStop(player, over: fade)
            }
            if let tablet = self.tabletPlayer, let url, tablet.url == url {
                self.tabletPlayer = nil
                self.fadeOutAndStop(tablet, over: fade)
            }
        }
    }

    /// Whether a tablet-routed sound is currently playing (main thread only —
    /// used by the ping watchdog).
    var isTabletSoundPlaying: Bool {
        tabletPlayer?.isPlaying ?? false
    }

    /// Stop any overlapping instances of a given sound immediately (e.g. interrupt
    /// the break-timer gong when the user closes the watch mid-strike).
    func stopOverlapping(_ filename: String, fade: TimeInterval = 0) {
        Self.onMain { [weak self] in
            guard let self, let url = self.soundURL(for: filename) else { return }
            let matching = self.overlappingPlayers.filter { $0.url == url }
            // Dropped from the pool FIRST, then faded: `fadeOutAndStop` is what
            // keeps them alive now, and leaving them in the pool as well would
            // have the next `removeAll { !$0.isPlaying }` decide their fate.
            self.overlappingPlayers.removeAll { $0.url == url }
            for p in matching { self.fadeOutAndStop(p, over: fade) }
            self.overlappingPlayers.removeAll { !$0.isPlaying }
        }
    }

    /// Immediately stop EVERY one-shot `play()` sound (the `players` pool). Used
    /// by the desktop `/effect/stop-all` so a non-restartable re-tap silences any
    /// Mac-owned effect audio (e.g. the 🛰️ sonar beeps `23_radar.mp3`) that plays
    /// through this pool rather than the tablet-routed player. The money "ching"
    /// and other stacking clips ride the SEPARATE overlapping pool and are left
    /// alone (stop those by name via `stopOverlapping`).
    func stopAllPlayers(fade: TimeInterval = SoundManager.interruptFade) {
        Self.onMain { [weak self] in
            guard let self else { return }
            let all = Array(self.players.values)
            self.players.removeAll()
            for p in all { self.fadeOutAndStop(p, over: fade) }
        }
    }

    /// Fade a Mac-owned effect sound out, then stop it.
    ///
    /// Two very different callers, hence the parameter. When an effect reaches
    /// its **natural** end the visual has just finished and the audio is already
    /// over, so a 300ms tail is all that is wanted. When the effect is
    /// **interrupted** (re-press), the caller passes `interruptFade` and the clip
    /// dies away over 0.2 seconds like every other interrupted sound.
    func stop(_ filename: String, fade: TimeInterval = 0.3) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let player = self.players[filename], player.isPlaying else {
                self?.players[filename] = nil
                return
            }
            self.players[filename] = nil
            self.fadeOutAndStop(player, over: fade)
        }
    }
}
