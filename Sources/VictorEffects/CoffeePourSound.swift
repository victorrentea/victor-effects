import AVFoundation
import Foundation

/// The espresso machine you hear while the 🫖 pours into a ☕ — quietly, under
/// the room, never over it (Victor, 2026-09-30: "în surdină, nu prea tare").
///
/// One looping player, made once and paused between pours rather than rebuilt:
/// the pour switches on and off many times a second as a hand wobbles over a
/// cup, and each switch is a volume fade, not a new file open. Paused, not
/// stopped, so the next pour picks the pump up mid-stroke instead of replaying
/// the same first second every time.
///
/// `espresso_pour.mp3` is bundled (12.5 s, mono): the steady pump stretch of
/// Wikimedia Commons' public-domain "Espresso machine.ogg", loudness-normalised
/// to −18 LUFS, with its last second cross-faded into its first so the loop has
/// no seam. It starts at once — no Bluetooth start delay: a sound that trails
/// the pot by half a second reads as a different event.
final class CoffeePourSound {
    /// Loud enough to recognise, soft enough to talk over.
    static let volume: Float = 0.22
    static let fadeIn: TimeInterval = 0.25
    static let fadeOut: TimeInterval = 0.4

    private var player: AVAudioPlayer?
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
        if on { start() } else { fade(out: generation) }
    }

    private func start() {
        if player == nil {
            guard let url = Bundle.module.url(forResource: "espresso_pour", withExtension: "mp3"),
                  let p = try? AVAudioPlayer(contentsOf: url) else {
                overlayError("espresso_pour.mp3 not found in bundle")
                return
            }
            p.numberOfLoops = -1
            p.prepareToPlay()
            player = p
        }
        guard let p = player else { return }
        if !p.isPlaying {
            p.volume = 0
            p.play()
        }
        p.setVolume(Self.volume, fadeDuration: Self.fadeIn)
    }

    private func fade(out gen: Int) {
        guard let p = player, p.isPlaying else { return }
        p.setVolume(0, fadeDuration: Self.fadeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOut) { [weak self] in
            guard let self, self.generation == gen else { return }
            self.player?.pause()
        }
    }
}
