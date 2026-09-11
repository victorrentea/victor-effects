import AppKit
import Foundation

/// Resting the cursor on a rising ☕ freezes it, charges it for ~3 s, and pops
/// it. This is the 10 Hz poll that notices.
///
/// The *payoff* — pulling a break timer closer — used to run in the same
/// `if` as the pop, because the timer was two properties away. It now lives in
/// another process, so each pop becomes one webhook carrying the point it
/// happened at. That the pop is visible and the payoff is remote is deliberate:
/// the dissolve must never wait on a network call.
final class CoffeeChargeMonitor {
    private weak var animator: EmojiAnimator?
    private var timer: Timer?

    init(animator: EmojiAnimator) {
        self.animator = animator
    }

    func start() {
        stop()
        // 10 Hz on the main run loop in `.common` mode: the charge ring has to
        // keep filling while a menu is open, which the default mode would
        // freeze.
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let animator = self.animator else { return }
            let exploded = animator.tickCoffeeCharge(cursorGlobalPoint: NSEvent.mouseLocation)
            guard !exploded.isEmpty else { return }
            effectsInfo("☕ x\(exploded.count) exploded → \(exploded.count) coffee-popped event(s)")
            for point in exploded { EventWebhook.coffeePopped(at: point) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
