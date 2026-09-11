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
/// No menu toggle — it self-gates on the name.
final class BluetoothKeepAlive {
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
        overlayInfo("🔵 BT keep-alive started (continuous tone while default output is a Bluetooth '\(Self.nameMatch)' speaker, re-checked every \(Int(Self.interval))s)")
    }

    private func tick() {
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
