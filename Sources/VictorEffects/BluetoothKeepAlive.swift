import AVFoundation
import CoreAudio
import Foundation

/// Keeps a Bluetooth speaker from dropping into power-save/standby between
/// sounds. Many BT speakers mute their amplifier after a few seconds of
/// silence, which clips the start of the next sound (a problem now that the
/// Mac renders the tablet-routed soundboard). While the *current default
/// output device* is one of those speakers we keep a **continuously looping**
/// near-silent tone (≈ -56 dBFS, inaudible in a room) playing, so the amp
/// never sees silence at all.
///
/// **Why continuous and not a burst every 30s** (2026-09-10): that is what the
/// first version did, and on the JBL Go 4 it stopped working — the amp mutes
/// after a few seconds, so 29.5 s out of every 30 were silence and each burst
/// only arrived to *re-wake* an already-muted amp, its own first moments
/// swallowed. The clipping it was supposed to remove came back. The whip
/// already knew this: `BluetoothOutput.startContinuousWarm()` exists precisely
/// because a periodic tone is not enough to play a crack with no spin-up lag.
/// The keep-alive now uses the same shape, with its own player so the whip
/// starting and stopping its warm never cuts ours.
///
/// Scope: every *connected* speaker that needs it — the JBL boxes — whether
/// or not it is the default output (see `targets`, and why since 2026-10-01).
/// Other Bluetooth outputs (e.g. "Vic Bose" headphones) don't standby-mute, so
/// pumping a tone into them is pointless. Each speaker gets its own players,
/// pointed at it by device UID, so nothing plays when no such speaker is
/// connected, and the wired/built-in output and the "🔊OS Output" loopback
/// never hear a thing.
///
/// It still self-gates on the name; the **menu row** added on 2026-09-14 is a
/// switch *over* that gate, not a second copy of it. Two things earned it a
/// row: the tone is by design inaudible, so "is it running?" had no answer
/// short of the log, and it is the one thing in this app that plays into a
/// speaker nobody asked to hear from — a recording, a call, or a speaker
/// someone else is using is exactly when it has to be possible to stop it
/// without quitting the app. Off is remembered (`KeepAliveSettings`), because
/// the reason to switch it off outlives a relaunch.
final class BluetoothKeepAlive {
    /// What the menu row shows, and the only three answers there are. The row
    /// itself is a plain checkbox (✓ = switched on, i.e. `running` or `idle`);
    /// the running/idle difference lives in its tooltip.
    enum State {
        /// The tone is playing: a matching speaker is the default output.
        case running
        /// Armed, but the default output is not a speaker that needs it.
        case idle
        /// Switched off in the menu (or no speaker name configured at all).
        case off

        /// The menu row's ✓: on whenever the switch is, playing or not.
        var isChecked: Bool { self != .off }
    }

    /// The three-way answer, from the three facts that decide it. Pure and
    /// static so `BluetoothKeepAliveStateTests` can hold it to the table
    /// without a speaker, a player or a run loop.
    ///
    /// `configured` (an empty `bluetoothSpeakerNameMatch`) reads as `off`
    /// rather than `idle` on purpose: idle promises "the moment a JBL becomes
    /// the output, this starts", and with no name to match nothing ever will.
    static func state(enabled: Bool, configured: Bool, playing: Bool) -> State {
        guard enabled, configured else { return .off }
        return playing ? .running : .idle
    }
    /// Which connected outputs to hold awake: every Bluetooth output whose
    /// name contains `match` and that has **no microphone**. Pure, so
    /// `BluetoothKeepAliveTargetsTests` pins it without a speaker.
    ///
    /// *Every* one, not only the default output (2026-10-01): Victor carries two
    /// JBL boxes as each other's spare, and a connected box that is not the
    /// default gets no audio at all — so it timed itself out ~20 min later and
    /// was gone by the time the other one died. Holding both awake is what
    /// lets `OutputRouter` (victor-macos-addons) hand the sound to a survivor.
    ///
    /// No microphone = a speaker. The name alone would also catch the
    /// "JBL TUNE500BT" headphones, and the nudge's 30 Hz is felt in a pair of
    /// headphones the way it is not from a palm-sized box; a headset publishes
    /// its HFP mic on the same CoreAudio device, an A2DP speaker does not.
    static func targets(_ devices: [BluetoothOutput.OutputDevice], match: String) -> [BluetoothOutput.OutputDevice] {
        guard !match.isEmpty else { return [] }
        return devices.filter {
            $0.isBluetooth && !$0.hasInput && !$0.uid.isEmpty
                && $0.name.range(of: match, options: .caseInsensitive) != nil
        }
    }

    /// How often we re-check the device list (and that each loop is still
    /// running). Not the tone's cadence — the tone never stops.
    private static let interval: TimeInterval = 30
    /// How often each speaker gets the nudge.
    ///
    /// **Why a nudge on top of the loop** (2026-10-01): the −56 dBFS loop keeps
    /// the *amp* from muting between sounds, but a JBL does not count it as
    /// audio. Its auto-off — "~20 min without sound" — kept firing with the
    /// loop running: the log shows the Go 4 dropping 18–19 min after every
    /// connect, five times in one evening and twice the next morning. The
    /// nudge is 2 s of 30 Hz at −30 dBFS: loud enough for the speaker's
    /// silence detector, and a frequency a palm-sized box can barely move air
    /// at and an ear barely hears. Four minutes leaves four chances inside the
    /// speaker's window.
    private static let nudgeEvery: TimeInterval = 4 * 60
    /// Substring (case-insensitive) a Bluetooth output's name must contain for
    /// the keep-alive to run. Computed, not stored: `/config/reload` can change
    /// it, and an empty value switches the keep-alive off entirely.
    private static var nameMatch: String { BluetoothOutput.speakerNameMatch }

    private let queue = DispatchQueue(label: "ro.victorrentea.victor-effects.bt-keepalive", qos: .utility)
    private var pollTimer: DispatchSourceTimer?

    /// Pre-rendered near-silent WAV, looped forever. 2s per lap, faded at both
    /// ends, so the loop boundary is click-free.
    private let keepAliveWav: Data = BluetoothOutput.makeSilentToneWav(seconds: 2.0)
    /// The nudge (see `nudgeEvery`). 200 ms fades so 30 Hz starts and stops
    /// without a thump.
    private let nudgeWav: Data = BluetoothOutput.makeToneWav(
        seconds: 2.0, freq: 30, amplitude: 0.0316,  // ≈ -30 dBFS
        fadeSeconds: 0.2)

    /// One per speaker being held awake, keyed by CoreAudio device UID. Each
    /// player is pointed at its own device (`currentDevice`), not at the
    /// default output. Main thread only (AVAudioPlayer is not thread-safe).
    private struct Held {
        let name: String
        var loop: AVAudioPlayer?
        var nudge: AVAudioPlayer?
        var lastNudge: Date
    }
    private var held: [String: Held] = [:]

    /// Last set of speaker names held awake, for transition-only logging.
    /// Queue only.
    private var lastNames: Set<String> = []

    /// Is the switch on? Main-thread read for the menu; the tick reads the same
    /// stored value off its own queue (`UserDefaults` is thread-safe).
    var isEnabled: Bool { KeepAliveSettings.isEnabled }

    /// What the menu row draws. Main thread only — `held` is.
    var state: State {
        Self.state(enabled: KeepAliveSettings.isEnabled,
                   configured: !Self.nameMatch.isEmpty,
                   playing: held.values.contains { $0.loop?.isPlaying == true })
    }

    /// The menu row's click. Switching **off** takes the tone down now rather
    /// than at the next tick: the row is reached in the middle of whatever made
    /// it necessary (a recording started, someone else took the speaker), and a
    /// switch that keeps playing for another half minute is not a switch.
    func setEnabled(_ on: Bool) {
        KeepAliveSettings.isEnabled = on
        guard on else {
            sync([])
            // Forget the last edge so switching back on logs "active" again
            // instead of staying quiet because the speaker never changed.
            queue.async { [weak self] in self?.lastNames = [] }
            overlayInfo("🚫 BT keep-alive switched off in the menu")
            return
        }
        overlayInfo("🔵 BT keep-alive switched on in the menu")
        queue.async { [weak self] in self?.tick() }
    }

    func start() {
        // No speaker name configured = nothing to keep awake. Bailing here (and
        // not just never matching) means the poll and the tone never exist on a
        // Mac that did not ask for them.
        guard !Self.nameMatch.isEmpty else {
            overlayInfo("⚪️ BT keep-alive off (bluetoothSpeakerNameMatch is empty)")
            return
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // Fire one tick immediately, then every 30s. 2s leeway lets the OS
        // coalesce the wakeup — this is a battery-friendly background poll.
        timer.schedule(deadline: .now() + 1, repeating: Self.interval, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        pollTimer = timer
        timer.resume()
        guard KeepAliveSettings.isEnabled else {
            overlayInfo("🚫 BT keep-alive poll started but the menu switch is off (turn it back on in the ⭐ menu)")
            return
        }
        overlayInfo("🔵 BT keep-alive started (every connected Bluetooth '\(Self.nameMatch)' speaker: continuous tone + a nudge every \(Int(Self.nudgeEvery / 60)) min, re-checked every \(Int(Self.interval))s)")
    }

    private func tick() {
        // Switched off in the menu: the poll stays alive (it is what notices
        // the switch coming back on, and it costs one coalesced wakeup every
        // 30 s) but nothing plays. Taking the timer down instead would leave
        // the app with no way back on short of a relaunch.
        guard KeepAliveSettings.isEnabled else {
            sync([])
            return
        }
        let targets = Self.targets(BluetoothOutput.outputDevices(), match: Self.nameMatch)
        let names = Set(targets.map(\.name))
        if names != lastNames {
            for name in names.subtracting(lastNames).sorted() {
                overlayInfo("🔵 BT keep-alive active → '\(name)' is a connected Bluetooth '\(Self.nameMatch)' speaker")
            }
            for name in lastNames.subtracting(names).sorted() {
                overlayInfo("⚪️ BT keep-alive released '\(name)' (no longer connected)")
            }
            lastNames = names
        }
        sync(targets.map { ($0.uid, $0.name) })
    }

    /// Bring `held` in line with `targets`, on the main thread: drop speakers
    /// that left, (re)start a loop that is not playing — the route changed
    /// under it, the Mac slept — and nudge the ones that are due.
    private func sync(_ targets: [(uid: String, name: String)]) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let wanted = Set(targets.map(\.uid))
            for uid in held.keys where !wanted.contains(uid) {
                held[uid]?.loop?.stop()
                held[uid]?.nudge?.stop()
                held[uid] = nil
            }
            let now = Date()
            for (uid, name) in targets {
                // A speaker that just connected was just switched on, so its
                // own timer has just started: no nudge owed yet.
                var h = held[uid] ?? Held(name: name, loop: nil, nudge: nil, lastNudge: now)
                if h.loop?.isPlaying != true {
                    h.loop?.stop()
                    h.loop = play(keepAliveWav, on: uid, loops: true, what: "keep-alive loop for '\(name)'")
                }
                if now.timeIntervalSince(h.lastNudge) >= Self.nudgeEvery {
                    h.nudge = play(nudgeWav, on: uid, loops: false, what: "nudge for '\(name)'")
                    h.lastNudge = now
                }
                held[uid] = h
            }
        }
    }

    private func play(_ wav: Data, on uid: String, loops: Bool, what: String) -> AVAudioPlayer? {
        do {
            let p = try AVAudioPlayer(data: wav)
            p.currentDevice = uid
            p.numberOfLoops = loops ? -1 : 0
            p.volume = 1.0  // amplitude is baked into the samples
            p.prepareToPlay()
            p.play()
            return p
        } catch {
            overlayError("BT keep-alive: \(what) failed: \(error)")
            return nil
        }
    }

}

/// The menu switch, persisted — same reasoning as `PeekMascotStore`: this app
/// is rebuilt and restarted several times an hour, and a switch a `pkill` undoes
/// is not a switch. **Defaults to on**, so a Mac that has never touched the row
/// behaves exactly as it did before the row existed.
enum KeepAliveSettings {
    private static let key = "BluetoothKeepAlive.enabled"

    static var isEnabled: Bool {
        // `object(forKey:)`, not `bool(forKey:)`: the latter cannot tell "never
        // set" from "set to false", and the default here is true.
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
