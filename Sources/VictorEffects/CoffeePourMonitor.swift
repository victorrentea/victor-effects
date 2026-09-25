import AppKit
import Foundation

/// The cursor on a rising ☕ turns into a pot and pours into it. This is the
/// 60 Hz tick that notices — 60 and not 10 because the pot rides the mouse
/// from the same tick, and a pointer that lags is a pointer that feels broken.
///
/// The *payoff* — pulling a break timer closer — used to run in the same
/// `if` as the pop, because the timer was two properties away. It now lives in
/// another process, so each payoff (a cup that popped) becomes one webhook
/// carrying the point it happened at. That the picture is local and the payoff
/// is remote is deliberate: the pour must never wait on a network call.
final class CoffeePourMonitor {
    private weak var animator: EmojiAnimator?
    private var timer: Timer?

    init(animator: EmojiAnimator) {
        self.animator = animator
    }

    func start() {
        stop()
        // On the main run loop in `.common` mode: the pour has to keep going
        // while a menu is open, which the default mode would freeze.
        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self, let animator = self.animator else { return }
            let paid = animator.tickCoffeePour(cursorGlobalPoint: NSEvent.mouseLocation)
            guard !paid.isEmpty else { return }
            effectsInfo("☕ x\(paid.count) paid out → \(paid.count) coffee-popped event(s)")
            for point in paid { EventWebhook.coffeePopped(at: point) }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
