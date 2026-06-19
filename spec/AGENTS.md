# AGENTS.md — Operational context for coding agents

This file is for the AI building the game. It holds the facts an agent needs to operate in
this repo without rediscovering them or guessing. It is NOT the design — design lives in
`SPEC.md`. Read `SPEC.md` first for *what*; read this for *how*.

> Reconciled with **SPEC.md v0.6.0** (2026-06-19 docs-to-code reconciliation). v0.5 proposed bounded
> rectangular mines + a physical platform; v0.6 reverts both to match the shipped code: an **infinite
> shaft** (`mine_height_cells: 0` sentinel) and a **visual platform** (charges pass through it,
> `collision_mask=1` = terrain-only). Prestige is still **exactly 1 point per relic**; money is
> per-dig only and does not convert to prestige. There is no passive income. v0.4 **dropped**
> cross-platform physics determinism and the bounce-accurate "preview == actual" arc. **Motherload**
> remains the primary look/feel reference. When this file and `SPEC.md`/`CLAUDE.md` disagree, the spec
> wins. (`CLAUDE.md` is the fast path; keep it and this file in sync.)

---

## Project facts

- **Engine:** Godot 4.x. Primary language: GDScript. Use typed GDScript.
- **Targets:** one project, exported to HTML5 (web), Windows/macOS/Linux (desktop), iOS, Android.
  **All targets are first-class at 60 fps.** Portrait orientation. Do not add landscape layouts.
- **Primary feel reference:** **Motherload** — chunky arcade mining, compact instrument-style HUD,
  readable dirt/ore material identity, and a shaft that feels inspectable on fullscreen desktop.
  Dome Keeper / Diggin are adjacent references, not the north star.
- **Physics backend (v0.4):** **Rapier 2D, NON-deterministic.** Cross-platform determinism is NOT
  required and not relied upon (Rapier is kept for convenience; GodotPhysics2D would also be fine).
  The charge is a Rapier `RigidBody2D`. The aim preview is an **initial-arc hint (pre-first-bounce
  only)**, computed by a pure ballistic function (`ThrowParams.initial_arc`/`Aim`), and **need not
  match actual flight** — post-bounce uncertainty is intentional (SPEC REMOVED AC-5.3.4). There are
  **no physics golden tests**; only *logical* gen + blast (fixed seed) are golden-pinned.
- **Save:** local only for v1, via Godot `Resource` serialization, **plus** a `save_schema_version`,
  ordered migrations, and atomic write + rolling backup (see SPEC §5.11). No cloud, no accounts.

## Repository layout (intended)

```
/scenes        Godot scenes (.tscn) — one per screen + reusable nodes
/scripts       GDScript (.gd), typed
/data          Tunables as JSON (block-type registry, depth bands, packs, prices, blast maps)
/art           Aseprite sources (.aseprite) + exported sprite sheets + master palette
/particles     Explosion/particle resources + gradient ramps
/tests         GdUnit4 (or GUT) headless unit tests
/spec          SPEC.md, AGENTS.md, ATTRIBUTIONS.md
```

## Hard conventions

- **Tunables are data, never code.** Explosive stats, depth-band loot tables, pack weights, prices,
  blast maps, and platform-clear thresholds live in `/data` as **JSON, validated by the `DataValidator`
  CI gate** (ad-hoc GDScript rules + JSON schemas in `data/schemas/` where present). Changing balance
  must never require editing a script. (Resources are fine for read-only authored content shipped in
  the export, e.g. an explosive pointing at a particle resource — but not for the numeric balance
  tables, and never for read-write save data decoded blindly.) Load-time schema validation is a ROADMAP
  hardening item; the v0.6 shipping contract is CI-gate validation, not load-time validation.
- **One canonical block-type registry.** Block type id is the join key: id → {hardness, max_hp (or a
  formula from hardness, computed once), loot ref, value}. Depth bands and loot tables reference
  block types by id (foreign-key style), never redefine their values. Validate that every referenced
  id resolves at load.
- **Per-cell block state lives beside the TileMap, not in it.** A TileMap cell stores only
  source/atlas/alt ids and `TileSet` custom data is shared per tile-type — so per-cell HP and
  accumulated damage live in a parallel **per-chunk `PackedInt32Array`** indexed by local cell, with
  a lifecycle tied to chunk load/unload.
- **Physics shapes are primitives — for dynamic bodies.** Charge/collectible colliders are
  circles/capsules regardless of pixel art. **Terrain block colliders are square tiles** on the
  TileMap physics layer (blocks must read as blocks). Visual sprite ≠ collision shape.
- **Collision masks are explicit constants/data.** Charge ↔ terrain only (v0.6: the platform is a
  visual anchor, not a physics body, so charges pass through it — `collision_layer=2`,
  `collision_mask=1`, `contact_monitor=true`. The v0.5-pinned `mask=5` (charge↔terrain+platform) is a
  ROADMAP option if a physical platform is added). Launcher/platform geometry must leave the default
  downward entry path into the mine clear; it must not behave like a solid lid over the shaft.
  Collectibles ↔ terrain only (never each other or the charge); particles never collide. Launched
  charges use continuous collision detection to avoid tunneling.
- **Particles for cosmetics, rigid bodies only for collectibles.** Never spawn per-pixel rigid
  bodies. Pool and cap collectible bodies; settled bodies sleep; the cap is expressed in **active
  (awake)** bodies with separate web/mobile and desktop values in `/data`. (v0.6 note: `active_body_cap_*`
  is validated but not enforced at runtime because v0.6 has no physics collectibles — coins are tweened
  `Sprite2D`s. The cap is a forward placeholder; enforce it if/when physics collectibles are reintroduced.)
- **One block grid.** The mine is a single chunked `TileMapLayer` of typed square blocks in an
  infinite-depth shaft (v0.6: `mine_height_cells: 0` is the infinite sentinel; width is fixed in `/data`),
  with a sliding window of resident chunks (recycle off-screen) so resident cell count stays bounded.
  Generation sets block types (pure function of saved seed + absolute cell). Destruction removes blocks
  in a radius by a grid walk over the per-cell HP array (no physics queries, no full-map scan). Do not
  implement marching squares, value-density fields, or smooth contours — squares only. (Bounded
  per-mine `width_cells`×`depth_cells` volumes are a ROADMAP option, not the v0.6 shipping plan.)
- **Damage overlay is a dedicated second TileMapLayer** sharing the chunk coordinate config and
  using the single shared 0..N crack-stage TileSet, `set_cell`'d in parallel with the base layer.
  Do NOT bake crack stage into base-tile alternatives (combinatorial blowup) and do NOT draw
  per-tile damage. Batch all `set_cell` changes for a detonation, then trigger one collision/visual
  update.
- **Controls:** aiming is **drag-to-adjust-angle + a dedicated throw button**. Drag may occur
  anywhere on the play area; the predicted arc always originates from a fixed platform muzzle so the
  finger never covers it. Launch power is the active charge's data-defined base impulse — not a
  separate input. Detonation is driven by the explosive's `detonation_mode` data field.
- **Camera follows the platform**, never raw explosion positions; platform lowering is tweened
  smoothly (not snapped). Use Camera2D position smoothing.
- **Input parity is mandatory.** Author input once so mouse and single-touch are identical. No
  hover, no multi-touch, no timing-precision inputs. Test parity with a real thumb, not a stylus.

## Web export (first-class target — handle these or web breaks)

- Pin the **Compatibility renderer** for web/mobile.
- Particle materials MUST set `COLOR` or GPUParticles2D will not render under WebGL2.
- Resume the **Web Audio context on the first user gesture** before playing any sound.
- If you ship a threaded build, the host MUST serve **COOP/COEP** headers (SharedArrayBuffer);
  otherwise ship single-threaded. Web physics is effectively single-threaded WASM.
- iOS/macOS Safari is the weakest browser — validate web builds there explicitly.
- v0.4: physics is non-deterministic and the preview is an initial-arc hint, so cross-platform arc
  *identity* is NOT a requirement; Rapier is precompiled for web. The web concern is render/audio
  (COLOR-set particles, audio unlock), not preview parity.

## App lifecycle & persistence

- Autosave at run/prestige boundaries and on app pause/focus-out. Do not rely solely on
  `NOTIFICATION_APPLICATION_PAUSED` (delayed/duplicated on mobile) — also save on focus-out.
- Write saves atomically (temp → rename) with one rolling backup; recover from backup on load
  failure, then fall back to a clean default with a non-destructive warning.
- On web, `user://` is IndexedDB: evictable, incognito-blocked, per-origin. Namespace the save path,
  warn when persistence is unavailable, and offer manual save export/import.

## Art pipeline

- **Source existing assets before generating.** Prefer free/licensed pixel-art packs (itch.io,
  OpenGameArt) over AI generation. Generate art only to fill gaps the packs don't cover.
- **License hygiene (track in `ATTRIBUTIONS.md` with SPDX id + commercial-use + share-alike flags):**
  ALLOW CC0, CC-BY, OFL (fonts), and explicitly-commercial/usable itch licenses. FORBID CC-BY-**NC**.
  FORBID CC-BY-**SA** and **GPL** art unless the team accepts copyleft on the whole art set
  (recoloring/quantizing a sourced asset is a derivative and can trigger share-alike). Attribution
  must reach the **shipped build** via the in-game Credits/Attributions screen (SPEC AC-5.8.7),
  single-sourced from `ATTRIBUTIONS.md` — a repo file alone is not enough.
- **AI-generated art:** clean every generated asset through Aseprite (human authorship); log it in
  `ATTRIBUTIONS.md` with tool + date + a "no claimed copyright" note; never prompt in the style of a
  named artist/IP; keep generated art off the game's signature/marketable surface.
- **Master palette is the adopted colorblind-safe palette, locked.** **Generated and recolored** art
  quantizes to it; **sourced packs are exempt from strict quantization** (force-quantizing them
  destroys their ramps/AA and may exceed their license). Require luminance contrast — not just hue —
  between adjacent block types.
- **Pixel-art style contract** (so a shared palette isn't the only cohesion lever): fix
  pixels-per-block, outline rule, dithering rule, and light direction. Pack selection and generation
  conform to this, not just the palette.
- **Block-type identity rides the shared overlay/glyph layer** (shape/pattern), so "no color alone"
  survives the recolor-first per-mine variety. Plan ≥1 non-color axis of mine differentiation beyond
  recolor (alt base-tile textures / per-mine background / per-mine particle ramps).
- **Block damage is a single shared cracked-overlay set** composited via the overlay TileMapLayer —
  authored once, reused across every tile type and every mine. Do not draw per-tile damage.
- **Per-mine variety is recolor-first for v0**, but new mines are **authored** (not re-rolled
  seeds); recolor-only is a known fatigue risk, not the shipping plan.
- **Aseprite is the canonical source.** External/generated art is imported into Aseprite, cleaned,
  saved as `.aseprite`, exported to sprite sheets, imported to Godot.
- **Mine rock is a TileSet** with terrain variants per rock type.
- **Explosions are particle resources**, not sprite sheets: a few textures + gradient ramps (ramps
  authored from the master palette, in `/particles`). Sourced explosion sprites are for the charge
  and a small detonation pop only.

## Audio

- Bus layout: Master → {SFX, Music}; the Settings sliders control each independently.
- Core SFX events: detonate, block crack-stage, block break, ore credited, pack open, relic found,
  run-end. Placeholder SFX present from the step-1 slice (feel is judged with sound).
- On web, unlock the audio context on first gesture.

## Testing & validation

- Use **GdUnit4** (or GUT) with headless runs in CI. Cover the pure-logic systems: loot-table
  sampling distributions, pack weighting + pity, depth-band resolution, economy crediting, save/load
  round-trip + migration, chunk-gen determinism given a seed.
- A **data-validation pass** loads all `/data` at build/test time and asserts: weights > 0, every
  referenced block-type id resolves, every mine's relic set has nonzero cumulative probability,
  blast maps reference valid falloff. This is a CI gate.
- EARS items carry stable IDs (`AC-x.y.z`) in SPEC §5; reference them from commits/tests so "matches
  acceptance criteria" has a stable referent.

## Accessibility (non-negotiable)

- Motion/screen-shake intensity slider, default low, seeded from the OS reduced-motion preference
  where detectable (web: `prefers-reduced-motion` via `JavaScriptBridge`; mobile: platform plugin).
- UI text scale option. No information by color alone (shape/glyph/pattern + counts carry identity).
- Narrative reveal: on-screen text honoring text scale, captions for any VO, reduced-motion fallback,
  replayable.
- Minimum ~44–48px touch targets; bottom controls above the home-indicator/gesture zone.

## Definition of done for any feature

1. Matches the relevant acceptance criteria in `SPEC.md` (cite the `AC-x.y.z` ids).
2. Tunables exposed in `/data` as schema-validated JSON, not hardcoded; data-validation passes.
3. Works in portrait on both mouse and single-touch (parity tested with a real thumb).
4. Holds 60 fps on the performance target — including the **web** build — during normal use
   (a named benchmark scene with a fixed active-body count).
5. Persists/recovers correctly where relevant (save round-trip + migration + corrupt-save fallback).
6. Does not violate any "NOT in scope" boundary in `SPEC.md` §2.

## Do NOT

- Add idle/AFK infinite-grind systems. The game is finite (SPEC §2).
- Add monetization, ads, energy, or accounts.
- Build landscape or 3D layouts.
- Hardcode balance values, or store balance tables as anything but schema-validated JSON.
- Rely on cross-platform physics determinism or a bounce-accurate "preview == actual" arc (v0.4
  dropped both; the preview is an initial-arc hint only, computed by a pure ballistic function).
- Store per-cell HP/damage in TileMap cells or `TileSet` custom data (use the per-chunk array).
- Decode untrusted `Resource` save files blindly; honor the save-version/migration/backup contract.
- Replace particle explosions with frame-by-frame sprite animations.
- Implement marching squares or smooth/contoured terrain. Terrain is large discrete square blocks.
- Force-quantize sourced art packs to the palette, or ship CC-BY-NC / untracked SA/GPL art.
- Expand scope from an ambiguous spec line — flag the ambiguity and ask instead.
