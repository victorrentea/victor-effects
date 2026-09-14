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
/// Scope: only the active output, and only the speakers that actually need it
/// — the JBL boxes. Other Bluetooth outputs (e.g. "Vic Bose" headphones) don't
/// standby-mute, so pumping a tone into them is pointless. We check the default
/// output device's transport type *and* its name, and emit through the normal
/// default route (AVAudioPlayer), so nothing plays when the default output is
/// wired/built-in, the "🔊OS Output" loopback, or a non-JBL Bluetooth device.
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
    /// What the menu row shows, and the only three answers there are.
    ///
    /// The vocabulary is deliberately the log's: 🔵 is the same "active" the
    /// tick has always logged, ⚪️ the same "idle". `off` is the new one — the
    /// switch, not the speaker.
    enum State {
        /// The tone is playing: a matching speaker is the default output.
        case running
        /// Armed, but the default output is not a speaker that needs it.
        case idle
        /// Switched off in the menu (or no speaker name configured at all).
        case off

        var emoji: String {
            switch self {
            case .running: return "🔵"
            case .idle: return "⚪️"
            case .off: return "🚫"
            }
        }
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
    /// How often we re-check the default output (and that our loop is still
    /// running). Not the tone's cadence any more — the tone never stops.
    private static let interval: TimeInterval = 30
    /// Substring (case-insensitive) a Bluetooth output's name must contain for
    /// the keep-alive to run. Computed, not stored: `/config/reload` can change
    /// it, and an empty value switches the keep-alive off entirely.
    private static var nameMatch: String { BluetoothOutput.speakerNameMatch }

    private let queue = DispatchQueue(label: "ro.victorrentea.victor-effects.bt-keepalive", qos: .utility)
    private var pollTimer: DispatchSourceTimer?

    /// Pre-rendered near-silent WAV, looped forever. 2s per lap, faded at both
    /// ends, so the loop boundary is click-free. AVAudioPlayer(data:) routes to
    /// the current default output device.
    private let keepAliveWav: Data = BluetoothOutput.makeSilentToneWav(seconds: 2.0)
    /// The looping player, alive for as long as a JBL is the default output.
    /// Main thread only (AVAudioPlayer is not thread-safe).
    private var player: AVAudioPlayer?

    /// Last observed "default output is a JBL speaker" state, for
    /// transition-only logging (avoids ~2880 log lines/day from a silent 30s
    /// heartbeat).
    private var lastWasTarget = false

    /// Is the switch on? Main-thread read for the menu; the tick reads the same
    /// stored value off its own queue (`UserDefaults` is thread-safe).
    var isEnabled: Bool { KeepAliveSettings.isEnabled }

    /// What the menu row draws. Main thread only — `player` is.
    var state: State {
        Self.state(enabled: KeepAliveSettings.isEnabled,
                   configured: !Self.nameMatch.isEmpty,
                   playing: player?.isPlaying == true)
    }

    /// The menu row's click. Switching **off** takes the tone down now rather
    /// than at the next tick: the row is reached in the middle of whatever made
    /// it necessary (a recording started, someone else took the speaker), and a
    /// switch that keeps playing for another half minute is not a switch.
    func setEnabled(_ on: Bool) {
        KeepAliveSettings.isEnabled = on
        guard on else {
            stopLoop()
            // Forget the last edge so switching back on logs "active" again
            // instead of staying quiet because the speaker never changed.
            lastWasTarget = false
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
            overlayInfo("🚫 BT keep-alive poll started but the menu switch is off (turn it back on in the 💥 menu)")
            return
        }
        overlayInfo("🔵 BT keep-alive started (continuous tone while default output is a Bluetooth '\(Self.nameMatch)' speaker, re-checked every \(Int(Self.interval))s)")
    }

    private func tick() {
        // Switched off in the menu: the poll stays alive (it is what notices
        // the switch coming back on, and it costs one coalesced wakeup every
        // 30 s) but nothing plays. Taking the timer down instead would leave
        // the app with no way back on short of a relaunch.
        guard KeepAliveSettings.isEnabled else {
            DispatchQueue.main.async { [weak self] in self?.stopLoop() }
            return
        }
        let (isBT, name) = BluetoothOutput.defaultOutput()
        let match = Self.nameMatch
        let isTarget = isBT && !match.isEmpty
            && name.range(of: match, options: .caseInsensitive) != nil
        if isTarget != lastWasTarget {
            lastWasTarget = isTarget
            if isTarget {
                overlayInfo("🔵 BT keep-alive active → default output '\(name)' is a Bluetooth '\(Self.nameMatch)' speaker")
            } else {
                overlayInfo("⚪️ BT keep-alive idle → default output '\(name)' is not a Bluetooth '\(Self.nameMatch)' speaker")
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isTarget ? self.startLoop() : self.stopLoop()
        }
    }

    /// Idempotent: a running loop is left alone. A player that died — the route
    /// changed under it, the Mac slept — is rebuilt, which is the other half of
    /// what the 30s tick is for.
    private func startLoop() {
        if player?.isPlaying == true { return }
        player?.stop()
        player = nil
        do {
            let p = try AVAudioPlayer(data: keepAliveWav)
            p.numberOfLoops = -1
            p.volume = 1.0  // amplitude is baked into the samples
            p.prepareToPlay()
            player = p
            p.play()
        } catch {
            overlayError("BT keep-alive play failed: \(error)")
        }
    }

    private func stopLoop() {
        guard player != nil else { return }
        player?.stop()
        player = nil
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
