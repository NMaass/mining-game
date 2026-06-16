# AUDIT — SPEC.md & AGENTS.md (Vertical Mining Game)

**Audited:** 2026-06-13 · **Docs:** SPEC.md v0.2, AGENTS.md
**Method:** 8 independent expert reviews (engine/perf, physics, design/economy, save/data,
accessibility/UX, art/licensing, spec-quality, planning) → adversarial verification of every
high-severity and technical claim (Godot 4.x facts checked against engine docs/issue tracker)
→ completeness critic. Severities below are **post-verification** (after corrections); where a
reviewer's headline claim was overstated, the corrected rating is used and the over-claim noted.

---

## Overall verdict

These are unusually disciplined design docs for an indie/AI-built game: explicit anti-scope,
locked decisions *with rationale*, a prototype-first build order that isolates the risky core,
and a hard data-driven-tunables rule. That foundation is genuinely strong and should be preserved.

The weaknesses are **not** in the vision — they're in three places:

1. **The "risky core" is under-specified and riskier than the doc claims.** §6 says "Step 1 is
   the only high-risk unknown" and "everything from step 2 onward is conventional data+UI work."
   That is false in two ways: Step 1 itself hides several unsolved problems (per-cell damage state,
   trajectory prediction, crack compositing, blast model), and Step-2+ contains at least three
   non-conventional problems (save migration, 5-target export, an economy that can stall).
2. **The economy can stall — both economically and physically — and nothing prevents it.**
3. **Persistence and cross-platform ("one build everywhere") are the largest unhandled
   engineering risks, and both are deferred to a single end-of-list line.**

Net: the spec is a strong *what*, but it defers most of the *hard how* to "data+UI work" that
isn't. The fixes below are mostly **additive clarifications**, not redesigns.

---

## Top priority — fix before/while building Step 1

These either block the build, can corrupt the win condition, or invalidate the feel gate.

### 1. Per-block HP & damage state have no specified home  *(high — gap)*
SPEC §5.2 requires per-cell HP, per-cell accumulated damage, and a *retained damage stage across
blasts*. A Godot 4 TileMap cell stores only source/atlas/alt ids; `TileSet` custom-data layers are
**shared per tile-type**, not per-cell — verified, they cannot hold per-cell HP. So the actual core
data model of the destruction system is an unspecified parallel structure.
**Fix:** add an acceptance criterion naming a per-chunk `PackedByteArray`/`PackedInt32Array` indexed
by local cell (not a global `Dictionary` — cache locality + bounded memory), with a lifecycle tied
to chunk load/unload, and state whether damaged-but-unbroken blocks survive save/reload.

### 2. Detonation trigger is never defined  *(high — gap)*
§5.1 says charges "bounce off blocks before detonating" and §5.4 adds a "sticky flag," but nothing
says **what** triggers detonation: fuse-on-spawn? on impact? on rest? Fuse-dynamite, impact-grenade,
and stick-then-timer limpet are three different games and three different prediction problems, and
§5.3's "first N physics steps" is undefined until this is. (§5.1 + §6's "bounces…then removes" do
imply a bounce *precedes* detonation, so it's not wide open — but the trigger itself is missing.)
**Fix:** add a `detonation_mode ∈ {fuse_seconds, on_first_impact, on_rest}` field on the explosive
resource; define how `sticky` interacts (freeze at first contact, then run the trigger); tie §5.3's N to it.

### 3. The economy can hard soft-lock — no anti-stall floor  *(high — gap)*
Trace the loop: charges come only from packs (§5.4) → packs cost money (implied Shop) → money comes
only from blasting ore (§5.5), which costs charges. A player who buys a pack, drops poorly, and nets
less than a pack's price gets strictly poorer. Repeat → zero charges **and** can't afford the cheapest
pack. §5.3's "out-of-charges run-end" has **no defined exit**, and prestige needs relics which need
deep digging which needs charges. The spec doesn't *guarantee* a soft-lock, but it does nothing to
*preclude* one. (Note: the money→pack purchase transaction itself has **no acceptance criterion** —
§5.4 only covers *opening* a pack. The single most important economic action is unspecified.)
**Fix:** add the Shop/purchase criterion (debit price, grant pack; block if unaffordable), and an
anti-stall guarantee: a free starter pack / minimum-solvent reset when the player can't afford the
cheapest pack. Make "no /data config produces a stalled run" an economy gate.

### 4. Physical solvability dead-end — weak charges can't break the floor  *(high — pitfall · critic)*
Separate from the economic stall: §5.7 only lowers the platform when tiles beneath are cleared, and
harder rock needs stronger charges (§5.4). If the tray holds only charges too weak to ever bring the
floor block to 0 HP, the player can have money **and** charges yet be unable to descend.
**Fix:** guarantee the floor beneath the platform is always breakable by at least one *obtainable*
charge (min-tier charge eventually breaks any reachable block, or the shop always offers a
depth-sufficient tier). Add an EARS line. This also argues for the gacha **pity** below.

### 5. The win-condition item can be silently destroyed  *(high — pitfall · critic; unverified but sharp)*
A relic is a rare drop on block destruction (§5.6), collectibles are a **capped pool, oldest
recycled** (§5.9). If a relic is emitted as a pooled collectible during a big multi-block blast and
the pool overflows, the relic body can be **recycled before it's gathered** — consuming the one
resource the entire win condition depends on. This is the lethal special case of the §5.5-vs-§5.9
ambiguity (auto-credit vs "settle and are gathered").
**Fix:** exempt relics from the collectible pool entirely — award the relic the instant its block
hits 0 HP (same moment as auto-credit), never as a recyclable physics body. Add an EARS criterion.

### 6. Trajectory prediction can't honestly show post-bounce reality  *(medium — pitfall; was flagged critical)*
Verified: Godot 4 has **no API to step a single RigidBody2D forward N physics steps** and read the
path (godot-proposals #740, still open), and default physics isn't bit-deterministic across
web/desktop/mobile. So a "predicted arc" can be faithful only up to first contact; a true bouncing
preview needs a hand-rolled shadow sim or a deterministic physics backend.
*Correction to the raw finding:* §5.3 only says "an arc by simulating the first N steps" — it never
promises bounce-accurate landing, and no §7 gate depends on arc-vs-landing accuracy, so this is
**medium, not critical**. But it must be scoped honestly or the feel gate suffers.
**Fix:** redefine §5.3 as a **launch-intent preview** — analytic parabola to first predicted
collision, confidence decaying with distance — and explicitly drop any "what will actually happen"
post-bounce claim. (Decouple all gameplay outcomes — loot, relic rolls, money, platform-lowering —
from exact physics rest positions; ground them in §5.5/§5.6 data + a cell-cleared count.)

---

## High priority — persistence & cross-platform (the deferred "conventional" work)

### 7. No save schema version or migration path  *(high — gap, confirmed)*
Core retention (§5.6 prestige persists) depends on a save that survives updates, but there's **no
`save_version` field, no migration step**, and §8 explicitly defers prestige-tree shape — so the
persisted structure *will* change. Godot Resource deserialization is brittle to field changes and
can silently drop exactly the progress the design says to retain.
**Fix:** top-level `save_schema_version` + ordered migration (load → detect → migrate → re-save);
persist *purchased node IDs + counts*, not a serialized tree object, so re-balancing §8 doesn't
invalidate saves; unknown fields ignored, missing defaulted. Make it a DoD item.

### 8. Save format (Godot Resource serialization) is a code-execution vector  *(medium — best-practice; was flagged critical)*
Loading a `.tres/.res` via `ResourceLoader.load()` can instantiate embedded scripts/types — a
documented Godot footgun. *Correction:* for a local-only, no-account single-player game the practical
risk is corrupt/incompatible saves and tampering, so **medium**, not critical — but the fix is cheap.
**Fix:** never decode Resources for read-write **save** data — use JSON or `FileAccess.get_var(...,
full_objects=false)` over a plain Dictionary schema. Resources remain fine for read-only **tunables**
shipped in the trusted export. Add this as a hard convention next to "physics shapes are primitives."

### 9. Web (`user://`) saves are evictable, per-origin, incognito-fragile  *(high — gap, confirmed)*
On HTML5, `user://` is IndexedDB: the browser can evict it, incognito blocks it,
`OS.is_userfs_persistent()` can false-positive, and saves are **per-origin** (two Godot web games on
itch.io's shared host can collide — community issue #2207). Silent prestige loss on the web target.
**Fix:** on web, check persistence and warn when unavailable; provide manual **save export/import**
(download/upload JSON — also your cross-platform backup story); namespace the save path per-game.

### 10. No atomic-write/backup; no autosave on mobile background-kill  *(medium — gap/pitfall)*
A single-file overwrite that's interrupted (tab close, app kill mid-write) corrupts the only save.
And mobile apps "close" by being **background-killed** — if you only save at explicit moments, a kill
mid-run loses state. *Godot reality:* `NOTIFICATION_APPLICATION_PAUSED` exists on Android/iOS but is
unreliable (delayed/duplicated — issue #85265); there's no guaranteed "about to be killed" callback.
**Fix:** atomic save (temp file → rename) + one rolling backup; autosave on focus-out **and** at
run/prestige boundaries; load-failure falls back to backup, then to a clean default with a warning.
Add a persistence step to §6 (currently absent entirely).

### 11. "One build everywhere" overstates the web target  *(medium/high — source-issue)*
Verified Godot 4 web realities the docs treat as free: (a) threaded builds need
SharedArrayBuffer + **COOP/COEP** headers the host must serve (itch.io/static hosts need special
handling); (b) multithreaded physics on HTML5 is unstable → web physics is single-threaded WASM;
(c) **iOS/macOS Safari** has standing SharedArrayBuffer/WebGL2 problems — so a *mobile-first* game's
web build is least reliable on iPhones; (d) **GPUParticles2D don't render on web (Compatibility/
WebGL2) without a custom `COLOR` shader** (godot #96030) — your signature explosion could be invisible
in the browser; (e) Web Audio is **muted until a user gesture** — silent-on-load web build.
**Fix:** scope "web" explicitly (e.g. desktop Chromium/Firefox = 60fps target; iOS users use the
native build; iOS Safari = best-effort); pin the Compatibility renderer for web/mobile; declare
single-threaded vs threaded (single-threaded dodges COOP/COEP + Safari but loses threaded audio/
physics); require a `COLOR`-setting particle material on web; add a first-gesture audio-unlock
criterion. Treat web as its own row in the §7 perf gate; run a web/iOS export smoke test *after Step 1*,
not at step 8.

### 12. 5-target export/CI collapsed into one line  *(medium — gap)*
§6 step 8 = "export to all targets." Each leg has real blockers: web COOP/COEP hosting; iOS Team ID +
provisioning + codesign + App Store review; Android keystore + JDK 17 + SDK. None is "conventional."
**Fix:** add a build-pipeline doc (per-target prerequisites + reproducible export command) and move a
thin 5-target smoke test to right after the Step-1 slice so platform constraints surface early.

---

## Medium priority — accessibility, UX, and missing systems

- **Finger occludes the trajectory arc** *(high — pitfall, confirmed)*. Parity is defined as
  "mouse == touch" ignoring the decisive difference: a thumb covers the launch point and lower arc in
  one-thumb portrait play. **Fix:** render the arc/launch indicator *offset above* the contact point
  (or "drag anywhere, launch from a fixed muzzle"); test the parity gate with a real thumb, and make
  "arc stays visible while dragging on touch" a criterion.
- **No onboarding / first-run UX** *(medium — gap)*. The headline metric ("good drop in 10 s, one
  thumb") and the step-1 feel gate both assume a first-timer instantly discovers drag-to-aim on a
  deliberately minimal HUD ("Nothing else by default"). The arc only appears *after* a drag starts, so
  it can't bootstrap discovery. The feel gate as written tests a *coached* tester. **Fix:** a one-time,
  skippable drag hint + empty-tray/out-of-charges states; run the feel gate cold (no verbal coaching).
- **"No info by color alone" is never operationalized** *(medium — gap)*, and it **collides with
  "recolor-first" per-mine variety** (AGENTS) — an agent following AGENTS literally produces
  color-only differentiation. **Fix:** each block type carries a distinct shape/glyph/pattern on the
  shared overlay layer (survives recoloring); tray slots show icon + count + tier glyph; selected
  charge indicated by shape/border/elevation, not color.
- **No audio design at all** *(medium — gap)*. Only a volume slider exists, yet "feel" is the whole
  pitch and audio carries explosion feel as much as particles. Also missing: the **audio-bus layout**
  (Master→{SFX,Music}) the two sliders presuppose, and the web first-gesture unlock. **Fix:** add a
  SPEC Audio section (SFX events tied to EARS systems: detonate, crack-stage, break, credit, pack-open,
  relic, run-end; music/ambience; bus layout; sourcing/licensing parallel to art) and require
  placeholder SFX at the feel gate.
- **Palette is an Open Decision (§8) yet AGENTS says "locked first" and "every asset quantizes to
  it"** *(medium — ambiguity)*. Not a hard contradiction ("locked first" is sequencing, not status),
  but it needs concrete criteria. **Fix:** promote palette to a step-0 deliverable with criteria —
  enumerate simultaneously-distinguishable swatches (every ore/gem/relic + crack overlay + UI states),
  require **luminance** contrast (not just hue) between adjacent block types, validate against
  protanopia/deuteranopia/tritanopia + grayscale. Pick a concrete 8–16 colour candidate now.
- **Bottom tray vs safe-area insets** *(medium — pitfall)*. The most touch-critical UI sits where the
  iOS home indicator / Android gesture pill live; `DisplayServer.get_display_safe_area()` reports the
  top notch but **not** bottom inset. **Fix:** reserve a configurable bottom margin; get the bottom
  inset via platform plugin; verify tray/run-end controls are tappable above the gesture zone on a
  rounded-corner phone.
- **Minimum tap-target size never specified** *(medium — gap)*. **Fix:** ~44–48px targets with
  non-overlapping hit areas on the smallest portrait resolution; scroll/paginate the tray rather than
  shrink below threshold.
- **Reduced-motion only as a manual slider** *(medium — best-practice)*. Best practice is to respect
  the OS setting; Godot has no built-in API for it. **Fix:** seed the slider default from
  `prefers-reduced-motion` on web (via `JavaScriptBridge`) / platform plugin on mobile; keep "low"
  where undetectable.
- **Minimal HUD omits required run-state feedback** *(medium — ambiguity)*: per-charge remaining
  counts, a non-chromatic selected-charge indicator, and an explained out-of-charges run-end are all
  loop-critical but excluded by "Nothing else by default." **Fix:** fold these into "the tray," not "else."
- **Narrative reveal has no captions/replay/reduced-motion fallback** *(medium — gap)*. The one
  emotional payoff could be the single inaccessible moment. **Fix:** on-screen text honoring text-scale,
  captions for any VO, static legible fallback, replayable from Settings/relic codex.
- **No game-feel/juice spec beyond particles + a shake slider** *(medium — gap)*. No hitstop, camera
  punch, number pops, or haptics — and shake defaults to low/off for a11y, removing one of only two
  feel levers. (Haptics caveat: `Input.vibrate_handheld()` doesn't work on web and ignores duration on
  iOS — never the sole non-color channel.) **Fix:** enumerate a juice toolkit, each gated by the
  motion-intensity setting.
- **Scene lifecycle on nav is unspecified** *(high — gap · critic)*. Four "separate full screens" + a
  live physics shaft: what happens to in-flight charges / settling collectibles / damage state when the
  player opens the Shop mid-run? A chunked terrain can't be cheaply rebuilt. **Fix:** keep the Mine
  instanced-and-paused with overlay screens as `CanvasLayer` modals (or define exactly what run state
  serializes on a true scene swap); add an EARS criterion that nav preserves in-progress run state.
- **"Charge in flight" at run-end / app-pause is undefined** *(medium — ambiguity · critic)*. Dropping
  the *last* charge empties the tray — does run-end fire while it's still bouncing, before it can
  detonate and free value? **Fix:** run-end = tray empty AND no charges in flight AND nothing pending;
  app-pause freezes the physics world and resolves in-flight charges on return.

---

## Medium priority — economy, content & balance

- **Game length is entirely unquantified** *(medium — assumption)*. "Completable in a bounded number
  of hours" rests on three §8-open variables (relic-set size, mine count, relic distribution) + prestige
  costs; the finiteness gate only checks *an* end state exists, not a *bounded, paced* one. **Fix:** set
  a target playtime band (e.g. 6–12 h), back-solve provisional values, add a pacing criterion.
- **No gacha pity / bad-luck protection** *(medium — gap)*. Random packs stack variance on top of
  skill-aim variance; with no real money there's no reason to withhold. Repeated low-tier rolls that
  can't dig the current band compound the stall + solvability risks. **Fix:** state the gacha's intent
  (build-variety, not scarcity) and add a pity rule (e.g. every pack guarantees ≥1 charge able to damage
  the current depth band).
- **Finite-game vs prestige-grind, and retention + infinite depth re-opens the banned grind**
  *(medium/high — pitfall · critic)*. A "retention" branch that carries depth across prestige + infinite
  depth + rising loot floors = an ever-easier, unbounded money/depth treadmill — exactly the AFK-style
  escape hatch §2 forbids. Also: does prestige re-roll the *same* mine seeds (repetition fatigue) or
  unlock *new* mines? **Fix:** clarify that prestige unlocks *new* authored mines (not re-rolls);
  guarantee relic progress is monotone (collected relics stay collected); tie the finiteness gate to a
  concrete bound ("max descents to guarantee one new relic ≤ K"); define the retention branch's "late"
  gate concretely.
- **"Comeback hook (relics)" doesn't function in-run** *(medium — pitfall)*. §1 sells relics as a
  comeback hook, but §5.6 awards prestige points "not money" — finding one gives the failing run nothing
  spendable. **Fix:** either reword §1 to locate the in-run comeback in §5.5's depth-scaled rare-gem
  ceiling, or give relics a small in-run payout too.
- **Auto-credit (§5.5) vs "settle and are gathered" (§5.9)** *(low — editorial; was flagged
  high/contradiction)*. *Correction:* §5.2 already reconciles it ("remove it, emit ore as collectible
  debris, **and** auto-credit its value") — credit fires at destruction; debris is cosmetic. Just an
  imprecise word in §5.9. **Fix:** reword §5.9 to "cosmetic debris that settles and despawns; carries no
  value; recycling has no gameplay effect." (But see #5 — relics must be explicitly exempt.)
- **"Circular cluster" / "Terraria hole" contradicts "craters jagged by construction / blocks only"**
  *(medium — ambiguity)*. A "circle" on a handful-of-large-blocks grid reads as a blocky plus/diamond.
  **Fix:** replace "circular cluster" with "all blocks whose center is within blast radius and whose HP
  reaches 0"; describe the visual as "a jagged blocky crater"; make the feel-gate language consistent.

---

## Medium/low priority — spec hygiene, data architecture, legal

- **Verification gates are subjective** *(medium — best-practice; was flagged critical)*. The most
  important gate ("a playtester… calls it satisfying," N=1) isn't falsifiable. **Fix:** operationalized
  proxies (median time-to-first-successful-drop < 10 s for N≥5 fresh testers on a named device;
  drag-to-detonation latency ≤ X ms; ≥N blocks removed per full charge on band-0) + a fixed playtest
  script and a pass threshold; keep the qualitative read as supporting evidence.
- **Quantitative targets undefined** *(low — ambiguity; was flagged critical)*. *Correction:* 60 fps
  *is* specified and the pool cap is correctly data-deferred — so criteria aren't "untestable." Still
  worth: name a **reference device** (specific phone + browser + resolution) and a single hard
  rigid-body integer cap for the perf gate.
- **No automated test strategy** *(high — gap, confirmed)*. EARS items are written "to be checkable" and
  the DoD requires matching them, but no framework/harness/CI is named. **Fix:** pick GdUnit4 or GUT;
  headless unit tests for the pure-logic systems (loot sampling distributions, pack weighting, depth-band
  resolution, economy crediting, save/load round-trip, chunk-gen determinism given a seed); run in CI;
  map automatable EARS items to test ids.
- **No data-validation / content-authoring tooling** *(medium — gap · critic)*. The whole balance
  surface is hand-edited data with no schema/validation; a weight that sums to 0, a dangling block-type
  id, or a relic with zero cumulative probability silently breaks the loop and won't be caught by
  GDScript typing. **Fix:** a build/test-time validator (weights > 0; every referenced id resolves;
  every mine's relic set has nonzero probability) as a CI gate.
- **No single cross-referenced source of truth for the block-type table** *(medium — gap)*. Many systems
  reference "the data table" without a declared schema or join keys. **Fix:** one canonical block-type
  registry keyed by type id {hardness, max_hp (or formula), loot ref, value}; depth/loot tables
  reference by id (foreign-key style); derive `max_hp` once; validate ids on load.
- **`.tres` vs `.json` never decided** *(medium — ambiguity)*. Both docs hedge "as .tres/.json,"
  guaranteeing an inconsistent `/data`. **Fix:** JSON (schema-validated on load) for human-tuned numeric
  tables; `.tres` only where you need typed references to other Godot assets. Keep tunable format
  separate from save format.
- **Generation seed/determinism not persisted** *(medium — gap)*. Chunks regenerate on revisit, but the
  noise seed isn't stated as saved, and FastNoiseLite output isn't guaranteed stable across engine
  versions. **Fix:** generation = pure function of (saved seed, absolute cell coord); persist the seed;
  persist per-cell deltas (removed/damaged) rather than replaying generation for visited depth.
- **"Infinite depth" vs TileMapLayer's int16 cell limit** *(medium — was flagged critical)*. Cells pack
  into int16 (range ±32 767, wraps on serialize) → a hard floor at ~32 767 rows, not "no bottom."
  *Correction:* the game is finite/bounded-hours anyway, so the limit is unlikely to be hit — the real,
  actionable issue is **memory/perf**: a single monotonically growing resident TileMapLayer degrades
  non-linearly (issue #105957). **Fix:** specify a sliding window of resident chunks (recycle off-screen)
  and/or periodic re-origin so cell coords stay near 0; document the effective max depth; decouple
  displayed depth from raw cell-Y.
- **Cracked-overlay compositing undefined** *(medium — gap)*. **Fix:** a dedicated second TileMapLayer
  sharing the chunk coordinate config, using the single shared 0..N crack-stage TileSet, `set_cell`'d in
  parallel; explicitly reject baking crack stage into base-tile alternatives (combinatorial blowup).
- **Blast model under-defined** *(medium — ambiguity)*: distance metric, occlusion, propagation through
  broken cells. **Fix (v0):** grid-cell distance; no line-of-sight (simple radial falloff); compute
  against the pre-blast snapshot (no chain propagation); one EARS line each. Resolve blast as a direct
  grid walk over the radius's cell bounding box against the per-cell HP structure — no physics queries,
  no full-map scan; bound max radius in cells in `/data`.
- **Camera smoothing toward a stepped descent target can lurch** *(medium — pitfall · critic)*.
  Event-driven platform lowering teleports the smoothing target; combined with chunk-gen spikes at
  boundaries it stutters exactly during the feel gate. **Fix:** tween platform lowering over T seconds;
  pre-generate one chunk ahead so gen never coincides with a descent step.
- **Attribution only in a repo file** *(medium — best-practice)*. CC-BY requires attribution in the
  *shipped* build; `ATTRIBUTIONS.md` doesn't reach end users in an export. **Fix:** a Settings-reachable
  Credits/Attributions screen rendered at runtime, single-sourced from `ATTRIBUTIONS.md`.
- **License rule covers only CC-BY** *(medium — gap; was flagged critical)*. NC (non-commercial),
  SA/GPL (copyleft — and recolor/quantize makes derivatives) are unaddressed. *Correction:* the docs
  never state commercial intent, so "legally unsellable" is inferred. **Fix:** an SPDX allow/forbid list
  (ALLOW CC0/CC-BY/OFL/explicitly-commercial; FORBID NC; FORBID SA/GPL art unless accepting copyleft on
  the art set) + commercial-use & share-alike flags per ATTRIBUTIONS entry.
- **"Source packs first" vs "everything quantizes to one locked palette"** *(medium — pitfall)*.
  Force-quantizing a sourced pack collapses its ramps/AA and is a derivative (license risk).
  *Correction:* SPEC §5.10/§8 actually scope quantization to **generated** art — AGENTS over-reaches.
  **Fix:** align AGENTS to SPEC (strict quantization on bespoke/recolored/generated only; sourced art
  exempt); recolor only where license-permitted.
- **Recolor-only per-mine variety will read samey** *(medium — pitfall)*, worsened by a limited
  colorblind-safe palette. **Fix:** plan ≥1 non-color axis (alt base-tile textures, per-mine
  background/parallax, per-mine particle ramps — cheap) beyond v0; mark recolor-only as a known-fatigue
  expedient in §8.
- **"Coherent 8-bit look" assumes palette = cohesion** *(medium — assumption)*. Palette unifies color,
  not pixel density / outline / dithering / light direction. **Fix:** a one-page pixel-art style
  contract (px-per-block, outline rule, dithering rule, light direction); pack selection conforms to it.
- **AI-art ownership/provenance/store policy** *(low — gap; was flagged high)*. *Correction:* the
  human-in-loop Aseprite cleanup step materially weakens the copyrightability concern. **Fix (light):**
  log generated assets in ATTRIBUTIONS with tool + "no claimed copyright"; don't prompt in named-artist/
  IP styles; keep generated art off the signature/marketable surface.
- **Gacha store compliance** *(low/medium — gap)*. *Correction:* Apple's odds-disclosure rule (3.1.1)
  is scoped to **IAP** loot boxes — N/A with no real money. The real task is the **age-rating
  questionnaire** (IARC/App Store/Google Play ask about randomized/simulated-gambling content regardless
  of money). **Fix:** answer rating questionnaires honestly; optional voluntary odds transparency as a
  design choice; privacy labels likely "no data collected" (ties to the telemetry decision).
- **Business model unstated** *(low — gap; was flagged critical)*. Paid vs free vs portfolio constrains
  licensing, length, store work. *Correction:* the art rule doesn't actually steer toward NC, so the
  harm is overstated — but a one-line §4 decision removes ambiguity downstream.
- **No analytics/telemetry to balance a finite game** *(medium — gap)*. The actionable half is an
  **economy-stall gate** ("no /data config produces a stalled run"); a lightweight local metrics log
  (charges/run, time-to-first-relic, money-vs-depth, deaths-by-empty-tray) is a nice-to-have compatible
  with local-only.
- **No stable IDs / change-control / CI tie to EARS** *(medium — best-practice)*. EARS items are
  unnumbered, so "matches the relevant acceptance criteria" has no stable referent. **Fix:** give each
  criterion an ID (e.g. `AC-5.3.1`); reference from commits/tests; version + changelog on every spec
  edit; define "normal use" (DoD item 4) as a named benchmark scene.
- **Aesthetic language inside SHALL statements** *(medium — ambiguity)*: "reads as 8-bit," "keeps the
  play space breathing." **Fix:** move taste into a labeled non-normative art-direction note; where it
  must be a requirement, quantify (palette ≤ N colors, M-px nearest-neighbor; HUD ≤ ~18% screen height).
- **i18n, error handling, content tooling absent** *(medium — gap)*. **Fix:** route user-facing strings
  through `tr()` now even if English-only; add a graceful-failure clause to the DoD; the data validator
  above doubles as content tooling.
- **Charge collision matrix / CCD / sticky precedence unspecified** *(low — gap)*. **Fix:** charges
  collide terrain+platform only (not collectibles/each other, keeping the prediction valid); collectibles
  collide terrain+collector only (not each other — cuts broadphase pairs); `continuous_cd` on launched
  charges to prevent tunneling; define whether sticky overrides bounce and how the charge is frozen.
- **"Few hundred rigid bodies" optimistic on single-thread WASM** *(medium — assumption)*. **Fix:**
  reframe the cap as **active (awake)** bodies; ensure settled collectibles sleep; tighter web/mobile cap
  than desktop in `/data`; validate empirically at the step-1 feel gate.

---

## Strengths (preserve — don't let fixes erode these)

- **Particles-for-cosmetics, rigid-bodies-only-for-collectibles, pooled + capped.** The single biggest
  2D-perf footgun, pre-empted, and stated identically in both docs so it won't drift. (Add only: a
  per-blast particle-count budget in `/data`, validated on the web Compatibility renderer.)
- **Data-driven tunables, enforced by the Definition of Done.** Exactly right for a tuning-heavy
  gacha/prestige game. (Add: a schema + load-time validation so hot iteration is real, not silent-fail.)
- **Finiteness / anti-grind discipline with an explicit win condition and gate.** Unusual and correct
  for a gacha loop — gives the economy a terminal goal that resists dark-pattern drift.
- **Prototype-first build order isolating the high-risk core, gated on feel before any economy.** Right
  risk sequencing. (Just widen "the risky core" to include trajectory prediction, per-cell state, and an
  early export smoke test; soften "only high-risk unknown / conventional from step 2.")
- **Locked-decisions-with-rationale + explicit anti-scope + "flag ambiguity, don't invent."** Above the
  indie norm; materially lowers scope-creep risk for an AI builder. (Add stable IDs so "spec wins" and
  "flag and ask" have referents.)
- **Diegetic, platform-anchored camera explicitly decoupled from explosion positions.** Avoids the
  juddery "camera chases every blast" failure and is independent of non-deterministic physics. (Pair with
  the descent-smoothing clarification.)
- **Explosions as particle textures + gradient ramps (not sprite sheets).** Engine-accurate, near-zero
  authoring cost, sidesteps the worst licensing surface; per-mine ramp tints are nearly-free variety.
- **Calm-by-default motion + slider + text scale + separate SFX/music volumes.** Accessibility as a
  first-class constraint with safer-than-default choices.

---

## Suggested doc actions (smallest set, highest leverage)

1. **Add 3 EARS criteria to Step 1's scope:** per-cell state store (#1), detonation trigger (#2),
   launch-intent preview reframing (#6). These are the load-bearing holes in the "risky core."
2. **Add a §5 Shop/purchase + anti-stall + solvability + pity block** (#3, #4, #5-relic-exempt, gacha
   pity). This is the difference between a finite game and an unwinnable one.
3. **Add a Persistence section + a §6 persistence step:** safe save format, `save_version` + migration,
   web export/import, atomic write + backup, autosave-on-pause (#7–#10).
4. **Scope the platform targets honestly** (web = which browsers; renderer; threads; particle COLOR
   shader; audio unlock) and move a 5-target export smoke test to right after Step 1 (#11, #12).
5. **Operationalize the gates:** name a reference device, replace "satisfying" with measurable proxies +
   a playtest protocol, add Accessibility / Save / Audio gates, give EARS items IDs, add a data-validation
   CI gate and a test framework (spec-quality + testing items).
6. **Resolve the small contradictions in wording:** auto-credit vs "gathered," circular vs jagged,
   palette "locked first" vs "open," `.tres` vs `.json`, AGENTS quantization-scope vs SPEC.
