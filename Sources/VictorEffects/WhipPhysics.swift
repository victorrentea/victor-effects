import Foundation

/// Pure, deterministic Verlet whip physics — a faithful Swift port of the
/// JavaScript simulation in OpenWhip's `overlay.html` (https://github.com/GitFrog1111/OpenWhip).
///
/// This type holds NO UI or platform dependency so it can be unit-tested and
/// compared frame-by-frame against the original JS via golden values
/// (see Tests/VictorEffectsTests/WhipPhysicsTests + tools/whip-parity).
///
/// Coordinate space matches the original HTML canvas: origin top-left, +y points
/// DOWN, so gravity is +y. The rendering view is flipped to match.
///
/// The operation ORDER inside `update(now:)` is kept byte-for-byte with the JS
/// (same loop bounds, same sequence of stretch/wall/base-pose calls inside and
/// outside the constraint-iteration loop). Changing the order breaks parity.
final class WhipPhysics {

    /// Physics constants — copied verbatim from the `P` object in overlay.html
    /// (physics-relevant fields only; visual fields like line widths live in the view).
    enum P {
        // Rope structure
        static let segments = 28          // number of chain links
        static let segmentLength = 25.0   // base length of each link (px)
        static let taper = 0.6            // tip segment is this fraction of base length

        // Physics
        static let gravity = 1.2
        static let dropGravity = 0.95
        static let damping = 0.96
        static let constraintIters = 20
        static let maxStretchRatio = 1.2

        // Dynamic handle aim
        static let baseTargetAngle = -1.12
        static let handleAimByMouseX = 0.4
        static let handleAimByMouseY = 0.2
        static let handleAimClamp = 2.0
        static let handleSpring = 0.7
        static let handleAngularDamping = 0.078
        static let basePoseSegments = 2
        static let basePoseStiffStart = 0.9
        static let basePoseStiffEnd = 0.8

        // Elastic bend limits by chain position
        static let handleMaxBendDeg = 16.0
        static let tipMaxBendDeg = 130.0
        static let bendRigidityStart = 0.8
        static let bendRigidityEnd = 0.12

        // Screen-edge slap
        static let wallBounce = 0.42
        static let wallFriction = 0.86

        // Crack detection
        static let crackSpeed = 260.0     // tip velocity threshold to trigger a crack
                                          // (tuned down from OpenWhip's 340 so a
                                          //  gentler flick still cracks)
        static let crackCooldownMs = 200.0
        static let firstCrackGraceMs = 350.0

        // Initial arc shape
        static let arcWidth = 260.0
        static let arcHeight = 185.0
    }

    /// One chain link. `(px,py)` is the previous position used by Verlet integration.
    struct Point: Equatable {
        var x: Double
        var y: Double
        var px: Double
        var py: Double
    }

    // MARK: - State (all mirrors the JS globals)

    private(set) var points: [Point] = []
    private(set) var isActive = false
    private(set) var dropping = false

    private var lastCrackTime = 0.0
    private var whipSpawnTime = 0.0
    private var handleAngle = P.baseTargetAngle
    private var handleAngVel = 0.0

    private(set) var mouseX = 0.0
    private(set) var mouseY = 0.0
    private var prevMouseX = 0.0
    private var prevMouseY = 0.0

    var W: Double
    var H: Double

    init(width: Double, height: Double) {
        self.W = width
        self.H = height
    }

    // MARK: - Lifecycle

    /// Spawn the whip with the handle at the cursor — mirrors `spawnWhip` + `onSpawnWhip`.
    func spawn(mouseX mx: Double, mouseY my: Double, now: Double) {
        mouseX = mx
        mouseY = my
        prevMouseX = mx
        prevMouseY = my
        dropping = false
        lastCrackTime = 0
        whipSpawnTime = now
        handleAngle = P.baseTargetAngle
        handleAngVel = 0

        var pts: [Point] = []
        pts.reserveCapacity(P.segments)
        for i in 0..<P.segments {
            let t = Double(i) / Double(P.segments - 1)
            let x = mx + t * P.arcWidth
            let y = my - sin(t * Double.pi * 0.75) * P.arcHeight
            pts.append(Point(x: x, y: y, px: x, py: y))
        }
        points = pts
        isActive = true
    }

    /// Begin the drop/despawn animation — mirrors `onDropWhip`.
    func startDropping() {
        if isActive && !dropping { dropping = true }
    }

    func setMouse(_ x: Double, _ y: Double) {
        mouseX = x
        mouseY = y
    }

    // MARK: - Per-link length / helpers

    private func segLen(_ i: Int) -> Double {
        let t = Double(i) / Double(P.segments - 1)
        return P.segmentLength * (1 - t * (1 - P.taper))
    }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        Swift.max(lo, Swift.min(hi, v))
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }

    private func wrapPi(_ angle: Double) -> Double {
        var a = angle
        while a > Double.pi { a -= Double.pi * 2 }
        while a < -Double.pi { a += Double.pi * 2 }
        return a
    }

    // MARK: - Physics step (mirrors `update()`)

    /// Advance one frame. Returns `true` if a crack fired this frame (tip velocity
    /// exceeded the threshold, past the spawn grace and crack cooldown). `now` is
    /// milliseconds (injected so the simulation is deterministic and testable).
    @discardableResult
    func update(now: Double) -> Bool {
        guard isActive else { return false }

        let g = dropping ? P.dropGravity : P.gravity
        updateHandleAim()

        // Verlet integration
        let start = dropping ? 0 : 1
        if start < points.count {
            for i in start..<points.count {
                let vx = (points[i].x - points[i].px) * P.damping
                let vy = (points[i].y - points[i].py) * P.damping
                points[i].px = points[i].x
                points[i].py = points[i].y
                points[i].x += vx
                points[i].y += vy + g
            }
        }

        // Pin handle to mouse
        if !dropping {
            points[0].x = mouseX
            points[0].y = mouseY
            points[0].px = mouseX
            points[0].py = mouseY
        }

        capSegmentStretch()
        applyWallCollisions()
        applyBasePose()

        // Distance constraints (multiple iterations for stiffness)
        for _ in 0..<P.constraintIters {
            for i in 0..<(points.count - 1) {
                let dx = points[i + 1].x - points[i].x
                let dy = points[i + 1].y - points[i].y
                var dist = (dx * dx + dy * dy).squareRoot()
                if dist == 0 { dist = 0.0001 }
                let target = segLen(i)
                let diff = (dist - target) / dist * 0.5
                let ox = dx * diff
                let oy = dy * diff
                if i == 0 && !dropping {
                    points[i + 1].x -= ox * 2
                    points[i + 1].y -= oy * 2
                } else {
                    points[i].x += ox
                    points[i].y += oy
                    points[i + 1].x -= ox
                    points[i + 1].y -= oy
                }
            }
            applyBendLimits()
            if !dropping { applyBasePose() }
            capSegmentStretch()
            applyWallCollisions()
        }

        // Tip velocity for crack detection. Use the sqrt(a*a+b*b) form (not
        // hypot/pow) to bit-match the JS golden harness.
        let tip = points[points.count - 1]
        let tdx = tip.x - tip.px
        let tdy = tip.y - tip.py
        let tipVel = (tdx * tdx + tdy * tdy).squareRoot()

        var crack = false
        if !dropping && tipVel > P.crackSpeed {
            if now - whipSpawnTime >= P.firstCrackGraceMs && now - lastCrackTime > P.crackCooldownMs {
                lastCrackTime = now
                crack = true
            }
        }

        // If dropping, check if everything fell off screen
        if dropping && points.allSatisfy({ $0.y > H + 60 }) {
            points = []
            isActive = false
            dropping = false
        }

        prevMouseX = mouseX
        prevMouseY = mouseY
        return crack
    }

    // MARK: - Sub-steps (each mirrors the same-named JS function)

    private func updateHandleAim() {
        if dropping { return }
        let mvx = mouseX - prevMouseX
        let mvy = mouseY - prevMouseY
        let delta = clamp(
            mvx * P.handleAimByMouseX + mvy * P.handleAimByMouseY,
            -P.handleAimClamp,
            P.handleAimClamp
        )
        let target = P.baseTargetAngle + delta
        let err = wrapPi(target - handleAngle)
        handleAngVel += err * P.handleSpring
        handleAngVel *= P.handleAngularDamping
        handleAngle = wrapPi(handleAngle + handleAngVel)
    }

    private func applyBasePose() {
        guard isActive, !dropping else { return }
        let dx = cos(handleAngle)
        let dy = sin(handleAngle)
        let guided = Swift.min(P.basePoseSegments, points.count - 1)
        guard guided >= 1 else { return }
        for i in 1...guided {
            let t = Double(i - 1) / Double(Swift.max(guided - 1, 1))
            let stiff = lerp(P.basePoseStiffStart, P.basePoseStiffEnd, t)
            let prevX = points[i - 1].x
            let prevY = points[i - 1].y
            let targetLen = segLen(i - 1)
            let tx = prevX + dx * targetLen
            let ty = prevY + dy * targetLen
            points[i].x = lerp(points[i].x, tx, stiff)
            points[i].y = lerp(points[i].y, ty, stiff)
        }
    }

    private func applyBendLimits() {
        guard points.count >= 3 else { return }
        for i in 1..<(points.count - 1) {
            let ax = points[i - 1].x, ay = points[i - 1].y
            let bx = points[i].x, by = points[i].y
            let cx = points[i + 1].x, cy = points[i + 1].y

            let v1x = ax - bx
            let v1y = ay - by
            let v2x = cx - bx
            let v2y = cy - by
            var l1 = (v1x * v1x + v1y * v1y).squareRoot(); if l1 == 0 { l1 = 0.0001 }
            var l2 = (v2x * v2x + v2y * v2y).squareRoot(); if l2 == 0 { l2 = 0.0001 }
            let n1x = v1x / l1, n1y = v1y / l1
            let n2x = v2x / l2, n2y = v2y / l2

            let dot = clamp(n1x * n2x + n1y * n2y, -1, 1)
            let angle = acos(dot)
            let t = Double(i) / Double(points.count - 2)
            let maxBend = lerp(P.handleMaxBendDeg, P.tipMaxBendDeg, t) * Double.pi / 180
            let bend = Double.pi - angle
            if bend <= maxBend { continue }

            let cross = n1x * n2y - n1y * n2x
            let sign: Double = cross >= 0 ? 1 : -1
            let targetAngle = Double.pi - maxBend
            let targetA = atan2(n1y, n1x) + sign * targetAngle
            let tx = bx + cos(targetA) * l2
            let ty = by + sin(targetA) * l2
            let rigidity = lerp(P.bendRigidityStart, P.bendRigidityEnd, t)

            points[i + 1].x = lerp(cx, tx, rigidity)
            points[i + 1].y = lerp(cy, ty, rigidity)
        }
    }

    private func capSegmentStretch() {
        guard points.count >= 2 else { return }
        for i in 0..<(points.count - 1) {
            let dx = points[i + 1].x - points[i].x
            let dy = points[i + 1].y - points[i].y
            var dist = (dx * dx + dy * dy).squareRoot()
            if dist == 0 { dist = 0.0001 }
            let maxLen = segLen(i) * P.maxStretchRatio
            if dist <= maxLen { continue }
            let k = maxLen / dist
            points[i + 1].x = points[i].x + dx * k
            points[i + 1].y = points[i].y + dy * k
        }
    }

    private func applyWallCollisions() {
        guard isActive, !dropping else { return } // disable collisions while dropping
        let start = 1 // keep pinned handle untouched
        for i in start..<points.count {
            var vx = points[i].x - points[i].px
            var vy = points[i].y - points[i].py
            var hit = false

            if points[i].x < 0 {
                points[i].x = 0
                if vx < 0 { vx = -vx * P.wallBounce }
                vy *= P.wallFriction
                hit = true
            } else if points[i].x > W {
                points[i].x = W
                if vx > 0 { vx = -vx * P.wallBounce }
                vy *= P.wallFriction
                hit = true
            }

            if points[i].y < 0 {
                points[i].y = 0
                if vy < 0 { vy = -vy * P.wallBounce }
                vx *= P.wallFriction
                hit = true
            } else if points[i].y > H {
                points[i].y = H
                if vy > 0 { vy = -vy * P.wallBounce }
                vx *= P.wallFriction
                hit = true
            }

            if hit {
                points[i].px = points[i].x - vx
                points[i].py = points[i].y - vy
            }
        }
    }
}
