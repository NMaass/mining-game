> # ⚠️ DEPRECATED — RETIRED PLAN, DO NOT FOLLOW
> This is the superseded **v0.3** quality-recovery plan. It has been **retired** and
> **replaced by `spec/VERTICAL_SLICE.md` § 0 (the v0.4 salvage map)**, which is now the
> single source of truth for what to build and repair. The items below were written against
> v0.3 assumptions (e.g. physics determinism and preview==actual) that **no longer hold under
> v0.4**. The file is kept only for historical reference — do not act on it.
>
> **P0 disposition (resolved by the 2026-06-14 12:30 audit — see `reports/spec-coverage.md`):**
> QP-001 (bounce-accurate preview) = **OBSOLETE** (v0.4 REMOVED AC-5.3.4; preview is initial-arc only,
> implemented in `throw_params.gd`/`aim.gd`). QP-002 (charge collision/detonation under-tested) =
> **RESOLVED** (`test_charge.gd` drives every detonation mode incl. no-soft-lock on_rest;
> `charge.tscn` authors `contact_monitor`). QP-003 (smoke doesn't boot the level) = **RESOLVED**
> (`test_level_smoke.gd` instantiates the authored `mine.tscn` and drives the full loop). QP-004
> (portrait UI) = **PARTIAL** (HUD/tray/dig-end real with non-color tray cue; the settings/nav/shop
> overlays + max-text-scale reflow stay ROADMAP). QP-005 (visual identity / non-color) = **ADDRESSED
> 2026-06-14 22:30** — block identity no longer rides color: a colorblind-safe `palette.json` (per-type
> colour, luminance-contrast gate-enforced) + a shape **glyph overlay** (`GlyphLayer`) + a tray tier
> glyph now render via the pure `block_art.gd`, gate-/test-/mutation-verified (real art assets stay
> ROADMAP). QP-006 (audio) = **ADDRESSED 2026-06-14 17:30** (spec tension resolved in
> favour of the spec — placeholder SFX now ship from the slice: `default_bus_layout.tres` Master→{SFX,
> Music} + an `Audio` autoload with procedural placeholder SFX for the 7 core events + first-gesture web
> unlock, wired into `mine.gd`; `test_audio.gd` + a smoke wiring assert prove it; real SFX assets/mix +
> the volume-slider UI stay ROADMAP). QP-007 (docs overstate completion) = **ADDRESSED**.

# QUALITY_PLAN.md - quality recovery plan after the 2026-06-14 07:30 run

## Why this exists

The 2026-06-14 07:30 unattended run moved quickly and marked the vertical slice as complete even
though several hard acceptance criteria were not actually proven. Treat the current game as a
rough prototype, not a finished slice. Passing tests are useful, but they are not sufficient when
the tests do not exercise the acceptance criteria in `spec/SPEC.md` and `spec/VERTICAL_SLICE.md`.

Future unattended runs must prefer correctness, feel, and evidence over broad feature count.

## Operating rule for the next runs

Do not claim "done", "complete", "playable", or "spec compliant" for a unit unless all of these
are true:

1. The code behavior matches the relevant `AC-x.y.z` requirements in `spec/SPEC.md`.
2. The required test files named by `spec/VERTICAL_SLICE.md` exist and exercise the acceptance
   criteria, not just nearby helper logic.
3. Both gates pass:
   - `tools/validate_data.sh`
   - `tools/run_tests.sh tests`
4. The run handoff includes the evidence: changed files, tests added/updated, gate results, and
   remaining gaps.

If any of those are false, call the unit "provisional" and continue the repair loop.

## P0 spec and verification gaps

These are the first things to attack.

### QP-001 - Bounce-accurate preview is not implemented

- ACs: `AC-5.3.1`, `AC-5.3.4`, `AC-5.7.1`
- Current state: `Charge.simulate_path()` is a deterministic parabola. It ignores terrain, walls,
  platform collision, bounce, friction, and the actual physics body.
- Why it matters: the spec's core promise is that the predicted arc matches the live throw,
  including bounces.
- Required repair: implement a preview simulation that uses the same collision geometry and physics
  parameters as the live charge, or explicitly document why the spec must change before doing so.
- Required tests: add `tests/integration/test_aim_preview.gd` proving preview path and live path
  agree for at least one collision/bounce case.

### QP-002 - Charge collision/detonation behavior is under-tested

- ACs: `AC-5.3.3`, `AC-5.4.1`, `AC-5.4.2`
- Current state: `tests/unit/test_throw_params.gd` mostly validates data extraction and analytic
  helper math. It does not prove live `RigidBody2D` impact, sticky, fuse, or rest detonation.
- Risk to check in code: `RigidBody2D.body_entered` generally requires contact monitoring and a
  nonzero max contacts report count. If those are not configured, `on_first_impact` and sticky
  modes may never fire.
- Required tests: add `tests/integration/test_charge_determinism.gd` per the vertical slice spec.

### QP-003 - Level smoke test does not boot the level

- ACs: `AC-5.8.1`, `AC-5.8.2`, `AC-5.8.4`, end-to-end U1-U10
- Current state: `tests/integration/test_level_smoke.gd` says it boots `mine.tscn`, but its tests
  mostly instantiate systems directly.
- Required repair: add a real headless scene boot test for `res://scenes/mine.tscn`, validate
  required nodes/controls, drive one throw through the scene API, and check for errors/orphans.

### QP-004 - UI does not meet the spec yet

- ACs: `AC-5.8.1` through `AC-5.8.7`, `AC-5.10.1` through `AC-5.10.4`
- Current state: the HUD is a top-row label group plus a hardcoded bottom throw button. It lacks
  the nav button, actual charge tray with per-charge counts, selected-charge non-color indicator,
  compact relic progress, safe-area handling, text-scale behavior, and modal overlay structure.
- Required repair: design the vertical slice UI as a real portrait game surface, not a debug HUD.
  Keep it responsive and thumb-safe.

### QP-005 - Visual identity and accessibility are placeholder-only

- ACs: `AC-5.9.1`, `AC-5.10.2`, `AC-5.10.3`
- Current state: blocks are flat solid colors generated in code. That conveys block identity by
  color alone and has no durable art direction.
- Required repair: choose a concrete colorblind-safe palette, add shape/glyph/pattern identity for
  block types, and create a reusable placeholder tileset/crack overlay path that can become real
  art later.

### QP-006 - Audio and feel gate are missing

- ACs: `AC-5.13.1`, `AC-5.13.2`, `AC-5.13.3`
- Current state: no placeholder SFX or audio bus proof is present.
- Required repair: add the bus layout and placeholder SFX hooks for detonate, crack, break, ore
  credit, pack open, relic found, and run-end. Web audio unlock can be a documented later-web task
  if the current slice cannot exercise a browser export.

### QP-007 - Documentation overstates completion

- Current state: `CLAUDE.md`, `README.md`, and `.claude/weekly-loop-handoff.md` contain statements
  that imply the slice is complete while also listing spec-breaking TODOs.
- Required repair: keep docs brutally accurate. Mark current status as "prototype/provisional"
  until the P0 items above are fixed and tested.

## P1 polish and design work

- Replace hardcoded HUD positions with responsive portrait layout constraints.
- Add real charge tray selection, icons/glyphs, counts, disabled states, and selected state.
- Make the run-end panel explain what ended, what was earned, and how to begin the next run.
- Improve blast feedback with particles or a deterministic placeholder effect that respects motion
  intensity.
- Add tactile game-feel passes: timing, camera smoothing, visual hit feedback, and readable block
  damage stages.
- Verify that all balance values remain in `/data` and are schema-validated.
- Add a spec-to-test traceability table for U1-U10 so missing AC coverage is visible.

## Next recommended run plan

1. Run a read-only audit: compare `spec/SPEC.md`, `spec/VERTICAL_SLICE.md`, tests, and runtime code.
2. Update docs to remove any false "complete" language.
3. Fix QP-002 first if live detonation modes are broken, because it affects gameplay correctness.
4. Add missing integration tests for QP-001 through QP-003.
5. Implement one high-value repair at a time, rerun both gates, then update this file and the
   handoff with exact evidence.

