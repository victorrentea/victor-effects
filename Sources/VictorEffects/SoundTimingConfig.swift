import Foundation

/// Loads the shared `sound-timing.json` that this app and the tablet both read.
/// The file lives in `soundsDir`, beside the sounds it describes, so it is a
/// single source of truth for:
///   - `bluetoothCompensationMs`: silence prepended before a sound, and the
///     matching delay applied to its paired animation, **only** when the
///     current output is Bluetooth (see `BluetoothOutput`).
///   - per-sound `animationLeadMs`: how long an animation leads its sound
///     (backs `SoundManager.pairedEffectStartDelays`).
///
/// Loaded once, lazily. If the file is missing or malformed we fall back to the
/// values baked in below, which match the tablet's current behaviour — so a bad
/// config never breaks playback, it just reverts to the previous constants.
final class SoundTimingConfig {
    /// A `var` rather than a `let` only so `GET /config/reload` can pick up a
    /// timing file from a newly configured `soundsDir`. Replacing the instance
    /// drops the live slider override with it, which is correct: a different
    /// sounds folder is a different set of numbers.
    private(set) static var shared = SoundTimingConfig()

    static func reload() { shared = SoundTimingConfig() }

    /// Seconds of silence to prepend (and to delay the paired animation by)
    /// when the current default output is Bluetooth. Loaded from
    /// `sound-timing.json` (Mac prefers `macBluetoothCompensationMs`); this is
    /// the *baked-in default* — the tablet's header slider can override it at
    /// runtime (see `overrideSeconds` / `setBluetoothCompensation`).
    let bluetoothCompensationSeconds: TimeInterval

    /// Hard ceiling for the BT compensation, matching the tablet slider's 0–1.2s
    /// range. Any override is clamped into `0...maxCompensationSeconds`.
    static let maxCompensationSeconds: TimeInterval = 1.2

    /// Live override pushed by the tablet's header slider (persisted on the
    /// tablet, re-pushed on every (re)connect). `nil` until the tablet sets one,
    /// in which case the file default applies. Guarded by `lock` because the
    /// setter runs on the HTTP server's main-sync closure while sound playback
    /// reads it on the main thread too — the lock keeps it safe regardless.
    private var overrideSeconds: TimeInterval?
    private let lock = NSLock()

    /// `animationLeadMs` per sound file, in seconds.
    let animationLeads: [String: TimeInterval]

    private init() {
        // The timing file lives beside the sounds it describes, in the
        // configured soundsDir — the same folder the tablet reads, so both ends
        // stay on one set of numbers. Absent file = the baked defaults below.
        let url = (SoundManager.sharedSoundsDir() ?? EffectsConfig.shared.soundsDir)
            .appendingPathComponent("sound-timing.json")

        var comp: TimeInterval = 0.55
        var leads: [String: TimeInterval] = ["67_sfx_109.mp3": 0.30]

        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let ms = obj["bluetoothCompensationMs"] as? NSNumber {
                comp = ms.doubleValue / 1000.0
            }
            // Mac-only override: the Mac's BT output needs a longer warm-up than
            // the tablet's own BT speaker. Prefer macBluetoothCompensationMs when
            // present; the tablet ignores this key.
            if let ms = obj["macBluetoothCompensationMs"] as? NSNumber {
                comp = ms.doubleValue / 1000.0
            }
            if let sounds = obj["sounds"] as? [String: Any] {
                var parsed: [String: TimeInterval] = [:]
                for (file, raw) in sounds {
                    if let entry = raw as? [String: Any],
                       let lead = entry["animationLeadMs"] as? NSNumber {
                        parsed[file] = lead.doubleValue / 1000.0
                    }
                }
                leads = parsed  // authoritative once the file parses
            }
            overlayInfo("⏱️ sound-timing.json loaded: BT compensation \(Int(comp * 1000))ms, \(leads.count) paired-delay entr\(leads.count == 1 ? "y" : "ies")")
        } else {
            overlayInfo("⏱️ sound-timing.json not found; using built-in defaults (BT compensation \(Int(comp * 1000))ms)")
        }

        bluetoothCompensationSeconds = comp
        animationLeads = leads
    }

    /// The animation→sound lead for a file (0 if none).
    func animationLead(for file: String) -> TimeInterval { animationLeads[file] ?? 0 }

    /// The BT wake-up compensation in effect right now regardless of the current
    /// output route: the tablet-set override if present, else the file default.
    var effectiveBluetoothCompensationSeconds: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return overrideSeconds ?? bluetoothCompensationSeconds
    }

    /// Override the BT wake-up compensation from the tablet slider. Clamped to
    /// `0...maxCompensationSeconds`. Pass a value; there is no "clear" — the
    /// tablet always pushes an explicit number.
    func setBluetoothCompensation(seconds: TimeInterval) {
        let clamped = max(0, min(Self.maxCompensationSeconds, seconds))
        lock.lock(); overrideSeconds = clamped; lock.unlock()
        overlayInfo("⏱️ BT compensation set to \(Int((clamped * 1000).rounded()))ms (tablet slider)")
    }

    /// Compensation to apply **right now**: the effective seconds when the
    /// current default output is Bluetooth, otherwise 0.
    var currentBluetoothCompensation: TimeInterval {
        BluetoothOutput.isDefaultOutputBluetooth ? effectiveBluetoothCompensationSeconds : 0
    }
}
