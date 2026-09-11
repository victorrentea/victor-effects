# Whip physics — cross-language parity harness

Golden-value generator for the Verlet whip simulation. The JavaScript reference
lives in `/tmp/OpenWhip/overlay.html` (a `<script>`-tag canvas demo). This
harness extracts ONLY the physics into a deterministic Node module and emits
golden snapshots so a Swift port can assert numerical parity in an XCTest.

## Files

| File | Purpose |
| --- | --- |
| `whip-physics.js` | CommonJS module exporting `WhipSim` (+ `P`, `clamp`, `lerp`, `wrapPi`). Faithful, rendering-free port of the physics in `overlay.html`. |
| `generate-golden.js` | Runs the two fixed scenarios and writes the golden JSON. |
| `../../Tests/VictorEffectsTests/Resources/whip_golden.json` | The generated golden values (committed; the test target copies `Resources`). |

## Regenerate

```bash
cd <repo-root>
node tools/whip-parity/generate-golden.js
```

The output is **deterministic** — there is no randomness on the physics path
(`Math.random` only picked a crack *sound* in the original, which is not ported),
and time is injected (`now`), so two runs produce byte-identical JSON:

```bash
node tools/whip-parity/generate-golden.js && cp Tests/VictorEffectsTests/Resources/whip_golden.json /tmp/a.json
node tools/whip-parity/generate-golden.js
cmp Tests/VictorEffectsTests/Resources/whip_golden.json /tmp/a.json   # no output = identical
```

## What was ported (and what was not)

Ported verbatim (physics): the PHYSICS-relevant fields of `P`; `spawnWhip`,
`segLen`, `clamp`, `lerp`, `wrapPi`, `updateHandleAim`, `applyBasePose`,
`applyBendLimits`, `capSegmentStretch`, `applyWallCollisions`, `update`.

Deliberately excluded: `catmullPoint`, `whipSegmentBezier`, `draw` (rendering),
and the purely-visual `P` fields (`lineWidth*`, `outlineWidth`,
`handleExtraWidth`, `handleThickSegments`, `bgAlpha`).

### The one intentional change: time injection

Every `Date.now()` is replaced by an injected `now`:

- `update(now)` takes `now` (ms) and uses it for crack detection.
- `whipSpawnTime` is set by the caller (the runner sets it to `0`), NOT inside
  `spawnWhip` (the JS did `whipSpawnTime = Date.now()` there).
- `update(now)` **returns `true` iff a crack fired this frame** (modelling the
  `playCrackSound()` / `window.bridge.whipCrack()` side effects).

### Operation order (must match byte-for-byte in Swift)

Inside `update(now)`:

1. `updateHandleAim()`
2. Verlet integrate (`start = dropping ? 0 : 1`)
3. Pin handle to mouse (when not dropping)
4. `capSegmentStretch()`
5. `applyWallCollisions()`
6. `applyBasePose()`
7. For `iter` in `0..<constraintIters` (20):
   - distance constraints over links `0..<length-1` (link 0 pushes only `b` by
     `-ox*2` / `-oy*2` when pinned)
   - `applyBendLimits()`
   - `applyBasePose()` (when not dropping)
   - `capSegmentStretch()`
   - `applyWallCollisions()`
8. crack detection (tip velocity vs `crackSpeed`, with grace + cooldown)
9. `prevMouseX/Y = mouseX/Y`  ← at the END

## Scenario definitions (mirror these byte-for-byte in Swift)

**Common setup** (both scenarios): `W=1280, H=800`. `spawnWhip(640, 400)`, then
`whipSpawnTime=0`, `handleAngle=baseTargetAngle`, `handleAngVel=0`,
`mouseX=mouseY` → wait, mouse is `(640,400)`, `prevMouseX/Y=(640,400)`,
`dropping=false`, `lastCrackTime=0`.

**Frame loop** for `f = 1..N` inclusive:
1. `mouseX, mouseY = path(f)`
2. `now = f * 16` (ms)
3. `update(now)`

(`update` pins the handle to the mouse, integrates, solves constraints, detects
the crack, and sets `prevMouse = mouse` at the END.)

### settle

`path(f) = (640, 400)` for all `f`. `N = 60`. Snapshot frames
`S = [1, 5, 15, 30, 45, 60]`. Each snapshot records all 28 points as `[x, y]`
pairs at full double precision.

### swing

`N = 45`. `path(f)`:

- `f` in `1..10`:  `(640, 400)`
- `f` in `11..25`: `(min(1200, 640 + (f-10)*40), 400)`
- `f` in `26..45`: `(max(80, 1200 - (f-25)*55), 400)`

Records `crackFrames` (frame indices where `update` reported a crack — **empty**
for this gentle path; max tip velocity ≈ 181 px/frame vs the 340 threshold),
`tipVelByFrame` (45 values of `hypot(tip.x-tip.px, tip.y-tip.py)` measured after
each `update`), and the final 28 points at frame 45.

## Golden JSON shape

```jsonc
{
  "scenario": { "W":1280, "H":800, "segments":28, "spawnX":640, "spawnY":400, "frameMs":16 },
  "settle":   { "snapshotFrames":[1,5,15,30,45,60], "points": { "1":[[x,y]…28], … } },
  "swing":    { "N":45, "crackFrames":[…], "tipVelByFrame":[…45…], "finalPoints":[[x,y]…28] }
}
```

## Notes for the Swift port (parity gotchas)

- **`Math.acos` domain**: the JS clamps `dot` to `[-1, 1]` *before* `acos`
  (`applyBendLimits`). Swift `acos` returns NaN just outside the domain, so keep
  that clamp.
- **`hypot` `|| 0.0001`**: JS uses `Math.hypot(...) || 0.0001` (and
  `Math.sqrt(...) || 0.0001`) to avoid divide-by-zero. In Swift, `||` is a JS
  *falsy-or* — `0` and `NaN` both fall through to `0.0001`. Replicate that
  (treat `0` **and** `NaN` as the fallback), not just `0`.
- **All math is `Double`** — the JS numbers are IEEE-754 doubles. Use `Double`
  in Swift; do not let any value become a `Float` or `CGFloat` (which is 32-bit
  on some targets) mid-pipeline. Integer division is not a hazard here because
  every divisor (`segments-1`, `whip.length-2`, `6`, etc.) participates in
  floating context, but ensure e.g. `i / (segments - 1)` is computed as
  `Double(i) / Double(segments - 1)`, not integer `/`.
- **Array-mutation aliasing**: the JS mutates point objects in place and the
  constraint/bend/pose passes read neighbours that may have been written earlier
  in the same loop. Swift `struct` points copied out of an array would break
  this aliasing — use reference semantics (a `class Point`, or mutate the array
  by index `whip[i].x = …`) so that a write to `whip[i]` is seen by the read of
  `whip[i]` in the next link's iteration.
- **`wrapPi` loop**: it is a `while` subtracting/adding `2π`, not `fmod`. For the
  small angles here one pass suffices, but keep the loop form for exactness.
- **`lerp` order of ops**: `a + (b - a) * t` — keep this exact form (not
  `a*(1-t)+b*t`) to match rounding.
- **`Math.min`/`Math.max` clamp**: `clamp(v,lo,hi)=max(lo,min(hi,v))` — same
  nesting order.
- **`now` injection**: `now = f*16` is an exact integer; `whipSpawnTime=0`,
  `lastCrackTime=0` at start. Grace `now - whipSpawnTime >= 350`, cooldown
  `now - lastCrackTime > 200`.
