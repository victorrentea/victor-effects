import AppKit
import AVFoundation
import CoreImage
import QuartzCore
import ScreenCaptureKit

class EmojiAnimator {
    private let hostLayer: CALayer

    static let emojiSet = ["❤️", "🔥", "👏", "😂", "🤯", "💡", "☕", "✅", "❌"]

    // Image-extracted ECG beat curve (64 points, normalized x∈[0,1], y∈[-1,1], R-spike at x≈0.3465)
    private static let beatCurve: [(Double, Double)] = [
        (0.0000,0.0000), (0.0157,0.0054), (0.0315,0.0291), (0.0472,0.0560),
        (0.0630,0.0891), (0.0787,0.1258), (0.0945,0.2001), (0.1102,0.2375),
        (0.1260,0.2755), (0.1417,0.2809), (0.1575,0.2320), (0.1732,0.1614),
        (0.1890,0.0915), (0.2047,0.0496), (0.2205,-0.0438), (0.2362,-0.1079),
        (0.2520,-0.1122), (0.2677,-0.1312), (0.2835,-0.1176), (0.2992,0.0083),
        (0.3150,0.3795), (0.3307,0.7897), (0.3465,0.9132), (0.3622,0.9064),
        (0.3780,0.6096), (0.3937,0.4664), (0.4094,0.1651), (0.4252,-0.2663),
        (0.4409,-0.3111), (0.4567,-0.2185), (0.4724,-0.0557), (0.4882,-0.0400),
        (0.5039,-0.0197), (0.5197,-0.0020), (0.5354,0.0116), (0.5512,0.0062),
        (0.5669,0.0112), (0.5827,0.0196), (0.5984,0.0198), (0.6142,0.0171),
        (0.6299,0.0115), (0.6457,0.0059), (0.6614,0.0090), (0.6772,0.0005),
        (0.6929,-0.0087), (0.7087,0.0039), (0.7244,0.0185), (0.7402,0.0268),
        (0.7559,0.1190), (0.7717,0.1651), (0.7874,0.1964), (0.8031,0.2486),
        (0.8189,0.3517), (0.8346,0.3388), (0.8504,0.3551), (0.8661,0.3484),
        (0.8819,0.3192), (0.9055,0.3217), (0.9213,0.1663), (0.9370,0.1384),
        (0.9528,0.0871), (0.9685,0.0368), (0.9843,0.0190), (1.0000,-0.0000)
    ]

    // Track active toggleable effects (danger, sepia, zorro) so clicking again cancels them
    private var activeEffects: [String: CALayer] = [:]

    // Floating ☕ layers currently rising on screen. They're hover targets: parking
    // the cursor on one (hit-tested via AppDelegate's poll timer) FREEZES it and
    // begins a hold-charge — see tickCoffeeCharge.
    private var activeCoffeeLayers: [CATextLayer] = []

    // Hover-to-hold coffee gesture. Resting the cursor on a rising ☕ freezes it in
    // place and grows it for `coffeeChargeSeconds`; completing the hold explodes it
    // (the payoff — start / shorten the break — is the caller's, in AppDelegate).
    // EVERY coffee under the cursor charges at once, each on its own clock, so
    // parking on a cluster inflates the whole cluster and they pop as they ripen;
    // what counts is how many actually explode. The cursor leaving a coffee's box
    // releases that one alone, back into its rise.
    private struct CoffeeCharge {
        let layer: CATextLayer
        let start: CFTimeInterval
    }
    private var coffeeCharges: [CoffeeCharge] = []
    static let coffeeChargeSeconds: Double = 3.0

    // ☕🌊 A flood of coffees — more than 4 in a second — is a STORM. The key
    // is that the cups MOVE differently: instead of the calm rise they fly a
    // wild flight (`addStormFlight`) — spawned across the width, swinging in
    // wide zigzags, tumbling, climbing higher and faster — somewhat bigger,
    // and at the top of it they DETONATE into many pieces instead of fading
    // out. A hovered pop during the storm goes off the same way. All of it is
    // progressive: the longer and denser the flood, the wilder, bigger and
    // more violent (`CoffeeStormGauge.intensity`). A first cut also shook and
    // rippled the desktop under the cups; that was too disruptive to present
    // over and came out the same morning — the cups carry the storm alone.
    private var coffeeStorm = CoffeeStormGauge()
    /// How much bigger a ☕ spawns during a storm, at intensity 0 and 1.
    private static let coffeeStormSpawnScale: ClosedRange<CGFloat> = 1.3...2.0
    /// How hard a storm pop flings its fragments, at intensity 0 and 1.
    private static let coffeeStormViolence: ClosedRange<CGFloat> = 2.0...3.6
    /// A storm cup shatters into this many tiles per side (a calm pop: 12).
    private static let coffeeStormGrid = 22
    var coffeeStormActive: Bool { coffeeStorm.isStorm(at: CACurrentMediaTime()) }
    private static let coffeeChargeGrowScale: CGFloat = 2.6
    private static let coffeeHitSlop: CGFloat = 34
    /// How long a calm ☕ hangs at the cursor before fading — comfortably longer
    /// than `coffeeChargeSeconds`, so a cup that arrives under a resting hand can
    /// finish its hold without the flight pulling it away mid-charge.
    private static let coffeeApproachDwell: Double = 4.5

    // Every reaction emoji spawns at the same height and rides the same rise, which
    // is what lets a released ☕ work out how far up it had already got without
    // anyone bookkeeping its flight — see releaseCoffeeCharge.
    private static let emojiSize: CGFloat = 91
    private static let emojiSpawnY: CGFloat = 80
    private static let emojiRiseHeight: CGFloat = 540
    private static let emojiRiseScale: CGFloat = 1.3
    private static let emojiRiseSeconds: Double = 3.25

    // Pulse: layers stored so clicking again can stop it
    private var pulseRunning = false
    private var _pulseDimLayer: CALayer?
    private var _pulseGridLayer: CALayer?
    private var _pulseEcgLayer: CALayer?

    // Spiral hearts: a pulsing red heart that floats just above the cursor while the effect runs
    private var _heartCursorLayer: CALayer?
    private var _heartCursorTimer: Timer?
    private var _heartCursorActiveUntil: CFTimeInterval = 0
    private var _heartCursorHidSystemCursor = false   // balance hide/unhide of the real cursor

    // Fear 😱: the scared face follows the live mouse (cursor hidden) while it grows + fades
    private var _fearLayer: CATextLayer?
    private var _fearTimer: Timer?
    private var _fearHidCursor = false                // balance hide/unhide of the real cursor

    // ☢️ Nuke bombardment: the pointer stays the ordinary pointer for the whole
    // run — nothing is hidden and nothing rides the mouse — and CLICKING plants a
    // red target. The planted one stays where it was clicked, turns slowly
    // counter-clockwise while its own fuse runs down, and a bomb whistles down
    // from the top of the screen onto it. Several targets can be planted, so the
    // bombs land in the rhythm they were clicked; the run ends with the last
    // bomb's animation.
    private var _bombEpoch: Int = 0                   // bumped on every (re)press; stale continuations bail
    private var _bombPlanted: [CALayer] = []          // clicked targets, fuse still running
    private var _bombFalling: [CALayer] = []          // bomb sprites still in the air
    private var _bombStrikeLayers: [CALayer] = []     // targets mid strike-pop/fade
    private var _bombBlasts: [CALayer] = []           // explosion gifs currently on screen
    private var _bombPending = 0                      // bombs neither landed nor finished burning
    private var _bombSessionActive = false
    private var _bombPlantedAny = false               // false → the big bomb may still be the one that lands
    private var _bombBigDropped = false               // true → the big one is falling; aiming is over
    private var _bombInputTap: CFMachPort?
    private var _bombInputTapSource: CFRunLoopSource?

    // 🔫 Minigun aiming reticle: during the bullet-holes (#22) burst a bigger,
    // always-red copy of the sniper crosshair tracks the cursor (where the
    // bullets cluster), real cursor hidden. No arming/fuse — it's red from the
    // first frame and just follows until the burst ends. It appears on the same
    // instant as the gun, the first hole and the first frame of noise —
    // `minigunAimLeadIn` is 0, and the reveal path still honours it if a beat is
    // ever put back.
    private var _minigunReticleLayer: CALayer?
    private var _minigunReticleTimer: Timer?
    private var _minigunReticleHidCursor = false      // balance hide/unhide of the real cursor
    // The gun sprite rides the same 60fps timer as the reticle, so it can never
    // outlive it or lag a frame behind it: one tick moves both. Held weakly —
    // the layer itself belongs to the burst's container.
    private weak var _minigunGunLayer: CALayer?

    // 🪚 Chainsaw cursor: for the length of tile #18 the pointer IS a running
    // chainsaw — a 16-frame sprite looping on the cursor, real cursor hidden.
    // Lives OUTSIDE `activeEffects` (own follow timer + hidden cursor), like the
    // minigun reticle, so `stopAllActiveEffects` tears it down explicitly.
    private var _chainsawLayer: CALayer?
    private var _chainsawTimer: Timer?
    private var _chainsawHidCursor = false            // balance hide/unhide of the real cursor
    private var _chainsawGeneration = 0               // guards a stale run's self-stop against a newer one
    // The kerf the saw leaves, and the screen coming apart along it. The
    // container holds the cut, the black holes and the pieces in mid-air, so
    // teardown is one `removeFromSuperlayer` however much damage was done.
    private var _chainsawDamage: CALayer?
    private var _chainsawKerfLayer: CAShapeLayer?
    private var _chainsawKerfPath: CGMutablePath?
    private var _chainsawMask: ChainsawCutMask?
    private var _chainsawScreenshot: CGImage?         // the sheet being sawn, grabbed before the saw appears
    private var _chainsawLastCut: CGPoint?            // previous sample, so the kerf is a stroke and not dots
    private var _chainsawTicksToSweep = 0             // connectivity runs at a fraction of the follow rate
    private var _chainsawSparks: CAEmitterLayer?      // the shower thrown off the biting point, always on

    // 🕳️ Iris close: a black radial overlay (transparent centre, opaque edges)
    // whose clear hole shrinks from the screen-circumscribing circle down to
    // nothing over ~5s — a cinematic "iris out" blackout. The layer itself is
    // silent; the tablet-routed press pairs it with the gong (50_gong.mp3) in
    // AppDelegate's onSoundPlay. Kept OUTSIDE
    // `activeEffects` on purpose: the tablet fires /effect/stop-all before every
    // tile press, so for a SECOND press of the same tile to *cancel* (not
    // restart) the iris, it must survive stop-all and toggle itself here.
    private var _irisLayer: CAGradientLayer?

    init(hostLayer: CALayer) {
        self.hostLayer = hostLayer
        Self.warmBrotherCache()
    }

    /// Cancel a running toggleable effect. Returns true if it was running (and got cancelled).
    private func cancelIfRunning(_ key: String, sound: String? = nil) -> Bool {
        if let layer = activeEffects[key] {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
            activeEffects.removeValue(forKey: key)
            if let sound = sound {
                SoundManager.shared.stop(sound, fade: SoundManager.interruptFade)
            }
            return true
        }
        return false
    }

    /// Register a layer as an active toggleable effect, with auto-cleanup after duration.
    private func trackEffect(_ key: String, layer: CALayer, duration: Double, sound: String? = nil) {
        activeEffects[key] = layer
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak layer] in
            guard let self = self, let layer = layer else { return }
            // Only clean up if this layer is still the active one for this key
            if self.activeEffects[key] === layer {
                self.activeEffects.removeValue(forKey: key)
            }
            layer.removeFromSuperlayer()
            if let sound = sound {
                SoundManager.shared.stop(sound)
            }
        }
    }

    func spawnEmoji(_ emoji: String = "❤️", glow: String? = nil) {
        let fontSize: CGFloat = 78
        let size = Self.emojiSize

        let spawnX: CGFloat = 100 + CGFloat.random(in: -56...56)
        let spawnY = Self.emojiSpawnY

        let layer = CATextLayer()
        layer.string = emoji
        layer.fontSize = fontSize
        layer.alignmentMode = .center
        layer.frame = CGRect(x: spawnX - size / 2, y: spawnY, width: size, height: size)
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        // Per-participant halo: a coloured glow around the (unchanged) emoji so the
        // trainer can tell how many distinct people are reacting — same sender →
        // same colour. No colour → no halo (unchanged look).
        if let glow = glow, let color = Self.nsColor(fromHex: glow) {
            layer.shadowColor = color.cgColor
            layer.shadowRadius = 14
            layer.shadowOpacity = 0.95
            layer.shadowOffset = .zero
            layer.masksToBounds = false
        }

        hostLayer.addSublayer(layer)

        // ☕ layers are clickable (see popCoffee): remember them while on screen.
        // Which glyph charges is configurable — it is the one piece of the
        // gesture a host might want to re-key (`chargeEmoji`).
        let isCoffee = EffectsConfig.shared.chargeEmoji.contains(emoji)
        if isCoffee { activeCoffeeLayers.append(layer) }

        // Storm? Every ☕ arrival feeds the gauge; past the threshold the cup
        // takes the wild flight instead of the calm rise.
        if isCoffee {
            let now = CACurrentMediaTime()
            if coffeeStorm.record(at: now) {
                addStormFlight(layer, intensity: coffeeStorm.intensity(at: now))
                return
            }
            // Calm: come to the hand. Every cup rides the one lane that ends at the
            // cursor (CoffeeFlight.approach), so catching one for the hold-charge is
            // a decision instead of a guess. Falls through to the old rise only when
            // there is no cursor to aim at (it is on another display).
            if addCoffeeApproach(layer) { return }
        }

        // Randomize duration: 2.5–4 seconds (matches browser host.js)
        let duration = Double.random(in: 2.5...4.0)

        addRiseAndFade(layer,
                       from: layer.position,
                       rise: Self.emojiRiseHeight,
                       driftX: CGFloat.random(in: -50...50),
                       duration: duration,
                       scaleValues: [1.0, Self.emojiRiseScale],
                       scaleKeyTimes: [0, 1],
                       fadeStartFraction: 0.4,
                       isCoffee: isCoffee)
    }

    /// ☕ The calm flight: one shared lane from the spawn point to **the cursor**,
    /// where the cup then hangs for a beat before fading.
    ///
    /// The dwell at the end is the point of the whole thing: the hold-charge needs
    /// the cursor to rest on a cup for 3 s, and a cup that flew to the cursor and
    /// kept going would hand back the same guessing game it was meant to end. It
    /// arrives, it waits, and `tickCoffeeCharge` — which reads the layer's
    /// *presentation* frame — finds it sitting there.
    ///
    /// No rotation. A cup that comes up spinning reads as debris; this one is being
    /// offered.
    ///
    /// Returns false when there is no cursor on the overlay's screen, leaving the
    /// caller to use the plain rise.
    @discardableResult
    private func addCoffeeApproach(_ layer: CATextLayer) -> Bool {
        guard let screen = Self.builtInScreenFrame() else { return false }
        let global = NSEvent.mouseLocation
        guard screen.contains(global) else { return false }

        let bounds = hostLayer.bounds
        let start = layer.position
        let target = CoffeeFlight.clamp(CGPoint(x: global.x - screen.origin.x,
                                                y: global.y - screen.origin.y),
                                        in: bounds, margin: Self.emojiSize * 0.6)

        let travel = CoffeeFlight.approachDuration(from: start, to: target)
        let dwell = Self.coffeeApproachDwell
        let total = travel + dwell

        let path = CGMutablePath()
        let pts = CoffeeFlight.approach(from: start, to: target)
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }

        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .cubic
        move.duration = travel
        move.timingFunction = CAMediaTimingFunction(name: .easeOut)
        move.fillMode = .forwards

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1.0
        scale.toValue = Self.emojiRiseScale
        scale.duration = travel
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        scale.fillMode = .forwards

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.beginTime = travel + dwell * 0.45
        fade.duration = dwell * 0.55
        fade.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [move, scale, fade]
        group.duration = total
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let layer = layer else { return }
            // Caught for a hold-charge on the way in (or during the dwell): the
            // charge owns the layer now.
            if self?.coffeeCharges.contains(where: { $0.layer === layer }) == true { return }
            layer.removeFromSuperlayer()
            self?.activeCoffeeLayers.removeAll { $0 === layer }
        }
        layer.add(group, forKey: "floatAndFade")
        CATransaction.commit()
        return true
    }

    private static func stormViolence(at intensity: CGFloat) -> CGFloat {
        let r = coffeeStormViolence
        return r.lowerBound + (r.upperBound - r.lowerBound) * intensity
    }

    /// ☕🌊 The storm flight, `k` = intensity 0…1. Everything about it scales
    /// with `k`:
    ///
    /// - **where** it starts: the calm cups all leave from x≈100; a storm cup
    ///   can leave from anywhere across up to the whole width;
    /// - **how** it flies: a wide sideways zigzag (80…400 px either way, 1.5…3
    ///   swings) with a sideways drift, tumbling as it goes (a rock of ±20° at
    ///   the start, whole spins at full intensity), climbing higher (up to the
    ///   top of the screen) and faster than the calm rise;
    /// - **how big**: 1.3…2× the calm cup, still growing on the way up;
    /// - **how it ends**: solid to the top, then it goes off 100% into
    ///   `coffeeStormGrid`² fragments at `stormViolence`. Visual only — the
    ///   break-timer payoff belongs to the deliberate hover gesture, so a cup
    ///   nobody touched fires no webhook.
    ///
    /// It stays hoverable throughout: it is in `activeCoffeeLayers` like any
    /// other cup, a catch freezes it where it is (`beginCoffeeCharge`) and a
    /// release resumes the CALM rise from there (`releaseCoffeeCharge` knows
    /// only that one) — an accepted simplification, the storm has plenty more.
    private func addStormFlight(_ layer: CATextLayer, intensity k: CGFloat) {
        let bounds = hostLayer.bounds
        let r = Self.coffeeStormSpawnScale
        let baseScale = r.lowerBound + (r.upperBound - r.lowerBound) * k
        let violence = Self.stormViolence(at: k)

        // Spread across the screen as the flood grows.
        let spawnSpread = (bounds.width - 200) * k
        let startX = 100 + CGFloat.random(in: 0...max(spawnSpread, 1))
        let start = CGPoint(x: startX, y: layer.position.y)
        layer.position = start

        // Aim for the MIDDLE of the screen, scattered — not for the top edge.
        // Climbing to the ceiling put every detonation in the same strip above the
        // slides; the middle is where the room is already looking, and a scatter
        // around it is what "in diverse locuri" means. The scatter widens with the
        // flood.
        let spread = CGSize(width: bounds.width * (0.16 + 0.22 * k),
                            height: bounds.height * (0.12 + 0.18 * k))
        let target = CoffeeFlight.clamp(
            CoffeeFlight.blastPoint(center: CGPoint(x: bounds.midX, y: bounds.midY),
                                    spread: spread,
                                    angle: CGFloat.random(in: 0...(2 * .pi)),
                                    unitRadius: CGFloat.random(in: 0...1)),
            in: bounds, margin: 60 * baseScale)

        let swayAmp = 80 + 320 * k
        let swings = 1.5 + 1.5 * k + CGFloat.random(in: -0.3...0.3)
        let phase = CGFloat.random(in: 0...(2 * .pi))
        let steps = 48
        let pts = CoffeeFlight.sweep(from: start, to: target,
                                     amplitude: swayAmp, swings: swings,
                                     phase: phase, steps: steps)
        let path = CGMutablePath()
        path.move(to: pts[0])
        for p in pts.dropFirst() { path.addLine(to: p) }
        let end = pts[pts.count - 1]
        let move = CAKeyframeAnimation(keyPath: "position")
        move.path = path
        move.calculationMode = .cubic

        // Grows on the way in, with a throb riding on the wave. NO rotation: a cup
        // that comes in spinning reads as a thrown object rather than as coffee,
        // and the wave already carries the violence.
        var scales: [CGFloat] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            scales.append(baseScale * (1 + (Self.emojiRiseScale - 1) * t) * (1 + 0.08 * k * sin(t * 4 * .pi * swings)))
        }
        let tumble = CAKeyframeAnimation(keyPath: "transform.scale")
        tumble.values = scales.map { NSNumber(value: Double($0)) }

        let duration = Double.random(in: 2.4...3.4) / Double(1 + 0.4 * k)
        // Solid to the end: it is about to blow up, and a cup that had already
        // faded would blow up invisibly. A hair of fade so the swap to the
        // fragments never shows a seam.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.beginTime = duration * 0.97
        fade.duration = duration * 0.03
        fade.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [move, tumble, fade]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        let side = Self.emojiSize * (scales.last ?? baseScale)
        let grid = Self.coffeeStormGrid
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let layer = layer else { return }
            // Caught mid-flight for a hold-charge: the charge owns it now.
            if self?.coffeeCharges.contains(where: { $0.layer === layer }) == true { return }
            layer.removeFromSuperlayer()
            self?.activeCoffeeLayers.removeAll { $0 === layer }
            self?.pixelDissolve(at: end, side: side, violence: violence, grid: grid)
        }
        layer.add(group, forKey: "floatAndFade")
        CATransaction.commit()
    }

    /// Test hook (`/test/coffee/storm`): a salvo of ☕ at ~8 per second for
    /// `seconds`, well past the 4/s threshold, so the storm can be rehearsed
    /// without a room tapping the tablet. 2.5 s × 8 = 20 cups, close to the
    /// gauge's escalation cap, so the salvo shows the whole ramp.
    func spawnCoffeeStormForTest(seconds: Double = 2.5) {
        let emoji = EffectsConfig.shared.chargeEmoji.first ?? "☕"
        let perSecond = 8
        let total = Int(seconds * Double(perSecond))
        for i in 0..<total {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) / Double(perSecond)) { [weak self] in
                self?.spawnEmoji(emoji)
            }
        }
    }

    /// The flight every reaction emoji rides: a rise with a divergent sideways drift,
    /// a slight growth and a fade-out, grouped so one completion block owns the
    /// layer's removal. Factored out because a ☕ whose hold was abandoned REJOINS
    /// this same flight from wherever it was frozen (`releaseCoffeeCharge`) instead of
    /// being thrown away, and from there on it must fly — and die — exactly like the
    /// ones nobody ever touched. `scaleValues`/`scaleKeyTimes` are the caller's
    /// because that is the only part a resumed coffee needs different: it has to
    /// shrink back down first.
    private func addRiseAndFade(_ layer: CATextLayer,
                                from start: CGPoint,
                                rise: CGFloat,
                                driftX: CGFloat,
                                duration: Double,
                                scaleValues: [CGFloat],
                                scaleKeyTimes: [NSNumber],
                                fadeStartFraction: Double,
                                isCoffee: Bool) {
        let steps = 20
        let path = CGMutablePath()
        path.move(to: start)
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            path.addLine(to: CGPoint(x: start.x + t * driftX, y: start.y + rise * t))
        }

        let pathAnim = CAKeyframeAnimation(keyPath: "position")
        pathAnim.path = path
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = scaleValues
        scaleAnim.keyTimes = scaleKeyTimes
        scaleAnim.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeOut),
                                          count: max(scaleValues.count - 1, 1))

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = duration * fadeStartFraction
        fadeOut.duration = duration * (1 - fadeStartFraction)
        fadeOut.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [pathAnim, scaleAnim, fadeOut]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let layer = layer else { return }
            // If this coffee got caught (again) mid-flight for a hold-charge, the
            // charge owns its lifecycle now — don't let the rise/fade removal pull it
            // off screen underneath the growing hover.
            if isCoffee, self?.coffeeCharges.contains(where: { $0.layer === layer }) == true { return }
            layer.removeFromSuperlayer()
            if isCoffee { self?.activeCoffeeLayers.removeAll { $0 === layer } }
        }
        layer.add(group, forKey: "floatAndFade")
        CATransaction.commit()
    }

    /// Drive the hover-to-hold coffee gesture. Call every poll tick (~0.1s) with the
    /// current global cursor point. Returns WHERE (global coords) each coffee that
    /// finished its `coffeeChargeSeconds` hold exploded on this tick — the caller
    /// turns each one into a minute off the break (or the first one into a fresh
    /// break timer). The POSITIONS, not just the count, because both payoffs start
    /// at the coffee: the fresh timer zooms in from there and each later minute
    /// flies to the clock from there.
    ///
    /// Every coffee under the cursor charges simultaneously: parking on a cluster
    /// inflates all of them, each frozen in place and growing steadily (the growth is
    /// its own 3-second progress bar), and they pop as they ripen. Only the ones that
    /// actually explode count. A coffee whose box the cursor has left is released
    /// individually — it shrinks back and resumes its rise, the others keep charging.
    /// A generous hit slop keeps both the catch and the hold forgiving.
    func tickCoffeeCharge(cursorGlobalPoint globalPoint: CGPoint) -> [CGPoint] {
        guard let frame = Self.builtInScreenFrame() else { return [] }
        // Overlay panel covers the built-in screen; its layer origin (0,0) sits at
        // the screen's bottom-left, so shift the global point by the screen origin.
        let p = CGPoint(x: globalPoint.x - frame.origin.x, y: globalPoint.y - frame.origin.y)
        let pad = Self.coffeeHitSlop
        let now = CACurrentMediaTime()
        func box(_ layer: CATextLayer) -> CGRect {
            (layer.presentation()?.frame ?? layer.frame).insetBy(dx: -pad, dy: -pad)
        }

        // --- Charging ones: complete, release, or keep each on its own clock ---
        var exploded: [CGPoint] = []
        var stillCharging: [CoffeeCharge] = []
        for charge in coffeeCharges {
            if !box(charge.layer).contains(p) {
                releaseCoffeeCharge(charge.layer)
            } else if now - charge.start >= Self.coffeeChargeSeconds {
                let at = explodeCoffee(charge.layer)
                exploded.append(CGPoint(x: at.x + frame.origin.x, y: at.y + frame.origin.y))
            } else {
                stillCharging.append(charge)
            }
        }
        coffeeCharges = stillCharging

        // --- Catch EVERY fresh coffee under the cursor (they all inflate together) ---
        for layer in activeCoffeeLayers where box(layer).contains(p) {
            beginCoffeeCharge(layer, now: now)   // snapshot semantics: safe to mutate the pool inside
        }
        return exploded
    }

    /// Catch a coffee: freeze it where it visually is, stop its rise/fade, and start
    /// the steady 3-second grow that doubles as the hold's progress indicator.
    private func beginCoffeeCharge(_ layer: CATextLayer, now: CFTimeInterval) {
        let pos = layer.presentation()?.position ?? layer.position
        // Registered FIRST: guards the original rise/fade completion block.
        coffeeCharges.append(CoffeeCharge(layer: layer, start: now))
        activeCoffeeLayers.removeAll { $0 === layer }   // out of the auto-rising pool
        layer.removeAllAnimations()
        layer.position = pos
        layer.opacity = 1
        layer.transform = CATransform3DMakeScale(Self.coffeeChargeGrowScale, Self.coffeeChargeGrowScale, 1)
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = Self.coffeeChargeGrowScale
        grow.duration = Self.coffeeChargeSeconds
        grow.timingFunction = CAMediaTimingFunction(name: .linear)
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false
        layer.add(grow, forKey: "charge")
    }

    /// Cursor slipped off this coffee before its hold finished. Hesitating is NOT
    /// fatal to the cup: it shrinks back to the size it would have had by now and
    /// carries on rising from where it was frozen, catchable again on the way up, as
    /// if it had never been touched. (It used to fade out on the spot, which read as
    /// the coffee being killed for having been hovered.) Only this one is released;
    /// any sibling coffees keep charging.
    private func releaseCoffeeCharge(_ layer: CATextLayer) {
        let pres = layer.presentation()
        let pos = pres?.position ?? layer.position
        let heldScale = CGFloat((pres?.value(forKeyPath: "transform.scale") as? Double) ?? 1)
        layer.removeAllAnimations()
        layer.position = pos
        layer.opacity = 1
        layer.transform = CATransform3DIdentity

        // How far along the standard flight it was when caught — every emoji starts at
        // the same y and climbs the same height, so the frozen position says it all.
        let flightStartY = Self.emojiSpawnY + Self.emojiSize / 2
        let progress = min(max((pos.y - flightStartY) / Self.emojiRiseHeight, 0), 1)
        let remaining = 1 - progress
        let duration = max(0.5, Self.emojiRiseSeconds * Double(remaining))
        // Snap back to the size the untouched flight would be at now (~0.3s), then
        // resume growing towards the usual 1.3 over what is left of the climb.
        let settled = 1 + (Self.emojiRiseScale - 1) * progress
        let snapBack = min(0.3 / duration, 0.5)

        activeCoffeeLayers.append(layer)   // back in the pool: hoverable again
        addRiseAndFade(layer,
                       from: pos,
                       rise: Self.emojiRiseHeight * remaining,
                       driftX: CGFloat.random(in: -50...50) * remaining,
                       duration: duration,
                       scaleValues: [heldScale, settled, Self.emojiRiseScale],
                       scaleKeyTimes: [0, NSNumber(value: snapBack), 1],
                       fadeStartFraction: 0.4,
                       isCoffee: true)
    }

    /// The hold completed: the coffee doesn't get a 💥 pasted on top of it — it
    /// FRAGMENTS. The ☕ layer goes away in the same frame and its own rendered
    /// pixels take its place as a grid of little square tiles that blow apart while
    /// the cloud as a whole keeps growing (see `pixelDissolve`), so the pop reads as
    /// the cup shattering rather than as a second emoji arriving. Returns the
    /// explosion centre in overlay-layer coords, which is where the payoff starts
    /// from (the timer's zoom-in, or the −1 token's flight).
    @discardableResult
    private func explodeCoffee(_ coffee: CATextLayer) -> CGPoint {
        let pres = coffee.presentation() ?? coffee
        let center = pres.position
        // The charge grew the cup via transform.scale, so its on-screen box is the
        // layer box times that scale — the size the fragments must start at.
        let scale = max(0.1, pres.transform.m11)
        let side = pres.bounds.width * scale

        coffee.removeAllAnimations()
        coffee.removeFromSuperlayer()
        // In a storm the cup does not dissolve, it DETONATES: many more
        // fragments, flying further and spinning harder, under a real flash.
        let now = CACurrentMediaTime()
        if coffeeStorm.isStorm(at: now) {
            pixelDissolve(at: center, side: side,
                          violence: Self.stormViolence(at: coffeeStorm.intensity(at: now)),
                          grid: Self.coffeeStormGrid)
        } else {
            pixelDissolve(at: center, side: side)
        }
        return center
    }

    // MARK: - Pixel dissolve

    /// The ☕ glyph is diced into `dissolveGrid²` square tiles. 12×12 over a ~240px
    /// popped cup gives ~20px fragments: chunky enough to read as pixels, fine
    /// enough to still look like a cup for the first frames.
    private static let dissolveGrid = 12
    private static var _dissolveTiles: [Int: [(row: Int, col: Int, image: CGImage)]] = [:]

    /// The cup rendered once and cut into tiles, laid out the way `CATextLayer`
    /// draws it inside its box — horizontally centred, anchored at the TOP (that's
    /// where CATextLayer puts the first line) — so each fragment starts on exactly
    /// the pixels it replaces and the swap is invisible.
    private static func dissolveTiles(grid g: Int = dissolveGrid) -> [(row: Int, col: Int, image: CGImage)] {
        if let cached = _dissolveTiles[g] { return cached }
        let side: CGFloat = 91                        // the spawnEmoji box
        let img = NSImage(size: NSSize(width: side, height: side))
        img.lockFocus()
        let str = NSAttributedString(string: "☕", attributes: [.font: NSFont.systemFont(ofSize: 78)])
        let sz = str.size()
        str.draw(at: NSPoint(x: (side - sz.width) / 2, y: side - sz.height))
        img.unlockFocus()
        var rect = CGRect(x: 0, y: 0, width: side, height: side)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return [] }
        var out: [(row: Int, col: Int, image: CGImage)] = []
        for r in 0..<g {
            for c in 0..<g {
                // Integer pixel bounds, so no row/column is dropped or doubled.
                let x0 = cg.width * c / g, x1 = cg.width * (c + 1) / g
                let y0 = cg.height * r / g, y1 = cg.height * (r + 1) / g
                if let cut = cg.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)) {
                    out.append((row: r, col: c, image: cut))
                }
            }
        }
        _dissolveTiles[g] = out
        return out
    }

    /// Blow the cup's pixels apart from `center`, over a box `side` wide. Every tile
    /// drifts outward along its own direction from the centre (plus jitter and a
    /// little gravity on the way down), turning and shrinking as it fades, while
    /// the whole cloud is scaled up — so the cup visibly ENLARGES as it fragments
    /// instead of just vanishing.
    ///
    /// Tuned DOWN from the first version, which read as a detonation: the fragments
    /// travel about a third as far, turn a quarter as much, take longer doing it and
    /// start fading at a quarter of the way in. The cup should come apart and
    /// dissolve, not be shot.
    ///
    /// `violence` is 1 for the quiet dissolve above; a storm pop passes 2–3.5,
    /// which scales how far and how fast the fragments fly, how much they
    /// spin, how big the bloom gets and how bright the flash is.
    /// `grid` is tiles per side: 12 for the calm pop, more for a storm's
    /// "many pieces".
    private func pixelDissolve(at center: CGPoint, side: CGFloat, violence: CGFloat = 1,
                               grid g: Int = dissolveGrid) {
        let tiles = Self.dissolveTiles(grid: g)
        let v = max(1, violence)
        let extra = v - 1                                   // 0 in calm, up to 2.6 in a storm
        guard !tiles.isEmpty else { return }
        let cell = side / CGFloat(g)
        let contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        let container = CALayer()
        container.frame = CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
        hostLayer.addSublayer(container)

        for t in tiles {
            // Row 0 is the TOP of the bitmap; the overlay layer's y grows upward.
            let f = CGRect(x: CGFloat(t.col) * cell,
                           y: CGFloat(g - 1 - t.row) * cell,
                           width: cell, height: cell)
            let piece = CALayer()
            piece.frame = f
            piece.contents = t.image
            piece.contentsScale = contentsScale
            piece.magnificationFilter = .nearest      // stay square: pixels, not smudges
            container.addSublayer(piece)

            let from = CGPoint(x: f.midX, y: f.midY)
            let dx = from.x - side / 2, dy = from.y - side / 2
            let len = max(1, sqrt(dx * dx + dy * dy))
            let dist = side * CGFloat.random(in: 0.18...0.55) * v
            let jx = CGFloat.random(in: -0.15...0.15), jy = CGFloat.random(in: -0.15...0.15)
            let ux = dx / len + jx, uy = dy / len + jy
            let end = CGPoint(x: from.x + ux * dist, y: from.y + uy * dist - side * 0.16 * v)
            let apex = CGPoint(x: from.x + ux * dist * 0.55, y: from.y + uy * dist * 0.55 + side * 0.06 * v)
            let path = CGMutablePath()
            path.move(to: from)
            path.addQuadCurve(to: end, control: apex)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)

            // Spin + shrink baked into ONE keyframed transform: two separate
            // animations on transform.rotation and transform.scale fight over the
            // same property, so the fragments would jitter instead of tumbling.
            let rot = CGFloat.random(in: -0.7...0.7) * (1 + extra * 1.5)
            let endScale = CGFloat.random(in: 0.55...1.0)
            let steps = 6
            var frames: [NSValue] = []
            for i in 0...steps {
                let k = CGFloat(i) / CGFloat(steps)
                let s = 1 + (endScale - 1) * k
                var m = CATransform3DMakeRotation(rot * k, 0, 0, 1)
                m = CATransform3DScale(m, s, s, 1)
                frames.append(NSValue(caTransform3D: m))
            }
            let tumble = CAKeyframeAnimation(keyPath: "transform")
            tumble.values = frames
            tumble.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let dur = Double.random(in: 0.8...1.25) * Double(1 + extra * 0.25)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.beginTime = dur * 0.25
            fade.duration = dur * 0.75
            fade.fillMode = .forwards

            let grp = CAAnimationGroup()
            grp.animations = [move, tumble, fade]
            grp.duration = dur
            grp.fillMode = .forwards
            grp.isRemovedOnCompletion = false
            piece.add(grp, forKey: "shatter")
        }

        // The cloud itself keeps expanding — the "grows while it comes apart" part.
        let bloom = CABasicAnimation(keyPath: "transform.scale")
        bloom.fromValue = 1.0
        bloom.toValue = 1.25 + 0.35 * extra
        bloom.duration = 1.2
        bloom.timingFunction = CAMediaTimingFunction(name: .easeOut)
        bloom.fillMode = .forwards
        bloom.isRemovedOnCompletion = false
        container.add(bloom, forKey: "bloom")

        // A soft glow where the cup was — a hint that something gave way, not a muzzle
        // flash (which is what made the first version read as an explosion).
        let flash = CAGradientLayer()
        flash.type = .radial
        // A storm pop is allowed the muzzle flash the calm one was denied:
        // brighter, warmer, and up to three times the size.
        let flashCore = extra > 0 ? NSColor(calibratedRed: 1, green: 0.85, blue: 0.55, alpha: 1) : .white
        flash.colors = [flashCore.withAlphaComponent(min(0.95, 0.45 + 0.2 * extra)).cgColor,
                        flashCore.withAlphaComponent(0.0).cgColor]
        flash.locations = [0.0, 1.0]
        flash.startPoint = CGPoint(x: 0.5, y: 0.5)
        flash.endPoint = CGPoint(x: 1.0, y: 1.0)
        let fs = side * 0.9 * (1 + extra * 0.8)
        flash.frame = CGRect(x: center.x - fs / 2, y: center.y - fs / 2, width: fs, height: fs)
        hostLayer.addSublayer(flash)
        let fScale = CABasicAnimation(keyPath: "transform.scale")
        fScale.fromValue = 0.4
        fScale.toValue = 1.15 + 0.3 * extra
        let fFade = CABasicAnimation(keyPath: "opacity")
        fFade.fromValue = min(1, 0.5 + 0.2 * extra)
        fFade.toValue = 0
        let fGrp = CAAnimationGroup()
        fGrp.animations = [fScale, fFade]
        fGrp.duration = 0.4 + 0.1 * Double(extra)
        fGrp.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fGrp.fillMode = .forwards
        fGrp.isRemovedOnCompletion = false
        flash.add(fGrp, forKey: "flash")

        // Both layers are fire-and-forget: nothing else refers to them, so a plain
        // deadline past the longest animation is all the teardown they need.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { flash.removeFromSuperlayer() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.45 + 0.4 * Double(extra)) { container.removeFromSuperlayer() }
    }

    // The "−1" minute token that flies from an exploded coffee into the break
    // timer lives in victor-macos-addons now, with the timer it lands on: the
    // flight re-samples the clock's position every frame, which cannot survive
    // a cross-process call. This app tells addons that a coffee popped (and
    // where) through the event webhook; addons launches the token.

    /// Test hook (`/test/coffee/pop`): put a ☕ at the given point already fully
    /// charged and blow it up on the spot, returning where it popped — the whole
    /// chain (pixel dissolve → timer zoom-in / −1 token) without holding a cursor
    /// still for three seconds. Nil if there is no built-in screen to draw on.
    @discardableResult
    func popCoffeeForTest(atGlobal globalPoint: CGPoint? = nil) -> CGPoint? {
        guard let screen = Self.builtInScreenFrame() else { return nil }
        let side: CGFloat = 91
        let layer = CATextLayer()
        layer.string = "☕"
        layer.fontSize = 78
        layer.alignmentMode = .center
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        layer.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        let p = globalPoint.map { CGPoint(x: $0.x - screen.origin.x, y: $0.y - screen.origin.y) }
            ?? CGPoint(x: screen.width * 0.3, y: screen.height * 0.45)
        layer.position = p
        layer.transform = CATransform3DMakeScale(Self.coffeeChargeGrowScale, Self.coffeeChargeGrowScale, 1)
        hostLayer.addSublayer(layer)
        let at = explodeCoffee(layer)
        return CGPoint(x: at.x + screen.origin.x, y: at.y + screen.origin.y)
    }

    /// The overlay screen's frame in global coords. Goes through `Screens` like
    /// the panel and the flash do — the fourth copy of the built-in-display loop
    /// was the one that would have ignored `overlayScreen`.
    private static func builtInScreenFrame() -> CGRect? {
        Screens.overlayScreen()?.frame
    }

    func spawnRandomEmoji() {
        spawnEmoji(EmojiAnimator.emojiSet.randomElement()!)
    }

    /// Parse a "#rrggbb" (or "rrggbb") string into an NSColor; nil if malformed.
    static func nsColor(fromHex hex: String) -> NSColor? {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        return NSColor(
            srgbRed: CGFloat((v >> 16) & 0xff) / 255.0,
            green: CGFloat((v >> 8) & 0xff) / 255.0,
            blue: CGFloat(v & 0xff) / 255.0,
            alpha: 1.0
        )
    }

    // MARK: - Confetti burst

    private static let confettiColors: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .systemPink, .systemTeal,
    ]

    // MARK: - Screen vignette effects

    /// Radial gradient vignette that pulses then fades — used for danger/success moods.
    func showVignette(key: String? = nil, color: NSColor, duration: Double = 2.5, pulses: Int = 2, soundToStop: String? = nil) {
        let bounds = hostLayer.bounds

        let vignetteLayer = CALayer()
        vignetteLayer.frame = bounds
        vignetteLayer.opacity = 0

        // Build radial gradient: transparent center → colored edges.
        // The gradient — not the container — is what carries the frame, because
        // it is also what ScreenZoom shrinks: while macOS screen zoom is on,
        // "the edges of the screen" are the edges of the magnified SLICE, and a
        // vignette painted around the whole display would be entirely off the
        // glass. `ZoomFollower` keeps it there while the pointer pans.
        let gradientLayer = CAGradientLayer()
        gradientLayer.type = .radial
        gradientLayer.frame = bounds
        ZoomFollower.shared.track(gradientLayer, full: bounds)
        gradientLayer.colors = [
            NSColor.clear.cgColor,
            color.withAlphaComponent(0.0).cgColor,
            color.withAlphaComponent(0.35).cgColor,
            color.withAlphaComponent(0.7).cgColor,
        ]
        gradientLayer.locations = [0.0, 0.35, 0.7, 1.0]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)

        vignetteLayer.addSublayer(gradientLayer)
        hostLayer.addSublayer(vignetteLayer)

        // Pulse in, hold, fade out
        let pulseDuration = duration / Double(pulses * 2 + 1)
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = pulseDuration
        fadeIn.autoreverses = true
        fadeIn.repeatCount = Float(pulses)

        let totalPulse = pulseDuration * 2 * Double(pulses)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 0.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = totalPulse
        fadeOut.duration = duration - totalPulse
        fadeOut.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [fadeIn, fadeOut]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        if let key = key {
            activeEffects[key] = vignetteLayer
        }

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak vignetteLayer] in
            if let key = key, let self = self, self.activeEffects[key] === vignetteLayer {
                self.activeEffects.removeValue(forKey: key)
            }
            vignetteLayer?.removeFromSuperlayer()
            ZoomFollower.shared.untrack(gradientLayer)
            if let sound = soundToStop {
                SoundManager.shared.stop(sound)
            }
        }
        vignetteLayer.add(group, forKey: "vignette")
        CATransaction.commit()
    }

    func showDanger() {
        if cancelIfRunning("danger", sound: "alarm.mp3") { return }
        SoundManager.shared.play("alarm.mp3")
        showVignette(key: "danger", color: .systemRed, duration: 3.0, pulses: 3, soundToStop: "alarm.mp3")
    }

    // MARK: - Tablet-triggered alarm overlay (sound plays on tablet, not here)
    private var alarmOverlayTimer: Timer?
    private var drumRollTimer: DispatchSourceTimer?

    func startAlarmOverlay() {
        stopAlarmOverlay()
        showVignette(key: "danger", color: .systemRed, duration: 2.72, pulses: 4)
        // Fire 200ms before cycle ends so layers overlap and avoid flicker at the seam
        // 4 pulses × 0.68s = 2.72s matches siren.mp3 cycle tempo
        alarmOverlayTimer = Timer.scheduledTimer(withTimeInterval: 2.52, repeats: true) { [weak self] _ in
            self?.showVignette(key: "danger", color: .systemRed, duration: 2.72, pulses: 4)
        }
    }

    func stopAlarmOverlay() {
        alarmOverlayTimer?.invalidate()
        alarmOverlayTimer = nil
        _ = cancelIfRunning("danger")
    }

    // MARK: - Screen crash (screenshot shatters into broken glass shards)

    func showBrokenGlass(playSound: Bool = true) {  // formerly showEarthquake
        // 0.8: full volume is too violent for live workshops
        if playSound { SoundManager.shared.play("90_breaking-glass.mp3", volume: 0.8) }
        let bounds = hostLayer.bounds
        let totalDuration = 4.5

        // Capture the built-in (retina) display off the main thread (the
        // screencapture subprocess takes ~hundreds of ms), then build the shatter on
        // main. Same path as the heartbeat: it grabs the currently-visible space —
        // including a fullscreen app — on the screen the overlay sits on, never the
        // wrong (primary) display nor the desktop behind a fullscreen window.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screenshot = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self, let screenshot else { return }
                self.renderBrokenGlass(screenshot: screenshot, bounds: bounds, totalDuration: totalDuration)
            }
        }
    }

    private func renderBrokenGlass(screenshot: CGImage, bounds: CGRect, totalDuration: Double) {
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // Black background revealed as shards fall
        let blackBg = CALayer()
        blackBg.frame = bounds
        blackBg.backgroundColor = NSColor.black.cgColor
        container.addSublayer(blackBg)

        // Impact point — slightly off-center for realism
        let impact = CGPoint(
            x: bounds.width * CGFloat.random(in: 0.3...0.7),
            y: bounds.height * CGFloat.random(in: 0.3...0.7)
        )

        // Generate radial crack lines from impact to beyond screen edges
        let radialCount = Int.random(in: 14...20)
        let maxDist = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)
        var radialAngles: [CGFloat] = []
        for i in 0..<radialCount {
            let baseAngle = (CGFloat(i) / CGFloat(radialCount)) * 2 * .pi
            radialAngles.append(baseAngle + CGFloat.random(in: -0.15...0.15))
        }
        radialAngles.sort()

        // For each radial line, generate points at concentric ring distances with jitter
        let ringDistances: [CGFloat] = [60, 150, 300, 500, maxDist]
        var radialPoints: [[CGPoint]] = []  // [radialIndex][ringIndex] -> point on that ray at that ring

        for angle in radialAngles {
            var points: [CGPoint] = [impact]
            for dist in ringDistances {
                let jitteredAngle = angle + CGFloat.random(in: -0.12...0.12)
                let jitteredDist = dist + CGFloat.random(in: -dist * 0.15...dist * 0.15)
                points.append(CGPoint(
                    x: impact.x + cos(jitteredAngle) * jitteredDist,
                    y: impact.y + sin(jitteredAngle) * jitteredDist
                ))
            }
            radialPoints.append(points)
        }

        // Build shard polygons: each shard is bounded by two adjacent radial lines
        // and two adjacent concentric rings
        var shardPolygons: [(path: CGPath, center: CGPoint, distFromImpact: CGFloat)] = []

        for ri in 0..<radialCount {
            let nextRi = (ri + 1) % radialCount
            for di in 0..<ringDistances.count {
                // Four corners of this shard (between ring di and di+1, between radial ri and nextRi)
                let innerDi = di
                let outerDi = di + 1
                guard outerDi < radialPoints[ri].count else { continue }

                let p1 = radialPoints[ri][innerDi]
                let p2 = radialPoints[ri][outerDi]
                let p3 = radialPoints[nextRi][outerDi]
                let p4 = radialPoints[nextRi][innerDi]

                // Add extra jagged points along the edges for irregular glass look
                let path = CGMutablePath()
                path.move(to: p1)

                // Jagged edge from p1 to p2 (along radial ri)
                let mid12 = CGPoint(
                    x: (p1.x + p2.x) / 2 + CGFloat.random(in: -15...15),
                    y: (p1.y + p2.y) / 2 + CGFloat.random(in: -15...15)
                )
                path.addLine(to: mid12)
                path.addLine(to: p2)

                // Jagged edge from p2 to p3 (along outer ring)
                let mid23 = CGPoint(
                    x: (p2.x + p3.x) / 2 + CGFloat.random(in: -12...12),
                    y: (p2.y + p3.y) / 2 + CGFloat.random(in: -12...12)
                )
                path.addLine(to: mid23)
                path.addLine(to: p3)

                // Jagged edge from p3 to p4 (along radial nextRi)
                let mid34 = CGPoint(
                    x: (p3.x + p4.x) / 2 + CGFloat.random(in: -15...15),
                    y: (p3.y + p4.y) / 2 + CGFloat.random(in: -15...15)
                )
                path.addLine(to: mid34)
                path.addLine(to: p4)

                // Jagged edge from p4 back to p1 (along inner ring)
                let mid41 = CGPoint(
                    x: (p4.x + p1.x) / 2 + CGFloat.random(in: -12...12),
                    y: (p4.y + p1.y) / 2 + CGFloat.random(in: -12...12)
                )
                path.addLine(to: mid41)
                path.closeSubpath()

                let cx = (p1.x + p2.x + p3.x + p4.x) / 4
                let cy = (p1.y + p2.y + p3.y + p4.y) / 4
                let dist = sqrt((cx - impact.x) * (cx - impact.x) + (cy - impact.y) * (cy - impact.y))

                shardPolygons.append((path: path, center: CGPoint(x: cx, y: cy), distFromImpact: dist))
            }
        }

        // Create shard layers and animate
        for shard in shardPolygons {
            let shardLayer = CALayer()
            shardLayer.frame = bounds
            shardLayer.contents = screenshot
            shardLayer.contentsGravity = .resize

            let mask = CAShapeLayer()
            mask.path = shard.path
            shardLayer.mask = mask

            let group = CALayer()
            group.frame = bounds
            group.addSublayer(shardLayer)
            container.addSublayer(group)

            // Shards near impact fall first; outer shards follow
            let normalizedDist = min(shard.distFromImpact / maxDist, 1.0)
            let holdDelay = 0.2 + Double(normalizedDist) * 1.0 + Double.random(in: 0...0.3)
            let fallDuration = Double.random(in: 0.7...1.4)

            // Fall down — use screen diagonal to account for rotation expanding shard footprint
            let fall = CABasicAnimation(keyPath: "position.y")
            fall.byValue = -(maxDist + 300)
            fall.beginTime = CACurrentMediaTime() + holdDelay
            fall.duration = fallDuration
            fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
            fall.fillMode = .forwards
            fall.isRemovedOnCompletion = false

            // Rotate while falling
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.byValue = Double.random(in: -1.2...1.2)
            rotation.beginTime = CACurrentMediaTime() + holdDelay
            rotation.duration = fallDuration
            rotation.fillMode = .forwards
            rotation.isRemovedOnCompletion = false

            // Drift away from impact point horizontally
            let driftDir = shard.center.x > impact.x ? 1.0 : -1.0
            let drift = CABasicAnimation(keyPath: "position.x")
            drift.byValue = CGFloat(driftDir) * CGFloat.random(in: 20...80)
            drift.beginTime = CACurrentMediaTime() + holdDelay
            drift.duration = fallDuration
            drift.fillMode = .forwards
            drift.isRemovedOnCompletion = false

            group.add(fall, forKey: "fall")
            group.add(rotation, forKey: "rotate")
            group.add(drift, forKey: "drift")
        }

        // Black screen holds, then fades out
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + totalDuration - 0.8
        fadeOut.duration = 0.8
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        container.add(fadeOut, forKey: "fadeOut")

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.2) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    // MARK: - Film burn (4 black circles expanding from random positions)

    func showFilmBurn() {
        let bounds = hostLayer.bounds
        let totalDuration = 4.5

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // Max radius needed to cover the screen from any point
        let maxRadius = sqrt(bounds.width * bounds.width + bounds.height * bounds.height)

        // One circle per quadrant: TL, TR, BL, BR (random position within each quadrant)
        let halfW = bounds.width / 2
        let halfH = bounds.height / 2
        let quadrants: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, halfW, halfH, bounds.height),  // top-left
            (halfW, bounds.width, halfH, bounds.height),  // top-right
            (0, halfW, 0, halfH),              // bottom-left
            (halfW, bounds.width, 0, halfH),   // bottom-right
        ]

        for i in 0..<4 {
            let q = quadrants[i]
            let cx = CGFloat.random(in: q.0 + 20...q.1 - 20)
            let cy = CGFloat.random(in: q.2 + 20...q.3 - 20)
            let center = CGPoint(x: cx, y: cy)

            // Each circle appears within the first 1 second, staggered
            let startDelay = Double(i) * 0.25 + Double.random(in: 0...0.15)

            // Initial radius 20–100px
            let initialRadius = CGFloat.random(in: 20...100)

            // Different expansion speeds: each takes a different duration to reach max
            let expandDuration = Double.random(in: 2.5...4.0)

            let circle = CAShapeLayer()
            let initialPath = CGPath(ellipseIn: CGRect(x: center.x - initialRadius,
                                                        y: center.y - initialRadius,
                                                        width: initialRadius * 2,
                                                        height: initialRadius * 2), transform: nil)
            let finalPath = CGPath(ellipseIn: CGRect(x: center.x - maxRadius,
                                                      y: center.y - maxRadius,
                                                      width: maxRadius * 2,
                                                      height: maxRadius * 2), transform: nil)
            circle.path = initialPath
            circle.fillColor = NSColor.black.cgColor
            circle.opacity = 0
            container.addSublayer(circle)

            // Appear
            let appear = CABasicAnimation(keyPath: "opacity")
            appear.fromValue = 0
            appear.toValue = 1
            appear.beginTime = startDelay
            appear.duration = 0.15
            appear.fillMode = .both
            appear.isRemovedOnCompletion = false

            // Expand
            let expand = CABasicAnimation(keyPath: "path")
            expand.fromValue = initialPath
            expand.toValue = finalPath
            expand.beginTime = startDelay
            expand.duration = expandDuration
            expand.timingFunction = CAMediaTimingFunction(name: .easeIn)
            expand.fillMode = .both
            expand.isRemovedOnCompletion = false

            let group = CAAnimationGroup()
            group.animations = [appear, expand]
            group.duration = totalDuration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false
            circle.add(group, forKey: "burn")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 0.2) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    private func spawnFireSparks(at point: CGPoint, in container: CALayer, count: Int = 15) {
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        for _ in 0..<count {
            let spark = CALayer()
            let size: CGFloat = CGFloat.random(in: 3...8)
            spark.frame = CGRect(x: point.x - size/2, y: point.y - size/2, width: size, height: size)
            spark.cornerRadius = size / 2
            let g = CGFloat.random(in: 0.2...0.6)
            spark.backgroundColor = NSColor(red: 1.0, green: g, blue: 0.0, alpha: 1.0).cgColor
            spark.contentsScale = scale
            container.addSublayer(spark)

            // Rise upward like embers
            let angle = CGFloat.random(in: CGFloat.pi * 0.15 ... CGFloat.pi * 0.85) // mostly upward
            let dist = CGFloat.random(in: 50...200)
            let endPoint = CGPoint(x: point.x + cos(angle) * dist * 0.4,
                                   y: point.y + sin(angle) * dist)

            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: point)
            move.toValue = NSValue(point: endPoint)
            move.timingFunction = CAMediaTimingFunction(name: .easeOut)

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0

            let duration = Double.random(in: 0.5...1.2)
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.duration = duration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak spark] in spark?.removeFromSuperlayer() }
            spark.add(group, forKey: "spark")
            CATransaction.commit()
        }
    }

    // MARK: - Zorro Z (animated fire GIF overlay)

    func showZorro() {
        if cancelIfRunning("zorro") { return }
        let bounds = hostLayer.bounds

        guard let url = Bundle.module.url(forResource: "zorro_fire", withExtension: "gif", subdirectory: "Resources"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return }

        // Extract all frames and durations
        var frames: [CGImage] = []
        var totalGifDuration: Double = 0
        for i in 0..<frameCount {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            frames.append(cgImage)
            if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
               let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any],
               let delay = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ??
                           gifProps[kCGImagePropertyGIFDelayTime as String] as? Double {
                totalGifDuration += delay
            } else {
                totalGifDuration += 0.05
            }
        }

        let totalDuration = totalGifDuration + 1.0

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // 85% screen width, centered, maintain aspect ratio
        let imgW = bounds.width * 0.70
        let aspectRatio = CGFloat(frames[0].height) / CGFloat(frames[0].width)
        let imgH = imgW * aspectRatio
        let imgX = (bounds.width - imgW) / 2
        let imgY = (bounds.height - imgH) / 2

        let imgLayer = CALayer()
        imgLayer.frame = CGRect(x: imgX, y: imgY, width: imgW, height: imgH)
        imgLayer.contentsGravity = .resizeAspect
        imgLayer.contents = frames[0]
        container.addSublayer(imgLayer)

        // Animate through GIF frames
        let frameAnim = CAKeyframeAnimation(keyPath: "contents")
        frameAnim.values = frames
        frameAnim.duration = totalGifDuration
        frameAnim.calculationMode = .discrete
        frameAnim.repeatCount = 1
        frameAnim.fillMode = .forwards
        frameAnim.isRemovedOnCompletion = false
        imgLayer.add(frameAnim, forKey: "gifFrames")

        // Orange glow shadow
        imgLayer.shadowColor = NSColor(red: 1.0, green: 0.4, blue: 0.0, alpha: 1.0).cgColor
        imgLayer.shadowOffset = .zero
        imgLayer.shadowRadius = 30
        imgLayer.shadowOpacity = 0.8

        let glowFlicker = CAKeyframeAnimation(keyPath: "shadowRadius")
        glowFlicker.values = [30, 40, 25, 45, 30, 35, 28]
        glowFlicker.duration = 0.25
        glowFlicker.repeatCount = .infinity
        imgLayer.add(glowFlicker, forKey: "glowFlicker")

        // Fade out
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + totalDuration - 0.8
        fadeOut.duration = 0.8
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        container.add(fadeOut, forKey: "fadeAll")

        trackEffect("zorro", layer: container, duration: totalDuration + 0.2)
    }

    // MARK: - Fireworks

    private static let fireworkPalettes: [[NSColor]] = [
        [NSColor(red: 1, green: 0.2, blue: 0.2, alpha: 1),
         NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1),
         NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)],
        [NSColor(red: 0.2, green: 0.6, blue: 1, alpha: 1),
         NSColor(red: 0.4, green: 0.9, blue: 1, alpha: 1),
         .white],
        [NSColor(red: 1, green: 0.2, blue: 0.6, alpha: 1),
         NSColor(red: 0.8, green: 0.3, blue: 1, alpha: 1),
         NSColor(red: 1, green: 0.6, blue: 0.9, alpha: 1)],
        [NSColor(red: 1, green: 0.85, blue: 0.1, alpha: 1),
         .white,
         NSColor(red: 1, green: 0.95, blue: 0.6, alpha: 1)],
        [NSColor(red: 0.1, green: 1, blue: 0.4, alpha: 1),
         NSColor(red: 0.3, green: 1, blue: 0.8, alpha: 1),
         .white],
    ]

    func showFireworks(playSound: Bool = true) {
        guard activeEffects["fireworks"] == nil else { return }
        let container = CALayer()
        container.frame = hostLayer.bounds
        hostLayer.addSublayer(container)
        trackEffect("fireworks", layer: container, duration: 8.0, sound: playSound ? "89_fireworks.mp3" : nil)

        let bounds = hostLayer.bounds
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        // Wave 1: 3 big ones
        for r in 0..<3 {
            let delay = Double(r) * 0.4
            let x = bounds.width * (0.2 + CGFloat(r) * 0.3) + CGFloat.random(in: -60...60)
            let y = CGFloat.random(in: bounds.height * 0.50...bounds.height * 0.80)
            let palette = EmojiAnimator.fireworkPalettes.randomElement()!
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak container] in
                guard let container = container, container.superlayer != nil else { return }
                self?.launchRocket(from: CGPoint(x: x, y: -10), to: CGPoint(x: x + CGFloat.random(in: -30...30), y: y),
                                   palette: palette, scale: scale, big: true, container: container)
            }
        }
        // Wave 2: 3-4 more, staggered
        for r in 0..<Int.random(in: 3...4) {
            let delay = 1.0 + Double(r) * 0.35
            let x = CGFloat.random(in: bounds.width * 0.1...bounds.width * 0.9)
            let y = CGFloat.random(in: bounds.height * 0.40...bounds.height * 0.75)
            let palette = EmojiAnimator.fireworkPalettes.randomElement()!
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak container] in
                guard let container = container, container.superlayer != nil else { return }
                self?.launchRocket(from: CGPoint(x: x, y: -10), to: CGPoint(x: x + CGFloat.random(in: -20...20), y: y),
                                   palette: palette, scale: scale, big: Bool.random(), container: container)
            }
        }
        // Wave 3: grand finale — rapid burst of 4
        for r in 0..<4 {
            let delay = 2.5 + Double(r) * 0.15
            let x = CGFloat.random(in: bounds.width * 0.15...bounds.width * 0.85)
            let y = CGFloat.random(in: bounds.height * 0.45...bounds.height * 0.80)
            let palette = EmojiAnimator.fireworkPalettes.randomElement()!
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak container] in
                guard let container = container, container.superlayer != nil else { return }
                self?.launchRocket(from: CGPoint(x: x, y: -10), to: CGPoint(x: x, y: y),
                                   palette: palette, scale: scale, big: true, container: container)
            }
        }
    }

    private func launchRocket(from start: CGPoint, to burst: CGPoint,
                              palette: [NSColor], scale: CGFloat, big: Bool, container: CALayer) {
        let riseDuration = Double.random(in: 0.4...0.7)

        // Rocket — bright streak rising up
        let rocket = CAShapeLayer()
        let trailPath = CGMutablePath()
        trailPath.move(to: start)
        trailPath.addLine(to: CGPoint(x: start.x, y: start.y + 40))
        rocket.path = trailPath
        rocket.strokeColor = NSColor.white.cgColor
        rocket.lineWidth = 3
        rocket.lineCap = .round
        rocket.fillColor = nil
        rocket.shadowColor = palette[0].cgColor
        rocket.shadowOffset = .zero
        rocket.shadowRadius = 12
        rocket.shadowOpacity = 1.0
        container.addSublayer(rocket)

        // Rise animation
        let risePath = CGMutablePath()
        risePath.move(to: start)
        // Slight wobble on the way up
        let midX = (start.x + burst.x) / 2 + CGFloat.random(in: -15...15)
        let midY = (start.y + burst.y) / 2
        risePath.addQuadCurve(to: burst, control: CGPoint(x: midX, y: midY))

        let riseAnim = CAKeyframeAnimation(keyPath: "position")
        riseAnim.path = risePath
        riseAnim.duration = riseDuration
        riseAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        riseAnim.fillMode = .forwards
        riseAnim.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak rocket, weak container] in
            rocket?.removeFromSuperlayer()
            guard let container = container, container.superlayer != nil else { return }
            self?.explodeFirework(at: burst, palette: palette, scale: scale, big: big, container: container)
        }
        rocket.add(riseAnim, forKey: "rise")
        CATransaction.commit()
    }

    private func explodeFirework(at center: CGPoint, palette: [NSColor], scale: CGFloat, big: Bool, container: CALayer) {
        let streakCount = big ? Int.random(in: 40...55) : Int.random(in: 24...32)
        let burstRadius = big ? CGFloat.random(in: 250...400) : CGFloat.random(in: 140...220)
        let duration = big ? Double.random(in: 1.8...2.5) : Double.random(in: 1.2...1.8)

        // Massive flash
        let flash = CALayer()
        let flashSize: CGFloat = big ? 120 : 60
        flash.frame = CGRect(x: center.x - flashSize/2, y: center.y - flashSize/2,
                              width: flashSize, height: flashSize)
        flash.cornerRadius = flashSize / 2
        flash.backgroundColor = NSColor.white.cgColor
        flash.shadowColor = palette[0].cgColor
        flash.shadowOffset = .zero
        flash.shadowRadius = big ? 80 : 40
        flash.shadowOpacity = 1.0
        flash.contentsScale = scale
        container.addSublayer(flash)

        let flashScale = CABasicAnimation(keyPath: "transform.scale")
        flashScale.fromValue = 0.5
        flashScale.toValue = big ? 3.0 : 2.0

        let flashFade = CABasicAnimation(keyPath: "opacity")
        flashFade.fromValue = 1.0
        flashFade.toValue = 0.0

        let flashGroup = CAAnimationGroup()
        flashGroup.animations = [flashScale, flashFade]
        flashGroup.duration = 0.3
        flashGroup.fillMode = .forwards
        flashGroup.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak flash] in flash?.removeFromSuperlayer() }
        flash.add(flashGroup, forKey: "flash")
        CATransaction.commit()

        // Streaking lines — the real firework effect
        for i in 0..<streakCount {
            let baseAngle = (CGFloat(i) / CGFloat(streakCount)) * 2 * .pi
            let angle = baseAngle + CGFloat.random(in: -0.12...0.12)
            let dist = burstRadius * CGFloat.random(in: 0.6...1.0)
            let color = palette.randomElement()!

            // Each streak is a line (CAShapeLayer) that extends outward
            let endPoint = CGPoint(
                x: center.x + cos(angle) * dist,
                y: center.y + sin(angle) * dist
            )
            // Gravity droop at the end
            let droopEnd = CGPoint(x: endPoint.x, y: endPoint.y - dist * 0.25)

            let streakPath = CGMutablePath()
            streakPath.move(to: center)
            streakPath.addQuadCurve(to: droopEnd,
                                     control: endPoint)

            let streak = CAShapeLayer()
            streak.path = streakPath
            streak.strokeColor = color.cgColor
            streak.lineWidth = big ? CGFloat.random(in: 2.5...4.5) : CGFloat.random(in: 1.5...3.0)
            streak.lineCap = .round
            streak.fillColor = nil
            streak.shadowColor = color.cgColor
            streak.shadowOffset = .zero
            streak.shadowRadius = big ? 8 : 4
            streak.shadowOpacity = 1.0
            streak.strokeEnd = 0
            container.addSublayer(streak)

            // Draw the streak outward rapidly
            let drawDuration = duration * 0.35
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = drawDuration
            draw.timingFunction = CAMediaTimingFunction(name: .easeOut)
            draw.fillMode = .forwards
            draw.isRemovedOnCompletion = false

            // Then the tail follows (strokeStart catches up)
            let tail = CABasicAnimation(keyPath: "strokeStart")
            tail.fromValue = 0
            tail.toValue = 1
            tail.beginTime = drawDuration * 0.4
            tail.duration = duration - drawDuration * 0.4
            tail.timingFunction = CAMediaTimingFunction(name: .easeIn)
            tail.fillMode = .forwards
            tail.isRemovedOnCompletion = false

            // Fade at the end
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.beginTime = duration * 0.5
            fade.duration = duration * 0.5
            fade.fillMode = .forwards
            fade.isRemovedOnCompletion = false

            let group = CAAnimationGroup()
            group.animations = [draw, tail, fade]
            group.duration = duration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak streak] in streak?.removeFromSuperlayer() }
            streak.add(group, forKey: "burst")
            CATransaction.commit()

            // Glowing dot at the tip of each streak
            if i % 2 == 0 {
                let dot = CALayer()
                let dotSize: CGFloat = big ? 6 : 4
                dot.frame = CGRect(x: center.x - dotSize/2, y: center.y - dotSize/2,
                                    width: dotSize, height: dotSize)
                dot.cornerRadius = dotSize / 2
                dot.backgroundColor = NSColor.white.cgColor
                dot.shadowColor = color.cgColor
                dot.shadowOffset = .zero
                dot.shadowRadius = 6
                dot.shadowOpacity = 1.0
                dot.contentsScale = scale
                container.addSublayer(dot)

                let dotPath = CGMutablePath()
                dotPath.move(to: center)
                dotPath.addQuadCurve(to: droopEnd, control: endPoint)

                let dotMove = CAKeyframeAnimation(keyPath: "position")
                dotMove.path = dotPath
                dotMove.timingFunction = CAMediaTimingFunction(name: .easeOut)

                let dotFade = CABasicAnimation(keyPath: "opacity")
                dotFade.fromValue = 1.0
                dotFade.toValue = 0.0
                dotFade.beginTime = duration * 0.4
                dotFade.duration = duration * 0.6
                dotFade.fillMode = .forwards

                let dotShrink = CABasicAnimation(keyPath: "transform.scale")
                dotShrink.fromValue = 1.5
                dotShrink.toValue = 0.2
                dotShrink.timingFunction = CAMediaTimingFunction(name: .easeIn)

                let dotGroup = CAAnimationGroup()
                dotGroup.animations = [dotMove, dotFade, dotShrink]
                dotGroup.duration = duration
                dotGroup.fillMode = .forwards
                dotGroup.isRemovedOnCompletion = false

                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak dot] in dot?.removeFromSuperlayer() }
                dot.add(dotGroup, forKey: "tip")
                CATransaction.commit()
            }
        }

        // Secondary crackle sparks — tiny pops after main burst
        if big {
            for j in 0..<8 {
                let sparkDelay = Double.random(in: 0.3...1.0)
                let sparkCenter = CGPoint(
                    x: center.x + CGFloat.random(in: -burstRadius * 0.5...burstRadius * 0.5),
                    y: center.y + CGFloat.random(in: -burstRadius * 0.3...burstRadius * 0.5)
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + sparkDelay) { [weak container] in
                    guard let container = container, container.superlayer != nil else { return }
                    let color = palette.randomElement()!
                    for _ in 0..<6 {
                        let spark = CALayer()
                        let sz: CGFloat = CGFloat.random(in: 2...4)
                        spark.frame = CGRect(x: sparkCenter.x, y: sparkCenter.y, width: sz, height: sz)
                        spark.cornerRadius = sz / 2
                        spark.backgroundColor = color.cgColor
                        spark.contentsScale = scale
                        container.addSublayer(spark)

                        let ang = CGFloat.random(in: 0...(2 * .pi))
                        let d = CGFloat.random(in: 20...50)
                        let end = CGPoint(x: sparkCenter.x + cos(ang) * d,
                                          y: sparkCenter.y + sin(ang) * d - 15)
                        let move = CABasicAnimation(keyPath: "position")
                        move.toValue = NSValue(point: end)
                        let fade = CABasicAnimation(keyPath: "opacity")
                        fade.fromValue = 1.0
                        fade.toValue = 0.0
                        let g = CAAnimationGroup()
                        g.animations = [move, fade]
                        g.duration = Double.random(in: 0.3...0.6)
                        g.fillMode = .forwards
                        g.isRemovedOnCompletion = false
                        CATransaction.begin()
                        CATransaction.setCompletionBlock { [weak spark] in spark?.removeFromSuperlayer() }
                        spark.add(g, forKey: "crackle")
                        CATransaction.commit()
                    }
                    _ = j // suppress warning
                }
            }
        }
    }

    // MARK: - Sepia / old film overlay

    func showSepia(playSound: Bool = true) {
        let soundKey: String? = playSound ? "78_projector.mp3" : nil
        if cancelIfRunning("sepia", sound: soundKey) { return }
        let bounds = hostLayer.bounds
        let totalDuration = 7.0

        if playSound {
            SoundManager.shared.play("78_projector.mp3")
        }

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // Warm sepia wash — visible yellowed center
        let sepiaLayer = CALayer()
        sepiaLayer.frame = bounds
        sepiaLayer.backgroundColor = NSColor(red: 0.50, green: 0.38, blue: 0.15, alpha: 0.45).cgColor
        sepiaLayer.opacity = 0
        container.addSublayer(sepiaLayer)

        // Vignette darkening at edges (keeps center visible/yellowed)
        let vignette = CAGradientLayer()
        vignette.type = .radial
        vignette.frame = bounds
        vignette.colors = [
            NSColor.clear.cgColor,
            NSColor.clear.cgColor,
            NSColor(white: 0, alpha: 0.45).cgColor,
            NSColor(white: 0, alpha: 0.75).cgColor,
        ]
        vignette.locations = [0.0, 0.35, 0.70, 1.0]
        vignette.startPoint = CGPoint(x: 0.5, y: 0.5)
        vignette.endPoint = CGPoint(x: 1.0, y: 1.0)
        vignette.opacity = 0
        container.addSublayer(vignette)

        // Film grain — flickering specks
        let grainLayer = CALayer()
        grainLayer.frame = bounds
        grainLayer.opacity = 0
        container.addSublayer(grainLayer)

        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        for _ in 0..<60 {
            let speck = CALayer()
            let sz = CGFloat.random(in: 1.5...4)
            speck.frame = CGRect(
                x: CGFloat.random(in: 0...bounds.width),
                y: CGFloat.random(in: 0...bounds.height),
                width: sz, height: sz
            )
            speck.cornerRadius = sz / 2
            let bright = Bool.random() ? CGFloat.random(in: 0.8...1.0) : CGFloat.random(in: 0...0.15)
            speck.backgroundColor = NSColor(white: bright, alpha: CGFloat.random(in: 0.3...0.7)).cgColor
            speck.contentsScale = scale
            grainLayer.addSublayer(speck)

            let flicker = CAKeyframeAnimation(keyPath: "opacity")
            flicker.values = [1.0, 0.0, 1.0, 0.0, 0.7, 0.0, 1.0]
            flicker.duration = Double.random(in: 0.15...0.4)
            flicker.repeatCount = .infinity
            speck.add(flicker, forKey: "flicker")
        }

        // Vertical scratches — thick and visible
        for _ in 0..<8 {
            let scratch = CAShapeLayer()
            let sp = CGMutablePath()
            let x = CGFloat.random(in: bounds.width * 0.05...bounds.width * 0.95)
            sp.move(to: CGPoint(x: x + CGFloat.random(in: -3...3), y: 0))
            sp.addLine(to: CGPoint(x: x + CGFloat.random(in: -8...8), y: bounds.height))
            scratch.path = sp
            scratch.strokeColor = NSColor(white: 0.95, alpha: 0.6).cgColor
            scratch.lineWidth = CGFloat.random(in: 1.5...4.0)
            scratch.fillColor = nil
            scratch.opacity = 0
            container.addSublayer(scratch)

            let sf = CAKeyframeAnimation(keyPath: "opacity")
            sf.values = [0, 0, 0.8, 0, 0, 0.6, 0, 0]
            sf.duration = Double.random(in: 0.2...0.5)
            sf.repeatCount = .infinity
            scratch.add(sf, forKey: "scratch")
        }

        // Fade in over 1s, hold throughout, fade out in last 1s
        let fadeInEnd = 1.0 / totalDuration
        let fadeOutStart = 1.0 - (1.0 / totalDuration)

        for layer in [sepiaLayer, vignette, grainLayer] {
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = [0.0, 1.0, 1.0, 0.0]
            anim.keyTimes = [0.0, NSNumber(value: fadeInEnd),
                             NSNumber(value: fadeOutStart), 1.0]
            anim.duration = totalDuration
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            layer.add(anim, forKey: "sepia")
        }

        // Projector jitter — gentle throughout
        let jitter = CAKeyframeAnimation(keyPath: "position")
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        var jitterValues: [NSValue] = []
        for _ in 0..<100 {
            jitterValues.append(NSValue(point: CGPoint(
                x: c.x + CGFloat.random(in: -1.5...1.5),
                y: c.y + CGFloat.random(in: -1.5...1.5)
            )))
        }
        jitter.values = jitterValues
        jitter.duration = totalDuration
        container.add(jitter, forKey: "jitter")

        trackEffect("sepia", layer: container, duration: totalDuration + 0.2, sound: soundKey)
    }

    // MARK: - Confetti burst

    func spawnConfetti(count: Int = 80) {
        SoundManager.shared.playOverlapping("confetti.mp3")
        let bounds = hostLayer.bounds
        let screenW = bounds.width
        let screenH = bounds.height
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        for i in 0..<count {
            let delay = Double(i) * 0.012 // stagger over ~1s

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                let color = EmojiAnimator.confettiColors.randomElement()!
                let layer = CALayer()

                // Larger confetti pieces
                let w = CGFloat.random(in: 14...26)
                let h = CGFloat.random(in: 8...26)
                let startX = CGFloat.random(in: 0...screenW)
                let startY = screenH + 20 // start above top edge

                layer.frame = CGRect(x: startX, y: startY, width: w, height: h)
                layer.backgroundColor = color.cgColor
                layer.cornerRadius = Bool.random() ? w / 2 : 1 // round or rectangular
                layer.contentsScale = scale
                self.hostLayer.addSublayer(layer)

                let duration = Double.random(in: 2.5...4.5)

                // Fall down with horizontal drift
                let endY: CGFloat = -30
                let drift = CGFloat.random(in: -200...200)

                let path = CGMutablePath()
                let start = layer.position
                let end = CGPoint(x: start.x + drift, y: endY)
                let cp1 = CGPoint(x: start.x + drift * 0.3 + CGFloat.random(in: -80...80),
                                  y: start.y - (start.y - endY) * 0.3)
                let cp2 = CGPoint(x: end.x + CGFloat.random(in: -60...60),
                                  y: start.y - (start.y - endY) * 0.7)
                path.move(to: start)
                path.addCurve(to: end, control1: cp1, control2: cp2)

                let pathAnim = CAKeyframeAnimation(keyPath: "position")
                pathAnim.path = path
                pathAnim.timingFunction = CAMediaTimingFunction(name: .easeIn)

                // Spin
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = Double.random(in: -6...6) * .pi

                // Fade near end
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1.0
                fade.toValue = 0.0
                fade.beginTime = duration * 0.6
                fade.duration = duration * 0.4
                fade.fillMode = .forwards

                let group = CAAnimationGroup()
                group.animations = [pathAnim, spin, fade]
                group.duration = duration
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false

                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak layer] in
                    layer?.removeFromSuperlayer()
                }
                layer.add(group, forKey: "confetti")
                CATransaction.commit()
            }
        }
    }

    /// Party-popper burst from the bottom-right corner. Fired when the tablet
    /// progress bar fills to the right edge: pieces shoot up-and-to-the-left
    /// out of the corner, then arc back down under gravity. Pairs with the
    /// short confetti pop to signal the end of the interval.
    func spawnCornerConfetti(count: Int = 70) {
        SoundManager.shared.playOverlapping("confetti.mp3", volume: 0.5)   // half volume
        let bounds = hostLayer.bounds
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        let origin = CGPoint(x: bounds.width, y: 0) // bottom-right corner
        let gravity: CGFloat = 1500

        for i in 0..<count {
            let delay = Double(i) * 0.004 // near-simultaneous pop (~0.28s)

            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                let color = EmojiAnimator.confettiColors.randomElement()!
                let layer = CALayer()

                let w = CGFloat.random(in: 12...24)
                let h = CGFloat.random(in: 8...22)
                layer.frame = CGRect(x: origin.x, y: origin.y, width: w, height: h)
                layer.backgroundColor = color.cgColor
                layer.cornerRadius = Bool.random() ? w / 2 : 1
                layer.contentsScale = scale
                self.hostLayer.addSublayer(layer)

                // Launch up-and-to-the-left: angle 118°…172° from the +x axis
                // (90° = straight up, 180° = straight left).
                let angle = CGFloat.random(in: (118 * .pi / 180)...(172 * .pi / 180))
                let speed = CGFloat.random(in: 650...1200)
                let vx = speed * cos(angle) // negative → leftward
                let vy = speed * sin(angle) // positive → upward
                let duration = Double.random(in: 2.2...3.4)

                // Sample the ballistic arc (x linear, y under gravity) into a path.
                let path = CGMutablePath()
                path.move(to: origin)
                let steps = 24
                for s in 1...steps {
                    let t = CGFloat(duration) * CGFloat(s) / CGFloat(steps)
                    let x = origin.x + vx * t
                    let y = origin.y + vy * t - 0.5 * gravity * t * t
                    path.addLine(to: CGPoint(x: x, y: y))
                }

                let pathAnim = CAKeyframeAnimation(keyPath: "position")
                pathAnim.path = path
                pathAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)

                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = Double.random(in: -8...8) * .pi

                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1.0
                fade.toValue = 0.0
                fade.beginTime = duration * 0.65
                fade.duration = duration * 0.35
                fade.fillMode = .forwards

                let group = CAAnimationGroup()
                group.animations = [pathAnim, spin, fade]
                group.duration = duration
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false

                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak layer] in
                    layer?.removeFromSuperlayer()
                }
                layer.add(group, forKey: "cornerConfetti")
                CATransaction.commit()
            }
        }
    }

    // MARK: - Money rain (sfx #53, one rising round per "ching")

    /// Money-flying emojis that swarm UP from the bottom edge to the top while
    /// fading out — one "round" per call. It is intentionally NOT a tracked /
    /// toggleable effect: every call spawns an independent, self-removing burst,
    /// so pressing the soundboard tile repeatedly stacks multiple overlapping
    /// rounds of rising dollars (one round per "ching"). Modeled on `spawnEmoji`
    /// (rise + sway + fade) but full-width and bottom→top across the screen.
    private static let moneyEmojis = ["💸", "💵", "💰", "🤑"]

    func showMoneyRise(count: Int = 16) {
        let bounds = hostLayer.bounds
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        for _ in 0..<count {
            // Stagger the burst over ~0.5s so the round reads as a swarm, not a row.
            let delay = Double.random(in: 0...0.5)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }

                let size = CGFloat.random(in: 64...104)
                let startX = CGFloat.random(in: size...(bounds.width - size))
                let startY = -size                              // just below the bottom edge

                let layer = CATextLayer()
                layer.string = EmojiAnimator.moneyEmojis.randomElement()!
                layer.fontSize = size * 0.86
                layer.alignmentMode = .center
                layer.frame = CGRect(x: startX - size / 2, y: startY, width: size, height: size)
                layer.contentsScale = scale
                self.hostLayer.addSublayer(layer)

                let duration = Double.random(in: 2.4...3.6)
                // Rise clear off the top edge, swaying left↔right like fluttering cash.
                let topY = bounds.height + size
                let sway = CGFloat.random(in: 60...140) * (Bool.random() ? 1 : -1)
                let path = CGMutablePath()
                let start = layer.position
                path.move(to: start)
                let steps = 24
                for s in 1...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let y = start.y + (topY - start.y) * t
                    let x = start.x + sway * sin(t * .pi * 2)   // one full wobble over the climb
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                let rise = CAKeyframeAnimation(keyPath: "position")
                rise.path = path
                rise.timingFunction = CAMediaTimingFunction(name: .easeOut)

                // Gentle tumble so the bills look like they're flying, not sliding up.
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = Double.random(in: -0.6...0.6) * .pi

                // Hold fully opaque for the first half, then fade out as it nears the top.
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1.0
                fade.toValue = 0.0
                fade.beginTime = duration * 0.5
                fade.duration = duration * 0.5
                fade.fillMode = .forwards

                let group = CAAnimationGroup()
                group.animations = [rise, spin, fade]
                group.duration = duration
                group.fillMode = .forwards
                group.isRemovedOnCompletion = false

                CATransaction.begin()
                CATransaction.setCompletionBlock { [weak layer] in
                    layer?.removeFromSuperlayer()
                }
                layer.add(group, forKey: "moneyRise")
                CATransaction.commit()
            }
        }
    }

    // MARK: - 🕳️ Iris close (toggle: press to close the screen into black, press again to fade it back)

    private static let irisCloseDuration: CFTimeInterval = 5.0   // corners → full black
    private static let irisHoldDuration: CFTimeInterval = 1.0    // dwell on full black before revealing
    private static let irisRevealDuration: CFTimeInterval = 1.0  // auto fade-out back to the screen

    /// Cinematic "iris out": a full-screen black overlay that is transparent in
    /// the centre and opaque at the edges, with a soft transition band. The clear
    /// hole starts as the circle circumscribing the screen (its rim passing
    /// through the corners, so nothing is hidden yet) and shrinks to nothing over
    /// ~5s — black creeps in from the corners and swallows the screen. SILENT; the
    /// shrinking-circle visual is the whole effect.
    ///
    /// Once fully black it dwells for ~1s, then automatically fades the black back
    /// out over ~1s to reveal whatever is underneath — no second press needed.
    ///
    /// Pressing the tile again at any point before that auto-reveal (during the
    /// close or the dwell) cancels it early with a quick fade. Because the tablet
    /// fires /effect/stop-all right before each tile press, this effect is
    /// deliberately kept out of `activeEffects` (so stopAllActiveEffects leaves it
    /// alone) — that lets the second press reach here and toggle instead of being
    /// wiped and restarted.
    func showIrisClose() {
        // Already running → second press cancels with a quick fade-out.
        if let existing = _irisLayer {
            cancelIris(existing)
            return
        }

        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // A square large enough to cover the screen, centred on it. Keeping the
        // gradient layer square makes the radial gradient a TRUE circle (on a
        // non-square layer it would distort into an ellipse). Side = the screen
        // diagonal, so the gradient's location 1.0 lands exactly on the screen
        // corners.
        let diag = (bounds.width * bounds.width + bounds.height * bounds.height).squareRoot()
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.frame = CGRect(x: bounds.midX - diag / 2, y: bounds.midY - diag / 2, width: diag, height: diag)
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)   // ellipse corner → radius = diag/2 → reaches the screen corners
        let clear = NSColor(white: 0, alpha: 0).cgColor
        let opaque = NSColor(white: 0, alpha: 1).cgColor
        layer.colors = [clear, clear, opaque, opaque]

        // `locations` for a normalised hole radius r∈[0,1]: [0 … r-band] is the
        // fully-clear visible hole, [r-band … r] the soft transition band, and
        // [r … 1] solid black. Animating r from 1→0 shrinks the hole to nothing.
        let band: CGFloat = 0.06
        func locs(_ r: CGFloat) -> [NSNumber] {
            let r1 = max(0, min(1, r))
            let r0 = max(0, r1 - band)
            return [0, NSNumber(value: Double(r0)), NSNumber(value: Double(r1)), 1]
        }

        // Settle the model fully black; suppress the implicit animation so the
        // explicit close below drives the whole transition from the open state.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.locations = locs(0.0)
        hostLayer.addSublayer(layer)
        CATransaction.commit()
        _irisLayer = layer

        let anim = CABasicAnimation(keyPath: "locations")
        anim.fromValue = locs(1.0)             // hole circumscribes the screen → nothing hidden
        anim.toValue = locs(0.0)               // hole gone → full black
        anim.duration = Self.irisCloseDuration
        anim.timingFunction = CAMediaTimingFunction(name: .easeIn)  // creeps from the corners, then collapses
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false     // hold full black through the dwell below
        layer.add(anim, forKey: "irisClose")

        // After it settles full black + a short dwell, auto-reveal: fade the black
        // out to show the screen again. Guarded so a manual cancel (or a later
        // re-trigger) makes this a no-op.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.irisCloseDuration + Self.irisHoldDuration) { [weak self, weak layer] in
            guard let self = self, let layer = layer, self._irisLayer === layer else { return }
            self.cancelIris(layer, fadeDuration: Self.irisRevealDuration)
        }
    }

    /// Fade the black iris back to transparent and remove it. `fadeDuration` is
    /// short for a manual interrupt (snappy) and ~1s for the gentle auto-reveal.
    private func cancelIris(_ layer: CAGradientLayer, fadeDuration: CFTimeInterval = 0.35) {
        _irisLayer = nil
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? 1.0
        fade.toValue = 0.0
        fade.duration = fadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        layer.opacity = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in
            layer?.removeFromSuperlayer()
        }
        layer.add(fade, forKey: "irisFade")
        CATransaction.commit()
    }

    // MARK: - Applause (👏 clapping-hands GIF, centered, half the screen height)

    /// The clapping sound (`27_clapping.mp3`) trimmed to **70%** — i.e. 30%
    /// shorter — used as the length of BOTH the applause GIF and the Mac-owned
    /// routed sound, so the visual and the audio run together and end together.
    /// Computed once from the bundled clip; falls back to its measured ~10.1s.
    static let applauseDuration: Double = {
        var natural = 10.1
        if let url = SoundManager.shared.soundURL(for: "27_clapping.mp3") {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { natural = CMTimeGetSeconds(d) }
        }
        return natural * 0.7
    }()

    /// Tile #27 👏 — a clapping-hands animation. Replaces the old 👏-emoji stream
    /// with the bundled `applause-hands.gif` (4 transparent full-canvas frames,
    /// ~0.4s loop) shown at HALF the screen height, centered, looping for the
    /// trimmed length of the clapping sound (`applauseDuration`). Tracked in
    /// `activeEffects`, so the tablet's pre-press /effect/stop-all tears it down —
    /// which is what makes the NON-restartable tile stop (not restart) on re-click.
    func showApplause(playSound: Bool = true) {
        if cancelIfRunning("applause", sound: playSound ? "27_clapping.mp3" : nil) { return }

        guard let url = Bundle.module.url(forResource: "applause-hands", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("applause-hands.gif not found")
            return
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var sourceDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif  = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
            sourceDuration += delay
        }
        guard let first = images.first, sourceDuration > 0 else { return }

        let duration = Self.applauseDuration

        // 35% of the screen height (0.7× the former 50%), aspect-preserved
        // width, centered on screen.
        let bounds = hostLayer.bounds
        let aspect = CGFloat(first.width) / CGFloat(first.height)
        let layerH = bounds.height * 0.35
        let layerW = layerH * aspect
        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: (bounds.width - layerW) / 2,
                                y: (bounds.height - layerH) / 2,
                                width: layerW, height: layerH)
        gifLayer.contentsGravity = .resizeAspect
        gifLayer.contents = first
        hostLayer.addSublayer(gifLayer)

        // Loop the clap for the whole duration.
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = sourceDuration
        anim.repeatCount = .infinity
        gifLayer.add(anim, forKey: "applauseFrames")

        // Gentle fade in/out so it doesn't pop on/off.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.25
        gifLayer.add(fadeIn, forKey: "applauseFadeIn")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + max(0, duration - 0.6)
        fadeOut.duration = 0.6
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        gifLayer.add(fadeOut, forKey: "applauseFadeOut")

        // Only the direct (playSound:true) path owns the clipped sound; the
        // tablet/menu paths pass false — the routed sound is clipped in AppDelegate.
        if playSound { SoundManager.shared.playClip("27_clapping.mp3", seconds: duration) }

        trackEffect("applause", layer: gifLayer, duration: duration, sound: playSound ? "27_clapping.mp3" : nil)
    }

    func stopApplause() {
        _ = cancelIfRunning("applause", sound: "27_clapping.mp3")
    }

    // MARK: - Minion (tile #80 `80_badumtss.mp3` — silent animated minion crowd)

    /// How long the minions linger on screen, and — mirrored by
    /// AppDelegate's onSoundPlay `durationMs` — how long the tablet keeps the tile
    /// in its "playing" state, i.e. the window during which a re-tap STOPS it.
    /// It is **one full pass of the asset** (132 frames × 40 ms), so the clip is
    /// never cut mid-motion: the GIF ends on the frame it started from (it plays
    /// forward, then rewinds through its last 30%), which is only a seamless
    /// landing if the effect lives exactly one loop.
    static let minionDuration: Double = 5.28

    /// Tile #80 (`80_badumtss.mp3`) — a cheering crowd of minions, pinned FLUSH
    /// BOTTOM-LEFT, ~45% of screen width, with NO sound. The asset is `minion.gif`
    /// (OPAQUE frames, 480×227): the source footage is a live-action-ish crowd
    /// shot with no separable subject, so there is no alpha to key out and the
    /// banner is meant to read as a framed clip sitting on the desktop.
    /// It is **not** mirrored — the old asset was a lone minion facing out of frame
    /// and had to be flipped to face the screen; a crowd has no such heading, and
    /// flipping it would only mirror the lettering and lighting for no gain.
    /// It loops for `minionDuration`, tracked in `activeEffects` so the tablet's
    /// pre-press /effect/stop-all tears it down — which is what makes the
    /// NON-restartable tile STOP (not restart) when pressed again. A direct
    /// re-trigger (/test/minion, /effect/minion) also toggles it off via
    /// cancelIfRunning.
    func showMinion() {
        if cancelIfRunning("minion") { return }

        guard let url = Bundle.module.url(forResource: "minion", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("minion.gif not found")
            return
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var sourceDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif  = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
            sourceDuration += delay
        }
        guard let first = images.first, sourceDuration > 0 else { return }

        let total = Self.minionDuration

        // ~45% of the screen WIDTH, aspect-preserved height, pinned FLUSH to the
        // BOTTOM-LEFT corner. hostLayer is AppKit y-up, so the bottom edge is
        // y = 0; the crowd is framed right up to the bottom of its own canvas, so
        // a flush mount reads as no empty space below.
        let bounds = hostLayer.bounds
        let aspect = CGFloat(first.width) / CGFloat(first.height)
        let layerW = bounds.width * 0.45
        let layerH = layerW / aspect
        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: 0, y: 0, width: layerW, height: layerH)
        gifLayer.contentsGravity = .resizeAspect
        gifLayer.contents = first
        gifLayer.opacity = 0
        hostLayer.addSublayer(gifLayer)

        // Loop the crowd for the whole duration. `repeatCount` stays infinite even
        // though the effect is one loop long: the fade-out overlaps the tail, and a
        // finite count would freeze the last frame under it if either drifts.
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = sourceDuration
        anim.repeatCount = .infinity
        gifLayer.add(anim, forKey: "minionFrames")

        // Fade in immediately — the press IS the cue, so anything before the crowd
        // is dead air on a 5s effect.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.35
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        gifLayer.add(fadeIn, forKey: "minionFadeIn")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + max(0, total - 0.6)
        fadeOut.duration = 0.6
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        gifLayer.add(fadeOut, forKey: "minionFadeOut")

        // No sound by design — the tile is silent; onSoundPlay neutralizes the
        // routed clip and returns just the duration so the tile stays "playing".
        trackEffect("minion", layer: gifLayer, duration: total, sound: nil)
    }

    // MARK: - Pulse / heartbeat (one-shot: 2 QRS cycles then flatline)

    func showPulse(playSound: Bool = false) {
        if pulseRunning { _stopPulse(); return }
        pulseRunning = true
        if playSound { SoundManager.shared.play("15_flatline.mp3") }

        let bounds = hostLayer.bounds
        // Timing: dying.mp3 R-spikes at 0.105s and 1.507s. Image peaks at 22% and 48% of width.
        // totalDuration: interval 26% of width must match audio interval 1.402s → 1.402/0.26=5.392s
        // soundDelay=1.081s: audio starts 1.081s after reveal →
        //   beat1 visual at 0.22*5.392=1.186s = audio beat1 at 1.081+0.105=1.186s ✓
        //   beat2 visual at 0.48*5.392=2.588s = audio beat2 at 1.081+1.507=2.588s ✓ (0ms error)
        let totalDuration: Double = 5.392
        let soundDelay:    Double = 1.081

        // Dark overlay
        let dimLayer = CALayer()
        _pulseDimLayer = dimLayer
        dimLayer.frame = bounds
        dimLayer.backgroundColor = NSColor(white: 0, alpha: 0.50).cgColor
        dimLayer.opacity = 0
        hostLayer.addSublayer(dimLayer)

        // Fade in overlay
        let dimIn = CABasicAnimation(keyPath: "opacity")
        dimIn.fromValue = 0
        dimIn.toValue = 1
        dimIn.duration = 0.5
        dimIn.fillMode = .forwards
        dimIn.isRemovedOnCompletion = false
        dimLayer.add(dimIn, forKey: "dimIn")

        // EKG graph-paper grid (green, between dark overlay and ECG line)
        let gridContainer = CALayer()
        _pulseGridLayer = gridContainer
        gridContainer.frame = bounds
        gridContainer.opacity = 0
        hostLayer.addSublayer(gridContainer)

        let minorSpacing: CGFloat = 20
        let majorEvery: Int = 5
        let minorPath = CGMutablePath()
        let majorPath = CGMutablePath()

        var xi = 0; var x: CGFloat = 0
        while x <= bounds.width {
            if xi % majorEvery == 0 { majorPath.move(to: CGPoint(x: x, y: 0)); majorPath.addLine(to: CGPoint(x: x, y: bounds.height)) }
            else                    { minorPath.move(to: CGPoint(x: x, y: 0)); minorPath.addLine(to: CGPoint(x: x, y: bounds.height)) }
            x += minorSpacing; xi += 1
        }
        var yi = 0; var y: CGFloat = 0
        while y <= bounds.height {
            if yi % majorEvery == 0 { majorPath.move(to: CGPoint(x: 0, y: y)); majorPath.addLine(to: CGPoint(x: bounds.width, y: y)) }
            else                    { minorPath.move(to: CGPoint(x: 0, y: y)); minorPath.addLine(to: CGPoint(x: bounds.width, y: y)) }
            y += minorSpacing; yi += 1
        }

        let minorGrid = CAShapeLayer()
        minorGrid.path = minorPath
        minorGrid.strokeColor = NSColor(red: 0.0, green: 0.8, blue: 0.35, alpha: 0.10).cgColor
        minorGrid.lineWidth = 0.5
        minorGrid.fillColor = nil
        gridContainer.addSublayer(minorGrid)

        let majorGrid = CAShapeLayer()
        majorGrid.path = majorPath
        majorGrid.strokeColor = NSColor(red: 0.0, green: 0.8, blue: 0.35, alpha: 0.24).cgColor
        majorGrid.lineWidth = 1.0
        majorGrid.fillColor = nil
        gridContainer.addSublayer(majorGrid)

        let gridIn = CABasicAnimation(keyPath: "opacity")
        gridIn.fromValue = 0; gridIn.toValue = 1
        gridIn.duration = 0.5
        gridIn.fillMode = .forwards; gridIn.isRemovedOnCompletion = false
        gridContainer.add(gridIn, forKey: "gridIn")

        // ECG canvas — full screen (amplitude needs full height)
        // Load the extracted ECG image (green line, transparent background)
        guard let url = Bundle.module.url(forResource: "ecg_line", withExtension: "png", subdirectory: "Resources"),
              let nsImage = NSImage(contentsOf: url),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            pulseRunning = false
            return
        }

        let ecgLayer = CALayer()
        _pulseEcgLayer = ecgLayer
        ecgLayer.contents = cgImage
        ecgLayer.contentsGravity = .resize   // stretch to fill frame completely
        ecgLayer.frame = bounds
        ecgLayer.opacity = 0
        hostLayer.addSublayer(ecgLayer)

        // Fade in image
        let ecgFadeIn = CABasicAnimation(keyPath: "opacity")
        ecgFadeIn.fromValue = 0
        ecgFadeIn.toValue = 1
        ecgFadeIn.duration = 0.5
        ecgFadeIn.fillMode = .forwards
        ecgFadeIn.isRemovedOnCompletion = false
        ecgLayer.add(ecgFadeIn, forKey: "ecgFadeIn")

        // Left-to-right reveal mask (white rect grows from left edge)
        let maskLayer = CALayer()
        maskLayer.backgroundColor = NSColor.white.cgColor
        maskLayer.anchorPoint = CGPoint(x: 0, y: 0.5)
        maskLayer.position = CGPoint(x: 0, y: bounds.height / 2)
        maskLayer.bounds = CGRect(x: 0, y: 0, width: 0, height: bounds.height)
        ecgLayer.mask = maskLayer

        let reveal = CABasicAnimation(keyPath: "bounds.size.width")
        reveal.fromValue = 0
        reveal.toValue = bounds.width
        reveal.duration = totalDuration
        reveal.timingFunction = CAMediaTimingFunction(name: .linear)
        reveal.fillMode = .forwards
        reveal.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak dimLayer, weak gridContainer, weak ecgLayer] in
            // Model opacity is still 0 (forward-filled anim keeps presentation at 1).
            // Use explicit CABasicAnimation fromValue:1 so Core Animation sees a real change.
            CATransaction.begin()
            CATransaction.setCompletionBlock {
                dimLayer?.removeFromSuperlayer()
                gridContainer?.removeFromSuperlayer()
                ecgLayer?.removeFromSuperlayer()
                self?.pulseRunning = false
                self?._pulseDimLayer = nil
                self?._pulseGridLayer = nil
                self?._pulseEcgLayer = nil
            }
            for layer in [dimLayer, gridContainer, ecgLayer].compactMap({ $0 }) {
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1; fadeOut.toValue = 0
                fadeOut.duration = 0.5
                fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
                layer.add(fadeOut, forKey: "fadeOut")
            }
            CATransaction.commit()
        }
        maskLayer.add(reveal, forKey: "reveal")
        CATransaction.commit()

    }

    // MARK: - Sketched Heart (crayon pencil style, right half first then left half)

    func showSketchedHeart() {
        let bounds = hostLayer.bounds
        let cx = bounds.midX
        let hcy = bounds.midY + bounds.height * 0.03
        let r: CGFloat = min(bounds.width, bounds.height) * 0.38

        let drawHalf: Double = 0.72      // seconds to draw each half
        let holdTime: Double = 1.8
        let fadeDuration: Double = 1.0

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // Heart geometry (CALayer coords: y increases upward)
        let topDip    = CGPoint(x: cx,       y: hcy + r * 0.18)
        let rightmost = CGPoint(x: cx + r,   y: hcy)
        let bottomTip = CGPoint(x: cx,       y: hcy - r * 1.10)
        let leftmost  = CGPoint(x: cx - r,   y: hcy)

        // Right half: top-dip → right-arc → bottom-tip
        let rightPath = CGMutablePath()
        rightPath.move(to: topDip)
        rightPath.addCurve(to: rightmost,
            control1: CGPoint(x: cx + r * 0.28, y: hcy + r * 0.62),
            control2: CGPoint(x: cx + r * 0.88, y: hcy + r * 0.48))
        rightPath.addCurve(to: bottomTip,
            control1: CGPoint(x: cx + r * 0.98, y: hcy - r * 0.42),
            control2: CGPoint(x: cx + r * 0.22, y: hcy - r * 1.10))

        // Left half: bottom-tip → left-arc → top-dip (mirror)
        let leftPath = CGMutablePath()
        leftPath.move(to: bottomTip)
        leftPath.addCurve(to: leftmost,
            control1: CGPoint(x: cx - r * 0.22, y: hcy - r * 1.10),
            control2: CGPoint(x: cx - r * 0.98, y: hcy - r * 0.42))
        leftPath.addCurve(to: topDip,
            control1: CGPoint(x: cx - r * 0.88, y: hcy + r * 0.48),
            control2: CGPoint(x: cx - r * 0.28, y: hcy + r * 0.62))

        // Crayon stroke layers — multiple slightly offset strokes create the pencil texture
        struct StrokeDef {
            let width: CGFloat; let opacity: Float; let dx: CGFloat; let dy: CGFloat
            let r: CGFloat; let g: CGFloat; let b: CGFloat
            let shadowRadius: CGFloat
        }
        let strokeDefs: [StrokeDef] = [
            // Soft outer glow
            StrokeDef(width: 32, opacity: 0.10, dx:  0,  dy:  0, r: 0.90, g: 0.08, b: 0.08, shadowRadius: 18),
            // Main rough strokes — slightly offset for crayon look
            StrokeDef(width: 20, opacity: 0.82, dx:  2,  dy: -1, r: 0.76, g: 0.05, b: 0.05, shadowRadius: 0),
            StrokeDef(width: 18, opacity: 0.65, dx: -2,  dy:  2, r: 0.68, g: 0.04, b: 0.04, shadowRadius: 0),
            StrokeDef(width: 14, opacity: 0.50, dx:  1,  dy:  3, r: 0.82, g: 0.06, b: 0.06, shadowRadius: 0),
            // Fine bright edge (gives the "fresh pencil" shine)
            StrokeDef(width:  8, opacity: 0.40, dx: -1,  dy: -2, r: 0.94, g: 0.20, b: 0.20, shadowRadius: 0),
        ]

        let now = CACurrentMediaTime()

        for (halfIdx, path) in [(rightPath as CGPath), (leftPath as CGPath)].enumerated() {
            let halfBegin = now + Double(halfIdx) * drawHalf
            for def in strokeDefs {
                let sl = CAShapeLayer()
                sl.path = path
                sl.strokeColor = NSColor(red: def.r, green: def.g, blue: def.b, alpha: 1.0).cgColor
                sl.fillColor = nil
                sl.lineWidth = def.width
                sl.lineCap = .round
                sl.lineJoin = .round
                sl.strokeEnd = 0
                sl.opacity = 0
                if def.dx != 0 || def.dy != 0 {
                    sl.setAffineTransform(CGAffineTransform(translationX: def.dx, y: def.dy))
                }
                if def.shadowRadius > 0 {
                    sl.shadowColor = NSColor(red: def.r, green: def.g, blue: def.b, alpha: 1.0).cgColor
                    sl.shadowOffset = .zero
                    sl.shadowRadius = def.shadowRadius
                    sl.shadowOpacity = 0.7
                }
                container.addSublayer(sl)

                // Draw stroke
                let draw = CABasicAnimation(keyPath: "strokeEnd")
                draw.fromValue = 0; draw.toValue = 1
                draw.beginTime = halfBegin
                draw.duration = drawHalf
                draw.timingFunction = CAMediaTimingFunction(name: .linear)
                draw.fillMode = .both
                draw.isRemovedOnCompletion = false
                sl.add(draw, forKey: "draw")

                // Fade in as drawing starts
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0; fadeIn.toValue = def.opacity
                fadeIn.beginTime = halfBegin
                fadeIn.duration = drawHalf * 0.25
                fadeIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
                fadeIn.fillMode = .both
                fadeIn.isRemovedOnCompletion = false
                sl.add(fadeIn, forKey: "reveal")
            }
        }

        // Fade out entire container after hold
        let fadeBegin = now + drawHalf * 2 + holdTime
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1; fadeOut.toValue = 0
        fadeOut.beginTime = fadeBegin
        fadeOut.duration = fadeDuration
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak container] in
            container?.removeFromSuperlayer()
        }
        container.add(fadeOut, forKey: "fadeOut")
        CATransaction.commit()
    }

    // MARK: - Fear

    func showFear(playSound: Bool = true) {
        if playSound { SoundManager.shared.play("08_scream_man.mp3") }

        let initialSize: CGFloat = 200
        let growPhaseDuration: Double = 3.0    // grow 200→600px at 100% opacity
        let fadePhaseDuration: Double = 1.75   // fade out + continue scaling
        let totalDuration = growPhaseDuration + fadePhaseDuration

        // Re-trigger while a fear is already on screen: drop the in-flight layer
        // + its follow timer, but KEEP the cursor hidden (we'll keep driving the
        // new face from the same mouse — no hide/show flicker between presses).
        _fearTimer?.invalidate(); _fearTimer = nil
        _fearLayer?.removeFromSuperlayer(); _fearLayer = nil

        let layer = CATextLayer()
        layer.string = "😱"
        layer.fontSize = initialSize * 0.83
        layer.alignmentMode = .center
        // anchorPoint .5,.5 so transform.scale grows around the centre AND so
        // updating `position` each frame keeps that centre pinned to the mouse.
        layer.bounds = CGRect(x: 0, y: 0, width: initialSize, height: initialSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = mousePointInHostLayer()   // start centred on the live cursor
        CATransaction.commit()
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        layer.opacity = 0.3   // start faded (matches opacityAnim) so no full-opacity flash
        hostLayer.addSublayer(layer)
        _fearLayer = layer

        // The face now stands in for the pointer — hide the real cursor so the
        // user "moves the scared face" with the mouse. Arm lifts the
        // "frontmost-app-only" restriction (our overlay floats over other apps);
        // NSCursor covers the case where we ARE frontmost. Balanced in stopFear.
        if !_fearHidCursor {
            Self.armBackgroundCursorHiding()
            NSCursor.hide()
            CGDisplayHideCursor(CGMainDisplayID())
            _fearHidCursor = true
        }

        let growEndFrac = growPhaseDuration / totalDuration
        let finalScale = 3.0 * hostLayer.bounds.height / initialSize

        // Scale: 1.0 → 3.0 over first 3s (200→600px), then continue to giant.
        let scaleAnim = CAKeyframeAnimation(keyPath: "transform.scale")
        scaleAnim.values = [1.0, 3.0, finalScale]
        scaleAnim.keyTimes = [0, NSNumber(value: growEndFrac), 1]
        scaleAnim.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .linear),
        ]

        // Opacity: start at 30% (so whatever is on screen stays readable through
        // the emoji) and hold for the first 3s, then fade to 0.
        let opacityAnim = CAKeyframeAnimation(keyPath: "opacity")
        opacityAnim.values = [0.3, 0.3, 0.0]
        opacityAnim.keyTimes = [0, NSNumber(value: growEndFrac), 1]
        opacityAnim.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeIn),
        ]

        let group = CAAnimationGroup()
        group.animations = [scaleAnim, opacityAnim]
        group.duration = totalDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        // Only tear down if THIS layer is still the active one (a re-trigger
        // installed a newer layer → let its own completion own the teardown).
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let self, self._fearLayer === layer else { return }
            self.stopFear()
        }
        layer.add(group, forKey: "fear")
        CATransaction.commit()

        // Follow the mouse at 60fps so the growing face stays centred on the
        // cursor; a deadline backstop restores the cursor even if the CA
        // completion block is ever missed.
        let endTime = CACurrentMediaTime() + totalDuration
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self, weak layer] t in
            guard let self, let layer, self._fearLayer === layer else { t.invalidate(); return }
            if CACurrentMediaTime() >= endTime { self.stopFear(); return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // move instantly, no implicit position animation
            layer.position = self.mousePointInHostLayer()
            CATransaction.commit()
        }
        _fearTimer = timer
    }

    /// Tear down the fear effect: stop following, remove the face, and restore
    /// the real cursor. Idempotent — safe to call from both the CA completion
    /// block and the follow timer's deadline backstop.
    private func stopFear() {
        _fearTimer?.invalidate(); _fearTimer = nil
        _fearLayer?.removeFromSuperlayer(); _fearLayer = nil
        if _fearHidCursor {
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            _fearHidCursor = false
        }
    }

    // MARK: - Explosion GIF overlay

    /// **Where the blast actually starts inside `03_explosion.mp3`** — the one
    /// number the whole ☢️ animation now hangs off. Measured, not guessed: the
    /// clip (3.28 s) is a falling-bomb WHISTLE followed by the blast, and the
    /// whistle is a clean descending tone (2.80 kHz at 0.50 s down to 2.13 kHz at
    /// 1.50 s, narrowband — spectral peak/mean 30–50×) that stops dead at 1.52 s,
    /// where the sub-400 Hz energy jumps ~20× in two 25 ms frames. That step *is*
    /// the explosion.
    ///
    /// The blast's loudest sample is much later, ~2.20 s, and the old code landed
    /// the fireball there. That is what "bomba nu mai cade sincron cu sunetul"
    /// was: by the time the crescendo peaks, the ear has been hearing the
    /// explosion for two thirds of a second and the picture is late. The eye
    /// matches ONSETS, so the fireball's first frame goes here.
    static let explosionBlastOnset: Double = 1.52

    /// Where the whistle swells to the foreground: the 0.75 s frame is the biggest
    /// single step in its envelope (1–6 kHz RMS 2.2 → 3.3, +50 %). The big bomb
    /// crosses the top edge of the screen exactly here, so it appears on the
    /// "here it comes" of the sound instead of sliding in under the quiet lead-in
    /// — Victor's "intră în ecran doar pe partea de fluierătură din sfx".
    static let explosionWhistleForeground: Double = 0.75

    /// Click → fireball for an AIMED bomb. Unchanged at 1.10 s, and now a literal
    /// rather than a subtraction: it is the rhythm the room reacts to (a rhythm of
    /// clicks comes back as a rhythm of explosions) and it is short enough that
    /// clicking never feels like queuing. The sound is fitted to it instead of the
    /// other way round — see `bombBoomLead`.
    static let explosionStrikeDelay: Double = 1.10

    /// How far AHEAD of a click its own boom copy has to start for the clip's
    /// BLAST to land on that click's fireball: the blast is at
    /// `explosionBlastOnset` into the file, the fireball is `explosionStrikeDelay`
    /// after the click.
    ///
    /// One offset, two jobs, as before. It is how far into the clip a per-bomb
    /// copy is seeked, and it is how long after the press the head-of-run boom
    /// still covers a bomb on its own — a target planted exactly this late
    /// explodes on the head boom's own blast, so handing it a second copy would
    /// only double one sound. A third job now falls out for free: the copy's first
    /// `explosionStrikeDelay` seconds are the tail of the whistle, so every aimed
    /// bomb whistles down exactly as long as it is falling.
    static let bombBoomLead: Double = explosionBlastOnset - explosionStrikeDelay

    /// Level of a per-bomb boom, before the equal-power thinning below. Under the
    /// head boom on purpose: these copies are heard on top of it, not instead.
    private static let bombBoomVolume: Float = 0.75

    /// Floor for that thinning. Ten bombs in the air must not silence the tenth.
    private static let bombBoomVolumeFloor: Float = 0.35

    /// Where, inside the square explosion gif, the bomb actually *lands* —
    /// expressed as a fraction up from the bottom of the frame (the OY centre
    /// horizontally). An aimed strike anchors this point to the cursor crosshair
    /// so the blast appears to fall onto the cursor rather than be centred on it.
    static let bombImpactFractionFromBottom: CGFloat = 0.25

    /// The aimed strike is 1.5× larger than before: it used to divide the blast
    /// size by 4, so dividing by `4/1.5` makes it half-again as big.
    static let aimedScaleDivisor: CGFloat = 4 / 1.5

    /// Once the crosshair locks (the user shook it past the aim threshold) it
    /// freezes in place and grows from 1× to this over the remaining time until
    /// the strike, then — at the blast — pops out by `bombReticleStrikePop`× more
    /// and fades away over `bombReticleStrikeFade`s ("fades out when it's bigger").
    private static let bombReticleLockGrow: CGFloat = 2.2
    /// Positive is counter-clockwise — the host layer is y-up, so this is the
    /// trigonometric direction Victor asked the planted target to turn in.
    static let bombReticleRotationSpeed: Double = .pi / 8
    private static let bombReticleStrikePop: CGFloat = 1.5
    private static let bombReticleStrikeFade: Double = 0.45

    /// Every planted target sits BELOW every blast — not below the one bomb that
    /// lands on it, below all of them. Three targets clicked on top of each other
    /// therefore still get three explosions that all cover all three rings.
    /// zPosition sorts siblings globally, which is exactly why this is two
    /// constants rather than insertion order: order can't express "all of A under
    /// all of B" once the two sets interleave in time.
    static let bombReticleZ: CGFloat = 10_000
    static let bombBlastZ: CGFloat = 11_000

    /// How long a press waits for its FIRST click before committing to the
    /// ORIGINAL nuke: one full-screen blast in the middle of the screen. Aiming is
    /// an opt-in — you get the big one for free, and only trade it for the small
    /// precise ones by actually clicking.
    ///
    /// It is `explosionWhistleForeground` on purpose, because that is the instant
    /// the big bomb crosses the top edge of the screen: **once you can see it
    /// falling, it is too late to aim.** That is the rule Victor asked for, and it
    /// is the only deadline that needs no explaining in the room — the screen
    /// itself announces it. It also means every run owns at least one bomb and
    /// therefore always ends the same way, through `finishBomb`, instead of
    /// through an idle timer.
    static let bombAutoDropDelay: Double = explosionWhistleForeground

    // MARK: The bomb that falls into the blast

    /// The falling-bomb sprite: nose down, tail alight, trimmed to its opaque box
    /// so the geometry below can be stated in fractions of the artwork instead of
    /// fractions of a transparent margin.
    private static let fallingBombImage: CGImage? = {
        guard let url = Bundle.module.url(forResource: "falling-bomb", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    /// Aspect and nose position, measured on the trimmed png (116 × 255 px). The
    /// tip sits on the bottom edge at 52.2 % of the width — very slightly right of
    /// centre, and worth honouring rather than rounding to 0.5: the entire point
    /// of the fall is that the *nose* arrives on the crosshair.
    static let fallingBombAspect: CGFloat = 116.0 / 255.0
    static let fallingBombTipXFraction: CGFloat = 60.5 / 116.0

    /// Bomb height as a fraction of ITS OWN blast's diameter. This is how "bomba e
    /// mare pt explozia full screen și proporțional mai mică pt exploziile
    /// țintite" stays one number instead of two sizes: the aimed blast is already
    /// `aimedScaleDivisor` smaller, so its bomb shrinks with it automatically and
    /// the pairing can never drift.
    ///
    /// Halved from 0.22 on 2026-09-02 ("fă 2× mai mică bomba, și aia mare și alea
    /// mici") — one fraction, both sizes at once, which is the payoff of stating
    /// this as a fraction rather than as two sizes. Note what it does NOT touch:
    /// the fall is timed and placed by the nose, so a smaller bomb still crosses
    /// the top edge on the same beat and still lands on the same pixel. Only the
    /// sprite got smaller.
    static let fallingBombHeightPerBlast: CGFloat = 0.11

    /// …except the full-screen bomb, which is deliberately kept BELOW proportional
    /// (halved a second time on 2026-09-02, while the aimed ones stayed).
    ///
    /// Strict proportionality is the wrong law at this end of the scale. The
    /// full-screen blast is `aimedScaleDivisor` (≈2.67×) wider than an aimed one,
    /// so a bomb scaled straight off it fills a quarter of the screen height for
    /// the whole fall and stops reading as an object coming from very far away —
    /// it reads as an object being lowered. The aimed bombs are small enough that
    /// they need no such correction, which is why this factor belongs here and not
    /// in the fraction above.
    static let fullScreenBombShrink: CGFloat = 0.5

    /// The one place either size is computed. Both call sites go through it, so
    /// "how big is a bomb" has a single answer and the tests can ask it directly.
    static func fallingBombHeight(forBlast blastSize: CGFloat, fullScreen: Bool) -> CGFloat {
        blastSize * fallingBombHeightPerBlast * (fullScreen ? fullScreenBombShrink : 1)
    }

    /// A bomb in the air is above every crosshair (it is the thing the crosshair
    /// is waiting for) and below every fireball (it is consumed by its own).
    static let bombFallingZ: CGFloat = 10_500

    /// The explosion gif's frames, decoded once. A bombardment can put several
    /// blasts in the air within a second of each other, and re-decoding 400 KB of
    /// gif on every click hitches exactly while the room is watching.
    private static let explosionFrames: (images: [CGImage], duration: Double) = {
        guard let url = Bundle.module.url(forResource: "explosion", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return ([], 0) }
        var images: [CGImage] = []
        var total: Double = 0
        for i in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            total += gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
        }
        return (images, total)
    }()

    func showExplosionGif(playSound: Bool = true) {
        // A second press RESTARTS the bombardment: every target still ticking and
        // every blast still burning goes, and the run begins again from an empty
        // screen. Clicking the nuke has always re-armed it; with several bombs in
        // the air the alternative would be two overlapping runs racing to hand the
        // pointer back.
        stopBombSession(fade: 0)
        _bombEpoch &+= 1
        let epoch = _bombEpoch
        // The head clip. It is the **full-screen nuke's** sound and nothing
        // else's: its blast at `explosionBlastOnset` is what `bombAutoDropDelay`
        // and the big bomb's fall are derived from. A press left alone therefore
        // ends on it exactly as it always has — and the first click, which
        // cancels the nuke, also takes this clip off and hands the raid's sound
        // to the bomb that was aimed (`playBombBoom`). Each further bomb lays its
        // own boom under the one before it.
        //
        // On the routed path the tablet owns this clip (playSound: false) and
        // plays it in its own HTTP request; it still comes out of this Mac's
        // speakers, which is why the handover has to be able to reach either
        // player — see `SoundManager.stopWherever`.
        if playSound { SoundManager.shared.play("03_explosion.mp3") }

        _bombSessionActive = true
        _bombPending = 0
        _bombPlantedAny = false
        _bombBigDropped = false
        startBombInputCapture()

        // Nobody aimed → the old full-screen nuke, in time with the boom. Once the
        // first target is down this is a no-op: from then on the run is aimed, and
        // bounded by the last small bomb instead.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.bombAutoDropDelay) { [weak self] in
            guard let self, self._bombEpoch == epoch,
                  self._bombSessionActive, !self._bombPlantedAny else { return }
            self.dropFullScreenBomb()
        }
    }

    /// End the whole bombardment: every planted target, every bomb still in the
    /// air, every blast still on screen, and the event tap. Idempotent — the last
    /// bomb finishing, Escape, a re-press and stop-all all funnel here, which is
    /// the only reason it is safe for four callers to race.
    ///
    /// Nothing here gives the cursor back any more: the run never took it. The
    /// pointer stays the pointer from the first frame to the last.
    private func stopBombSession(fade: Double = 0.25) {
        _bombEpoch &+= 1
        _bombSessionActive = false
        _bombPending = 0
        _bombPlantedAny = false
        _bombBigDropped = false
        stopBombInputCapture()

        let layers: [CALayer] = _bombPlanted + _bombFalling + _bombStrikeLayers + _bombBlasts
        _bombPlanted = []
        _bombFalling = []
        _bombStrikeLayers = []
        _bombBlasts = []

        let teardown = {
            for layer in layers {
                layer.removeAllAnimations()
                layer.removeFromSuperlayer()
            }
        }

        guard fade > 0, !layers.isEmpty else { teardown(); return }
        for layer in layers {
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = layer.presentation()?.opacity ?? 1.0
            out.toValue = 0.0
            out.duration = fade
            out.fillMode = .forwards
            out.isRemovedOnCompletion = false
            layer.add(out, forKey: "bombSessionFade")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: teardown)
    }

    // MARK: The fall

    /// Where a blast's gif goes. Split out of `spawnBombBlast` because the falling
    /// bomb has to aim at the very point the fireball will later cover, and
    /// deriving that point from a second copy of this arithmetic is exactly how
    /// the two drift a few pixels apart.
    ///
    /// The full-screen one keeps the geometry it always had: centred, then lifted
    /// by `h/6 - h*0.1`, which is what puts the fireball where the eye expects it
    /// instead of at the gif's own middle. The aimed one is anchored by its impact
    /// point rather than its middle, so the blast appears to fall ONTO the
    /// crosshair rather than be centred on it.
    static func bombBlastFrame(in bounds: CGRect, fullScreen: Bool, at center: CGPoint) -> CGRect {
        let size = min(bounds.width, bounds.height) * 1.2 / (fullScreen ? 1 : aimedScaleDivisor)
        return fullScreen
            ? CGRect(x: (bounds.width - size) / 2,
                     y: (bounds.height - size) / 2 + bounds.height / 6 - bounds.height * 0.1,
                     width: size, height: size)
            : CGRect(x: center.x - size / 2,
                     y: center.y - size * bombImpactFractionFromBottom,
                     width: size, height: size)
    }

    /// The point a bomb is aimed at. For an aimed strike that is the crosshair
    /// itself — the frame above is built around it — and for the full-screen nuke
    /// it is wherever `bombImpactFractionFromBottom` lands inside that big centred
    /// square, which on a 16:10 retina is roughly three quarters of the way down
    /// the screen.
    static func bombBlastImpactPoint(in bounds: CGRect, fullScreen: Bool, at center: CGPoint) -> CGPoint {
        guard fullScreen else { return center }
        let frame = bombBlastFrame(in: bounds, fullScreen: true, at: .zero)
        return CGPoint(x: frame.midX, y: frame.minY + frame.height * bombImpactFractionFromBottom)
    }

    /// Constant fall speed in points per second, shared by EVERY bomb in the run —
    /// the big one and the small ones alike, which is the "ideal cu o viteză
    /// constantă" half of the request.
    ///
    /// It is derived, not tuned. The big bomb has to cross the top edge on
    /// `explosionWhistleForeground` and put its nose down on
    /// `explosionBlastOnset`, and those two instants plus the screen fix the
    /// speed. The other half of the request then falls out for free: at one fixed
    /// speed, a bomb aimed high on the screen has less screen to fall through than
    /// one aimed near the dock, so it **enters later** — exactly the asymmetry
    /// Victor described.
    static func bombFallSpeed(in bounds: CGRect) -> CGFloat {
        let impact = bombBlastImpactPoint(in: bounds, fullScreen: true, at: .zero)
        let visibleFall = explosionBlastOnset - explosionWhistleForeground
        return max(1, bounds.maxY - impact.y) / CGFloat(visibleFall)
    }

    /// Drop a bomb that arrives nose-first on `impact` in `fall` seconds.
    ///
    /// It starts `speed × fall` points higher, which for anything but a target on
    /// the very bottom edge is off the top of the screen — and the overlay window
    /// simply does not draw what is above it. That is the whole "enters the screen
    /// partway down" effect: no clipping mask, no visibility scheduling, just a
    /// layer that is off-screen until it isn't, and one linear animation the
    /// window server can run without us.
    @discardableResult
    private func spawnFallingBomb(to impact: CGPoint, blastSize: CGFloat,
                                  fullScreen: Bool, fall: Double) -> CALayer? {
        guard let image = Self.fallingBombImage, fall > 0 else { return nil }
        let height = Self.fallingBombHeight(forBlast: blastSize, fullScreen: fullScreen)

        let bomb = CALayer()
        bomb.bounds = CGRect(x: 0, y: 0, width: height * Self.fallingBombAspect, height: height)
        // Anchored on the NOSE — bottom edge of the trimmed png, 52.2 % across —
        // so `position` is literally the point being bombed and the fall is a
        // straight line between two impact points rather than between two centres.
        bomb.anchorPoint = CGPoint(x: Self.fallingBombTipXFraction, y: 0)
        bomb.contents = image
        bomb.contentsGravity = .resizeAspect
        bomb.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        bomb.zPosition = Self.bombFallingZ

        let start = CGPoint(x: impact.x, y: impact.y + CGFloat(fall) * Self.bombFallSpeed(in: hostLayer.bounds))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bomb.position = start
        CATransaction.commit()
        hostLayer.addSublayer(bomb)
        _bombFalling.append(bomb)

        let drop = CABasicAnimation(keyPath: "position.y")
        drop.fromValue = start.y
        drop.toValue = impact.y
        drop.duration = fall
        drop.timingFunction = CAMediaTimingFunction(name: .linear)   // constant speed, as asked
        drop.fillMode = .forwards
        drop.isRemovedOnCompletion = false
        bomb.add(drop, forKey: "bombFall")
        return bomb
    }

    /// The bomb has arrived; the fireball takes it from here.
    private func consumeFallingBomb(_ bomb: CALayer?) {
        guard let bomb else { return }
        bomb.removeAllAnimations()
        bomb.removeFromSuperlayer()
        _bombFalling.removeAll { $0 === bomb }
    }

    /// The press nobody aimed: the original full-screen nuke. It is counted like
    /// any other bomb so the run still ends through `finishBomb`, and it carries
    /// no `playBombBoom` — the head clip is its sound, which is the entire reason
    /// its timing has to be exact. Reaching here at all means no click ever came,
    /// so the head clip is still playing: the handover in `playBombBoom` only
    /// fires on a click, and a click before this point would have cancelled it.
    ///
    /// This fires at `bombAutoDropDelay`, i.e. the instant the bomb clears the top
    /// edge. From here the fall is `explosionBlastOnset - explosionWhistleForeground`
    /// long, so the fireball's first frame lands on the blast in the clip. It also
    /// closes aiming for good (`_bombBigDropped`): the deadline the screen
    /// announces is a real deadline, and a small bomb planted under a big one
    /// already falling would land after it, out of the raid it belongs to.
    private func dropFullScreenBomb() {
        guard _bombSessionActive else { return }
        _bombPlantedAny = true
        _bombBigDropped = true
        _bombPending += 1

        let bounds = hostLayer.bounds
        let fall = Self.explosionBlastOnset - Self.explosionWhistleForeground
        let bomb = spawnFallingBomb(to: Self.bombBlastImpactPoint(in: bounds, fullScreen: true, at: .zero),
                                    blastSize: Self.bombBlastFrame(in: bounds, fullScreen: true, at: .zero).width,
                                    fullScreen: true, fall: fall)

        let epoch = _bombEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + fall) { [weak self] in
            guard let self, self._bombEpoch == epoch else { return }
            self.consumeFallingBomb(bomb)
            self.spawnBombBlast(at: .zero, fullScreen: true)
        }
    }

    /// Plant a target where the user clicked and start its bomb falling.
    ///
    /// There is no crosshair to hand over any more — the pointer stayed the
    /// pointer — so the click MAKES the target, red and armed from its first
    /// frame, and the arrow goes on moving over it. It then grows and turns
    /// counter-clockwise for the length of the fuse while its own bomb whistles
    /// down onto it, and the blast lands on the point that was under the cursor at
    /// the click — not wherever the mouse has wandered to by then, which is the
    /// whole reason the point is captured here rather than read again at strike
    /// time.
    fileprivate func plantBombAtCursor() {
        // Once the big one is on its way down, the raid is the big one. Clicks are
        // still swallowed — the app underneath must not get them — they just stop
        // making targets. See `bombAutoDropDelay`.
        guard _bombSessionActive, !_bombBigDropped else { return }
        let point = mousePointInHostLayer()

        // **Every target stays until its own bomb lands** (Victor, 2026-09-14),
        // which undoes the one-crosshair rule of 2026-09-09 — `retirePlantedReticles`
        // and its call from here are gone.
        //
        // That rule read the pile of rings as clutter; the pile is the raid. A
        // chain of clicks is someone marking four places and then watching four
        // bombs come down on them one after another, and a mark that vanishes the
        // instant the next one is made stops being a mark of anything — the room
        // loses which points are still coming, and the target that *is* under the
        // falling bomb is the one that already went. What went with it was the
        // pop-and-fade, the only frame that ties a blast to the ring it grew
        // under. So each reticle now burns its own fuse and is taken off by its
        // own strike below, exactly as a single click always did.
        let reticle = Self.makeBombReticleLayer(armed: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reticle.position = point
        reticle.zPosition = Self.bombReticleZ
        CATransaction.commit()
        hostLayer.addSublayer(reticle)

        let fuse = Self.explosionStrikeDelay
        let animations = Self.makeBombReticleLockAnimations(remaining: fuse)
        reticle.add(animations.grow, forKey: "reticleLockGrow")
        reticle.add(animations.rotate, forKey: "reticleLockRotate")

        // Same speed as the big one, so a target high on the screen gets a bomb
        // that only appears near the end of its fuse — the small bombs read as
        // part of the same raid, not as a separate effect with its own physics.
        let bomb = spawnFallingBomb(to: point,
                                    blastSize: Self.bombBlastFrame(in: hostLayer.bounds,
                                                                   fullScreen: false, at: point).width,
                                    fullScreen: false, fall: fuse)

        _bombPlanted.append(reticle)
        // The FIRST click is what cancels the full-screen nuke, so it is also
        // what orphans the head clip that was scoring it — see `playBombBoom`.
        let firstOfTheRaid = !_bombPlantedAny
        _bombPlantedAny = true
        _bombPending += 1
        playBombBoom(takingOverFromHeadClip: firstOfTheRaid)

        let epoch = _bombEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + fuse) { [weak self] in
            guard let self, self._bombEpoch == epoch else { return }
            self._bombPlanted.removeAll { $0 === reticle }
            self.consumeFallingBomb(bomb)
            self.spawnBombBlast(at: point)
            // The one frame that ties the blast to the ring it grew under: the
            // target pops as the fireball opens. The `superlayer` check is the
            // only case left where there is nothing to pop — `stopBombSession`
            // tore every layer down while this strike was still pending.
            if reticle.superlayer != nil { self.strikeFadeReticle(reticle) }
        }
    }

    /// Give the bomb just planted its own boom, so a rhythm of clicks comes back
    /// as a rhythm of explosions instead of one clip covering all of them.
    ///
    /// Three things keep that from turning into noise:
    /// * the copy is seeked to `bombBoomLead` so ITS blast arrives with ITS
    ///   fireball — which also means the fuse is scored by the tail of the
    ///   whistle, under the bomb that is visibly falling;
    /// * every copy after the first swells in over the whole fuse rather than
    ///   banging in at once;
    /// * simultaneous copies are thinned by 1/√n (n = bombs still in the air,
    ///   this one included), the equal-power law: two booms together then land at
    ///   about the loudness of one, not twice it.
    ///
    /// **`takingOverFromHeadClip` is the fix for the double boom** (Victor,
    /// 2026-09-17: "când pun o singură bombă … parcă se aude sunetul de două ori
    /// picând"). The head clip started at the press belongs to the **full-screen
    /// nuke** — that is the only thing its 1.52 s blast is timed to. The first
    /// click cancels the nuke (`_bombPlantedAny`), so from that instant the head
    /// clip is scoring a bomb that will never fall, and its blast arrives with
    /// nothing under it — a beat away from the aimed bomb's own, which is what
    /// the ear hears as one explosion landing twice.
    ///
    /// It used to be ducked by arithmetic instead: a bomb planted within
    /// `bombBoomLead` of the press explodes almost exactly on the head blast, so
    /// it was left uncovered and given no copy. That is true, but it only covers
    /// clicks in the first 0.42 s — and the aiming window runs to
    /// `bombAutoDropDelay` (0.75 s), so every click in the 0.33 s between them
    /// produced two blasts. Handing the clip over instead is the same idea
    /// without the window: the head clip is cut (`stopWherever` — it may be the
    /// Mac's or the tablet's), and this bomb plays the *full* clip level with no
    /// swell, because it is not layering under anything any more, it IS the
    /// sound of the raid. The seek keeps its whistle continuous across the
    /// handover: the head clip is at most `bombAutoDropDelay` in, the copy
    /// resumes at `bombBoomLead`, both inside the same descending whistle.
    private func playBombBoom(takingOverFromHeadClip: Bool) {
        if takingOverFromHeadClip {
            SoundManager.shared.stopWherever("03_explosion.mp3", fade: Self.bombHeadClipHandoverFade)
            SoundManager.shared.playOverlapping(
                "03_explosion.mp3",
                volume: 1.0,
                bluetoothCompensated: false,
                startAt: Self.bombBoomLead)
            return
        }
        let volume = max(Self.bombBoomVolumeFloor,
                         Self.bombBoomVolume / Float(max(1, _bombPending)).squareRoot())
        SoundManager.shared.playOverlapping(
            "03_explosion.mp3",
            volume: volume,
            // Something has been sounding since the first bomb was planted, so
            // the A2DP link is warm; adding the start delay on top would push the
            // crescendo late off the blast it is supposed to land on.
            bluetoothCompensated: false,
            startAt: Self.bombBoomLead,
            fadeIn: Self.explosionStrikeDelay)
    }

    /// How long the head clip takes to die away when the first click hands the
    /// raid's sound over to an aimed bomb. Short enough that the two whistles are
    /// never audibly two, long enough not to click.
    private static let bombHeadClipHandoverFade: Double = 0.12

    /// One bomb has finished burning. The run ends with the LAST one: while any
    /// bomb is still in the air the crosshair stays live and more can be planted,
    /// which is what makes a rhythm of clicks come back as a rhythm of blasts.
    private func finishBomb() {
        _bombPending = max(0, _bombPending - 1)
        guard _bombSessionActive, _bombPending == 0 else { return }
        stopBombSession()
    }

    /// Drop one blast: either the full-screen nuke (`center` is ignored) or the
    /// small aimed strike onto a planted target. The geometry lives in
    /// `bombBlastFrame`, which the falling bomb aims by — see there for why it is
    /// placed the way it is.
    private func spawnBombBlast(at center: CGPoint, fullScreen: Bool = false) {
        let (images, duration) = Self.explosionFrames
        guard let first = images.first, duration > 0 else { finishBomb(); return }

        let layer = CALayer()
        layer.frame = Self.bombBlastFrame(in: hostLayer.bounds, fullScreen: fullScreen, at: center)
        layer.contentsGravity = .resizeAspect
        layer.zPosition = Self.bombBlastZ
        layer.contents = first
        hostLayer.addSublayer(layer)
        _bombBlasts.append(layer)

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = duration
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false

        let epoch = _bombEpoch
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak layer] in
            guard let self, self._bombEpoch == epoch else { return }
            if let layer {
                layer.removeFromSuperlayer()
                self._bombBlasts.removeAll { $0 === layer }
            }
            self.finishBomb()
        }
        layer.add(anim, forKey: "explosionFrames")
        CATransaction.commit()
    }

    static func makeBombReticleLockAnimations(remaining: CFTimeInterval) -> (grow: CABasicAnimation, rotate: CABasicAnimation) {
        let grow = CABasicAnimation(keyPath: "transform.scale")
        grow.fromValue = 1.0
        grow.toValue = Self.bombReticleLockGrow
        grow.duration = remaining
        grow.timingFunction = CAMediaTimingFunction(name: .easeIn)   // accelerate toward the strike
        grow.fillMode = .forwards
        grow.isRemovedOnCompletion = false

        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        rotate.fromValue = 0.0
        rotate.toValue = Self.bombReticleRotationSpeed * remaining
        rotate.duration = remaining
        rotate.timingFunction = CAMediaTimingFunction(name: .linear)
        rotate.fillMode = .forwards
        rotate.isRemovedOnCompletion = false

        return (grow, rotate)
    }

    static func makeBombReticleStrikeRotateAnimation(from currentRotation: Double, duration: CFTimeInterval) -> CABasicAnimation {
        let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
        rotate.fromValue = currentRotation
        rotate.toValue = currentRotation + Self.bombReticleRotationSpeed * duration
        rotate.duration = duration
        rotate.timingFunction = CAMediaTimingFunction(name: .linear)
        rotate.fillMode = .forwards
        rotate.isRemovedOnCompletion = false
        return rotate
    }

    /// The blast has landed on this target: give it one last outward pop and
    /// fade it out from wherever its rotation had got to, so the ring dissolves
    /// under the explosion instead of blinking out from under it.
    ///
    /// It stays at `bombReticleZ` all the way through the fade — a dying target
    /// still belongs UNDER every blast on screen, including the blasts of other
    /// bombs that land on top of it a moment later.
    private func strikeFadeReticle(_ target: CALayer) {
        _bombStrikeLayers.append(target)

        let base = Self.bombReticleLockGrow
        let currentRotation = (target.presentation()?.value(forKeyPath: "transform.rotation.z") as? Double)
            ?? (target.value(forKeyPath: "transform.rotation.z") as? Double)
            ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.removeAnimation(forKey: "reticleLockGrow")
        target.removeAnimation(forKey: "reticleLockRotate")
        target.setValue(currentRotation, forKeyPath: "transform.rotation.z")
        target.setValue(base, forKeyPath: "transform.scale")
        target.zPosition = Self.bombReticleZ
        CATransaction.commit()

        let dur = Self.bombReticleStrikeFade

        let pop = CABasicAnimation(keyPath: "transform.scale")
        pop.fromValue = base
        pop.toValue = base * Self.bombReticleStrikePop
        pop.duration = dur
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        pop.fillMode = .forwards
        pop.isRemovedOnCompletion = false
        target.add(pop, forKey: "reticleStrikePop")
        target.add(Self.makeBombReticleStrikeRotateAnimation(from: currentRotation, duration: dur),
                   forKey: "reticleStrikeRotate")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = dur
        fade.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        let epoch = _bombEpoch
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak target] in
            guard let self, self._bombEpoch == epoch else { return }
            target?.removeFromSuperlayer()
            self._bombStrikeLayers.removeAll { $0 === target }
        }
        target.add(fade, forKey: "reticleStrikeFade")
        CATransaction.commit()
    }

    // MARK: Click to plant, Escape to call it off

    /// One tap for the click and for Escape, for the fire cursor's reason: both
    /// have to be *taken away* from the app underneath. A click that also pressed
    /// the button below would make dropping a bomb cost something, and an Escape
    /// that also closed the user's dialog would too.
    private func startBombInputCapture() {
        stopBombInputCapture()

        let mask = CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let animator = Unmanaged<EmojiAnimator>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = animator._bombInputTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown,
               CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == 53 {   // Esc
                DispatchQueue.main.async {
                    animator.stopBombSession()
                    SoundManager.shared.stopTabletSound()
                    SoundManager.shared.stopAllPlayers()
                }
                return nil   // consume — the user is calling off the raid, not their app
            }
            if type == .leftMouseDown {
                DispatchQueue.main.async { animator.plantBombAtCursor() }
                return nil   // consume — while it's armed, a click means "bomb here"
            }
            if type == .leftMouseUp {
                // The down was swallowed above, so delivering the up alone would
                // hand the app underneath half a click. The pair goes together.
                return nil
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: refcon) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _bombInputTap = tap
        _bombInputTapSource = src
    }

    private func stopBombInputCapture() {
        if let tap = _bombInputTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let src = _bombInputTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        _bombInputTap = nil
        _bombInputTapSource = nil
    }

    /// Idle (un-aimed) vs armed (shaken-enough) crosshair styling: the idle
    /// reticle is thin + grey; once locked it turns red and thickens. Widths are
    /// 1.5× the original to match the 1.5×-larger reticle geometry.
    private static let bombReticleLineWidthIdle: CGFloat = 1.5
    private static let bombReticleLineWidthArmed: CGFloat = 3.75

    static func makeBombReticleLayer(armed: Bool = false) -> CALayer {
        let size: CGFloat = 180
        let center = CGPoint(x: size / 2, y: size / 2)
        let radius: CGFloat = 54
        let strokeWidth: CGFloat = 3.85
        let color = (armed ? NSColor.systemRed : NSColor.systemGray).cgColor

        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        container.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        let markerAngles = [CGFloat.pi / 2, CGFloat.pi / 2 - 2 * .pi / 3, CGFloat.pi / 2 - 4 * .pi / 3]
        let gapHalfAngle: CGFloat = 0.34
        let ringArcRanges: [(CGFloat, CGFloat)] = [
            (-5 * .pi / 6 + gapHalfAngle, -1 * .pi / 6 - gapHalfAngle),
            (-1 * .pi / 6 + gapHalfAngle, .pi / 2 - gapHalfAngle),
            (.pi / 2 + gapHalfAngle, 7 * .pi / 6 - gapHalfAngle),
        ]
        for (startAngle, endAngle) in ringArcRanges {
            let ring = CAShapeLayer()
            ring.path = Self.bombReticleRingArcPath(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = color
            ring.lineWidth = strokeWidth
            ring.lineCap = .round
            container.addSublayer(ring)
        }

        for angle in markerAngles {
            let marker = CAShapeLayer()
            marker.path = Self.bombReticleTrianglePath(center: center, angle: angle, ringRadius: radius)
            marker.fillColor = color
            marker.strokeColor = nil
            container.addSublayer(marker)
        }

        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.55
        container.shadowRadius = 2.5
        container.shadowOffset = .zero
        return container
    }

    private static func bombReticleRingArcPath(center: CGPoint, radius: CGFloat, startAngle: CGFloat, endAngle: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        return path
    }

    private static func bombReticleTrianglePath(center: CGPoint, angle: CGFloat, ringRadius: CGFloat) -> CGPath {
        let outward = CGVector(dx: cos(angle), dy: sin(angle))
        let tangent = CGVector(dx: -sin(angle), dy: cos(angle))
        let tipDistance = ringRadius - 18.2
        let baseDistance = ringRadius + 9.1
        let halfBase: CGFloat = 14

        let tip = CGPoint(x: center.x + outward.dx * tipDistance, y: center.y + outward.dy * tipDistance)
        let baseCenter = CGPoint(x: center.x + outward.dx * baseDistance, y: center.y + outward.dy * baseDistance)
        let left = CGPoint(x: baseCenter.x + tangent.dx * halfBase, y: baseCenter.y + tangent.dy * halfBase)
        let right = CGPoint(x: baseCenter.x - tangent.dx * halfBase, y: baseCenter.y - tangent.dy * halfBase)

        let path = CGMutablePath()
        path.move(to: tip)
        path.addLine(to: left)
        path.addLine(to: right)
        path.closeSubpath()
        return path
    }

    /// A sniper-scope reticle drawn as CALayers: a ring, four crosshair arms with
    /// a small central gap, and a centre dot — with a soft dark shadow so it reads
    /// on any desktop backdrop. By default it starts thin + grey (the nuke fuse;
    /// `armReticle()` later recolours it red). Pass `armed: true` to build it red
    /// + thick from the first frame (the minigun reticle, which is never grey).
    /// `scale` sizes the whole reticle (nuke 1.5×; the minigun passes a bigger
    /// value) and the stroke widths scale with it so the lines stay proportional.
    static func makeSniperReticle(scale: CGFloat = 1.5, armed: Bool = false) -> CALayer {
        let canonical: CGFloat = 1.5      // the scale at which the width constants are defined
        let d: CGFloat = 65 * scale       // overall reticle box
        let idleW = bombReticleLineWidthIdle * (scale / canonical)
        let armedW = bombReticleLineWidthArmed * (scale / canonical)
        let lineW = armed ? armedW : idleW
        let c = d / 2
        let r = c - armedW                // leave room for the thicker armed stroke
        let gap: CGFloat = 7 * scale      // half-length of the empty centre
        let stroke = (armed ? NSColor.systemRed : NSColor.systemGray).cgColor

        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: d, height: d)
        container.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        let ring = CAShapeLayer()
        ring.path = CGPath(ellipseIn: CGRect(x: c - r, y: c - r, width: 2 * r, height: 2 * r), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = stroke
        ring.lineWidth = lineW
        container.addSublayer(ring)

        let arms = CAShapeLayer()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: c));     path.addLine(to: CGPoint(x: c - gap, y: c))   // left
        path.move(to: CGPoint(x: c + gap, y: c)); path.addLine(to: CGPoint(x: d, y: c))       // right
        path.move(to: CGPoint(x: c, y: 0));     path.addLine(to: CGPoint(x: c, y: c - gap))   // bottom
        path.move(to: CGPoint(x: c, y: c + gap)); path.addLine(to: CGPoint(x: c, y: d))       // top
        arms.path = path
        arms.strokeColor = stroke
        arms.lineWidth = lineW
        container.addSublayer(arms)

        let dotR: CGFloat = 2.0 * scale
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: c - dotR, y: c - dotR, width: 2 * dotR, height: 2 * dotR), transform: nil)
        dot.fillColor = stroke
        container.addSublayer(dot)

        container.shadowColor = NSColor.black.cgColor
        container.shadowOpacity = 0.6
        container.shadowRadius = 1.5 * scale
        container.shadowOffset = .zero
        return container
    }

    /// How much bigger the minigun aiming reticle is than the 1.5× nuke reticle —
    /// the bullet-spray crosshair reads as a heftier "machine-gun sight".
    private static let minigunReticleScale: CGFloat = 2.5
    /// The gun's solo — **zero since 2026-09-17**, i.e. there is no solo.
    ///
    /// It was a silent aiming beat (0.5 s, then a full second from 2026-09-11)
    /// on the reading that a room needs to notice the weapon before it opens
    /// fire. Victor's correction: *"machine gun-ul arată ca foc, ca și cum ar
    /// trage"* — the sprite is drawn mid-burst, muzzle flashing, so a second of
    /// it hanging there silent doesn't read as taking aim, it reads as the
    /// effect being broken. The gun, the reticle, the first bullet hole and the
    /// first frame of noise now all land on t=0.
    ///
    /// The constant stays (at 0) rather than being deleted because it is the one
    /// place those four are tied together: it is also the delay applied to the
    /// *audio* on the routed `/sound/play/22_minigun.mp3` path
    /// (`EffectsEngine.playSound`), whose HTTP request is a separate one from the
    /// one that starts the visual. Putting a beat back means changing one number,
    /// not re-deriving four call sites.
    static let minigunAimLeadIn: Double = 0
    static let minigunBulletHoleScale: CGFloat = 0.7

    // MARK: The gun itself (minigun.gif)

    /// `minigun.gif` is drawn firing up-and-to-the-LEFT (muzzle flash north-west,
    /// spent casings arcing off the same way). Standing on the west side of the
    /// screen it has to fire the other way — *into* the desktop, along the
    /// bullets' trajectory — so the sprite gets mirrored on the X axis. Flip this
    /// to `false` to show it as drawn; nothing else needs to change.
    private static let minigunSpriteFacesWest = true
    /// Horizontal centre line of the receiver inside the source sprite. The
    /// frame is mostly empty sky for casings, so its geometric centre is not the
    /// point that should track the mouse.
    private static let minigunSpriteGunCentreX: CGFloat = 0.758
    /// Anchor at the cut-off bottom of the mount. Keeping it on y=0 leaves the
    /// gun welded to the desktop while its x follows the mouse.
    private static var minigunSpriteMountAnchor: CGPoint {
        CGPoint(x: minigunSpriteFacesWest ? 1 - minigunSpriteGunCentreX
                                          : minigunSpriteGunCentreX,
                y: 0)
    }
    /// How far the gun swings compared with the cursor: half its travel, so you
    /// swing the crosshair 400px and the weapon hauls itself 200px after it.
    private static let minigunSpriteSwayRatio: CGFloat = 0.5

    /// Pure horizontal tracking, deliberately confined to the screen's left
    /// half. A centred cursor parks the body at W/4; edge-to-edge cursor travel
    /// maps to 0…W/2. The artwork keeps its own fixed firing angle throughout.
    static func minigunBodyX(forMouseX mouseX: CGFloat, inWidth _: CGFloat) -> CGFloat {
        mouseX * minigunSpriteSwayRatio
    }

    /// The reticle remains authoritative even when the mouse is motionless, as
    /// it does in an FPS. An off-screen pointer has no visible aim target, so the
    /// legacy full-screen spray remains the fallback for that case.
    static func minigunShotTarget(forMouse mouse: CGPoint, in bounds: CGRect) -> CGPoint? {
        bounds.contains(mouse) ? mouse : nil
    }

    /// Width of the whole sprite frame as a fraction of the screen. The gun body
    /// is only ~46% of that frame (the rest is the casing spray), so 0.44 puts
    /// the gun itself at ~0.20 of the screen — big enough to read as the source
    /// of the burst — while the ejected brass arcs up and to the right over the
    /// lower-left of the desktop.
    private static let minigunSpriteWidthFraction: CGFloat = 0.44
    /// One turn of the 64-frame loop, kept at the source gif's own 0.02s/frame.
    /// The muzzle flash cycles every 8 frames — ~6 flashes/s, a believable
    /// cyclic rate — while the casings need all 64 to complete their arc, so
    /// speeding the loop up would fling the brass out at a comic speed.
    private static let minigunSpriteLoopDuration: Double = 1.28

    /// Build the firing-minigun sprite with its mount on the **bottom edge**.
    /// It slides only on X, resting at one quarter of the screen; the painted-in
    /// barrel angle never rotates.
    ///
    /// Returns nil (silently) when the asset is missing: the burst itself must
    /// still run.
    private func makeMinigunSprite(in bounds: CGRect) -> CALayer? {
        guard let url = Bundle.module.url(forResource: "minigun", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("minigun.gif not found in bundle")
            return nil
        }
        let frameCount = CGImageSourceGetCount(source)
        guard frameCount > 0 else { return nil }
        var frames: [CGImage] = []
        for i in 0..<frameCount {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) { frames.append(cg) }
        }
        guard let first = frames.first else { return nil }

        let aspect = CGFloat(first.width) / CGFloat(first.height)
        let w = bounds.width * Self.minigunSpriteWidthFraction
        let h = w / aspect

        let gun = CALayer()
        gun.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        gun.anchorPoint = Self.minigunSpriteMountAnchor
        let mouse = mousePointInHostLayer()
        gun.position = CGPoint(x: Self.minigunBodyX(forMouseX: mouse.x, inWidth: bounds.width),
                               y: bounds.minY)

        let sprite = CALayer()
        sprite.frame = gun.bounds
        sprite.contents = first
        sprite.contentsGravity = .resizeAspect
        // Pixel art: bilinear smoothing at this magnification turns the barrels
        // into grey mush, so keep the hard pixel edges.
        sprite.magnificationFilter = .nearest
        sprite.minificationFilter = .nearest
        if Self.minigunSpriteFacesWest {
            sprite.transform = CATransform3DMakeScale(-1, 1, 1)
        }
        gun.addSublayer(sprite)
        gun.opacity = 0

        let spin = CAKeyframeAnimation(keyPath: "contents")
        spin.values = frames
        spin.duration = Self.minigunSpriteLoopDuration
        spin.repeatCount = .infinity
        spin.calculationMode = .discrete
        sprite.add(spin, forKey: "spin")
        return gun
    }

    /// Float a bigger, always-red sniper crosshair on the cursor and follow it at
    /// 60fps for the whole minigun burst (the real cursor is hidden, the crosshair
    /// stands in). Tears itself down `duration`s later — keyed to this exact
    /// reticle so a re-press (fresh reticle) isn't torn down by an old schedule.
    ///
    /// `gun`, if given, receives its horizontal position on the same tick — one
    /// timer moves both, so the weapon can never lag a frame behind the
    /// crosshair it is chasing. Its orientation remains fixed.
    ///
    /// `revealAfter` is the aiming lead-in: the **gun** is what appears first and
    /// the pointer only becomes the crosshair that many seconds later, on the
    /// same instant as the first shot. The layer and the 60 fps tick are created
    /// up front regardless — the tick is what hauls the weapon after the mouse
    /// during the lead-in, and creating the layer early means every identity
    /// guard (`_minigunReticleLayer === reticle`) covers the lead-in too, so a
    /// cancelling re-press inside it cannot leave a reveal scheduled behind it.
    /// Only the crosshair's *visibility* and the real cursor's hide are deferred.
    private func startMinigunReticle(following gun: CALayer?,
                                     revealAfter leadIn: Double = 0,
                                     autoStopAfter duration: Double) {
        stopMinigunReticle()   // never leak a previous burst's reticle (and its gun)
        _minigunGunLayer = gun

        let reticle = Self.makeSniperReticle(scale: Self.minigunReticleScale, armed: true)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        reticle.position = mousePointInHostLayer()
        reticle.zPosition = 9_000   // ride above the bullet holes
        reticle.opacity = leadIn > 0 ? 0 : 1
        CATransaction.commit()
        hostLayer.addSublayer(reticle)
        _minigunReticleLayer = reticle

        // Hiding the real cursor is half of "the pointer turns into a crosshair",
        // so it happens on the same instant the reticle is shown — not before,
        // or the lead-in would leave the desktop with no pointer at all.
        let revealCrosshair = { [weak self, weak reticle] in
            guard let self, let reticle, self._minigunReticleLayer === reticle else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            reticle.opacity = 1
            CATransaction.commit()
            if !self._minigunReticleHidCursor {
                Self.armBackgroundCursorHiding()
                NSCursor.hide()
                CGDisplayHideCursor(CGMainDisplayID())
                self._minigunReticleHidCursor = true
            }
            overlayInfo("🔫 reticle revealed")
        }
        if leadIn > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + leadIn, execute: revealCrosshair)
        } else {
            revealCrosshair()
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self, self._minigunReticleTimer === t else { t.invalidate(); return }
            let mouse = self.mousePointInHostLayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // follow instantly, no implicit animation
            self._minigunReticleLayer?.position = mouse
            if let gun = self._minigunGunLayer {
                gun.position.x = Self.minigunBodyX(forMouseX: mouse.x,
                                                   inWidth: self.hostLayer.bounds.width)
            }
            CATransaction.commit()
        }
        _minigunReticleTimer = timer

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self, weak reticle] in
            guard let self, self._minigunReticleLayer === reticle else { return }
            self.stopMinigunReticle()
        }
    }

    /// Stop following the cursor, remove the minigun reticle, and restore the real
    /// cursor. Idempotent — safe to call when nothing is running (toggle-off,
    /// stop-all, or the natural end-of-burst all funnel through here).
    private func stopMinigunReticle() {
        _minigunReticleTimer?.invalidate(); _minigunReticleTimer = nil
        _minigunReticleLayer?.removeFromSuperlayer(); _minigunReticleLayer = nil
        // The gun is owned by the burst's container (which fades and is torn down
        // with the holes) — just stop steering it.
        _minigunGunLayer = nil
        if _minigunReticleHidCursor {
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            _minigunReticleHidCursor = false
        }
    }

    // MARK: - 🪚 Chainsaw cursor (tile #18 — the pointer becomes a running chainsaw)

    /// The art is a 4×4 sprite SHEET (`chainsaw-frames.png`), not a gif, because
    /// the smoke puff and the antialiased blade need real 8-bit alpha and gif
    /// only carries 1-bit — a gif of it fringes white against a dark desktop. The 16
    /// cells are equal-sized, so slicing is a pure `cropping(to:)` per frame.
    private static let chainsawGrid = (cols: 4, rows: 4)

    /// The 16 frames, decoded once. A press must be instant (the cursor is
    /// already moving), so the ~1.7 MP sheet is not re-decoded per press.
    private static let chainsawFrames: [CGImage] = {
        guard let url = Bundle.module.url(forResource: "chainsaw-frames", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let cw = sheet.width / chainsawGrid.cols
        let ch = sheet.height / chainsawGrid.rows
        var frames: [CGImage] = []
        // Row-major: the sheet reads left-to-right, top-to-bottom, and CGImage
        // cropping is top-left origin too, so the cell order IS the frame order.
        for row in 0..<chainsawGrid.rows {
            for col in 0..<chainsawGrid.cols {
                let rect = CGRect(x: col * cw, y: row * ch, width: cw, height: ch)
                if let cell = sheet.cropping(to: rect) { frames.append(cell) }
            }
        }
        return frames
    }()

    /// Where the blade actually bites, as a fraction of a frame: mid-bar, on the
    /// lower row of teeth (x≈0.600, y≈0.815 from the top). Used as the layer's
    /// `anchorPoint`, so THAT is the point riding the pointer — the kerf then
    /// comes out from under the teeth, with the whole machine held above the
    /// cut, the way a saw is actually used.
    ///
    /// It was the sprite's centre before, and before that the blade tip. The tip
    /// read beautifully as a pointer but put the cut ~180 pt from what the hand
    /// was aiming at; the centre fixed the aim but made the screen split open
    /// through the middle of the engine block, which is why you could never tell
    /// what was doing the cutting. The teeth are the only point that is both
    /// accurate and legible.
    private static let chainsawCutAnchor = CGPoint(x: 0.600, y: 1 - 0.815)

    /// Width of the kerf on screen, in points. The brief said "at least 10";
    /// wider than that is not just cosmetic — the mask cells it clears are what
    /// actually severs a piece, so a thin cut makes closing a loop fiddly.
    private static let chainsawKerfWidth: CGFloat = 16

    /// Side of a cut-mask cell, in points. Coarse enough that the connectivity
    /// sweep is a few ms over the whole screen, fine enough that a torn edge
    /// reads as torn rather than as a staircase.
    private static let chainsawCellSize: CGFloat = 3

    /// Below this many cells a loose piece is a crumb from the kerf itself, and
    /// dropping it reads as a rendering glitch rather than as a piece of screen.
    private static let chainsawMinPieceCells = 24

    /// Connectivity runs every N follow ticks (60 fps / 6 = 10 Hz). A piece can
    /// only come loose on a stroke, and a tenth of a second after the stroke
    /// that freed it is not a delay anyone can see.
    private static let chainsawSweepEveryTicks = 6

    /// Displayed width in points. Big enough to read as a chainsaw across a
    /// projected room, small enough that it still points at something.
    private static let chainsawWidth: CGFloat = 450

    /// 16 frames at 15 fps ≈ a 1.07 s rev cycle. The source frames jitter in
    /// position as well as in shape, so at the 24 fps this started on the saw
    /// read as *twitching* rather than idling — the eye tracked the jumps
    /// instead of the saw. Slowing it down turns the same jitter back into a
    /// heavy vibration, which is what a chainsaw at rest actually looks like.
    private static let chainsawFPS: Double = 15

    /// Fallback length if `18_chainsaw.mp3` can't be measured (its real one).
    private static let chainsawFallbackDuration: Double = 6.09

    /// Replace the mouse pointer with a running chainsaw for as long as
    /// `18_chainsaw.mp3` lasts (or until the tile is stopped, whichever is
    /// first). The real cursor is hidden — the saw IS the pointer.
    ///
    /// Not a `trackEffect` client: like the minigun reticle this owns a follow
    /// timer and a hidden system cursor, so it must be torn down through
    /// `stopChainsawCursor` and never by the generic `activeEffects` sweep,
    /// which would drop the layer and leave the cursor invisible forever.
    func showChainsawCursor(playSound: Bool = true) {
        let frames = Self.chainsawFrames
        guard let first = frames.first else {
            overlayError("chainsaw-frames.png not found in bundle")
            return
        }

        stopChainsawCursor(fade: 0)   // never leak a previous run's timer/hidden cursor

        // Grab the sheet BEFORE the saw is on screen. A falling piece is made of
        // this image, and the capture sees our own overlay, so a saw drawn first
        // would be baked into whatever piece it happens to be standing on. The
        // fast display grab (~20 ms) is what makes "before" affordable at all —
        // the `screencapture` subprocess the other effects use costs hundreds of
        // ms, which on a cursor replacement would read as the shortcut misfiring.
        _chainsawScreenshot = Self.captureBuiltInDisplayFast() ?? Self.captureBuiltInDisplay()

        var duration = Self.chainsawFallbackDuration
        if let soundURL = SoundManager.shared.soundURL(for: "18_chainsaw.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        let w = Self.chainsawWidth
        let h = w * CGFloat(first.height) / CGFloat(first.width)

        let saw = CALayer()
        saw.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        saw.anchorPoint = Self.chainsawCutAnchor
        saw.contents = first
        saw.contentsGravity = .resizeAspect
        saw.zPosition = 9_500          // above every other effect: it's the pointer
        saw.opacity = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        saw.position = mousePointInHostLayer()
        CATransaction.commit()
        hostLayer.addSublayer(saw)
        _chainsawLayer = saw

        let rev = CAKeyframeAnimation(keyPath: "contents")
        rev.values = frames
        rev.duration = Double(frames.count) / Self.chainsawFPS
        rev.repeatCount = .infinity
        rev.calculationMode = .discrete
        saw.add(rev, forKey: "rev")

        // Snap in rather than drift in: the cursor is a thing you are already
        // looking at, and a slow fade there reads as lag.
        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.12
        fadeIn.fillMode = .forwards
        fadeIn.isRemovedOnCompletion = false
        saw.opacity = 1
        saw.add(fadeIn, forKey: "fadeIn")

        // Hide the real pointer for the run. The arm step lifts the "frontmost
        // app only" restriction so it also works while the user is in another
        // app (the common case for this overlay). Balanced in stopChainsawCursor.
        if !_chainsawHidCursor {
            Self.armBackgroundCursorHiding()
            NSCursor.hide()
            CGDisplayHideCursor(CGMainDisplayID())
            _chainsawHidCursor = true
        }

        beginChainsawDamage()
        beginChainsawSparks()

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self, self._chainsawTimer === t else { t.invalidate(); return }
            let point = self.mousePointInHostLayer()
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // follow instantly, no implicit animation
            self._chainsawLayer?.position = point
            self._chainsawSparks?.emitterPosition = point
            CATransaction.commit()
            self.extendChainsawCut(to: point)
        }
        _chainsawTimer = timer

        if playSound { SoundManager.shared.play("18_chainsaw.mp3") }

        // The lifecycle rule: the sound's length is the authoritative teardown,
        // never the tablet's /sound/stopped (which a flaky venue network eats —
        // and here that would leave the desktop with no visible cursor at all).
        // Generation-guarded so an old run's timer can't kill a newer run.
        _chainsawGeneration += 1
        let generation = _chainsawGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self._chainsawGeneration == generation else { return }
            self.stopChainsawCursor()
        }
    }

    /// Put the real pointer back. Idempotent — the early stop from the tablet,
    /// the natural end of the clip and `stopAllActiveEffects` all funnel here.
    /// The system cursor is restored only once the saw has finished fading, so
    /// the two are never on screen together.
    func stopChainsawCursor(fade: Double = 0.25) {
        _chainsawTimer?.invalidate(); _chainsawTimer = nil
        _chainsawGeneration += 1      // any pending self-stop is now stale

        let restoreCursor = { [weak self] in
            guard let self, self._chainsawHidCursor else { return }
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            self._chainsawHidCursor = false
        }

        // The screen heals when the saw goes: kerf, holes and anything still in
        // mid-air fade out together, on the same clock, so the desktop is never
        // left with a black gash and no explanation for it.
        let damage = _chainsawDamage
        let sparks = _chainsawSparks
        // Stop making new sparks the instant the saw is called off; the ones
        // already in the air keep their arc and die of old age, so the shower
        // trails away instead of being cut off mid-flight.
        sparks?.birthRate = 0
        _chainsawSparks = nil
        _chainsawDamage = nil
        _chainsawKerfLayer = nil
        _chainsawKerfPath = nil
        _chainsawMask = nil
        _chainsawScreenshot = nil
        _chainsawLastCut = nil

        let saw = _chainsawLayer
        _chainsawLayer = nil

        let teardown = {
            for layer in [saw, damage, sparks].compactMap({ $0 }) {
                layer.removeAllAnimations()
                layer.removeFromSuperlayer()
            }
            restoreCursor()
        }

        guard fade > 0, saw != nil || damage != nil || sparks != nil else { teardown(); return }

        for layer in [saw, damage, sparks].compactMap({ $0 }) {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = layer.presentation()?.opacity ?? 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = fade
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "fadeOut")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: teardown)
    }

    // MARK: Sawing the screen apart

    /// Set up the layer stack the cut lives in, and the mask that decides what
    /// is still holding on. Ordered kerf → holes → pieces so a piece falls in
    /// front of the black it came out of, and the whole stack sits under the saw.
    private func beginChainsawDamage() {
        let bounds = hostLayer.bounds
        let damage = CALayer()
        damage.frame = bounds
        damage.zPosition = 9_000       // under the saw (9_500), over every other effect
        hostLayer.addSublayer(damage)
        _chainsawDamage = damage

        let kerf = CAShapeLayer()
        kerf.frame = bounds
        kerf.fillColor = nil
        kerf.strokeColor = NSColor.black.cgColor
        kerf.lineWidth = Self.chainsawKerfWidth
        // Round cap and join: the kerf is a slot a moving blade left, and mitred
        // corners on a hand-drawn squiggle look like vector art, not like damage.
        kerf.lineCap = .round
        kerf.lineJoin = .round
        damage.addSublayer(kerf)
        _chainsawKerfLayer = kerf
        _chainsawKerfPath = CGMutablePath()

        _chainsawMask = ChainsawCutMask(size: bounds.size, cellSize: Self.chainsawCellSize)
        _chainsawLastCut = nil
        _chainsawTicksToSweep = Self.chainsawSweepEveryTicks
    }

    /// The shower thrown off the biting point, running for the whole cut.
    ///
    /// It is not decoration: the saw is 450 pt of drawing and, once the anchor
    /// moved to the teeth, nothing on screen said *which* of those points is the
    /// one that removes material. The sparks are the answer — a bright, moving
    /// dot exactly where the kerf appears, visible across a projected room.
    ///
    /// Deliberately independent of the mouse: it burns whether or not the saw is
    /// being moved, because an idling blade against material still throws chips.
    /// A shower that switched off when the hand stopped would go dark at exactly
    /// the moments Victor is holding the saw still to point at something.
    private func beginChainsawSparks() {
        guard let dot = Self.chainsawSparkDot else { return }

        let emitter = CAEmitterLayer()
        emitter.frame = hostLayer.bounds
        emitter.emitterPosition = mousePointInHostLayer()
        emitter.emitterShape = .point
        emitter.emitterMode = .points
        emitter.zPosition = 9_600      // over the saw itself: sparks fly toward the room
        // Additive, so overlapping sparks pile up into a white-hot core instead
        // of averaging into a flat orange smear.
        emitter.renderMode = .additive
        emitter.emitterCells = [Self.chainsawSparkCell(dot: dot, longitude: 0),
                                Self.chainsawSparkCell(dot: dot, longitude: .pi)]
        hostLayer.addSublayer(emitter)
        _chainsawSparks = emitter
    }

    /// One lateral jet. Two of them (longitude 0 and π) give the two-sided spray
    /// a blade throws along the line of the cut, rather than a firework.
    private static func chainsawSparkCell(dot: CGImage, longitude: CGFloat) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = dot
        cell.birthRate = 110
        cell.lifetime = 0.55
        cell.lifetimeRange = 0.25
        cell.velocity = 420
        cell.velocityRange = 260
        cell.emissionLongitude = longitude
        // A narrow fan (±20°) around the horizontal: wider than this and the
        // sparks read as an explosion at the cursor instead of as material
        // being thrown sideways out of a groove.
        cell.emissionRange = .pi / 9
        cell.yAcceleration = -900      // host layer is y-up, so gravity is negative
        cell.scale = 0.16
        cell.scaleRange = 0.12
        cell.scaleSpeed = -0.12        // they burn down to nothing as they fly
        cell.alphaSpeed = -1.6
        cell.color = NSColor(calibratedRed: 1.0, green: 0.82, blue: 0.35, alpha: 1.0).cgColor
        // Spread across the orange→white band, so the shower has hot and cool
        // sparks in it the way a real one does.
        cell.greenRange = 0.35
        cell.blueRange = 0.5
        cell.spin = 0
        return cell
    }

    /// A soft round spark, built once: white core fading to transparent, so the
    /// cell's tint colours it and its edges never show a square.
    private static let chainsawSparkDot: CGImage? = {
        let side = 32
        guard let ctx = CGContext(data: nil, width: side, height: side,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let centre = CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2)
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor(white: 1, alpha: 1).cgColor,
                                                 NSColor(white: 1, alpha: 0.85).cgColor,
                                                 NSColor(white: 1, alpha: 0).cgColor] as CFArray,
                                        locations: [0, 0.35, 1]) else { return nil }
        ctx.drawRadialGradient(gradient, startCenter: centre, startRadius: 0,
                               endCenter: centre, endRadius: CGFloat(side) / 2,
                               options: [])
        return ctx.makeImage()
    }()

    /// One mouse sample's worth of sawing: extend the drawn kerf, clear the same
    /// band out of the mask, and every so often ask what has come loose.
    private func extendChainsawCut(to point: CGPoint) {
        guard let mask = _chainsawMask, let path = _chainsawKerfPath else { return }

        if let last = _chainsawLastCut {
            let dx = point.x - last.x, dy = point.y - last.y
            let distance = (dx * dx + dy * dy).squareRoot()
            // Sub-pixel jitter is not a cut; a jump is not one either. A pointer
            // that teleports (a Space switch, a warp between displays) never
            // passed through the middle, so joining those two samples would saw
            // a long straight line the user never made.
            if distance > 0.6 {
                if distance > 220 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                    // A shade under half the drawn width, so the black stroke
                    // always covers the cells this frees: a piece can then never
                    // fall and leave a hairline of live desktop along its edge.
                    mask.saw(from: last, to: point, radius: Self.chainsawKerfWidth / 2 - 1)
                }
                _chainsawKerfLayer?.path = path
                _chainsawLastCut = point
            }
        } else {
            path.move(to: point)
            _chainsawLastCut = point
        }

        _chainsawTicksToSweep -= 1
        guard _chainsawTicksToSweep <= 0 else { return }
        _chainsawTicksToSweep = Self.chainsawSweepEveryTicks
        guard mask.dirty else { return }
        for piece in mask.detachedPieces(minCells: Self.chainsawMinPieceCells) {
            mask.drop(piece)
            dropChainsawPiece(piece, mask: mask)
        }
    }

    /// Cut the piece out of the captured screen, leave black where it was, and
    /// let it fall out of the frame.
    private func dropChainsawPiece(_ piece: ChainsawCutMask.Piece, mask: ChainsawCutMask) {
        guard let damage = _chainsawDamage else { return }
        let rect = mask.rect(of: piece)
        guard let silhouette = Self.chainsawImage(rgba: mask.silhouetteRGBA(of: piece),
                                                 width: piece.cols, height: piece.rows) else { return }

        // The hole first, and permanently: it is the screen's new state, not part
        // of the fall. Nearest-neighbour on purpose — the mask is cell-resolution
        // and smoothing it would give the tear a soft airbrushed edge.
        let hole = CALayer()
        hole.frame = rect
        hole.contents = silhouette
        hole.magnificationFilter = .nearest
        damage.addSublayer(hole)

        guard let shot = _chainsawScreenshot,
              let sprite = Self.chainsawPieceSprite(screenshot: shot, rect: rect,
                                                    silhouette: silhouette,
                                                    screen: hostLayer.bounds.size) else { return }

        let falling = CALayer()
        falling.frame = rect
        falling.contents = sprite
        falling.zPosition = 100        // in front of the hole it just left
        damage.addSublayer(falling)

        // Gravity, not a slide: ease-in the whole way and let it leave the frame
        // rather than fade, so it reads as having fallen out of the screen
        // instead of having been switched off. It also tips as it goes — a slab
        // that drops perfectly level looks like a UI transition.
        let drop = rect.maxY + rect.height
        let duration = 0.35 + (drop / 900).squareRoot() * 1.1
        let fall = CABasicAnimation(keyPath: "position.y")
        fall.fromValue = falling.position.y
        fall.toValue = falling.position.y - drop
        fall.duration = duration
        fall.timingFunction = CAMediaTimingFunction(name: .easeIn)
        fall.fillMode = .forwards
        fall.isRemovedOnCompletion = false
        falling.add(fall, forKey: "fall")

        let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
        tilt.fromValue = 0
        tilt.toValue = CGFloat.random(in: 0.12...0.4) * (Bool.random() ? 1 : -1)
        tilt.duration = duration
        tilt.timingFunction = CAMediaTimingFunction(name: .easeIn)
        tilt.fillMode = .forwards
        tilt.isRemovedOnCompletion = false
        falling.add(tilt, forKey: "tilt")

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak falling] in
            falling?.removeFromSuperlayer()
        }
    }

    /// The falling sprite: the captured screen, stencilled to the piece's
    /// silhouette. `.destinationIn` does the stencilling, which needs no guess
    /// about how CoreGraphics reads a clipping mask's polarity — the silhouette
    /// is simply drawn over the screen pixels and keeps what it covers.
    private static func chainsawPieceSprite(screenshot: CGImage, rect: CGRect,
                                            silhouette: CGImage, screen: CGSize) -> CGImage? {
        guard screen.width > 0 else { return nil }
        let scale = CGFloat(screenshot.width) / screen.width
        let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
        guard width > 0, height > 0 else { return nil }
        guard let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let full = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        // Draw the whole screenshot shifted so the piece's footprint lands on the
        // bitmap: the piece then carries the pixels that were actually under it.
        ctx.draw(screenshot, in: CGRect(x: -rect.minX * scale, y: -rect.minY * scale,
                                        width: CGFloat(screenshot.width),
                                        height: CGFloat(screenshot.height)))
        ctx.setBlendMode(.destinationIn)
        ctx.interpolationQuality = .none
        ctx.draw(silhouette, in: full)
        return ctx.makeImage()
    }

    private static func chainsawImage(rgba: [UInt8], width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0, rgba.count == width * height * 4 else { return nil }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        return CGImage(width: width, height: height,
                       bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    /// The built-in display in one call, no subprocess. Deprecated in macOS 14
    /// but still the only capture cheap enough to run *before* showing a cursor
    /// replacement; `captureBuiltInDisplay()`'s `screencapture` remains the
    /// fallback for the day it stops answering.
    private static func captureBuiltInDisplayFast() -> CGImage? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        let id: CGDirectDisplayID = displays.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
        return CGDisplayCreateImage(id)
    }

    // MARK: - Game Over overlay

    // 📺 Bumped by every game-over start AND by stopAllActiveEffects, so the
    // pending "now close the tube" hop below can tell whether the run it belongs
    // to is still the current one. It cannot ask activeEffects: the CRT is armed
    // for the exact deadline at which trackEffect drops the game-over layer, and
    // that cleanup is queued first, so by the time the arm runs the entry is
    // gone whether the run ended naturally or was cut short.
    private var _crtArmEpoch = 0

    // The overlay never plays its own sound — the tablet owns the audio
    // (59_game_over.mp3, routed). Per project principle: Mac overlays are silent.
    func showGameOver() {
        guard activeEffects["game-over"] == nil else { return }
        let bounds = hostLayer.bounds

        // Self-destruct time MUST match the sound the tablet actually plays
        // (59_game_over.mp3, ~1.6s) — NOT the legacy dying.mp3 (~4.6s) the
        // overlay no longer plays. This auto-cleanup is the authoritative
        // removal: the tablet's /sound/stopped → game-over/stop is best-effort
        // (skipped on preempt/network drop), so the overlay must clear itself in
        // sync with the sound regardless. Fallback stays short so a missing file
        // can't leave a long black screen.
        var duration: Double = 2.0
        if let soundURL = SoundManager.shared.soundURL(for: "59_game_over.mp3") {
            let asset = AVURLAsset(url: soundURL)
            let d = asset.duration
            if d.isNumeric, CMTimeGetSeconds(d) > 0 { duration = CMTimeGetSeconds(d) }
        }

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        // Outlives the sound by exactly the CRT close: the tube shuts OVER the
        // game-over screen as it is — static still boiling, picture still there —
        // and only once the black has met in the middle is there nothing left to
        // see. Dropping it when the shutters start would flash the bare desktop
        // through the closing gap, which is the opposite of a set switching off.
        trackEffect("game-over", layer: container,
                    duration: duration + CrtShutdown.closeDuration)

        // 📺 Backdrop: TV WHITE NOISE, not a flat wash. The tile is a set that
        // has lost its signal, and static is what that looks like — a 70% black
        // rectangle just dimmed the desktop and said nothing. Translucent
        // (TvStatic.defaultAlpha) so what is being demoed still reads through it,
        // animated (see TvStatic) so it boils instead of sitting there, and faded
        // in over TvStatic.fadeInDuration so the signal degrades into noise
        // instead of the screen cutting to it.
        if let staticLayer = TvStatic.makeLayer(in: bounds) {
            container.addSublayer(staticLayer)
        }

        // Game Over image centered — PNG with transparent background
        if let url = Bundle.module.url(forResource: "game-over", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            let imgW = bounds.width * 0.7
            let imgH = imgW * (img.size.height / img.size.width)
            let imgLayer = CALayer()
            imgLayer.frame = CGRect(x: (bounds.width - imgW) / 2,
                                    y: (bounds.height - imgH) / 2,
                                    width: imgW, height: imgH)
            imgLayer.contents = img
            imgLayer.contentsGravity = .resizeAspect
            container.addSublayer(imgLayer)
        }
        // No fade — and what ends it is the tube being switched off
        // (CrtShutdown), armed for the moment the sound ends. The CRT layer is
        // added to hostLayer AFTER this container, so it closes on top of a
        // game-over screen that is still running underneath it. The epoch is the guard: a
        // /effect/stop-all (which is what a preempting tile press and a
        // non-restartable re-tap both send) bumps it and this hop does nothing.
        // Note `game-over/stop` deliberately does NOT disarm it — that message
        // arrives from the client *because* the sound just ended, i.e. at exactly
        // the moment the tube is supposed to close.
        _crtArmEpoch &+= 1
        let crtEpoch = _crtArmEpoch
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self = self, self._crtArmEpoch == crtEpoch else { return }
            self.showCrtShutdown()
        }
    }

    // MARK: - 📺 CRT shutdown (the tail of game-over, and /test/crt-shutdown alone)

    /// Two black shutters close the screen from the top and bottom edges onto a
    /// white line, which then collapses sideways into a dot. The whole thing is
    /// built by `CrtShutdown` (see `CrtShutdown.swift` for the shape and the
    /// timings); here it only gets hung on the host layer and tracked, so it
    /// self-terminates at `CrtShutdown.totalDuration` and `stop-all` clears it
    /// like any other effect. Not a toggle: re-firing restarts it.
    func showCrtShutdown() {
        _ = cancelIfRunning("crt-shutdown")
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        guard let layer = CrtShutdown.makeLayer(in: hostLayer.bounds, scale: scale) else { return }
        hostLayer.addSublayer(layer)
        trackEffect("crt-shutdown", layer: layer, duration: CrtShutdown.totalDuration)
    }

    // MARK: - Fail overlay (a stamp from assetsDir, centered)

    func showFail(playSound: Bool = true) {
        guard activeEffects["fail"] == nil else { return }
        let bounds = hostLayer.bounds
        let duration: Double = 4.2

        // Licensed stock art, so it is not in the repo: drop it into assetsDir
        // and the effect wakes up. Absent, it does nothing rather than crash.
        guard let url = EffectsConfig.shared.assetURL("pngtree-fail-stamp-cleaned.png"),
              let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else {
            overlayInfo("showFail: no pngtree-fail-stamp-cleaned.png in \(EffectsConfig.shared.assetsDir.path)")
            return
        }

        let imgH = bounds.height * 1.0
        let imgW = imgH * (img.size.width / img.size.height)
        let imgLayer = CALayer()
        imgLayer.frame = CGRect(x: (bounds.width - imgW) / 2,
                                y: -bounds.height / 4 + bounds.height * 0.30,
                                width: imgW, height: imgH)
        imgLayer.contents = img
        imgLayer.contentsGravity = .resizeAspect
        hostLayer.addSublayer(imgLayer)
        trackEffect("fail", layer: imgLayer, duration: duration, sound: playSound ? "19_fail.mp3" : nil)
        if playSound { SoundManager.shared.play("19_fail.mp3") }

        // Zoom out from 1.3x to 1.0x over the first 0.5s
        let zoomOut = CABasicAnimation(keyPath: "transform.scale")
        zoomOut.fromValue = 1.3
        zoomOut.toValue = 1.0
        zoomOut.duration = 0.5
        zoomOut.fillMode = .forwards
        zoomOut.isRemovedOnCompletion = false
        imgLayer.add(zoomOut, forKey: "failZoom")

        // Fade out over the last 0.3s
        let fadeStart = max(0, duration - 0.3)
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + fadeStart
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "failFade")
    }

    // MARK: - Wazzup (sfx #69, 69_scream_ghost.mp3)

    /// 👅 The tongue-out Ghostface mask, sliding in from off-screen into the
    /// **bottom-left corner** and staying for the build-up plus the clip.
    ///
    /// Reworked 2026-09-16 at Victor's request: it used to pop in as a still and
    /// play alongside the scream immediately — he found that landed as a loud
    /// image, not a scare. Now the mask glides in (`wazzupSlideDuration`,
    /// `WazzupCorner.slideInStartFrame` → `frame`, ease-out so it settles rather
    /// than stops dead), holds still for `wazzupStillness`, and only THEN does
    /// the scream play — the silence after the slide is the scare, the sound is
    /// just the punctuation. The AUDIO is what is actually delayed (by
    /// `wazzupLeadIn` on the routed `/sound/play/69_scream_ghost.mp3` path, see
    /// `EffectsEngine.playSound`) rather than the visual, same mechanism and
    /// same reasoning as tile #22's `minigunAimLeadIn`: the number belongs to
    /// the animation's own timeline, not to the tablet-tunable
    /// `sound-timing.json`. Only the last 0.35 s fade at the very end, so it
    /// leaves with the sound instead of blinking out.
    ///
    /// Geometry (which corner, how big, where the slide starts) lives in
    /// `WazzupCorner` so it can be tested without a screen.
    func showWazzup(playSound: Bool = true) {
        if cancelIfRunning("wazzup", sound: playSound ? WazzupCorner.soundName : nil) { return }

        // Cut out from a stock mask sheet and mirrored, so it is not in the
        // repo: drop it into assetsDir and the effect wakes up. Absent, it logs
        // one line and does nothing rather than crash — the clip still plays.
        guard let url = EffectsConfig.shared.assetURL(WazzupCorner.assetName),
              let img = NSImage(contentsOf: url), img.size.width > 0, img.size.height > 0 else {
            overlayInfo("showWazzup: no \(WazzupCorner.assetName) in \(EffectsConfig.shared.assetsDir.path)")
            return
        }

        // Linger exactly as long as the ghost track; fall back to its measured length.
        var clipDuration = WazzupCorner.fallbackDuration
        if let soundURL = SoundManager.shared.soundURL(for: WazzupCorner.soundName) {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { clipDuration = CMTimeGetSeconds(d) }
        }
        // The mask is on screen for the build-up too, not just the clip — the
        // scream only starts once the slide has settled and the stillness has
        // run out (`wazzupLeadIn`), so the total lifetime must cover both or the
        // mask would vanish mid-scream (or linger long after it).
        let duration = Self.wazzupLeadIn + clipDuration

        let endBox = WazzupCorner.frame(imageSize: img.size, in: hostLayer.bounds)
        let startBox = WazzupCorner.slideInStartFrame(imageSize: img.size, in: hostLayer.bounds)
        let layer = CALayer()
        layer.frame = endBox  // model value is the RESTING frame; the animation below only presents the entrance
        layer.contents = img
        layer.contentsGravity = .resizeAspect
        hostLayer.addSublayer(layer)
        overlayInfo(String(format: "👅 wazzup: sliding into bottom-left, %.0f×%.0f, %.2fs slide + %.2fs stillness, then %.2fs scream",
                           endBox.width, endBox.height, Self.wazzupSlideDuration, Self.wazzupStillness, clipDuration))

        // Horizontal-only: same convention as the claude-peek slide-in
        // (`position.x`, not `frame`, which CALayer does not animate cleanly).
        // No fillMode override needed — the model value is already the resting
        // position, so removal-on-completion just stops presenting the
        // in-flight offset and reveals the (already correct) model.
        let slideIn = CABasicAnimation(keyPath: "position.x")
        slideIn.fromValue = layer.position.x - (endBox.minX - startBox.minX)
        slideIn.toValue = layer.position.x
        slideIn.duration = Self.wazzupSlideDuration
        slideIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(slideIn, forKey: "wazzupSlideIn")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + max(0, duration - 0.35)
        fadeOut.duration = 0.35
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "wazzupFade")

        // Only reached by a call this codebase never actually makes today (see
        // `wazzupLeadIn`'s doc) — kept delayed the same way for consistency, so
        // if a future caller ever passes playSound: true it still gets the
        // slide/beat/scream choreography instead of a scream over a mid-slide mask.
        if playSound {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.wazzupLeadIn) {
                SoundManager.shared.play(WazzupCorner.soundName)
            }
        }
        trackEffect("wazzup", layer: layer, duration: duration,
                    sound: playSound ? WazzupCorner.soundName : nil)
    }

    /// How long the mask takes to glide in from off-screen to its resting
    /// corner — long enough to read as a deliberate creep (compare the
    /// claude-peek mascot's snappy 0.45 s slide) without dragging the room's
    /// patience out past the point where the eventual scream stops landing.
    static let wazzupSlideDuration: Double = 0.8

    /// Dead air after the slide settles and before the scream. This is the
    /// whole point of the rework — Victor, verbatim: "după ce face slide, să
    /// mai stai jumătate de secundă, până dai play la efect. Pentru că e foarte
    /// scary efectul respectiv." The silence sells the scare; without it the
    /// scream just overlaps a still-moving image and reads as noise, not a jump.
    static let wazzupStillness: Double = 0.5

    /// Total head start the visual has on the audio: slide + stillness. This is
    /// what actually delays the scream (see `EffectsEngine.playSound`'s
    /// `69_scream_ghost.mp3` case, which passes it as `lead` to
    /// `SoundManager.playTabletSound`) — the mask itself starts sliding
    /// immediately on press, same as it always has.
    static let wazzupLeadIn: Double = wazzupSlideDuration + wazzupStillness

    // MARK: - Blood drip overlay (sfx #40, 40_joker.mp3)

    /// Blood band pinned to the TOP of the screen at full width, drips hanging
    /// down with droplets falling onto the (transparent) live screen below.
    /// The source loop (~1.6s) plays ~1.5x slower and repeats for the joker
    /// sound's duration, fading in at the head and out at the tail.
    func showBloodDrip(playSound: Bool = true) {
        if cancelIfRunning("blood-drip", sound: playSound ? "40_joker.mp3" : nil) { return }

        guard let url = Bundle.module.url(forResource: "blood-drip", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("blood-drip.gif not found")
            return
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var sourceDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif  = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
            sourceDuration += delay
        }
        guard !images.isEmpty, sourceDuration > 0 else { return }

        // Linger exactly as long as the joker track; fall back to its measured 9.0s.
        var duration: Double = 9.0
        if let soundURL = SoundManager.shared.soundURL(for: "40_joker.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        let bounds = hostLayer.bounds
        // Full screen width; height stretched to ~1.8× the screen so the blood —
        // whose dense band/drips only occupy the upper third of the source art —
        // runs much further down and the falling droplets reach the BOTTOM. Pinned
        // to the TOP edge (y = 0 is the bottom here), so the extra height thickens
        // the band/drips up top and pushes the lowest droplets off the bottom edge.
        let layerW = bounds.width
        // 1.8 was the stretch that pushed the lowest droplets off the bottom;
        // ×0.7 (2026-09-09) pulls the whole curtain back up so it reads as a band
        // hanging from the top rather than a full-screen wash. The top-edge anchor
        // below means the shrink comes off the BOTTOM — the band stays glued up.
        let layerH = bounds.height * 1.8 * 0.7
        let gifLayer = CALayer()
        // Pivot at the TOP edge so the vertical-scale reveal grows DOWNWARD from
        // the top of the screen (anchorPoint y=1 = top edge in this non-flipped
        // layer). Set before .frame so position is derived from this anchor.
        gifLayer.anchorPoint = CGPoint(x: 0.5, y: 1.0)
        gifLayer.frame = CGRect(x: 0, y: bounds.height - layerH, width: layerW, height: layerH)
        gifLayer.contentsGravity = .resize
        if let first = images.first { gifLayer.contents = first }
        hostLayer.addSublayer(gifLayer)

        // ~1.5x slower than the source loop ("slow it down a bit"), repeating.
        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = sourceDuration * 1.5
        anim.repeatCount = .infinity
        gifLayer.add(anim, forKey: "bloodFrames")

        // Reveal: scale vertically from 0 → full height over 1.5s so the blood
        // appears to grow downward from the top of the screen (the contents keep
        // dripping while it unfurls). Settles at the layer's model scale of 1.
        let grow = CABasicAnimation(keyPath: "transform.scale.y")
        grow.fromValue = 0.0
        grow.toValue = 1.0
        grow.duration = 1.5
        grow.timingFunction = CAMediaTimingFunction(name: .easeOut)
        gifLayer.add(grow, forKey: "bloodGrow")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + max(0, duration - 0.6)
        fadeOut.duration = 0.6
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        gifLayer.add(fadeOut, forKey: "bloodFadeOut")

        if playSound { SoundManager.shared.play("40_joker.mp3") }
        trackEffect("blood-drip", layer: gifLayer, duration: duration, sound: playSound ? "40_joker.mp3" : nil)
    }

    // MARK: - Phoenix overlay (🔥 fire-phoenix, menu-triggered)

    /// A fiery phoenix that *rises up from the bottom of the screen* in the
    /// rhythm of its own wing beats and settles in the upper-middle, paired with
    /// the phoenix cry (`phoenix.mp3`, a Mac-owned resource — the tablet's
    /// `34_phoenix.mp3` stays silent). The cry plays for the **whole** animation
    /// and fades out **in unison** with the visual fade (same tail window), via
    /// `playClip(seconds: totalLife, fade: fadeOutDur)`. The source art is a
    /// black-background GIF whose
    /// flames were keyed to transparency via luminance→alpha (bright fire opaque,
    /// dark glow fading smoothly out), **cropped tight to the changing-pixel
    /// bounding box** (so the asset is the flame and nothing else), and shipped as
    /// a transparent multi-frame APNG (`phoenix.png`); a GIF would 1-bit-quantize
    /// the alpha and bring the black halo back. Frames load through the same
    /// `CGImageSource` path as the other gif effects.
    /// Decode the bundled transparent phoenix APNG into its frames. Static +
    /// internal so a headless test can assert the asset bundles and decodes
    /// (28 transparent 226×340 frames) without firing the on-screen effect.
    static func loadPhoenixFrames() -> [CGImage] {
        guard let url = Bundle.module.url(forResource: "phoenix", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("phoenix.png not found")
            return []
        }
        let count = CGImageSourceGetCount(source)
        var images: [CGImage] = []
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) { images.append(cg) }
        }
        return images
    }

    // Animation tunables, hoisted out of showPhoenix so the on-screen life can be
    // known WITHOUT firing the effect (see phoenixDuration).
    private static let phoenixFrameDt = 0.05    // one source frame
    private static let phoenixBeats = 3         // wing beats spent rising
    private static let phoenixHoldAtTop = 3.0   // hover-and-flap once arrived
    private static let phoenixFadeOutDur = 1.4  // dissolve (visual + cry, in unison)

    /// Frame count of the bundled APNG, read without decoding any pixels.
    private static let phoenixFrameCount: Int = {
        guard let url = Bundle.module.url(forResource: "phoenix", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 28 }
        return CGImageSourceGetCount(source)
    }()

    /// How long the phoenix lives on screen, and — mirrored by AppDelegate's
    /// onSoundPlay `durationMs` — how long the tablet keeps tile #34 in its
    /// "playing" state, i.e. the window during which a re-tap STOPS it. Tile #34
    /// carries no ↻ restartable badge, so this number IS the stop contract: the
    /// branch used to answer a token 1ms (the tablet's `34_phoenix.mp3` is a silent
    /// placeholder — nothing to time), which cleared the playing state instantly
    /// and turned every re-tap into a restart instead of a stop.
    static let phoenixDuration: Double =
        Double(phoenixFrameCount) * phoenixFrameDt * Double(phoenixBeats)
        + phoenixHoldAtTop + phoenixFadeOutDur

    func showPhoenix() {
        // Re-press cancels: tear down the visual AND silence the cry. The sound
        // rides playClip's overlapping player (not the `players` dict cancelIfRunning
        // touches), so stop it explicitly here.
        if cancelIfRunning("phoenix") {
            SoundManager.shared.stopOverlapping("phoenix.mp3", fade: SoundManager.interruptFade)
            return
        }

        let images = Self.loadPhoenixFrames()
        guard !images.isEmpty else { return }

        let bounds = hostLayer.bounds
        let H = bounds.height
        let W = bounds.width

        // --- Tunables -------------------------------------------------------
        // Asset is cropped tight to the flame AND vertically registered — every
        // frame's flame is centred in the 226×340 sprite, so the bird doesn't
        // slide up/down inside the layer as it flaps; only the wings/shape
        // animate. That makes the hover position exact. hostLayer is
        // bottom-origin (y grows upward). Size is 2× the original on-screen
        // footprint, per request (the original drew the flame at ~0.46·H tall).
        let assetAspect: CGFloat = 226.0 / 340.0
        let originalFlameFrac: CGFloat = 0.46      // pre-change on-screen height
        let sizeMultiplier: CGFloat = 2.0          // "2x size"
        // Horizontal stretch: make the bird 30% wider on the X axis without
        // touching its height. We widen the layer bounds by 1.3× and use a
        // fill-both contentsGravity (.resize) below so the sprite actually
        // stretches to fill the wider box (rather than .resizeAspect, which
        // would preserve aspect and just letterbox the extra width).
        let stretchX: CGFloat = 1.30
        let flameHeight = min(H * 0.96, H * originalFlameFrac * sizeMultiplier)
        let flameWidth = flameHeight * assetAspect * stretchX
        let centerX = W * 0.5
        // The flame is centred in its sprite, so the layer centre IS the flame
        // body. It settles with that body at ~40% from the top — the upper-centre
        // zone the user marked (head/wings reach up toward the X at ~30%; with a
        // 2× flame the tallest tips just kiss the top edge).
        let flameCenterFromTop: CGFloat = 0.40
        // Settle 100px lower than the framed position (hostLayer is bottom-origin,
        // so "lower on screen" = smaller y).
        let stopCenterY = H * (1.0 - flameCenterFromTop) - 100
        // Start well below the bottom edge so the bird enters from low down and
        // climbs the full screen into view.
        let startCenterY = -flameHeight * 0.80

        let layer = CALayer()
        layer.bounds = CGRect(x: 0, y: 0, width: flameWidth, height: flameHeight)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.position = CGPoint(x: centerX, y: stopCenterY)   // model = settle point
        layer.contentsGravity = .resize   // fill both axes → real horizontal stretch
        layer.contents = images.first
        hostLayer.addSublayer(layer)

        // Loop the 28 source frames (~0.05s each → ~1.4s/cycle) — one full wing
        // beat per cycle. Discrete so frames switch crisply (no cross-fade).
        let frameDt = Self.phoenixFrameDt
        let cycleDur = Double(images.count) * frameDt
        let framesAnim = CAKeyframeAnimation(keyPath: "contents")
        framesAnim.values = images
        framesAnim.duration = cycleDur
        framesAnim.calculationMode = .discrete
        framesAnim.repeatCount = .infinity
        layer.add(framesAnim, forKey: "phoenixFrames")

        // --- Rise synced to the wing beat -----------------------------------
        // The flame gathers low & wide (downbeat) then launches tall & upward
        // each cycle. We drive the whole bird up in one strong surge per cycle,
        // timed to that launch sub-phase (frames ~8→24 of each loop), holding
        // (gliding) between beats. The per-beat distance decreases so it decel-
        // erates into a hover at the settle point.
        let beats = Self.phoenixBeats
        let riseDur = cycleDur * Double(beats)
        let riseDist = stopCenterY - startCenterY
        let surgeStartFrac = 0.30   // within a cycle: launch begins (~frame 8/28)
        let surgeEndFrac = 0.88     // launch ends (~frame 24/28)
        let cum: [CGFloat] = [0.0, 0.52, 0.83, 1.0]   // cumulative rise per beat
        // Soften the per-wing-beat OY bob by 20%: instead of gliding dead-flat
        // and then surging the whole beat's travel in one punch, let the glide
        // ease up 20% of the beat first, so the surge only covers the remaining
        // 80%. Same beat checkpoints & total rise — just a 20% gentler up-down.
        let beatBobReduce: CGFloat = 0.20

        func point(_ d: CGFloat) -> NSValue {
            NSValue(point: CGPoint(x: centerX, y: startCenterY + riseDist * d))
        }
        let linear = CAMediaTimingFunction(name: .linear)
        let surge = CAMediaTimingFunction(name: .easeOut)   // snappy launch, then glide

        var keyTimes: [NSNumber] = [0.0]
        var values: [NSValue] = [point(cum[0])]
        var tfs: [CAMediaTimingFunction] = []
        let span = 1.0 / Double(beats)
        for k in 0..<beats {
            let base = Double(k) * span
            // glide up the first 20% of this beat's travel (was a flat hold),
            // shrinking the punchy surge that follows
            let glideTo = cum[k] + beatBobReduce * (cum[k + 1] - cum[k])
            keyTimes.append(NSNumber(value: base + surgeStartFrac * span))
            values.append(point(glideTo))
            tfs.append(linear)
            // launch up to the next cumulative height
            keyTimes.append(NSNumber(value: base + surgeEndFrac * span))
            values.append(point(cum[k + 1]))
            tfs.append(surge)
        }
        keyTimes.append(1.0); values.append(point(cum[beats])); tfs.append(linear)

        let rise = CAKeyframeAnimation(keyPath: "position")
        rise.keyTimes = keyTimes
        rise.values = values
        rise.timingFunctions = tfs
        rise.calculationMode = .linear
        rise.duration = riseDur
        rise.fillMode = .forwards
        rise.isRemovedOnCompletion = false
        layer.add(rise, forKey: "phoenixRise")

        // After arriving, hover-and-flap in place for ~3s before leaving, THEN
        // fade out (the fade follows the hover — it must not eat into it).
        let holdAtTop = Self.phoenixHoldAtTop
        // Fade-out is 2× the original 0.7s — a slower, gentler dissolve. It
        // drives BOTH the visual opacity fade and the audio fade (playClip
        // below uses fadeOutDur), so they stay in unison at the longer length.
        let fadeOutDur = Self.phoenixFadeOutDur
        let totalLife = riseDur + holdAtTop + fadeOutDur

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = 1.0
        fadeIn.duration = 0.4
        layer.add(fadeIn, forKey: "phoenixFadeIn")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.beginTime = CACurrentMediaTime() + (riseDur + holdAtTop)
        fadeOut.duration = fadeOutDur
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "phoenixFadeOut")

        // The phoenix cry plays for the WHOLE animation and fades the audio out
        // in unison with the visual fade: playClip's fade starts at
        // `totalLife - fadeOutDur` (== riseDur + holdAtTop, the visual fade's
        // begin time) and lasts `fadeOutDur` — same window, same length. The
        // 63s source is clipped to the animation's life; on early cancel
        // (re-press) the overlapping player is stopped above. Played at 56%:
        // the raw cry was too loud at full volume, 0.7 was still too loud in
        // the room, and 2026-09-09 took another 20% off it (0.7 × 0.8).
        SoundManager.shared.playClip("phoenix.mp3", seconds: totalLife, fade: fadeOutDur, volume: 0.56)

        trackEffect("phoenix", layer: layer, duration: totalLife)
    }

    /// Random green/black speckle frames for the sonar's "reception noise" —
    /// sparse bright-green specks + dark dropouts on a clear field, premultiplied.
    private static func makeSonarNoiseFrames(count: Int, size: Int) -> [CGImage] {
        var frames: [CGImage] = []
        let cs = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = size * 4
        for _ in 0..<count {
            guard let ctx = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: cs,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let buf = ctx.data else { continue }
            let p = buf.bindMemory(to: UInt8.self, capacity: size * size * 4)
            for idx in 0..<(size * size) {
                let r = Double.random(in: 0...1)
                let o = idx * 4
                if r > 0.62 {                       // bright green speck
                    let a = (r - 0.62) / 0.38 * 255.0
                    p[o] = UInt8(0.40 * a); p[o + 1] = UInt8(a); p[o + 2] = UInt8(0.55 * a); p[o + 3] = UInt8(a)
                } else if r < 0.20 {                // dark dropout
                    let a = (0.20 - r) / 0.20 * 220.0
                    p[o] = 0; p[o + 1] = 0; p[o + 2] = 0; p[o + 3] = UInt8(a)
                } else {                            // clear
                    p[o] = 0; p[o + 1] = 0; p[o + 2] = 0; p[o + 3] = 0
                }
            }
            if let img = ctx.makeImage() { frames.append(img) }
        }
        return frames
    }

    // MARK: - Sonar radar sweep (sfx #23, 23_radar.mp3)

    /// A black 30%-opacity wash fades in over 1s, THEN a phosphor-green radar
    /// appears on it: concentric rings + a radial grid + a sweep line that
    /// rotates clockwise trailing a comet tail with a green glow. One-shot —
    /// runs ~6s (matching 23_radar.mp3 ~5.5s) then fades out and is removed.
    /// Drawn entirely as CALayers/CAShapeLayers on the overlay's hostLayer.
    func showSonar(playSound: Bool = true) {
        let soundKey: String? = playSound ? "23_radar.mp3" : nil
        if cancelIfRunning("sonar", sound: soundKey) { return }

        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        let green = NSColor(red: 0.10, green: 1.0, blue: 0.30, alpha: 1.0).cgColor
        let gridGrey = NSColor(white: 0.5, alpha: 1.0).cgColor   // muted grey radar lines

        let fadeIn: Double = 1.0       // black overlay fade-in duration
        let fadeOut: Double = 0.6
        let sectorFrac: Double = 0.32  // visible sweep sector width, as a fraction of a full turn

        // --- Detection timing: ~0.5s beep-free lead-in, then the front sweeps
        //     over the 💩 on three radar beeps in 23_radar.mp3. The effect ENDS
        //     (fully faded, while still rotating) the moment the 3rd detection's
        //     1s fade finishes — < one interval after det3, so the front never
        //     sweeps over the 💩 a 4th time unshown. ---
        let sweepStartRel = fadeIn * 0.9               // when the sweep appears (rel. to effect start)
        let leadIn = 0.5                               // beep-free rotation before the first detection
        let beepClip = [0.104, 2.211, 3.879]           // detection beep times within the clip
        let soundStartRel = sweepStartRel + leadIn - beepClip[0]
        let detT = beepClip.map { $0 + soundStartRel - sweepStartRel }   // detections, rel. to sweepStart
        let i1 = detT[1] - detT[0]
        let i2 = detT[2] - detT[1]
        let animEnd = detT[2] + sectorFrac * i2 + 1.0  // end when the last 💩 flash's 1s fade completes
        let active = sweepStartRel + animEnd - fadeOut // fade-out starts here (rotation still going)
        let total  = sweepStartRel + animEnd           // full removal

        // On Bluetooth output the radar audio is played `btComp` later than
        // "now" (to warm the A2DP link while a power-saving speaker spins up),
        // so shift the ENTIRE visual timeline by the same amount — otherwise the
        // three 💩 detections would flash ~btComp (0.55s) BEFORE their beeps
        // (the desync seen when broadcasting to a Bluetooth speaker). On
        // wired/built-in output btComp = 0 and nothing moves. `clock0` is the
        // (possibly delayed) effect start on the CoreAnimation clock; every
        // begin-time below hangs off it.
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0
        let clock0 = CACurrentMediaTime() + btComp

        // Everything lives under one container so the end fade-out is a single op.
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // 1) Black backdrop — fades 0 → 0.45 opacity over 1s (darker outside the
        //    circle; inside is darker still under the 70% disc).
        let backdrop = CALayer()
        backdrop.frame = bounds
        backdrop.backgroundColor = NSColor.black.cgColor
        backdrop.opacity = 0.45
        let backdropFade = CABasicAnimation(keyPath: "opacity")
        backdropFade.fromValue = 0.0
        backdropFade.toValue = 0.45
        backdropFade.duration = fadeIn
        backdropFade.beginTime = clock0
        backdropFade.fillMode = .backwards   // stay invisible until the (BT-shifted) start
        backdrop.add(backdropFade, forKey: "backdropFadeIn")
        container.addSublayer(backdrop)

        // Radar geometry: centered, radius ~42% of the smaller screen side.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) * 0.42

        // 2) Static radar grid (rings + radial spokes + center dot). Fades in
        //    AFTER the backdrop so the sonar "appears" on the dark wash.
        let grid = CALayer()
        grid.frame = bounds
        grid.opacity = 1.0

        // Black disc filling the radar circle — black at 70% opacity (under the
        // grid lines), a darker background inside the circle than the 30% wash.
        let disc = CAShapeLayer()
        disc.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        disc.fillColor = NSColor(white: 0.0, alpha: 0.7).cgColor
        grid.addSublayer(disc)

        let ringsPath = CGMutablePath()
        let ringCount = 4
        for i in 1...ringCount {
            let r = radius * CGFloat(i) / CGFloat(ringCount)
            ringsPath.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
        }
        let rings = CAShapeLayer()
        rings.path = ringsPath
        rings.fillColor = NSColor.clear.cgColor
        rings.strokeColor = gridGrey
        rings.opacity = 0.7
        rings.lineWidth = 3.0
        rings.contentsScale = scale
        grid.addSublayer(rings)

        let outer = CAShapeLayer()
        outer.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
        outer.fillColor = NSColor.clear.cgColor
        outer.strokeColor = gridGrey
        outer.opacity = 0.85
        outer.lineWidth = 4.0
        outer.contentsScale = scale
        grid.addSublayer(outer)

        let spokesPath = CGMutablePath()
        var ang: CGFloat = 0
        while ang < .pi * 2 - 0.001 {
            spokesPath.move(to: center)
            spokesPath.addLine(to: CGPoint(x: center.x + radius * cos(ang), y: center.y + radius * sin(ang)))
            ang += .pi / 6   // every 30°
        }
        let spokes = CAShapeLayer()
        spokes.path = spokesPath
        spokes.strokeColor = gridGrey
        spokes.opacity = 0.5
        spokes.lineWidth = 2.0
        spokes.contentsScale = scale
        grid.addSublayer(spokes)

        let dotR: CGFloat = 4
        let dot = CAShapeLayer()
        dot.path = CGPath(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR, width: 2 * dotR, height: 2 * dotR), transform: nil)
        dot.fillColor = green
        dot.contentsScale = scale
        grid.addSublayer(dot)

        let gridFade = CABasicAnimation(keyPath: "opacity")
        gridFade.fromValue = 0.0
        gridFade.toValue = 1.0
        gridFade.beginTime = clock0 + fadeIn * 0.6
        gridFade.duration = 0.6
        gridFade.fillMode = .both
        grid.add(gridFade, forKey: "gridFadeIn")
        container.addSublayer(grid)

        // Faint "background reception noise" flickering inside the radar circle —
        // the sonar screen is never perfectly black.
        let bgNoiseFrames = Self.makeSonarNoiseFrames(count: 10, size: 240)
        if let firstBg = bgNoiseFrames.first {
            let bgNoise = CALayer()
            bgNoise.frame = bounds
            bgNoise.contents = firstBg
            bgNoise.contentsGravity = .resize
            bgNoise.opacity = 0.16
            let bgMask = CAShapeLayer()
            bgMask.path = CGPath(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), transform: nil)
            bgMask.fillColor = NSColor.black.cgColor
            bgNoise.mask = bgMask
            let bgFade = CABasicAnimation(keyPath: "opacity")
            bgFade.fromValue = 0.0
            bgFade.toValue = 0.16
            bgFade.duration = fadeIn
            bgFade.beginTime = clock0
            bgFade.fillMode = .backwards   // stay invisible until the (BT-shifted) start
            bgNoise.add(bgFade, forKey: "bgNoiseFadeIn")
            let bgFlick = CAKeyframeAnimation(keyPath: "contents")
            bgFlick.values = bgNoiseFrames
            bgFlick.calculationMode = .discrete
            bgFlick.duration = 0.7
            bgFlick.repeatCount = .infinity
            bgNoise.add(bgFlick, forKey: "bgNoiseFlicker")
            container.addSublayer(bgNoise)
        }

        // 3) Rotating sweep: a conic-gradient arc that fades from a bright
        //    leading edge to transparent over ~90° → the classic radar comet
        //    tail. Masked to the radar circle; spins about the screen center.
        let sweepSide = radius * 2
        let sweep = CAGradientLayer()
        sweep.type = .conic
        sweep.frame = CGRect(x: center.x - radius, y: center.y - radius, width: sweepSide, height: sweepSide)
        sweep.opacity = 1.0
        sweep.startPoint = CGPoint(x: 0.5, y: 0.5) // cone center
        sweep.endPoint = CGPoint(x: 1.0, y: 0.5)   // location-0 points +x (the bright leading edge)
        let sweepBright = NSColor(red: 0.30, green: 1.0, blue: 0.45, alpha: 0.9).cgColor
        let sweepClear  = NSColor(red: 0.10, green: 1.0, blue: 0.30, alpha: 0.0).cgColor
        // Front of attack = the bright +x leading edge at full opacity; the
        // gradient then fades 100% → 0% BEHIND it as the sweep rotates clockwise.
        sweep.colors    = [sweepBright, sweepClear, NSColor.clear.cgColor, NSColor.clear.cgColor]
        sweep.locations = [0.0, NSNumber(value: sectorFrac), NSNumber(value: sectorFrac), 1.0]

        // Clip the square gradient to the radar circle.
        let sweepMask = CAShapeLayer()
        sweepMask.path = CGPath(ellipseIn: sweep.bounds, transform: nil)
        sweepMask.fillColor = NSColor.black.cgColor
        sweep.mask = sweepMask

        // Crisp bright leading edge (local +x) with a green glow.
        let localCenter = CGPoint(x: radius, y: radius)
        let lead = CAShapeLayer()
        let leadPath = CGMutablePath()
        leadPath.move(to: localCenter)
        leadPath.addLine(to: CGPoint(x: localCenter.x + radius, y: localCenter.y))
        lead.path = leadPath
        lead.strokeColor = green
        lead.lineWidth = 2.0
        lead.lineCap = .round
        lead.contentsScale = scale
        lead.shadowColor = green
        lead.shadowRadius = 8
        lead.shadowOpacity = 0.9
        lead.shadowOffset = .zero
        sweep.addSublayer(lead)

        // Ultrasound-style "reception noise": flickering green/black speckle over
        // the wedge — imperfect sonar reception, not crisp pixels. Masked by a
        // copy of the gradient so it fades with the signal, and it rides the spin.
        let noiseFrames = Self.makeSonarNoiseFrames(count: 10, size: 240)
        if let firstNoise = noiseFrames.first {
            let noise = CALayer()
            noise.frame = sweep.bounds
            noise.contents = firstNoise
            noise.contentsGravity = .resize
            noise.opacity = 0.95
            let noiseMask = CAGradientLayer()
            noiseMask.type = .conic
            noiseMask.frame = sweep.bounds
            noiseMask.startPoint = CGPoint(x: 0.5, y: 0.5)
            noiseMask.endPoint = CGPoint(x: 1.0, y: 0.5)
            noiseMask.colors = [sweepBright, sweepClear, NSColor.clear.cgColor, NSColor.clear.cgColor]
            noiseMask.locations = [0.0, NSNumber(value: sectorFrac), NSNumber(value: sectorFrac), 1.0]
            noise.mask = noiseMask
            let flick = CAKeyframeAnimation(keyPath: "contents")
            flick.values = noiseFrames
            flick.calculationMode = .discrete
            flick.duration = 0.6
            flick.repeatCount = .infinity
            noise.add(flick, forKey: "noiseFlicker")
            sweep.addSublayer(noise)
        }

        let sweepStart = clock0 + fadeIn * 0.9
        let sweepFade = CABasicAnimation(keyPath: "opacity")
        sweepFade.fromValue = 0.0
        sweepFade.toValue = 1.0
        sweepFade.beginTime = sweepStart
        sweepFade.duration = 0.4
        sweepFade.fillMode = .both
        sweep.add(sweepFade, forKey: "sweepFadeIn")

        // 3a) Keyframed clockwise rotation (negative z): one full turn between
        //     detections so the front lands on the 💩 exactly on each beep.
        //     Lead-in and interval 1 share a speed so the lead-in looks continuous.
        let blipAngle: CGFloat = 0.6                    // 💩 world angle (y-up); front is here at each detection
        let phi = Double(blipAngle)
        let speed1 = 2 * Double.pi / i1
        let speed2 = 2 * Double.pi / i2
        let rotKeyT: [Double] = [0, detT[0], detT[1], detT[2], animEnd]
        let rotVal: [Double] = [
            phi + speed1 * detT[0],                     // lead-in start → rotates down to phi by detT[0]
            phi,                                        // detection 1
            phi - 2 * Double.pi,                        // detection 2 (one CW turn later)
            phi - 4 * Double.pi,                        // detection 3
            phi - 4 * Double.pi - speed2 * (animEnd - detT[2]),  // keep spinning to the end
        ]
        let spin = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        spin.keyTimes = rotKeyT.map { NSNumber(value: $0 / animEnd) }
        spin.values = rotVal
        spin.calculationMode = .linear
        spin.duration = animEnd
        spin.beginTime = sweepStart
        spin.fillMode = .both
        spin.isRemovedOnCompletion = false
        sweep.add(spin, forKey: "sweepSpin")
        container.addSublayer(sweep)

        // 3b) The 💩 the radar "finds": fixed on the map at the front's detection
        //     angle, flashing each time the front sweeps over it.
        let blipRadius = radius * 0.62
        let blipPos = CGPoint(x: center.x + blipRadius * cos(blipAngle),
                              y: center.y + blipRadius * sin(blipAngle))
        let blipSize: CGFloat = 144               // 3× the original 48
        let blip = CATextLayer()
        blip.string = "💩"
        blip.fontSize = blipSize * 0.8
        blip.alignmentMode = .center
        blip.frame = CGRect(x: blipPos.x - blipSize / 2, y: blipPos.y - blipSize / 2, width: blipSize, height: blipSize)
        blip.contentsScale = scale
        // Green glow behind the 💩 so it reads clearly (fades with the layer opacity).
        blip.shadowColor = NSColor(red: 0.20, green: 1.0, blue: 0.35, alpha: 1.0).cgColor
        blip.shadowRadius = 16
        blip.shadowOpacity = 1.0
        blip.shadowOffset = .zero
        blip.masksToBounds = false
        blip.opacity = 0
        // ABOVE the sweep. It used to sit below it, so the green front and its
        // reception noise washed over the find at the exact instant the find
        // happens — which is the one moment it must be unmistakable. The wedge
        // passing behind it now reads as the thing that revealed it.
        container.addSublayer(blip)

        // Blip lifecycle: invisible until a detection, then FULLY lit while the
        // sector passes over it, then a 1s fade-out. Three detections, each
        // phase-locked to the rotation above (and thus to the beeps).
        let coverT = [sectorFrac * i1, sectorFrac * i2, sectorFrac * i2]   // sector-pass time per detection
        let fadeT = 1.0
        var blipKeyTimes: [NSNumber] = []
        var blipValues: [NSNumber] = []
        let blipSamples = 240
        for k in 0...blipSamples {
            let tau = Double(k) / Double(blipSamples) * animEnd
            var v = 0.0
            for di in 0..<3 {
                let x = tau - detT[di]
                if x < 0 { continue }
                if x <= coverT[di] {
                    v = max(v, 1.0)                  // sector still passing over it → fully lit
                } else if x <= coverT[di] + fadeT {
                    v = max(v, 1.0 - (x - coverT[di]) / fadeT)   // 1s fade-out
                }
            }
            blipKeyTimes.append(NSNumber(value: tau / animEnd))
            blipValues.append(NSNumber(value: v))
        }
        let blipFlash = CAKeyframeAnimation(keyPath: "opacity")
        blipFlash.keyTimes = blipKeyTimes
        blipFlash.values = blipValues
        blipFlash.calculationMode = .linear
        blipFlash.duration = animEnd
        blipFlash.beginTime = sweepStart
        blipFlash.fillMode = .both
        blipFlash.isRemovedOnCompletion = false
        blip.add(blipFlash, forKey: "blipFlash")

        // Each detection ZOOMS the 💩 in: it lands at 2× and settles to its own
        // size over 1s, easing out so the motion is spent in the first third —
        // it arrives, it doesn't creep. Sampled on the SAME grid as the flash
        // above and off the SAME `detT[di]`, so the zoom starts on the exact
        // frame the find becomes visible; drifting the two apart would show the
        // 💩 already shrinking as it appears.
        //
        // Between detections the scale is parked back at 2× ready for the next
        // one. That reset is deliberately placed *after* the fade has fully
        // finished (`coverT + fadeT`), so the jump from 1× back to 2× always
        // happens while the layer is at zero opacity and can never be seen.
        let zoomT = 1.0
        var blipScale: [NSNumber] = []
        for k in 0...blipSamples {
            let tau = Double(k) / Double(blipSamples) * animEnd
            var s = 2.0
            for di in 0..<3 {
                let x = tau - detT[di]
                if x < 0 || x > coverT[di] + fadeT { continue }
                let u = min(1.0, x / zoomT)
                s = 1.0 + pow(1.0 - u, 3)          // 2 → 1, cubic ease-out
            }
            blipScale.append(NSNumber(value: s))
        }
        let blipZoom = CAKeyframeAnimation(keyPath: "transform.scale")
        blipZoom.keyTimes = blipKeyTimes
        blipZoom.values = blipScale
        blipZoom.calculationMode = .linear
        blipZoom.duration = animEnd
        blipZoom.beginTime = sweepStart
        blipZoom.fillMode = .both
        blipZoom.isRemovedOnCompletion = false
        blip.add(blipZoom, forKey: "blipZoom")

        // 4) End: fade the whole container out, then trackEffect removes it.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.beginTime = clock0 + active
        fade.duration = fadeOut
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "sonarFadeOut")

        // Play the radar SFX (when this path owns the audio), delayed by
        // `soundStartRel` so its three detection beeps land on the three 💩
        // detections (first ~0.5s stays beep-free rotation). The extra +0.1s
        // nudges the whole soundtrack slightly behind the visuals. On Bluetooth
        // output the play is pushed a further `btComp` — matching the visual
        // shift above — and an inaudible wake tone runs for the WHOLE lead-in so
        // a power-saving speaker is fully awake before the first beep. (A BT amp
        // can take ~1s to leave power-saving; warming only ~0.5s ahead — as the
        // generic path does — would still clip the leading beep.)
        if playSound {
            let soundAt = soundStartRel + 0.1 + btComp
            if btComp > 0 { BluetoothOutput.playWakeTone(seconds: soundAt + 0.05) }
            DispatchQueue.main.asyncAfter(deadline: .now() + soundAt) { [weak self, weak container] in
                guard let self = self, let container = container,
                      self.activeEffects["sonar"] === container else { return }   // dropped/retriggered
                // btComp is already baked into `soundAt` (and the visual shift),
                // so bypass SoundManager's own BT compensation — otherwise the
                // audio would be delayed 2×btComp and lag the visuals again.
                SoundManager.shared.play("23_radar.mp3", bluetoothCompensated: false)
            }
        }
        trackEffect("sonar", layer: container, duration: btComp + total, sound: soundKey)
    }

    /// 💓 The screen beats around the cursor. Returns the routed sound's length
    /// (0 when it plays none) so `onSoundPlay` can answer the tablet with it.
    ///
    /// **The Mac plays the clip itself, from this same call.** It used to arrive
    /// as a press→`SoundEffectMap` visual while a *second* HTTP request started
    /// the audio, and the pulse clock then started from whenever the async
    /// `screencapture` happened to finish — so every zoom landed a few hundred ms
    /// behind its thump, by a margin that changed from press to press. Sound and
    /// visual now hang off one instant (`clock0`), the way the radar and the
    /// microwave already did.
    @discardableResult
    func showHeartbeat(playSound: Bool = false, volume: Float? = nil) -> TimeInterval {
        // A press PREEMPTS a running heartbeat rather than being swallowed by it.
        // The old guard debounced a second tap while the screencapture subprocess
        // was still in flight, but now that the same call also starts the audio,
        // being swallowed would answer the tablet with "no sound" and send it back
        // to local playback. Restarting is also what `playTabletSound` does to the
        // audio anyway, so the two halves agree. The dropped container leaves
        // `activeEffects`, so its in-flight capture completion sees the identity
        // check fail and discards itself.
        _ = cancelIfRunning("heartbeat")
        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 0 }

        let beats = Self.loadHeartbeatBeats()
        guard beats.count >= 2 else {
            overlayInfo("showHeartbeat: need at least one lub-dub pair in heartbeat_beats.json")
            return 0
        }

        // Start the audio FIRST and stamp the clock every pulse hangs off, before
        // anything slow (the capture) runs. On Bluetooth output `playTabletSound`
        // prepends `btComp` of warm-up silence, so the audio really starts that
        // much later and the whole visual timeline shifts with it — same bargain
        // as the microwave. Zero on wired/built-in output.
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0
        var soundDuration: TimeInterval = 0
        if playSound {
            soundDuration = SoundManager.shared.playTabletSound("13_heartbeat.mp3", volume: volume) ?? 0
        }
        let clock0 = CACurrentMediaTime() + btComp

        let lastBeat = beats.last ?? 0
        // 1.0s tail: the pulse animation only begins after the async screen
        // capture, so leave enough margin that cleanup never clips the last cycle.
        let totalDuration = btComp + lastBeat + 1.0

        // Initial lens centre = where the cursor is now (a sensible default for
        // the first beat). It is NOT frozen, though: scheduleHeartbeatPulses
        // re-centres it on the live mouse position before every lub-dub, so the
        // heart "beats" wherever the cursor currently rests.
        let mouseGlobal = NSEvent.mouseLocation
        let panelOriginGlobal = hostLayer.bounds.origin  // contentView bounds: (0,0)
        // Convert global mouse to layer-local coords. The overlay panel's
        // window frame defines the global origin of the layer. Find it via
        // the screen the hostLayer's containing window currently occupies.
        let anchor = Self.layerAnchor(forGlobalMouse: mouseGlobal,
                                      panelOrigin: panelOriginGlobal,
                                      hostLayer: hostLayer)

        // Insert a placeholder layer so a second tap is debounced even while
        // the screencapture subprocess is still running. What gets tracked is a
        // CONTAINER rather than the capture itself: the 🐶 rides on top of the
        // beating screen and has to be torn down by the same stop-all and the
        // same auto-cleanup, so the pair must be one tracked unit.
        let container = CALayer()
        container.frame = bounds

        // Pivot stays at the layer's centre: the beat itself is the lens below,
        // and what little whole-screen breathe is left should be symmetric
        // rather than hinged on the cursor — pivoting at the pointer is what
        // made the far corner the fastest-moving thing on screen.
        let imgLayer = CALayer()
        imgLayer.frame = bounds
        // 💓 The lens. Installed here, before the capture comes back, so the
        // first beat can never race it. `name` is what makes the per-beat
        // `filters.bump.inputScale` key path resolve.
        let bump = CIFilter(name: "CIBumpDistortion")
        if let bump = bump {
            let center = HeartbeatBump.center(forAnchor: anchor, bounds: bounds)
            bump.name = Self.heartbeatBumpFilterName
            bump.setValue(CIVector(x: center.x, y: center.y), forKey: kCIInputCenterKey)
            bump.setValue(HeartbeatBump.radius(in: bounds), forKey: kCIInputRadiusKey)
            bump.setValue(0.0, forKey: kCIInputScaleKey)   // at rest: identity
            imgLayer.filters = [bump]
        } else {
            overlayError("CIBumpDistortion unavailable — heartbeat falls back to the breathe alone")
        }
        container.addSublayer(imgLayer)
        trackEffect("heartbeat", layer: container, duration: totalDuration)

        // 🖱️ The pointer goes away for the whole beat (Victor, 2026-09-19: "the
        // mouse should not be visible during this animation"). It reads as a
        // taste call and is really a consequence of the lens following the mouse
        // now: an arrow parked on top of the bulge it is itself causing looks
        // like the arrow is what got magnified, and the magnification stops
        // being the subject.
        let cursorHide = HeartbeatCursorHide()
        // Whoever tears down first gives it back — normally `watchHeartbeatScreen`.
        // This is the backstop for the one path that has no timer: a capture that
        // never returns, so the follow is never armed at all.
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration + 1.0) {
            cursorHide.release()
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let captured = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self = self,
                      self.activeEffects["heartbeat"] === container else {
                    // Preempted (or stopped) while the capture was in flight.
                    // Nothing further runs for this heartbeat, so the pointer has
                    // to come back from here.
                    cursorHide.release()
                    return
                }
                if let captured = captured {
                    imgLayer.contents = captured
                    imgLayer.contentsGravity = .resize
                }
                // Added after the capture => drawn above it. A SIBLING, not a
                // child, on purpose: the lub-dub beats `imgLayer` alone (CALayer
                // filters apply to a layer *and its sublayers*), so the screen
                // bulges under the cursor while the dog beside it stays undistorted.
                // 🐶/🐱 The companion alternates run to run — the choice itself
                // lives in `HeartbeatCompanion`, this is only the wiring. Both
                // animals now follow the beat (Victor, 2026-09-14: the cat
                // translates the way the dog does); they differ in what they
                // track — the dog's face rides at the cursor's height, the cat
                // stays flat on the floor. A cat asked for but missing from
                // assetsDir falls back to the dog.
                var companion: (layer: CALayer, onRight: Bool)?
                if HeartbeatCompanion.next() == .cat {
                    // `anchor` is the cursor as it was when the effect started,
                    // before the capture — which is exactly the "decide once at
                    // start" the cat's side wants, and it puts the cat in the
                    // right place before its first frame instead of sliding it in
                    // from somewhere nobody saw.
                    companion = HeartbeatCatFollow.makeLayer(
                        bounds: bounds,
                        cursor: CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height))
                    if companion == nil {
                        overlayInfo("💓 \(HeartbeatCatFollow.assetName) not in \(EffectsConfig.shared.assetsDir.path) — falling back to the 🐶")
                    }
                }
                if let cat = companion {
                    container.addSublayer(cat.layer)
                    self.watchHeartbeatCat(cat.layer, onRight: cat.onRight, effect: container,
                                           bounds: bounds, until: clock0 + totalDuration)
                } else if let dog = Self.makeHeartbeatDogLayer(bounds: bounds) {
                    overlayInfo("💓 companion: 🐶 following dog")
                    container.addSublayer(dog)
                    self.watchHeartbeatDog(dog, effect: container, bounds: bounds,
                                           until: clock0 + totalDuration)
                }
                self.hostLayer.addSublayer(container)
                self.scheduleHeartbeatPulses(layer: imgLayer, effect: container,
                                             beats: beats, clock0: clock0)
                // …and from here the screenshot stops being a screenshot: the
                // lens walks after the pointer and the picture under it is
                // retaken four times a second. Also the owner of `cursorHide`.
                self.watchHeartbeatScreen(imgLayer, effect: container, bounds: bounds,
                                          until: clock0 + totalDuration,
                                          cursorHide: cursorHide)
            }
        }
        return soundDuration
    }

    /// A cursor hide that can be released exactly once, by whichever teardown
    /// path gets there first.
    ///
    /// `NSCursor.hide()`/`unhide()` and `CGDisplayHideCursor`/`ShowCursor` are
    /// **counted**, so a double release does not merely do nothing — it cancels
    /// somebody else's hide (the 😱 fear face's, say, which hides the pointer for
    /// its own reasons). The heartbeat has three ends that all have to be safe:
    /// the follow timer noticing the effect is over, the capture completion
    /// finding itself preempted, and an absolute backstop for when neither runs.
    /// A box that can only be opened once is cheaper than three call sites
    /// agreeing on who wins.
    ///
    /// Main thread only — the counters behind it are not thread-safe.
    private final class HeartbeatCursorHide {
        private var held = true
        init() {
            // Lifts the "only while frontmost" restriction: our overlay floats
            // over whatever app Victor is actually in, so without this the real
            // arrow keeps showing over the beat.
            EmojiAnimator.armBackgroundCursorHiding()
            NSCursor.hide()
            CGDisplayHideCursor(CGMainDisplayID())
        }
        func release() {
            guard held else { return }
            held = false
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    /// 🐶 The chihuahua pinned over the beating screen. It is cut out of its
    /// background as real alpha — not a coloured box — so the capture pulsing
    /// behind it shows through around the fur.
    ///
    /// This function only decides how **big** the dog is: half the screen,
    /// aspect-fit, taken down to two thirds. Where it stands is not settled here
    /// at all — `watchHeartbeatDog` parks it against the beat (face first, body
    /// free to run off the bottom edge) before the first frame is ever drawn, so
    /// the frame set below is a placeholder that is never seen.
    private static let heartbeatDogScale: CGFloat = 2.0 / 3.0

    private static func makeHeartbeatDogLayer(bounds: CGRect) -> CALayer? {
        guard let url = Bundle.module.url(forResource: "heartbeat-dog", withExtension: "png", subdirectory: "Resources")
                ?? Bundle.module.url(forResource: "heartbeat-dog", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            overlayError("heartbeat-dog.png not found in bundle")
            return nil
        }
        // Aspect-fit inside half the screen with a small side margin, then take
        // TWO THIRDS of that: filling the half outright made the dog the subject
        // and the beating screen its backdrop, which is the wrong way round.
        // hostLayer is bottom-origin, so y = 0 is the floor of the screen.
        let halfWidth = bounds.width / 2
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var w = halfWidth * 0.92
        var h = w / aspect
        let maxH = bounds.height * 0.80
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        w *= Self.heartbeatDogScale
        h *= Self.heartbeatDogScale
        let layer = CALayer()
        layer.frame = CGRect(x: (halfWidth - w) / 2, y: 0, width: w, height: h)
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        return layer
    }

    /// The `CIFilter.name` the lens is installed under, and therefore the middle
    /// component of the `filters.<name>.inputScale` / `.inputCenter` key paths
    /// the per-beat animation drives. One place, so the two can't drift apart.
    private static let heartbeatBumpFilterName = "bump"

    /// How far ahead of the rise the per-cycle callback is armed. It only has to
    /// re-centre the lens and hand CoreAnimation two animations whose `beginTime`
    /// is already the exact instant — so this absorbs main-thread jitter without
    /// putting any of it on screen.
    private static let heartbeatArmLead: CFTimeInterval = 0.06

    /// One self-contained lub-dub per cycle, each pinned to the real onset times
    /// in `heartbeat_beats.json` — the *rising edges* measured off the clip, laid
    /// out `[lub, dub, lub, dub …]`.
    ///
    /// Two things decide whether this reads as synced, and both used to be wrong:
    ///
    /// 1. **What the clock zero is.** `clock0` is the moment the audio starts, not
    ///    the moment the screen capture came back — the capture is async and cost
    ///    a variable couple of hundred ms, all of which used to be added to every
    ///    beat.
    /// 2. **Which part of the swell lands on the beat.** The *peak* is what the
    ///    eye takes as the hit, so a cycle begins `rise` seconds BEFORE its
    ///    onset and the bump tops out exactly on it. Starting the rise on the
    ///    onset (what it did before) puts the peak half a pulse late, which reads
    ///    as lagging even with a perfect clock.
    ///
    /// Each cycle drives TWO animations off one set of key times: the
    /// `HeartbeatBump` lens under the cursor (the beat proper) and a 2% breathe
    /// of the whole capture (so the rest of the screen isn't stone dead). They
    /// share `beginTime`, so they cannot drift apart on screen.
    ///
    /// The per-cycle deadlines are absolute and independent, so a beat whose
    /// moment has already passed (a slow capture, a late press) is **skipped**
    /// rather than fired late — one missing thump is invisible, a whole timeline
    /// shifted behind the audio is exactly the ugly part.
    private func scheduleHeartbeatPulses(layer: CALayer, effect: CALayer,
                                         beats: [Double], clock0: CFTimeInterval) {
        // Pair the onsets up: even index = lub, the odd one after it = its dub.
        let pairs = stride(from: 0, to: beats.count - 1, by: 2).map { (beats[$0], beats[$0 + 1]) }
        guard !pairs.isEmpty else { return }

        let bounds = layer.bounds
        for (lub, dub) in pairs {
            let dubOffset = dub - lub
            guard dubOffset > 0 else { continue }
            // Each swell-and-relax is a symmetric easeInOut bell (rise == fall).
            // Keep the lub pulse fully clear of the dub so the two never blend.
            let pulseDur = min(0.22, max(0.08, dubOffset - 0.02))
            let rise     = pulseDur / 2.0
            // beginTime such that the FIRST peak lands on the lub onset; the dub
            // peak then lands on its own onset, dubOffset later.
            let startAt = clock0 + lub - rise
            let armAt   = startAt - Self.heartbeatArmLead
            let wait    = armAt - CACurrentMediaTime()
            guard wait > 0 else { continue }   // already past — skip, never fire late

            let times: [Double] = [
                0.0,                    // lub: start rise
                rise,                   // lub: PEAK, on the onset
                pulseDur,               // lub: back to rest
                dubOffset,              // dub: start rise
                dubOffset + rise,       // dub: PEAK, on its onset
                dubOffset + pulseDur,   // dub: back to rest
            ]
            let cycleDur = dubOffset + pulseDur

            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self, weak layer, weak effect] in
                guard let self = self, let layer = layer, let effect = effect,
                      self.activeEffects["heartbeat"] === effect else { return }
                // Re-centre the LENS on the current mouse before this beat. The
                // bump is back at 0 here, so moving its centre is invisible.
                let anchor = Self.layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                              panelOrigin: self.hostLayer.bounds.origin,
                                              hostLayer: self.hostLayer)
                let center = HeartbeatBump.center(forAnchor: anchor, bounds: bounds)
                CATransaction.begin()
                CATransaction.setDisableActions(true)   // move the lens instantly, no slide
                layer.setValue(CIVector(x: center.x, y: center.y),
                               forKeyPath: "filters.\(Self.heartbeatBumpFilterName).inputCenter")
                CATransaction.commit()

                let keyTimes = times.map { NSNumber(value: $0 / cycleDur) }
                let timings = [
                    CAMediaTimingFunction(name: .easeInEaseOut), // lub rise
                    CAMediaTimingFunction(name: .easeInEaseOut), // lub fall
                    CAMediaTimingFunction(name: .linear),        // rest between lub and dub
                    CAMediaTimingFunction(name: .easeInEaseOut), // dub rise
                    CAMediaTimingFunction(name: .easeInEaseOut), // dub fall
                ]

                // The beat proper: the lens swells and relaxes under the cursor.
                // Outside its radius CIBumpDistortion is the identity, so this
                // costs the periphery exactly zero movement.
                let lens = CAKeyframeAnimation(keyPath: "filters.\(Self.heartbeatBumpFilterName).inputScale")
                let peak = HeartbeatBump.peakScale
                lens.values   = [0, peak, 0, 0, peak, 0]
                lens.keyTimes = keyTimes
                lens.timingFunctions = timings
                lens.duration = cycleDur
                // Absolute, in CoreAnimation's own clock: the render server places
                // the pulse on the exact frame even though this callback was armed
                // early and may itself have jittered.
                lens.beginTime = startAt
                layer.add(lens, forKey: "heartbeatLens")

                // …plus a hair of whole-screen breathe, so the screen still reads
                // as alive between lens pulses without the corners lurching.
                let breathe = CAKeyframeAnimation(keyPath: "transform.scale")
                let b = HeartbeatBump.breatheScale
                breathe.values   = [1.0, b, 1.0, 1.0, b, 1.0]
                breathe.keyTimes = keyTimes
                breathe.timingFunctions = timings
                breathe.duration = cycleDur
                breathe.beginTime = startAt
                layer.add(breathe, forKey: "heartbeatPulse")
            }
        }
    }

    /// How often the cursor is sampled while the dog is on screen. The overlay
    /// panel is click-through, so it receives no mouse events at all — polling
    /// `NSEvent.mouseLocation` is the only reading available, and 20 Hz is well
    /// under the reaction time this is imitating.
    private static let heartbeatDogPollInterval: TimeInterval = 0.05

    /// How long the dog takes to catch up when the beat moves. Deliberately a
    /// touch longer than the poll
    /// interval: the dog then trails the pointer by a frame or two instead of
    /// being welded to it, which is what makes it read as following rather than
    /// as a cursor decoration.
    private static let heartbeatDogFollowDuration: CFTimeInterval = 0.16

    /// 💓 How often the picture under the beat is retaken — 4 fps (Victor,
    /// 2026-09-19: "a four frame per second refresh"). This is not a frame rate
    /// anybody watches; it is the rate at which the content stops being stale.
    ///
    /// The *lens* is deliberately not on this clock. It follows the pointer at
    /// the 20 Hz poll the companions already use, because moving a
    /// `CIBumpDistortion`'s centre is a filter parameter rather than a redraw,
    /// and a magnifier that snaps to the mouse four times a second reads as
    /// broken where one that snaps twenty times a second reads as glued.
    private static let heartbeatRecaptureInterval: TimeInterval = 0.25

    /// 💓 Keeps the beat honest about the two things it used to freeze at press
    /// time: **where** the lens is and **what** it is magnifying.
    ///
    /// Until 2026-09-19 the lens was re-centred once per lub-dub pair, at the
    /// moment that pair was armed, over a screenshot taken once and never again.
    /// Moving the mouse mid-beat therefore left the bulge sitting where the
    /// pointer *had* been (Victor: "even if I move my mouse, the bump stays on
    /// the same place"), magnifying a picture of a screen that had since moved
    /// on. Both are live now, on two different clocks — see
    /// `heartbeatRecaptureInterval` for why they are not the same one.
    ///
    /// Captures never overlap: one is in flight at a time, and a tick that finds
    /// the previous one still running simply skips its turn rather than queueing
    /// behind it. A capture that answers nil leaves the current frame alone —
    /// which is exactly the pre-2026-09-19 behaviour, so every failure mode
    /// degrades to "the screenshot is frozen again" rather than to a broken
    /// effect.
    ///
    /// The timer is also what gives the pointer back: it stops the moment this is
    /// no longer the active heartbeat, and releases `cursorHide` on the way out.
    private func watchHeartbeatScreen(_ imgLayer: CALayer, effect: CALayer, bounds: CGRect,
                                      until deadline: CFTimeInterval,
                                      cursorHide: HeartbeatCursorHide) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var capturing = false
        // The initial screenshot is milliseconds old at this point, so the first
        // refresh is a full interval away rather than immediate.
        var nextCaptureAt = CACurrentMediaTime() + Self.heartbeatRecaptureInterval

        // Returns false once this effect is over — the timer's cue to stop.
        let advance: () -> Bool = { [weak self, weak imgLayer, weak effect] in
            guard let self = self, let imgLayer = imgLayer, let effect = effect,
                  self.activeEffects["heartbeat"] === effect,
                  CACurrentMediaTime() < deadline else { return false }

            // 1. The lens goes where the mouse is. Instantly, with no implicit
            //    slide: the bump *is* the pointer's mark on the screen, so a
            //    magnifier easing in behind the hand reads as lag, not as weight.
            //    Safe to do mid-swell — `inputCenter` and the animated
            //    `inputScale` are different key paths on the same filter.
            let anchor = Self.layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                          panelOrigin: self.hostLayer.bounds.origin,
                                          hostLayer: self.hostLayer)
            let center = HeartbeatBump.center(forAnchor: anchor, bounds: bounds)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imgLayer.setValue(CIVector(x: center.x, y: center.y),
                              forKeyPath: "filters.\(Self.heartbeatBumpFilterName).inputCenter")
            CATransaction.commit()

            // 2. …and four times a second, the picture under it.
            let now = CACurrentMediaTime()
            guard !capturing, now >= nextCaptureAt else { return true }
            capturing = true
            nextCaptureAt = now + Self.heartbeatRecaptureInterval
            Self.captureScreenExcludingOverlay { [weak self, weak imgLayer, weak effect] image in
                capturing = false
                guard let self = self, let imgLayer = imgLayer, let effect = effect,
                      self.activeEffects["heartbeat"] === effect,
                      let image = image else { return }
                // `contents` has a default implicit animation, and a cross-fade
                // between two nearly identical screenshots turns every refresh
                // into a visible smear. Swap it outright.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                imgLayer.contents = image
                CATransaction.commit()
            }
            return true
        }

        timer.schedule(deadline: .now() + Self.heartbeatDogPollInterval,
                       repeating: Self.heartbeatDogPollInterval)
        timer.setEventHandler {
            if !advance() {
                timer.cancel()
                cursorHide.release()
            }
        }
        timer.resume()
    }

    /// A screenshot of the built-in display **with our own overlay cut out of
    /// it**, handed back on the main thread.
    ///
    /// The exclusion is the whole point, and it is why this is not simply
    /// `captureBuiltInDisplay()` on a timer. A refresh is taken while the overlay
    /// is showing the *previous* capture, so a plain screenshot would photograph
    /// the effect's own output — a bumped screen inside a bumped screen, one
    /// level deeper every 250 ms.
    ///
    /// `screencapture(1)`, which the first capture still uses (at that instant
    /// the overlay is empty, so there is nothing to exclude), cannot leave a
    /// window out. `CGWindowListCreateImage` could, via
    /// `.optionOnScreenBelowWindow` — and was the obvious answer right up until
    /// macOS 15 **obsoleted** it: it is a compile error now, not a warning. What
    /// replaced it is ScreenCaptureKit's `SCContentFilter(display:excludingWindows:)`.
    ///
    /// Answers nil — never a fallback screenshot — on macOS 13, without Screen
    /// Recording permission, or when our own panel is missing from the window
    /// list. "Cannot exclude the overlay" must mean "do not capture", because the
    /// alternative is the recursion above.
    private static func captureScreenExcludingOverlay(_ done: @escaping (CGImage?) -> Void) {
        guard #available(macOS 14.0, *) else { done(nil); return }
        // Main thread: `NSApp.windows` is AppKit state, and the only caller is a
        // main-queue timer.
        let excluded = Set(NSApp.windows.compactMap {
            $0 is OverlayPanel ? CGWindowID($0.windowNumber) : nil
        })
        guard !excluded.isEmpty else { done(nil); return }
        heartbeatContentFilter(excluding: excluded, displayID: builtInDisplayID()) { filter in
            guard let filter = filter else { DispatchQueue.main.async { done(nil) }; return }
            let cfg = SCStreamConfiguration()
            cfg.width  = Int(filter.contentRect.width  * CGFloat(filter.pointPixelScale))
            cfg.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
            // The real pointer is hidden for the whole beat anyway; this makes
            // sure a stray one can never be baked into the picture either, the
            // way `captureBuiltInDisplay` omits -C for the same reason.
            cfg.showsCursor = false
            cfg.captureResolution = .best
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg) { image, error in
                if image == nil, let error = error {
                    overlayError("💓 refresh capture failed: \(error.localizedDescription)")
                }
                DispatchQueue.main.async { done(image) }
            }
        }
    }

    /// The cached content filter behind `captureScreenExcludingOverlay`.
    ///
    /// Built once per process and reused, because
    /// `SCContentFilter(display:excludingWindows:)` is a **live** filter: it is
    /// "this display, minus these windows", evaluated at capture time, so windows
    /// that open after it was built still show up. Only the exclusion list is
    /// frozen — and our overlay panel is created once at launch and never
    /// replaced, so that is exactly the part that may be.
    ///
    /// Typed `AnyObject?` so the stored property itself carries no macOS 14
    /// requirement; the package still builds for macOS 13.
    private static var _heartbeatContentFilter: AnyObject?

    @available(macOS 14.0, *)
    private static func heartbeatContentFilter(excluding: Set<CGWindowID>,
                                               displayID: CGDirectDisplayID,
                                               _ done: @escaping (SCContentFilter?) -> Void) {
        if let cached = _heartbeatContentFilter as? SCContentFilter { done(cached); return }
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { content, error in
            guard let content = content,
                  let display = content.displays.first(where: { $0.displayID == displayID })
                             ?? content.displays.first else {
                overlayError("💓 no shareable display for the refresh capture: \(error?.localizedDescription ?? "unknown")")
                done(nil)
                return
            }
            let mine = content.windows.filter { excluding.contains($0.windowID) }
            guard !mine.isEmpty else {
                // Our panel is not in the list, so a capture could not leave it
                // out. Refuse rather than photograph ourselves.
                overlayInfo("💓 overlay panel not in the shareable window list — skipping the live refresh")
                done(nil)
                return
            }
            let filter = SCContentFilter(display: display, excludingWindows: mine)
            DispatchQueue.main.async { _heartbeatContentFilter = filter }
            done(filter)
        }
    }

    /// The built-in panel's display **id** — the ScreenCaptureKit counterpart of
    /// `builtInDisplayNumber()`, which answers the 1-based index
    /// `screencapture -D` wants instead.
    private static func builtInDisplayID() -> CGDirectDisplayID {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return CGMainDisplayID() }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return CGMainDisplayID() }
        return displays.first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// 🐶 The dog stays next to the beat for as long as the heartbeat runs.
    ///
    /// The rule inverted on 2026-09-06. It used to flee the cursor to the far
    /// half of the screen; but the projector is generally zoomed in around the
    /// beat, so the far half is precisely the part of the screen the room cannot
    /// see. Now the dog is glued to the beat: parked right up against the pulsing
    /// lens — 30 % inside the strict clearance since 2026-09-10, so the ear leans
    /// into it — **face** toward the pointer, and it moves along whenever the
    /// pointer does.
    ///
    /// **The side is chosen once and then kept** (Victor, 2026-09-09). The first
    /// poll picks it the way it always did — from the half of the screen the
    /// cursor is in, so the dog gets the roomier side — and that answer stands
    /// for the whole heartbeat. It used to be re-decided on every poll, which
    /// meant dragging the pointer across the midline mid-effect sent the dog
    /// leaping over the beat to the other side. On the projector that read as a
    /// glitch rather than as a joke, and the leap (with its mirror at the apex
    /// and its cursor freeze) is gone with it.
    ///
    /// What is left is the follow: a short eased slide of both x and y onto the
    /// placement `HeartbeatDogFollow.position` computes, on whichever side was
    /// locked in. The face rides at the cursor's own height, so a pointer near
    /// the bottom of the screen leaves most of the dog's body below the frame.
    /// That is the intended look, not a clamp that failed.
    ///
    /// The timer stops itself the moment this effect is no longer the active
    /// heartbeat, so a stop-all — or the next press — never leaves it polling.
    private func watchHeartbeatDog(_ dog: CALayer, effect: CALayer, bounds: CGRect,
                                   until deadline: CFTimeInterval) {
        var onRight = false
        var placed = false
        let lens = HeartbeatBump.radius(in: bounds)

        let timer = DispatchSource.makeTimerSource(queue: .main)

        // Returns false once this effect is over — which is the timer's cue to
        // stop. `animated` is false only for the placement before the first frame.
        let advance: (Bool) -> Bool = { [weak self, weak dog, weak effect] animated in
            guard let self = self, let dog = dog, let effect = effect,
                  self.activeEffects["heartbeat"] === effect,
                  CACurrentMediaTime() < deadline else { return false }
            let rel = Self.layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                       panelOrigin: self.hostLayer.bounds.origin,
                                       hostLayer: self.hostLayer)
            let cursor = CGPoint(x: rel.x * bounds.width, y: rel.y * bounds.height)
            // Only the FIRST poll gets a vote. After that the dog keeps the side
            // it appeared on, whatever the pointer does — see the note above.
            if !placed {
                onRight = HeartbeatDogFollow.shouldBeOnRight(cursorX: cursor.x,
                                                             wasOnRight: onRight,
                                                             boundsWidth: bounds.width)
            }
            let to = HeartbeatDogFollow.position(onRight: onRight,
                                                 cursor: cursor,
                                                 boxSize: dog.bounds.size,
                                                 clearRadius: lens,
                                                 bounds: bounds)
            let from = dog.presentation()?.position ?? dog.position

            // The first evaluation is a placement, not a move: the layer is built
            // at a placeholder frame, and the dog has to be beside the beat
            // *before* the first frame — not sliding in from a spot nobody saw.
            guard placed else {
                placed = true
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                dog.position = to
                dog.transform = Self.heartbeatDogFacing(onRight: onRight)
                CATransaction.commit()
                return true
            }
            let dx = to.x - from.x, dy = to.y - from.y
            guard animated, (dx * dx + dy * dy).squareRoot() >= HeartbeatDogFollow.minStep
            else { return true }

            // The dog trots after the beat. It never changes sides any more, so
            // there is nothing left to leap over and nothing to re-aim mid-flight.
            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: NSPoint(x: from.x, y: from.y))
            slide.toValue = NSValue(point: NSPoint(x: to.x, y: to.y))
            slide.duration = Self.heartbeatDogFollowDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)

            CATransaction.begin()
            CATransaction.setDisableActions(true)   // set the model value, no implicit slide
            dog.position = to
            CATransaction.commit()
            dog.add(slide, forKey: "dogHop")
            return true
        }

        _ = advance(false)

        timer.schedule(deadline: .now() + Self.heartbeatDogPollInterval,
                       repeating: Self.heartbeatDogPollInterval)
        timer.setEventHandler {
            if !advance(true) { timer.cancel() }
        }
        timer.resume()
    }

    /// 🐱 The cat walks after the beat, on the same timer and the same eased
    /// slide as the dog (Victor, 2026-09-14: "să se translateze cum se
    /// translatează câinele"). Until that ask the cat was placed once and never
    /// touched again — `HeartbeatCatFollow` carries the history of why.
    ///
    /// Two things it does NOT copy from `watchHeartbeatDog`, both because the
    /// cat's placement is simpler than the dog's:
    ///
    /// - **No first-poll placement.** `makeLayer` already put the cat beside the
    ///   beat from the same `anchor` the first lens centre uses, so the layer is
    ///   correct before its first frame and this timer only has to keep it there.
    /// - **No side vote.** The side came with the layer — it is baked into the
    ///   mirror (`HeartbeatCatFollow.facing`), so re-deciding it here would flip
    ///   the cat and teleport it across the beat in one frame, which is the very
    ///   glitch the dog stopped doing on 2026-09-09.
    ///
    /// Only x actually moves: the cat is pinned to the floor, so
    /// `HeartbeatCatFollow.position` returns the same y every time. The timer
    /// stops itself the moment this is no longer the active heartbeat, so a
    /// stop-all — or the next press — never leaves it polling.
    private func watchHeartbeatCat(_ cat: CALayer, onRight: Bool, effect: CALayer,
                                   bounds: CGRect, until deadline: CFTimeInterval) {
        let size = cat.bounds.size
        let timer = DispatchSource.makeTimerSource(queue: .main)

        // Returns false once this effect is over — the timer's cue to stop.
        let advance: () -> Bool = { [weak self, weak cat, weak effect] in
            guard let self = self, let cat = cat, let effect = effect,
                  self.activeEffects["heartbeat"] === effect,
                  CACurrentMediaTime() < deadline else { return false }
            let rel = Self.layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                       panelOrigin: self.hostLayer.bounds.origin,
                                       hostLayer: self.hostLayer)
            let cursor = CGPoint(x: rel.x * bounds.width, y: rel.y * bounds.height)
            let to = HeartbeatCatFollow.position(size: size, in: bounds,
                                                 onRight: onRight, cursor: cursor)
            let from = cat.presentation()?.position ?? cat.position
            let dx = to.x - from.x, dy = to.y - from.y
            guard (dx * dx + dy * dy).squareRoot() >= HeartbeatDogFollow.minStep else { return true }

            let slide = CABasicAnimation(keyPath: "position")
            slide.fromValue = NSValue(point: NSPoint(x: from.x, y: from.y))
            slide.toValue = NSValue(point: NSPoint(x: to.x, y: to.y))
            slide.duration = Self.heartbeatDogFollowDuration
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)

            CATransaction.begin()
            CATransaction.setDisableActions(true)   // set the model value, no implicit slide
            cat.position = to
            CATransaction.commit()
            cat.add(slide, forKey: "catWalk")
            return true
        }

        timer.schedule(deadline: .now() + Self.heartbeatDogPollInterval,
                       repeating: Self.heartbeatDogPollInterval)
        timer.setEventHandler {
            if !advance() { timer.cancel() }
        }
        timer.resume()
    }

    /// The PNG faces right (muzzle toward the screen from the left), so a dog
    /// standing to the RIGHT of the beat has to be flipped to look back at it.
    private static func heartbeatDogFacing(onRight: Bool) -> CATransform3D {
        onRight ? CATransform3DMakeScale(-1, 1, 1) : CATransform3DIdentity
    }

    private static func loadHeartbeatBeats() -> [Double] {
        guard let url = Bundle.module.url(forResource: "heartbeat_beats", withExtension: "json", subdirectory: "Resources"),
              let data = try? Data(contentsOf: url),
              let beats = try? JSONDecoder().decode([Double].self, from: data) else {
            return []
        }
        return beats
    }

    private static func captureBuiltInDisplay() -> CGImage? {
        // Unique per call: several capture effects (heartbeat, broken glass, FBI,
        // phone) can now run this concurrently — a pid-only path would let them
        // clobber each other's file.
        let tmpPath = NSTemporaryDirectory() + "victor-capture-\(getpid())-\(UUID().uuidString).png"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        // No -C: the cursor is intentionally excluded from the captured image, so
        // the zoom pulses the desktop only. The live OS cursor stays visible and
        // movable on top of the overlay, never baked into the zoomed screenshot.
        process.arguments = ["-x", "-t", "png", "-D", String(builtInDisplayNumber()), tmpPath]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            overlayError("heartbeat capture failed: \(error)")
            return nil
        }
        guard let provider = CGDataProvider(filename: tmpPath),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return nil
        }
        try? FileManager.default.removeItem(atPath: tmpPath)
        return image
    }

    private static func builtInDisplayNumber() -> Int {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return 1 }
        if let idx = displays.firstIndex(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return idx + 1
        }
        return 1
    }

    private static func layerAnchor(forGlobalMouse mouse: CGPoint, panelOrigin: CGPoint, hostLayer: CALayer) -> CGPoint {
        // Find the built-in screen frame in global coords; that's where the
        // overlay panel sits. Anchor is mouse-position relative to that frame,
        // expressed as a unit-square fraction. Clamp so an off-screen mouse
        // still produces a valid pivot inside the layer.
        let screen = NSScreen.screens.first { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
            return CGDisplayIsBuiltin(id) != 0
        } ?? NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.frame, frame.width > 0, frame.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        let relX = (mouse.x - frame.origin.x) / frame.width
        let relY = (mouse.y - frame.origin.y) / frame.height
        return CGPoint(x: min(max(relX, 0), 1), y: min(max(relY, 0), 1))
    }

    // MARK: - 🔍 Magnifier (sfx #6, 06_copyright_cartoon.mp3 — the Pink Panther)

    /// Tile #6 is the Pink Panther theme with Inspector Clouseau on the artwork,
    /// stooped over a magnifying glass. So the desktop gets the glass: a drawn
    /// prop a third of the screen tall that rides the pointer and magnifies
    /// **only what is inside its lens** — the rest of the screen is untouched,
    /// which is the whole difference between this and the 💓 heartbeat's
    /// whole-screen bump.
    static let magnifierSound = "06_copyright_cartoon.mp3"

    /// Measured length of that clip, used only when the mp3 is not on this
    /// machine (this repo carries no soundboard audio).
    static let magnifierFallbackDuration: TimeInterval = 37.8

    /// How often the glass is put back on the pointer. Same 20 Hz as the
    /// heartbeat's lens and the companions, and for the same reason: the overlay
    /// panel is click-through, so it receives no mouse events at all and polling
    /// `NSEvent.mouseLocation` is the only reading there is. A magnifier that
    /// snapped to the mouse four times a second would read as broken.
    private static let magnifierFollowInterval: TimeInterval = 0.05

    /// …and how often the desktop **under** it is retaken: 4 fps, the heartbeat's
    /// rate. Not a frame rate anybody watches — the rate at which the picture
    /// stops being stale. Deliberately NOT the follow rate: moving the glass is
    /// two layer positions, while a recapture is a ScreenCaptureKit round trip.
    private static let magnifierRecaptureInterval: TimeInterval = 0.25

    /// The glass drops onto the pointer rather than blinking into existence, and
    /// lifts off at the end of the clip.
    private static let magnifierEntrance: CFTimeInterval = 0.32
    private static let magnifierFade: CFTimeInterval = 0.4

    /// 🔍 Show the glass on the pointer for the length of the Pink Panther clip.
    ///
    /// Three layers, and the split matters: a round **clip** layer holding the
    /// screenshot scaled `MagnifierGlass.zoom` times (the magnification), the
    /// drawn **glass** on top of it (rim, collar, handle, glare), and a container
    /// so one `stop-all` takes both away. The zoom is a layer frame inside a
    /// masked circle rather than a `CIBumpDistortion` because this lens is not a
    /// bulge: everything inside the rim is magnified by exactly the same factor,
    /// the way looking through a real glass works, and everything outside it is
    /// not merely less magnified but literally the untouched desktop.
    func showMagnifier() {
        // A re-press PREEMPTS rather than being swallowed: the tablet fires
        // /effect/stop-all before every press anyway, and restarting is what the
        // audio does on its own path, so the two halves agree.
        _ = cancelIfRunning("magnifier")
        let bounds = hostLayer.bounds
        let diameter = MagnifierGlass.outerDiameter(in: bounds)
        guard diameter > 1 else { return }

        // On screen for exactly as long as the clip plays — the lifecycle rule.
        // A `/sound/stopped` → "magnifier/stop" is the polite exit; this is the
        // guaranteed one.
        var clipDuration = Self.magnifierFallbackDuration
        if let url = SoundManager.shared.soundURL(for: Self.magnifierSound) {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { clipDuration = CMTimeGetSeconds(d) }
        }

        let scale = Screens.overlayScreen()?.backingScaleFactor ?? 2.0
        guard let art = MagnifierGlass.image(outerDiameter: diameter, scale: scale) else {
            overlayError("🔍 magnifier: the glass could not be drawn at \(Int(diameter))pt")
            return
        }
        let glassRadius = MagnifierGlass.glassRadius(outerDiameter: diameter)
        let focus = Self.magnifierFocus(bounds: bounds, hostLayer: hostLayer)

        let container = CALayer()
        container.frame = bounds

        // The lens: a circular window with the whole screenshot behind it,
        // blown up and slid until the pointer's spot sits in the middle.
        let clip = CALayer()
        clip.bounds = CGRect(x: 0, y: 0, width: glassRadius * 2, height: glassRadius * 2)
        clip.position = focus
        clip.cornerRadius = glassRadius
        clip.masksToBounds = true
        let shot = CALayer()
        shot.contentsGravity = .resize
        shot.contentsScale = scale
        shot.frame = MagnifierGlass.shotFrame(screen: bounds, focus: focus, glassRadius: glassRadius)
        clip.addSublayer(shot)
        container.addSublayer(clip)

        // The prop, hung off its own lens centre (`lensAnchor`) so it and the
        // lens share one position — and so the entrance scales about the glass
        // rather than about the handle's far end.
        let glass = CALayer()
        glass.contents = art
        glass.contentsScale = scale
        glass.bounds = CGRect(origin: .zero, size: MagnifierGlass.canvasSize(outerDiameter: diameter))
        glass.anchorPoint = MagnifierGlass.lensAnchor(outerDiameter: diameter)
        glass.position = focus
        glass.shadowColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        glass.shadowOpacity = 0.35
        glass.shadowRadius = diameter * 0.03
        glass.shadowOffset = CGSize(width: diameter * 0.018, height: -diameter * 0.018)
        container.addSublayer(glass)

        // Tracked BEFORE the capture, as a placeholder: the screencapture
        // subprocess takes a couple of hundred ms, and a second press in that
        // window must preempt this run rather than stack a second glass on it.
        let startedAt = CACurrentMediaTime()
        trackEffect("magnifier", layer: container, duration: clipDuration)
        overlayInfo(String(format: "🔍 magnifier: %.0fpt lens at %.0f×, following the pointer for %.1fs",
                           diameter, MagnifierGlass.zoom, clipDuration))

        // The first picture is taken while the overlay is still EMPTY — nothing
        // of ours is on screen yet, so `screencapture(1)` cannot photograph the
        // effect's own output. Every refresh after this one has to exclude the
        // panel explicitly (`captureScreenExcludingOverlay`).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let captured = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self = self, self.activeEffects["magnifier"] === container else { return }
                if let captured = captured { shot.contents = captured }
                self.hostLayer.addSublayer(container)

                // Added here rather than above: a layer outside the render tree
                // has nothing to run an animation against, so the drop would be
                // over before the glass was ever visible.
                let drop = CABasicAnimation(keyPath: "transform.scale")
                drop.fromValue = 1.45
                drop.toValue = 1.0
                drop.duration = Self.magnifierEntrance
                drop.timingFunction = CAMediaTimingFunction(name: .easeOut)
                clip.add(drop, forKey: "magnifierDrop")
                glass.add(drop, forKey: "magnifierDrop")
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0.0
                fadeIn.toValue = 1.0
                fadeIn.duration = Self.magnifierEntrance * 0.7
                container.add(fadeIn, forKey: "magnifierIn")

                // The lift-off, timed from the press (not from the capture) so
                // it always lands just before `trackEffect` takes the layer away.
                let fadeOut = CABasicAnimation(keyPath: "opacity")
                fadeOut.fromValue = 1.0
                fadeOut.toValue = 0.0
                fadeOut.beginTime = startedAt + max(0, clipDuration - Self.magnifierFade)
                fadeOut.duration = Self.magnifierFade
                fadeOut.fillMode = .forwards
                fadeOut.isRemovedOnCompletion = false
                container.add(fadeOut, forKey: "magnifierOut")

                self.watchMagnifier(clip: clip, shot: shot, glass: glass, effect: container,
                                    bounds: bounds, until: startedAt + clipDuration)
            }
        }
    }

    /// "magnifier/stop" — the clip was stopped on the tablet. Fades rather than
    /// cuts, so a stop mid-clip looks like the inspector pocketing the glass.
    func stopMagnifier() {
        guard let container = activeEffects["magnifier"] else { return }
        // Dropping the key is also what stops the follow timer and any in-flight
        // capture: both check that this container is still the active one.
        activeEffects.removeValue(forKey: "magnifier")
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.magnifierFade)
        container.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.magnifierFade) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    /// The pointer, in the overlay's own points.
    private static func magnifierFocus(bounds: CGRect, hostLayer: CALayer) -> CGPoint {
        let anchor = layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                 panelOrigin: hostLayer.bounds.origin,
                                 hostLayer: hostLayer)
        return CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
    }

    /// Keeps the glass honest about the two things a still picture would freeze:
    /// **where** it is and **what** it is looking at. Same shape as
    /// `watchHeartbeatScreen`, including the rule that captures never overlap —
    /// a tick that finds the previous one still in flight skips its turn instead
    /// of queueing behind it, and a capture that answers nil leaves the current
    /// frame alone, so every failure degrades to "the view is frozen" rather
    /// than to an empty lens.
    private func watchMagnifier(clip: CALayer, shot: CALayer, glass: CALayer, effect: CALayer,
                                bounds: CGRect, until deadline: CFTimeInterval) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        var capturing = false
        // The first picture is milliseconds old here, so the first refresh is a
        // whole interval away rather than immediate.
        var nextCaptureAt = CACurrentMediaTime() + Self.magnifierRecaptureInterval
        let glassRadius = clip.bounds.width / 2

        let advance: () -> Bool = { [weak self, weak clip, weak shot, weak glass, weak effect] in
            guard let self = self, let clip = clip, let shot = shot, let glass = glass,
                  let effect = effect, self.activeEffects["magnifier"] === effect,
                  CACurrentMediaTime() < deadline else { return false }

            // 1. The glass goes where the pointer is — instantly, with no
            //    implicit slide. A magnifier easing in behind the hand reads as
            //    lag; this one is held, not thrown.
            let focus = Self.magnifierFocus(bounds: bounds, hostLayer: self.hostLayer)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            clip.position = focus
            glass.position = focus
            shot.frame = MagnifierGlass.shotFrame(screen: bounds, focus: focus,
                                                  glassRadius: glassRadius)
            CATransaction.commit()

            // 2. …and four times a second, the desktop it is looking at.
            let now = CACurrentMediaTime()
            guard !capturing, now >= nextCaptureAt else { return true }
            capturing = true
            nextCaptureAt = now + Self.magnifierRecaptureInterval
            Self.captureScreenExcludingOverlay { [weak self, weak shot, weak effect] image in
                capturing = false
                guard let self = self, let shot = shot, let effect = effect,
                      self.activeEffects["magnifier"] === effect, let image = image else { return }
                // `contents` has a default implicit animation, and a cross-fade
                // between two nearly identical screenshots smears every refresh.
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shot.contents = image
                CATransaction.commit()
            }
            return true
        }

        timer.schedule(deadline: .now() + Self.magnifierFollowInterval,
                       repeating: Self.magnifierFollowInterval)
        timer.setEventHandler { if !advance() { timer.cancel() } }
        timer.resume()
    }

    // MARK: - Love hands (sound #41) — two hands close in from edges, then hearts
    // spiral up out of the meeting point.

    func showLoveHands(playSound: Bool = true) {
        // Re-pressing toggles off — but with a fade-out, not an instant cut.
        if activeEffects["love-hands"] != nil { stopLoveHands(); return }

        guard let leftURL = EffectsConfig.shared.assetURL("love_hand_left.png"),
              let rightURL = EffectsConfig.shared.assetURL("love_hand_right.png"),
              let leftSrc = NSImage(contentsOf: leftURL),
              let rightSrc = NSImage(contentsOf: rightURL),
              let leftCG = leftSrc.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rightCG = rightSrc.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            overlayError("love_hand_{left,right}.png not in \(EffectsConfig.shared.assetsDir.path)")
            return
        }

        let bounds = hostLayer.bounds
        // 0.40 → 0.52 (+30%) → 1.04 (×2, 2026-09-11). The hands are now taller
        // than the screen and that is the point: they read as two hands reaching
        // INTO the frame rather than two cut-outs sliding across it. The motion
        // is untouched — every other number here is derived from handHeight, so
        // doubling it moves the start/end positions with it.
        let handHeight = bounds.height * 1.04
        // Source images are square halves (512x1024 → aspect 0.5).
        let handWidth = handHeight * 0.5
        // Place the hand centre 1/5 of screen height below screen midpoint
        // (AppKit y grows upward, so subtract).
        let handY = bounds.midY - handHeight / 2 - bounds.height * 0.20

        // End positions: hands touching at the horizontal center.
        let leftEndX  = bounds.midX - handWidth
        let rightEndX = bounds.midX
        // Start positions: just off-screen at the edges.
        let leftStartX  = -handWidth
        let rightStartX = bounds.width

        // The container is added to the layer tree and OWNS both hands, so every
        // teardown path (cancelIfRunning, stopAllActiveEffects, the scheduled
        // fade below) removes the hands with it — they can't be left orphaned on
        // screen (the previous design tracked an empty off-tree wrapper while the
        // hands lived as siblings under host, so a stop cleared the tracker but
        // not the hands).
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        activeEffects["love-hands"] = container

        // 0.8, and on the two hand layers rather than on `container`: the heart
        // burst is a child of the same container, and it is the HANDS that
        // should let the desktop through, not the hearts. Fading out still works
        // — `fadeOutLoveHands` animates the container's opacity to 0 on top of
        // this, so 0.8 is the ceiling the fade starts from.
        let handOpacity: Float = 0.8

        let leftLayer = CALayer()
        leftLayer.frame = CGRect(x: leftEndX, y: handY, width: handWidth, height: handHeight)
        leftLayer.contents = leftCG
        leftLayer.contentsGravity = .resizeAspect
        leftLayer.opacity = handOpacity
        container.addSublayer(leftLayer)

        let rightLayer = CALayer()
        rightLayer.frame = CGRect(x: rightEndX, y: handY, width: handWidth, height: handHeight)
        rightLayer.contents = rightCG
        rightLayer.contentsGravity = .resizeAspect
        rightLayer.opacity = handOpacity
        container.addSublayer(rightLayer)

        let converge: CFTimeInterval = 2.7          // 3× slower than the original 0.9s
        let slideLeft = CABasicAnimation(keyPath: "position.x")
        slideLeft.fromValue = leftStartX + handWidth / 2
        slideLeft.toValue   = leftEndX + handWidth / 2
        slideLeft.duration = converge
        slideLeft.timingFunction = CAMediaTimingFunction(name: .easeOut)
        leftLayer.add(slideLeft, forKey: "slide")

        let slideRight = CABasicAnimation(keyPath: "position.x")
        slideRight.fromValue = rightStartX + handWidth / 2
        slideRight.toValue   = rightEndX + handWidth / 2
        slideRight.duration = converge
        slideRight.timingFunction = CAMediaTimingFunction(name: .easeOut)
        rightLayer.add(slideRight, forKey: "slide")

        // When the hands touch, spawn the heart burst.
        let meetingPoint = CGPoint(x: bounds.midX, y: bounds.midY - bounds.height * 0.20)
        let riseDuration: CFTimeInterval = 2.0
        let fadeDuration: CFTimeInterval = 0.6
        DispatchQueue.main.asyncAfter(deadline: .now() + converge) { [weak self, weak container] in
            guard let self = self, let container = container,
                  self.activeEffects["love-hands"] === container else { return }
            self.spawnLoveHearts(center: meetingPoint, rise: riseDuration, fadeOver: fadeDuration, parent: container)
        }

        // The hands now linger until the sfx (41_love_hearts.mp3) is almost over,
        // then fade out so they disappear together with the sound instead of on a
        // fixed timeline. An explicit/early tablet stop also clears them via
        // onStop → love-hands/stop → stopLoveHands.
        var soundDuration = 6.0
        if let url = SoundManager.shared.soundURL(for: "41_love_hearts.mp3") {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { soundDuration = CMTimeGetSeconds(d) }
        }
        let handsFadeAt = max(converge + 0.5, soundDuration - fadeDuration)
        DispatchQueue.main.asyncAfter(deadline: .now() + handsFadeAt) { [weak self, weak container] in
            guard let self = self, let container = container,
                  self.activeEffects["love-hands"] === container else { return }
            self.fadeOutLoveHands(container, over: fadeDuration)
        }

        if playSound {
            SoundManager.shared.play("41_love_hearts.mp3")
        }
    }

    func stopLoveHands() {
        SoundManager.shared.stop("41_love_hearts.mp3", fade: SoundManager.interruptFade)
        if let container = activeEffects["love-hands"] {
            fadeOutLoveHands(container)
        }
    }

    /// Fade the hands out (never an instant cut) and remove them once faded.
    /// Clears the tracker up front so a re-trigger can't be removed by an old
    /// timer, and so the disappearance is idempotent across the natural-end
    /// timer, an explicit tablet stop, and a re-press toggle.
    private func fadeOutLoveHands(_ container: CALayer, over fadeDuration: CFTimeInterval = 0.6) {
        if activeEffects["love-hands"] === container {
            activeEffects.removeValue(forKey: "love-hands")
        }
        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeDuration)
        container.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    /// 7 red hearts rise gently from `center` and diverge outward — modelled on
    /// the WebSocket emoji float (`spawnEmoji`) so the motion looks calm and
    /// continuous rather than spinny. Each heart picks its own pseudo-random
    /// direction, rise height, lateral drift, end scale and spawn delay so
    /// the swarm fans out without repeating the same arc.
    /// Parameters `rise`/`fadeOver` set the *target* duration; per-heart life
    /// is randomized ±15% around `rise + fadeOver` for organic spread.
    private func spawnLoveHearts(center: CGPoint, rise: CFTimeInterval, fadeOver: CFTimeInterval, parent: CALayer) {
        let bounds = hostLayer.bounds
        let heartCount = 7
        let baseSize: CGFloat = 70
        let nominalLife = rise + fadeOver

        for i in 0..<heartCount {
            // Per-heart divergent direction; jittered around the even slice so
            // adjacent hearts don't take exactly the same outward angle.
            let baseAngle = Double(i) / Double(heartCount) * 2.0 * Double.pi
            let direction = baseAngle + Double.random(in: -0.35...0.35)
            // Mostly vertical lift with a modest lateral component along the
            // chosen direction (eased outward, never overshooting).
            let lateralReach = bounds.width * CGFloat.random(in: 0.06...0.18)
            let riseHeight = bounds.height * CGFloat.random(in: 0.55...0.78)
            let endScale: CGFloat = CGFloat.random(in: 1.25...1.55)
            let duration: CFTimeInterval = nominalLife * Double.random(in: 0.85...1.15)
            let spawnDelay = Double.random(in: 0.0...0.30)
            // Low-frequency S-curve wobble layered on top of the linear drift —
            // matches `spawnEmoji`'s subtle wobble character.
            let wobblePhase = Double.random(in: 0.0...(2.0 * Double.pi))
            let wobbleAmp = bounds.width * CGFloat.random(in: 0.010...0.025)

            DispatchQueue.main.asyncAfter(deadline: .now() + spawnDelay) { [weak self] in
                // Don't spawn into a love-hands burst that was already stopped/faded
                // (the tracker is cleared up-front by fadeOutLoveHands).
                guard let self = self, self.activeEffects["love-hands"] === parent else { return }
                let layer = CATextLayer()
                layer.string = "❤️"
                layer.fontSize = baseSize
                layer.alignmentMode = .center
                layer.frame = CGRect(x: center.x - baseSize, y: center.y - baseSize, width: baseSize * 2, height: baseSize * 2)
                layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
                // Parent the heart to the tracked love-hands container (not hostLayer)
                // so stopping the effect fades/removes the hearts with the hands —
                // otherwise they keep rising after the sound stops.
                parent.addSublayer(layer)

                let dirCos = CGFloat(cos(direction))
                let path = CGMutablePath()
                path.move(to: center)
                let steps = 40
                for s in 1...steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let lateral = dirCos * lateralReach * t
                    let wobble = CGFloat(sin(wobblePhase + Double(t) * 2.0 * Double.pi)) * wobbleAmp
                    let x = center.x + lateral + wobble
                    let y = center.y + riseHeight * t
                    path.addLine(to: CGPoint(x: x, y: y))
                }
                let posAnim = CAKeyframeAnimation(keyPath: "position")
                posAnim.path = path
                posAnim.duration = duration
                posAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                posAnim.fillMode = .forwards
                posAnim.isRemovedOnCompletion = false
                layer.add(posAnim, forKey: "rise")

                let scale = CABasicAnimation(keyPath: "transform.scale")
                scale.fromValue = 1.0
                scale.toValue = endScale
                scale.duration = duration
                scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
                scale.fillMode = .forwards
                scale.isRemovedOnCompletion = false
                layer.add(scale, forKey: "grow")

                // Fade starts at 40% of the lifetime — matches spawnEmoji's
                // gentle melt-out.
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 1.0
                fade.toValue = 0.0
                fade.beginTime = CACurrentMediaTime() + duration * 0.4
                fade.duration = duration * 0.6
                fade.fillMode = .forwards
                fade.isRemovedOnCompletion = false
                layer.add(fade, forKey: "fade")

                DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.1) { [weak layer] in
                    layer?.removeFromSuperlayer()
                }
            }
        }
    }

    // MARK: - Star Wars Death Star slide (sound #55)

    /// The sphere's diameter as a fraction of screen height. Half again the
    /// 0.462 it used to be — the artwork was 40% of the screen tall but was a
    /// CROP of the sphere, so the sphere itself measured more than the picture.
    /// Stating the size as the sphere, not as the image, is what makes "half
    /// again bigger" a number anyone can check.
    private static let starWarsSphereHeight: CGFloat = 0.69

    /// How much of the artwork's height the sphere fills; the rest is the
    /// transparent margin that keeps the limb from being clipped. Re-cut the
    /// art and this is the one number to update — every size below is derived.
    private static let starWarsSphereFraction: CGFloat = 0.893

    /// Where the sphere comes to rest, as a fraction of the screen (its CENTRE,
    /// y-up). **Victor pointed at this spot** — he drew on the screen with
    /// ScreenBrush at 940×1460 of the retina's 3456×2234 and said "here is where
    /// the centre of the star goes" — so it is a measurement, not a taste call:
    /// don't "improve" it without asking. At the current 0.69 H sphere it sits
    /// low and left, its bottom edge grazing the floor of the screen and a
    /// comfortable margin off the left — clear of the corner it used to be
    /// welded into, which was the whole point.
    private static let starWarsRestPoint = CGPoint(x: 0.272, y: 0.347)

    /// How long the slide takes. The ask was "twice as fast"; the path is also
    /// ~2.5× longer now (corner → near the middle), so at double the old speed
    /// it would need 9.8 s and no longer fit under a 10 s clip. 6.5 s makes it
    /// **three times** the old speed and still leaves the last 3.5 s with the
    /// sphere simply hanging there — which is the better shape anyway: arriving
    /// on the final beat left no moment where the thing was just *present*.
    private static let starWarsSlideSeconds: CFTimeInterval = 6.5

    func showStarWars(playSound: Bool = true) {
        if cancelIfRunning("star-wars", sound: playSound ? "55_star_wars.mp3" : nil) { return }

        // Bundled. The old fallback to a stray copy in the user's download
        // folder is gone: it existed only while the asset was not yet
        // committed, and it made the effect depend on a folder the app has no
        // business reading.
        guard let pngURL = Bundle.module.url(forResource: "death-star", withExtension: "png"),
              let nsImage = NSImage(contentsOf: pngURL),
              let cg = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            overlayError("death-star.png missing from the bundle")
            return
        }

        let bounds = hostLayer.bounds
        let W = bounds.width
        let H = bounds.height
        // Size the SPHERE, then work back to the image it is drawn inside.
        let sphere = H * Self.starWarsSphereHeight
        let imgH = sphere / Self.starWarsSphereFraction
        let aspect = CGFloat(cg.width) / CGFloat(cg.height)
        let imgW = imgH * aspect

        // The artwork is a whole sphere now, so it can stop anywhere. It could
        // not before: the old PNG was cut off flat along its left and bottom
        // edges, and the only place those cuts are invisible is welded into the
        // screen's bottom-left corner — pull it even 10% inboard and the sphere
        // showed two straight slices. The missing lower-left limb was rebuilt
        // (radially extrapolated and darkened into shadow) so this position is
        // now a free choice rather than the one place the art allowed.
        let endPos = CGPoint(x: Self.starWarsRestPoint.x * W, y: Self.starWarsRestPoint.y * H)

        // It comes up the diagonal from outside the bottom-left corner, starting
        // exactly tangent to it: any further out and the first second of the
        // slide is spent on an empty screen (the old start wasted ~0.3 s even
        // after being tuned for it), any closer and it pops into existence.
        let reach = (endPos.x * endPos.x + endPos.y * endPos.y).squareRoot()
        let dir = reach > 0 ? CGPoint(x: endPos.x / reach, y: endPos.y / reach) : CGPoint(x: 0.83, y: 0.55)
        let radius = sphere / 2
        let startPos = CGPoint(x: -dir.x * radius, y: -dir.y * radius)

        let layer = CALayer()
        layer.contents = cg
        layer.bounds = CGRect(x: 0, y: 0, width: imgW, height: imgH)
        layer.contentsGravity = .resizeAspect
        layer.position = endPos        // model value matches the post-anim state
        hostLayer.addSublayer(layer)
        activeEffects["star-wars"] = layer

        // Sound is 10.08s; the slide finishes well inside it (see above).
        let soundDuration: CFTimeInterval = 10.0
        let slideDuration = Self.starWarsSlideSeconds

        let anim = CABasicAnimation(keyPath: "position")
        anim.fromValue = NSValue(point: startPos)
        anim.toValue = NSValue(point: endPos)
        anim.duration = slideDuration
        anim.timingFunction = CAMediaTimingFunction(name: .linear)   // constant speed
        anim.fillMode = .forwards
        anim.isRemovedOnCompletion = false
        layer.add(anim, forKey: "slide")

        if playSound {
            SoundManager.shared.play("55_star_wars.mp3")
        }
        // ALWAYS self-stop when the sound ends — including the silent tablet
        // path (playSound: false), whose /sound/stopped → star-wars/stop is
        // best-effort (lost on relay/network drops) and previously the ONLY
        // thing standing between the Death Star and staying parked forever.
        // Identity-guarded so an old run's timer can't kill a newer run.
        DispatchQueue.main.asyncAfter(deadline: .now() + soundDuration + 0.3) { [weak self, weak layer] in
            guard let self, let layer, self.activeEffects["star-wars"] === layer else { return }
            self.stopStarWars()
        }
    }

    func stopStarWars() {
        _ = cancelIfRunning("star-wars", sound: "55_star_wars.mp3")
    }

    // Pending spawn (and cleanup) work items for the current spiral-hearts
    // emission, kept so an explicit stop — the saxophone sound stopped on the
    // tablet — can cancel the not-yet-fired ones. Without this, hearts keep
    // appearing for the full sound length even after it's silenced.
    private var spiralHeartSpawns: [DispatchWorkItem] = []

    func showSpiralHearts() {
        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Re-press: clear any in-flight emission so containers don't stack.
        clearSpiralHearts(fadeDuration: 0)

        // Emit hearts for as long as the tablet's sfx (42_saxophone.mp3) plays,
        // so the animation lasts exactly the length of the sound.
        var sfxDuration = 5.0
        if let url = SoundManager.shared.soundURL(for: "42_saxophone.mp3") {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { sfxDuration = CMTimeGetSeconds(d) }
        }
        let spawnRate = 6.0  // hearts per second (matches the original 30 over 5s)
        let total = max(1, Int((spawnRate * sfxDuration).rounded()))

        // All hearts live in one container so a stop can fade them out together
        // and drop them wholesale.
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        activeEffects["spiral-hearts"] = container

        // The cursor stays a pulsing red heart for the whole emission.
        startHeartCursor(activeFor: sfxDuration)

        spiralHeartSpawns = []
        for i in 0..<total {
            let delay = (Double(i) / Double(total)) * sfxDuration
            let work = DispatchWorkItem { [weak self] in self?.spawnSpiralHeart(into: container) }
            spiralHeartSpawns.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        // After the last heart has finished rising (~4.5s max life) drop the
        // now-empty container so it doesn't accumulate across re-presses.
        let cleanup = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.activeEffects["spiral-hearts"] === container {
                self.activeEffects.removeValue(forKey: "spiral-hearts")
            }
            container.removeFromSuperlayer()
        }
        spiralHeartSpawns.append(cleanup)
        DispatchQueue.main.asyncAfter(deadline: .now() + sfxDuration + 5.0, execute: cleanup)
    }

    /// Stop the spiral-hearts emission now: cancel pending spawns, drop the
    /// heart cursor, and fade out the hearts already on screen. Wired to
    /// "spiral-hearts/stop" (the saxophone sound stopped on the tablet).
    func stopSpiralHearts() {
        clearSpiralHearts(fadeDuration: 0.5)
    }

    private func clearSpiralHearts(fadeDuration: CFTimeInterval) {
        spiralHeartSpawns.forEach { $0.cancel() }
        spiralHeartSpawns = []
        stopHeartCursor()
        guard let container = activeEffects["spiral-hearts"] else { return }
        activeEffects.removeValue(forKey: "spiral-hearts")
        guard fadeDuration > 0 else { container.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeDuration)
        container.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    /// The pulsing cursor heart's scale **at this instant of its beat**, read off
    /// the presentation layer (the model layer knows nothing about where an
    /// in-flight animation has got to). 1.0 when there is no cursor heart, which
    /// is the case for `/effect/spiral-hearts` fired straight from the menu.
    private func heartCursorLiveScale() -> CGFloat {
        guard let presented = _heartCursorLayer?.presentation() else { return 1.0 }
        let t = CATransform3DGetAffineTransform(presented.transform)
        let scale = sqrt(abs(t.a * t.d - t.b * t.c))
        return scale > 0.01 ? scale : 1.0
    }

    private func spawnSpiralHeart(into container: CALayer) {
        let bounds = hostLayer.bounds
        // A heart that floats up is a CLONE of the pulsing cursor heart, not a
        // new heart of its own: same glyph size, and it is born at the exact
        // scale the pulse happens to be at on that frame. It used to be a random
        // 44…80 pt glyph that popped from 0.6 to 1.5 while fading up from
        // transparent — which read as hearts *appearing near* the cursor rather
        // than peeling off it. (The two ranges happen to overlap: the cursor
        // heart's 86.4 pt across a 0.8…1.35 beat spans the same sizes the random
        // range used to, so the variety survived the change.)
        let fontSize = Self.heartCursorFontSize
        let birthScale = heartCursorLiveScale()
        // The layer box must be taller than the glyph or CATextLayer clips the
        // heart's bottom tip (the emoji line box is ~1.18× the font size).
        let box = fontSize * Self.heartCursorBoxRatio
        // …and it rises from where the pulsing heart actually is, which is the
        // presentation position when there is one and the cursor otherwise.
        let origin = _heartCursorLayer?.presentation()?.position ?? mousePointInHostLayer()
        let duration = Double.random(in: 3.2...4.5)

        let layer = CATextLayer()
        layer.string = "❤️"
        layer.fontSize = fontSize
        layer.alignmentMode = .center
        // anchorPoint stays at its (0.5, 0.5) default, so position == centre.
        layer.frame = CGRect(x: origin.x - box / 2, y: origin.y - box / 2, width: box, height: box)
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        container.addSublayer(layer)

        // Travel from the spawn point up to (just past) the top edge.
        let riseHeight = (bounds.height - origin.y) + box * 1.5
        // A per-heart net sideways drift fans the hearts out in various
        // directions — mostly up, some up-left, some up-right — while the
        // sine term layered on top gives each one its vertical spiral.
        let drift = CGFloat.random(in: -0.18...0.18) * bounds.width
        let amplitude = CGFloat.random(in: 24...60)
        let frequency = Double.random(in: 1.5...3.0)  // full sine cycles over the rise
        let phase = Double.random(in: 0...(2 * .pi))
        let direction: CGFloat = Bool.random() ? 1 : -1

        let steps = 60
        let path = CGMutablePath()
        path.move(to: origin)
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            let y = origin.y + riseHeight * CGFloat(t)
            let xBase = origin.x + drift * CGFloat(t)
            let xWobble = direction * amplitude * CGFloat(sin(phase + t * frequency * 2 * .pi))
            path.addLine(to: CGPoint(x: xBase + xWobble, y: y))
        }

        var animations: [CAAnimation] = []

        let pathAnim = CAKeyframeAnimation(keyPath: "position")
        pathAnim.path = path
        pathAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animations.append(pathAnim)

        // Held at the scale it was born at — no pop-in. The 0.6 → 1.5 grow this
        // replaces was the other half of "a new heart appears": it made the
        // clone visibly smaller than the heart it came off for the first 0.18 s.
        let hold = CAKeyframeAnimation(keyPath: "transform.scale")
        hold.values = [birthScale, birthScale]
        hold.keyTimes = [0.0, 1.0]
        hold.timingFunctions = [CAMediaTimingFunction(name: .linear)]
        animations.append(hold)

        // Slight rotation wobble — adds to the spiral feel.
        let rotate = CABasicAnimation(keyPath: "transform.rotation")
        rotate.fromValue = -0.18 * direction
        rotate.toValue = 0.18 * direction
        rotate.autoreverses = true
        rotate.repeatCount = .greatestFiniteMagnitude
        rotate.duration = Double.random(in: 0.5...0.9)
        animations.append(rotate)

        // Fully opaque from frame one — it IS the pulsing heart, and a thing that
        // detaches from something solid cannot start out see-through. Only the
        // fade OUT survives (it was `[0, 1, 1, 0]` over `[0, 0.08, 0.55, 1]`),
        // because a heart still has to leave at the top of its rise.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0.0, 0.55, 1.0]
        animations.append(fade)

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in layer?.removeFromSuperlayer() }
        layer.add(group, forKey: "spiralHeart")
        CATransaction.commit()
    }

    // MARK: - ❄️ Snow (tile #46, Michael Bublé — "It's Beginning to Look a Lot Like Christmas")

    /// Flakes per second while the clip plays.
    private static let snowSpawnRate: Double = 16
    /// Flakes released in the opening cascade (see `showSnow`).
    private static let snowSeedCount = 26
    /// How long a landed flake lingers on the floor before it has melted away.
    private static let snowSettleSeconds: Double = 1.4
    private static let snowFadeSeconds: CFTimeInterval = 1.0
    /// Seconds a flake takes to cross the whole screen, far (`0` depth) to near.
    /// Faster than the 9.5…5.0 s this started with, and deliberately so: the
    /// flakes are now twice the size, and at the old speed a big flake drifting
    /// that slowly read as floating rather than falling. It is also what buys
    /// the descent guarantee below inside a 10.5 s song.
    private static let snowFallSecondsFar: Double = 6.5
    private static let snowFallSecondsNear: Double = 3.5

    /// **New flakes are released for the WHOLE clip** — there is no quiet tail
    /// (Victor, 2026-09-09: "să tot cadă fulgi noi, să nu se oprească din
    /// cădere"). Emission used to stop `snowFallSecondsFar × 2/3` (4.3 s) before
    /// the end so that every flake was guaranteed to reach the lower third of
    /// the screen before anything melted it. The guarantee was real, but the
    /// price was the last 4 s of a 10.5 s song: no flake entering at the top,
    /// the sky visibly emptying downward, one wave of snow rather than snowfall.
    /// The end is now the container fade (`snowFadeSeconds`), which takes the
    /// stragglers with it wherever they happen to be — a flake fading with the
    /// whole picture reads as the effect ending, not as a flake dissolving.
    /// Pending spawn (and self-stop) work items for the current snowfall, kept so
    /// an explicit stop — the song stopped on the tablet — can cancel the ones
    /// that haven't fired yet. Same pattern as the spiral hearts: without this the
    /// sky keeps filling for the full clip length after it has been silenced.
    private var snowSpawns: [DispatchWorkItem] = []

    /// ❄️ Snow falls over the whole desktop for as long as the Bublé clip plays,
    /// **new flakes entering the top edge the entire time** — the fall never
    /// thins out into a last wave with an empty sky above it.
    /// Drawn, not emoji: ❄️ renders as the system's blue-tinted glyph, and what is
    /// being asked for here is *white snow* over whatever is on screen.
    func showSnow() {
        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Re-press: clear any in-flight snowfall so containers don't stack.
        clearSnow(fadeDuration: 0)

        // Snow for exactly as long as the tablet's clip plays.
        var sfxDuration = 10.5
        if let url = SoundManager.shared.soundURL(for: "46_michael_buble.mp3") {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { sfxDuration = CMTimeGetSeconds(d) }
        }

        // One container so a stop can fade the whole snowfall out together.
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        activeEffects["snow"] = container

        // EVERY flake enters from above the top edge — none is ever dropped in
        // mid-screen, which reads as flakes materialising out of nowhere rather
        // than as snow falling. The opening cascade is therefore stacked *above*
        // the screen instead: a batch released at staggered heights over the top
        // edge, so the sky fills within the first couple of seconds while each
        // flake still makes the whole journey down.
        // Stacked at most 0.55 screens up, not 0.9: a slow flake starting a
        // whole screen above the top spends four seconds merely arriving, and
        // then cannot reach the lower third before the song ends.
        for _ in 0..<Self.snowSeedCount {
            spawnSnowflake(into: container, startAbove: CGFloat.random(in: 0...0.55) * bounds.height)
        }

        snowSpawns = []
        // Flakes keep entering the top edge until the very last moment of the
        // clip — see the note on the emission window above.
        let emitFor = max(0.5, sfxDuration)
        let total = max(1, Int((Self.snowSpawnRate * emitFor).rounded()))
        for i in 0..<total {
            let delay = (Double(i) / Double(total)) * emitFor
            let work = DispatchWorkItem { [weak self, weak container] in
                guard let self, let container else { return }
                self.spawnSnowflake(into: container)
            }
            snowSpawns.append(work)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }

        // The snowfall lasts EXACTLY as long as the song: the melt starts on the
        // clip's last moment, so the desktop is clear a beat after the music has
        // stopped. This is also the authoritative self-stop required by the
        // lifecycle rule — the tablet's `/sound/stopped` → `snow/stop` is
        // best-effort and is lost on a flaky venue network, which would otherwise
        // leave it snowing forever. Identity-guarded so an old run's timer can't
        // kill a newer run.
        let selfStop = DispatchWorkItem { [weak self, weak container] in
            guard let self, let container, self.activeEffects["snow"] === container else { return }
            self.clearSnow(fadeDuration: Self.snowFadeSeconds)
        }
        snowSpawns.append(selfStop)
        DispatchQueue.main.asyncAfter(deadline: .now() + sfxDuration, execute: selfStop)
    }

    /// Stop the snowfall now: cancel pending flakes and melt away the ones on
    /// screen. Wired to "snow/stop" (the song stopped on the tablet).
    func stopSnow() {
        clearSnow(fadeDuration: Self.snowFadeSeconds)
    }

    private func clearSnow(fadeDuration: CFTimeInterval) {
        snowSpawns.forEach { $0.cancel() }
        snowSpawns = []
        guard let container = activeEffects["snow"] else { return }
        activeEffects.removeValue(forKey: "snow")
        guard fadeDuration > 0 else { container.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeDuration)
        container.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    /// One flake, falling from above the top edge to the floor, where it settles
    /// briefly and melts. `startAbove` stacks it that much FURTHER above the top
    /// edge (used by the opening cascade) — it always enters through the top, and
    /// the fall speed is held constant so starting higher just means entering
    /// later, not falling faster.
    private func spawnSnowflake(into container: CALayer, startAbove: CGFloat = 0) {
        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // ONE number carries the depth — size, speed, brightness and how wide it
        // swings all come off it — so a flake can never read as a contradiction
        // (big but distant, tiny but racing). 0 = far, 1 = near.
        let depth = CGFloat.random(in: 0...1)
        // 10…40 pt — twice the 5…20 this started at. At the old size the flakes
        // read as specks on a projected screen from the back of a room, which is
        // the only place this is ever watched from.
        let radius = 10 + depth * 30
        let brightness = Float(0.35 + depth * 0.55)
        let fallSeconds = Self.snowFallSecondsFar
            - Double(depth) * (Self.snowFallSecondsFar - Self.snowFallSecondsNear)

        let flake = CAShapeLayer()
        flake.path = Self.snowflakePath(radius: radius)
        flake.bounds = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        flake.strokeColor = NSColor.white.cgColor
        flake.fillColor = nil
        flake.lineWidth = max(1.0, radius * 0.13)
        flake.lineCap = .round
        flake.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        // The halo is what makes it read as snow rather than as line art.
        flake.shadowColor = NSColor.white.cgColor
        flake.shadowRadius = radius * 0.55
        flake.shadowOpacity = 0.9
        flake.shadowOffset = .zero
        flake.masksToBounds = false

        // Falling = decreasing y (hostLayer is not geometry-flipped).
        let floorY = radius * 0.6
        let startY = bounds.height + radius * 2 + startAbove
        let startX = CGFloat.random(in: -radius...(bounds.width + radius))

        // A net sideways drift (a draught across the room) plus a sine sway, both
        // scaled by depth so near flakes swing wider than distant ones.
        let drift = CGFloat.random(in: -0.06...0.06) * bounds.width * (0.4 + depth)
        let amplitude = (10 + depth * 26) * CGFloat.random(in: 0.6...1.4)
        let frequency = Double.random(in: 0.8...2.0)   // full sine cycles over the fall
        let phase = Double.random(in: 0...(2 * .pi))

        let steps = 48
        var points: [NSValue] = []
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let y = startY + (floorY - startY) * t
            let x = startX + drift * t
                + amplitude * CGFloat(sin(phase + Double(t) * frequency * 2 * .pi))
            points.append(NSValue(point: NSPoint(x: x, y: y)))
        }

        // Constant fall speed: `fallSeconds` is the time to cross the screen, so a
        // flake stacked higher simply takes proportionally longer to arrive.
        let descent = max(0.4, fallSeconds * Double((startY - floorY) / bounds.height))
        let total = descent + Self.snowSettleSeconds
        let landed = descent / total                    // keyTime at which it touches down

        flake.position = points[0].pointValue
        container.addSublayer(flake)

        var animations: [CAAnimation] = []

        // The descent occupies the first `landed` of the timeline; the repeated
        // final point holds the flake on the floor while it melts.
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = points + [points[steps]]
        var keyTimes = (0...steps).map { NSNumber(value: Double($0) / Double(steps) * landed) }
        keyTimes.append(1.0)
        move.keyTimes = keyTimes
        move.calculationMode = .linear
        animations.append(move)

        // Slow tumble. Only the rotation is animated (the size is baked into the
        // path), so nothing fights over `transform`.
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = (Bool.random() ? 1.0 : -1.0) * Double.random(in: 0.4...1.6) * 2 * .pi
        spin.duration = total
        animations.append(spin)

        // Fade in as it enters, hold, then melt away once it has landed.
        let fadeIn = min(0.06, landed * 0.5)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, brightness, brightness, 0.0]
        fade.keyTimes = [0.0, NSNumber(value: fadeIn), NSNumber(value: landed), 1.0]
        animations.append(fade)

        let group = CAAnimationGroup()
        group.animations = animations
        group.duration = total
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak flake] in flake?.removeFromSuperlayer() }
        flake.add(group, forKey: "snowflake")
        CATransaction.commit()
    }

    /// A six-spoke snowflake centred on (0,0): each arm carries two pairs of
    /// branches, which is the least detail that still reads as a snowflake rather
    /// than as an asterisk.
    private static func snowflakePath(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        for i in 0..<6 {
            let angle = Double(i) * .pi / 3
            let tip = CGPoint(x: cos(angle) * Double(r), y: sin(angle) * Double(r))
            path.move(to: .zero)
            path.addLine(to: tip)
            for (along, length) in [(0.45, 0.34), (0.72, 0.24)] {
                let base = CGPoint(x: tip.x * along, y: tip.y * along)
                for side in [1.0, -1.0] {
                    let branch = angle + side * (.pi / 4)
                    path.move(to: base)
                    path.addLine(to: CGPoint(x: base.x + cos(branch) * Double(r) * length,
                                             y: base.y + sin(branch) * Double(r) * length))
                }
            }
        }
        return path
    }

    // MARK: - ⛈️ Storm (tile #20 — clouds roll in, the desktop darkens, it rains)

    /// The storm's self-stop, kept so an explicit stop (the clip was stopped on
    /// the tablet, or a stop-all) can cancel the one that hasn't fired yet —
    /// otherwise it would fire later into a detached container and, worse, clear
    /// the key out from under whatever ran next.
    private var stormSelfStop: DispatchWorkItem?

    /// Drops the rain. One repeating timer releasing a handful of layers a tick,
    /// rather than a `CAEmitterLayer`: the emitter expressed its direction as
    /// `emissionLongitude`, an angle whose zero and whose sign are a convention
    /// rather than a coordinate, and on this layer it came out sideways — a
    /// dense band of streaks sliding LEFT under the cloud base instead of rain
    /// reaching the floor. A drop now flies between two POINTS (`RainStorm.Drop`),
    /// which cannot be misread and can be asserted without opening a window.
    private var stormRainTimer: Timer?

    /// ⛈️ Four clouds slide in from both sides onto the top edge, the desktop
    /// dims under them, and rain falls out of the cloud base for as long as the
    /// clip plays — with lightning on the thunder rolls.
    ///
    /// One container holds all four parts (dark, clouds, flash, rain) so the
    /// end is a single fade and `stopAllActiveEffects` needs no special case
    /// beyond cancelling the pending self-stop. The layer ORDER is the whole
    /// picture: the dark goes down first because it is what the clouds and the
    /// rain are seen *against*, and the rain goes on top because drops in front
    /// of the gloom are the only ones that read from the back of a room.
    func showStorm() {
        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        // Re-press: tear the old one down at once so two skies don't stack.
        clearStorm(fadeDuration: 0)

        // The storm lasts exactly as long as the tablet's clip.
        var clip = RainStorm.fallbackDuration
        if let url = SoundManager.shared.soundURL(for: RainStorm.soundName) {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { clip = CMTimeGetSeconds(d) }
        }
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        activeEffects["storm"] = container

        // 1. The gloom. Model value is the END state with a `.forwards` ramp on
        // top, so nothing snaps back to clear if the animation is ever removed.
        let dark = CALayer()
        dark.frame = bounds
        dark.backgroundColor = NSColor.black.cgColor
        dark.opacity = RainStorm.darkenOpacity
        container.addSublayer(dark)
        let dim = CABasicAnimation(keyPath: "opacity")
        dim.fromValue = 0
        dim.toValue = RainStorm.darkenOpacity
        dim.duration = RainStorm.darkenSeconds
        dim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dark.add(dim, forKey: "stormDim")

        // 2. The clouds, each sliding in from its own side after its own delay.
        // `position.x` rather than `frame`, the same convention the wazzup mask
        // and the claude-peek slide use — CALayer does not animate `frame`
        // cleanly — and `.backwards` fill is what parks a delayed cloud
        // off-screen instead of showing it at its destination until its turn.
        for (index, arrival) in RainStorm.arrivals(in: bounds).enumerated() {
            guard let image = RainStorm.cloudImage(index: index, size: arrival.rest.size, scale: scale) else { continue }
            let pad = arrival.rest.width * RainStorm.spritePadding
            let layer = CALayer()
            layer.frame = arrival.rest.insetBy(dx: -pad, dy: -pad)
            layer.contents = image
            layer.contentsGravity = .resize
            container.addSublayer(layer)

            // One axis only, chosen by the edge it comes in over: the inner
            // clouds DROP out of the top, the outer ones slide in from the
            // sides. A cloud arriving diagonally would be the only thing on
            // screen moving in two directions at once.
            let axis = arrival.isVertical ? "position.y" : "position.x"
            let from = arrival.isVertical
                ? layer.position.y + (arrival.start.minY - arrival.rest.minY)
                : layer.position.x + (arrival.start.minX - arrival.rest.minX)
            let slide = CABasicAnimation(keyPath: axis)
            slide.fromValue = from
            slide.toValue = arrival.isVertical ? layer.position.y : layer.position.x
            slide.duration = RainStorm.cloudSlideSeconds
            slide.beginTime = CACurrentMediaTime() + arrival.delay
            slide.timingFunction = CAMediaTimingFunction(name: .easeOut)
            slide.fillMode = .backwards
            layer.add(slide, forKey: "stormSlide")

            // …and it never quite settles. ADDITIVE, on `position` rather than
            // `position.x`, and beginning only once the slide has landed: the
            // two would otherwise both be driving the same property, and an
            // additive delta on top of a resting model value is the one form
            // that cannot fight it. Removed-on-completion is left off — the sway
            // repeats for the rest of the clip and the container fade takes it.
            let drift = RainStorm.drift(for: index, in: bounds)
            let sway = CABasicAnimation(keyPath: "position")
            sway.fromValue = NSValue(point: .zero)
            sway.toValue = NSValue(point: NSPoint(x: drift.dx, y: drift.dy))
            sway.duration = drift.seconds
            sway.beginTime = CACurrentMediaTime() + arrival.delay + RainStorm.cloudSlideSeconds
            sway.autoreverses = true
            sway.repeatCount = .greatestFiniteMagnitude
            sway.isAdditive = true
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(sway, forKey: "stormDrift")
        }

        // 3. Lightning, one stutter per thunder roll in the clip. Above the
        // clouds: a flash that lit the desktop but not the sky it came out of
        // would read as a monitor glitch.
        let flash = CALayer()
        flash.frame = bounds
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        container.addSublayer(flash)
        for onset in RainStorm.thunderOnsets where onset + RainStorm.flashSeconds < clip {
            let strike = CAKeyframeAnimation(keyPath: "opacity")
            strike.values = RainStorm.flashOpacities
            strike.keyTimes = RainStorm.flashKeyTimes
            strike.duration = RainStorm.flashSeconds
            strike.beginTime = CACurrentMediaTime() + onset
            flash.add(strike, forKey: "stormFlash\(onset)")
        }

        // 4. The rain, ramping up rather than switching on: the tick rate is
        // fixed and the number of drops it releases is what grows, so the sky
        // is dry until there are clouds to rain out of and the downpour then
        // builds. Drops go in a sublayer of their own so they sit ABOVE the
        // flash and the clouds — only drops in front of the gloom read from the
        // back of a room.
        let rain = CALayer()
        rain.frame = bounds
        container.addSublayer(rain)
        if let dropImage = RainStorm.dropImage(scale: scale) {
            let started = Date()
            let timer = Timer.scheduledTimer(withTimeInterval: 1 / RainStorm.dropSpawnHz, repeats: true) { [weak self, weak rain] timer in
                guard let self, let rain, self.activeEffects["storm"] === container else {
                    timer.invalidate()
                    return
                }
                let elapsed = Date().timeIntervalSince(started)
                guard elapsed >= RainStorm.rainLeadIn else { return }
                let ramp = min(1, (elapsed - RainStorm.rainLeadIn) / RainStorm.rainRampSeconds)
                let perTick = RainStorm.dropsPerSecond / RainStorm.dropSpawnHz * ramp
                // The fractional part is spent as a probability, or a light
                // ramp would round to zero drops on every tick and the rain
                // would start abruptly at half strength instead of building.
                var count = Int(perTick)
                if Double.random(in: 0..<1) < perTick - Double(count) { count += 1 }
                for _ in 0..<count {
                    self.spawnRainDrop(into: rain, bounds: bounds, image: dropImage, scale: scale)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            stormRainTimer = timer
        }

        overlayInfo(String(format: "⛈️ storm: %d clouds in over %.1fs, rain from %.1fs, %.1fs clip",
                           RainStorm.cloudCount, RainStorm.cloudSlideSeconds, RainStorm.rainLeadIn, clip))

        // The authoritative end, per the self-termination rule: the tablet's
        // `/sound/stopped` → `storm/stop` is best-effort and is lost on a flaky
        // venue network, which would otherwise leave the desktop under a
        // permanent downpour. Identity-guarded so an old run's timer cannot kill
        // a newer one.
        let selfStop = DispatchWorkItem { [weak self, weak container] in
            guard let self, let container, self.activeEffects["storm"] === container else { return }
            self.clearStorm(fadeDuration: RainStorm.fadeOutSeconds)
        }
        stormSelfStop = selfStop
        DispatchQueue.main.asyncAfter(deadline: .now() + clip, execute: selfStop)
    }

    /// One drop, falling from the cloud base to just past the bottom edge.
    ///
    /// The streak is ROTATED to lie along its own path. A vertical sprite
    /// travelling at an angle reads as a drop sliding sideways rather than
    /// leaning into a wind — which was half of what was wrong with the emitter
    /// this replaced.
    private func spawnRainDrop(into container: CALayer, bounds: CGRect, image: CGImage, scale: CGFloat) {
        let drop = RainStorm.randomDrop(in: bounds)
        let layer = CALayer()
        layer.bounds = CGRect(origin: .zero, size: drop.size)
        layer.position = drop.start
        layer.contents = image
        layer.contentsScale = scale
        layer.opacity = drop.opacity
        layer.transform = CATransform3DMakeRotation(drop.angle, 0, 0, 1)
        container.addSublayer(layer)

        let fall = CABasicAnimation(keyPath: "position")
        fall.fromValue = NSValue(point: drop.start)
        fall.toValue = NSValue(point: drop.end)
        fall.duration = drop.seconds
        // Linear, and deliberately so: over two thirds of a second the
        // acceleration of real rain is invisible, while an ease of any kind is
        // not — it reads as the drop slowing down near the floor.
        fall.timingFunction = CAMediaTimingFunction(name: .linear)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in layer?.removeFromSuperlayer() }
        layer.add(fall, forKey: "stormDropFall")
        CATransaction.commit()
    }

    /// Wired to `storm/stop` — the clip stopped on the tablet.
    func stopStorm() {
        clearStorm(fadeDuration: RainStorm.fadeOutSeconds)
    }

    private func clearStorm(fadeDuration: CFTimeInterval) {
        stormSelfStop?.cancel()
        stormSelfStop = nil
        // Before the container goes: a repeating timer holding a reference to a
        // detached layer would keep dropping rain into nothing for as long as
        // the app runs.
        stormRainTimer?.invalidate()
        stormRainTimer = nil
        guard let container = activeEffects["storm"] else { return }
        activeEffects.removeValue(forKey: "storm")
        guard fadeDuration > 0 else { container.removeFromSuperlayer(); return }
        CATransaction.begin()
        CATransaction.setAnimationDuration(fadeDuration)
        container.opacity = 0
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + fadeDuration) { [weak container] in
            container?.removeFromSuperlayer()
        }
    }

    /// Current mouse position expressed in hostLayer-local coordinates,
    /// clamped to the built-in screen (reuses the heartbeat anchor mapping).
    private func mousePointInHostLayer() -> CGPoint {
        let bounds = hostLayer.bounds
        let anchor = Self.layerAnchor(forGlobalMouse: NSEvent.mouseLocation,
                                      panelOrigin: hostLayer.bounds.origin,
                                      hostLayer: hostLayer)
        return CGPoint(x: anchor.x * bounds.width, y: anchor.y * bounds.height)
    }

    /// `CGDisplayHideCursor` normally takes effect only while the calling app is
    /// frontmost. Our overlay floats over whatever app the user is actually in,
    /// so by default the real arrow keeps showing next to the heart. The window
    /// server has long honoured a per-connection `SetsCursorInBackground` flag
    /// that lifts that restriction; it's private/undocumented but has been stable
    /// for ~15 years and this app isn't sandboxed. Resolved via dlsym so a future
    /// macOS that drops the symbols degrades to "cursor visible" rather than
    /// failing to launch. Runs once (lazy static); the flag never needs clearing
    /// — it only changes what hide/show mean, and a process exit/crash releases
    /// the hide automatically with the window-server connection.
    private static let _backgroundCursorHidingArmed: Bool = {
        typealias DefaultConnFn = @convention(c) () -> Int32
        typealias SetPropFn = @convention(c) (Int32, Int32, CFString, CFTypeRef) -> Int32
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)  // RTLD_DEFAULT
        guard let connSym = dlsym(rtldDefault, "_CGSDefaultConnection"),
              let propSym = dlsym(rtldDefault, "CGSSetConnectionProperty") else { return false }
        let defaultConnection = unsafeBitCast(connSym, to: DefaultConnFn.self)
        let setConnectionProperty = unsafeBitCast(propSym, to: SetPropFn.self)
        let cid = defaultConnection()
        _ = setConnectionProperty(cid, cid, "SetsCursorInBackground" as CFString, kCFBooleanTrue)
        return true
    }()

    private static func armBackgroundCursorHiding() { _ = _backgroundCursorHidingArmed }

    /// Glyph size of the pulsing cursor heart: 108 (itself 2× the original)
    /// **× 0.8** since 2026-09-11 — Victor wanted it smaller without losing the
    /// beat. The pulse is a `transform.scale` animation, so shrinking the glyph
    /// leaves both the rhythm (0.45 s, autoreversed) and the amplitude *ratio*
    /// (0.8 ↔ 1.35) exactly as they were.
    ///
    /// It is `static` because the hearts that float up are **clones of it**
    /// (`spawnSpiralHeart`) and there must be one number, not two that drift.
    static let heartCursorFontSize: CGFloat = 108 * 0.8
    /// Headroom around the glyph so the heart's bottom tip isn't clipped — the
    /// emoji line box is ~1.18× the font size.
    static let heartCursorBoxRatio: CGFloat = 1.2

    /// Float a pulsing red heart centred ON the mouse cursor for `seconds`,
    /// hiding the real system cursor so only the heart marks the pointer.
    /// Re-calling while active just extends the deadline.
    private func startHeartCursor(activeFor seconds: CFTimeInterval) {
        _heartCursorActiveUntil = CACurrentMediaTime() + seconds
        guard _heartCursorLayer == nil else { return }  // already running; deadline extended above

        let size = Self.heartCursorFontSize
        let box = size * Self.heartCursorBoxRatio
        let heart = CATextLayer()
        heart.string = "❤️"
        heart.fontSize = size
        heart.alignmentMode = .center
        heart.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        heart.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        heart.position = mousePointInHostLayer()   // centred on the pointer, not above it
        CATransaction.commit()
        hostLayer.addSublayer(heart)
        _heartCursorLayer = heart

        // The heart now sits ON the pointer, so hide the real cursor for the
        // emission — only the beating heart marks where the mouse is. The arm
        // step lifts the "frontmost app only" restriction so the hide also works
        // while the user is in another app (the common case for our overlay).
        // NSCursor covers the case where we ARE the active app. Balanced in
        // stopHeartCursor.
        if !_heartCursorHidSystemCursor {
            Self.armBackgroundCursorHiding()
            NSCursor.hide()
            CGDisplayHideCursor(CGMainDisplayID())
            _heartCursorHidSystemCursor = true
        }

        // Beat: scale big↔small forever (until the heart is removed).
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.8
        pulse.toValue = 1.35
        pulse.duration = 0.45
        pulse.autoreverses = true
        pulse.repeatCount = .greatestFiniteMagnitude
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        heart.add(pulse, forKey: "cursorPulse")

        // Follow the mouse; auto-stop once the deadline passes.
        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self = self else { t.invalidate(); return }
            if CACurrentMediaTime() >= self._heartCursorActiveUntil {
                self.stopHeartCursor()
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self._heartCursorLayer?.position = self.mousePointInHostLayer()
            CATransaction.commit()
        }
        _heartCursorTimer = timer
    }

    private func stopHeartCursor() {
        _heartCursorTimer?.invalidate()
        _heartCursorTimer = nil
        _heartCursorLayer?.removeFromSuperlayer()
        _heartCursorLayer = nil
        // Restore the real cursor (balances the hide in startHeartCursor). Guarded
        // so a spurious stop can't unbalance the hide count and force-show it.
        if _heartCursorHidSystemCursor {
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            _heartCursorHidSystemCursor = false
        }
    }

    func startPulseOverlay(playSound: Bool = true) {
        if !pulseRunning { showPulse(playSound: playSound) }
    }

    func stopPulseOverlay() {
        if pulseRunning { _stopPulse() }
    }

    // MARK: - Pulse stop (called when button pressed while running)

    private func _stopPulse() {
        guard pulseRunning else { return }
        pulseRunning = false
        SoundManager.shared.stop("15_flatline.mp3", fade: SoundManager.interruptFade)
        let dim = _pulseDimLayer
        let grid = _pulseGridLayer
        let ecg = _pulseEcgLayer
        _pulseDimLayer = nil
        _pulseGridLayer = nil
        _pulseEcgLayer = nil
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            dim?.removeFromSuperlayer()
            grid?.removeFromSuperlayer()
            ecg?.removeFromSuperlayer()
        }
        for layer in [dim, grid, ecg].compactMap({ $0 }) {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = 1; fadeOut.toValue = 0
            fadeOut.duration = 0.5
            fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "fadeOut")
        }
        CATransaction.commit()
    }

    // MARK: - Fire alarm GIF (bottom-left corner)

    func showFireAlarm(playSound: Bool = true) {
        if cancelIfRunning("fire-alarm", sound: playSound ? "65_school_bell.mp3" : nil) { return }

        guard let url = Bundle.module.url(forResource: "fire-alarm", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("fire-alarm.gif not found")
            return
        }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var totalDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif  = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.05
            totalDuration += delay
        }

        let bounds = hostLayer.bounds
        // Size: ~31% of screen width (26% × 1.2 — grown 20% toward interior per user request)
        let size = bounds.width * 0.312
        // Bottom-left corner with small margin
        let margin: CGFloat = 20
        let x = margin
        let y = margin  // y=0 is bottom in flipped coordinates

        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: x, y: y, width: size, height: size)
        gifLayer.contentsGravity = .resizeAspect
        if let first = images.first { gifLayer.contents = first }
        hostLayer.addSublayer(gifLayer)

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = totalDuration
        anim.repeatCount = .infinity  // loop until cancelled

        CATransaction.begin()
        gifLayer.add(anim, forKey: "fireAlarmFrames")
        CATransaction.commit()

        if playSound { SoundManager.shared.play("65_school_bell.mp3") }
        trackEffect("fire-alarm", layer: gifLayer, duration: 4.72, sound: playSound ? "65_school_bell.mp3" : nil)
    }

    // MARK: - Bullet holes (minigun)

    /// Current mouse location converted into hostLayer (overlay panel) coordinates.
    private func mouseInHostLayer() -> CGPoint {
        let global = NSEvent.mouseLocation
        let origin = (hostLayer.delegate as? NSView)?.window?.frame.origin ?? .zero
        return CGPoint(x: global.x - origin.x, y: global.y - origin.y)
    }

    func showBulletHoles(playSound: Bool = true) {
        // Toggle-off: a re-press while the burst runs cancels it — take the
        // aiming reticle down with it.
        if cancelIfRunning("bullet-holes") { stopMinigunReticle(); return }

        let bounds = hostLayer.bounds
        let totalDuration = 6.37  // matches minigun.mp3
        // 42 evenly-spaced shots (~7/s): 30% lower fire rate than the original
        // 60, spread over the same window so the burst still spans the sound.
        let count = 42
        // 0, not 0.25: the first hole has to land on the same instant as the
        // reticle and the first frame of noise. A quarter second of crosshair
        // over an unmarked desktop read as a misfire after the (now full second
        // of) silent aiming.
        let spawnStart = 0.0
        let spawnEnd = totalDuration - 0.25

        guard let url = Bundle.module.url(forResource: "bullet_hole", withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            overlayError("bullet_hole.png not found")
            return
        }

        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)

        // The gun that is doing the shooting. It rides inside `container` so the
        // burst's teardown (trackEffect, or a cancelling re-press) takes it down
        // with the holes; the resorb pass below skips it by identity.
        let gun = makeMinigunSprite(in: bounds)
        if let gun { container.addSublayer(gun) }
        // The three lines this and the two below print are how the timing is
        // checked without watching the screen: with `minigunAimLeadIn` at 0 the
        // gun, the reticle and the first hole all stamp the same tenth.
        overlayInfo("🔫 gun up — lead-in \(Self.minigunAimLeadIn)s, then reticle/holes/sound")

        let interval = (spawnEnd - spawnStart) / Double(count - 1)
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        let holeW: CGFloat = image.size.width * Self.minigunBulletHoleScale
        let holeH: CGFloat = image.size.height * Self.minigunBulletHoleScale

        if playSound {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.minigunAimLeadIn) { [weak container] in
                guard container?.superlayer != nil else { return }
                SoundManager.shared.play("22_minigun.mp3")
            }
        }

        for i in 0..<count {
            let delay = Self.minigunAimLeadIn + spawnStart + Double(i) * interval
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak container] in
                guard let self, let container, container.superlayer != nil else { return }
                if i == 0 { overlayInfo("🔫 first bullet hole") }
                let mouse = self.mouseInHostLayer()

                let x: CGFloat
                let y: CGFloat
                if let target = Self.minigunShotTarget(forMouse: mouse, in: bounds) {
                    // Cursor on-screen: cluster within 140px of the reticle,
                    // with higher density toward the center (r ∝ u, not √u).
                    let radius: CGFloat = 140
                    let angle = CGFloat.random(in: 0..<(2 * .pi))
                    let r = radius * CGFloat.random(in: 0...1)
                    x = min(max(target.x + r * cos(angle) - holeW / 2, 0), bounds.width - holeW)
                    y = min(max(target.y + r * sin(angle) - holeH / 2, 0), bounds.height - holeH)
                } else {
                    // Off-screen cursor: there is no visible aim point.
                    x = CGFloat.random(in: 0...(bounds.width - holeW))
                    y = CGFloat.random(in: 0...(bounds.height - holeH))
                }
                let hole = CALayer()
                hole.frame = CGRect(x: x, y: y, width: holeW, height: holeH)
                hole.contents = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                hole.contentsScale = scale
                hole.opacity = 0
                container.addSublayer(hole)
                // Pop in
                let fadeIn = CABasicAnimation(keyPath: "opacity")
                fadeIn.fromValue = 0.0; fadeIn.toValue = 1.0
                fadeIn.duration = 0.08
                fadeIn.fillMode = .forwards; fadeIn.isRemovedOnCompletion = false
                hole.add(fadeIn, forKey: "fadeIn")
            }
        }

        // At the tail, each hole shrinks to nothing over 1s — the bullets get
        // "resorbed" instead of fading out.
        let resorbDuration = 1.0
        let resorbStart = Self.minigunAimLeadIn + spawnEnd + 0.05  // just after the last bullet lands
        // The gun swings up out of the bottom edge and opens fire on the same
        // instant (the aiming lead-in is 0), hauls itself after the mouse for the
        // burst, and is gone by the time the last hole is resorbed. One keyframe
        // track (not two animations) so the tail can never overtake the head.
        if let gun {
            let visible = resorbStart + resorbDuration   // gun's entrance is t=0
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 1.0, 1.0, 0.0]
            fade.keyTimes = [0,
                             NSNumber(value: 0.15 / visible),
                             NSNumber(value: (visible - 0.5) / visible),
                             1]
            fade.duration = visible
            fade.beginTime = CACurrentMediaTime()
            fade.fillMode = .both
            fade.isRemovedOnCompletion = false
            gun.add(fade, forKey: "fade")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + resorbStart) { [weak container] in
            guard let holes = container?.sublayers else { return }
            for hole in holes where hole !== gun {
                let shrink = CABasicAnimation(keyPath: "transform.scale")
                shrink.fromValue = 1.0
                shrink.toValue = 0.0
                shrink.duration = resorbDuration
                shrink.timingFunction = CAMediaTimingFunction(name: .easeIn)
                shrink.fillMode = .forwards
                shrink.isRemovedOnCompletion = false
                hole.add(shrink, forKey: "resorb")
            }
        }

        trackEffect("bullet-holes", layer: container, duration: resorbStart + resorbDuration + 0.1, sound: playSound ? "22_minigun.mp3" : nil)

        // The crosshair takes the pointer over when the shooting starts, which
        // is now t=0 as well. `revealAfter` is kept wired to the lead-in so a
        // reinstated aiming beat moves the crosshair with the first round rather
        // than leaving it on an unmarked desktop.
        startMinigunReticle(following: gun,
                            revealAfter: Self.minigunAimLeadIn,
                            autoStopAfter: resorbStart + resorbDuration + 0.1)
    }

    // MARK: - FBI Knock (the screen lurches on each door bang)

    /// The three door bangs in `64_fbi.mp3`, in seconds from the first sample —
    /// the *attack* of each, measured off the clip (22 kHz, low-band envelope in
    /// 10 ms windows): bursts starting at 0.022 / 0.227 / 0.430, ~0.205 s apart,
    /// after which the clip is only the shouting.
    ///
    /// These used to read 0.406 / 0.615 / 0.813 — the same three bangs with the
    /// same 0.205 s spacing, plus a constant 0.383 s. That is the leading silence
    /// the clip was re-cut without; the constants never followed it, so every
    /// lurch landed a third of a second after its bang. **Re-cutting the clip
    /// means re-measuring these.**
    private static let fbiKnockOnsets: [Double] = [0.022, 0.227, 0.430]

    /// How far the screen lurches at the top of a bang. 1.07 on a 1728 pt-wide
    /// capture sweeps the edges ~60 pt — a shove, not a zoom.
    private static let fbiKnockScale: CGFloat = 1.07

    /// The swell rises fast and settles slower, the shape of something hit. The
    /// rise is clamped per knock so it can never start before the clip does —
    /// the first bang is only 22 ms in, so that one snaps.
    private static let fbiKnockRise: Double = 0.05
    private static let fbiKnockFall: Double = 0.13

    /// What the tracked life adds on top of the clip to cover the `screencapture`
    /// subprocess: the audio does not start until the capture is back, so the
    /// whole timeline slides by however long that took (a couple hundred ms).
    private static let fbiCaptureAllowance: Double = 0.9

    /// 🚪 A screenshot of the desktop takes a shove on each of the three door
    /// bangs, then holds while the FBI shouts.
    ///
    /// **The Mac plays the clip itself, from this same call** — same bargain as
    /// the heartbeat and the microwave. It used to arrive as a press→
    /// `SoundEffectMap` visual while a *second* HTTP request started the audio,
    /// and the knock clock then started from whenever the async `screencapture`
    /// happened to finish, so the lurches trailed the bangs by a few hundred
    /// variable ms on top of the 0.383 s the stale constants already cost.
    ///
    /// The audio therefore waits for the capture: the first bang is 22 ms into
    /// the clip, far sooner than a capture can return, so starting the sound at
    /// press time would spend that bang on an empty overlay no matter how
    /// accurate the clock was. Both halves now hang off one `clock0`.
    ///
    /// Returns the full length incl. any Bluetooth compensation, which
    /// `onSoundPlay` reports back to the tablet as `durationMs`.
    @discardableResult
    func showFbiKnock(playSound: Bool = false, volume: Float? = nil) -> TimeInterval {
        _ = cancelIfRunning("fbi-knock", sound: playSound ? "64_fbi.mp3" : nil)

        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 0 }

        // The screenshot lives exactly as long as the clip: the bangs are over by
        // 0.56s, the rest is the shouting, and the desktop should come back with
        // the last of it rather than sitting frozen in silence.
        var clipLength: Double = 1.95
        if let soundURL = SoundManager.shared.soundURL(for: "64_fbi.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric, CMTimeGetSeconds(d) > 0 { clipLength = CMTimeGetSeconds(d) }
        }
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0

        // Tracked before the capture goes out, so a second tap is debounced and a
        // stop-all reaches this even while the subprocess is still running. It is
        // contents-less until the capture returns, i.e. invisible.
        let imgLayer = CALayer()
        imgLayer.frame = bounds
        hostLayer.addSublayer(imgLayer)
        trackEffect("fbi-knock", layer: imgLayer,
                    duration: btComp + clipLength + Self.fbiCaptureAllowance,
                    sound: playSound ? "64_fbi.mp3" : nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screenshot = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self = self,
                      self.activeEffects["fbi-knock"] === imgLayer else { return }
                self.startFbiKnock(imgLayer: imgLayer, screenshot: screenshot,
                                   bounds: bounds, clipLength: clipLength,
                                   btComp: btComp, playSound: playSound, volume: volume)
            }
        }

        return btComp + clipLength
    }

    /// Called the instant the capture is back: start the audio, stamp the one
    /// clock both halves hang off, and hand CoreAnimation the whole knock
    /// sequence with an absolute `beginTime`. The render server then places every
    /// lurch on the exact frame — `asyncAfter` per knock (what this did before)
    /// puts main-thread jitter straight on screen.
    private func startFbiKnock(imgLayer: CALayer, screenshot: CGImage?, bounds: CGRect,
                               clipLength: Double, btComp: Double,
                               playSound: Bool, volume: Float?) {
        // Sound first, then the clock — nothing slow may run between them. On
        // Bluetooth output `playTabletSound` prepends `btComp` of warm-up silence,
        // so the audio really starts that much later and the whole visual
        // timeline shifts with it. Zero on wired/built-in output.
        if playSound { _ = SoundManager.shared.playTabletSound("64_fbi.mp3", volume: volume) }
        let clock0 = CACurrentMediaTime() + btComp

        // A failed capture still leaves the sound playing; there is just nothing
        // to shove. The tracked layer expires on its own.
        guard let screenshot = screenshot else { return }
        imgLayer.contents = screenshot
        imgLayer.contentsGravity = .resizeAspectFill

        // One keyframe animation for all three bangs, so they cannot drift apart.
        // The PEAK lands on the onset, not the start of the rise: the top of the
        // swell is what the eye takes as the hit, so starting the rise on the bang
        // reads as half a beat late (the same lesson as the heartbeat's).
        var times: [Double] = []
        var values: [CGFloat] = []
        var timings: [CAMediaTimingFunction] = []
        for onset in Self.fbiKnockOnsets {
            let rise = min(Self.fbiKnockRise, onset)
            let start = onset - rise
            if let last = times.last, start > last {
                times.append(start); values.append(1.0)            // rest between bangs
                timings.append(CAMediaTimingFunction(name: .linear))
            } else if times.isEmpty {
                times.append(start); values.append(1.0)
            }
            times.append(onset);              values.append(Self.fbiKnockScale)
            timings.append(CAMediaTimingFunction(name: .easeOut))  // the shove
            times.append(onset + Self.fbiKnockFall); values.append(1.0)
            timings.append(CAMediaTimingFunction(name: .easeIn))   // settling back
        }
        guard let span = times.last, span > 0 else { return }

        let knocks = CAKeyframeAnimation(keyPath: "transform.scale")
        knocks.values = values.map { NSNumber(value: Double($0)) }
        knocks.keyTimes = times.map { NSNumber(value: $0 / span) }
        knocks.timingFunctions = timings
        knocks.duration = span
        knocks.beginTime = clock0          // absolute, in CoreAnimation's own clock
        imgLayer.add(knocks, forKey: "fbiKnocks")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.beginTime = clock0 + clipLength - 0.3
        fadeOut.fromValue = 1.0; fadeOut.toValue = 0.0
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "fadeOut")
    }

    // MARK: - 🚪 Dark door (tile #25) — the desktop is punched IN on every knock

    /// The seven knocks in `25_dark_door.mp3`, in seconds from the first sample.
    ///
    /// **How they were measured** (2026-09-11), the same way the FBI knock's
    /// onsets were: decode to mono 22 kHz, run a one-pole 500 Hz low-pass (a
    /// knock is a low thump; the room tone and the door's rattle sit above it),
    /// take the RMS envelope in 2 ms windows, then for each peak walk *back* to
    /// where the envelope first exceeds 8 % of that peak — that edge is the
    /// attack, and it is what the ear calls "the knock". Run against `64_fbi.mp3`
    /// the same procedure reproduces its committed 0.022 / 0.227 to the
    /// millisecond, which is why these are trusted.
    ///
    /// The spacing is metronomic — 0.18…0.20 s, no rubato — and the clip is
    /// 1.477 s long with nothing but decay after the last knock (silence from
    /// ~1.35 s). **Re-cutting the clip means re-measuring these.**
    private static let darkDoorKnockOnsets: [Double] = [0.024, 0.224, 0.416, 0.596,
                                                        0.784, 0.964, 1.160]

    /// Each knock punches the capture in by this much **on top of the last one**
    /// — the difference between this and the FBI knock, whose every bang shoves
    /// the screen and lets it straight back. Seven compounding steps of 1.09
    /// land on 1.83×, which is as far in as a 16:10 capture can go before the
    /// desktop stops being recognisable as itself.
    private static let darkDoorPunchStep: CGFloat = 1.09
    /// A punch overshoots its new level and settles back onto it. Without this
    /// the steps read as a smooth ramp rather than seven separate hits.
    private static let darkDoorPunchOvershoot: CGFloat = 1.03
    /// Fast in (peaking ON the knock, the heartbeat's lesson), slower to settle.
    private static let darkDoorPunchRise: Double = 0.045
    private static let darkDoorPunchSettle: Double = 0.085
    /// As `fbiCaptureAllowance`: the whole timeline slides by however long the
    /// `screencapture` subprocess took, because the audio waits for it.
    private static let darkDoorCaptureAllowance: Double = 0.9

    /// 🚪 A screenshot of the desktop is zoomed in FBI-style: seven successive
    /// punch-ins, one on each knock, each one holding its new level until the
    /// next knock takes it further.
    ///
    /// Tile #25 did nothing at all before 2026-09-11 — `25_dark_door.mp3` was
    /// simply not mentioned anywhere in the app, so the tile played a clip over
    /// an untouched desktop.
    ///
    /// Like the FBI knock (and the heartbeat, and the microwave) **this owns its
    /// own audio**: the first knock is 24 ms into the clip, far sooner than a
    /// capture can return, so the sound is started in the capture's completion
    /// and both halves hang off one `clock0`. That is also why the tile stays
    /// out of `SoundEffectMap` — the press path would double-trigger it.
    ///
    /// Returns the full length incl. any Bluetooth compensation, which
    /// `onSoundPlay` reports back to the tablet as `durationMs`.
    @discardableResult
    func showDarkDoor(playSound: Bool = false, volume: Float? = nil) -> TimeInterval {
        _ = cancelIfRunning("dark-door", sound: playSound ? "25_dark_door.mp3" : nil)

        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 0 }

        var clipLength: Double = 1.477
        if let soundURL = SoundManager.shared.soundURL(for: "25_dark_door.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric, CMTimeGetSeconds(d) > 0 { clipLength = CMTimeGetSeconds(d) }
        }
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0

        // Tracked (and contents-less, i.e. invisible) before the capture goes
        // out, so a second tap is debounced and a stop-all reaches this even
        // while the subprocess is still running. The FBI knock's pattern.
        let imgLayer = CALayer()
        imgLayer.frame = bounds
        hostLayer.addSublayer(imgLayer)
        trackEffect("dark-door", layer: imgLayer,
                    duration: btComp + clipLength + Self.darkDoorCaptureAllowance,
                    sound: playSound ? "25_dark_door.mp3" : nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screenshot = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self = self,
                      self.activeEffects["dark-door"] === imgLayer else { return }
                self.startDarkDoor(imgLayer: imgLayer, screenshot: screenshot,
                                   clipLength: clipLength, btComp: btComp,
                                   playSound: playSound, volume: volume)
            }
        }

        return btComp + clipLength
    }

    /// Called the instant the capture is back: start the audio, stamp the clock
    /// both halves hang off, and hand CoreAnimation the whole punch sequence with
    /// an absolute `beginTime` so the render server places every step on the
    /// exact frame (an `asyncAfter` per knock puts main-thread jitter on screen).
    private func startDarkDoor(imgLayer: CALayer, screenshot: CGImage?,
                               clipLength: Double, btComp: Double,
                               playSound: Bool, volume: Float?) {
        // Sound first, then the clock — nothing slow may run between them.
        if playSound { _ = SoundManager.shared.playTabletSound("25_dark_door.mp3", volume: volume) }
        let clock0 = CACurrentMediaTime() + btComp

        guard let screenshot = screenshot else {
            overlayError("🚪 dark door: screen capture failed (Screen Recording not granted?) — the clip plays over an untouched desktop")
            return
        }
        imgLayer.contents = screenshot
        imgLayer.contentsGravity = .resizeAspectFill

        // One keyframe animation for all seven knocks so they cannot drift
        // apart. Each knock RAISES the resting level instead of returning to 1 —
        // that cumulation is what makes it a zoom rather than a shudder.
        var times: [Double] = [0]
        var values: [CGFloat] = [1.0]
        var timings: [CAMediaTimingFunction] = []
        var level: CGFloat = 1.0
        for onset in Self.darkDoorKnockOnsets {
            let previous = level
            level *= Self.darkDoorPunchStep
            // Clamped so a knock can never start before the clip does, and never
            // before the previous knock has finished settling.
            let start = max(times.last ?? 0, onset - Self.darkDoorPunchRise)
            if start > (times.last ?? 0) {
                times.append(start); values.append(previous)          // holding the last level
                timings.append(CAMediaTimingFunction(name: .linear))
            }
            times.append(onset); values.append(level * Self.darkDoorPunchOvershoot)
            timings.append(CAMediaTimingFunction(name: .easeOut))     // the punch
            times.append(onset + Self.darkDoorPunchSettle); values.append(level)
            timings.append(CAMediaTimingFunction(name: .easeIn))      // settling onto it
        }
        // Hold the final level for the rest of the clip — the desktop stays
        // punched in under the door's decay instead of snapping back on silence.
        if let last = times.last, clipLength > last {
            times.append(clipLength); values.append(level)
            timings.append(CAMediaTimingFunction(name: .linear))
        }
        guard let span = times.last, span > 0 else { return }

        let punches = CAKeyframeAnimation(keyPath: "transform.scale")
        punches.values = values.map { NSNumber(value: Double($0)) }
        punches.keyTimes = times.map { NSNumber(value: $0 / span) }
        punches.timingFunctions = timings
        punches.duration = span
        punches.beginTime = clock0         // absolute, in CoreAnimation's own clock
        punches.fillMode = .forwards
        punches.isRemovedOnCompletion = false
        imgLayer.add(punches, forKey: "darkDoorPunches")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.beginTime = clock0 + clipLength - 0.3
        fadeOut.fromValue = 1.0; fadeOut.toValue = 0.0
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "fadeOut")

        overlayInfo("🚪 dark door: capture up, \(Self.darkDoorKnockOnsets.count) punch-ins to \(String(format: "%.2f", level))×")
    }

    // MARK: - 🎼 Beethoven's Fifth (the screen zooms on the motif — sound #51)

    /// The two "da-da-da-DUM" phrases of `51_beethoven.mp3`, in seconds from the
    /// first sample: the three eighth notes, then the long note they fall onto.
    /// Measured off the clip — mono 16 kHz, log-envelope flux in 5 ms windows —
    /// not counted off a score: the eighths are ~0.11 s apart, which is faster
    /// than the concert tempo, because this is a sound effect and not the
    /// symphony.
    ///
    /// Same standing rule as the FBI knock's onsets: **re-cutting the clip means
    /// re-measuring these.**
    private static let beethovenPhrases: [(shorts: [Double], resolve: Double)] = [
        (shorts: [0.305, 0.410, 0.520], resolve: 0.650),
        (shorts: [3.240, 3.375, 3.495], resolve: 3.610),
    ]

    /// How big the screen gets on each of the three notes — **bigger every
    /// time**, which is half the ask ("din ce în ce mai mare"). 1.22 on a
    /// 1728 pt-wide capture pushes the edges ~190 pt off frame: a lunge, well
    /// past the FBI knock's 1.07 shove, because this one is the joke rather
    /// than a punctuation mark.
    private static let beethovenZoomPeaks: [CGFloat] = [1.06, 1.13, 1.22]

    /// …and how much of what a note just gained is given straight back before
    /// the next one — the other half of the ask ("dând puțin de înapoi de
    /// fiecare dată"). A *fraction of the gain*, not a fixed scale, so the
    /// retreat stays proportional as the peaks grow; a fixed one would be a
    /// twitch under the first note and a collapse under the third.
    private static let beethovenPullBack: CGFloat = 0.45

    /// The swell before a note. The three eighths are only ~0.11 s apart, so the
    /// rise and the pull-back have to share that gap: 0.06 s of rise leaves
    /// 0.05 s of retreat, which reads as a punch — the shape the motif has.
    /// As everywhere else here, the **peak lands ON the onset**, so the rise
    /// starts this much before it.
    private static let beethovenRise: Double = 0.06

    /// How long the screen takes to settle back to its own size once the triplet
    /// has landed on its long note. Slow next to the punches on purpose: the
    /// three hits are the motif, this is the fermata under them.
    private static let beethovenRelease: Double = 0.45

    /// 🎼 The desktop is photographed and then lunges at the room three times on
    /// Beethoven's three eighth notes — each lunge bigger than the last, each
    /// giving a little back before the next — and unwinds to its own size on the
    /// long note. Then the whole shape repeats on the second phrase.
    ///
    /// **The Mac plays the clip itself, from this same call, and the audio waits
    /// for the capture** — the FBI knock's two lessons, for the FBI knock's two
    /// reasons: a press-path visual and a separately-routed play have no common
    /// clock, and the first hit is 0.305 s in, close enough to a `screencapture`
    /// round trip that starting the sound before the picture existed would spend
    /// it on an empty overlay.
    ///
    /// Returns the full length incl. any Bluetooth compensation, which
    /// `onSoundPlay` reports back to the tablet as `durationMs`.
    @discardableResult
    func showBeethoven(playSound: Bool = false, volume: Float? = nil) -> TimeInterval {
        _ = cancelIfRunning("beethoven", sound: playSound ? "51_beethoven.mp3" : nil)

        let bounds = hostLayer.bounds
        guard bounds.width > 0, bounds.height > 0 else { return 0 }

        // The capture lives exactly as long as the clip. It spends the last two
        // seconds at scale 1, i.e. pixel-identical to the desktop under it, so
        // there is no frozen-screenshot tax for holding it there — only the
        // cursor is missing, and the real one is still on top of the overlay.
        var clipLength: Double = 6.52
        if let soundURL = SoundManager.shared.soundURL(for: "51_beethoven.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric, CMTimeGetSeconds(d) > 0 { clipLength = CMTimeGetSeconds(d) }
        }
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0

        // Tracked before the capture goes out, so a second tap is debounced and a
        // stop-all reaches this even while the subprocess is still running.
        let imgLayer = CALayer()
        imgLayer.frame = bounds
        hostLayer.addSublayer(imgLayer)
        trackEffect("beethoven", layer: imgLayer,
                    duration: btComp + clipLength + Self.fbiCaptureAllowance,
                    sound: playSound ? "51_beethoven.mp3" : nil)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screenshot = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self = self,
                      self.activeEffects["beethoven"] === imgLayer else { return }
                self.startBeethoven(imgLayer: imgLayer, screenshot: screenshot,
                                    clipLength: clipLength, btComp: btComp,
                                    playSound: playSound, volume: volume)
            }
        }

        return btComp + clipLength
    }

    /// Called the instant the capture is back: start the audio, stamp the one
    /// clock both halves hang off, and hand CoreAnimation the **whole** zoom
    /// timeline as a single keyframe animation on an absolute `beginTime`. One
    /// animation rather than six `asyncAfter` callbacks is what keeps six hits
    /// 0.11 s apart from picking up main-thread jitter on the way to the screen.
    private func startBeethoven(imgLayer: CALayer, screenshot: CGImage?,
                                clipLength: Double, btComp: Double,
                                playSound: Bool, volume: Float?) {
        if playSound { _ = SoundManager.shared.playTabletSound("51_beethoven.mp3", volume: volume) }
        let clock0 = CACurrentMediaTime() + btComp

        guard let screenshot = screenshot else { return }
        imgLayer.contents = screenshot
        imgLayer.contentsGravity = .resizeAspectFill

        var times: [Double] = [0.0]
        var values: [CGFloat] = [1.0]
        var timings: [CAMediaTimingFunction] = []

        // Append a keyframe, skipping it when it would go backwards in time —
        // the gaps here are 50 ms wide and the constants above are free to
        // change, so the guard is what stops a re-tune from producing an
        // animation CoreAnimation quietly refuses to run.
        func at(_ t: Double, _ v: CGFloat, _ curve: CAMediaTimingFunctionName) {
            guard t > (times.last ?? 0) else { return }
            times.append(t); values.append(v)
            timings.append(CAMediaTimingFunction(name: curve))
        }

        for phrase in Self.beethovenPhrases {
            for (i, onset) in phrase.shorts.enumerated() {
                let peak = Self.beethovenZoomPeaks[min(i, Self.beethovenZoomPeaks.count - 1)]
                let rest = values.last ?? 1.0
                at(onset - Self.beethovenRise, rest, .linear)   // waiting for the note
                at(onset, peak, .easeOut)                       // the note
                // Give part of it back — but only up to the moment the NEXT note
                // starts winding up. The third note has no next one: it holds its
                // peak into the long note, which is what makes the release read
                // as one gesture instead of a fourth twitch.
                guard i + 1 < phrase.shorts.count else { continue }
                let backTo = peak - (peak - rest) * Self.beethovenPullBack
                at(min(onset + Self.beethovenRise,
                       phrase.shorts[i + 1] - Self.beethovenRise), backTo, .easeIn)
            }
            at(phrase.resolve, values.last ?? 1.0, .linear)     // hold onto the long note
            at(phrase.resolve + Self.beethovenRelease, 1.0, .easeInEaseOut)
        }
        at(clipLength, 1.0, .linear)                            // sit still for the tail

        guard let span = times.last, span > 0, values.count > 1 else { return }
        let zoom = CAKeyframeAnimation(keyPath: "transform.scale")
        zoom.values = values.map { NSNumber(value: Double($0)) }
        zoom.keyTimes = times.map { NSNumber(value: $0 / span) }
        zoom.timingFunctions = timings
        zoom.duration = span
        zoom.beginTime = clock0          // absolute, in CoreAnimation's own clock
        imgLayer.add(zoom, forKey: "beethovenZoom")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.beginTime = clock0 + clipLength - 0.4
        fadeOut.fromValue = 1.0; fadeOut.toValue = 0.0
        fadeOut.duration = 0.4
        fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "fadeOut")
    }

    // MARK: - Phone ring (screenshot shake)

    func showPhoneRing(playSound: Bool = true) {
        if cancelIfRunning("phone-ring", sound: playSound ? "10_red_phone.mp3" : nil) { return }

        let bounds = hostLayer.bounds
        let totalDuration = 2.29

        // Retina capture off-main (see showBrokenGlass); play + build on main.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let screenshot = Self.captureBuiltInDisplay()
            DispatchQueue.main.async {
                guard let self, let screenshot else { return }
                self.renderPhoneRing(screenshot: screenshot, bounds: bounds, totalDuration: totalDuration, playSound: playSound)
            }
        }
    }

    private func renderPhoneRing(screenshot: CGImage, bounds: CGRect, totalDuration: Double, playSound: Bool) {
        if playSound { SoundManager.shared.play("10_red_phone.mp3") }

        let imgLayer = CALayer()
        imgLayer.frame = bounds
        imgLayer.contents = screenshot
        imgLayer.contentsGravity = .resizeAspectFill
        hostLayer.addSublayer(imgLayer)

        // Shake: rapid random offsets ±20px horizontal, ±7px vertical
        let shake = CAKeyframeAnimation(keyPath: "position")
        shake.duration = totalDuration
        shake.calculationMode = .discrete
        let cx = bounds.midX, cy = bounds.midY
        var positions: [NSValue] = []
        let count = Int(totalDuration / 0.04) // ~25Hz
        for _ in 0..<count {
            let dx = CGFloat.random(in: -20...20)
            let dy = CGFloat.random(in: -7...7)
            positions.append(NSValue(point: CGPoint(x: cx + dx, y: cy + dy)))
        }
        positions.append(NSValue(point: CGPoint(x: cx, y: cy)))
        shake.values = positions
        imgLayer.add(shake, forKey: "shake")

        // The ringing phone itself, in the bottom-left corner. It is a SUBLAYER
        // of the screenshot, not a sibling: the shake above animates the
        // screenshot's `position`, and children ride along with it for free —
        // so the phone rattles in lockstep with the desktop instead of drifting
        // out of phase with a shake of its own.
        if let url = Bundle.module.url(forResource: "red-phone", withExtension: "png"),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let phone = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let aspect = CGFloat(phone.width) / CGFloat(phone.height)
            var w = bounds.width * 0.26
            var h = w / aspect
            if h > bounds.height * 0.45 {
                h = bounds.height * 0.45
                w = h * aspect
            }
            let margin = bounds.width * 0.02
            let phoneLayer = CALayer()
            phoneLayer.frame = CGRect(x: margin, y: margin, width: w, height: h)  // y = 0 is the bottom edge
            phoneLayer.contents = phone
            phoneLayer.contentsGravity = .resizeAspect
            imgLayer.addSublayer(phoneLayer)
        }

        // Fade out over last 0.3s
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.beginTime = CACurrentMediaTime() + totalDuration - 0.3
        fadeOut.fromValue = 1.0; fadeOut.toValue = 0.0
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards; fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "fadeOut")

        trackEffect("phone-ring", layer: imgLayer, duration: totalDuration + 0.1, sound: playSound ? "10_red_phone.mp3" : nil)
    }

    // MARK: - Cavalry charge (knight gallops in from the left, fades past mid-screen — sound #70)

    func showCavalry(playSound: Bool = true) {
        if cancelIfRunning("cavalry", sound: playSound ? "70_cavalry.mp3" : nil) { return }

        // APNG (full 8-bit alpha — flood-filled from the GIF's black bg) in
        // the bundle; frame delays come from the APNG dictionary.
        guard let url = Bundle.module.url(forResource: "cavalry", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("cavalry.png not found in bundle")
            return
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }
        var images: [CGImage] = []
        var loopDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let png = props?[kCGImagePropertyPNGDictionary as String] as? [String: Any]
            loopDuration += png?[kCGImagePropertyAPNGDelayTime as String] as? Double ?? 0.05
        }

        let bounds = hostLayer.bounds
        let width = bounds.width * 0.338         // 0.26 grown by 30% — the rider read too small
        let height = width * 373.0 / 498.0
        let travel = 5.0                          // ≈ 70_cavalry.mp3 duration (5.56s)
        let startX = -width / 2                   // fully offscreen left
        let endX = bounds.width * 0.78            // gone around the right quarter

        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        gifLayer.contentsGravity = .resizeAspect
        gifLayer.contents = images.first
        // Glued to the bottom screen edge: center at half the layer height,
        // pulled down by the APNG's transparent margin below the hooves
        // (5.6% of frame height) plus 10px so the hooves sit right on the
        // bottom.
        gifLayer.position = CGPoint(x: startX, y: height / 2 - height * 0.056 - 10)
        hostLayer.addSublayer(gifLayer)

        let gallop = CAKeyframeAnimation(keyPath: "contents")
        gallop.values = images
        gallop.duration = loopDuration
        gallop.repeatCount = .infinity
        gifLayer.add(gallop, forKey: "gallop")

        let charge = CABasicAnimation(keyPath: "position.x")
        charge.fromValue = startX
        charge.toValue = endX
        charge.duration = travel
        charge.fillMode = .forwards
        charge.isRemovedOnCompletion = false
        gifLayer.add(charge, forKey: "charge")

        // Full strength until mid-screen, then fade away by the end of the run.
        let halfTime = (bounds.width * 0.50 - startX) / (endX - startX)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1.0, 1.0, 0.0]
        fade.keyTimes = [0, NSNumber(value: Double(halfTime)), 1]
        fade.duration = travel
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        gifLayer.add(fade, forKey: "fade")

        if playSound { SoundManager.shared.play("70_cavalry.mp3") }
        trackEffect("cavalry", layer: gifLayer, duration: travel + 0.1, sound: playSound ? "70_cavalry.mp3" : nil)
    }

    // MARK: - Counter-Strike (CT duo holds the bottom-left quarter — sound #73)

    /// The two Counter-Strike operators hold the WEST side of the screen, glued
    /// to the bottom edge, for exactly as long as `73_counter_strike.mp3`
    /// plays (~1.36s, measured from the file so a re-cut clip stays in sync).
    /// The bundled PNG is pre-trimmed to its opaque content, so "glued to the
    /// bottom" is literal — the layer's bottom edge IS the boots, with no
    /// transparent margin lifting them off the edge. Width is the driver: they
    /// fill exactly HALF the screen width, aspect preserved, and the height
    /// falls out of that (only clamped if it would overflow the screen).
    func showCounterStrike(playSound: Bool = true) {
        if cancelIfRunning("counter-strike", sound: playSound ? "73_counter_strike.mp3" : nil) { return }

        guard let url = Bundle.module.url(forResource: "counter-strike", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            overlayError("counter-strike.png not found in bundle")
            return
        }

        // Linger exactly as long as the clip; fall back to its measured length.
        var duration: Double = 1.36
        if let soundURL = SoundManager.shared.soundURL(for: "73_counter_strike.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        let bounds = hostLayer.bounds
        // Half the screen width is the target, aspect preserved, anchored at the
        // bottom-left (west) corner. Height only binds in the degenerate case
        // where that would push the art off the top of the screen.
        let aspect = CGFloat(image.width) / CGFloat(image.height)
        var w = bounds.width / 2
        var h = w / aspect
        if h > bounds.height {
            h = bounds.height
            w = h * aspect
        }

        let imgLayer = CALayer()
        imgLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)   // y = 0 is the bottom edge
        imgLayer.contents = image
        imgLayer.contentsGravity = .resizeAspect
        hostLayer.addSublayer(imgLayer)

        // Snap up from just below the edge (0.18s) — reads as "they take position".
        let rise = CABasicAnimation(keyPath: "position.y")
        rise.fromValue = -h / 2
        rise.toValue = h / 2
        rise.duration = min(0.18, duration * 0.2)
        rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
        imgLayer.add(rise, forKey: "rise")

        // Gone with the last of the sound.
        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.beginTime = CACurrentMediaTime() + max(0, duration - 0.3)
        fadeOut.fromValue = 1.0
        fadeOut.toValue = 0.0
        fadeOut.duration = 0.3
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        imgLayer.add(fadeOut, forKey: "fadeOut")

        if playSound { SoundManager.shared.play("73_counter_strike.mp3") }
        trackEffect("counter-strike", layer: imgLayer, duration: duration,
                    sound: playSound ? "73_counter_strike.mp3" : nil)
    }

    // MARK: - Wasn't me (wagging finger in the SW quadrant — sound #76)

    /// A 3D hand wagging its index finger "no-no" sits in the **bottom-left
    /// quarter** of the desktop for exactly as long as `76_sfx_118.mp3` plays,
    /// then fades out on its own.
    ///
    /// The art is a 24-frame transparent GIF looping in under a second, so unlike
    /// the one-shot overlays (cavalry, counter-strike) the frames simply **repeat
    /// forever** and the *sound* decides when it is over — the gesture is a denial
    /// held for as long as the denial is being sung, not a thing that happens once.
    /// The length is read off the mp3 rather than hardcoded so a re-cut clip stays
    /// in sync, with the measured 6.55s as the fallback.
    ///
    /// It is **centred in the quadrant, not glued to the bottom-left corner** the
    /// way the Counter-Strike operators are: those stand on the screen edge, this
    /// is a floating hand, and a hand jammed into the corner reads as a cropping
    /// accident rather than a gesture.
    func showWasntMe(playSound: Bool = true) {
        if cancelIfRunning("wasnt-me", sound: playSound ? "76_sfx_118.mp3" : nil) { return }

        guard let url = Bundle.module.url(forResource: "wasnt-me", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("wasnt-me.gif not found in bundle")
            return
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var loopDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            loopDuration += gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.04
        }
        guard let first = images.first, loopDuration > 0 else { return }

        var duration: Double = 6.55
        if let soundURL = SoundManager.shared.soundURL(for: "76_sfx_118.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        let bounds = hostLayer.bounds
        // Aspect-fit inside 80% of the bottom-left quarter, centred in it. The
        // 80% is the breathing room that keeps the hand off both screen edges.
        let aspect = CGFloat(first.width) / CGFloat(first.height)
        let quarter = CGSize(width: bounds.width / 2, height: bounds.height / 2)
        var w = quarter.width * 0.8
        var h = w / aspect
        if h > quarter.height * 0.8 {
            h = quarter.height * 0.8
            w = h * aspect
        }

        let gifLayer = CALayer()
        gifLayer.bounds = CGRect(x: 0, y: 0, width: w, height: h)
        // y = 0 is the BOTTOM edge here, so the bottom-left quarter is the
        // quadrant whose centre sits a quarter of the way up and across.
        gifLayer.position = CGPoint(x: quarter.width / 2, y: quarter.height / 2)
        gifLayer.contents = first
        gifLayer.contentsGravity = .resizeAspect
        hostLayer.addSublayer(gifLayer)

        let wag = CAKeyframeAnimation(keyPath: "contents")
        wag.values = images
        wag.duration = loopDuration
        wag.repeatCount = .infinity
        wag.calculationMode = .discrete
        gifLayer.add(wag, forKey: "wag")

        // Fades in fast, holds, then fades out by itself over the last 0.8s —
        // one keyframe track rather than two animations, so the tail can never
        // start before the head has finished on a very short clip.
        let fadeTail = min(0.8, duration * 0.2)
        let fadeHead = min(0.25, duration * 0.1)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0,
                         NSNumber(value: fadeHead / duration),
                         NSNumber(value: (duration - fadeTail) / duration),
                         1]
        fade.duration = duration
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        gifLayer.add(fade, forKey: "fade")

        if playSound { SoundManager.shared.play("76_sfx_118.mp3") }
        trackEffect("wasnt-me", layer: gifLayer, duration: duration,
                    sound: playSound ? "76_sfx_118.mp3" : nil)
    }

    // MARK: - Microwave (kitchen timer ticks, then the door swings open on the BING — sound #61)

    /// Where the BING starts inside `61_dinner.mp3` — measured off the file as the
    /// *beginning of the rising front* toward the peak (RMS crosses 10% of peak at
    /// 2.695s, peak at 2.700s), which is the instant Victor asked the door to start
    /// moving on. Everything before it is the timer ticking away at a closed
    /// microwave; a constant is fine because the clip is fixed, and re-cutting it
    /// means re-measuring this number.
    private static let microwaveBingOnset: Double = 2.695

    /// A cartoon microwave sits translucent in the middle of the desktop while a
    /// kitchen timer ticks, then its door swings open exactly on the BING.
    ///
    /// The whole point is that one sync: the 16 source frames are NOT a loop —
    /// frame 0 is the closed door and frame 15 the fully open one — so the layer
    /// simply *holds frame 0* for the 2.695s of ticking and only then runs the
    /// swing (0.64s at the gif's native 25fps), holding the open door through the
    /// bell's decay before fading out with it.
    ///
    /// The art is pre-cropped to its content **symmetrically about the source
    /// frame's centre**, so the closed microwave still sits dead-centre and the
    /// door has room to swing out to the left; it is then fitted aspect-preserved
    /// inside 80% of the screen and drawn at 85% opacity so the desktop reads
    /// through it.
    ///
    /// `playSound` = this call owns the audio (the routed `/sound/play` path).
    /// Returns the full length incl. any Bluetooth compensation, which
    /// `onSoundPlay` reports back to the tablet as `durationMs`.
    @discardableResult
    func showMicrowave(playSound: Bool = true, volume: Float? = nil) -> TimeInterval {
        _ = cancelIfRunning("microwave", sound: playSound ? "61_dinner.mp3" : nil)

        guard let url = Bundle.module.url(forResource: "microwave", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            overlayError("microwave.gif not found in bundle")
            return 0
        }
        let count = CGImageSourceGetCount(source)
        var images: [CGImage] = []
        for i in 0..<count {
            if let cg = CGImageSourceCreateImageAtIndex(source, i, nil) { images.append(cg) }
        }
        guard let closed = images.first else { return 0 }

        // Live exactly as long as the timer clip; fall back to its measured length.
        var duration: Double = 4.38
        if let soundURL = SoundManager.shared.soundURL(for: "61_dinner.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        // On Bluetooth output the audio is started `btComp` late (A2DP warm-up),
        // so shift the ENTIRE visual timeline by the same amount — otherwise the
        // door would fly open most of a second before the BING reached the
        // speaker, which is the one thing this effect must never do. Zero on
        // wired/built-in output. `playTabletSound` applies the same delay to the
        // audio itself, so we must NOT add it there a second time.
        let btComp = playSound ? SoundTimingConfig.shared.currentBluetoothCompensation : 0
        let clock0 = CACurrentMediaTime() + btComp

        let bounds = hostLayer.bounds
        let aspect = CGFloat(closed.width) / CGFloat(closed.height)
        var w = bounds.width * 0.8
        var h = w / aspect
        if h > bounds.height * 0.8 {
            h = bounds.height * 0.8
            w = h * aspect
        }

        let layer = CALayer()
        layer.frame = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        layer.contentsGravity = .resizeAspect
        layer.contents = closed              // model value: door shut, all through the ticking
        layer.opacity = Self.microwaveOpacity
        hostLayer.addSublayer(layer)

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0.0
        fadeIn.toValue = Self.microwaveOpacity
        fadeIn.beginTime = clock0
        fadeIn.duration = 0.25
        fadeIn.fillMode = .backwards         // invisible until the (BT-shifted) start
        layer.add(fadeIn, forKey: "microwaveFadeIn")

        // THE sync point: the swing begins on the leading edge of the BING and
        // stays on the last frame afterwards (.forwards, not removed).
        let swing = CAKeyframeAnimation(keyPath: "contents")
        swing.values = images
        swing.duration = Double(images.count) * 0.04   // the gif's own 25fps
        swing.beginTime = clock0 + Self.microwaveBingOnset
        swing.calculationMode = .discrete               // step frames, never cross-fade
        swing.fillMode = .forwards
        swing.isRemovedOnCompletion = false
        layer.add(swing, forKey: "microwaveDoor")

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = Self.microwaveOpacity
        fadeOut.toValue = 0.0
        fadeOut.beginTime = clock0 + max(0, duration - 0.5)
        fadeOut.duration = 0.5
        fadeOut.fillMode = .forwards
        fadeOut.isRemovedOnCompletion = false
        layer.add(fadeOut, forKey: "microwaveFadeOut")

        if playSound { _ = SoundManager.shared.playTabletSound("61_dinner.mp3", volume: volume) }
        let total = btComp + duration
        trackEffect("microwave", layer: layer, duration: total,
                    sound: playSound ? "61_dinner.mp3" : nil)
        return total
    }

    /// Translucent enough that the desktop reads through the microwave, opaque
    /// enough that the flat cartoon art still holds its own colours.
    private static let microwaveOpacity: Float = 0.85

    // MARK: - Rainbow (translucent semicircle smeared in like a wiper, toggled by tablet sound #37)

    func showRainbow(playSound: Bool = true) {
        if cancelIfRunning("rainbow", sound: playSound ? "37_rainbow.mp3" : nil) { return }

        let bounds = hostLayer.bounds
        let container = CALayer()
        container.frame = bounds
        hostLayer.addSublayer(container)
        activeEffects["rainbow"] = container

        // Semicircle anchored at the bottom, same size as before, but with the
        // circle's centre pushed all the way to the right screen edge so only
        // the left quarter-arc is visible. The visible box is then square: its
        // width  W - (cx - R) and height min(R, screenH) are both R when cx == W
        // (R = 0.52·W < screenH on this display), i.e. a quarter-rainbow tucked
        // into the bottom-right corner.
        let center = CGPoint(x: bounds.width, y: 0)
        let outerRadius = bounds.width * 0.52
        let bandWidth = outerRadius * 0.035
        let colors: [NSColor] = [
            .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue,
            NSColor(red: 0.29, green: 0.0, blue: 0.51, alpha: 1),  // indigo
            NSColor(red: 0.56, green: 0.0, blue: 1.0, alpha: 1),   // violet
        ]
        for (i, color) in colors.enumerated() {
            let radius = outerRadius - CGFloat(i) * bandWidth
            let path = CGMutablePath()
            // From 180° (bottom-left tail) over the top (90°) down to 0°.
            path.addArc(center: center, radius: radius,
                        startAngle: .pi, endAngle: 0, clockwise: true)
            let band = CAShapeLayer()
            band.path = path
            band.strokeColor = color.withAlphaComponent(0.55).cgColor
            band.fillColor = nil
            band.lineWidth = bandWidth + 1  // +1 hides hairline gaps between bands
            band.lineCap = .round
            container.addSublayer(band)

            // Wiper smear: the arc draws itself from the left tail to the right.
            let draw = CABasicAnimation(keyPath: "strokeEnd")
            draw.fromValue = 0
            draw.toValue = 1
            draw.duration = 2.5
            draw.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.add(draw, forKey: "draw")
        }

        // Auto fade-out so the rainbow never stays stuck on screen: it lingers
        // for the sound's length, then stopRainbow() fades it to 0 and removes
        // it. The duration is read in the SILENT (tablet) path too — the routed
        // sound is the same mp3, and the old 5s default faded the rainbow ~9s
        // before the music ended. Identity-guarded so an old run's timer can't
        // kill a newer run.
        var visibleFor = 5.0
        if let soundURL = SoundManager.shared.soundURL(for: "37_rainbow.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { visibleFor = CMTimeGetSeconds(d) }
        }
        // 🦄 Unicorns hop across the screen while the arc smears in — they live
        // inside the same container, so stopRainbow() takes them with it. The
        // hops are on the song's beat, so they hang off the same instant the
        // sound is started from, one line below.
        let clock0 = CACurrentMediaTime()
        spawnRainbowUnicorns(into: container, bounds: bounds, window: visibleFor, clock0: clock0)

        if playSound { SoundManager.shared.play("37_rainbow.mp3") }
        DispatchQueue.main.asyncAfter(deadline: .now() + visibleFor) { [weak self, weak container] in
            guard let self, let container, self.activeEffects["rainbow"] === container else { return }
            self.stopRainbow()
        }
    }

    /// The beat of `37_rainbow.mp3`, measured off the clip itself — mono 8 kHz,
    /// RMS envelope in 10 ms windows, positive flux peaks, then the (period,
    /// phase) grid that best fits them: **0.484 s + k × 0.7130 s**, i.e. 84.2
    /// BPM. It matches the audible onsets to within ~20 ms across the whole
    /// 13.8 s (4.06→4.049, 5.46→5.475, 6.89→6.901, 8.34→8.327, 9.72→9.753 …).
    ///
    /// Same standing rule as the FBI knock's onsets: **re-cutting the clip means
    /// re-measuring these two numbers.** A trim at the head moves the phase; a
    /// different take moves both.
    private static let rainbowFirstBeat: Double = 0.484
    private static let rainbowBeatPeriod: Double = 0.7130

    /// The beat nearest `t`, never earlier than the first one. What snaps a
    /// unicorn's departure onto the grid.
    private static func rainbowBeatAligned(_ t: Double) -> Double {
        let n = max(0, (((t - rainbowFirstBeat) / rainbowBeatPeriod).rounded()))
        return rainbowFirstBeat + n * rainbowBeatPeriod
    }

    /// Unicorns crossing the screen for as long as the rainbow is up: each one
    /// hops in from one edge, bounces its way to the other, and fades out on the
    /// far side. Directions alternate (left→right unicorns are mirrored so they
    /// face where they're going — the Apple 🦄 glyph looks left by default), and
    /// the departures are spread across the whole rainbow window so there is
    /// always one or two in flight, never a herd all at once.
    ///
    /// **Every hoof-fall is on the beat** (Victor, 2026-09-09). Three things
    /// together buy that, and dropping any one of them loses it:
    ///
    /// 1. **One hop per beat.** The crossing is `hops × rainbowBeatPeriod` long,
    ///    not a round number picked for looks — 6 hops ≈ 4.28 s, which is close
    ///    to the 4.7 s it used to take, so the pacing barely changed.
    /// 2. **Equal hops, paced along the path.** `calculationMode = .paced` times
    ///    the keyframe path by arc length, and all six arcs of one unicorn are
    ///    congruent, so each takes exactly a beat. This is why the per-unicorn
    ///    travel jitter (±15 %) had to go: it made every unicorn a different,
    ///    wrong tempo.
    /// 3. **Departures snapped to the grid.** A unicorn lands on the ground at
    ///    its start plus every whole beat, so the start itself has to be a beat
    ///    or all six landings are off by the same constant.
    private func spawnRainbowUnicorns(into container: CALayer, bounds: CGRect,
                                      window: Double, clock0: CFTimeInterval) {
        let count = 7
        let hops = 6
        let travel = Double(hops) * Self.rainbowBeatPeriod
        let lastStart = max(0, window - travel - 0.6)

        for i in 0..<count {
            let progress = count > 1 ? Double(i) / Double(count - 1) : 0
            let delay = Self.rainbowBeatAligned(lastStart * progress)
            spawnRainbowUnicorn(into: container, bounds: bounds,
                                leftToRight: i % 2 == 0,
                                delay: delay,
                                travel: travel,
                                hops: hops,
                                clock0: clock0)
        }
    }

    private func spawnRainbowUnicorn(into container: CALayer, bounds: CGRect,
                                     leftToRight: Bool, delay: Double, travel: Double,
                                     hops: Int, clock0: CFTimeInterval) {
        // Twice the original 0.10...0.16 of screen height. At the old size they
        // read as decoration under the arc; at this one they are the thing you
        // watch, which is what they are there for on the projector.
        let fontSize = bounds.height * CGFloat.random(in: 0.20...0.32)
        let box = fontSize * 1.25

        let unicorn = CATextLayer()
        unicorn.string = "🦄"
        unicorn.fontSize = fontSize
        unicorn.alignmentMode = .center
        unicorn.bounds = CGRect(x: 0, y: 0, width: box, height: box)
        unicorn.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        unicorn.opacity = 0            // invisible until its own start time
        // Mirrored when running to the right so it always faces its direction.
        if leftToRight { unicorn.transform = CATransform3DMakeScale(-1, 1, 1) }

        // Lanes anywhere in the lower two thirds — the ground they "walk" on —
        // with the hop apex reaching about half a body above it. The lane is
        // clamped so the apex plus half a body still fits: at double size a
        // top-lane unicorn used to hop its horn off the top edge, and the
        // beheaded frame is the one the projector holds on.
        let hop = box * CGFloat.random(in: 0.30...0.55)
        let highestGround = max(bounds.height * 0.12, bounds.height - hop - box / 2)
        let groundY = min(bounds.height * CGFloat.random(in: 0.12...0.62), highestGround)
        let startX = leftToRight ? -box : bounds.width + box
        let endX = leftToRight ? bounds.width + box : -box

        let path = CGMutablePath()
        path.move(to: CGPoint(x: startX, y: groundY))
        for h in 1...hops {
            let x0 = startX + (endX - startX) * CGFloat(h - 1) / CGFloat(hops)
            let x1 = startX + (endX - startX) * CGFloat(h) / CGFloat(hops)
            // Quadratic control at 2× the hop height puts the arc's apex at 1×.
            path.addQuadCurve(to: CGPoint(x: x1, y: groundY),
                              control: CGPoint(x: (x0 + x1) / 2, y: groundY + hop * 2))
        }
        unicorn.position = CGPoint(x: startX, y: groundY)
        container.addSublayer(unicorn)

        let bounce = CAKeyframeAnimation(keyPath: "position")
        bounce.path = path
        // Even speed along the arcs: with congruent hops that is exactly one
        // beat each, which is the whole reason the landings fall on the music.
        bounce.calculationMode = .paced
        bounce.duration = travel

        // Pops in on the edge, holds, then fades out well before it leaves —
        // Victor wants them dissolving while the rainbow is still unrolling.
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0.0, 1.0, 1.0, 0.0]
        fade.keyTimes = [0, 0.12, 0.6, 1]
        fade.duration = travel

        let group = CAAnimationGroup()
        group.animations = [bounce, fade]
        group.duration = travel
        // Off the ONE instant the sound was started from — not off "now", which
        // would add this unicorn's own construction time to its beat offset.
        group.beginTime = clock0 + delay
        group.fillMode = .both               // stays at opacity 0 until it starts
        group.isRemovedOnCompletion = false
        unicorn.add(group, forKey: "unicornRun")
    }

    func stopRainbow() {
        guard let layer = activeEffects["rainbow"] else { return }
        activeEffects.removeValue(forKey: "rainbow")
        SoundManager.shared.stop("37_rainbow.mp3", fade: SoundManager.interruptFade)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.8)
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        layer.opacity = 0
        CATransaction.commit()
    }

    // MARK: - Brother (looping GIF, bottom-left area, toggled by tablet sound)

    // Decoded brother frames, pre-warmed at init. CGImageSourceCreateImageAtIndex
    // is lazy: creating the 174 CGImages takes ~30ms but the bitmap decode
    // (~450ms) happened at first render, so the GIF showed up half a second
    // after its sound (which starts one HTTP call earlier in the tablet-routed
    // path). Force-decoding into bitmap-backed CGImages up front makes the
    // animation start in sync with the sound, at the cost of ~100MB resident.
    private static var brotherCache: (frames: [CGImage], duration: Double, modDate: Date?)?
    private static let brotherDecodeQueue = DispatchQueue(label: "brother-gif-decode", qos: .userInitiated)

    static func warmBrotherCache() {
        brotherDecodeQueue.async { _ = decodedBrotherFrames() }
    }

    private static var brotherGifURL: URL? { EffectsConfig.shared.assetURL("brother_full.gif") }

    /// Decode every GIF frame into a bitmap-backed CGImage (cached by file mod
    /// date, so a re-downloaded GIF is picked up). Must run on brotherDecodeQueue.
    private static func decodedBrotherFrames() -> (frames: [CGImage], duration: Double)? {
        guard let gifURL = brotherGifURL else { return nil }
        let modDate = (try? FileManager.default.attributesOfItem(atPath: gifURL.path)[.modificationDate]) as? Date
        if let cache = brotherCache, cache.modDate == modDate {
            return (cache.frames, cache.duration)
        }

        guard let source = CGImageSourceCreateWithURL(gifURL as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        var frames: [CGImage] = []
        var totalDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            // Draw into a context to force the otherwise-lazy bitmap decode now.
            if let ctx = CGContext(data: nil, width: cg.width, height: cg.height,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
                frames.append(ctx.makeImage() ?? cg)
            } else {
                frames.append(cg)
            }
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.05
            totalDuration += delay
        }
        guard !frames.isEmpty else { return nil }

        brotherCache = (frames, totalDuration, modDate)
        return (frames, totalDuration)
    }

    func showBrother(playSound: Bool = true) {
        if cancelIfRunning("brother", sound: playSound ? "67_sfx_109.mp3" : nil) { return }

        Self.brotherDecodeQueue.async { [weak self] in
            guard let decoded = Self.decodedBrotherFrames() else {
                DispatchQueue.main.async {
                    overlayError("brother_full.gif not in \(EffectsConfig.shared.assetsDir.path)")
                }
                return
            }
            DispatchQueue.main.async {
                self?.startBrother(images: decoded.frames, totalDuration: decoded.duration, playSound: playSound)
            }
        }
    }

    private func startBrother(images: [CGImage], totalDuration: Double, playSound: Bool) {
        guard activeEffects["brother"] == nil else { return }  // double-trigger guard across the async hop

        let bounds = hostLayer.bounds
        let size = bounds.width * 0.32         // ~1/3 of screen width
        let x: CGFloat = 0                     // flush to left edge
        let y: CGFloat = -40                   // 40px below bottom

        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: x, y: y, width: size, height: size)
        gifLayer.contentsGravity = .resizeAspect
        if let first = images.first { gifLayer.contents = first }
        hostLayer.addSublayer(gifLayer)
        activeEffects["brother"] = gifLayer

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = totalDuration
        anim.repeatCount = .infinity

        CATransaction.begin()
        gifLayer.add(anim, forKey: "brotherFrames")
        CATransaction.commit()

        // Sound trails the animation by the paired-effect delay, matching
        // the tablet-routed path (see SoundManager.pairedEffectStartDelays).
        let soundDelay = SoundManager.pairedEffectStartDelays["67_sfx_109.mp3"] ?? 0
        if playSound {
            DispatchQueue.main.asyncAfter(deadline: .now() + soundDelay) {
                SoundManager.shared.play("67_sfx_109.mp3")
            }
        }
        // ALWAYS self-stop when the sound ends — the looping GIF must never
        // depend on the tablet's best-effort /sound/stopped → brother/stop
        // (lost on relay/network drops → brother danced forever). Identity-
        // guarded so an old run's timer can't kill a newer run.
        var soundDuration = 10.0
        if let soundURL = SoundManager.shared.soundURL(for: "67_sfx_109.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { soundDuration = CMTimeGetSeconds(d) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + soundDelay + soundDuration + 0.3) { [weak self, weak gifLayer] in
            guard let self, let gifLayer, self.activeEffects["brother"] === gifLayer else { return }
            self.stopBrother()
        }
    }

    func stopBrother() {
        _ = cancelIfRunning("brother", sound: "67_sfx_109.mp3")
    }

    // MARK: - Gangnam (looping transparent frames, toggled by sound #29)

    func showGangnam(playSound: Bool = true) {
        if cancelIfRunning("gangnam", sound: playSound ? "29_gangnam_style.mp3" : nil) { return }

        // Load each frame from assetsDir/gangnam_frames/frame_XXX.png. The GIF
        // path produced ghost trails because successive frames were
        // alpha-stacked once the background became transparent — a PNG sequence
        // sidesteps GIF disposal handling entirely.
        let framesDir = EffectsConfig.shared.assetsDir.appendingPathComponent("gangnam_frames")
        let frameURLs: [URL] = (try? FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension.lowercased() == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
        guard !frameURLs.isEmpty else {
            overlayError("no gangnam_frames/ in \(EffectsConfig.shared.assetsDir.path)")
            return
        }

        var images: [CGImage] = []
        for url in frameURLs {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { continue }
            images.append(cg)
        }
        guard !images.isEmpty else { return }

        // ~40ms per frame (≈ original 25fps gif cadence).
        let perFrame = 0.04
        let totalDuration = Double(images.count) * perFrame

        let bounds = hostLayer.bounds
        let size = bounds.height * 0.72          // +30% over the original 0.55 sizing
        let x: CGFloat = 0                       // flush to left edge
        let y: CGFloat = -20

        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: x, y: y, width: size, height: size)
        gifLayer.contentsGravity = .resizeAspect
        if let first = images.first { gifLayer.contents = first }
        hostLayer.addSublayer(gifLayer)
        activeEffects["gangnam"] = gifLayer

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = totalDuration
        anim.repeatCount = .infinity
        // Without .discrete Core Animation tries to interpolate between
        // adjacent frames; on a transparent GIF this causes ghost-trail
        // artefacts because successive frames are alpha-blended together.
        anim.calculationMode = .discrete

        CATransaction.begin()
        gifLayer.add(anim, forKey: "gangnamFrames")
        CATransaction.commit()

        if playSound {
            SoundManager.shared.play("29_gangnam_style.mp3")
        }
        // ALWAYS self-stop when the sound ends — the looping frames must never
        // depend on the tablet's best-effort /sound/stopped → gangnam/stop
        // (lost on relay/network drops → PSY danced forever). Identity-guarded
        // so an old run's timer can't kill a newer run.
        var soundDuration = 3.1
        if let soundURL = SoundManager.shared.soundURL(for: "29_gangnam_style.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { soundDuration = CMTimeGetSeconds(d) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + soundDuration + 0.3) { [weak self, weak gifLayer] in
            guard let self, let gifLayer, self.activeEffects["gangnam"] === gifLayer else { return }
            self.stopGangnam()
        }
    }

    func stopGangnam() {
        _ = cancelIfRunning("gangnam", sound: "29_gangnam_style.mp3")
    }

    // MARK: - Gong GIF overlay (bottom-left, full screen width)

    private func detectLastCycleLength(_ images: [CGImage]) -> Int {
        let n = images.count
        guard n >= 6 else { return 0 }
        let thumbSize = 32
        let pixelCount = thumbSize * thumbSize

        func thumb(_ img: CGImage) -> [UInt8] {
            var bytes = [UInt8](repeating: 0, count: pixelCount)
            let cs = CGColorSpaceCreateDeviceGray()
            guard let ctx = CGContext(data: &bytes, width: thumbSize, height: thumbSize,
                                      bitsPerComponent: 8, bytesPerRow: thumbSize,
                                      space: cs, bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return bytes }
            ctx.interpolationQuality = .low
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: thumbSize, height: thumbSize))
            return bytes
        }

        let thumbs = images.map(thumb)
        // Threshold: avg per-pixel grayscale diff <= 12 over the cycle window.
        let threshold = pixelCount * 12

        func framesMatch(_ a: Int, _ b: Int) -> Bool {
            let ta = thumbs[a]
            let tb = thumbs[b]
            var sum = 0
            for i in 0..<pixelCount {
                sum += abs(Int(ta[i]) - Int(tb[i]))
                if sum > threshold { return false }
            }
            return true
        }

        for k in 2...(n / 2) {
            var ok = true
            for i in 0..<k {
                let a = n - 1 - i
                let b = a - k
                if b < 0 || !framesMatch(a, b) { ok = false; break }
            }
            if ok { return k }
        }
        return 0
    }

    func showGong(playSound: Bool = true) {
        if cancelIfRunning("gong", sound: playSound ? "50_gong.mp3" : nil) { return }
        guard let url = Bundle.module.url(forResource: "gong", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var totalDuration: Double = 0
        let skipFrames = 43   // skip static standing-still prefix
        let stopFrame = 119   // frame 119 is a blank blue flash — stop before it
        for i in skipFrames..<min(stopFrame, count) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.05
            totalDuration += delay
        }

        let originalCount = images.count
        if originalCount >= 6 {
            let cycleLen = detectLastCycleLength(images)
            if cycleLen > 0 {
                let extraFrames = (originalCount + 1) / 2
                let repeats = max(1, (extraFrames + cycleLen - 1) / cycleLen)
                let cycle = Array(images.suffix(cycleLen))
                for _ in 0..<repeats { images.append(contentsOf: cycle) }
                totalDuration = totalDuration * Double(images.count) / Double(originalCount)
            }
        }

        let bounds = hostLayer.bounds
        let aspect: CGFloat = 600.0 / 800.0     // gong gif is 800x600
        let w = min(bounds.width, bounds.height / aspect)
        let h = w * aspect
        let x: CGFloat = -150                  // shifted 150px past the left edge
        let y: CGFloat = -310                  // shifted 310px toward the bottom of the screen

        let startDelay: TimeInterval = 0.3
        let startTime = CACurrentMediaTime() + startDelay

        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: x, y: y, width: w, height: h)
        gifLayer.contentsGravity = .resizeAspect
        if let first = images.first { gifLayer.contents = first }
        gifLayer.opacity = 0   // hidden during the start delay
        gifLayer.actions = ["opacity": NSNull()]
        hostLayer.addSublayer(gifLayer)
        activeEffects["gong"] = gifLayer

        let reveal = CABasicAnimation(keyPath: "opacity")
        reveal.fromValue = 0
        reveal.toValue = 1
        reveal.beginTime = startTime
        reveal.duration = 0.001
        reveal.fillMode = .both
        reveal.isRemovedOnCompletion = false

        let anim = CAKeyframeAnimation(keyPath: "contents")
        anim.values = images
        anim.duration = totalDuration
        anim.beginTime = startTime
        anim.repeatCount = 1
        anim.fillMode = .both
        anim.isRemovedOnCompletion = false

        CATransaction.begin()
        gifLayer.add(reveal, forKey: "gongReveal")
        gifLayer.add(anim, forKey: "gongFrames")
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + totalDuration) { [weak self] in
            _ = self?.cancelIfRunning("gong", sound: nil)
        }

        if playSound { SoundManager.shared.play("50_gong.mp3") }
    }

    // MARK: - Wrong X (two diagonal brush strokes, drawn one after the other)

    func showWrongX(playSound: Bool = true) {
        if cancelIfRunning("wrong-x", sound: playSound ? "49_wrong.mp3" : nil) { return }
        guard let url = Bundle.module.url(forResource: "leg", withExtension: "png"),
              let nsImg = NSImage(contentsOf: url),
              let cg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        let bounds = hostLayer.bounds
        let w = bounds.width * 0.5
        let aspect = CGFloat(cg.height) / CGFloat(cg.width)
        let h = w * aspect
        let legRect = CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)

        let container = CALayer()
        container.frame = bounds
        container.actions = ["opacity": NSNull()]   // no implicit opacity animation racing the fade
        hostLayer.addSublayer(container)
        activeEffects["wrong-x"] = container

        let drawEach: TimeInterval = 0.25          // 2× faster strike (was 0.5 per stroke)
        let totalDraw = 2 * drawEach
        let holdAfterDraw: TimeInterval = 1.04     // hold after the X is drawn, unchanged by the faster strike
        let fadeDuration: TimeInterval = 1.2

        func makeLeg(flipped: Bool) -> (CALayer, CALayer) {
            let leg = CALayer()
            leg.frame = legRect
            leg.contents = cg
            leg.contentsGravity = .resizeAspect
            if flipped { leg.transform = CATransform3DMakeScale(-1, 1, 1) }

            let mask = CALayer()
            // Silence implicit animations on this layer's bounds/position so
            // our explicit CABasicAnimation is the only thing driving width.
            mask.actions = ["bounds": NSNull(), "position": NSNull(), "frame": NSNull()]
            mask.backgroundColor = NSColor.black.cgColor
            mask.anchorPoint = CGPoint(x: 0, y: 0.5)
            mask.position = CGPoint(x: 0, y: h / 2)
            mask.bounds = CGRect(x: 0, y: 0, width: w, height: h)   // final width — held by animation
            leg.mask = mask
            return (leg, mask)
        }

        let (legA, maskA) = makeLeg(flipped: false)
        let (legB, maskB) = makeLeg(flipped: true)
        container.addSublayer(legA)
        container.addSublayer(legB)

        let startTime = CACurrentMediaTime()
        func scheduleDraw(_ mask: CALayer, beginTime: CFTimeInterval) {
            let anim = CABasicAnimation(keyPath: "bounds.size.width")
            anim.fromValue = 0
            anim.toValue = w
            anim.duration = drawEach
            anim.beginTime = beginTime
            anim.fillMode = .both
            anim.isRemovedOnCompletion = false
            mask.add(anim, forKey: "draw")
        }
        scheduleDraw(maskA, beginTime: startTime)
        scheduleDraw(maskB, beginTime: startTime + drawEach)

        let fadeStart = totalDraw + holdAfterDraw
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        fade.duration = fadeDuration
        fade.beginTime = startTime + fadeStart
        fade.fillMode = .both
        fade.isRemovedOnCompletion = false
        container.add(fade, forKey: "fade")

        DispatchQueue.main.asyncAfter(deadline: .now() + fadeStart + fadeDuration) { [weak self] in
            _ = self?.cancelIfRunning("wrong-x", sound: nil)
        }

        if playSound { SoundManager.shared.play("49_wrong.mp3") }
    }

    // MARK: - Drum roll GIF overlay (bottom-left, loops until stopped)

    func showDrumRoll(playSound: Bool = true) {
        if cancelIfRunning("drum-roll", sound: playSound ? "26_drum.mp3" : nil) { return }
        guard let url = Bundle.module.url(forResource: "drum", withExtension: "gif"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return }

        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return }

        var images: [CGImage] = []
        var cycleDuration: Double = 0
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            images.append(cg)
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any]
            let gif = props?[kCGImagePropertyGIFDictionary as String] as? [String: Any]
            let delay = gif?[kCGImagePropertyGIFDelayTime as String] as? Double ?? 0.1
            cycleDuration += delay
        }
        cycleDuration /= 2.0  // play 2× faster than GIF native speed

        let bounds = hostLayer.bounds
        let w = bounds.width * 0.40
        let x = (bounds.width - w) / 2
        let y = (bounds.height - w) / 2
        let gifLayer = CALayer()
        gifLayer.frame = CGRect(x: x, y: y, width: w, height: w)
        gifLayer.contentsGravity = .resizeAspect
        gifLayer.opacity = 0.5
        if let first = images.first { gifLayer.contents = first }
        hostLayer.addSublayer(gifLayer)
        activeEffects["drum-roll"] = gifLayer

        let n = images.count
        let keyTimes = (0..<n).map { NSNumber(value: Double($0) / Double(n)) }

        func startCycle() {
            let anim = CAKeyframeAnimation(keyPath: "contents")
            anim.values = images
            anim.keyTimes = keyTimes
            anim.duration = cycleDuration
            anim.calculationMode = .discrete
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            CATransaction.begin()
            CATransaction.disableActions()
            gifLayer.add(anim, forKey: "drumRollFrames")
            CATransaction.commit()
        }

        startCycle()

        // Restart animation 2ms before cycle end to avoid repeatCount loop-boundary pause
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + cycleDuration - 0.002, repeating: cycleDuration)
        timer.setEventHandler { [weak gifLayer] in
            // Self-cancel once the layer left the tree (stop-all removes layers
            // directly, without stopDrumRoll) — otherwise this timer would keep
            // firing no-ops forever. Cancellation releases the handler, breaking
            // the timer→handler→timer retain cycle.
            guard gifLayer?.superlayer != nil else { timer.cancel(); return }
            startCycle()
        }
        timer.resume()
        drumRollTimer = timer

        if playSound { SoundManager.shared.play("26_drum.mp3") }

        // ALWAYS self-stop when the sound ends — this loop previously had NO
        // self-termination and relied entirely on the tablet's best-effort
        // /sound/stopped → drum-roll/stop (lost on relay/network drops → the
        // drum rolled forever). Identity-guarded so an old run's timer can't
        // kill a newer run.
        var soundDuration = 6.2
        if let url = SoundManager.shared.soundURL(for: "26_drum.mp3") {
            let d = AVURLAsset(url: url).duration
            if d.isNumeric { soundDuration = CMTimeGetSeconds(d) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + soundDuration + 0.3) { [weak self, weak gifLayer] in
            guard let self, let gifLayer, self.activeEffects["drum-roll"] === gifLayer else { return }
            self.stopDrumRoll()
        }
    }

    func stopDrumRoll() {
        guard let layer = activeEffects.removeValue(forKey: "drum-roll") else { return }
        SoundManager.shared.stop("26_drum.mp3", fade: SoundManager.interruptFade)
        // Keep drumming while fading out, then clean up. The loop-restart timer
        // is NOT cancelled here — `drumRollTimer` may already belong to a newer
        // run started during the fade; each timer self-cancels on its next tick
        // once its own layer has left the tree (see showDrumRoll).
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.opacity
        fade.toValue = 0.0
        fade.duration = 1.0
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            layer.removeFromSuperlayer()
        }
        layer.add(fade, forKey: "fadeOut")
        CATransaction.commit()
    }

    // MARK: - Laugh (🤣 rolls in from left to center at full opacity, then continues + fades; 3 extra laugh emojis)

    private struct EmojiPlacement {
        var centerX: CGFloat
        var centerY: CGFloat
        var size: CGFloat

        func intersects(_ other: EmojiPlacement) -> Bool {
            // Emojis travel horizontally at constant Y, so only vertical separation matters
            let minDist = (size + other.size) / 2
            let dy = abs(centerY - other.centerY)
            return dy < minDist
        }
    }

    func showLaugh() {
        let bounds = hostLayer.bounds
        let size: CGFloat = bounds.height / 4 * 1.2
        let duration: Double = 2.0
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        // Phase geometry for main emoji
        let mainStartX: CGFloat = -size / 2
        let mainMidX: CGFloat = bounds.midX          // end of phase 1 / start of phase 2
        let mainEndX: CGFloat = bounds.midX + 0.25 * bounds.width  // end of phase 2

        let totalDistance = mainEndX - mainStartX
        let phase1Distance = mainMidX - mainStartX
        let phase1Fraction = phase1Distance / totalDistance   // time fraction for phase 1

        // Track placements for collision detection
        var placements: [EmojiPlacement] = [
            EmojiPlacement(centerX: (mainStartX + mainMidX) / 2, centerY: bounds.midY, size: size)
        ]

        // Helper: animate one laugh emoji
        func animateLaughEmoji(emoji: String, emojiSize: CGFloat, startX: CGFloat, endX: CGFloat,
                               centerY: CGFloat, fadeFraction: Double, layer: CATextLayer) {
            let fontSize: CGFloat = emojiSize * 0.85
            layer.string = emoji
            layer.fontSize = fontSize
            layer.alignmentMode = .center
            layer.frame = CGRect(x: startX - emojiSize / 2, y: centerY - emojiSize / 2,
                                 width: emojiSize, height: emojiSize)
            layer.contentsScale = scale
            hostLayer.addSublayer(layer)

            let distance = endX - startX
            // Negate: y-up CALayer positive rotation = CCW; rolling right = CW = negative
            let totalRotation = -(distance / (CGFloat.pi * emojiSize)) * (2 * CGFloat.pi)

            let pathAnim = CAKeyframeAnimation(keyPath: "position")
            let path = CGMutablePath()
            path.move(to: CGPoint(x: startX, y: centerY))
            path.addLine(to: CGPoint(x: endX, y: centerY))
            pathAnim.path = path
            pathAnim.timingFunction = CAMediaTimingFunction(name: .linear)

            let rotAnim = CABasicAnimation(keyPath: "transform.rotation.z")
            rotAnim.fromValue = 0
            rotAnim.toValue = totalRotation
            rotAnim.timingFunction = CAMediaTimingFunction(name: .linear)

            let fadeAnim = CABasicAnimation(keyPath: "opacity")
            fadeAnim.fromValue = 1.0
            fadeAnim.toValue = 0.0
            fadeAnim.beginTime = duration * fadeFraction
            fadeAnim.duration = duration * (1.0 - fadeFraction)
            fadeAnim.fillMode = .forwards

            let group = CAAnimationGroup()
            group.animations = [pathAnim, rotAnim, fadeAnim]
            group.duration = duration
            group.fillMode = .forwards
            group.isRemovedOnCompletion = false

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak layer] in layer?.removeFromSuperlayer() }
            layer.add(group, forKey: "laugh")
            CATransaction.commit()
        }

        // Main emoji: two-phase — full opacity to center, then fade to center+25%
        // We model this as traveling mainStartX → mainEndX with fade starting at phase1Fraction
        let mainLayer = CATextLayer()
        animateLaughEmoji(emoji: "🤣", emojiSize: size,
                          startX: mainStartX, endX: mainEndX,
                          centerY: bounds.midY,
                          fadeFraction: Double(phase1Fraction),
                          layer: mainLayer)

        // Helper: random Y placement for an extra emoji that doesn't intersect existing ones
        func randomYForSize(_ extraSize: CGFloat, existingPlacements: [EmojiPlacement], approxCenterX: CGFloat) -> CGFloat? {
            for _ in 0..<20 {
                let minY = extraSize / 2
                let maxY = bounds.height - extraSize / 2
                guard maxY > minY else { return bounds.midY }
                let candidateY = CGFloat.random(in: minY...maxY)
                let candidate = EmojiPlacement(centerX: approxCenterX, centerY: candidateY, size: extraSize)
                if !existingPlacements.contains(where: { candidate.intersects($0) }) {
                    return candidateY
                }
            }
            return nil
        }

        // Extra 1: from left (😂), different Y
        let extra1Size = CGFloat.random(in: size / 4 ... size)
        let extra1StartX: CGFloat = -extra1Size / 2
        let extra1EndX: CGFloat = bounds.midX + CGFloat.random(in: -0.1 * bounds.width ... 0.1 * bounds.width)
        let extra1ApproxCenterX = (extra1StartX + extra1EndX) / 2
        let extra1Y: CGFloat
        if let y = randomYForSize(extra1Size, existingPlacements: placements, approxCenterX: extra1ApproxCenterX) {
            extra1Y = y
        } else {
            // Fallback: place at 1/4 height if no non-overlapping position found
            extra1Y = bounds.height * 0.25
        }
        placements.append(EmojiPlacement(centerX: extra1ApproxCenterX, centerY: extra1Y, size: extra1Size))

        let extra1Layer = CATextLayer()
        animateLaughEmoji(emoji: "😂", emojiSize: extra1Size,
                          startX: extra1StartX, endX: extra1EndX,
                          centerY: extra1Y,
                          fadeFraction: Double(phase1Fraction),
                          layer: extra1Layer)

        // Extras 2 & 3: from right (random emoji), travel leftward toward center area
        let rightExtras = [2, 3]
        let rightEmojis = ["🤣", "😂"]
        for (i, _) in rightExtras.enumerated() {
            let extraSize = CGFloat.random(in: size / 4 ... size)
            let extraStartX: CGFloat = bounds.width + extraSize / 2
            let extraEndX: CGFloat = bounds.midX + CGFloat.random(in: -0.15 * bounds.width ... 0.15 * bounds.width)
            let extraApproxCenterX = (extraStartX + extraEndX) / 2
            let extraY: CGFloat
            if let y = randomYForSize(extraSize, existingPlacements: placements, approxCenterX: extraApproxCenterX) {
                extraY = y
            } else {
                // Fallback: space evenly — 3/4 height for first right extra, 1/2 for second
                extraY = i == 0 ? bounds.height * 0.75 : bounds.height * 0.5
            }
            placements.append(EmojiPlacement(centerX: extraApproxCenterX, centerY: extraY, size: extraSize))

            let extraEmoji = rightEmojis[Int.random(in: 0..<rightEmojis.count)]
            let extraLayer = CATextLayer()
            animateLaughEmoji(emoji: extraEmoji, emojiSize: extraSize,
                              startX: extraStartX, endX: extraEndX,
                              centerY: extraY,
                              fadeFraction: Double(phase1Fraction),
                              layer: extraLayer)
        }
    }

    // MARK: - Santa (🎅 slides in from left to top-left corner, stays, then fades out)

    func showSanta() {
        let bounds = hostLayer.bounds
        let emojiSize: CGFloat = bounds.height / 2
        let fontSize: CGFloat = emojiSize * 0.85
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0

        let finalX: CGFloat = 0
        let finalY: CGFloat = bounds.height - emojiSize
        let startX: CGFloat = -emojiSize

        let layer = CATextLayer()
        layer.string = "🎅"
        layer.fontSize = fontSize
        layer.alignmentMode = .center
        layer.frame = CGRect(x: startX, y: finalY, width: emojiSize, height: emojiSize)
        layer.contentsScale = scale
        hostLayer.addSublayer(layer)

        let slideInDuration: Double = 1.0
        let stayDuration: Double = 2.0
        let fadeOutDuration: Double = 2.0
        let totalDuration: Double = slideInDuration + stayDuration + fadeOutDuration

        // Slide in: x from startX → finalX
        let slideAnim = CABasicAnimation(keyPath: "position.x")
        slideAnim.fromValue = startX + emojiSize / 2
        slideAnim.toValue = finalX + emojiSize / 2
        slideAnim.duration = slideInDuration
        slideAnim.timingFunction = CAMediaTimingFunction(name: .easeOut)
        slideAnim.fillMode = .forwards

        // Fade out: starts after slideIn + stay
        let fadeAnim = CABasicAnimation(keyPath: "opacity")
        fadeAnim.fromValue = 1.0
        fadeAnim.toValue = 0.0
        fadeAnim.beginTime = slideInDuration + stayDuration
        fadeAnim.duration = fadeOutDuration
        fadeAnim.fillMode = .forwards

        let group = CAAnimationGroup()
        group.animations = [slideAnim, fadeAnim]
        group.duration = totalDuration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak layer] in layer?.removeFromSuperlayer() }
        layer.add(group, forKey: "santa")
        // Set model layer position to final so slide ends correctly
        layer.position = CGPoint(x: finalX + emojiSize / 2, y: finalY + emojiSize / 2)
        CATransaction.commit()
    }

    // MARK: - Stop game-over overlay (once the CRT shutters have closed over it)

    /// The client sends this when the clip ends, which is the same instant the
    /// tube starts closing — so the delay is the length of that close, not the
    /// old 0.5 s. Cutting the picture mid-close would show the bare desktop
    /// through the gap the shutters have not covered yet.
    func stopGameOver() {
        DispatchQueue.main.asyncAfter(deadline: .now() + CrtShutdown.closeDuration + 0.05) { [weak self] in
            _ = self?.cancelIfRunning("game-over")
        }
    }

    // MARK: - 🔥 Fire cursor (tile #11 — the pointer becomes a burning flame)

    /// Same sprite-SHEET reasoning as the chainsaw: fire is nothing but soft
    /// edges and glow, and gif carries 1-bit alpha, so a gif of it fringes black
    /// against every desktop. `fire-frames.png` is an 8×5 grid of 40 equal cells
    /// keyed out of the original clip (alpha = luminance ×2, clamped) and read
    /// row-major. The ×2 is not a brightness trick: straight luminance-as-alpha
    /// leaves the flame's orange edges and every spark half-transparent, which
    /// over a slide reads as a washed-out stain rather than as fire on top of it.
    private static let fireGrid = (cols: 8, rows: 5)

    /// The 40 frames, decoded once. Same reason as the chainsaw's: the press has
    /// to be instant because the cursor is already moving under the user's hand.
    private static let fireFrames: [CGImage] = {
        guard let url = Bundle.module.url(forResource: "fire-frames", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return [] }
        let cw = sheet.width / fireGrid.cols
        let ch = sheet.height / fireGrid.rows
        var frames: [CGImage] = []
        for row in 0..<fireGrid.rows {
            for col in 0..<fireGrid.cols {
                let rect = CGRect(x: col * cw, y: row * ch, width: cw, height: ch)
                if let cell = sheet.cropping(to: rect) { frames.append(cell) }
            }
        }
        return frames
    }()

    /// The flame's own root, near the bottom edge of the frame and centred —
    /// THAT is the point riding the pointer, so the fire grows *upward out of*
    /// the cursor instead of swallowing it. Deliberately not the centre (the
    /// chainsaw's choice): a centred flame would put half the smoke plume below
    /// the hand, and the thing being pointed at is what should be on fire.
    private static let fireRootAnchor = CGPoint(x: 0.5, y: 0.10)

    /// Displayed width in points at scale 1 — the size a FIRST press starts at,
    /// before the wheel is touched (later presses reopen at the remembered size,
    /// see `fireRememberedScale`). Halved on 2026-09-09 (280 → 140) because at
    /// 280 the flame stopped reading as a *pointer*; put back to 280 on
    /// 2026-09-10 at Victor's request. What makes 280 workable now is the pair
    /// of changes below it: the size survives the run, so shrinking to a torch
    /// is a one-time gesture rather than a per-press tax, and the wheel reaches
    /// the full screen width, so the default is no longer near the ceiling.
    private static let fireBaseWidth: CGFloat = 280

    /// The source clip's own rate (40 frames / 1.33 s). Kept at 30 rather than
    /// halved like the chainsaw's 15: this one is on screen for the length of a
    /// 36 s sound, and fire at 15 fps reads as a strobing loop within seconds.
    private static let fireFPS: Double = 30

    /// Fallback length if `11_fire.mp3` can't be measured (its real one).
    private static let fireFallbackDuration: Double = 35.88

    /// Wheel-resize envelope. One notch is a multiply, not an add, so the step
    /// feels the same size at a candle and at a bonfire.
    private static let fireScaleStep: CGFloat = 1.10
    private static let fireMinScale: CGFloat = 0.30

    /// The ceiling is the SCREEN, not a number: the wheel can grow the flame
    /// until it is exactly as wide as the display it burns on. A fixed multiple
    /// (3.5 was the old one) means the biggest fire is a different fraction of a
    /// 13" retina than of a projector, and "as big as it goes" is the size Victor
    /// actually reaches for on stage. Falls back to the main screen while the
    /// overlay has no bounds yet (first frame of a fresh run).
    private var fireMaxScale: CGFloat {
        let width = hostLayer.bounds.width > 0
            ? hostLayer.bounds.width
            : (NSScreen.main?.frame.width ?? 1_440)
        return max(Self.fireMinScale, width / Self.fireBaseWidth)
    }

    /// The wheel size the LAST run ended at, kept for the life of the process.
    /// Sizing the flame is a deliberate gesture — a couple of seconds of
    /// scrolling with everyone watching — and having it snap back to default on
    /// the next press made that gesture disposable. RAM only, on purpose: a new
    /// day (a restart) starts from the neutral size rather than from whatever
    /// one demo needed.
    private static var fireRememberedScale: CGFloat = 1

    // MARK: The fireball the pointer turns into (2026-09-22)

    /// Victor: *"doar vorbim despre înlocuirea cursorului"* — the pointer is a
    /// **burning sphere**, and nothing downstream of it moved.
    ///
    /// It replaced the drawn match of 2026-09-18/19, and the match is worth
    /// remembering, because it answered a real problem: a bare flame hanging on
    /// the pointer read as a *decal* over the slide, and the gesture the effect
    /// invites — clicking to set something alight — had nothing doing the
    /// lighting. The match gave the flame a cause. A fireball needs no cause,
    /// because it is not a flame *on* the pointer: it IS the pointer, and "why
    /// click?" still has an answer — to put some of it down.
    ///
    /// **One ball, not three.** It shipped as a rotation of three sheets the
    /// same afternoon and lost two of them within the hour (*"bila a doua …
    /// sfera care arde ca un soare … las-o doar pe ea, de departe"*). The
    /// rotation was answering a question nobody had asked: a tile pressed twice
    /// in an hour does not need to surprise anybody the second time, and the
    /// other two balls were a spiky burst and a flat cartoon — neither of which
    /// is what a fire *starts* from. The two sheets are gone from `Resources/`
    /// rather than left unused; `tools/make-fireball-sheets.py` and the history
    /// are where they live now.
    ///
    /// **A sheet, not the gif it came from** — `fire-frames.png`'s reason,
    /// unchanged: a gif carries 1-bit alpha, so a gif of fire fringes against
    /// every desktop. The tool keys the matte into 8-bit alpha and writes the
    /// grid, read row-major exactly like the flame's. This clip needed one
    /// trick beyond that, documented there: its interior is genuinely BLACK
    /// (dark rock between glowing veins) and a luminance key cannot tell that
    /// black from the black around the ball, so the sphere is given a forced
    /// opaque core or the slide shows through its cracks.
    struct Fireball {
        let asset: String
        let cols: Int, rows: Int
        /// Frames actually in the sheet. The last row is short — `cols * rows`
        /// is the grid, this is the count, and cropping past it would hand the
        /// animation a strip of empty cells to flash through.
        let count: Int
        /// The clip's own rate, not the flame's `fireFPS`: this sheet is 16.7,
        /// that one is 30, and a sprite played at somebody else's rate either
        /// strobes or crawls.
        let fps: Double
    }

    /// The ball the pointer becomes. A dense sphere of dark rock under glowing
    /// veins — *"sfera care arde ca un soare"*.
    static let fireball = Fireball(asset: "fireball-plasma", cols: 6, rows: 6, count: 32, fps: 16.7)

    /// Cells cut out of the sheet, once and kept for the life of the process.
    /// The press has to be instant — the cursor is already moving under his hand
    /// — and this is 3 MB of png to decode.
    private static var fireballFrameCache: [CGImage]?

    static func fireballFrames(_ ball: Fireball = fireball) -> [CGImage] {
        if let cached = fireballFrameCache { return cached }
        guard let url = Bundle.module.url(forResource: ball.asset, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            fireballFrameCache = []   // a missing sheet is asked about once
            return []
        }
        let cw = sheet.width / ball.cols
        let ch = sheet.height / ball.rows
        var frames: [CGImage] = []
        for i in 0..<ball.count {
            let rect = CGRect(x: (i % ball.cols) * cw, y: (i / ball.cols) * ch,
                              width: cw, height: ch)
            if let cell = sheet.cropping(to: rect) { frames.append(cell) }
        }
        fireballFrameCache = frames
        return frames
    }

    /// The pointer ball's displayed width, in points. Halved from 150 on the day
    /// it shipped (*"micșorează-o la 50%"*), which put it at a bit over a
    /// quarter of the flame's `fireBaseWidth` (280). That ratio is the point:
    /// this is the POINTER, and the fire it lights is the thing that should be
    /// big. It does not move with the wheel, for the reason the match's size did
    /// not either — the wheel belongs to the fire on the ground, and a pointer
    /// that grew with it would leave him sizing two things with one gesture.
    static let fireballCursorWidth: CGFloat = 75

    /// **The ball is drawn UNDER the fires it starts** (`zPosition` 9 350
    /// against their 9 400). It was 9 450 — above them — for the match's reason,
    /// that a pointer passes in front of things. A ball of fire is not a
    /// pointer-shaped arrow, though: drawn over a blaze twice its size it reads
    /// as *floating on top of* the fire rather than as the thing that started
    /// it, and at 75 pt it simply disappears into the flame it is sitting on.
    /// Underneath, the fire swallows it as it grows, which is the right story
    /// and the right silhouette.
    static let fireballZ: CGFloat = 9_350

    /// **After each fire is laid the ball gets out of the way**: it vanishes on
    /// the instant of the click, stays gone for `fireballHideAfterPlant`, and
    /// then fades back over `fireballReturnFade` — *"mărind impactul focului
    /// care l-a născut"*. The blackout is the whole effect: a new fire has about
    /// two seconds of being the only thing that moved, instead of sharing the
    /// frame with the ball that made it.
    ///
    /// The clock RESTARTS on every plant, so a drag that lays a line of fires
    /// keeps the ball away for the whole sweep and it returns once, after the
    /// last one — the alternative is a ball strobing in and out every 50 pt of
    /// travel.
    ///
    /// 3 s and 0.5 s since he watched it (the first pass was 2 s and 0.7 s): a
    /// longer gap and a quicker return, which is the pair that makes the beat
    /// land — the silence is what the new fire gets to itself, and dragging the
    /// ball back in slowly only spends some of it again.
    static let fireballHideAfterPlant: Double = 3.0
    static let fireballReturnFade: Double = 0.5

    /// The ball's entry fade. A function rather than six lines inline so a test
    /// can hold the thing that broke: see `testTheFireballEntryFadeRemovesItself`.
    static func fireballEntryFade() -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.0
        fade.toValue = 1.0
        fade.duration = 0.12
        return fade
    }

    /// The ball's box, keeping the sheet's aspect. Pure, so the geometry is
    /// asserted without a screen — see `EmojiAnimatorTests`.
    static func fireballBounds(for frame: CGImage) -> CGRect {
        let w = fireballCursorWidth
        return CGRect(x: 0, y: 0, width: w,
                      height: w * CGFloat(frame.height) / CGFloat(frame.width))
    }

    /// The fireball riding the mouse, and the whole test for "he is still
    /// carrying it": nil once Escape has put it out, which is what lets the tap
    /// go on living for a second Escape while passing his clicks and scrolls
    /// through to the fires already standing.
    private var _firePointerLayer: CALayer?

    private var _fireTimer: Timer?
    private var _fireHidCursor = false            // balance hide/unhide of the real cursor
    private var _fireGeneration = 0               // guards a stale run's self-stop against a newer one
    private var _fireScale: CGFloat = 1           // wheel-driven size of the last fire struck
    private var _fireInputTap: CFMachPort?
    private var _fireInputTapSource: CFRunLoopSource?
    private var _fireScrollAccum: CGFloat = 0     // trackpad pixels → notches
    private var _firePlanted: [CALayer] = []      // fires struck by clicking, oldest first; the LAST is the wheel's
    private var _fireLastPlantPoint: CGPoint?     // where the last one was struck; the drag measures from here
    private var _fireballHideToken = 0            // every plant bumps it; a stale return bails

    /// How far the fireball has to travel before a drag plants the next fire.
    /// Small enough that a sweep reads as a continuous line of flame, large
    /// enough that the flames stay separate fires rather than one smeared blob
    /// — and that a second of wrist movement doesn't exhaust `fireMaxPlanted`.
    private static let fireDragSpacing: CGFloat = 50

    /// How long a fire takes to climb to its full size, and the fraction of it
    /// it starts from. Not zero: a fire growing out of nothing is a dot
    /// expanding, while one that starts as a spark and takes hold is what the
    /// eye reads as catching.
    private static let fireCatchDuration: Double = 0.5
    private static let fireCatchFromScale: CGFloat = 0.15

    /// Ceiling on planted fires. Never reached by hand — it exists so a stuck
    /// mouse button (or a tablet demo where the trackpad gets leaned on) can't
    /// grow the layer tree without bound during the 36 s the clip runs. Past it
    /// the oldest fire is put out to make room, which reads as the first one
    /// having burnt itself out rather than as a limit.
    private static let fireMaxPlanted = 60

    /// Replace the mouse pointer with a **burning fireball** that follows it
    /// across the built-in screen. A click puts some of it down as a standing
    /// fire, the
    /// wheel then sizes **that** fire on the spot, and the next click starts
    /// another one. Unlike every other tile effect this one has THREE ways to
    /// end — the length of `11_fire.mp3`, an Escape keypress, or the tablet's
    /// stop.
    ///
    /// The pointer used to be an unlit match (2026-09-18/19) and is a fireball
    /// since 2026-09-22; the reasoning for both, and for why nothing downstream
    /// moved with it, is under **the fireball the pointer turns into** above.
    ///
    /// Not a `trackEffect` client, for the chainsaw's reason: it owns a follow
    /// timer, an event tap and a hidden system cursor, so it must be torn down
    /// through `stopFireCursor` and never by the generic `activeEffects` sweep,
    /// which would drop the layer and leave the desktop with no cursor at all.
    func showFireCursor(playSound: Bool = true) {
        guard Self.fireFrames.first != nil else {
            overlayError("fire-frames.png not found in bundle")
            return
        }
        let ball = Self.fireball
        let ballFrames = Self.fireballFrames()
        guard let firstBallFrame = ballFrames.first else {
            overlayError("\(ball.asset).png not found in bundle")
            return
        }

        stopFireCursor(fade: 0)   // never leak a previous run's timer/tap/hidden cursor

        var duration = Self.fireFallbackDuration
        if let soundURL = SoundManager.shared.soundURL(for: "11_fire.mp3") {
            let d = AVURLAsset(url: soundURL).duration
            if d.isNumeric { duration = CMTimeGetSeconds(d) }
        }

        // The size the NEXT fire is struck at: the one the last one was left at,
        // clamped in case that run happened on a wider screen (a projector
        // unplugged since). From the first click on, the wheel moves this and the
        // fire it belongs to together.
        _fireScale = min(fireMaxScale, max(Self.fireMinScale, Self.fireRememberedScale))
        Self.fireRememberedScale = _fireScale
        _fireScrollAccum = 0

        // **The fireball is the whole pointer** (2026-09-22). Its CENTRE is the
        // anchor — a ball has no tip, and the middle of it is where the eye puts
        // the pointer — so that is the pixel that rides the mouse and the point
        // a click plants a fire at. Its size is FIXED at `fireballCursorWidth`:
        // the wheel belongs to the fire on the ground. `fireballZ` puts it
        // BELOW the fires it starts — see that constant for why.
        let pointer = CALayer()
        pointer.bounds = Self.fireballBounds(for: firstBallFrame)
        pointer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        pointer.contents = firstBallFrame
        pointer.contentsGravity = .resizeAspect
        pointer.zPosition = Self.fireballZ
        pointer.opacity = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pointer.position = mousePointInHostLayer()
        CATransaction.commit()
        hostLayer.addSublayer(pointer)
        _firePointerLayer = pointer

        // The ball burns on its own clip's clock, not on the 60 Hz follow timer:
        // the timer's job is *where* the pointer is, and a sprite driven from it
        // would tie the flame's rate to how often we can afford to poll the
        // mouse. Discrete, so each cell is shown rather than cross-faded into
        // the next — a blended fire is a blur.
        let burn = CAKeyframeAnimation(keyPath: "contents")
        burn.values = ballFrames
        burn.duration = Double(ballFrames.count) / ball.fps
        burn.repeatCount = .infinity
        burn.calculationMode = .discrete
        pointer.add(burn, forKey: "burn")

        // Snap in rather than drift in, same as the chainsaw: the cursor is a
        // thing the user is already looking at, and a slow fade there reads as lag.
        //
        // It REMOVES ITSELF when it is done, unlike the match's version, which
        // held `fillMode = .forwards` and `isRemovedOnCompletion = false`. On
        // the match that was harmless because nothing ever hid it; on the ball
        // it was a silent bug with teeth — a finished animation that goes on
        // filling forwards keeps *overriding the model layer*, so
        // `hideFireballWhileTheFireTakes` set `opacity = 0` and the ball stayed
        // visibly, stubbornly on screen. The model value is already 1 before it
        // is added, so there is nothing for the fill to preserve anyway.
        pointer.opacity = 1
        pointer.add(Self.fireballEntryFade(), forKey: "fadeIn")

        // Hide the real pointer for the run. The arm step lifts the "frontmost
        // app only" restriction so it also works while the user is in another
        // app (the common case). Balanced in stopFireCursor.
        if !_fireHidCursor {
            Self.armBackgroundCursorHiding()
            NSCursor.hide()
            CGDisplayHideCursor(CGMainDisplayID())
            _fireHidCursor = true
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self, self._fireTimer === t else { t.invalidate(); return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)   // follow instantly, no implicit animation
            // The ball's anchor IS its centre, so this one assignment is what
            // puts the ball under the pointer at every size — and what makes the
            // fire a click plants stand exactly where the ball was.
            self._firePointerLayer?.position = self.mousePointInHostLayer()
            CATransaction.commit()
        }
        _fireTimer = timer

        startFireInputCapture()

        if playSound { SoundManager.shared.play("11_fire.mp3") }

        // The sound's length is the authoritative teardown, never the tablet's
        // /sound/stopped (which a flaky venue network eats — and here that would
        // leave the desktop with no visible cursor at all). Escape is the second
        // way out; both funnel through stopFireCursor. Generation-guarded so an
        // old run's timer can't kill a newer run.
        _fireGeneration += 1
        let generation = _fireGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, self._fireGeneration == generation else { return }
            self.stopFireCursor()
        }
    }

    /// Put the real pointer back. Idempotent — Escape, the early stop from the
    /// tablet, the natural end of the clip and `stopAllActiveEffects` all funnel
    /// here. The system cursor is restored only once the flame has finished
    /// fading, so the two are never on screen together.
    func stopFireCursor(fade: Double = 0.25) {
        _fireTimer?.invalidate(); _fireTimer = nil
        _fireGeneration += 1      // any pending self-stop is now stale
        stopFireInputCapture()

        let restoreCursor = { [weak self] in
            guard let self, self._fireHidCursor else { return }
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            self._fireHidCursor = false
        }

        let pointer = _firePointerLayer
        _firePointerLayer = nil
        // `_fireScale` is NOT reset — `fireRememberedScale` already holds it and
        // the next press reads it back.

        // Every fire the user planted goes out with the one on the pointer. They
        // are deliberately NOT in `activeEffects`: the whole set is this run's
        // property, so the same Escape / clip-end / tablet-stop that restores the
        // cursor also clears the desktop, and no sweep can take them separately.
        let planted = _firePlanted
        _firePlanted = []
        _fireLastPlantPoint = nil

        let teardown = {
            for layer in planted {
                layer.removeAllAnimations()
                layer.removeFromSuperlayer()
            }
            pointer?.removeAllAnimations()
            pointer?.removeFromSuperlayer()
            restoreCursor()
        }

        let held = planted + [pointer].compactMap { $0 }
        guard fade > 0, !held.isEmpty else { teardown(); return }

        for layer in held {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = layer.presentation()?.opacity ?? 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = fade
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "fadeOut")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: teardown)
    }

    /// **Escape puts the fireball out and leaves the fires he lit** (2026-09-18).
    ///
    /// Victor: *"if I click Escape, the match and the fire disappear, and only
    /// the fire that I've laid on the screen remain behind."* Until now Escape
    /// was one thing — *stop the whole effect* — and it took the planted fires
    /// with it, which made planting them pointless: the only way to keep a
    /// burning screen was to keep carrying the fire around over it.
    ///
    /// So Escape is now the **pointer's** exit, not the effect's. The fires he
    /// lit go on burning, the real pointer comes straight back — **and so does
    /// the sound** (2026-09-22: *"la primul escape sa ramana focurile +
    /// SUNET"*). That first press used to cut the clip too, on the reasoning
    /// that Escape means *enough*; it does not, when there are fires standing.
    /// A burning screen in silence is a screenshot. The first Escape hands him
    /// back his mouse and leaves the scene exactly as it was — fires, crackle
    /// and all — and only the press that clears the fires takes the sound with
    /// them.
    ///
    /// **What still puts THEM out**, because nothing here is allowed to live
    /// forever (the self-termination rule): the clip's own length, which is
    /// already scheduled and is deliberately NOT cancelled here — that is why
    /// this does not touch `_fireGeneration` — plus a second Escape, the
    /// tablet's stop and `stopAllActiveEffects`. With nothing planted there is
    /// nothing to keep, so Escape is the full stop it always was.
    fileprivate func escapeFire() {
        // Nothing left standing → this press IS the full stop, so it takes the
        // sound with it. `stopTabletSound` reaches the routed clip; a press the
        // tablet chose to play on its OWN speaker is not ours to stop.
        guard _firePointerLayer != nil, !_firePlanted.isEmpty else {
            SoundManager.shared.stopTabletSound()
            SoundManager.shared.stopAllPlayers()
            stopFireCursor()
            return
        }
        // Fires standing: only the ball goes. The clip plays on under them.
        blowOutFireball()
    }

    /// The pointer half of the teardown: the fireball and the hidden cursor.
    /// The planted fires and the tap are left standing — the tap because a
    /// second Escape has to be able to clear the screen, and it passes clicks
    /// and scrolls through from this moment on (`_firePointerLayer == nil` is
    /// the whole test, so there is no second flag to keep in step).
    private func blowOutFireball(fade: Double = 0.25) {
        _fireTimer?.invalidate(); _fireTimer = nil

        let pointer = _firePointerLayer
        _firePointerLayer = nil
        let going = [pointer].compactMap { $0 }

        let teardown = { [weak self] in
            for layer in going {
                layer.removeAllAnimations()
                layer.removeFromSuperlayer()
            }
            guard let self, self._fireHidCursor else { return }
            NSCursor.unhide()
            CGDisplayShowCursor(CGMainDisplayID())
            self._fireHidCursor = false
        }
        guard fade > 0, !going.isEmpty else { teardown(); return }
        for layer in going {
            let fadeOut = CABasicAnimation(keyPath: "opacity")
            fadeOut.fromValue = layer.presentation()?.opacity ?? 1.0
            fadeOut.toValue = 0.0
            fadeOut.duration = fade
            fadeOut.fillMode = .forwards
            fadeOut.isRemovedOnCompletion = false
            layer.add(fadeOut, forKey: "fadeOut")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + fade, execute: teardown)
    }

    /// Put some of the ball down: a fire starts burning where it was, at the
    /// size the wheel was left at. The place is the point of the gesture — it
    /// reads as "set THIS alight" — so a fire that drifted to the layer's centre
    /// would be a different effect than the one the head was over.
    ///
    /// **The new fire becomes the wheel's target** (2026-09-19). Sizing used to
    /// happen on the pointer *before* the click, which is backwards: he only
    /// knows how big this fire should be once he can see it standing on the
    /// thing it is burning. So the wheel follows the last one struck, and the
    /// next click hands it on. `_fireScale` carries the size across, so a second
    /// fire opens at the size he just dialled the first one to rather than
    /// snapping back.
    ///
    /// Each fire gets its own random phase into the 40-frame loop. Fires started
    /// at frame 0 flicker in lockstep, and a row of perfectly synchronised
    /// flames announces "sprite sheet" louder than any of them announces "fire".
    fileprivate func plantFireAtCursor() {
        guard _firePointerLayer != nil else { return }
        let frames = Self.fireFrames
        guard let first = frames.first else { return }

        let copy = CALayer()
        copy.bounds = Self.fireBounds(for: first, scale: _fireScale)
        copy.anchorPoint = Self.fireRootAnchor     // the root, so it stands where it was clicked
        copy.contents = first
        copy.contentsGravity = .resizeAspect
        copy.zPosition = 9_400                     // under the ball, over every other effect
        let point = mousePointInHostLayer()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        copy.position = point
        CATransaction.commit()

        let burn = CAKeyframeAnimation(keyPath: "contents")
        burn.values = frames
        burn.duration = Double(frames.count) / Self.fireFPS
        burn.repeatCount = .infinity
        burn.calculationMode = .discrete
        burn.timeOffset = Double.random(in: 0..<burn.duration)
        copy.add(burn, forKey: "burn")

        // **It catches rather than appears** (2026-09-22, Victor: *"focul, când
        // apare, să crească la dimensiunea la care este targetat să fie pe
        // parcursul a jumătate de secundă, cum se aprinde incendiul"*). A fire
        // that arrives at full size is a *decal being pasted*; one that climbs
        // to it over half a second is something taking hold, and the half
        // second is short enough that a click still feels answered at once.
        //
        // `bounds`, not `transform`, for the wheel's reason: the anchor is the
        // flame's root, so growing the box makes it climb UP out of the spot it
        // was struck on instead of ballooning around its own middle. The model
        // value is the full size from this instant, so anything that reads the
        // box mid-climb (the wheel, a drag) sees where it is going, not where
        // it is. Eased out — fire flares and then settles, it does not arrive
        // at a constant rate.
        let full = copy.bounds
        let catchFire = CABasicAnimation(keyPath: "bounds")
        catchFire.fromValue = CGRect(x: 0, y: 0,
                                     width: full.width * Self.fireCatchFromScale,
                                     height: full.height * Self.fireCatchFromScale)
        catchFire.toValue = full
        catchFire.duration = Self.fireCatchDuration
        catchFire.timingFunction = CAMediaTimingFunction(name: .easeOut)
        copy.add(catchFire, forKey: "catch")

        hostLayer.addSublayer(copy)
        _firePlanted.append(copy)
        _fireLastPlantPoint = point
        hideFireballWhileTheFireTakes()

        while _firePlanted.count > Self.fireMaxPlanted {
            let oldest = _firePlanted.removeFirst()
            oldest.removeAllAnimations()
            oldest.removeFromSuperlayer()
        }
    }

    /// **Dragging draws a line of fire** (2026-09-19). With the button held, the
    /// ball leaves a fire behind every `fireDragSpacing` points of travel, so a
    /// sweep sets a whole edge of the screen alight instead of costing one click
    /// per flame — the gesture of dragging a match along a fuse, which is the
    /// one thing about the old pointer the new one still quotes.
    ///
    /// The spacing is the whole trick. A drag reports 60+ events a second, so
    /// without it one sweep would stack flames on top of each other and hit
    /// `fireMaxPlanted` before the wrist stopped moving. It is measured from the
    /// last fire *planted*, never from the last event, so a slow drag spaces the
    /// fires exactly like a fast one: speed changes when the next one appears,
    /// never how far apart they stand.
    fileprivate func plantFireIfDragged() {
        guard _firePointerLayer != nil else { return }
        guard let last = _fireLastPlantPoint else { plantFireAtCursor(); return }
        let here = mousePointInHostLayer()
        let dx = here.x - last.x, dy = here.y - last.y
        guard dx * dx + dy * dy >= Self.fireDragSpacing * Self.fireDragSpacing else { return }
        plantFireAtCursor()
    }

    /// **The ball gets out of the way of the fire it just made** (2026-09-22,
    /// Victor: *"după fiecare așezare a incendiului, bila de foc dispare pentru
    /// două secunde, după care reapare … mărind impactul focului care l-a
    /// născut"*). Out on the instant — no fade, because a ball that *dissolves*
    /// competes with the fire climbing next to it for exactly the half second
    /// the fire needs — and back over `fireballReturnFade`, which is slow enough
    /// to read as the ball rekindling rather than as a cursor blinking.
    ///
    /// The token is what makes a DRAG behave. A sweep plants a fire every 50 pt,
    /// so each plant restarts the clock and only the last one's return survives:
    /// the ball is away for the whole gesture and comes back once, at the end.
    /// Without it, a two-second timer per fire would bring the ball back in the
    /// middle of the sweep and take it away again, strobing.
    private func hideFireballWhileTheFireTakes() {
        guard let ball = _firePointerLayer else { return }
        _fireballHideToken &+= 1
        let token = _fireballHideToken

        // Both of them, and belt-and-braces about it: an opacity animation still
        // attached is an opacity animation still being obeyed, and a click that
        // lands inside the entry fade's 0.12 s would otherwise leave the ball up
        // for the rest of it — the one moment this beat cannot afford to miss.
        ball.removeAnimation(forKey: "fadeIn")
        ball.removeAnimation(forKey: "return")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ball.opacity = 0
        CATransaction.commit()

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fireballHideAfterPlant) { [weak self] in
            guard let self, self._fireballHideToken == token,
                  let ball = self._firePointerLayer else { return }
            let back = CABasicAnimation(keyPath: "opacity")
            back.fromValue = 0.0
            back.toValue = 1.0
            back.duration = Self.fireballReturnFade
            back.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ball.opacity = 1
            ball.add(back, forKey: "return")
        }
    }

    /// Layer box for a given wheel scale, keeping the sprite's aspect ratio.
    private static func fireBounds(for frame: CGImage, scale: CGFloat) -> CGRect {
        let w = fireBaseWidth * scale
        let h = w * CGFloat(frame.height) / CGFloat(frame.width)
        return CGRect(x: 0, y: 0, width: w, height: h)
    }

    // MARK: Escape to put it out, wheel to size it

    /// One tap for both gestures, because both have to be *taken away* from the
    /// app underneath: an Escape that also closed the user's dialog, or a scroll
    /// that also scrolled their editor while they were sizing the flame, would
    /// make the effect cost something. An `NSEvent` global monitor can only
    /// observe; a tap can consume, which is why this isn't the whip's monitor pair.
    private func startFireInputCapture() {
        stopFireInputCapture()

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
            | CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDown.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseDragged.rawValue)
            | CGEventMask(1 << CGEventType.leftMouseUp.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let animator = Unmanaged<EmojiAnimator>.fromOpaque(refcon).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = animator._fireInputTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown,
               CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == 53 {   // Esc
                // First press puts the ball out and leaves the fires he lit;
                // a second one clears them. See `escapeFire`.
                DispatchQueue.main.async { animator.escapeFire() }
                return nil   // consume — the user is dismissing the fire, not their app
            }
            // **Once the ball is out, the mouse is his again.** The tap stays
            // alive only for the second Escape, so consuming clicks here would
            // take the pointer away from him while he is looking at a desktop
            // that already has its arrow back.
            if animator._firePointerLayer == nil {
                return Unmanaged.passUnretained(event)
            }
            if type == .leftMouseDown {
                DispatchQueue.main.async { animator.plantFireAtCursor() }
                return nil   // consume — while he carries the ball, a click means "burn here"
            }
            if type == .leftMouseDragged {
                // He struck one on the way down; keep laying them as he sweeps.
                DispatchQueue.main.async { animator.plantFireIfDragged() }
                return nil   // consume — the down was ours, so the drag is ours too
            }
            if type == .leftMouseUp {
                // The down was swallowed above, so delivering the up alone would
                // hand the app underneath half a click: a button that highlights
                // and never fires, a text view that loses its selection. The pair
                // goes or stays together.
                return nil
            }
            if type == .scrollWheel {
                // Cmd+scroll is left alone: EventTapManager turns it into
                // terminal font zoom, and silently eating that for 36 s would
                // look like the zoom shortcut had broken.
                if event.flags.contains(.maskCommand) { return Unmanaged.passUnretained(event) }
                // **Nothing struck yet, nothing to size** (2026-09-19): the wheel
                // owns the last fire on the ground, so before the first click it
                // has no target and eating the scroll would freeze his slides for
                // a gesture that does nothing visible. It becomes ours at the
                // moment there is a fire to answer it.
                if animator._firePlanted.isEmpty { return Unmanaged.passUnretained(event) }
                animator.handleFireScroll(event)
                return nil   // consume — don't scroll the app below while sizing
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                          options: .defaultTap, eventsOfInterest: mask,
                                          callback: callback, userInfo: refcon) else { return }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        _fireInputTap = tap
        _fireInputTapSource = src
    }

    private func stopFireInputCapture() {
        if let tap = _fireInputTap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let src = _fireInputTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes) }
        _fireInputTap = nil
        _fireInputTapSource = nil
        _fireScrollAccum = 0
    }

    /// Scroll up = bigger fire, scroll down = smaller, on **the last fire he
    /// struck** (2026-09-19) — it grows out of the spot it was planted on,
    /// because `bounds` is what changes and its anchor is its root. Runs on the
    /// tap's thread, so the layer edit is hopped to main.
    fileprivate func handleFireScroll(_ event: CGEvent) {
        var notches = 0
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            // Trackpad: continuous pixels, accumulated into notch-sized steps so
            // a two-finger flick doesn't jump the flame from candle to inferno.
            _fireScrollAccum += CGFloat(event.getDoubleValueField(.scrollWheelEventPointDeltaAxis1))
            while _fireScrollAccum >= 12 { notches += 1; _fireScrollAccum -= 12 }
            while _fireScrollAccum <= -12 { notches -= 1; _fireScrollAccum += 12 }
        } else {
            let dy = event.getDoubleValueField(.scrollWheelEventDeltaAxis1)   // + up, - down
            if dy > 0 { notches = 1 } else if dy < 0 { notches = -1 }
        }
        guard notches != 0 else { return }

        let factor = pow(Self.fireScaleStep, CGFloat(notches))
        DispatchQueue.main.async { [weak self] in
            guard let self, let fire = self._firePlanted.last,
                  let frame = Self.fireFrames.first else { return }
            let scale = min(self.fireMaxScale, max(Self.fireMinScale, self._fireScale * factor))
            guard scale != self._fireScale else { return }
            self._fireScale = scale
            Self.fireRememberedScale = scale   // the next fire is struck at this size
            // Resizing `bounds` (not `transform`) keeps the anchor pinned, so the
            // fire's root stays on the spot it was struck on while it grows —
            // it swells upward out of the thing it is burning instead of
            // ballooning around its own middle. No implicit animation: the wheel
            // should feel like a physical dial, not a servo.
            //
            // A fire scrolled DURING its half-second catch has two answers for
            // its box: the climb and the wheel. Drop the climb — the wheel is a
            // hand on the thing right now, and letting the animation finish
            // would snap the flame back to the size he just scrolled away from.
            fire.removeAnimation(forKey: "catch")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            fire.bounds = Self.fireBounds(for: frame, scale: scale)
            CATransaction.commit()
        }
    }

    // MARK: - 🐘 The elephant in the room (⌘⌃O)

    /// How long the elephant stays before it walks out on its own.
    static let elephantLifetime: Double = 25

    /// Where the elephant stands: the LEFT HALF of the screen, on the bottom
    /// edge, as large as that half allows.
    ///
    /// Width is claimed first (half the screen, less a margin) and the height
    /// then gets the final say — on a 16:10 screen half the width is taller
    /// than the screen is, and an elephant cropped at the knees is a bug you
    /// only see on the projector. It stands on the bottom edge on purpose:
    /// floated at mid-height the same picture reads as a sticker somebody
    /// dropped on the desktop, not as an animal that walked in.
    ///
    /// Pure so the geometry can be asserted without a screen.
    static func elephantFrame(in bounds: CGRect, aspect: CGFloat) -> CGRect {
        let margin = bounds.width * 0.015
        var w = bounds.width / 2 - margin * 2
        var h = w / max(aspect, 0.01)
        let maxH = bounds.height * 0.62
        if h > maxH {
            h = maxH
            w = h * aspect
        }
        // y = 0 is the bottom edge of the host layer.
        return CGRect(x: margin, y: margin, width: w, height: h)
    }

    /// 🐘 The orange elephant with the comb-over and the red tie walks in from
    /// the left edge and stands in the left half of the screen.
    ///
    /// It is a prop for one sentence — "there's an elephant in the room" — so
    /// it arrives *beside* what is being discussed rather than over it, and it
    /// is a cut-out PNG with a real alpha channel: a rectangle of white around
    /// it would announce "a picture opened" instead of "an elephant is here".
    /// macOS has no way to add a custom emoji to the character palette, so the
    /// key draws the picture itself.
    ///
    /// Pressing the key again walks it back out, and it leaves on its own after
    /// `elephantLifetime` — the lifecycle rule matters here because the overlay
    /// is click-through, so a joke left on screen cannot be dismissed by
    /// clicking it.
    func showElephant() {
        if activeEffects["elephant"] != nil { stopElephant(); return }

        guard let url = Bundle.module.url(forResource: "elephant", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            overlayError("elephant.png is not in the bundle")
            return
        }

        let bounds = hostLayer.bounds
        let frame = Self.elephantFrame(in: bounds, aspect: CGFloat(image.width) / CGFloat(image.height))

        peekWhipHopIndex = 0

        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        hostLayer.addSublayer(layer)
        activeEffects["elephant"] = layer

        // Walks in rather than fading in on the spot: the whole gag is that
        // something *entered* the room.
        let walkIn = CABasicAnimation(keyPath: "position.x")
        walkIn.fromValue = layer.position.x - (frame.width + frame.minX)
        walkIn.toValue = layer.position.x
        walkIn.duration = 0.55
        walkIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(walkIn, forKey: "walk-in")

        // Self-termination, identity-guarded so a second press followed by a
        // third can't have the first press's timer remove the newest elephant.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.elephantLifetime) { [weak self, weak layer] in
            guard let self, let layer, self.activeEffects["elephant"] === layer else { return }
            self.stopElephant()
        }
    }

    /// Walks it back out the way it came in. Safe when nothing is showing.
    func stopElephant() {
        guard let layer = activeEffects["elephant"] else { return }
        activeEffects.removeValue(forKey: "elephant")

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let walkOut = CABasicAnimation(keyPath: "position.x")
        walkOut.fromValue = layer.position.x
        walkOut.toValue = layer.position.x - (layer.bounds.width + layer.frame.minX)
        walkOut.duration = 0.4
        walkOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        walkOut.fillMode = .forwards
        walkOut.isRemovedOnCompletion = false
        layer.add(walkOut, forKey: "walk-out")
        CATransaction.commit()
    }

    // MARK: - 🤖 Claude leans in from the left (⌘⌃Q)

    /// One key, two agents: the wave is not an ad for a vendor, it is "the
    /// assistants", which is what the course is about. Both are cut-out robots
    /// of almost the same aspect (461×363 and 455×362), so `claudePeekFrame`
    /// sizes them off the height and the two land the same size in the same
    /// spot — they read as one character changing costume, not as two effects,
    /// which is exactly why a click can swap the costume in place.
    ///
    /// **Which one shows is a choice, not a rotation** — see `PeekMascotChoice`
    /// for why the press-by-press alternation was dropped.

    /// The invisible click target laid over the icon while it is on screen.
    /// Nil whenever nothing is showing; see `PeekHitPanel` for why the overlay
    /// itself cannot take the click.
    private var peekHitPanel: PeekHitPanel?

    /// Bumped by every appearance *and* by every costume change, so a timer
    /// armed before a swap cannot take the swapped-in mascot down early. Layer
    /// identity alone is not enough here: a click keeps the same layer.
    private var peekGeneration = 0

    /// How long the icon stays before it slides back out on its own.
    ///
    /// Short: this is a greeting, not a prop. The elephant is a picture that a
    /// sentence is built around and stays 25 s; this one only has to be seen.
    static let claudePeekLifetime: Double = 5

    /// Where it leans in: the **top LEFT**, at **41%** of the screen height,
    /// hanging from 82% of it — twice the size it was for a fortnight
    /// (2026-09-21), in the corner it has always used.
    ///
    /// Sized off the **height**, unlike the elephant, which claims half the
    /// width: that one is a picture a sentence is built around, this one is an
    /// app icon, and an icon measured in screen-widths on the projector is a
    /// billboard. It sat at 21% for a fortnight and still read as a favicon
    /// from the back of the room — *"vreau să fie mult mai mare, de două ori
    /// mai mare"* — so the number doubled rather than being nudged again.
    ///
    /// **The corner did not move with it.** A doubled mascot was briefly put
    /// on the right, on the theory that a third of the screen's width is too
    /// much to drop on top of the editor's text — and that was the wrong read
    /// of what was asked, corrected within the hour (*"de ce mi-ai pus din
    /// dreapta fără să apară din stânga sus ca înainte?"*). The entrance is
    /// part of what the key *is*: it comes in from the left, and a bigger
    /// character is not a different character. The top-left quarter is also
    /// still the **last** one `TerminalTileLayout.fillOrder` hands out, so of
    /// the whole screen it remains the least likely to have a terminal under
    /// it — which matters more, not less, now that the icon is this big.
    ///
    /// **Top-anchored, not centred.** The old frame centred the icon at 78% of
    /// the height; at double the size that same centre would push its head
    /// through the menu bar. It hangs from a fraction of the height instead, so
    /// the clearance above it is a number rather than whatever the aspect ratio
    /// of the PNG on duty leaves over.
    ///
    /// **It hung from 93% for half a day.** That was the doubling's first
    /// answer — get him as high as he goes without touching the menu bar — and
    /// it put his head in the strip of screen where a full-screen app's own
    /// toolbar lives. Victor drew where he wanted him instead (*"coboară-l mai
    /// jos"*), roughly a tenth of the screen further down, so the anchor is
    /// **82%**: still hanging from the top of the frame, but with his head
    /// clear of the chrome and his feet nearer the middle of the quarter he
    /// occupies. The room that buys above him is not wasted — it is what the
    /// whip's startle jumps into (`peekWhipHopDirections`), which was pinned to
    /// a hair under 7% of clearance while he hung at 93%.
    ///
    /// Pure so the geometry can be asserted without a screen.
    static func claudePeekFrame(in bounds: CGRect, aspect: CGFloat) -> CGRect {
        let h = bounds.height * peekHeightFraction
        let w = h * max(aspect, 0.01)
        // Not flush against the bezel: it comes a little way IN, so it reads as
        // somebody leaning into the room rather than as a sticker stuck to the
        // edge of the screen.
        let x = bounds.width * 0.045
        // y = 0 is the bottom edge of the host layer, so this hangs the icon's
        // TOP at `peekTopFraction` of the height and lets it grow downwards.
        let y = bounds.height * peekTopFraction - h
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// How tall the mascot is, as a fraction of the screen height. It went 21%
    /// → 42% on 2026-09-21 (*"vreau să fie mult mai mare, de două ori mai
    /// mare"*) and then back by 3% the same evening — a trim, not a reversal:
    /// at 42% and hanging lower he was crowding the quarter he stands in. Later
    /// the same evening it was taken to **×0.7 of that** (≈28.5% of the screen):
    /// the doubling was the right call at 21%, but the trim showed the limit was
    /// the quarter he stands in, not the reading distance. The factors are kept
    /// as a product rather than folded into one number because each one is a
    /// separate decision, and the history is the only thing that explains why
    /// the number is not round.
    static let peekHeightFraction: CGFloat = 0.42 * 0.97 * 0.7

    /// Where his head hangs, as a fraction of the screen height. See
    /// `claudePeekFrame` for why this is 82% and not the 93% it was.
    static let peekTopFraction: CGFloat = 0.82

    /// 🤖 A mascot slides in from the left, wiggles, and slides back out. ⌘⌃Q,
    /// and nothing else — it started life as the garnish on that key's Claude
    /// terminal and outlived it. It spent 2026-09-09 on ⌃⌥G and came back when
    /// that pair became the third emoji board and G went to the goose.
    ///
    /// **Claude by default, Copilot if you ask for it** (`PeekMascotChoice`):
    /// every day opens on Claude, and clicking the mascot while it is on screen
    /// swaps the costume in place and keeps that choice for the rest of the day.
    ///
    /// It floats: a cut-out PNG with a real alpha channel over a click-through
    /// overlay, so what arrives is the mark itself and not a white rectangle
    /// announcing "a picture opened" — and the cut has to reach the *halo* too,
    /// not just the card it was sitting on, because a pale rim one pixel wide is
    /// visible from the back of a room as a white outline.
    ///
    /// The wiggle is the whole personality — it starts once the slide has
    /// landed, so the two motions read as "walked in, then said hello" instead
    /// of one wobbly diagonal — and it decays (7° → 2°) because a rotation that
    /// repeats at constant amplitude reads as a loading spinner. It was twice
    /// this wide on the first pass, which on a 16% icon looked less like a wave
    /// than like something falling over.
    ///
    /// Pressing ⌘⌃Q again sends it back out, and it leaves on its own after
    /// `claudePeekLifetime`. **Clicking it does not dismiss it** — it changes
    /// which robot it is. That is the one exception to the rule that everything
    /// here must be dismissible without the mouse, and it is safe because the
    /// key itself and the five-second timer both still end it: the click is a
    /// setting, not a way out.
    func showClaudePeek() {
        if activeEffects["claude-peek"] != nil { stopClaudePeek(); return }

        let mascot = PeekMascotStore.current()
        guard let image = Self.peekImage(mascot) else {
            overlayError("\(mascot.rawValue).png is not in the bundle")
            return
        }

        let bounds = hostLayer.bounds
        let frame = Self.claudePeekFrame(in: bounds, aspect: CGFloat(image.width) / CGFloat(image.height))

        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsGravity = .resizeAspect
        layer.contentsScale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        hostLayer.addSublayer(layer)
        activeEffects["claude-peek"] = layer

        let slideIn = CABasicAnimation(keyPath: "position.x")
        slideIn.fromValue = layer.position.x - (frame.width + frame.minX)
        slideIn.toValue = layer.position.x
        slideIn.duration = 0.45
        slideIn.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(slideIn, forKey: "slide-in")

        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [0, -0.12, 0.10, -0.065, 0.04, 0]
        wiggle.keyTimes = [0, 0.18, 0.40, 0.62, 0.82, 1]
        wiggle.duration = 0.85
        wiggle.beginTime = CACurrentMediaTime() + slideIn.duration
        wiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(wiggle, forKey: "wiggle")

        // The click target goes up at the LANDED frame, not the sliding one: a
        // rectangle chasing the icon through the slide-in would be a target
        // that moves out from under the pointer, and the icon is only worth
        // clicking once it has arrived anyway.
        let screenOrigin = EdgeFlash.builtInScreen?.frame.origin ?? .zero
        let hitFrame = frame.offsetBy(dx: screenOrigin.x, dy: screenOrigin.y)
        peekHitPanel = PeekHitPanel(frame: hitFrame) { [weak self] in self?.flipPeekMascot() }

        schedulePeekExit(layer: layer)
    }

    /// Already-stroked mascots, kept because the rim is built once per PNG and
    /// this key is pressed many times a day; the images are a few hundred KB
    /// each and the app is restarted several times an hour anyway.
    private static var peekImageCache: [PeekMascot: CGImage] = [:]

    /// Load a mascot's cut-out PNG out of the bundle, wearing its white rim
    /// (`PeekMascotOutline` — why a cut-out alone is not enough on a dark
    /// screen). If the rim cannot be built the bare cut-out still shows: a
    /// mascot that is hard to see beats no mascot at all.
    private static func peekImage(_ mascot: PeekMascot) -> CGImage? {
        if let cached = peekImageCache[mascot] { return cached }
        guard let url = Bundle.module.url(forResource: mascot.rawValue, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let stroked = PeekMascotOutline.outlined(image) ?? image
        peekImageCache[mascot] = stroked
        return stroked
    }

    /// Arm the self-termination, guarded by BOTH layer identity and generation:
    /// identity so a second press followed by a third can't have the first
    /// press's timer remove the newest icon, generation so a costume change —
    /// which reuses the layer — can't be cut short by the timer armed for the
    /// costume before it.
    private func schedulePeekExit(layer: CALayer) {
        peekGeneration += 1
        let generation = peekGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.claudePeekLifetime) { [weak self, weak layer] in
            guard let self, let layer,
                  self.peekGeneration == generation,
                  self.activeEffects["claude-peek"] === layer else { return }
            self.stopClaudePeek()
        }
    }

    /// 🔥 The whip cracked: the mascot jumps, *ca ars de bici*.
    ///
    /// The whip already scolds the agent in the terminal (Ctrl+C + "FASTER");
    /// this is the same joke told to the room instead of to the shell — the
    /// robot on screen is the one being shouted at, so it is the one that has to
    /// flinch. Without it a crack is a sound and a rope, and the mascot stands
    /// there through it as if none of this were about him.
    ///
    /// **One crack, one hop.** Not a scamper: a scramble of four hops was tried
    /// on 2026-09-21 and was too much animation for one sound — *"să sară doar
    /// o dată un pic la o lovitură de bici și apoi să revenim la poziția
    /// originală"*. The repetition is supposed to come from the whip, not from
    /// the hop: crack again and he jumps again.
    ///
    /// **Each crack goes a different way.** A flinch that always leaves in the
    /// same direction stops being a flinch by the third crack and becomes an
    /// idle animation. `peekWhipHopDirections` is walked in order, one entry per
    /// crack, and the entries alternate left and right — so the second crack
    /// always answers the first, which is what "somewhat different, but still
    /// upwards and to one side" asks for. A list rather than `random()` because
    /// a random pick repeats itself often enough to be noticed, and because a
    /// cycle can be asserted in a test.
    ///
    /// **He always lands back where he came in.** The keyframes end at a zero
    /// offset and the animation is removed on completion, so the model layer is
    /// never written to: twenty cracks in a row leave the icon on the same pixel
    /// as the first, and the `PeekHitPanel` laid over the landed frame stays a
    /// valid click target throughout (it deliberately does not chase the hop,
    /// for the same reason it does not chase the slide-in).
    ///
    /// **A crack mid-flight picks him up where he is** rather than dropping him
    /// home first: the replacing animation starts from the offset the
    /// presentation layer is showing, and rises *from there*. Snapping to the
    /// ground to start the next hop is exactly the stutter that makes a
    /// repeated effect look broken.
    ///
    /// **Additive is what buys the sideways half.** The first flinch was
    /// confined to `position.y` because that was the one keypath that could
    /// fight neither the `wiggle` on `transform.rotation.z` nor the `slide-in`
    /// on `position.x` — a crack 200 ms after ⌘⌃Q plays all three at once. An
    /// additive animation on `position` is summed onto whatever else is driving
    /// it instead of replacing it, so he can leave to the side and still ride
    /// the slide-in rather than teleporting to his landing spot.
    ///
    /// **The five seconds start over**, exactly as a costume change restarts
    /// them: something just happened to the mascot, and having it slide out mid-
    /// flinch because its timer was armed before the crack would read as a bug.
    /// That also makes the whip a way to *keep* him on screen — crack again and
    /// he stays.
    ///
    /// A no-op when nothing is showing: the whip is cracked far more often over
    /// a bare desktop than over the mascot, and a crack must never be what puts
    /// him there.
    func whipClaudePeek() {
        guard let layer = activeEffects["claude-peek"] else { return }

        let direction = Self.peekWhipHopDirections[
            peekWhipHopIndex % Self.peekWhipHopDirections.count]
        peekWhipHopIndex += 1

        let hop = Self.peekWhipHop(
            frame: layer.frame, in: hostLayer.bounds,
            from: liveWhipOffset(of: layer), direction: direction)

        let jump = CAKeyframeAnimation(keyPath: "position")
        jump.isAdditive = true
        jump.values = hop.map { NSValue(point: NSPoint(x: $0.x, y: $0.y)) }
        jump.keyTimes = [0, NSNumber(value: Double(Self.peekWhipApexTime)), 1]
        jump.duration = Self.peekWhipDuration
        // Rising is a kick, falling is gravity.
        jump.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        layer.add(jump, forKey: "whip-jump")

        schedulePeekExit(layer: layer)
    }

    /// Which direction the next crack throws him. Reset when he walks on, so a
    /// fresh appearance always opens with the same first hop and the sequence is
    /// the same one the room saw last time.
    private var peekWhipHopIndex = 0

    /// How far a hop already in the air has carried him, as an offset from where
    /// he stands — so a second crack can continue from there instead of
    /// snapping him back to the ground to start over.
    ///
    /// Zero unless **our own** hop is what is moving him: while `slide-in` is
    /// running, the gap between the presentation and model layers is the slide,
    /// not the hop, and feeding that in would have the jump fight the entrance.
    /// Both animations are removed on completion, so `animation(forKey:)` is the
    /// question "is this still playing".
    private func liveWhipOffset(of layer: CALayer) -> CGPoint {
        guard layer.animation(forKey: "whip-jump") != nil,
              layer.animation(forKey: "slide-in") == nil,
              let shown = layer.presentation() else { return .zero }
        return CGPoint(x: shown.position.x - layer.position.x,
                       y: shown.position.y - layer.position.y)
    }

    /// Where each crack throws him, in fractions of the mascot's **own
    /// height** — both axes measured off the height, not one off each, so the
    /// two cut-outs (461×363 and 455×362) flinch identically and the effect
    /// never tells the room which costume is on duty.
    ///
    /// Measured off the icon rather than in points because he has been resized
    /// twice already (21% → 42% → 41% of the screen height, all on 2026-09-21)
    /// and a jump pinned to points would have stayed the hop it was when the
    /// robot was half as tall.
    ///
    /// Every entry goes **up**; the lateral part **alternates sign**, so
    /// consecutive cracks throw him opposite ways. The leftward ones are the
    /// small ones on purpose: `claudePeekFrame` insets him by 4.5% of the
    /// screen width, which is only ~0.17 of his own height, while the whole
    /// screen is open to his right.
    static let peekWhipHopDirections: [CGPoint] = [
        CGPoint(x:  0.24, y: 0.22),   // up and out to the right
        CGPoint(x: -0.15, y: 0.24),   // the other way, and higher
        CGPoint(x:  0.36, y: 0.18),   // a long one, flatter
        CGPoint(x: -0.06, y: 0.26),   // nearly straight up, a hair left
        CGPoint(x:  0.10, y: 0.25),   // nearly straight up, a hair right
        CGPoint(x: -0.13, y: 0.20),   // left again, and low
    ]

    /// When the top of the arc falls, as a fraction of the hop. Slightly past
    /// halfway: he is kicked up fast and falls back a touch slower, which is
    /// what makes it read as a startle rather than as a bounce.
    static let peekWhipApexTime: CGFloat = 0.42

    /// One hop, and a short one. Long enough to see from the back of the room,
    /// short enough that two cracks a second are two hops and not a queue.
    static let peekWhipDuration: Double = 0.42

    /// The highest a hop ever goes, as a fraction of the mascot's own height:
    /// the largest `y` in `peekWhipHopDirections`, kept as its own constant
    /// because it is the number that has to fit the clearance overhead.
    static let peekWhipJumpFraction: CGFloat = 0.26

    /// One hop as three offsets in points — where he is now, the top of the
    /// arc, and home — clamped to the room he actually has on each side.
    ///
    /// The apex is measured **from where he already is**, so a crack landing
    /// mid-hop throws him higher rather than interrupting him with a smaller
    /// number; the last point is always zero, because however many times he is
    /// hit he has to end up on the pixel he came in on.
    ///
    /// The clamp is not what picks the numbers, it is what keeps the *next*
    /// person from having to notice this: the overlay clips at the screen edge,
    /// and a flinch that beheads the robot on the projector — or walks him off
    /// the left bezel — reads as a broken effect rather than as a joke.
    ///
    /// Pure, so the whole arc can be asserted without a screen.
    static func peekWhipHop(
        frame: CGRect, in bounds: CGRect, from live: CGPoint, direction: CGPoint
    ) -> [CGPoint] {
        let unit = frame.height
        let up = max(0, bounds.maxY - frame.maxY)
        let down = max(0, frame.minY - bounds.minY)
        let right = max(0, bounds.maxX - frame.maxX)
        let left = max(0, frame.minX - bounds.minX)
        let apex = CGPoint(x: min(max(live.x + direction.x * unit, -left), right),
                           y: min(max(live.y + direction.y * unit, -down), up))
        return [live, apex, .zero]
    }

    /// How far the mascot rises on the highest of the hops, clamped to the room
    /// it actually has above it.
    ///
    /// `claudePeekFrame` hangs his head at `peekTopFraction` of the screen
    /// height, so the clearance is 18% of the height while the icon itself is
    /// ~28.5% — `peekWhipJumpFraction` is chosen to fit well inside it
    /// (0.26 × 0.285 ≈ 0.074 < 0.18; it was 0.26 × 0.41 ≈ 0.107 while he stood
    /// at 41%, so the trim only widened the margin — the clamp above stays the
    /// belt to this braces).
    static func peekWhipRise(frame: CGRect, in bounds: CGRect) -> CGFloat {
        let wanted = frame.height * peekWhipJumpFraction
        let roomAbove = max(0, bounds.maxY - frame.maxY)
        return min(wanted, roomAbove)
    }

    /// A click on the mascot: the *other* robot walks on in the same spot, and
    /// stays the one this key means for the rest of the day.
    ///
    /// The swap is a cross-fade of the layer's contents rather than a slide-out
    /// and a slide-in, because it is one character changing costume, not one
    /// leaving and another arriving — and because a mascot that walked out on
    /// a click would read as "I dismissed it", which is the opposite of what
    /// the click did. The wiggle runs again so the new one gets to say hello
    /// too, and the five seconds start over so a click at 4.9 s does not show
    /// the answer for a tenth of a second.
    private func flipPeekMascot() {
        guard let layer = activeEffects["claude-peek"] else { return }
        let mascot = PeekMascotStore.flip()
        guard let image = Self.peekImage(mascot) else {
            overlayError("\(mascot.rawValue).png is not in the bundle")
            return
        }

        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.22
        layer.add(fade, forKey: "costume-change")
        layer.contents = image

        let wiggle = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        wiggle.values = [0, -0.12, 0.10, -0.065, 0.04, 0]
        wiggle.keyTimes = [0, 0.18, 0.40, 0.62, 0.82, 1]
        wiggle.duration = 0.85
        wiggle.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(wiggle, forKey: "wiggle")

        schedulePeekExit(layer: layer)
    }

    /// Slides it back out the way it came in. Safe when nothing is showing.
    func stopClaudePeek() {
        peekHitPanel?.dismiss()
        peekHitPanel = nil
        guard let layer = activeEffects["claude-peek"] else { return }
        activeEffects.removeValue(forKey: "claude-peek")

        CATransaction.begin()
        CATransaction.setCompletionBlock { layer.removeFromSuperlayer() }
        let slideOut = CABasicAnimation(keyPath: "position.x")
        slideOut.fromValue = layer.position.x
        slideOut.toValue = layer.position.x - (layer.bounds.width + layer.frame.minX)
        slideOut.duration = 0.35
        slideOut.timingFunction = CAMediaTimingFunction(name: .easeIn)
        slideOut.fillMode = .forwards
        slideOut.isRemovedOnCompletion = false
        layer.add(slideOut, forKey: "slide-out")
        CATransaction.commit()
    }

    /// What is on screen right now, for `GET /state`. Read-only and cheap — a
    /// diagnostic, not a control surface.
    // MARK: - 🔁 Sketch arrow (tile #71 "One more time")

    /// The replay arrow from #71's artwork, drawn onto the desktop in cyan as if
    /// a marker were sketching it. The geometry, the three overlapping passes
    /// and the whole timeline live in `SketchArrow.swift`; here it only gets
    /// hung on the host layer and tracked, so it self-terminates at
    /// `SketchArrow.totalDuration` (the clip's own length) and `stop-all` clears
    /// it like any other effect. Not a toggle: re-firing redraws it.
    func showSketchArrow() {
        _ = cancelIfRunning("sketch-arrow")
        let scale = NSScreen.screens.first?.backingScaleFactor ?? 2.0
        // The menu bar's strip is not desktop, so the drawing is centred on what
        // can actually be seen rather than on the panel — see SketchArrow.visibleDrop.
        let screen = Screens.overlayScreen()
        let menuBar = screen.map { max(0, $0.frame.maxY - $0.visibleFrame.maxY) } ?? 0
        guard let layer = SketchArrow.makeLayer(in: hostLayer.bounds, topInset: menuBar, scale: scale) else { return }
        hostLayer.addSublayer(layer)
        trackEffect("sketch-arrow", layer: layer, duration: SketchArrow.totalDuration)
    }

    var activeEffectNames: [String] { activeEffects.keys.sorted() }

    // MARK: - Stop all active effects (called when tablet stops any sound)

    func stopAllActiveEffects() {
        // The spiral-hearts beating cursor lives OUTSIDE activeEffects (it's a
        // standalone hostLayer sublayer with its own follow timer), so the loop
        // below would drop the rising hearts but leave it beating forever. Tear
        // it (and any pending spawns) down explicitly.
        clearSpiralHearts(fadeDuration: 0)
        // Same for the snowfall: the loop below drops the container but the
        // pending spawn work items would keep firing into a detached layer.
        clearSnow(fadeDuration: 0)
        // ⛈️ And the storm, for the same reason: its container dies in the loop
        // but the pending self-stop would fire afterwards and clear the "storm"
        // key out from under whatever the next press put there.
        clearStorm(fadeDuration: 0)
        // The minigun aiming reticle also lives OUTSIDE activeEffects (its own
        // follow timer + hidden cursor), so tear it down explicitly or it would
        // keep tracking forever after a stop-all.
        stopMinigunReticle()
        // 🪚 The chainsaw cursor is outside activeEffects for the same reason —
        // and it also HIDES the real pointer, so leaving it behind would strand
        // the desktop with no cursor at all.
        stopChainsawCursor(fade: 0)
        // 🔥 The fire cursor is outside activeEffects for the same reasons, plus
        // one of its own: it holds a CGEventTap that is swallowing Escape and the
        // scroll wheel. Leaking that would cost the user their wheel long after
        // the flame was gone, with nothing on screen to explain it.
        stopFireCursor(fade: 0)
        // ☢️ The bombardment is outside activeEffects for the same reasons again:
        // its targets and blasts are the run's own layers, it hides the real
        // pointer, and it holds a tap that is swallowing Escape and every click.
        stopBombSession(fade: 0)
        // 🤖 The mascot's click target is a real window, not one of the layers
        // below: the loop would drop the icon and leave an invisible rectangle
        // eating clicks in the top-left corner of the screen forever.
        peekHitPanel?.dismiss()
        peekHitPanel = nil
        // 📺 A running CRT shutdown IS in activeEffects and dies in the loop
        // below; what the loop cannot reach is one that game-over has ARMED but
        // not started yet. Bumping the epoch cancels that pending start, so a
        // stop-all during the GAME OVER picture means no tube closing a second
        // later over whatever the next tile put on screen.
        _crtArmEpoch &+= 1
        // ☕🌊 A stop-all also ends the coffee storm: the next ☕ arrives calm.
        coffeeStorm = CoffeeStormGauge()
        for (_, layer) in activeEffects {
            layer.removeAllAnimations()
            layer.removeFromSuperlayer()
        }
        activeEffects.removeAll()
        stopApplause()
        if pulseRunning { _stopPulse() }
        stopAlarmOverlay()
        // 🕳️ Iris also lives OUTSIDE activeEffects (it survives stop-all so a
        // direct /effect/iris re-press can toggle it), but a NON-restartable tile
        // re-tap fires /effect/stop-all expecting the effect to STOP — so tear the
        // iris down here too.
        if let iris = _irisLayer { cancelIris(iris, fadeDuration: 0.2) }
        // Silence Mac-OWNED effect sounds that don't ride the tablet-routed player
        // (stopTabletSound misses them), so a non-restartable re-tap stops the
        // animation AND the sound: the 🛰️ sonar beeps (play() pool) and the 🔥
        // phoenix cry (overlapping pool). The money "ching" is intentionally left
        // (it's a restartable, stacking clip).
        SoundManager.shared.stopAllPlayers()
        SoundManager.shared.stopOverlapping("phoenix.mp3", fade: SoundManager.interruptFade)
    }
}
