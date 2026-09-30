import AVFoundation
import Foundation

/// What you hear while the 🫖 pours into a ☕ — quietly, under the room, never
/// over it (Victor, 2026-09-30: "în surdină, nu prea tare").
///
/// Two clips, because the pot tells a story (Victor, 2026-09-30): the FIRST
/// cup is brewed — an espresso machine; once the break timer is open the pot
/// is already full of coffee and each further cup is just poured — liquid into
/// a mug, no machine. `potIsFull` picks between them, and is read only when a
/// pour STARTS: a clip never swaps under a pour that is already running.
///
/// One looping player per clip, made once and paused between pours rather
/// than rebuilt: the pour switches on and off many times a second as a hand
/// wobbles over a cup, and each switch is a volume fade, not a new file open.
/// Paused, not stopped, so the next pour picks up mid-stroke instead of
/// replaying the same first second every time.
///
/// Both clips are bundled, public domain (Wikimedia Commons), mono, normalised
/// to −18 LUFS, their last second cross-faded into their first so the loop has
/// no seam:
/// - `espresso_pour.mp3` (12.5 s): the steady pump stretch of "Espresso machine.ogg".
/// - `coffee_pour.mp3` (5.6 s): the steady stream of "Boiling water being poured
///   into a mug for tea.ogg" (3.0–9.6 s), its natural fade-out ramped flat first.
///
/// They start at once — no Bluetooth start delay: a sound that trails the pot
/// by half a second reads as a different event.
final class CoffeePourSound {
    enum Clip: String {
        case espresso = "espresso_pour"
        case pour = "coffee_pour"
    }

    /// Loud enough to recognise, soft enough to talk over.
    static let volume: Float = 0.22
    static let fadeIn: TimeInterval = 0.25
    static let fadeOut: TimeInterval = 0.4

    /// True while the break timer is open: the coffee is already made, so a
    /// pour is only a pour. Set by the owner (`EmojiAnimator`) from the addons
    /// app's answer and from its own payouts.
    var potIsFull = false

    private var players: [Clip: AVAudioPlayer] = [:]
    /// The clip of the current (or last) pour — the one a fade-out pauses.
    private var current: Clip = .espresso
    private var pouring = false
    /// Bumped on every switch, so a fade-out's pause cannot land on a pour
    /// that started again inside it.
    private var generation = 0

    /// Main thread only (AVAudioPlayer is not thread-safe). Idempotent — the
    /// pour tick calls it 60 times a second.
    func setPouring(_ on: Bool) {
        guard on != pouring else { return }
        pouring = on
        generation &+= 1
        if on { start(potIsFull ? .pour : .espresso) } else { fade(out: generation) }
    }

    private func player(_ clip: Clip) -> AVAudioPlayer? {
        if let p = players[clip] { return p }
        guard let url = Bundle.module.url(forResource: clip.rawValue, withExtension: "mp3"),
              let p = try? AVAudioPlayer(contentsOf: url) else {
            overlayError("\(clip.rawValue).mp3 not found in bundle")
            return nil
        }
        p.numberOfLoops = -1
        p.prepareToPlay()
        players[clip] = p
        return p
    }

    private func start(_ clip: Clip) {
        // The other clip may still be fading out from a pour a moment ago:
        // silence it now, so the machine never hums under a plain pour.
        if clip != current, let old = players[current], old.isPlaying {
            old.pause()
        }
        current = clip
        guard let p = player(clip) else { return }
        if !p.isPlaying {
            p.volume = 0
            p.play()
        }
        p.setVolume(Self.volume, fadeDuration: Self.fadeIn)
    }

    private func fade(out gen: Int) {
        guard let p = players[current], p.isPlaying else { return }
        p.setVolume(0, fadeDuration: Self.fadeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut) { [weak self, weak p] in
            guard let self, self.generation == gen else { return }
            p?.pause()
        }
    }
}

/// Is the break timer open? It lives in the addons app, so this asks it —
/// `GET /test/break/state` → `{"showing":true,…}` — without ever waiting: the
/// answer lands in `completion` on the main thread, and a failed call (addons
/// down) answers nothing, leaving whatever the caller already believed.
enum BreakTimerProbe {
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 1.0
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    static func isShowing(_ completion: @escaping (Bool) -> Void) {
        let base = EffectsConfig.shared.addonsBaseURL
        guard !base.isEmpty, let url = URL(string: base + "/test/break/state") else { return }
        session.dataTask(with: url) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let showing = json["showing"] as? Bool else { return }
            DispatchQueue.main.async { completion(showing) }
        }.resume()
    }
}
