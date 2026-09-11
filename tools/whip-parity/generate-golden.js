'use strict';
// ══════════════════════════════════════════════════════════════════════════════
//  generate-golden.js — deterministic golden-value generator for the whip
//  physics parity test. Runs two fixed scenarios against WhipSim and emits
//  Tests/VictorEffectsTests/Resources/whip_golden.json with FULL double
//  precision (no rounding), so a Swift port can assert numerical parity.
//
//  Determinism: there is no randomness anywhere in the physics path (crack
//  sound selection / Math.random is NOT in WhipSim), and `now` is injected, so
//  running this twice produces byte-identical output.
// ══════════════════════════════════════════════════════════════════════════════

const fs = require('fs');
const path = require('path');
const { WhipSim } = require('./whip-physics');

const W = 1280;
const H = 800;
const SPAWN_X = 640;
const SPAWN_Y = 400;
const FRAME_MS = 16;
const SEGMENTS = 28;

// Build a fresh, fully-initialized sim with the common setup shared by both
// scenarios. (W=1280, H=800; spawn at 640,400; handleAngle=baseTargetAngle;
// handleAngVel=0; mouse + prevMouse at 640,400; dropping=false; lastCrackTime=0;
// whipSpawnTime=0.)
function freshSim() {
  const sim = new WhipSim(W, H);
  sim.spawnWhip(SPAWN_X, SPAWN_Y); // sets sim.whip, dropping=false, lastCrackTime=0
  sim.whipSpawnTime = 0;
  sim.handleAngle = require('./whip-physics').P.baseTargetAngle;
  sim.handleAngVel = 0;
  sim.mouseX = SPAWN_X;
  sim.mouseY = SPAWN_Y;
  sim.prevMouseX = SPAWN_X;
  sim.prevMouseY = SPAWN_Y;
  sim.dropping = false;
  sim.lastCrackTime = 0;
  return sim;
}

// Snapshot all 28 points as [x,y] pairs at full precision.
function snapshotPoints(sim) {
  return sim.whip.map(p => [p.x, p.y]);
}

// ── Scenario "settle" ─────────────────────────────────────────────────────────
// path(f) = (640, 400) for all f. N=60. Snapshot frames S.
function runSettle() {
  const N = 60;
  const S = [1, 5, 15, 30, 45, 60];
  const sim = freshSim();
  const points = {};
  const snapSet = new Set(S);

  for (let f = 1; f <= N; f++) {
    // (1) set mouse = path(f)
    sim.mouseX = 640;
    sim.mouseY = 400;
    // (2) now = f*16
    const now = f * FRAME_MS;
    // (3) update
    sim.update(now);

    if (snapSet.has(f)) {
      points[String(f)] = snapshotPoints(sim);
    }
  }

  return { snapshotFrames: S, points };
}

// ── Scenario "swing" ──────────────────────────────────────────────────────────
// N=70. Settle briefly, then a vigorous horizontal oscillation that whips the
// tip past the crackSpeed (260) threshold, producing real cracks (after the
// 350ms spawn grace and respecting the 200ms cooldown). Record crackFrames,
// tipVelByFrame, finalPoints. The handle stays within [320,960]×{400}, safely
// inside the 1280×800 field so wall collisions don't interfere.
function swingPath(f) {
  if (f <= 8) return [640, 400];
  const k = f - 8;
  return [640 + 320 * Math.sin(k * 0.85), 400];
}

function runSwing() {
  const N = 70;
  const sim = freshSim();
  const crackFrames = [];
  const tipVelByFrame = [];

  for (let f = 1; f <= N; f++) {
    const [mx, my] = swingPath(f);
    // (1) set mouse = path(f)
    sim.mouseX = mx;
    sim.mouseY = my;
    // (2) now = f*16
    const now = f * FRAME_MS;
    // (3) update — returns true iff a crack fired this frame
    const cracked = sim.update(now);
    if (cracked) crackFrames.push(f);

    // tip velocity AFTER the update (matches the crack-detection vector).
    // sqrt(a*a+b*b) form to bit-match the Swift port.
    const tip = sim.whip[sim.whip.length - 1];
    const tdx = tip.x - tip.px;
    const tdy = tip.y - tip.py;
    const tipVel = Math.sqrt(tdx * tdx + tdy * tdy);
    tipVelByFrame.push(tipVel);
  }

  return {
    N,
    crackFrames,
    tipVelByFrame,
    finalPoints: snapshotPoints(sim),
  };
}

function main() {
  const settle = runSettle();
  const swing = runSwing();

  const out = {
    scenario: {
      W,
      H,
      segments: SEGMENTS,
      spawnX: SPAWN_X,
      spawnY: SPAWN_Y,
      frameMs: FRAME_MS,
    },
    settle: {
      snapshotFrames: settle.snapshotFrames,
      points: settle.points,
    },
    swing: {
      N: swing.N,
      crackFrames: swing.crackFrames,
      tipVelByFrame: swing.tipVelByFrame,
      finalPoints: swing.finalPoints,
    },
  };

  // Resolve the output path relative to this file: ../../Tests/VictorEffectsTests/Resources
  const outPath = path.resolve(
    __dirname,
    '..',
    '..',
    'Tests',
    'VictorEffectsTests',
    'Resources',
    'whip_golden.json'
  );

  // Pretty-print with 2-space indent. JSON.stringify preserves full double
  // precision for the numbers (no rounding applied anywhere).
  fs.writeFileSync(outPath, JSON.stringify(out, null, 2) + '\n');
  process.stdout.write('Wrote ' + outPath + '\n');
  process.stdout.write('  settle snapshot frames: ' + settle.snapshotFrames.join(',') + '\n');
  process.stdout.write('  swing.crackFrames: [' + swing.crackFrames.join(',') + ']\n');
}

main();
