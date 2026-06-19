# Mining Game — Vertical Slice

Portrait, physics-driven mining game (Godot 4.6.x). This repo is the **MVP vertical slice**
(SPEC §6 steps 1–3: destructible block core + finite run + money), built to a **machine-verifiable
contract** so AI workflows can construct it reliably.

- **Design:** `spec/SPEC.md` (**v0.6**) — *what* + acceptance criteria (`AC-x.y.z`).
- **Engine conventions:** `spec/AGENTS.md` / `CLAUDE.md` — *how* (v0.6).
- **MVP build contract:** `spec/VERTICAL_SLICE.md` — the slice decomposed into 10 verifiable units;
  its **§0 is the v0.3→v0.4 salvage map** (the authoritative to-do).
- **AC→test coverage:** `reports/spec-coverage.md` — the traceability matrix (read this first).
- **Audit history:** `spec/AUDIT.md` (design audit) · `spec/QUALITY_PLAN.md` (**retired** v0.3 plan).

## Stack

| Piece | Choice | Notes |
|---|---|---|
| Engine | Godot 4.6.3 | `godot` on PATH (`/opt/homebrew/bin/godot`) |
| Physics | Rapier 2D (**non-deterministic**, v0.4) | `addons/godot-rapier2d`, precompiled for macOS/iOS/web/etc. Determinism is NOT relied upon; the aim preview is an initial-arc hint only. |
| Tests | gdUnit4 v6.1.3 | `addons/gdUnit4`, headless |
| Tunables | JSON in `/data` | schema-validated by `DataValidator` |

## The two gates (a feature is "done" only when both exit 0)

```bash
tools/validate_data.sh          # data integrity (cross-refs, ranges, free-charge solvability, …)
tools/run_tests.sh tests        # full headless gdUnit4 suite
tools/run_tests.sh tests/unit/test_block_gen.gd   # one suite (fast loop)
```

Reports land in `reports/`. CI runs both on every push (`.github/workflows/ci.yml`).

Current state (2026-06-19): **v0.6 slice + best-practices audit pass.** The full core loop is real
(FastNoiseLite gen → fuzzy seeded blast → ore→money → relic ends the dig → minimal prestige makes
the next dig stronger), wired through a thin `mine.gd` controller over an authored `mine.tscn`.
A 4-subagent read-only audit + vetting pass landed fixes across correctness, performance, tests,
conventions, and docs — see the commit history for details. The v0.5 bounded-mine + physical-platform
design was reconciled to the v0.6 shipped code (infinite shaft + visual platform) in SPEC/AGENTS.
Pre-existing v0.6 golden-gen drift (`test_block_gen`) is noted, not hidden. Remaining gaps are
documented in `reports/spec-coverage.md`: ROADMAP seams — real art/SFX assets, the Hub/Shop/Upgrades
overlay tabs + mine-select/buy-access (AC-5.12.3/4), and OS reduced-motion seeding (AC-5.10.4). A
Credits panel (AC-5.8.7) and manual save export/import (the export/import half of AC-5.11.5) now
live in the Settings overlay; full web IndexedDB persistence remains ROADMAP.

> **Historical (v0.4 slice, 2026-06-15):** independently audited, 329 tests, both gates green. A
> 21-agent adversarial AC-faithfulness audit took the slice from 33→40 PROVEN ACs. The 22:30 run
> landed non-color block identity (AC-5.10.2/5.10.3): a pure `block_art.gd` generates per-type
> **colour** (data-driven colorblind-safe `palette.json`, luminance-contrast gate-enforced) + a
> shared **glyph overlay** +
crack art, plus a tray **tier glyph**; a live screenshot caught + fixed a magenta placeholder
**platform**; and the last **4 WEAK ACs are now PROVEN** (0 WEAK remain). Visual evidence:
`reports/block_art_render.png` (`tools/screenshot.gd`). The same run also landed **save/persistence
(AC-5.11.1/2/3/4)** — a pure `SaveCodec` (versioned + migrating) + a `SaveManager` (atomic write,
rolling backup, recovery chain), wired so prestige power-growth survives an app restart (a round-trip
test caught + fixed a real migration bug). The **03:30 run closed the slice's #1 playability gap —
portrait safe-area UI (AC-5.8.5)**: the HUD was a debug harness with **zero** safe-area handling (controls
flush at the screen edge / in the home-indicator gesture zone; the tray could overflow and push the throw
button off-screen). A pure `ui_layout.gd` now maps the device safe area to logical HUD insets (data-driven
base margin) so the responsive `hud.gd` keeps the bars inside the safe area; interactive controls meet a
data-driven touch target; the tray scrolls (horizontal `ScrollContainer`) instead of overflowing; a grounded
bottom-bar background was added. Pure math is headless-tested vs notch/gesture-bar/desktop profiles and the
real HUD is driven through the same path with a synthetic notch profile. Visual: `reports/hud_layout_0330.png`.
The **08:30 run landed the nav → modal Settings overlay (AC-5.8.3) + the accessibility settings
(AC-5.10.1)**: the nav button (≡) was previously dead, with no settings UI at all. Opening the overlay now
pauses the Mine and preserves all dig state; the Settings panel ships SFX/Music volume (→ the audio buses),
motion intensity (→ explosion spray; reduced-motion floor), and UI text scale (→ HUD font + money
abbreviation, closing **AC-5.8.6**), all data-seeded and **persisted** via the save codec (bumped to v2 with
a `settings` block). Pure logic is headless-tested; the real overlay is driven through `mine.tscn`; five
mutation spot-checks confirm the new behaviors have teeth. Visual: `reports/settings_overlay_0830.png`.
Remaining gaps are **documented, not hidden** in `reports/spec-coverage.md`: ROADMAP seams — real art/SFX
assets, the Hub/Shop/Upgrades overlay tabs + mine-select/buy-access (AC-5.12.3/4), the Credits screen
(AC-5.8.7), OS reduced-motion seeding (AC-5.10.4), and web save (IndexedDB, AC-5.11.5).

## Building the slice with workflows

Three saved workflows in `.claude/workflows/` (invoke via the Workflow tool / ultracode):

- **`build-unit`** — build/repair ONE unit. `args: "U2"` (or `{unit:"U2"}`). Implements the unit +
  its tests, runs the gates, and runs a bounded fix loop with an independent verifier.
- **`build-slice`** — build/repair U1→U10 in dependency order, gating each; skips only units whose
  behavior and tests prove the acceptance criteria; finishes with a full-suite confidence pass.
- **`verify-slice`** — read-only clean-room check: both gates + golden determinism + an AC→test
  coverage audit.

Each unit's "done" requires both exit-0 gates and acceptance-criteria coverage. Green tests alone
are not enough when the tests are weak.

### Recommended permissions for long autonomous runs (opt-in)

So workflow agents don't stall on prompts, allow the gate commands. Add via the `/permissions`
panel in an interactive `claude` session, or to `.claude/settings.json`:

```json
{ "permissions": { "allow": [
  "Bash(godot:*)",
  "Bash(tools/run_tests.sh:*)",
  "Bash(tools/validate_data.sh:*)",
  "Bash(bash tools/run_tests.sh:*)",
  "Bash(bash tools/validate_data.sh:*)"
] } }
```

## Manual dev

```bash
godot --path .                 # open the editor on this project
godot --headless --path . --import   # (re)build class cache + GDExtensions
```

## Layout

```
project.godot         portrait, Rapier physics, GameData autoload
/scenes               main.tscn (slice scaffold) + per-unit scenes
/scripts/core         pure, headless-testable logic (validator, gen, blast, aim, …)
/scripts/systems      autoloads/managers (game_data, economy, run_state, …)
/scripts/ui           thin input/HUD nodes
/data                 JSON tunables (+ DataValidator rules)
/tests/{unit,integration,golden}   gdUnit4 suites + pinned golden files
/tools                run_tests.sh, validate_data.sh, validate_data.gd
/addons               godot-rapier2d, gdUnit4
/spec                 SPEC, AGENTS, VERTICAL_SLICE, AUDIT
/.claude/workflows    build-unit, build-slice, verify-slice
```
