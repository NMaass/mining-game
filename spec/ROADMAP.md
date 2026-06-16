# ROADMAP.md — full-game build plan (post-slice) + spec-gap register

**Purpose.** `VERTICAL_SLICE.md` decomposes SPEC §6 **steps 1–3** into verifiable units U0–U10.
This file extends the *same contract model* to the rest of the game (SPEC §6 **steps 4–8**) as
units **U11–U26**, and records **what is not yet spec'd** — because several units cannot be built
verifiably until a specific decision is made. Each "Blocked-by-spec" tag points at the gap in §G
that must be closed first.

Same rules as the slice: a unit is **one `build-unit` workflow run**, "done" only when its **gate
exits 0**, every test cites the `AC-x.y.z` it covers, all tunables live in `/data`, pure logic in
`scripts/core/`. The novelty here is that not every acceptance criterion is machine-checkable, so
each unit also names its **Verifier class** (§V).

> Wiring note: `.claude/workflows/build-unit.js` currently reads unit sections from
> `spec/VERTICAL_SLICE.md`. To build U11+, point it (or a sibling `build-milestone` workflow) at
> **this file** for `U >= 11`. One-line change; the loop/gate machinery is unchanged.

---

## V. Verifier classes (who/what proves a unit)

Each unit declares one or more. Only A–D are CI-gateable; **E is the developer's call** (same
stance as the slice's "feel gate").

- **A — CI gate (exit 0):** `tools/run_tests.sh` + `tools/validate_data.sh`. The default.
- **B — Golden/determinism:** pinned file in `tests/golden/`, byte-equality across two runs.
- **C — Headless integration:** boot a scene headless, drive via direct calls (no injected input),
  assert end-state + no orphan leak.
- **D — Build-success:** an export preset builds without error (automatable in CI matrix); a
  structural project-setting/material assertion (e.g. renderer pinned, particle sets `COLOR`).
- **E — Human/device verifier (out-of-CI):** feel, 60 fps on a real phone/browser tab, CVD
  simulation, real-thumb parity, iOS/macOS Safari render. Assigned to the developer with a written
  checklist; never claimed green by an agent.

A unit that leans on E still ships **as much A–D coverage as possible** (e.g. a perf unit gets an
auto "active-body cap never exceeded" test even though "feels smooth at 60 fps" is E).

---

## Milestone map (continues the U0–U10 graph)

```
[slice U0–U10 done] 
      │
M4 Gacha ───────── U11 pack-roll  U12 gacha-data+validator
      │
M5 Relics/Prestige U13 relic-place/award  U14 prestige-system  U15 first-relic-reveal
      │
M6 Meta/Save ───── U16 nav/overlays  U17 shop  U18 upgrades  U19 settings+credits  U20 save/persist
      │
M7 Content ─────── U21 mine-roster/unlock  U22 authored-ending
      │
M8 Harden ──────── U23 accessibility  U24 audio  U25 perf/caps  U26 per-target-export
```

Dependency-ordered; units with no edge (e.g. U17/U18/U19, or U23/U24/U25) are parallelizable by
separate workflow runs once their inputs exist. Each milestone = one `build-slice`-style sweep.

---

## M4 — Gacha (SPEC §6 step 4)

### U11 — Pack roll engine (pure)
- **Goal:** `Packs.roll(pack_id, rng, ctx) -> {charges:[id], pity}` — weighted table, rare
  higher-tier, pity + bad-luck protection. Pure; `rng` and `pity` state passed in/out.
- **Depends:** U1 (registry), U9 (tray/`buy_pack`).
- **ACs:** AC-5.4.3, AC-5.4.4, AC-5.4.5.
- **Auto-tests** `tests/unit/test_packs.gd`: roll distribution within tolerance of weights over a
  large sample; **pity guarantee holds under adversarial seeds** (every pack yields ≥1 charge that
  can damage the current band); bad-luck higher-tier roll occurs within N packs for worst-case seed.
- **Verifier:** A, B (golden roll sequence for a fixed seed).
- **Blocked-by-spec:** §G3-pity (value of `N`; the exact "can damage current band" predicate; what
  `ctx` carries — current depth band at open time).

### U12 — Gacha data + validator rules
- **Goal:** extend `data/packs.json` + `data/explosives.json` with tier/rarity/pity fields; add
  `DataValidator` rules so no pack can be unsolvable and `pity.N > 0`.
- **Depends:** U11.
- **ACs:** AC-5.4.1, AC-5.5.4, AC-5.5.5 (solvency).
- **Auto-tests:** validator rejects a pack whose max-tier charge can't dent its intended band;
  accepts the shipped tables. **Verifier:** A.
- **Blocked-by-spec:** §G3-solvency (the formal solvable-floor predicate; bounded depth makes this a finite check).

---

## M5 — Relics & prestige (SPEC §6 step 5)

### U13 — Relic placement & award
- **Goal:** decide relic presence per cell as `f(seed, cell, depth)` (nonzero only below a min
  depth); **offer prestige** on the carrying block's break (accept → bank +1 point and end dig;
  decline → keep digging); **pool-exempt**; set first-relic flag.
- **Depends:** U2 (gen), U4/U3 (break path), U8 (credit path mirror), UI overlay (U16).
- **ACs:** AC-5.6.1, AC-5.6.2 (offer + exemption), AC-5.6.5 (stays collected).
- **Auto-tests** `tests/unit/test_relic.gd`: placement is deterministic (golden); breaking the relic
  pauses and offers prestige; accepting banks exactly 1 point and ends the dig; declining resumes
  play; awarding never routes a relic through the collectible pool (structural); collected set is
  monotone across `reset_run()`.
- **Verifier:** A, B, C.
- **Blocked-by-spec:** §G3-relic (whether relics are unique-by-id and how the collection's size is
  known).

### U14 — Prestige system
- **Goal:** `Prestige` autoload — bank **1 point per relic accepted**, retain across runs; purchase
  power-growth tree nodes (stored as `{node_id: count}`); expose "collection complete?" for the
  ending hook.
- **Depends:** U9 (run-end), U13 (points source).
- **ACs:** AC-5.6.3, AC-5.6.4, AC-5.6.6, AC-5.6.7 (trigger only).
- **Auto-tests** `tests/integration/test_prestige.gd`: accepting a relic banks exactly 1 point +
  resets run; purchases persist across `reset_run()`; unaffordable purchase rejected. **Verifier:** A.
- **Blocked-by-spec:** §G2-prestige (tree shape + costs beyond the minimal blast-intensity upgrade).

### U15 — First-relic narrative reveal
- **Goal:** one-time reveal scene, **replayable** from Settings/codex; text honors UI text-scale;
  captions for any audio; reduced-motion static fallback.
- **Depends:** U13 (first-relic flag), U19 (settings, for replay entry) — soft.
- **ACs:** AC-5.6.2 (reveal trigger), AC-5.10.4.
- **Auto-tests:** reveal fires exactly once on first relic, flag persists; replay entry point
  invokes it; reduced-motion path selects the static variant (logic-level). **Verifier:** A + E
  (does the beat land / is it legible) — content quality is E.
- **Blocked-by-spec:** §G2-narrative (the actual reveal content — "the thing beneath the gold").

---

## M6 — Meta screens & save (SPEC §6 step 6)

### U16 — Screen navigation + modal overlays
- **Goal:** nav button opens Shop/Upgrades/Settings as **modal overlays**; Mine stays instanced and
  **paused**; all run state preserved (tray, depth, terrain damage, settled collectibles).
- **Depends:** U10 (assembled mine).
- **ACs:** AC-5.8.3.
- **Auto-tests** `tests/integration/test_nav.gd`: opening an overlay sets the Mine to paused and
  leaves grid/tray/economy state byte-identical on close; no scene rebuild. **Verifier:** A, C.

### U17 — Shop overlay
- **Goal:** Shop UI over the existing `buy_pack(id)`; available during a run.
- **Depends:** U16, U9 (`buy_pack`), U11 (rolls).
- **ACs:** AC-5.12.2, AC-5.12.3.
- **Auto-tests:** affordable buy debits + grants into tray; unaffordable blocked; buying does not
  unpause the Mine. **Verifier:** A, C. (Layout/touch-targets handled in U23.)

### U18 — Upgrades / Prestige overlay
- **Goal:** spend banked points in the prestige tree; reflect purchases; show retention gate.
- **Depends:** U16, U14.
- **ACs:** AC-5.6.4, AC-5.6.6.
- **Auto-tests:** purchasing a node debits points + persists; locked nodes un-buyable; tree state
  survives close/reopen. **Verifier:** A, C.
- **Blocked-by-spec:** §G2-prestige (can't lay out a tree that isn't designed).

### U19 — Settings overlay + Credits
- **Goal:** motion/shake slider (default low, seeded from OS reduced-motion), UI text scale,
  SFX/Music volumes; Credits screen rendered at runtime from `ATTRIBUTIONS.md`.
- **Depends:** U16; U24 (buses) soft.
- **ACs:** AC-5.10.1, AC-5.8.7.
- **Auto-tests:** each setting reads/writes and clamps; volumes map to bus levels; Credits parses
  `ATTRIBUTIONS.md` and lists every entry. **Verifier:** A; E for the OS-reduced-motion seeding on a
  real device.

### U20 — Save / persistence  *(high-risk, high auto-coverage — CORE landed early 2026-06-14 22:30)*
- **Goal:** persist prestige points, tree purchases, relic collection, unlocked mines, run seed,
  settings via Godot Resource serialization; `save_schema_version` + ordered migration; atomic
  write (temp→rename) + one rolling backup + recovery chain; autosave at run/prestige boundaries
  **and on focus-out**; web persistence detection + namespaced `user://` + export/import.
- **Depends:** U14 (the durable state).
- **ACs:** AC-5.11.1 … AC-5.11.5.
- **DONE (pulled into the slice):** AC-5.11.1/2/3/4 — pure `save_codec.gd` (versioned envelope +
  v0→v1 migration + sanitization) + `save_manager.gd` (atomic temp→rename, one rolling backup,
  primary→backup→clean-default recovery) + `Prestige.to_state/from_state`, wired into `mine.gd`
  (load on boot, autosave at the relic/dig boundary + focus-out). `test_save_codec.gd` +
  `test_save.gd` + a boot-persistence smoke test (mutation-verified). The durable state is currently
  just prestige (the only cross-dig state the slice has); per-mine seeds / mine unlocks join the
  save shape when U21 lands (the migration framework is in place for that).
- **Remaining:** AC-5.11.5 (web IndexedDB-unavailable detection + namespacing + manual export/import —
  needs the web build + a settings UI); persisting the mine roster/unlocks (with U21).
- **Auto-tests** `tests/integration/test_save.gd`: round-trip equality; an older-version fixture
  migrates correctly and ignores unknown fields / defaults missing ones; a corrupt primary falls
  back to backup, then to clean-default-with-warning; write is atomic (no partial file observable);
  purchases stored as ids+counts survive a tree-rebalance fixture.
- **Verifier:** A, C; **E** for web-eviction/incognito behavior and real background-kill on mobile.

---

## M7 — Content (SPEC §6 step 7)

### U21 — Mine roster + unlock
- **Goal:** multiple **authored** mines unlocked across prestige; each = recolor **+ ≥1 non-color
  axis**; switching preserves per-mine progress; unlock costs in `/data`.
- **Depends:** U14 (prestige currency), U20 (persist unlocks).
- **ACs:** mine-unlock (new — see §G), AC-5.10.2 / AC-5.10.3 (non-color identity).
- **Auto-tests:** an unlock debits the configured cost and flips the unlocked flag (persisted);
  each mine declares a distinct non-color axis value; gen stays deterministic per mine seed.
- **Verifier:** A, B; E for "the mines feel distinct."
- **Blocked-by-spec:** §G2-roster (count, unlock costs, the chosen non-color axis), §G3-relic
  (how the relic set is distributed across mines — needed to make completion reachable).

### U22 — Authored ending
- **Goal:** on relic-collection complete, trigger the authored ending; reachable + terminal.
- **Depends:** U14 (completion signal), U21 (full roster), U15 (reveal style).
- **ACs:** AC-5.6.7.
- **Auto-tests:** with all relics flagged collected, the ending fires exactly once and the
  finiteness invariant holds (no further required grind). **Verifier:** A + E (content).
- **Blocked-by-spec:** §G2-ending (what the ending *is*), §G3-relic (total set size defines
  "complete").

---

## M8 — Hardening (SPEC §6 step 8) — cross-cutting

### U23 — Accessibility pass  *(core landed early in-slice 2026-06-14 22:30)*
- **Goal:** master palette adopted + generated/recolored art quantized to it; **no color-only
  signal** (block glyph/shape overlay, tray icon+count+tier glyph); luminance contrast between
  adjacent block types; motion slider + text-scale actually reflow the UI.
- **ACs:** AC-5.10.1, AC-5.10.2, AC-5.10.3, AC-5.8.5, AC-5.8.6.
- **DONE (pulled into the slice):** AC-5.10.2 (block glyph overlay `GlyphLayer` + tray tier glyph) +
  AC-5.10.3 (colorblind-safe `palette.json` + luminance-contrast gate rule) — pure `block_art.gd`,
  `data_validator` rules (mutation-verified), `test_block_art.gd` + smoke + data-integrity negatives.
  Glyphs/colours are **procedural placeholders** (real art assets still ROADMAP). §G3-palette resolved.
- **Remaining:** AC-5.10.1 (motion + text-scale **settings UI** — sliders that reflow), AC-5.8.5/5.8.6
  (real-thumb hit-targets + max-text-scale reflow on the smallest portrait), AC-5.10.4 (reveal a11y).
- **Auto-tests (done):** palette luminance-contrast gate (pairwise, not just hue); every diggable block
  has a distinct known glyph; glyph renders into the GlyphLayer per cell. **Verifier:** A + **E** (CVD
  simulation on real screens, real-thumb hit-targets — the on-screen look sanity-checked by a screenshot).

### U24 — Audio integration
- **Status:** **core DONE IN-SLICE (v0.4.1, 2026-06-14 17:30).** `default_bus_layout.tres`
  (Master→{SFX, Music}) + the `Audio` autoload bind procedural **placeholder** SFX to all 7 core
  events (detonate, crack, break, ore credited, pack open, relic found, prestige banked), route
  per-bus volume, and unlock on first web gesture. Covered by `tests/unit/test_audio.gd` + a smoke
  wiring assert (AC-5.13.1/2/3 PROVEN; web-resume = Verifier-E). **Remaining U24 scope below.**
- **Goal (remaining):** replace the procedural placeholders with sourced/real SFX + a music bed;
  wire the **settings volume-slider UI** to `Audio.set_*_volume_db` (the routing exists, the UI is
  ROADMAP U16/settings); validate the web audio-context resume on a real export build.
- **ACs:** AC-5.13.1, AC-5.13.2, AC-5.13.3 (placeholder layer proven; final mix/UI/web-export open).
- **Auto-tests (done):** bus layout exists with the named buses; each core event has a bound stream;
  volume setters drive bus dB. **Verifier:** A, D (web unlock path on an export build) + E (mix).
- **Blocked-by-spec:** asset sourcing (placeholders ship now; final SFX = §G4).

### U25 — Performance + body-cap enforcement
- **Goal:** enforce the active-body cap (oldest recycled, recycling has no gameplay effect); batched
  `set_cell` + single collision/visual update per detonation; particles (not bodies) for cosmetics.
- **ACs:** AC-5.2.8, AC-5.2.9, AC-5.9.2, AC-5.9.3.
- **Auto-tests:** spawning past the cap never exceeds active count and recycles oldest; a detonation
  issues one batched terrain update (structural counter). **Verifier:** A + **E** (sustained 60 fps
  during heavy destruction on phone, browser tab, desktop — measured per device).
- **Blocked-by-spec:** §G3-dims (concrete cap numbers per target) — placeholders gate, real numbers
  from device measurement.

### U26 — Per-target export hardening
- **Goal:** export presets for web/desktop(Win/macOS/Linux)/iOS/Android; web ships Compatibility
  renderer + COOP/COEP (or single-threaded) + particle `COLOR` + audio unlock; iOS signing; Android
  keystore; web save export/import.
- **ACs:** SPEC §3 web-reality block, AC-5.9.1, AC-5.11.5.
- **Auto-tests / checks:** renderer pinned (project setting assertion); every particle material sets
  `COLOR` (structural scan); each export preset **builds without error** (CI matrix). **Verifier:**
  D + **E** (actually launches and renders on iOS/macOS Safari — the weakest browser — and on a real
  phone; the 5-target smoke from SPEC §6 step 1).

---

## G. What is NOT yet spec'd (the gap register)

Closing these is the precondition for the "Blocked-by-spec" units above. Grouped by how to act.

> **v0.4 update (2026-06-14) — now RESOLVED in SPEC v0.4, no longer gaps:** physics module (Rapier,
> **non-deterministic**); noise (**FastNoiseLite**); run model (**no-loss; relic-ends-dig;
> power-growth; finite soft cap**); relic placement (**gen-time, deterministic** — was the
> gen-vs-roll fork in G3-relic); solvency (**dissolved** — the free unlimited charge can always break
> the floor, so G3-solvency is now just a data-gate check, not a design question); run-seed
> (**per-mine**).
>
> **v0.5 update (2026-06-15) — now RESOLVED in SPEC v0.5, no longer gaps:** mine geometry →
> **bounded rectangular volume** (width × depth per mine archetype); prestige formula → **exactly 1
> point per relic** (money does not convert); relic flow → **offer UI** (accept banks the point and
> ends the dig, decline resumes play); depth readout → **resource odds at current depth**; no passive
> income. The prestige-tree *shape* beyond the minimal blast-intensity upgrade remains open.

### G1 — Spec hygiene (correct stale text)
- **G1-physics:** SPEC §8 still lists "which deterministic physics module" as open, but the project
  has **chosen Rapier 2D (enhanced-determinism)** and shipped it. Fix §8 to record the decision +
  rationale (precompiled all-targets incl. web) so it stops reading as undecided.

### G2 — Deferred-by-design (content/tuning; intentionally pending, but each blocks a unit)
These are fine to defer, but the named units **cannot be built** until decided:
- **G2-relicset:** relic-set size, mine count, relic distribution across the roster (SPEC §8). →
  blocks U21, U22 (and finiteness can't be concretely tested without a known total).
- **G2-prestige:** prestige-tree shape, node costs, retention carry-set + the "late" unlock
  threshold. → blocks U14, U18.
- **G2-narrative:** the narrative-reveal content ("the thing beneath the gold"). → blocks U15
  (content) and the ending.
- **G2-ending:** what the authored ending actually is. → blocks U22.
- **G2-roster:** the non-color variety axis per mine (alt base tiles vs parallax vs particle ramps)
  + unlock costs. → blocks U21.

### G3 — Under-specified mechanics (need a sub-decision before a unit is *verifiably* buildable)
These aren't "content" — they're rules an agent can't invent without drifting:
- **G3-pity:** pity `N` value + the exact **"charge can damage current depth band"** predicate, and
  what the roll's `ctx` knows (depth band at open time? what if the player descends after opening?).
  AC-5.4.4 names the guarantee but not the algorithm. → blocks U11.
- **G3-solvency:** the formal, checkable **solvable-floor predicate** (AC-5.5.5 says the min-tier
  obtainable charge must break "any reachable floor block"). With bounded mine depth, "reachable"
  is the deepest cell of the deepest band in the hardest mine; the DataValidator rule checks the
  free charge's worst-case damage against that finite HP.
- **G3-relic:** are relics unique-by-id, and how is total-collection size known? (Placement is
  confirmed gen-time as `f(seed,cell,depth)`.) → blocks U13, U21, U22.
- **G3-points:** ✅ **RESOLVED 2026-06-15.** Prestige is **exactly 1 point per relic**; money and
  other per-dig results do **not** convert to prestige.
- **G3-orevalue:** ✅ **RESOLVED 2026-06-14 17:30.** The two loot models are reconciled: a block's
  payout is **fixed by type** (`block_types[*].ore.value`, credited on break), and the **depth band's
  weighted table governs which types appear** (placed by `block_gen`). There is no separate runtime
  sampler — the dead `Economy.draw_loot` was removed. The depth-reward promise (AC-5.5.2) is enforced
  as a data-gate invariant: **EV per cell + rare-gem probability strictly rise across adjacent bands**.
  (Was: "is a block's payout fixed by type, rolled from the band, or type×band? relationship undefined.")
- **G3-dims:** concrete numbers that should be in `/data` but aren't pinned: mine width/depth (blocks),
  shaft width, chunk height, resident-chunk window size, depth→HP scaling function (per-band step vs
  continuous), active-body caps per target. → soft-blocks U3 (windowing test bounds), U25.
- **G3-seed:** run-seed lifecycle — random per run? per mine? persisted when (AC-5.1.4 says
  persisted)? re-roll on new run vs new mine? → tightens U2/U9/U20.
- **G3-palette:** ✅ **RESOLVED (2026-06-14 22:30).** Adopted a 12-colour colorblind-safe palette in
  `data/palette.json` (hues from Wong 2011 + Paul Tol, luminance-spread); the data gate enforces
  pairwise luminance contrast among block colours. Real *art assets* (vs procedural placeholders) and
  the final hue tuning remain a polish item, but the palette is no longer a blocker.

### G4 — Entirely missing (no AC anywhere)
- **Onboarding / first-run / tutorial:** nothing in the spec teaches drag-angle + throw-button to a
  new player. Decide: implicit, a one-time hint overlay, or none. (New unit if yes.)
- **App lifecycle UX:** explicit pause menu, quit/return-to-title, and what the "title/home" state
  even is (the spec only has four screens, all overlays on the Mine). Where does a session *start*?
- **Aim UX details:** is there a **cancel-aim** gesture? a confirm step? what shows when the tray
  has a charge selected but no drag yet? AC-5.3.x covers adjust/throw but not these states.
- **Localization stance:** text-scale is specced (AC-5.8.6) but i18n is unmentioned. Likely
  out-of-scope for a portfolio build — say so explicitly so it isn't silently assumed.
- **Analytics/telemetry:** none (consistent with portfolio/no-monetization) — worth one line to
  make the absence intentional.
- **Error/empty-state catalog:** save-corruption warning (AC-5.11.3) and run-end (AC-5.8.4) exist,
  but there's no catalogued set of failure/empty states (e.g. web-persistence-blocked banner copy).

### G5 — Verification gaps (specced behavior with **no machine gate** — needs a Verifier-E plan)
The slice already concedes "feel" to the dev. The full game adds more E-class gates that should get
a written, repeatable **human checklist** (not left implicit):
- **Perf gate on device** (AC-5.2.9): 60 fps during heavy destruction on phone + browser tab +
  desktop. Auto side: an active-body-cap test + a headless frame-time micro-bench can *approximate*;
  the device measurement is E.
- **Preview==actual on every export target** (AC-5.3.4): golden proves it in-engine (B); confirming
  it per-target at least once is an E/CI-matrix item.
- **Parity gate** (AC-5.3.7): structural shared-code-path test is A; "tested with a real thumb" is E.
- **Accessibility CVD-sim** (AC-5.10.3): contrast check is A; the colorblind simulation pass is E.
- **iOS/macOS Safari render + 5-target export smoke** (SPEC §3, §6 step 1): build-success is D;
  actually rendering on the weakest browser is E.

**Recommendation:** the slice (v0.4 salvage, `VERTICAL_SLICE.md` §0) comes first. Before kicking off
M4+, close the remaining **G3** mechanics that block *verifiable* builds (pity N, ore-value model,
prestige formula, mine-access pricing + hardness curve, efficiency model). **G2** content can stay
deferred until its milestone — but U14/U18/U21/U22 are hard-blocked, so they're the natural place to
force those decisions. **G4/G5** want a one-paragraph stance each (even "out of scope") so nothing is
silently assumed by a build agent.

---

## Process — auditable autonomous runs (referenced by CLAUDE.md + VERTICAL_SLICE)

How long unattended build runs stay trustworthy and a human at the end can confirm the spec was
honored. The 2026-06-14 review is the cautionary case: 132 green tests, yet several proved nothing
(self-healing goldens, an `is RefCounted` "architecture" test, a smoke test that never booted the
scene). **Green is necessary, not sufficient.** Layers:

1. **Traceability backbone.** Every test cites its `AC-x.y.z`. `verify-slice` emits a persisted
   `reports/spec-coverage.md` — a matrix of *every AC → asserting test (file:line) → pass/fail*. Any
   AC with no test, or any test citing no AC, is a flagged row. This is what a human reads first.
2. **Per-unit evidence.** One git commit per unit, message citing the unit + ACs + gate tail; a
   milestone = a tag and a reviewable PR. **CI green is the merge gate**, never a local agent's claim.
3. **Agentic review at milestone checkpoints.** Don't run all units unattended in one shot — stop at
   M-boundaries and fan out: `code-reviewer` (bugs/security/convention) + an **AC-faithfulness**
   reviewer ("does the impl satisfy the AC's *intent*, not just pass a test?") + a **completeness
   critic** ("which AC is unverified, what's missing?"). Findings → bounded fix loop → then advance.
4. **Anti-gaming guards.** Golden files **fail on missing** (no self-write); gate scripts + golden
   files are *protected* (a verifier flags any implementer edit to them); a **mutation spot-check**
   (flip the impl, the test must go red); structural claims must actually assert. The §G
   "Blocked-by-spec" register is the spec-drift guard — an agent **stops and flags**, never invents.
5. **End-of-run human kit (make it cheap).** Hand the reviewer: `spec-coverage.md`, the milestone
   PRs/`git log`, a golden re-run (identical bytes = behavior pinned), and a **`VERIFICATION.md`**
   checklist for the **Verifier-E** gates (§V) — perf-on-device, CVD-sim, Safari/5-target export,
   real-thumb parity, the optimization-feel gate — each pass/fail with notes. Agents never mark E green.
6. **Checkpointing.** Build to the next milestone tag, emit the report, optionally glance, then
   continue. Bounds the blast radius of a bad run and keeps the loop resumable.
