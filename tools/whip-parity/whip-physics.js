'use strict';
// ══════════════════════════════════════════════════════════════════════════════
//  Whip physics — faithful CommonJS extraction of /tmp/OpenWhip/overlay.html
//
//  This module reproduces the Verlet rope/whip simulation EXACTLY as the JS in
//  overlay.html, with one deliberate change: every `Date.now()` is replaced by
//  an injected `now` parameter. `whipSpawnTime` is set at spawn time (the caller
//  passes it, conventionally 0). The crack detection inside `update(now)` uses
//  the injected `now`.
//
//  Only PHYSICS is ported here. Rendering helpers (catmullPoint,
//  whipSegmentBezier, draw) are intentionally excluded.
//
//  Operation ORDER is byte-for-byte faithful to the original `update()`:
//    updateHandleAim → Verlet integrate → pin handle → capSegmentStretch →
//    applyWallCollisions → applyBasePose → [constraintIters × (distance
//    constraints → applyBendLimits → applyBasePose → capSegmentStretch →
//    applyWallCollisions)] → crack detection → prevMouse = mouse.
// ══════════════════════════════════════════════════════════════════════════════

// PHYSICS-relevant constants copied verbatim from the P object in overlay.html.
// Purely-visual fields (lineWidth*, outlineWidth, handleExtraWidth,
// handleThickSegments, bgAlpha) are intentionally omitted.
const P = {
  // Rope structure
  segments:       28,     // number of chain links
  segmentLength:  25,     // base length of each link (px)
  taper:          0.6,   // tip segment is this fraction of base length

  // Physics
  gravity:        1.2,   // normal gravity
  dropGravity:    0.95,    // gravity when dropping/despawning
  damping:        0.96,  // velocity retention per frame (1 = no loss)
  constraintIters:20,     // higher = stiffer chain
  maxStretchRatio: 1.2,  // hard cap for per-link stretch during fast whips

  // Dynamic handle aim (target angle + restoring spring, not static lock)
  baseTargetAngle: -1.12, // radians, default "up-right" resting direction
  handleAimByMouseX: 0.4, // horizontal mouse movement influence on target angle
  handleAimByMouseY: 0.2, // vertical mouse movement influence on target angle
  handleAimClamp:    2.0,  // max radians target can deviate from base angle
  handleSpring:      0.7,  // restoring force to target angle
  handleAngularDamping: 0.078, // angular velocity damping
  basePoseSegments: 2,    // how many early segments are strongly guided
  basePoseStiffStart: 0.9, // stiffness near handle
  basePoseStiffEnd:   0.8, // stiffness near end of guided region

  // Elastic bend limits by chain position (handle stiff, tip floppy)
  handleMaxBendDeg: 16,   // max angle between links near handle
  tipMaxBendDeg:   130,   // max angle between links near tip
  bendRigidityStart: 0.8, // correction strength near handle
  bendRigidityEnd:   0.12, // correction strength near tip

  // Screen-edge slap
  wallBounce:      0.42,   // velocity retained after wall hit
  wallFriction:    0.86,   // tangential damping on wall hit

  // Crack detection
  crackSpeed:     260,     // tip velocity threshold to trigger crack (tuned down from 340)
  crackCooldownMs:200,   // min ms between cracks
  firstCrackGraceMs: 350, // no crack (macro) until this long after spawn

  // Initial arc shape
  arcWidth:       260,    // how far right the arc extends from mouse
  arcHeight:      185,    // how high the arc goes above mouse
};

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const lerp = (a, b, t) => a + (b - a) * t;
const wrapPi = a => {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
};

class WhipSim {
  constructor(W, H) {
    this.W = W;
    this.H = H;
    this.whip = null;
    this.dropping = false;
    this.lastCrackTime = 0;
    this.whipSpawnTime = 0;
    this.handleAngle = P.baseTargetAngle;
    this.handleAngVel = 0;
    this.mouseX = 0;
    this.mouseY = 0;
    this.prevMouseX = 0;
    this.prevMouseY = 0;
  }

  // ── Whip creation ───────────────────────────────────────────────────────────
  // Faithful to spawnWhip(mx,my) from the JS. Returns the points array AND sets
  // this.whip / resets dropping / lastCrackTime. whipSpawnTime is the caller's
  // responsibility (set it to 0 after spawn, as the scenario runner does), so we
  // do NOT call Date.now() here.
  spawnWhip(mx, my) {
    this.dropping = false;
    this.lastCrackTime = 0;
    // NOTE: in the JS this is `whipSpawnTime = Date.now()`. We leave whipSpawnTime
    // to the caller (conventionally 0) to keep the simulation deterministic.
    const pts = [];
    for (let i = 0; i < P.segments; i++) {
      const t = i / (P.segments - 1);
      // Nice upward arc from handle (mouse) to tip
      const x = mx + t * P.arcWidth;
      const y = my - Math.sin(t * Math.PI * 0.75) * P.arcHeight;
      pts.push({ x, y, px: x, py: y });
    }
    this.whip = pts;
    return pts;
  }

  segLen(i) {
    const t = i / (P.segments - 1);
    return P.segmentLength * (1 - t * (1 - P.taper));
  }

  updateHandleAim() {
    if (this.dropping) return;
    const mvx = this.mouseX - this.prevMouseX;
    const mvy = this.mouseY - this.prevMouseY;
    const delta = clamp(
      mvx * P.handleAimByMouseX + mvy * P.handleAimByMouseY,
      -P.handleAimClamp,
      P.handleAimClamp
    );
    const target = P.baseTargetAngle + delta;
    const err = wrapPi(target - this.handleAngle);
    this.handleAngVel += err * P.handleSpring;
    this.handleAngVel *= P.handleAngularDamping;
    this.handleAngle = wrapPi(this.handleAngle + this.handleAngVel);
  }

  applyBasePose() {
    const whip = this.whip;
    if (!whip || this.dropping) return;
    const dx = Math.cos(this.handleAngle);
    const dy = Math.sin(this.handleAngle);
    const guided = Math.min(P.basePoseSegments, whip.length - 1);
    for (let i = 1; i <= guided; i++) {
      const t = (i - 1) / Math.max(guided - 1, 1);
      const stiff = lerp(P.basePoseStiffStart, P.basePoseStiffEnd, t);
      const prev = whip[i - 1];
      const p = whip[i];
      const targetLen = this.segLen(i - 1);
      const tx = prev.x + dx * targetLen;
      const ty = prev.y + dy * targetLen;
      p.x = lerp(p.x, tx, stiff);
      p.y = lerp(p.y, ty, stiff);
    }
  }

  applyBendLimits() {
    const whip = this.whip;
    if (!whip || whip.length < 3) return;
    for (let i = 1; i < whip.length - 1; i++) {
      const a = whip[i - 1];
      const b = whip[i];
      const c = whip[i + 1];

      const v1x = a.x - b.x;
      const v1y = a.y - b.y;
      const v2x = c.x - b.x;
      const v2y = c.y - b.y;
      // sqrt(a*a+b*b) form (not Math.hypot) to bit-match the Swift port.
      const l1 = Math.sqrt(v1x * v1x + v1y * v1y) || 0.0001;
      const l2 = Math.sqrt(v2x * v2x + v2y * v2y) || 0.0001;
      const n1x = v1x / l1, n1y = v1y / l1;
      const n2x = v2x / l2, n2y = v2y / l2;

      const dot = clamp(n1x * n2x + n1y * n2y, -1, 1);
      const angle = Math.acos(dot);
      const t = i / (whip.length - 2);
      const maxBend = lerp(P.handleMaxBendDeg, P.tipMaxBendDeg, t) * Math.PI / 180;
      const bend = Math.PI - angle; // bend away from a straight line
      if (bend <= maxBend) continue;

      // Clamp to max bend while preserving side/sign of the bend.
      const cross = n1x * n2y - n1y * n2x;
      const sign = cross >= 0 ? 1 : -1;
      const targetAngle = Math.PI - maxBend;
      const targetA = Math.atan2(n1y, n1x) + sign * targetAngle;
      const tx = b.x + Math.cos(targetA) * l2;
      const ty = b.y + Math.sin(targetA) * l2;
      const rigidity = lerp(P.bendRigidityStart, P.bendRigidityEnd, t);

      c.x = lerp(c.x, tx, rigidity);
      c.y = lerp(c.y, ty, rigidity);
    }
  }

  capSegmentStretch() {
    const whip = this.whip;
    if (!whip || whip.length < 2) return;
    for (let i = 0; i < whip.length - 1; i++) {
      const a = whip[i];
      const b = whip[i + 1];
      const dx = b.x - a.x;
      const dy = b.y - a.y;
      const dist = Math.sqrt(dx * dx + dy * dy) || 0.0001;
      const maxLen = this.segLen(i) * P.maxStretchRatio;
      if (dist <= maxLen) continue;
      const k = maxLen / dist;
      b.x = a.x + dx * k;
      b.y = a.y + dy * k;
    }
  }

  applyWallCollisions() {
    const whip = this.whip;
    if (!whip || this.dropping) return; // disable collisions while dropping
    const W = this.W;
    const H = this.H;
    const start = 1; // keep pinned handle untouched
    for (let i = start; i < whip.length; i++) {
      const p = whip[i];
      let vx = p.x - p.px;
      let vy = p.y - p.py;
      let hit = false;

      if (p.x < 0) {
        p.x = 0;
        if (vx < 0) vx = -vx * P.wallBounce;
        vy *= P.wallFriction;
        hit = true;
      } else if (p.x > W) {
        p.x = W;
        if (vx > 0) vx = -vx * P.wallBounce;
        vy *= P.wallFriction;
        hit = true;
      }

      if (p.y < 0) {
        p.y = 0;
        if (vy < 0) vy = -vy * P.wallBounce;
        vx *= P.wallFriction;
        hit = true;
      } else if (p.y > H) {
        p.y = H;
        if (vy > 0) vy = -vy * P.wallBounce;
        vx *= P.wallFriction;
        hit = true;
      }

      if (hit) {
        p.px = p.x - vx;
        p.py = p.y - vy;
      }
    }
  }

  // ── Physics step ────────────────────────────────────────────────────────────
  // Faithful port of update(). `now` (ms) is injected and used for crack
  // detection. Returns true iff a crack fired this call.
  update(now) {
    const whip = this.whip;
    if (!whip) return false;

    let crackFired = false;

    const g = this.dropping ? P.dropGravity : P.gravity;
    this.updateHandleAim();

    // Verlet integration
    const start = this.dropping ? 0 : 1; // if dropping, handle is free too
    for (let i = start; i < whip.length; i++) {
      const p = whip[i];
      const vx = (p.x - p.px) * P.damping;
      const vy = (p.y - p.py) * P.damping;
      p.px = p.x;
      p.py = p.y;
      p.x += vx;
      p.y += vy + g;
    }

    // Pin handle to mouse
    if (!this.dropping) {
      whip[0].x = this.mouseX;
      whip[0].y = this.mouseY;
      whip[0].px = this.mouseX;
      whip[0].py = this.mouseY;
    }

    // Prevent rubber-band stretching spikes before constraints.
    this.capSegmentStretch();
    this.applyWallCollisions();

    // Keep early whip segments posed upward from handle.
    this.applyBasePose();

    // Distance constraints (multiple iterations for stiffness)
    for (let iter = 0; iter < P.constraintIters; iter++) {
      for (let i = 0; i < whip.length - 1; i++) {
        const a = whip[i], b = whip[i + 1];
        const dx = b.x - a.x, dy = b.y - a.y;
        const dist = Math.sqrt(dx * dx + dy * dy) || 0.0001;
        const target = this.segLen(i);
        const diff = (dist - target) / dist * 0.5;
        const ox = dx * diff, oy = dy * diff;
        if (i === 0 && !this.dropping) {
          // Handle is pinned – push only the next point
          b.x -= ox * 2;
          b.y -= oy * 2;
        } else {
          a.x += ox; a.y += oy;
          b.x -= ox; b.y -= oy;
        }
      }
      // Clamp bend angle per joint; near handle = stiffer, near tip = floppier.
      this.applyBendLimits();
      if (!this.dropping) this.applyBasePose();
      this.capSegmentStretch();
      this.applyWallCollisions();
    }

    // Tip velocity for crack detection. sqrt(a*a+b*b) form to bit-match Swift.
    const tip = whip[whip.length - 1];
    const tdx = tip.x - tip.px;
    const tdy = tip.y - tip.py;
    const tipVel = Math.sqrt(tdx * tdx + tdy * tdy);

    if (!this.dropping && tipVel > P.crackSpeed) {
      // `now` is injected (was Date.now() in the JS).
      if (now - this.whipSpawnTime >= P.firstCrackGraceMs && now - this.lastCrackTime > P.crackCooldownMs) {
        this.lastCrackTime = now;
        // playCrackSound() + window.bridge.whipCrack() are side effects we model
        // as "a crack fired this frame".
        crackFired = true;
      }
    }

    // If dropping, check if everything fell off screen
    if (this.dropping && whip.every(p => p.y > this.H + 60)) {
      this.whip = null;
      this.dropping = false;
    }
    this.prevMouseX = this.mouseX;
    this.prevMouseY = this.mouseY;

    return crackFired;
  }
}

module.exports = { WhipSim, P, clamp, lerp, wrapPi };
