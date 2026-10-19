import QuartzCore

/// 😮 The O mouth a mascot pulls when the whip hits him (2026-10-20, Victor:
/// *"when it's doing whip lash, both Claude Code and Copilot should make a
/// scary face or put an O mouth"*).
///
/// Drawn, not a second picture: a dark oval laid on the face as a sublayer of
/// the mascot, so it rides the hop and the slide-in for free and works with
/// whatever cut-out sits in `assetsDir`. Where the face is was measured off
/// the two PNGs (`claude-icon.png` 461×363: the `> <` eyes end at 41% of the
/// height, the body at 74%; `copilot-icon.png` 455×362: the eyes end at 78%,
/// the face plate at 93%), as fractions of the picture from its top-left.
enum PeekOMouth {
    static let layerName = "o-mouth"
    /// Up for this long after a hit — the hop (`peekWhipDuration`, 0.42 s) and
    /// a beat after it, so the face is still there when he lands.
    static let holdSeconds = 0.75
    static let fadeSeconds = 0.2

    /// Centre x/y and size, as fractions of the bare picture, y from the top.
    static func face(_ mascot: PeekMascot) -> (cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) {
        switch mascot {
        case .claude: return (0.5, 0.575, 0.10, 0.16)
        case .copilot: return (0.5, 0.865, 0.095, 0.10)
        }
    }

    /// The mouth's rect in a layer whose bare picture fills `picture` (in that
    /// layer's own, y-up coordinates).
    static func rect(_ mascot: PeekMascot, picture: CGRect) -> CGRect {
        let f = face(mascot)
        let w = picture.width * f.w, h = picture.height * f.h
        let cy = picture.maxY - picture.height * f.cy
        return CGRect(x: picture.minX + picture.width * f.cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    /// Put an O on `mascotLayer` — replacing one already there, so a second
    /// lash restarts the scream rather than stacking a second mouth — and
    /// take it off again on its own clock.
    static func gasp(on mascotLayer: CALayer, mascot: PeekMascot, picture: CGRect) {
        mascotLayer.sublayers?.filter { $0.name == layerName }.forEach { $0.removeFromSuperlayer() }

        let mouth = CAShapeLayer()
        mouth.name = layerName
        let r = rect(mascot, picture: picture)
        mouth.frame = r
        mouth.path = CGPath(ellipseIn: CGRect(origin: .zero, size: r.size), transform: nil)
        mouth.fillColor = CGColor(red: 0.08, green: 0.02, blue: 0.03, alpha: 1)
        mouth.strokeColor = CGColor(gray: 0, alpha: 1)
        mouth.lineWidth = max(1, r.width * 0.06)
        mascotLayer.addSublayer(mouth)

        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [0.2, 1.15, 1.0]
        pop.keyTimes = [0, 0.6, 1]
        pop.duration = 0.12
        mouth.add(pop, forKey: "pop")

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + holdSeconds
        fade.duration = fadeSeconds
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false
        mouth.add(fade, forKey: "fade")

        // Self-terminating: gone on its own clock whatever happens to the
        // mascot meanwhile. Each timer removes only its own mouth, never the
        // one a newer lash put on.
        DispatchQueue.main.asyncAfter(deadline: .now() + holdSeconds + fadeSeconds) { [weak mouth] in
            mouth?.removeFromSuperlayer()
        }
    }
}
