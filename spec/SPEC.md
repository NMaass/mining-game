# SPEC.md — Untitled Vertical Mining Game

**Status:** v0.6.0 (reconciled to code: infinite shaft + visual platform; 2026-06-19). v0.5.0
introduced bounded mines + prestige offer UI + depth resource-odds HUD (2026-06-15); v0.6.0
reverts mine geometry to an infinite shaft and makes the platform a visual anchor, matching
the shipped code. See the v0.5→v0.6 changelog below.
**Source of truth.** Code is the build output of this document. When code and spec
disagree, the spec wins or the spec gets updated — never silent drift.

This file defines WHAT to build and the acceptance criteria that verify it.
Operational details (engine version, project layout, conventions, how to run/test)
live in `AGENTS.md` / `CLAUDE.md`. The MVP build contract is `VERTICAL_SLICE.md`; the
post-slice plan + gap register is `ROADMAP.md`.

> **Changelog v0.3 → v0.4** (this revision is a *design pivot*, not a polish pass; several
> v0.3 decisions are reversed — the prior code was built against v0.3 and needs a salvage pass,
> see `VERTICAL_SLICE.md` §0):
> - **Core fun = economic optimization.** Earning ore to buy *efficient* charges and reaching the
>   relic with less waste is the game. Aiming is *not* the skill.
> - **No losing runs.** A **free, unlimited, weak/inefficient charge** is always available. The
>   v0.3 "out-of-charges → run-end" model is **removed**. **REMOVED: AC-5.3.5** (empty-tray run-end).
> - **Run-end = collecting the mine's relic** → prestige screen → bank power → stronger next dig.
>   The **final mine's relic ends the game** (authored ending). **Finite with a soft cap** — you
>   may keep playing/optimizing after the ending.
> - **Hook = power growth** (prestige makes each dig stronger). Finite-and-completable is retained;
>   power growth is the *texture*, the ending is still real (soft cap).
> - **Multiple, player-selected mines.** You **buy access** to deeper mines; deeper rock is **harder**
>   so your explosives are **less effective** there — the economic squeeze that drives buying better
>   charges.
> - **Aiming is forgiving.** The predicted arc shows **only the initial throw, up to the first
>   bounce**; after the first bounce the path is **intentionally unknown** ("part of the fun is you
>   don't know after the first bounce"). **REMOVED: AC-5.3.4** (preview == actual flight).
> - **No cross-platform physics determinism.** The "deterministic physics backend / bounce-accurate
>   preview" requirement is **dropped**. Rapier is retained as the engine for convenience, but the
>   enhanced-determinism contract and physics golden tests are removed.
> - **Blast radius is fuzzy/random**, scaled from where the charge actually is at detonation. The
>   randomness is drawn from an **injected seed** so the blast *logic* stays unit-testable.
> - **Procedural gen uses FastNoiseLite** (re-affirmed from v0.3 and now enforced — the v0.3 code
>   shipped a custom hash and must be replaced) so ore forms **veins/clusters** to optimize toward.
> - Pure-logic determinism (gen + blast, given a fixed seed) is **retained** and golden-tested; only
>   *physics* determinism is dropped.
> - Resolved former §8 open items: physics module (**Rapier, non-deterministic**), noise
>   (**FastNoiseLite**), run model (**no-loss, relic-ends-run**).
>
> **Changelog v0.4 → v0.4.1** (2026-06-14 17:30 unattended quality run; small corrections, no pivot):
> - **AC-5.5.2 loot reward restated** to a precise, gate-enforced contract. The old wording required
>   the loot **floor (minimum value)** to rise with depth; the shipped (sound) data keeps common
>   value-0 filler rock at every depth, so that literal clause was false and its only test exercised a
>   dead sampler (`Economy.draw_loot`, no production callers). Replaced with **expected value per cell
>   strictly rises AND rare-gem probability strictly rises** — both already true in `depth_bands.json`
>   (EV 1.70→5.00, gem 2%→10%) and now a hard data-gate invariant across adjacent bands. Rationale:
>   filler rock at all depths is good mining-game design; the reward signal is EV + gem chance, not a
>   per-cell minimum. Dead `draw_loot` removed.
> - **Audio (AC-5.13.x) pulled into the slice**, resolving the SPEC↔VERTICAL_SLICE contradiction in
>   favour of the spec (SPEC §6 step-1 + AC-5.13.1 + CLAUDE.md both said placeholder SFX ship from the
>   first slice; VERTICAL_SLICE §1 had wrongly deferred it to ROADMAP U24). A minimal `Master→{SFX,
>   Music}` bus layout + an `Audio` autoload with procedurally-synthesised placeholder SFX for the
>   seven core events + first-gesture web unlock now ship in the slice (full SFX design/mix stays in
>   ROADMAP).
>
> **Changelog v0.4.1 → v0.4.2** (2026-06-15 look/feel correction; no mechanics pivot):
> - **Motherload named as the primary feel reference.** The game should read as a chunky,
>   desktop-legible, arcade mining cross-section with compact instrument-style HUD and clear
>   dirt/ore material identity. It is a taste anchor, not a clone target.
> - **Launcher/platform guardrail added.** The platform may be physical and may launch charges, but
>   it must not behave like a solid lid that traps a default downward throw above the mine.
>
> **Changelog v0.4.2 → v0.5.0** (2026-06-15 design pivot: Dome Keeper structure + Digseum/Scritchy
> Scratchy prestige clarity):
> - **Mines are bounded rectangular volumes**, not an infinite vertical shaft. Each mine is an
>   authored archetype with fixed `width` and `depth` in cells; generation fills the whole volume
>   at dig start and the platform descends through a defined bottom where the relic waits.
> - **Prestige is offered, not automatic.** Breaking the relic block pauses the dig and offers the
>   player "Prestige Now" or "Keep Digging". Accepting banks exactly **1 prestige point** and ends
>   the dig; declining lets the player keep clearing the current mine.
> - **Money is per-dig only and does not affect prestige.** Prestige is the cross-dig currency and
>   comes only from relics (one point each).
> - **HUD shows resource odds at the current depth.** A compact readout displays the current depth
>   band's block probabilities so the player can see the mine getting progressively more lucrative.
> - **No passive income.** There is no museum-style offline earnings or idle generation.

---

## 1. Vision & outcomes

A portrait, mobile-first, physics-driven mining game built around **economic optimization** inside
**an infinite-depth shaft**. The mine is a fixed-width, unbounded-depth column under the platform,
generated on demand as the platform descends. You drop explosives down the shaft to blast ore loose for money, spend that money on
**more efficient charges**, and reach the mine's **relic** to earn **prestige**. You can never get
stuck and you can never lose: a **free, unlimited, weak charge** is always in the tray — it just
digs slowly and inefficiently, so the optimization pressure is "do better," never "game over."

Breaking a mine's relic block **offers prestige**: the player can **accept** (bank **1 prestige
point** and end the dig) or **keep digging** deeper into the shaft. Prestige makes the
next dig **stronger** (the hook is power growth). You **buy access** to progressively **harder**
mines, where your current charges are less effective until you re-optimize. Taking the **final
mine's relic** is the authored ending — the game is **finite and completable**, with a **soft cap**
(you may keep optimizing afterward).

Money is **per-dig only** and does **not** convert to prestige: the cross-dig currency is prestige
points from relics only. The HUD shows the **resource odds at the current depth** so the player can
see the mine getting progressively more lucrative as they descend.

This is a **portfolio / learning project**. It is not sold; there is no monetization. That intent is
recorded because it relaxes store-revenue pressure while still requiring honest store-compliance and
asset-licensing hygiene for the public builds.

**Primary feel reference:** **Motherload**. The target read is a vertical arcade-mining cross-section:
chunky dirt and ore blocks, a compact instrument-like HUD, and a mine that feels large enough to
inspect and plan around on fullscreen desktop. Dome Keeper / Diggin remain useful adjacent references
for block-based terrain and modern polish, but Motherload is the north-star flavor. This is an
inspiration, not a clone brief: controls, economy, relics, prestige, finite ending, and asset identity
remain this game's own.

**Success looks like:**
- A dig has a clear optimization arc: the free charge always works, but buying efficient charges
  visibly improves your ore-per-throw and time-to-relic.
- Reaching a relic feels like a payoff that *converts* into permanent power for the next dig.
- Harder mines re-open the optimization problem (your old charges underperform → buy better).
- The first screen reads as a mine, not a small centered test grid: block materials, shaft scale,
  launcher silhouette, and HUD density all support the Motherload-adjacent mining fantasy.
- The full game is completable in a bounded number of hours with an authored ending.
- The same build runs on web, desktop, and mobile from one project, all at the performance target.

---

## 2. Scope boundaries (read this before adding anything)

**In scope:**
- A hub of multiple **authored** mines; the player picks which to dig and **buys access** to deeper,
  harder ones.
- An **infinite-depth mine** per dig (fixed width in cells, unbounded depth), generated on demand
  via a sliding chunk window, with destructible square-block terrain. (v0.5 proposed a bounded
  rectangular volume; v0.6 reverted to the infinite shaft that shipped.)
- Drag-to-aim (angle) + throw-button physics; a **forgiving** aim with an **initial-arc** preview
  (pre-first-bounce only).
- A **free unlimited weak charge** always available; finite **efficient** charges bought from packs
  (gacha), tray-based selection.
- Money economy with depth-scaled loot (money is per-dig); **economic optimization is the core loop**.
- Relics: each mine's relic is the **objective**; breaking its block **offers** prestige (accept to
  bank +1 point and end the dig, or decline to keep digging).
- Prestige → a power-growth upgrade tree; **exactly 1 prestige point per relic**.
- A HUD element showing the **resource odds at the current depth**.
- Authored ending triggered by taking the final mine's relic; soft cap (play continues after).
- Screens: Mine, Hub/Mine-select, Shop, Upgrades/Prestige, Settings.

**Explicitly NOT in scope (do not build without a spec change):**
- A lose state / fail condition. There is none by design.
- Cross-platform deterministic physics or a bounce-accurate "preview == actual" arc.
- Real-money microtransactions, ads, energy systems, accounts.
- Infinite idle/AFK grind with no ending. The game is finite (soft cap after the ending).
- Multiplayer, cloud sync (local save only for v1).
- Hand-drawn frame-by-frame explosion sprite sheets (explosions are particles).
- 3D, isometric, or landscape-primary layouts.
- Narrative beyond the relic-reveal beat(s) and the authored ending.
- Smooth/contoured/marching-squares terrain. Terrain is large discrete square blocks.

---

## 3. Constraints

- **Platform:** Godot 4.x, single project exporting to HTML5 (web), desktop (Win/macOS/Linux), iOS,
  Android. **All targets are first-class** and must hit the performance target.
- **Primary orientation:** portrait. Landscape is not a target for v1.
- **Controls:** aiming is **drag-to-adjust-angle + a dedicated throw button**, and it is
  **forgiving** — precision is not the skill. The drag may happen anywhere on the play area; the
  predicted arc originates from a fixed platform muzzle. Launch power is the active charge's own
  data-defined base impulse. Every interaction MUST work identically with mouse and single-touch via
  a **single shared code path**; no interaction may require multi-touch, hover, or precise timing.
- **Aim preview:** the predicted arc shows **only the initial throw up to the first bounce**. After
  the first bounce the trajectory is **intentionally not predicted** — the uncertainty is part of the
  fun. The preview is a *hint*, not a guarantee, and need not match actual flight.
- **Physics:** the charge is a Rapier `RigidBody2D`. **Cross-platform determinism is NOT required**
  and not relied upon. (Rapier is retained for convenience; GodotPhysics2D would also be acceptable.)
- **Blast:** blast intensity/radius is **fuzzy** — scaled from the charge's actual position at
  detonation with a randomized component. The randomness MUST be drawn from an **injected, seedable
  RNG** so blast resolution is unit-testable and golden-pinnable with a fixed seed.
- **Procedural gen:** **FastNoiseLite**, thresholded and depth-banded, as a pure function of
  (mine seed, absolute cell) — coherent noise so ore forms veins/clusters. Gen is golden-tested.
- **Performance target:** 60 fps on a mid-range phone, in a browser tab, and on desktop. Hard ceiling
  on simultaneous **active** rigid bodies (exact cap in `/data`); settled collectibles sleep;
  cosmetic effects use particles, not bodies.
- **Web export reality (must be handled, since web is first-class):** pin the Compatibility renderer
  for web/mobile; particle materials MUST set `COLOR` so GPUParticles2D render under WebGL2; resume
  the Web Audio context on first user gesture; if threaded, the host MUST serve COOP/COEP headers
  (else ship single-threaded). iOS/macOS Safari is the weakest browser and is validated explicitly.
- **Accessibility:** colorblind-safe master palette; no information conveyed by color alone; motion
  intensity slider; scalable UI text. (See §5.10.)

---

## 4. Prior decisions (locked, with rationale)

| Decision | Choice | Why |
|---|---|---|
| Project intent | Portfolio / learning piece, no monetization | Relaxes revenue pressure; keeps licensing/compliance honest for public builds |
| Engine | Godot 4.x | Nearest comp (Dome Keeper) is Godot; clean for AI codegen; one-project multi-export |
| Export targets | Web, desktop, mobile all first-class @ 60 fps | Learning goal includes shipping everywhere; forces the cross-platform work up front |
| Primary feel reference | **Motherload** | Keeps the vertical slice anchored to chunky arcade mining, compact HUD, and readable dirt/ore material identity |
| **Core fun** | **Economic optimization** (ore-per-charge efficiency → buy better charges → reach the relic faster) | This is the game; everything else serves it |
| **Hook** | **Power growth** — prestige makes each dig stronger | Finite-with-soft-cap; the across-run progression that pulls you forward |
| **Loss model** | **None.** A free, unlimited, weak charge is always available | No "game over"; the pressure is "optimize," never "fail." Removes the stall/solvency risk entirely |
| **Run boundary** | Breaking a mine's **relic** block **offers** prestige (accept → bank +1 point, end dig; decline → keep digging); **final mine's relic = ending** | The relic is the objective; prestige is the cross-dig reward; finite with a soft cap |
| **Mines** | Multiple **authored** mines; player picks one; **buy access** to deeper mines; deeper rock is **harder** (explosives less effective) | The optimization problem re-opens each tier; progression through content |
| Physics backend | **Rapier 2D, non-deterministic** (determinism dropped) | We no longer need cross-platform determinism; keep Rapier for convenience |
| **Aim preview** | **Initial-arc only** (up to first bounce); not bounce-accurate, not preview==actual | Forgiving aim; the post-bounce uncertainty is intentional fun |
| Controls | Drag adjusts launch **angle**; **throw button** commits; power = charge base impulse; forgiving | Readable, low-friction aiming; the decisions are *which charge where*, not pixel-precision |
| **Blast** | **Fuzzy/random radius** scaled from detonation position; randomness via an **injected seed** | Adds variance/feel; injected seed keeps it testable |
| Mine geometry | Infinite-depth shaft per dig (fixed width, unbounded depth in cells), chunked in memory via a sliding window | Fits portrait; depth is the difficulty axis; resident cell count stays bounded |
| Win condition | Final mine's relic → authored ending (soft cap) | Finite + completable; you may keep optimizing after |
| Destructible terrain | Block-based (TileMapLayer); each cell is a typed square block, removed on detonation | Motherload-adjacent chunky mine read; Dome Keeper / Diggin support the block-based modern-polish reference; per-tile collision free; no marching-squares risk |
| Block damage | Blocks have HP; a blast deals damage; per-cell HP/damage in a parallel per-chunk array; a shared cracked-overlay layer shows stages; block breaks at 0 HP | TileMap cells can't store mutable per-cell HP; state lives beside the map |
| **HP scaling** | Block HP scales with **depth** and **per-mine hardness** (data-driven multipliers) | Makes deeper/later mines harder so old charges underperform — drives re-optimization |
| Procedural gen | **FastNoiseLite**, thresholded, depth-banded; pure fn of (mine seed, absolute cell) | Coherent noise → ore **veins** to optimize toward; deterministic regeneration |
| **Free charge** | A free, unlimited, intentionally weak/inefficient charge occupies a permanent tray slot | Guarantees you can always progress; the baseline the economy improves on |
| Explosive properties | Body fields (mass, bounce, friction, base impulse) + scripted stickiness + blast map + **efficiency/cost** | Paid charges are *more efficient* than the free one — the thing money buys |
| Ore retrieval | Auto-credit on block destruction (v0: no pickup). Debris bodies are cosmetic | Fits the top-drop fantasy; keeps the loop lean |
| Relics | The mine's objective; awarded the instant its block breaks; **exempt from the collectible pool**; ends the dig | The objective item must never be lost to pool recycling; collecting it banks prestige |
| Explosion visuals | GPUParticles2D (COLOR-set for web) + small cosmetic debris | Screen-filling look is cheap particles; only collectibles are physics bodies |
| Descent/camera | Platform anchor; platform lowering tweened smoothly; camera position-smoothing **tracks the platform** | Diegetic; avoids lurch at descent steps |
| Screen navigation | Mine stays instanced and **paused**; Hub/Shop/Upgrades/Settings are modal overlays | Run state (terrain, in-flight, collectibles) is never lost or rebuilt |
| HUD | Minimal: money + depth top-left, nav button top-right, charge tray + throw button bottom, compact relic-progress | Keeps the play space breathing |
| Save | Godot Resource serialization + `save_version` + migration + atomic write/backup | Local, simple; survives updates and interrupted writes |
| Tunables | JSON in `/data`, validated by the `DataValidator` CI gate (load-time validation is ROADMAP) | Diff-friendly balancing; never hardcoded |
| Master palette | Adopt an existing proven colorblind-safe palette, locked before bulk art | Unblocks the art pipeline |
| Motion default | Calm by default; intensity slider (seeded from OS reduced-motion where detectable) | Minimal aesthetic + accessibility |

---

## 5. Systems & acceptance criteria

Acceptance criteria use EARS phrasing with stable IDs. IDs removed in v0.4 are listed as **REMOVED**
so traceability tooling doesn't silently lose them; new IDs continue the numbering.

### 5.1 Mine: infinite-depth shaft (v0.6: reconciled to code)
- **AC-5.1.1** The system SHALL represent each mine as a grid of square blocks (TileMapLayer) with
  a fixed width in cells and an unbounded depth, generated on demand via chunked loading.
  (v0.5 required a bounded rectangular volume; v0.6 reverts to the infinite shaft that shipped.)
- **AC-5.1.2** The system SHALL keep only a sliding window of resident chunks, recycling off-screen
  chunks, so resident cell count stays bounded regardless of mine depth.
- **AC-5.1.3** The mine SHALL be generated using **FastNoiseLite** to pick each block's type per
  depth band. The generation SHALL be a pure function of (mine seed, absolute cell coordinate) so
  any unloaded chunk regenerates identically.
- **AC-5.1.4** The mine's width SHALL come from data, not code. Depth is unbounded (the
  `mine_height_cells: 0` sentinel in `/data` denotes an infinite shaft). Per-mine
  `width_cells`/`depth_cells` (bounded volumes) is a ROADMAP option, not the v0.6 shipping plan.
- **AC-5.1.5** Each block SHALL carry a type id resolving — via the canonical block-type registry —
  to hardness, base HP, ore/loot content, and value.
- **AC-5.1.6** Blocks SHALL provide collision via the TileMap physics layer; dropped charges bounce
  off them before detonating.
- **AC-5.1.7** Generated noise SHALL be **coherent** (FastNoiseLite), producing ore veins/clusters
  rather than per-cell salt-and-pepper, so there are formations worth optimizing toward.
- **AC-5.1.8** The platform SHALL descend through the shaft as the player clears beneath it; there
  is no mine bottom in the infinite-shaft model (the reachable depth is the deepest supported row).
  The relic SHALL be placed at or below a configured minimum depth. (v0.5 required a bounded
  bottom + relic within it; v0.6 reverts to the infinite model.)

### 5.2 Destructible terrain (block HP + damage stages)
- **AC-5.2.1** Each block SHALL have HP equal to its type's base `max_hp` from the data table —
  **NO depth multiplier, NO per-mine hardness multiplier** (v0.6.1: both removed per design decision).
  Difficulty scaling comes from **depth bands placing harder block types** (higher base HP types like
  hard_rock, obsidian) at greater depths, and later mines featuring harder block distributions in
  their depth-band loot tables. The HP SHALL be applied once at chunk init and stored per-cell.
- **AC-5.2.2** Per-cell HP and accumulated damage SHALL be stored in a parallel per-chunk array
  (`PackedInt32Array` indexed by local cell), NOT in the TileMap cell, with a lifecycle tied to
  chunk load/unload.
- **AC-5.2.3** WHEN an explosive detonates, the system SHALL deal damage to each block within the
  blast radius equal to the blast intensity at that block's grid-cell distance from center, sampled
  from the explosive's blast map and **scaled by a fuzzy/random factor drawn from an injected,
  seedable RNG** (the charge's actual sub-cell detonation position seeds/biases the draw). v0 uses
  radial falloff with **no line-of-sight occlusion**, computed against the **pre-blast snapshot** (no
  chain propagation through cells broken in the same blast).
- **AC-5.2.4** Blast resolution SHALL be a direct grid walk over the cell-space bounding box of the
  radius against the per-cell HP array — no physics queries, no full-map scan. The RNG SHALL be
  advanced in a fixed walk order so a fixed seed yields a fixed result. Max radius in cells SHALL be
  bounded in `/data`, and the data gate SHALL enforce that the falloff array length matches the
  configured radius (single source of truth).
- **AC-5.2.5** WHEN a block's accumulated damage crosses a stage threshold, the system SHALL show the
  corresponding cracked-overlay stage on a dedicated overlay TileMapLayer using the single shared
  `0..N` crack-stage TileSet. The stage contract SHALL be explicit: full HP = stage 0; the maximum
  *visible* crack stage is `crack_stages - 1`; a broken cell (HP 0) shows no overlay (it is removed).
- **AC-5.2.6** WHEN a block's HP reaches 0, the system SHALL remove it, spawn cosmetic particle
  debris, award any relic instantly (§5.6), and auto-credit any ore value (§5.5). The cleared square
  cells form the cavity.
- **AC-5.2.7** IF a block survives a blast (HP remains), THEN it SHALL retain its damage stage, so
  harder/deeper rock needs repeated or more efficient charges (this is the optimization pressure).
- **AC-5.2.8** Block removal and damage SHALL update only affected cells via batched `set_cell` calls
  followed by a single collision/visual update per detonation, never rebuilding the whole map.
- **AC-5.2.9** WHILE destruction occurs, the system SHALL maintain 60 fps on the performance-target
  devices, including web.

### 5.3 Aim & throw
- **AC-5.3.1** WHILE the player drags on the mine screen, the system SHALL adjust the active charge's
  launch **angle** and display a predicted-trajectory arc that shows **only the initial throw up to
  the first bounce**, originating from a fixed platform muzzle (never under the finger).
- **AC-5.3.2** Launch power SHALL be the active charge's data-defined base impulse, not a separate
  player input. Aiming SHALL be forgiving (no precision/timing requirement).
- **AC-5.3.3** WHEN the player presses the throw button, the system SHALL spawn the active charge as a
  Rapier rigid body at the previewed angle/impulse; IF the charge was a finite (paid) charge, it
  SHALL remove one from the tray; the **free unlimited charge SHALL never be decremented**.
- **REMOVED: AC-5.3.4** (predicted arc matches actual flight) — the preview is a pre-first-bounce hint
  only; post-bounce is intentionally unpredicted.
- **AC-5.3.5** WHEN the tray becomes empty, the system SHALL open the shop flow rather than ending
  the dig; IF the player has no money and no charges, the system SHALL grant a free 5-pack of the
  basic charge. The old "empty tray ends the run" and "free unlimited charge always in tray" models
  are superseded.
- **AC-5.3.6** WHEN a tray charge is tapped, the system SHALL select it as the active charge. The
  free unlimited charge SHALL be a permanent, always-selectable tray slot.
- **AC-5.3.7** The aim and throw interactions SHALL behave identically for mouse and single-touch via
  a single shared code path.
- **AC-5.3.8** The system SHALL NOT have any lose/fail state. The empty-tray shop flow and the
  no-money free 5-pack of basic charges SHALL prevent soft-locks.
- **AC-5.3.9** WHEN a charge is launched from the platform muzzle at the default straight-down angle
  in an otherwise open shaft, it SHALL descend into the mine unobstructed (v0.6: the platform is a
  VISUAL anchor, not a physics body — the charge passes through it via `collision_mask=1` (terrain-only),
  so it is never trapped above the shaft by construction). Launcher/platform geometry SHALL NOT act as
  a solid lid over the shaft.

### 5.4 Explosives & packs (gacha)
- **AC-5.4.1** An explosive type SHALL be a data resource with: mass, bounce, friction, base impulse,
  blast map (shape + intensity falloff), `detonation_mode` (`fuse_seconds` | `on_first_impact` |
  `on_rest`) and its parameters, sticky flag, an **efficiency/cost** descriptor, rarity, and tier.
  IF `detonation_mode == fuse_seconds`, THEN `fuse_seconds > 0` SHALL be present (data-gate enforced).
- **AC-5.4.2** Sticky charges SHALL freeze at first contact, then run their `detonation_mode`. A
  charge that comes to rest without ever impacting SHALL still resolve its `on_rest` mode (no
  soft-lock).
- **AC-5.4.3** The basic weak/inefficient explosive SHALL be finite and available as a free 5-pack
  only when the player has no money and no charges. Bought packs grant finite, more efficient
  explosives (better ore-per-throw / dig-per-throw), which is what money buys. The old free
  unlimited permanent tray slot is superseded.
- **AC-5.4.4** A pack SHALL be a weighted table that yields a finite set of (efficient) charges, with
  rare chances to roll a higher tier. **No pity/bad-luck protection is implemented** (v0.6.1: removed
  per design decision). The comeback mechanic is the free charge + dropping to an easier mine to
  rebuild money — a player who cannot progress at the current depth returns to a shallower mine to
  rebuild their economy. The `pity`/`pity_every` field SHALL be absent from `/data` (no
  declared-but-unimplemented fields).
- **AC-5.4.5** WHEN a pack is opened, the system SHALL grant its rolled charges into the run tray.
  Pack rolls SHALL be driven by a single run-scoped seedable RNG (reproducible from the run/mine seed),
  not re-seeded from mutable state per call.
- **AC-5.4.6** A charge's effective dig depth is emergent from AC-5.2.3 (blast intensity vs local rock
  HP, which scales with depth + mine hardness); the free charge SHALL always be able to *eventually*
  break the floor beneath the platform (no stall), just slowly/inefficiently.

### 5.5 Economy
- **AC-5.5.1** WHEN a block carrying ore/gems is destroyed, the system SHALL auto-credit money by the
  item's value (v0: no pickup step; a fly-to-counter animation is cosmetic only), exactly once per
  cell.
- **AC-5.5.2** Loot SHALL be resolved by a two-layer model: a depth-banded weighted **filler** table
  (dirt/rock/hard_rock) over which rare **ore overlays** (`ore_overlays.json`) are stamped per-ore via
  coherent FastNoiseLite fields with a rarest-first priority budget. With increasing
  depth, the **expected ore value per cell SHALL strictly rise** and the **rare-gem (highest-value
  block type) probability SHALL strictly rise**, so deeper digging is strictly more rewarding and a
  deep gem strike can fund the next efficient pack (the in-dig comeback). Common low- or zero-value
  filler rock MAY appear at any depth — the reward signal is expected value plus gem chance, not a
  per-cell minimum. The data gate SHALL verify both monotonicities across adjacent depth bands.
  *(v0.4.1: replaced the prior "floor (minimum value) rises" clause — see changelog.)*
- **AC-5.5.3** Money is per-dig: earned and spent within a dig and reset when a new dig starts (§5.6).
- **AC-5.5.4** All prices, values, weights, efficiency descriptors, and HP multipliers SHALL come
  from editable data files validated by the `DataValidator` CI gate (ad-hoc GDScript rules + JSON
  schemas where present). "Schema-validated" here means the data gate enforces shape + cross-refs +
  ranges at build/test time; load-time validation is a ROADMAP hardening item, not a v0.6 shipping claim.
- **AC-5.5.5** No `/data` configuration SHALL produce a stall: the free charge SHALL always be able
  to break the shallowest block type in any mine (slowly), so progress is always possible without
  spending. The data gate SHALL verify this property — the free charge's blast intensity must exceed
  the lowest base HP among block types placed in each mine's shallowest depth band. (v0.6.1: reworded
  — "floor-HP scaling" removed since HP no longer scales with depth.)

### 5.6 Relics, prestige & power growth
- **AC-5.6.1** Each mine SHALL contain a relic placed at generation time as a pure function of
  (mine seed, cell), located below a configured minimum depth. The relic occupies a **2×2 cell
  footprint** (a seed-derived anchor; `RELIC_W`/`RELIC_H` in `block_gen.gd`), stamped at priority 0
  over all other layers. (Placement is deterministic; it is
  the dig's objective, not a random per-break drop. v0.6: the minimum depth is a global `min_depth_cells`
  in `relics.json`, not per-mine — per-mine relic windows are a ROADMAP option with bounded mines.)
- **AC-5.6.2** WHEN the relic's 2×2 footprint is fully excavated (all four cells destroyed), the
  system SHALL pause the dig and **offer** prestige, firing the offer exactly once on the last relic
  cell's break. The player MAY either **accept** (bank **1 prestige point**, end the dig, and show the
  prestige/dig-end screen) or **decline** (resume the current dig and keep descending the shaft). The relic SHALL never be a poolable/recyclable body. On the first relic ever found, the
  system SHALL trigger the one-time narrative reveal.
- **AC-5.6.3** WHEN prestige is accepted, the system SHALL bank **1 prestige point**, mark the
  relic collected, reset per-dig state (money, tray's finite charges, depth), and return to a state
  from which the next dig can begin.
- **AC-5.6.4** The system SHALL retain prestige points and prestige-tree purchases across digs;
  purchases SHALL make subsequent digs measurably stronger (power growth).
- **AC-5.6.5** Previously collected relics SHALL stay collected across digs, so progress toward
  completion is monotone and the loop provably converges.
- **AC-5.6.6** Prestige points SHALL come **only from relics**, at **exactly 1 point per relic**.
  Money and other per-dig results SHALL NOT convert to prestige.
- **AC-5.6.7** WHEN the **final mine's** relic is collected, the system SHALL trigger the authored
  ending. After the ending the game SHALL remain playable (soft cap) — the player may keep digging/
  optimizing, but completion is recorded.

### 5.7 Mining platform & descent
- **AC-5.7.1** The platform SHALL be the camera's anchor near the top of the shaft; the predicted
  arc and live charges launch from its muzzle. It SHALL read as a launcher/rig, not as a horizontal
  blocker that visually or physically caps the mine opening. (v0.6: the platform is a VISUAL anchor,
  not a physics body — charges pass through it with `collision_mask=1` (terrain-only). This satisfies
  "not a solid lid" by construction. A physical platform with charge↔platform collision is a ROADMAP
  option.)
- **AC-5.7.2** WHILE enough cells directly beneath the platform are cleared (threshold configurable
  and upgrade-reducible), the system SHALL lower the platform by tweening its target position over a
  configured duration (not an instantaneous snap).
- **AC-5.7.3** The camera SHALL follow the **platform's target position** using position smoothing,
  and SHALL NOT be hard-set per frame in a way that fights the smoothing.

### 5.8 UI & screens
- **AC-5.8.1** The Mine screen SHALL show: money + current depth (top-left), a nav button (top-right),
  the horizontal charge tray + throw button (bottom; the free charge is always the first slot), a
  compact relic/progress indicator, and a **depth resource-odds readout** showing the current depth
  band's block probabilities.
- **AC-5.8.2** The tray SHALL show per-charge remaining counts (the free charge shows ∞) and indicate
  the selected charge by shape/border/elevation (not color alone).
- **AC-5.8.3** WHEN the nav button is pressed, the system SHALL present Hub/Mine-select, Shop,
  Upgrades/Prestige, and Settings as modal overlays while the Mine remains instanced and paused,
  preserving all in-progress dig state.
- **AC-5.8.4** The relic-collected dig-end SHALL be a distinct, explained state (relic found, prestige
  banked, power gained, how to start the next dig / pick a mine).
- **AC-5.8.5** All interactive controls SHALL meet ~44–48px minimum touch targets with non-overlapping
  hit areas on the smallest supported portrait resolution; the tray SHALL scroll/paginate rather than
  shrink below that; bottom controls SHALL sit above the device home-indicator/gesture zone.
- **AC-5.8.6** The UI SHALL scale to the supported portrait aspect-ratio range across phone and
  browser without overlap or clipping at maximum UI text scale (numbers reflow/abbreviate).
- **AC-5.8.7** Settings SHALL include a Credits/Attributions screen rendered at runtime from
  `ATTRIBUTIONS.md` (single source), so shipped builds carry required asset attribution.
- **AC-5.8.8** The HUD SHALL display the **current depth band's block probabilities** (resource odds)
  and update them whenever the platform crosses into a new band, so the player can see deeper zones
  become more lucrative.

### 5.9 Particles & debris
- **AC-5.9.1** Cosmetic explosion spray SHALL be GPUParticles2D (bright pixel + darker trailing
  shades), with no collision, and SHALL set `COLOR` in its material so it renders on the web
  Compatibility renderer. (No `ColorRect`/sprite-sheet explosions.)
- **AC-5.9.2** Collectible/debris bodies SHALL be a pooled, capped set of cosmetic rigid bodies that
  settle (and sleep) then despawn; the pool SHALL never be exceeded (oldest recycled). Recycling a body
  SHALL have no gameplay effect (money credited on destruction per §5.5; relics exempt per §5.6).
- **AC-5.9.3** The cap SHALL be expressed in **active (awake)** bodies, with separate web/mobile and
  desktop caps in `/data`; collectibles SHALL NOT collide with each other or with the in-flight charge
  (v0.6 masks: charge↔terrain only — `collision_mask=1`, the platform is visual and not a collider;
  collectibles↔terrain only).

### 5.10 Accessibility & settings
- **AC-5.10.1** Settings SHALL include: motion/screen-shake intensity slider (default low, seeded from
  the OS reduced-motion preference where detectable), UI text scale, and SFX/music volume.
- **AC-5.10.2** The game SHALL convey no required information by color alone: each block type SHALL
  carry a distinct shape/glyph/pattern on the shared overlay layer; each tray charge SHALL show
  icon + count + tier glyph.
- **AC-5.10.3** The master palette SHALL be the adopted colorblind-safe palette, with luminance
  contrast (not just hue) between adjacent block types; generated/recolored art quantizes to it
  (sourced packs exempt).
- **AC-5.10.4** The narrative reveal SHALL present as on-screen text honoring the UI text-scale
  setting, include captions for any audio, respect reduced-motion (static legible fallback), and be
  replayable from Settings or a relic codex.

### 5.11 Save & persistence
- **AC-5.11.1** The system SHALL persist prestige points, prestige-tree purchases, the relic
  collection, unlocked/accessible mines, per-mine seeds, completion status, and settings, using Godot
  Resource serialization.
- **AC-5.11.2** The save SHALL carry a `save_schema_version`; on load the system SHALL migrate older
  versions via ordered steps, ignore unknown fields, and default missing ones. Prestige purchases
  SHALL be stored as purchased node IDs + counts (not a serialized tree object).
- **AC-5.11.3** Saves SHALL be written atomically (temp → rename) with one rolling backup; a load
  failure SHALL fall back to backup, then to a clean default with a non-destructive warning.
- **AC-5.11.4** The system SHALL autosave at dig/prestige boundaries and on app pause/focus-out.
- **AC-5.11.5** On web, the system SHALL detect when persistence is unavailable (incognito/cookies
  blocked) and warn, namespace its `user://` path per-game, and provide manual save export/import.

### 5.12 Shop, packs & mine access
- **AC-5.12.1** The tray SHALL always contain the free unlimited charge; no purchase is required to
  play or progress.
- **AC-5.12.2** WHEN the player buys a pack they can afford, the system SHALL debit its price and grant
  the rolled (efficient) charges into the run tray (per §5.4); IF unaffordable, the system SHALL
  prevent the purchase. Pack catalog and prices live in `/data`.
- **AC-5.12.3** Buying SHALL be available via the Shop overlay during a dig (Mine stays paused).
- **AC-5.12.4** The player SHALL **buy access** to deeper/harder mines using a data-defined currency
  (money and/or prestige; specified in `/data`); accessible mines persist (§5.11). Picking an
  accessible mine starts a dig there.

### 5.13 Audio
- **AC-5.13.1** The system SHALL provide SFX for core events: detonate, block crack-stage, block
  break, ore credited, pack open, relic found (dig-end), prestige banked. Placeholder SFX SHALL be
  present from the step-1 slice.
- **AC-5.13.2** Audio SHALL route through a bus layout (Master → {SFX, Music}) that the §5.10 volume
  sliders control independently.
- **AC-5.13.3** On web, the system SHALL resume/unlock the audio context on the first user gesture
  before any SFX/music plays.

---

## 6. Build order (prototype-first)

1. **Vertical slice of the core loop:** one infinite shaft (fixed width, unbounded depth); drag-to-aim-angle +
   throw button; **forgiving aim** with an **initial-arc preview**; a block-grid mine volume with the
   **per-cell HP/damage array** (HP scaled by depth + mine hardness); a charge that bounces on blocks,
   detonates per its `detonation_mode`, and clears a square cavity via a **fuzzy (seeded) blast**;
   **FastNoiseLite** gen with ore veins; cosmetic particle debris; smooth platform lowering + camera
   smoothing; the **free unlimited charge** plus at least one bought efficient charge; ore→money; a
   **relic that offers prestige** (accept → bank +1 point and end dig; decline → keep digging); a
   **depth resource-odds HUD readout**; a **minimal prestige step** (bank → one permanent upgrade →
   measurably stronger next dig); placeholder SFX; and a 5-target export smoke test.
   *Gate: developer judgment that the optimization loop reads — the free charge works but buying an
   efficient charge visibly improves ore/time-to-relic, and prestige makes the next dig stronger.*
2. Tray + throw + free-unlimited-charge + bought packs (gacha rolls + pity).
3. Procedural depth bands + loot tables + money + the canonical block registry + data-validation.
4. Relics as objectives + first-relic reveal + relic-ends-dig + prestige tree (power growth).
5. Hub/mine-select + buy-access to harder mines (per-mine hardness scaling). *Set the completion-time
   band here and back-solve relic-set size / mine count.*
6. Shop / Upgrades / Settings overlays + nav + save/persistence (§5.11).
7. Authored ending on final relic (soft cap); additional authored mines.
8. Accessibility pass + performance pass + per-target export hardening.

> Step 1 is the highest-risk slice. Dropping cross-platform determinism + bounce-accurate preview
> *reduces* its risk vs v0.3; the remaining unknowns are the optimization feel, the fuzzy-blast feel,
> and cross-platform export.

---

## 7. Verification gates

- **Optimization-feel gate (step 1):** developer judgment that the free charge is usable but a bought
  efficient charge visibly improves ore-per-throw / time-to-relic, and that prestige makes the next
  dig stronger.
- **Objective gate:** each mine's relic is reachable with obtainable charges, and breaking it offers
  prestige (accept banks +1 point and ends the dig; decline resumes play).
- **No-stall gate:** no `/data` configuration stalls a dig; the free charge can always break the floor
  beneath the platform (slowly). (Replaces the old solvency *and* tension gates.)
- **Finiteness gate:** a reachable end state exists (final relic); collected relics persist; the loop
  converges; the post-ending soft cap does not require endless grind to reach the ending.
- **Parity gate:** every interaction passes identically on mouse and touch via one code path.
- **Accessibility gate:** palette passes colorblind-simulation; every color-coded signal has a
  non-color redundancy; UI text scale reflows a target screen.
- **Save gate:** save/load round-trips; an older-version save migrates; a corrupt save recovers from
  backup; backgrounding does not lose progress.
- **Data-validation gate:** all `/data` loads and validates (weights > 0, referenced ids resolve,
  falloff length == radius, fuse charges have a fuse, free unlimited charge exists and is solvable,
  HP multipliers present).
- **Perf gate:** 60 fps sustained during heavy destruction on each target device (web measured
  explicitly).

> **Removed gates:** the v0.3 *preview-accuracy* gate (preview == actual landing incl. a bounce) and
> the *tension* gate (out-of-charges run-end) no longer apply.

---

## 8. Open decisions (still need answers)

- ~~Exact relic-set size, mine count, and relic distribution across the roster~~ → **RESOLVED v0.6.1**:
  8 mines (Surface, Coal, Copper, Quartz, Silver, Gold, Diamond, Abyss), 9 relics (1 per mine + Heart
  of the Earth), relic at authored depth per mine.
- The prestige **tree** shape/costs (power-growth nodes) — **24 nodes across 4 branches** (count
  locked v0.6.1; node names/effects deferred to design pass).
- Mine-**access pricing** (money vs prestige vs both) and the per-mine **hardness** curve (now: harder
  block *types* at depth, not an HP multiplier — AC-5.2.1 amended).
- The **efficiency model** for paid charges (how "efficiency" is expressed in data and felt in play —
  e.g. ore-per-throw, blast-per-cost, fewer throws to floor).
- The content of the narrative reveal(s) — **one line of lore per relic** (locked v0.6.1); the
  authored **ending** — **content deferred to U22** (cinematic format locked).
- ~~The **non-color axis** of per-mine variety~~ → **RESOLVED v0.6.1**: all three axes (alt base
  tiles + parallax bgs + particle ramps).
- ~~Onboarding/tutorial stance~~ → **RESOLVED v0.6.1**: one-time hint overlays, first dig only,
  replayable from Settings. ~~Title state~~ → **RESOLVED v0.6.1**: logo + one-tap auto-continue.
  Localization stance, analytics stance — see `ROADMAP.md` §G4 (currently unspecced; decide before
  the relevant milestone).

> **Resolved in v0.4** (were open in v0.3): physics module → **Rapier, non-deterministic**; noise →
> **FastNoiseLite**; run model → **no-loss, relic-ends-dig, power-growth, finite soft cap**.
>
> **Resolved in v0.5**: mine geometry → **bounded rectangular volume**; prestige formula → **exactly
> 1 point per relic** (money does not convert); relic flow → **offer UI** (accept or keep digging);
> depth readout → **resource odds at current depth**; no passive income.
>
> **Resolved in v0.6** (reconcile docs to shipped code): mine geometry → **infinite shaft** (the
> v0.5 bounded-volume pivot was reverted in code; `mine_height_cells: 0` is the infinite sentinel);
> platform → **visual anchor, not a physics body** (charges pass through it; `collision_mask=1`
> = terrain-only, not the v0.5-pinned `5`). The ACs below are amended to match. Per-mine
> `width_cells`/`depth_cells` and a physical platform remain a ROADMAP option, not the shipping plan.
>
> **Resolved in v0.6.1** (2026-06-19 art-planning interview):
> - **HP scaling removed** (AC-5.2.1 amended): no depth multiplier, no per-mine hardness multiplier.
>   Difficulty comes from harder block *types* at depth (higher base HP), not a multiplier on the
>   same types. Solvency gate (AC-5.5.5) reworded to match.
> - **Pity removed** (AC-5.4.4 amended): no bad-luck protection. Comeback = free charge + drop to
>   easier mine to rebuild economy.
> - **Mine roster locked at 8** (real-world mining eras): Surface, Coal, Copper, Quartz, Silver,
>   Gold, Diamond, Abyss (capstone). Width 128, infinite depth, relic at authored depth per mine.
> - **Relic set locked at 9**: 1 per mine + 1 final (Heart of the Earth). One line of lore per relic.
> - **Gacha roster locked at ~18 charges** across 5 rarities; **7 crates** (Rusty→Legendary Cache).
> - **Per-mine variety**: all three axes (alt tile textures + parallax bgs + particle ramps).
> - **Upgrade tree**: 24 nodes across 4 branches (design deferred, count locked).
> - **Onboarding**: one-time hint overlays, first dig only (replayable from Settings).
> - **Title screen**: logo + one-tap auto-continue.
> - **Ending**: final-game cinematic only (content deferred to U22).
> - **Art style**: Diggin cheerful/bright; 16px source / 32px render; no dithering; top-left light;
>   1px outline on sprites/icons, 1px frame on tiles; textured parallax bgs; compact HUD.
>   See `art/STYLE.md` for the full style contract.
