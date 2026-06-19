# CLAUDE.md — Claude Code operating guide

Folder-scoped guide auto-loaded for this project. It is the **fast path**, derived from
`spec/AGENTS.md` (the full operational reference). Design lives in `spec/SPEC.md` (**v0.6.0**); the MVP
build contract is `spec/VERTICAL_SLICE.md` (its **§0 is the v0.3→v0.4 salvage map**); the post-slice
plan + gap register is `spec/ROADMAP.md`. When code and spec disagree, the spec wins or the spec gets
updated — never silent drift.

## Current status (2026-06-18): v0.6 — infinite mine, fixed elevator, cooldown button, decouple pass
**State:** 583 tests, both gates exit 0 (DATA OK 15 tables, 0 orphans). v0.6 returns the dig to an
**infinite vertical descent** (gen streams chunks around the platform; the v0.5.0 bounded-volume idea
was superseded), adds a fixed continuous-glide **elevator**, a pure-timer **throw-cooldown button**,
logging/debug, camera/dirt/dotted-guide juice, Deep Mine + money upgrades, and a sticky-bomb fix. See
**Build progress** below. Prestige stays **exactly 1 point per relic** via the prestige-offer UI on
relic break; money is per-dig only and does not convert to prestige; no passive income. Primary feel
reference: **Motherload**.

## Previous status (2026-06-15 08:30): v0.4 slice COMPLETE + audited; nav→Settings overlay + accessibility settings landed
**08:30 run:** independently re-verified the 03:30 state (both gates green; the input path is genuinely
wired — not a headless-only harness) then closed the slice's biggest *player-facing* gap: the nav button
(≡) was dead (emitted `nav_pressed` into nothing) and there was **no settings UI**. Built a **modal
Settings overlay** (AC-5.8.3: opening pauses the Mine + preserves dig state, closing restores) hosting
**all four accessibility settings** (AC-5.10.1: SFX/Music volume → the audio buses, motion intensity →
explosion spray, UI text scale → HUD font + number abbreviation closing **AC-5.8.6**), persisted via the
save codec (bumped to **v2** with a `settings` block). Pure `SettingsState` + the codec path are
headless-unit-tested; the REAL overlay (driven through `mine.tscn`) proves pause/preserve/volume-routing/
persistence; **5 mutation spot-checks** each turned a target test red (restored byte-identical). Visual:
`reports/settings_overlay_0830.png`. End state: **329 tests, 20 suites, both gates exit 0.**

A fidelity interview reworked the design into **v0.4** (see SPEC changelog). The v0.4 salvage of
`spec/VERTICAL_SLICE.md` §0 (KEEP / REWORK / DELETE) is **done and independently
audited**: **329 tests, both gates green.** FastNoiseLite gen + fuzzy seeded blast + relic-ends-dig +
free unlimited charge + minimal prestige + a thin `mine.gd` controller over an authored `mine.tscn`
are all real and v0.4-aligned (the `floori` bug, initial-arc-only preview, idempotent `end_dig`,
run-scoped pack RNG, fail-on-missing goldens, and the DELETE-list tautologies are all done). A
21-agent adversarial AC-faithfulness audit (2026-06-14 12:30) took the slice from **33→40 PROVEN ACs**:
fixed the pity-guarantee **tautology** (now mutation-verified), the **MISSING** AC-5.7.1 platform/muzzle
test (+ the orphaned authored `Muzzle` marker), and the validator's **under-enforcement** of AC-5.4.1
(full explosive resource shape), AC-5.4.3 (paid > free efficiency), and AC-5.5.5 (worst-case-fuzz
no-stall). The **2026-06-14 17:30** quality run then fixed the last *wrong* slice item and pulled audio
in: **AC-5.5.2 loot** restated (the "floor rises" clause was false vs. shipped data; now "EV + gem
probability strictly rise", a hard data-gate invariant — dead `Economy.draw_loot` + 3 vacuous tests
removed, real EV/gem tests added, gate rule mutation-verified); **audio (AC-5.13.x) now IN-SLICE** —
`default_bus_layout.tres` (Master→{SFX,Music}) + an `Audio` autoload with procedurally-synthesised
placeholder SFX for the 7 core events + first-gesture web unlock, wired into `mine.gd` (wiring
mutation-verified). The **2026-06-14 22:30** run then landed **non-color block identity (AC-5.10.2/5.10.3)**
— previously inert (all block types rendered as the *same* magenta placeholder). New pure `BlockArt`
helper generates per-type **colour** (data-driven `palette.json`, colorblind-safe, luminance-contrast
gate-enforced) + a shared **glyph overlay** (`GlyphLayer`: dots/cross/bricks/circle/diamond) + crack
art; the tray gained a **tier glyph**; a live screenshot caught + fixed the **magenta placeholder
platform** (now a steel bar); and the last **4 WEAK ACs** (5.1.6/5.3.2/5.4.6/5.7.3) are now PROVEN.
Visual evidence: `reports/block_art_render.png` (`tools/screenshot.gd`). The same run also landed
**save/persistence (AC-5.11.1/2/3/4)**: a pure `SaveCodec` (versioned + migration + sanitization) +
a `SaveManager` (atomic temp→rename, rolling backup, primary→backup→default recovery) + `Prestige`
to_state/from_state, wired into `mine.gd` (load on boot, autosave at the relic/dig boundary +
focus-out) — so prestige power-growth **survives an app restart** (a round-trip test caught + fixed a
real codec migration bug; boot-persistence mutation-verified). The **2026-06-15 03:30** run then closed
the slice's #1 *playability* gap — **portrait safe-area UI (AC-5.8.5)**, previously a debug-harness HUD
with **zero** safe-area handling (controls flush at the screen edge / in the home-indicator gesture zone;
tray could overflow the bar and push the throw button off-screen). New pure `UiLayout.safe_insets` (device
safe area → logical HUD insets + data-driven base margin) drives a responsive `hud.gd` (top/nav/bottom bars
inside the safe area, reflow on resize); interactive controls meet a data-driven touch target
(`ui_min_touch_target_px`); the tray scrolls (horizontal `ScrollContainer`) instead of overflowing; a
grounded bottom-bar background was added. Pure math is headless-tested vs notch/gesture-bar/desktop
profiles; the **real HUD** is driven through the same path with a synthetic notch profile (bars proven
inside the safe region); the validator rule + HUD positioning are mutation-verified. Visual:
`reports/hud_layout_0330.png`. Remaining gaps are **documented, not hidden** → `reports/spec-coverage.md`
(the AC→test matrix) + the handoff. Seams left for ROADMAP: real art/SFX assets/mix + the settings
(volume/motion/text-scale) UI + full text-scale reflow (AC-5.8.6/5.10.1); nav→overlay screens (AC-5.8.3);
web save (IndexedDB, AC-5.11.5). **`spec/QUALITY_PLAN.md` is RETIRED** (its v0.3 P0 items are
resolved or obsoleted by the v0.4 pivot — QP-004 portrait-UI now ADVANCED via AC-5.8.5, QP-005
visual-identity ADDRESSED, QP-006 audio ADDRESSED; superseded by VERTICAL_SLICE §0 + this audit).

## Project
Vertical mining game in **Godot 4.6.3** (typed GDScript). Portrait, physics-driven, built around
**economic optimization** with **no lose state** (a free unlimited weak charge is always available)
and **power growth** via prestige; **finite + completable** with a soft cap. **Portfolio/learning
project — no monetization.** All targets first-class (web, desktop, iOS, Android) @ 60 fps. This repo
is the **vertical slice** (the v0.4 core loop: optimize → relic ends the dig → minimal prestige).

## Quick reference
```bash
# Gates — BOTH must exit 0 for any change to be "done"
tools/validate_data.sh                          # data-integrity (DataValidator over /data JSON)
tools/run_tests.sh tests                        # full headless gdUnit4 suite
tools/run_tests.sh tests/unit/test_<name>.gd    # single suite (fast inner loop)

# Godot (4.6.3, on PATH as `godot`)
godot --path .                                  # open editor
godot --headless --path . --import              # rebuild class cache (after adding class_name scripts)
```
Reports land in `reports/`. CI runs both gates on push (`.github/workflows/ci.yml`).
**Never claim a change works without running the gate and seeing exit 0. Green ≠ correct — see
"Audit discipline" below.**

## Stack
- **Engine:** Godot 4.6.3 (`/opt/homebrew/bin/godot`).
- **Physics:** Rapier 2D (`addons/godot-rapier2d`), set as the project's 2D physics engine;
  precompiled for all targets incl. web. **Determinism is NOT required (v0.4)** — the charge runs on
  Rapier for convenience; GodotPhysics2D would also be acceptable. The aim preview is an
  **initial-arc hint (pre-first-bounce only)** and need not match flight; post-bounce uncertainty is
  intentional.
- **Tests:** gdUnit4 v6.1.3 (`addons/gdUnit4`), headless (needs `--ignoreHeadlessMode`, already in
  `run_tests.sh`).

## Architecture
- **Pure logic** → `scripts/core/` (no Node/scene/input deps → headless-testable, deterministic).
- **Systems/autoloads** → `scripts/systems/` (GameData, Economy, RunState, Prestige).
- **UI/scenes** → `scripts/ui/` + `scenes/` (thin; delegate to core/systems; **scenes authored in the
  editor, not built imperatively in `_ready()`**).
- **Tunables** → `data/*.json` (schema-validated; NEVER hardcoded).
- **Tests** → `tests/{unit,integration,golden}/`.
- **Specs** → `spec/SPEC.md`, `spec/AGENTS.md`, `spec/VERTICAL_SLICE.md`, `spec/ROADMAP.md`, `spec/AUDIT.md`.

## Hard conventions
- **Tunables are data, never code.** Balance lives in `data/*.json`, validated by the `DataValidator`
  CI gate (`scripts/core/data_validator.gd`); load-time schema validation is a ROADMAP hardening item.
  Add a rule there for every new table/join.
- **Canonical block-type registry** (`data/block_types.json`): block id is the join key; depth/loot
  tables reference blocks by id, never redefine values. **`max_hp` is an authored literal field per
  block — NOT derived from `hardness`**; the per-cell HP store is seeded from it once at chunk init
  (`block_grid.gd` ← `Registry.block_max_hp`). Depth + per-mine HP multipliers live in `/data` balance
  and scale base HP via `Registry.scaled_block_hp` (`HP = max_hp × depth_mult × mine_hardness_mult`).
  The `hardness` field is **NOT vestigial** — it is load-bearing as a data-integrity invariant:
  `data_validator._check_hardness_hp_monotonic` enforces that `max_hp` is monotonic non-decreasing in
  `hardness` across diggable blocks. It does not *derive* runtime HP (that stays the authored `max_hp`
  literal via `Registry.scaled_block_hp`), but deleting it would break the data gate + block-types schema.
- **Per-cell HP/damage lives in a per-chunk `PackedInt32Array`**, NOT in TileMap cells.
- **No lose state.** A throw is always possible via the **free unlimited charge** (a permanent tray
  slot, ∞, never decremented). The tray is never empty. A dig ends by **collecting the relic**
  (→ bank prestige), never by running out of charges.
- **Physics shapes are primitives for dynamic bodies** (charge/collectibles = circle/capsule);
  **terrain colliders are square tiles** on the TileMap physics layer.
- **Collision masks are explicit (v0.6):** charge ↔ terrain only (`collision_mask=1`; the platform
  is a VISUAL anchor, not a physics body — charges pass through it); collectibles ↔ terrain only;
  particles never collide. Launched charges use continuous CD (no tunneling).
- **Particles for cosmetics; pooled rigid bodies only for collectibles** (cap = active/awake bodies,
  per-target values in `/data`; settled bodies sleep). Explosions are GPUParticles2D, **never
  `ColorRect`/sheets**.
- **Determinism contract (v0.4):** generation = pure `f(mine_seed, cell)` via **FastNoiseLite**
  (coherent → ore veins); blast = pure against the pre-blast snapshot (no chain prop) with a **fuzzy
  factor drawn from an injected, seedable RNG** advanced in a fixed walk order. **Physics is NOT
  deterministic** and not relied upon. Golden tests pin **gen + blast (fixed seed) only** — and MUST
  FAIL on a missing golden (no self-write).
- **Controls:** drag adjusts launch **angle** (**forgiving** — not a precision skill); **throw
  button** commits; power = charge base impulse; **initial-arc preview** from a fixed muzzle (to first
  bounce only). Input authored once → mouse == single-touch.
- **Camera follows the platform target** via position smoothing (never raw explosion positions,
  **never hard-set per frame** in a way that fights smoothing); platform lowering is **tweened**.
- **Tests** extend `GdUnitTestSuite`; every test references the `AC-x.y.z` it covers in a comment.
  Don't rely on injected `InputEvent`s (they don't fire headless) — test input math via pure funcs.
- **Tools needing a `class_name` script should `preload` it** (class cache can be cold under `-s`).

## Audit discipline (green ≠ correct — the v0.3 review found all of these)
- Golden files MUST **fail on missing**, never self-write (self-heal launders drift).
- Structural claims must actually assert (no `assert grid is RefCounted` standing in for "HP not in
  TileMap" — mutate and read back from the array).
- Integration "smoke" tests must instantiate the **real scene**, not re-`new()` the wiring inline.
- A test that just calls a pure function twice and asserts equality proves nothing (not "parity",
  not "determinism"). Delete tautologies.
- `verify-slice` should emit `reports/spec-coverage.md` (AC → asserting test); a milestone-boundary
  **AC-faithfulness** review guards autonomous runs against vacuous green (ROADMAP §process).

## Web export (first-class — handle or web breaks)
Pin Compatibility renderer for web/mobile; particle materials must set `COLOR` (else GPUParticles2D
don't render under WebGL2); resume the Web Audio context on first user gesture; threaded builds need
COOP/COEP headers (else ship single-threaded); validate on iOS/macOS Safari (weakest browser).

## App lifecycle & persistence
Autosave at dig/prestige boundaries AND on focus-out (don't rely solely on
`NOTIFICATION_APPLICATION_PAUSED` — unreliable on mobile). Atomic save (temp → rename) + one rolling
backup; recover from backup, then clean default with a warning. Web `user://` is IndexedDB
(evictable, incognito-blocked, per-origin) — namespace it, warn, offer export/import.
(Save/persistence is a later slice unit; dig/prestige state is in-memory for now.)

## Art & audio (when those units land)
Source-first (track licenses in `ATTRIBUTIONS.md`; allow CC0/CC-BY/OFL; forbid CC-BY-NC and
untracked SA/GPL; attribution must reach the shipped build via an in-game Credits screen). Master
palette is an adopted colorblind-safe palette; **generated/recolored** art quantizes to it, **sourced
packs are exempt**. Block-type identity rides a shape/glyph overlay layer (no color alone). Damage =
one shared crack-overlay on a second TileMapLayer. Explosions = particle textures + gradient ramps,
not sheets. Audio buses: Master → {SFX, Music}; placeholder SFX from the first slice; unlock audio on
first web gesture.

## Testing & validation
gdUnit4 headless via `tools/run_tests.sh`; data gate via `tools/validate_data.sh`. Cover pure-logic
systems (gen distribution + coherence + determinism, fuzzy-blast math with a fixed seed, economy
crediting, loot sampling, dig loop, relic-ends-dig, minimal prestige power-growth). Golden files in
`tests/golden/` pin gen + blast determinism (fail-on-missing). Both gates run in CI on every push.

## Definition of done
1. Matches the relevant `AC-x.y.z` in `spec/SPEC.md` (cite the ids in tests).
2. Tunables in `/data` as schema-validated JSON; data gate passes.
3. Works on mouse and single-touch (parity is structural — shared code path).
4. Both gates exit 0; no new errors/orphans; 60 fps on target incl. web (for runtime features).
5. Tests prove the actual acceptance behavior, not just helper functions (see Audit discipline).

## Build progress (vertical slice)
**State (2026-06-18, v0.6):** slice **COMPLETE + green** — **583 tests, both gates exit 0**
(DATA OK 15 tables, 0 orphans). v0.6 layered onto the v0.5 arcade pass:
- **Infinite mine generation:** the dig is no longer a bounded volume — gen windows around the
  platform and streams new chunks as you descend (still pure `f(mine_seed, cell)` via FastNoiseLite;
  golden gen/blast determinism preserved).
- **Logging / debug:** a boot logger (`user://mining_game.log`, DEBUG threshold) + an in-HUD debug
  overlay for live state inspection.
- **Camera / art feel:** higher `camera_zoom` + tuned `camera_lookahead_cells`; per-cell dirt tile
  variation; **dotted aim guides** (animated aim line + reticle, initial-arc hint only).
- **Fixed elevator:** continuous hold-to-glide descent (tap = one row; hold = ramped row-by-row,
  polled in `_process` via `_process_elevator_hold`), elevator-side setting honored.
- **Sticky-bomb fix + throw cooldown button:** the throw cooldown is a **pure time-driven timer**
  (`ThrowControls.start_cooldown`/`advance_cooldown`) armed on release, fully independent of the
  blast/explosion — drains every frame, re-enables the button on the expiry edge. Proven by a pure
  unit test (`test_aim.test_cooldown_is_pure_time_timer_independent_of_explosion`) + an integration
  test (`test_level_smoke.test_cooldown_visual_drains_to_completion_independent_of_detonation`, which
  watches for ANY detonation while the timer drains and asserts none fired).
- **Deep Mine + money upgrades; misc physics/render/UX fixes.**
- **Architecture decouple (this run):** centralized post-state re-render via `_refresh_after_state_change()`
  (= `_refresh_all_ui()` + `_update_preview()`, 5 call sites); a **dirty-checked `_update_light_mask()`**
  (caches `_last_light_uv`, skips the shader-param write when the platform/camera is settled);
  the per-frame `_process` cooldown path now re-runs the full HUD refresh **only on the ready edge**
  (no redundant per-frame double-write). Orphan cleanup: `shaft_guide.gd` (superseded by
  `ShaftSupports`) is gone — **0 orphan scripts/scenes** confirmed by a full ref sweep.

### v0.4 salvage pass (historical — 329 tests, audited 2026-06-15 08:30)
The `spec/VERTICAL_SLICE.md` §0 KEEP / REWORK / DELETE map is done:
- **KEEP ✅:** `aim.gd`, `blast.gd` (now fuzzy + seeded), `block_grid.gd` HP store, `registry.gd`,
  `economy.gd`, the pure-logic suites + fail-on-missing goldens — all in place.
- **REWORK ✅:** `block_gen.gd` → FastNoiseLite veins (done); `charge.gd`/`throw_params.gd` →
  initial-arc-only preview in core, no determinism, `floori` fixed (done); `run_state.gd` →
  relic-ends-dig + free unlimited charge + run-scoped pack RNG + idempotent `end_dig` (done);
  `data/*.json` → free charge + efficiency + depth/mine HP mults + relics; **price-0 starter pack
  REMOVED 2026-06-14**; `data_validator.gd` → falloff==radius, fuse-present, free-charge-solvable,
  full explosive shape / efficiency-ordering / worst-case-fuzz no-stall, **+ AC-5.5.2 depth-reward
  monotonicity (EV + gem prob rise across bands; added 17:30)**.
- **DELETE/REBUILD ✅:** determinism + tray-exhaustion tests gone; no self-healing goldens; the
  `is RefCounted` tautology replaced by a real per-cell-HP read-back; the v0.3 god-object is now a
  thin `mine.gd` controller over an **authored** `mine.tscn` (smoke test boots it); **dead
  `Economy.draw_loot` + its 3 vacuous loot tests REMOVED (17:30)**.
- **AUDIO ✅ (17:30, AC-5.13.x):** `default_bus_layout.tres` (Master→{SFX,Music}) + `Audio` autoload
  (procedural placeholder SFX for the 7 core events, per-bus volume routing, first-gesture web unlock)
  wired into `mine.gd`. Tests in `test_audio.gd` + a live-wiring assert in the smoke test.
- **NON-COLOR IDENTITY ✅ (22:30, AC-5.10.2/5.10.3):** pure `block_art.gd` generates per-type **colour**
  (`palette.json`, colorblind-safe, luminance-contrast **gate-enforced**) + a shared **glyph overlay**
  (authored `GlyphLayer`, dots/cross/bricks/circle/diamond) + crack art, swapped onto the authored
  atlases (physics preserved — verified). Tray **tier glyph** added. `data_validator` palette/glyph/
  luminance rules (mutation-verified). `test_block_art.gd` (11) + smoke glyph/physics + data-integrity
  negatives. Magenta placeholder **platform** fixed → steel bar (caught by a live screenshot). Last **4
  WEAK ACs (5.1.6/5.3.2/5.4.6/5.7.3) → PROVEN**. Evidence: `reports/block_art_render.png`.
- **SAVE/PERSISTENCE ✅ (22:30, AC-5.11.1/2/3/4):** pure `save_codec.gd` (versioned envelope + v0→v1
  migration + sanitization) + `save_manager.gd` (atomic temp→rename, one rolling backup,
  primary→backup→clean-default recovery) + `Prestige.to_state/from_state`, wired into `mine.gd`
  (load on boot, autosave at the relic/dig boundary + focus-out). Prestige power-growth **survives an
  app restart**. `test_save_codec.gd` (9) + `test_save.gd` (7) + a boot-persistence smoke test
  (mutation-verified); a round-trip test caught + fixed a real codec bug. **AC-5.11.5 (web IndexedDB +
  export/import) stays ROADMAP.**
- **PORTRAIT SAFE-AREA UI ✅ (03:30, AC-5.8.5):** pure `ui_layout.gd` (`safe_insets`: device safe area →
  logical HUD insets w/ a data-driven base-margin floor; `meets_touch_target`; `bottom_strip_span`) drives
  a responsive `hud.gd` (`apply_layout` reads DisplayServer; `apply_layout_with` is the headless test seam)
  that positions the top/nav/bottom bars inside the safe area + reflows on `size_changed`. Interactive
  controls sized to `ui_min_touch_target_px`; the tray reparented into a horizontal `ScrollContainer`
  (scrolls, never shrinks/overflows the bar); a grounded `BottomBg` panel added. `data/balance.json`
  +`ui_min_touch_target_px`/`ui_edge_margin_px`; `data_validator._check_ui` (mutation-verified). Tests:
  `test_ui_layout.gd` (8, notch/gesture/desktop profiles) + smoke `test_hud_lays_controls_inside_device_safe_area`
  / `_reflows_when_viewport_shrinks` / `test_interactive_controls_meet_touch_target` /
  `test_tray_scrolls_instead_of_overflowing_bottom_bar` (drives the REAL hud w/ a synthetic notch; HUD
  positioning mutation-verified) + 3 data-gate negatives. Visual: `reports/hud_layout_0330.png`.
- **NAV→SETTINGS OVERLAY + ACCESSIBILITY SETTINGS ✅ (08:30, AC-5.8.3/5.10.1/5.8.6):** pure
  `settings_state.gd` (4 settings: SFX/Music volume, motion intensity, UI text scale; data-seeded
  defaults from `balance.settings`, clamping, linear→dB, save round-trip) + `scenes/overlay.tscn`
  (CanvasLayer, `process_mode=ALWAYS`) + `settings_overlay.gd` (`open()` pauses the tree, `close()`
  restores; sliders mutate the shared `SettingsState`). Wired into `mine.gd`: `Hud.nav_pressed` →
  `overlay.open`; `_apply_settings` routes volumes → `Audio` + text scale → `Hud.set_text_scale`
  (scales fonts + abbreviates money for AC-5.8.6) + motion → `explosion_particle_count` (reduced-motion
  spray floor); settings persist (save **v2** + `_save_progress`). `data_validator._check_settings`
  (defaults in range; text-scale band coherent — mutation-verified). `test_settings_state.gd` (8) +
  `test_save_codec.gd` (+5 settings/v2-migration) + `test_data_integrity.gd` (+4 settings negatives) +
  `test_level_smoke.gd` (+8: nav-pause, state-preserve, sfx/music routing, persist, motion, money
  abbrev, fit-at-max-scale). 5 mutation spot-checks. Visual: `reports/settings_overlay_0830.png`.
- **Remaining (next runs, all documented in `reports/spec-coverage.md`):** real art/SFX assets
  (placeholders ship); the **Hub/Shop/Upgrades** overlay tabs + mine-select/buy-access (AC-5.8.3 other
  tabs / AC-5.12.3/4); the Credits screen (AC-5.8.7); OS reduced-motion seeding + reveal-a11y
  (AC-5.10.4); web save (AC-5.11.5); an icon-only HUD compact mode for extreme text scale on the
  narrowest phone. **0 WEAK ACs remain.**

Build/repair via `.claude/workflows/`: `build-unit` (`args:"U3"`), `build-slice` (U1→U10, resumable),
`verify-slice` (read-only gates + golden + AC coverage). Build units **sequentially** in dependency
order (shared tree — no parallel unit builds, no worktree isolation).

## Autoloads
- `GameData` → `scripts/systems/game_data.gd` (loads `/data` JSON)
- `Audio` → `scripts/systems/audio.gd` (SFX bus + placeholder cues; `default_bus_layout.tres`)

## Do NOT
- Hardcode balance, or store tunables as anything but schema-validated JSON.
- Add a lose/fail state, or decrement the free unlimited charge (the game cannot be lost).
- Rely on cross-platform physics determinism or a bounce-accurate "preview == actual" arc (dropped in
  v0.4; the preview is an initial-arc hint only).
- Store per-cell HP in TileMap cells / `TileSet` custom data.
- Add monetization, ads, energy, accounts, or idle/AFK grind (finite, completable game).
- Build landscape or 3D layouts; implement marching squares / smooth terrain (squares only).
- Ship a self-healing golden, a tautology test, or a "smoke" test that doesn't boot the real scene.
- Install new deps without clear justification.
- Expand scope from an ambiguous spec line — flag the ambiguity and ask instead.
- Commit or push unless the user asks.
