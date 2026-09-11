import Cocoa

/// Full-width countdown progress bar pinned to the bottom of the screen.
///
/// Triggered from the tablet (3s/5s/7s/10s buttons): a semi-transparent yellow
/// bar grows from the left edge to the full screen width over `seconds`, acting
/// as a discreet warm-up / break timer. When the fill completes the bar fades
/// out so the screen clears. Pressing another value restarts it from zero
/// (latest-wins). Lives on the built-in Retina display alongside the emoji effects.
///
/// The bar spans the FULL screen width — left edge to right edge. A white
/// countdown number is overlaid ON the bar's bottom-left corner, counting the
/// remaining whole seconds (N…1) in sync with the fill, then disappears with the
/// bar on completion / cancel.
///
/// 🏁 The end-of-training countdown (`TrainingEndSequence`) reuses the very same
/// bar with `rider: "🏁"`: an emoji pinned to the fill's leading edge, travelling
/// left→right with it. It rides the head rather than sitting at a fixed spot
/// because that is the only part of the bar the eye is actually tracking — the
/// finish line is where the fill currently *is*, not where the bar ends.
///
/// Rendered as a CALayer on the overlay's host layer — the same layer the emoji
/// effects use — NOT as an NSView subview. Adding a subview onto that
/// manually-populated, layer-backed host view does not composite (the bar never
/// appeared); a CALayer in the same tree renders reliably.
final class ProgressBarOverlay {
    private let hostLayer: CALayer
    private var bar: CALayer?
    private var fadeWork: DispatchWorkItem?

    // Countdown number shown to the left of the bar.
    private var countdownLabel: CATextLayer?
    private var countdownTimer: Timer?
    private var countdownDeadline: Date?

    /// Everything drawn ON the bar (countdown number, 🏁 rider). Kept together so
    /// cancel/fade treat them as one — a decoration that outlived the bar it was
    /// drawn on would be a leftover glyph floating over an empty screen.
    private var decorations: [CALayer] = []

    /// Fired when the bar fills all the way to the right edge — i.e. the
    /// interval elapsed naturally. NOT fired on `cancel()` (manual stop or a
    /// restart-from-zero), since that cancels the pending work item.
    var onComplete: (() -> Void)?

    private static let height: CGFloat = 100           // thick, clearly visible
    private static let alpha: Float = 0.5              // translucent — discreet
    private static let fadeDuration: TimeInterval = 0.5

    // Countdown number overlaid on the bar's bottom-left corner. `numberLeftInset`
    // is the breathing room from the screen's left edge; `numberAreaWidth` is the
    // text box width (left-aligned, so extra width is harmless).
    private static let numberAreaWidth: CGFloat = 200
    private static let numberLeftInset: CGFloat = 24
    private static let numberFontSize: CGFloat = 80

    // The emoji riding the fill's leading edge. Slightly smaller than the
    // countdown number so the two read as label + marker rather than as two
    // competing headlines.
    private static let riderFontSize: CGFloat = 72

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    /// Start (or restart) the bar, filling left→right over `seconds`.
    ///
    /// `rider`, when given, is an emoji pinned to the leading edge of the fill for
    /// the whole run.
    func start(seconds: TimeInterval, rider: String? = nil) {
        guard seconds > 0 else { return }
        cancel()  // restart-from-zero semantics

        let screenWidth = hostLayer.bounds.width > 0
            ? hostLayer.bounds.width
            : (NSScreen.main?.frame.width ?? 1440)
        // The bar spans the full screen width, left edge → right edge.
        let barOriginX: CGFloat = 0
        let width = max(1, screenWidth)

        // anchorPoint at the bottom-left so growing the width fills left→right and
        // position (barOriginX,0) pins it to the bottom-left of the bar region on the
        // host layer (which is non-flipped: origin bottom-left, same as the confetti's
        // "y=0 = bottom").
        let fill = CALayer()
        fill.anchorPoint = CGPoint(x: 0, y: 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)          // no implicit bounds animation
        fill.position = CGPoint(x: barOriginX, y: 0)
        fill.bounds = CGRect(x: 0, y: 0, width: width, height: Self.height)
        fill.backgroundColor = NSColor.systemYellow.cgColor
        fill.opacity = Self.alpha
        hostLayer.addSublayer(fill)
        CATransaction.commit()
        bar = fill

        // The model is already full width; the explicit animation drives the
        // presentation from 0 → full over `seconds`, then holds (no flicker).
        let grow = CABasicAnimation(keyPath: "bounds.size.width")
        grow.fromValue = 0
        grow.toValue = width
        grow.duration = seconds
        grow.timingFunction = CAMediaTimingFunction(name: .linear)
        fill.add(grow, forKey: "fill")

        // White countdown number overlaid on the bar's bottom-left corner. Added
        // after the fill so it renders on top of the yellow. Left-aligned with a
        // small inset from the screen edge, vertically centred within the bar band.
        let lineHeight = Self.numberFontSize * 1.2
        let label = CATextLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        label.anchorPoint = CGPoint(x: 0, y: 0)
        label.frame = CGRect(x: Self.numberLeftInset,
                             y: (Self.height - lineHeight) / 2,
                             width: Self.numberAreaWidth,
                             height: lineHeight)
        label.alignmentMode = .left
        label.foregroundColor = NSColor.white.cgColor
        label.font = NSFont.boldSystemFont(ofSize: Self.numberFontSize)
        label.fontSize = Self.numberFontSize
        label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2   // crisp on Retina
        hostLayer.addSublayer(label)
        CATransaction.commit()
        countdownLabel = label
        decorations = [label]

        if let rider = rider {
            decorations.append(addRider(rider, travelling: width, over: seconds))
        }

        // Drive the number off a deadline so restarts / drift can't desync it from
        // the bar. `ceil(remaining)` yields N…1 through the interval, 0 at the end.
        countdownDeadline = Date().addingTimeInterval(seconds)
        updateCountdown()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateCountdown()
        }
        RunLoop.main.add(timer, forMode: .common)
        countdownTimer = timer

        // After the fill completes, celebrate at the right corner, then fade
        // the bar out so the screen clears.
        let work = DispatchWorkItem { [weak self] in
            self?.onComplete?()
            self?.fadeOut()
        }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        overlayInfo("Progress bar started: \(Int(seconds))s\(rider.map { " \($0)" } ?? "")")
    }

    /// The emoji that travels with the fill's leading edge.
    ///
    /// `anchorPoint.x = 1` puts the glyph's RIGHT edge on the head, so it is always
    /// standing on the yellow rather than out ahead of it on bare desktop — and at
    /// the end it comes to rest flush against the screen's right edge instead of
    /// half off it. The trade is the first fraction of a second, where the head is
    /// still too close to the left edge for the whole glyph to fit; the alternative
    /// (centring it) costs a partly cut-off flag at BOTH ends of the run.
    private func addRider(_ emoji: String, travelling width: CGFloat, over seconds: TimeInterval) -> CALayer {
        let box = Self.riderFontSize * 1.4
        let layer = CATextLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.string = emoji
        layer.fontSize = Self.riderFontSize
        layer.alignmentMode = .center
        layer.anchorPoint = CGPoint(x: 1, y: 0.5)
        layer.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        layer.position = CGPoint(x: 0, y: Self.height / 2)
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        hostLayer.addSublayer(layer)
        CATransaction.commit()

        // Same duration, same linear curve and same 0→width span as the fill, so
        // the two cannot drift apart over the run.
        let travel = CABasicAnimation(keyPath: "position.x")
        travel.fromValue = 0
        travel.toValue = width
        travel.duration = seconds
        travel.timingFunction = CAMediaTimingFunction(name: .linear)
        travel.fillMode = .forwards
        travel.isRemovedOnCompletion = false
        layer.add(travel, forKey: "ride")
        return layer
    }

    /// Refresh the countdown number from the deadline; hide it once time's up.
    private func updateCountdown() {
        guard let deadline = countdownDeadline, let label = countdownLabel else { return }
        let remaining = deadline.timeIntervalSinceNow
        CATransaction.begin()
        CATransaction.setDisableActions(true)          // no implicit contents crossfade
        if remaining <= 0 {
            label.isHidden = true
            countdownTimer?.invalidate()
            countdownTimer = nil
        } else {
            label.string = "\(Int(ceil(remaining)))"
        }
        CATransaction.commit()
    }

    /// Remove the bar (and its decorations) immediately (no fade).
    func cancel() {
        fadeWork?.cancel()
        fadeWork = nil
        tearDownCountdown()
        bar?.removeFromSuperlayer()
        bar = nil
    }

    /// Stop and remove the decorations + the countdown timer.
    private func tearDownCountdown() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownDeadline = nil
        countdownLabel = nil
        for layer in decorations { layer.removeFromSuperlayer() }
        decorations = []
    }

    private func fadeOut() {
        guard let bar = bar else { return }
        self.bar = nil

        // Fade the decorations out alongside the bar (stop the countdown timer
        // first so it can't fight the fade), then remove them.
        countdownTimer?.invalidate()
        countdownTimer = nil
        countdownDeadline = nil
        countdownLabel = nil
        let fading = decorations
        decorations = []

        for layer in [bar] + fading {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = layer.opacity
            fade.toValue = 0
            fade.duration = Self.fadeDuration
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false
            layer.add(fade, forKey: "fadeOut")
            layer.opacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeDuration) { [weak bar] in
            bar?.removeFromSuperlayer()
            for layer in fading { layer.removeFromSuperlayer() }
        }
    }
}
