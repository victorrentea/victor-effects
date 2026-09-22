import AppKit
import QuartzCore

// MARK: - The gauge

/// Decides when a trickle of ☕ has become a **storm**: strictly more than
/// `threshold` arrivals inside the last `window` seconds. Pure value type, so
/// the decision can be tested with fake clocks and no screen.
///
/// Once tripped the storm **lingers** for `linger` seconds past the last
/// arrival that kept the rate up, and its `intensity` decays over that tail
/// instead of cutting out: a flood is bursty (participants tap in salvos), and
/// a screen that stops shaking between two salvos half a second apart would
/// read as a glitch, not as a lull.
struct CoffeeStormGauge {
    /// A storm is MORE than this many ☕ per `window`.
    var threshold: Int = 4
    var window: TimeInterval = 1.0
    /// How long after the rate drops the storm is still considered on.
    var linger: TimeInterval = 2.0

    private(set) var arrivals: [TimeInterval] = []
    /// The last instant at which the rate was measured above the threshold.
    private(set) var lastOverThreshold: TimeInterval = -.infinity

    /// Record one ☕ arriving at `now`. Answers whether the storm is on
    /// afterwards.
    @discardableResult
    mutating func record(at now: TimeInterval) -> Bool {
        arrivals.append(now)
        prune(at: now)
        if arrivals.count > threshold { lastOverThreshold = now }
        return isStorm(at: now)
    }

    /// ☕ per second over the trailing window, as of `now`.
    func rate(at now: TimeInterval) -> Double {
        let recent = arrivals.filter { now - $0 <= window }.count
        return Double(recent) / window
    }

    func isStorm(at now: TimeInterval) -> Bool {
        now - lastOverThreshold <= linger
    }

    /// 0 when calm, 1 at twice the threshold rate or beyond. While the storm is
    /// lingering after the rate dropped it fades linearly to 0 across `linger`,
    /// with a floor of 0.3 so a lingering storm still visibly shakes.
    func intensity(at now: TimeInterval) -> CGFloat {
        guard isStorm(at: now) else { return 0 }
        let over = rate(at: now) / Double(threshold) - 1          // 0 at threshold, 1 at 2×
        let live = CGFloat(min(max(over, 0), 1))
        let tail = CGFloat(1 - min(max((now - lastOverThreshold) / linger, 0), 1))
        return max(live, 0.3 * tail)
    }

    private mutating func prune(at now: TimeInterval) {
        arrivals.removeAll { now - $0 > window }
    }
}

// MARK: - The screen

/// The desktop itself joining in: a screenshot of the built-in display (with
/// the overlay cut out of it) laid UNDER the emoji as horizontal strips that
/// slosh sideways in a sine wave while the whole sheet jitters, and every pop
/// during the storm kicks the jitter harder. Lives for as long as the caller's
/// `intensity` closure answers non-nil, then fades and removes itself —
/// **self-terminating**, as every overlay here must be.
///
/// The capture is refreshed every ~0.4 s so the screen under the wave stays
/// roughly live; a refresh that cannot exclude the overlay (macOS 13, no
/// Screen Recording grant) keeps the previous picture rather than
/// photographing itself.
final class CoffeeStormScreen {
    private let hostLayer: CALayer
    private var container: CALayer?
    private var strips: [CALayer] = []
    private var timer: Timer?
    private var phase: Double = 0
    private var lastTick: CFTimeInterval = 0
    private var smoothed: CGFloat = 0
    private var kick: CGFloat = 0
    private var lastCapture: CFTimeInterval = 0
    private var capturing = false
    private var intensity: (() -> CGFloat?)?

    static let stripCount = 28

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
    }

    var isRunning: Bool { container != nil }

    /// `intensity` is polled every frame: 0…1 drives the amplitude, nil ends
    /// the storm.
    func start(intensity: @escaping () -> CGFloat?) {
        self.intensity = intensity
        guard container == nil else { return }
        let bounds = hostLayer.bounds
        let container = CALayer()
        container.frame = bounds
        container.backgroundColor = NSColor.black.cgColor
        container.masksToBounds = true
        // A hair of zoom so the shake never shows the black backdrop at the edges.
        container.transform = CATransform3DMakeScale(1.04, 1.04, 1)
        // UNDER everything else: the coffees and their fragments stay on top of
        // the sloshing desktop.
        hostLayer.insertSublayer(container, at: 0)
        self.container = container

        let n = Self.stripCount
        let h = bounds.height / CGFloat(n)
        strips = (0..<n).map { i in
            let s = CALayer()
            s.frame = CGRect(x: 0, y: CGFloat(i) * h, width: bounds.width, height: h)
            s.contentsGravity = .resize
            // Unit coordinates, bottom-up like the layer itself: strip i shows
            // the i-th slice of the picture from the bottom.
            s.contentsRect = CGRect(x: 0, y: CGFloat(i) / CGFloat(n), width: 1, height: 1 / CGFloat(n))
            container.addSublayer(s)
            return s
        }
        lastTick = CACurrentMediaTime()
        smoothed = 0
        kick = 0
        // First picture: the fast path is fine here, the overlay holds nothing
        // but a few emoji, and the excluded refresh replaces it within a beat.
        if let first = EmojiAnimator.captureBuiltInDisplayFast() { apply(first) }
        refreshCapture(now: CACurrentMediaTime())

        let t = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        effectsInfo("☕🌊 coffee storm ON")
    }

    /// A pop happened: throw the sheet harder for a few frames.
    func kick(_ strength: CGFloat) {
        kick = min(kick + strength, 3)
    }

    func stop(fade: Double = 0.4) {
        timer?.invalidate()
        timer = nil
        intensity = nil
        strips = []
        guard let c = container else { return }
        container = nil
        if fade <= 0 { c.removeFromSuperlayer(); return }
        let f = CABasicAnimation(keyPath: "opacity")
        f.fromValue = 1
        f.toValue = 0
        f.duration = fade
        f.fillMode = .forwards
        f.isRemovedOnCompletion = false
        c.add(f, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.05) { c.removeFromSuperlayer() }
        effectsInfo("☕🌊 coffee storm off")
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(max(now - lastTick, 0), 0.1)
        lastTick = now
        guard let target = intensity?() else { stop(); return }

        smoothed += (target - smoothed) * CGFloat(min(1, dt * 6))
        kick = max(0, kick - CGFloat(dt) * 4)
        let amp = smoothed + kick
        phase += dt * (1.6 + Double(smoothed) * 1.4)

        guard let c = container else { return }
        let bounds = hostLayer.bounds
        let n = strips.count
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Wave: sideways offset varies with the strip's height — ~2 wavelengths
        // over the screen, rolling upward.
        let waveAmp = (10 + 34 * amp)
        for (i, s) in strips.enumerated() {
            let f = Double(i) / Double(n)
            let x = waveAmp * CGFloat(sin(f * 2 * .pi * 2.0 - phase * 2 * .pi))
            s.position.x = bounds.midX + x
        }
        // Shake: the whole sheet jitters, with a touch of roll.
        let shake = 3 + 16 * amp
        c.position = CGPoint(x: bounds.midX + CGFloat.random(in: -shake...shake),
                             y: bounds.midY + CGFloat.random(in: -shake...shake))
        let roll = CGFloat.random(in: -0.004...0.004) * (0.5 + amp)
        var m = CATransform3DMakeScale(1.04, 1.04, 1)
        m = CATransform3DRotate(m, roll, 0, 0, 1)
        c.transform = m
        CATransaction.commit()

        if now - lastCapture > 0.4 { refreshCapture(now: now) }
    }

    private func refreshCapture(now: CFTimeInterval) {
        guard !capturing else { return }
        capturing = true
        lastCapture = now
        EmojiAnimator.captureScreenExcludingOverlay { [weak self] image in
            guard let self else { return }
            self.capturing = false
            guard let image, self.container != nil else { return }
            self.apply(image)
        }
    }

    private func apply(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for s in strips { s.contents = image }
        CATransaction.commit()
    }
}
