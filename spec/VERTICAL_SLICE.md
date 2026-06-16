# VERTICAL_SLICE.md — MVP scope + verifiable build contract (v0.4.2)

**Purpose.** Define the smallest playable slice that demonstrates the v0.4 core loop —
**economic optimization → relic → prestige power-growth** — and decompose it into independently
buildable, independently verifiable units. Each unit has a machine-checkable pass condition (a
headless command that must exit 0). The build workflows consume this file.

> Read `spec/SPEC.md` (v0.4.2) for the design + `AC-x.y.z` criteria, `spec/AGENTS.md` /
> `CLAUDE.md` for conventions, and `spec/ROADMAP.md` for everything past the slice. **This is a
> v0.4 rewrite; the existing code was built against v0.3 — §0 is the salvage map.**
>
> **v0.4.2 addendum:** Motherload is now the primary look/feel reference, and AC-5.3.9 adds a
> concrete platform-as-lid guardrail: a default straight-down throw in an open shaft must enter the
> mine, not rest on the launcher/platform line. The previously audited v0.4 slice predates this AC;
> do not call the latest spec fully green until the U10 smoke test below is added and passes.

---

## 0. Salvage map (v0.3 code → v0.4)

A 2026-06-14 four-cluster review found: both gates green (132 tests), architecture structurally sound
where pure (clean core split, strong pure-logic tests), but ~half the slice is built on now-removed
v0.3 assumptions, plus real bugs. **Do not rebuild from scratch — salvage.** Disposition:

**KEEP (survives v0.4, light touch):**
- `scripts/core/aim.gd` — pure angle/impulse math; orthogonal to the pivot.
- `scripts/core/blast.gd` — pure structure; ADD an injected seeded RNG for fuzzy radius (default-off
  keeps goldens green) and fix the radius-vs-falloff dual-bound (single source of truth).
- `scripts/systems/block_grid.gd` — per-chunk HP store + windowing + damage/break lifecycle.
- `scripts/core/registry.gd` — accessors (drop the hardcoded balance fallbacks).
- `scripts/systems/economy.gd` — most v0.4-aligned file; per-dig money + double-credit guard + loot.
- The strong pure-logic test suites + the golden-test *approach*.

**REWORK (built toward a removed contract):**
- `scripts/core/block_gen.gd` — replace the custom hash with **FastNoiseLite** (coherent noise/veins);
  add a `mine_seed`/mine param to the signature.
- `scripts/systems/charge.gd` + `scripts/core/throw_params.gd` — `simulate_path` → **initial-arc-only
  (to first bounce)**, moved OUT of the `RigidBody2D` class into core; pull gravity/dt from project
  settings or `/data`; fix the **cell-conversion bug** (`floori`, not `int()` truncation).
- `scripts/systems/run_state.gd` — replace tray-exhaustion run-end with **relic-ends-dig**; add the
  **free unlimited charge** as a permanent slot; fix the non-reproducible `_grant_pack` RNG (seed from
  run seed, advance per draw); make `end_run` idempotent; stop leaking the live `tray` array.
- `data/*.json` — add the free unlimited charge (flagged) + efficiency descriptors; add depth + per-mine
  HP multipliers; add `relics`/objective data; remove the price-0 "starter pack"; require `fuse_seconds`
  for fuse charges; implement-or-remove `pity_every`.
- `scripts/core/data_validator.gd` — add the missing rules (see U1/U8); validate falloff-length==radius,
  free-charge-exists-and-solvable, fuse-present, starting_money/run_seed/body-caps.

**DELETE (pins a dead design or is vacuous):**
- The "preview==actual"/determinism tests: `test_throw_params.gd::test_simulate_path_determinism`,
  `test_aim.gd::test_same_coords_same_angle`.
- The tray-exhaustion run-end tests in `test_run_loop.gd` and `test_level_smoke.gd`
  (`test_run_ends_after_all_charges`, `test_throw_empty_tray_returns_empty`, starter-pack-of-N tests).
- The self-healing golden branches (missing golden must **fail**, not auto-write).
- `test_block_grid.gd::test_hp_stored_in_side_array_not_tilemap` (`is RefCounted` tautology) →
  replace with a real per-cell-HP storage assertion.
- `scripts/ui/mine.gd` as-is (619-line god-object, empty scenes, ColorRect explosions, magic numbers,
  encodes the v0.3 model, zero self-coverage) → **rebuild as a real `mine.tscn` + thin controller.**

**Design-independent bugs to fix regardless** (carry into the relevant unit):
floori cell conversion; `_grant_pack` RNG; `end_run` idempotency; leaky `tray` getter; vestigial
`hardness` field (wire it into HP derivation or delete it); camera per-frame hard-set fighting
`position_smoothing`; golden self-heal; blast radius/falloff dual-bound; CLAUDE.md stale counts
(97→132) and the false "max_hp derived from hardness" claim.

---

## 1. Slice scope

**In the slice (one playable mine that closes the core loop):**
- One block-grid mine: chunked `TileMapLayer` shaft, typed square blocks, per-cell HP **scaled by
  depth** (per-mine hardness is a single constant here; the roster is ROADMAP).
- Procedural generation via **FastNoiseLite**: block type per cell = pure fn of (mine seed, cell),
  depth-banded, coherent (ore veins).
- Destruction: **fuzzy (seeded) blast** deals radial damage; blocks crack through stages; break at 0.
- Physics (Rapier, **non-deterministic**): a thrown charge is a rigid body; **forgiving aim** with an
  **initial-arc preview** (pre-first-bounce only).
- Controls: drag adjusts launch **angle**; **throw button** commits; power = charge base impulse.
- A **free, unlimited, weak charge** always in the tray; at least one **efficient** charge buyable
  from a pack (so the optimization delta is visible).
- Detonation per the charge's `detonation_mode`.
- Platform descent + smoothed camera (camera follows the platform target, not hard-set per frame).
- Economy: auto-credit ore value on break; money counter; one depth band's loot.
- **A relic** placed in the mine; collecting it **ends the dig**.
- **Minimal prestige:** dig-end banks prestige → buy **one permanent upgrade** → the next dig is
  **measurably stronger** (closes the power-growth loop in miniature).
- **Minimal audio (v0.4.1):** a `Master → {SFX, Music}` bus layout + **placeholder SFX** for the seven
  core events (detonate/crack/break/ore-credited/pack-open/relic-found/prestige-banked) + first-gesture
  web unlock. Pulled into the slice to honour SPEC AC-5.13.1 ("placeholder SFX from the step-1 slice")
  — the earlier deferral here contradicted the spec. Full sound design/mix stays ROADMAP.
- **Non-color block identity (v0.4.1, pulled fwd from ROADMAP U23):** each block type renders a distinct
  **colour** (data-driven `palette.json`, colorblind-safe, luminance-contrast **gate-enforced**) PLUS a
  distinct **glyph** on a shared overlay `GlyphLayer`; the tray shows a non-color **tier glyph**
  (AC-5.10.2/5.10.3). Pulled in because block identity previously rode the *placeholder* texture (all
  types identical) — a real playability + accessibility gap. Procedural placeholder art; real art assets,
  the settings (motion/text-scale/volume) sliders, and reveal-a11y stay ROADMAP (U23/U26).
- **Save core (v0.4.1, pulled fwd from ROADMAP U20):** the durable progression (prestige points +
  purchases) persists across an app restart — `SaveCodec` (versioned + migration) + `SaveManager`
  (atomic write, rolling backup, recovery chain) wired to load on boot + autosave at the relic/dig
  boundary + focus-out (AC-5.11.1/2/3/4). Pulled in because the slice's whole *hook* is power growth,
  which was meaningless if it evaporated on close. Web persistence (IndexedDB detection + export/import,
  AC-5.11.5) and per-mine-roster persistence stay ROADMAP (U20/U21).
- **Portrait safe-area + touch targets (v0.4.2, pulled fwd from ROADMAP — AC-5.8.5):** the HUD lays its
  top/nav/bottom bars out inside the **device safe area** (bottom controls clear the home-indicator/
  gesture zone, top clears the notch) via the pure `UiLayout.safe_insets`, fed live DisplayServer metrics
  and a data-driven base edge margin; every interactive control meets a data-driven thumb-safe **touch
  target** (`ui_min_touch_target_px`); the tray lives in a horizontal **ScrollContainer** (scrolls, never
  shrinks below the target or overflows the bar). Pulled in because block identity + audio were polished
  while the HUD was still a debug harness (controls flush to the screen edge over the play field) — a real
  portrait-playability gap.
- **Nav → modal Settings overlay + accessibility settings (v0.4.3, pulled fwd from ROADMAP — AC-5.8.3 /
  AC-5.10.1 / AC-5.8.6):** the nav button (≡) opens a **modal overlay** (`scenes/overlay.tscn`,
  `process_mode=ALWAYS`) that **pauses the Mine** (`get_tree().paused = true`) — the dig stays instanced +
  frozen and is restored on close. Its in-slice tab is **Settings**, hosting all four AC-5.10.1 settings
  via the pure `SettingsState`: SFX/Music volume → the audio buses, motion intensity → the explosion
  particle spray (reduced-motion floor, AC-5.10.4 intent), and UI text scale → the HUD font + money
  **abbreviation** (closing **AC-5.8.6**: the top readout fits its slot at max scale on the shipped width).
  Defaults are /data (`balance.settings`, gate-enforced); the values **persist** via the save codec (bumped
  to **v2** with a `settings` block). Pulled in because the nav button was a dead control and there was no
  way to adjust volume/motion/text size — a real player-facing + accessibility gap. The **Hub/Mine-select,
  Shop, and Upgrades/Prestige overlay tabs** (the other AC-5.8.3 destinations), the **Credits screen
  (AC-5.8.7)**, **OS reduced-motion seeding + reveal-a11y (AC-5.10.4)**, and an icon-only HUD compact mode
  for extreme text scale on the narrowest phone stay ROADMAP.

**Out of the slice (ROADMAP, seams left):**
- Full gacha/pity, the full prestige tree, the mine hub + buy-access, multiple authored mines,
  the authored ending, narrative reveal, the **Hub/Shop/Upgrades** overlay *tabs* + the Credits screen,
  **full** audio design/mix (the placeholder SFX layer + bus IS in the slice), per-target export hardening.
  (The Settings overlay + its volume/motion/text-scale sliders + save-to-disk ARE in the slice.)

**Non-goals that can't be auto-verified (out-of-band):** "feels good", visual juice, the
optimization-feel gate — those are the developer's call (Verifier class E in ROADMAP §V).

---

## 2. Architecture & contracts

- **Pure logic in `scripts/core/`** — no Node/scene/input deps; headless + unit-tested directly.
- **Systems in `scripts/systems/`** — autoloads/managers wrapping core logic, owning state.
- **Nodes/scenes in `scripts/ui/` + `/scenes`** — thin; delegate to core/systems. Scenes are authored
  in the editor (NOT built imperatively in `_ready()`).
- **All tunables in `/data` JSON**, validated by `DataValidator`. No balance literals in code.
- **Determinism contract (v0.4):**
  - Generation: `BlockGen.block_at(mine_seed, cell)` is a pure, deterministic function (FastNoiseLite
    with a fixed seed) — golden-tested.
  - Blast: `Blast.resolve(hp_snapshot, center, radius, intensity, falloff, rng)` is pure; the fuzzy
    factor is drawn from the **injected `rng`** in a fixed walk order, so a fixed seed → fixed result
    (golden-tested). Computed against the pre-blast snapshot; no chain propagation.
  - **Physics is NOT deterministic and is not relied upon.** No physics golden tests. The aim preview
    is an initial-arc hint and need not match flight.
- **No lose state.** A throw is always possible (free charge). The tray is never empty.
- **AC traceability:** every test references the `AC-x.y.z` it covers in a comment.

---

## 3. The gates (a unit is "done" only when these exit 0)

```bash
tools/validate_data.sh          # data-integrity gate (SPEC §7)
tools/run_tests.sh tests        # full headless test suite
tools/run_tests.sh tests/unit/test_<unit>.gd   # a single unit's suite (fast inner loop)
```

`GODOT_BIN` defaults to `godot` (Godot 4.6.3). Reports in `reports/`. CI runs both gates on push.
**Audit hardening (do early):** golden tests must FAIL on a missing pin (no self-write); a coverage
report (`reports/spec-coverage.md`) maps each AC → asserting test (ROADMAP §process).

---

## 4. Unit dependency graph

```
U0 Foundation (DONE) ── contracts, harness, data, gates
       │
U1 Data access ──► U2 BlockGen(FastNoiseLite+relic) ──► U3 BlockGrid(HP scaling+relic break) ──► U4 Blast(fuzzy)
                                          │                              │
U5 Physics/charge(non-det) ──► U6 Aim & initial-arc preview ────────────┤
                                          ▼                              ▼
                          U7 Descent+camera     U8 Economy(free charge)     U9 Dig loop(relic-ends-dig + minimal prestige)
                                          └───────────────┬──────────────────┘
                                                          ▼
                                          U10 Level assembly (real scene + thin controller)
```

Units with no edge between them are parallelizable by separate workflow runs once their inputs exist.

---

## 5. Units (each = one workflow run, gated by its tests)

For every unit: **Goal → Files → ACs → Tests → Gate → DoD.** DoD always includes: data gate green,
the unit's tests green, full suite green (no new orphans/errors), no hardcoded balance, AC ids cited.

### U0 — Foundation ✅ DONE
Project, Rapier + gdUnit4, `GameData` autoload, `DataValidator`, seed `/data`, both gates.

### U1 — Data access layer  *(KEEP + harden)*
- **Goal:** typed accessors over raw tables; harden the validator.
- **Files:** `scripts/systems/game_data.gd`, `scripts/core/registry.gd`, `scripts/core/data_validator.gd`.
- **ACs:** AC-5.1.5, AC-5.4.1, AC-5.5.4, AC-5.5.5, AC-5.4.3.
- **Tests** `tests/unit/test_registry.gd`, `tests/unit/test_data_integrity.gd`:
  - block/explosive/pack/band accessors; **remove hardcoded balance fallbacks** (missing data → gate
    failure, not a playable default).
  - **New validator rules (with negative tests):** falloff length == `blast_radius_cells`+1; fuse-mode
    explosive has `fuse_seconds>0`; the **free unlimited charge exists** (flagged) and can break the
    shallowest floor; `starting_money`/`run_seed`/body-caps present and sane; `pity_every` implemented
    or absent.
- **Gate:** `tools/run_tests.sh tests/unit/test_registry.gd` (+ data gate).

### U2 — Procedural generation (FastNoiseLite + relic)  *(REWORK)*
- **Goal:** `BlockGen.block_at(mine_seed, x, y) -> String` using **FastNoiseLite** (coherent,
  depth-banded, veins); plus `relic_at(mine_seed, cell) -> bool` (pure placement below a min depth).
- **Files:** `scripts/core/block_gen.gd`.
- **ACs:** AC-5.1.3, AC-5.1.4, AC-5.1.7, AC-5.6.1.
- **Tests** `tests/unit/test_block_gen.gd` + golden `tests/golden/gen_surface.txt`:
  - Determinism across repeats + fresh instances; band exclusion; distribution within tolerance.
  - **Coherence:** assert spatial autocorrelation (neighbors share type more than chance) — i.e. veins,
    not salt-and-pepper (this is the FastNoiseLite point).
  - Relic placement is deterministic and only below the configured min depth; golden re-pins.
  - **Golden must FAIL if missing** (no self-write).
- **Gate:** `tools/run_tests.sh tests/unit/test_block_gen.gd`.

### U3 — Block grid + per-cell HP store (HP scaling + relic break)  *(KEEP + extend)*
- **Goal:** `BlockGrid` wraps `TileMapLayer` + per-chunk `PackedInt32Array` HP; HP = `base_hp(hardness)
  × depth_mult × mine_hardness_mult` (from `/data`), applied once at chunk init; breaking the relic
  cell emits a relic-collected signal.
- **Files:** `scripts/systems/block_grid.gd`, `scenes/block_grid.tscn`.
- **ACs:** AC-5.2.1, AC-5.2.2, AC-5.2.7, AC-5.1.2, AC-5.1.6, AC-5.6.2.
- **Tests** `tests/unit/test_block_grid.gd`:
  - HP inits from the **scaled** formula (assert deeper cells have higher HP); damage/solid/break
    lifecycle; surviving block retains damage; chunk recycle keeps resident count ≤ window.
  - **Real** per-cell-HP-in-side-array assertion (not `is RefCounted`): mutate HP, assert it reads back
    from the array and the TileMap cell id is unchanged.
  - Breaking the relic cell signals exactly once.
  - Decide `hardness`: wire it into `base_hp` derivation **or** delete the field + its validation.
- **Gate:** `tools/run_tests.sh tests/unit/test_block_grid.gd`.

### U4 — Blast (fuzzy, seeded)  *(REWORK)*
- **Goal:** `Blast.resolve(hp_snapshot, center, radius, intensity, falloff, rng) -> {damaged, cleared}`
  with a **fuzzy factor drawn from `rng`** per cell in a fixed walk order; `crack_stage(hp, max_hp,
  stages)` with the pinned 0..stages-1 contract.
- **Files:** `scripts/core/blast.gd`.
- **ACs:** AC-5.2.3, AC-5.2.4, AC-5.2.5, AC-5.2.6, AC-5.4.6.
- **Tests** `tests/unit/test_blast.gd` + golden `tests/golden/blast_basic.txt`:
  - **Single source of truth** for radius (resolve the falloff dual-bound first).
  - With a **fixed-seed rng**, output is identical run-to-run (golden); with different seeds, the
    cleared set varies (assert the fuzz actually fuzzes).
  - Pre-blast-snapshot / no-chain-prop; harder rock survives where softer clears; crack-stage mapping
    monotonic with the explicit range.
  - **Golden must FAIL if missing.**
- **Gate:** `tools/run_tests.sh tests/unit/test_blast.gd`.

### U5 — Physics / charge (non-deterministic)  *(REWORK)*
- **Goal:** spawn the charge as a Rapier `RigidBody2D`, apply launch impulse, detonate per
  `detonation_mode` (incl. sticky→freeze; `on_rest` resolves even with no prior impact — fix the
  soft-lock). **No determinism contract, no physics golden.** Fix the `floori` cell-conversion bug.
- **Files:** `scripts/systems/charge.gd`, `scenes/charge.tscn`, `scripts/core/throw_params.gd`.
- **ACs:** AC-5.3.3, AC-5.4.1, AC-5.4.2.
- **Tests** `tests/integration/test_charge.gd` (headless; call spawn/step API directly):
  - Detonation timing per mode (`fuse_seconds`, `on_first_impact`, `on_rest`, sticky); the
    no-impact-`on_rest` case resolves; cell conversion floors correctly at negative x.
  - **No determinism test** (removed by design).
- **Gate:** `tools/run_tests.sh tests/integration/test_charge.gd`.

### U6 — Aim & initial-arc preview  *(REWORK)*
- **Goal:** `Aim.angle_from_drag(start, current) -> float`; a pure `Aim.initial_arc(params, angle,
  muzzle) -> PackedVector2Array` that returns the throw path **up to the first predicted bounce only**
  (moved out of the RigidBody class; gravity/dt from project settings/`/data`). Tap selects tray slot.
- **Files:** `scripts/core/aim.gd`, `scripts/ui/aim_controller.gd`, `scripts/ui/throw_button.gd`.
- **ACs:** AC-5.3.1, AC-5.3.2, AC-5.3.6, AC-5.3.7, AC-5.3.8.
- **Tests** `tests/unit/test_aim.gd`:
  - `angle_from_drag` correct/clamped; below dead-zone → no change.
  - `initial_arc` starts at the muzzle and **ends at/just past the first surface contact** (not a full
    multi-bounce projection).
  - Parity is **structural**: one shared `angle_from_drag`+`throw()` path for mouse/touch (assert via
    the shared function, since input events don't fire headless). **Delete** the determinism tautology.
- **Gate:** `tools/run_tests.sh tests/unit/test_aim.gd`.

### U7 — Platform descent + camera  *(KEEP + fix camera)*
- **Goal:** count cleared cells beneath the platform; at threshold, tween the platform target down;
  **camera follows the platform target via position smoothing — not hard-set per frame.**
- **Files:** `scripts/systems/platform.gd`, `scenes/platform.tscn`.
- **ACs:** AC-5.7.1, AC-5.7.2, AC-5.7.3.
- **Tests** `tests/unit/test_platform.gd`:
  - `cleared_beneath` counts; below/at threshold behavior; one descent step per trigger; camera target
    == platform target (logic-level); no magic descent-depth literal (comes from `/data`).
- **Gate:** `tools/run_tests.sh tests/unit/test_platform.gd`.

### U8 — Economy (free charge + per-dig money)  *(KEEP)*
- **Goal:** `Economy`: `credit(block_id)` adds `ore.value` once per broken cell; `money` starts at
  `balance.starting_money`; `draw_loot(depth, rng)` samples the band; per-dig reset.
- **Files:** `scripts/systems/economy.gd`.
- **ACs:** AC-5.5.1, AC-5.5.2, AC-5.5.3, AC-5.5.4.
- **Tests** `tests/unit/test_economy.gd`:
  - Ore credit exact + once; non-ore = 0; loot distribution within tolerance; `reset_dig()` → starting
    money. (These largely survive; re-point any "starter pack" assertions to the free-charge model.)
- **Gate:** `tools/run_tests.sh tests/unit/test_economy.gd`.

### U9 — Dig loop (relic-ends-dig + minimal prestige)  *(REWORK — biggest behavioral change)*
- **Goal:** `RunState`: the tray always contains the **free unlimited charge** (never decremented,
  never empty); `buy_pack(id)` debits money + grants efficient charges (reproducible RNG seeded from
  the run seed); **collecting the relic ends the dig** → bank prestige → reset per-dig state; a
  **minimal prestige purchase** (`buy_upgrade(id)`) makes the next dig measurably stronger; `end_dig`
  is idempotent; `tray` getter returns a copy.
- **Files:** `scripts/systems/run_state.gd`, `scripts/systems/prestige.gd` (minimal).
- **ACs:** AC-5.3.3, AC-5.3.8, AC-5.4.3, AC-5.4.4, AC-5.4.5, AC-5.6.2, AC-5.6.3, AC-5.6.4, AC-5.12.1, AC-5.12.2.
- **Tests** `tests/integration/test_dig_loop.gd`:
  - Free charge always present + ∞ (throwing it never decrements); a throw is always possible (no
    empty-tray state — **delete the old empty-tray tests**).
  - `buy_pack` debits + grants efficient charges; unaffordable rejected; rolls reproducible from seed.
  - **Relic collected → dig ends, prestige banked once** (idempotent), per-dig state reset.
  - **Power growth:** after `buy_upgrade`, a measurable dig stat improves (e.g. blast intensity or
    descent threshold) on the next dig.
  - Pity implemented + tested, or absent.
- **Gate:** `tools/run_tests.sh tests/integration/test_dig_loop.gd`.

### U10 — Level assembly (real scene + thin controller)  *(DELETE old mine.gd → rebuild)*
- **Goal:** author `scenes/mine.tscn` in the editor (TileMapLayers, Camera2D, HUD, platform, tray,
  throw button); a **thin** `scripts/ui/mine.gd` controller delegates to core/systems. Wire:
  forgiving aim + initial-arc preview, free charge + one bought efficient charge, fuzzy blast,
  ore→money, **relic → dig-end → prestige screen → buy one upgrade → next dig is stronger**. Particle
  explosions (no `ColorRect`). `main.tscn` loads it.
- **Files:** `scenes/mine.tscn`, `scripts/ui/mine.gd`, `scripts/ui/hud.gd`, `scripts/ui/tray.gd`,
  `scripts/ui/dig_end_panel.gd`, update `scenes/main.tscn`.
- **ACs:** AC-5.3.9, AC-5.8.1, AC-5.8.2, AC-5.8.4, AC-5.9.1, plus end-to-end of U1–U9.
- **Tests** `tests/integration/test_level_smoke.gd` (headless; **actually instantiate `mine.tscn`**;
  drive via direct calls, not input):
  - Boot `mine.tscn`; assert it instantiates with no errors and the free charge is present.
  - Default straight-down throw in an otherwise open shaft: after up to one physics second, the live
    charge has passed below platform collision and has not rested on the launcher/platform line
    (AC-5.3.9).
  - Scripted sequence: select charge → `throw(angle)` at a solvable floor → advance physics → ≥1 block
    cleared, money increased by the cleared ore value, platform descends after enough clears.
  - Break the relic cell → dig ends, prestige banked, and a subsequent dig reflects the bought upgrade.
  - No orphan nodes after the level is freed.
- **Gate:** `tools/run_tests.sh tests` (whole suite, incl. this integration test, exit 0).

---

## 6. How a build workflow consumes this

Each unit is one `build-unit` workflow run, parameterized by the unit id. The workflow reads
`spec/SPEC.md`, `spec/AGENTS.md` (or `CLAUDE.md`), and this unit's section; architects; implements the
files + gdUnit4 tests asserting the listed ACs; runs the gates; bounded-fix-loops to green; returns a
structured result (files, AC→test map, gate output). `build-slice` runs U1→U10 in dep order, gating
each. `verify-slice` re-runs every gate + golden + the AC→test coverage audit (and should emit
`reports/spec-coverage.md`). Because each unit's "done" is an exit-0 command, the workflows don't rely
on eyeballing — but per the 2026-06-14 review, "green" is not enough: golden files must fail-on-missing,
structural claims must actually assert, and a milestone-boundary AC-faithfulness review guards against
vacuous green (ROADMAP §process).
