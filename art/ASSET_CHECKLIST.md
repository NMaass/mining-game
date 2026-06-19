# ASSET_CHECKLIST.md — Tracked art inventory

> The single source of truth for every art asset the game needs. Status moves from `needed` →
> `generating` → `review` → `done`. An asset is `done` only when it passes `tools/validate_art.py`
> AND has an `ATTRIBUTIONS.md` entry. Priority tiers follow the generation order you locked:
> **T1 tiles → T2 charges → T3 UI → T4 particles → T5 screens.**
>
> **Status legend:** `exists` (shipped placeholder/final), `placeholder` (runtime-drawn, replace
> before release), `needed` (not yet authored), `generating`, `review`, `done`.
>
> **Phasing:** biome art is delivered in pairs (Surface+Coal, Copper+Quartz, Silver+Gold,
> Diamond+Abyss). Non-biome art (UI, charges, FX) is not phased.

---

## T1 — Tiles & biome art (generate first)

### T1.0 — Shared block/crack art (all biomes use these)

| Asset | File | Canvas | Status | Driven by | Notes |
|---|---|---|---|---|---|
| Master palette | `art/palettes/mining_game.gpl` | — | exists | `data/palette.json` | 15 colors, locked |
| Crack-stage overlay set | `art/fx/tile_crack_{stage}.png` | 16×16 ×N | placeholder (procedural in `block_art.gd`) | AC-5.2.5 | Shared across every tile type + biome. Author the final set; replaces procedural. |

### T1.1 — Surface mine (pair 1)

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Dirt tile ×3 variants | `art/biome/surface/tile_dirt_{01-03}.png` | 16×16 | needed | `block_types.json:dirt`, `art_sources.json` |
| Rock tile ×3 | `art/biome/surface/tile_rock_{01-03}.png` | 16×16 | needed | `block_types.json:rock` |
| Hard rock tile ×3 | `art/biome/surface/tile_hard_rock_{01-03}.png` | 16×16 | needed | `block_types.json:hard_rock` |
| Coal ore tile ×3 | `art/biome/surface/tile_coal_{01-03}.png` | 16×16 | needed | `block_types.json:coal` (reskinned per biome) |
| Copper ore tile ×3 | `art/biome/surface/tile_ore_copper_{01-03}.png` | 16×16 | needed | `block_types.json:ore_copper` |
| Silver ore tile ×3 | `art/biome/surface/tile_ore_silver_{01-03}.png` | 16×16 | needed | `block_types.json:ore_silver` |
| Gold ore tile ×3 | `art/biome/surface/tile_ore_gold_{01-03}.png` | 16×16 | needed | `block_types.json:ore_gold` |
| Gem ore tile ×3 | `art/biome/surface/tile_ore_gem_{01-03}.png` | 16×16 | needed | `block_types.json:ore_gem` |
| Diamond ore tile ×3 | `art/biome/surface/tile_diamond_{01-03}.png` | 16×16 | needed | `block_types.json:diamond` |
| Relic tile (Ancient Relic) | `art/biome/surface/tile_relic.png` | 16×16 | needed | `block_types.json:relic` |
| BG far (sky) | `art/biome/surface/bg_far.png` | 256×256 | placeholder (`sky.png`) | parallax far layer |
| BG mid (cave) | `art/biome/surface/bg_mid.png` | 256×256 | needed | parallax mid layer |
| BG near (shaft wall) | `art/biome/surface/bg_near.png` | 16×256 | needed | parallax near layer, tileable |
| Particle ramp | `art/biome/surface/ramp_particles.png` | 256×8 | needed | explosion/debris color falloff |
| Depth fade ramp | `art/biome/surface/ramp_depth.png` | 256×8 | needed | atmosphere fade |
| Surface frame decor | `art/biome/surface/decor_surface_frame.png` | 256×32 | needed | grass line at mine top |
| Mine-select card | `art/biome/surface/card_mine.png` | 128×96 | placeholder (`mine_select.gd`) | mine-select thumbnail |
| Relic portrait (Ancient Relic) | `art/biome/surface/relic_ancient_portrait.png` | 64×64 | needed | relic-find reveal + codex |

### T1.2 — Coal mine (pair 1)

Same asset set as Surface, Coal-themed (darker, sooty, black seams):
- `tile_dirt_{01-03}.png`, `tile_rock_{01-03}.png`, `tile_hard_rock_{01-03}.png` (coal-hardened)
- `tile_coal_{01-03}.png`, `tile_ore_copper_{01-03}.png`, `tile_ore_silver_{01-03}.png`, `tile_ore_gold_{01-03}.png`, `tile_ore_gem_{01-03}.png`, `tile_diamond_{01-03}.png` (reskinned)
- `tile_relic.png` (Coalheart)
- `bg_far.png`, `bg_mid.png`, `bg_near.png`, `ramp_particles.png`, `ramp_depth.png`
- `card_mine.png`, `relic_coalheart_portrait.png`

**Status:** all needed.

### T1.3 — Copper mine (pair 2)
### T1.4 — Quartz mine (pair 2)
### T1.5 — Silver mine (pair 3)
### T1.6 — Gold mine (pair 3)
### T1.7 — Diamond mine (pair 4)
### T1.8 — Abyss mine (pair 4, capstone — most distinct)

Each has the same asset set as Surface, biome-themed. Abyss is the capstone: near-black bg,
bioluminescent ores, unique particle ramps, most distinct relic.

**Status:** all needed. Phased: pairs 2–4 generate after pair 1 is `done`.

**Biome art subtotal:** ~18 assets × 8 mines = ~144 biome assets. Delivered in 4 pairs.

---

## T2 — Charges & crates (generate second)

### T2.1 — Charge in-world sprites (18)

| Charge | Rarity | File (sprite) | File (icon) | Canvas | Status |
|---|---|---|---|---|---|
| Scrap Charge (free) | common | `sprite_charge_free_charge.png` | `icon_charge_free_charge.png` | 16×16 / 24×24 | placeholder (`charge.png`) |
| Dynamite | common | `sprite_charge_dynamite.png` | `icon_charge_dynamite.png` | 16×16 / 24×24 | placeholder |
| Cluster Bomb | common | `sprite_charge_cluster_bomb.png` | `icon_charge_cluster_bomb.png` | 16×16 / 24×24 | placeholder |
| Shaped Charge | common | `sprite_charge_shaped_charge.png` | `icon_charge_shaped_charge.png` | 16×16 / 24×24 | needed |
| Concussion | common | `sprite_charge_concussion.png` | `icon_charge_concussion.png` | 16×16 / 24×24 | needed |
| Sticky Charge | uncommon | `sprite_charge_charge_sticky.png` | `icon_charge_charge_sticky.png` | 16×16 / 24×24 | placeholder |
| Drill Charge | uncommon | `sprite_charge_drill_charge.png` | `icon_charge_drill_charge.png` | 16×16 / 24×24 | placeholder |
| Napalm | uncommon | `sprite_charge_napalm.png` | `icon_charge_napalm.png` | 16×16 / 24×24 | needed |
| Frost Charge | uncommon | `sprite_charge_frost_charge.png` | `icon_charge_frost_charge.png` | 16×16 / 24×24 | needed |
| Heavy Bomb | rare | `sprite_charge_heavy_bomb.png` | `icon_charge_heavy_bomb.png` | 16×16 / 24×24 | placeholder |
| Pile Driver | rare | `sprite_charge_pile_driver.png` | `icon_charge_pile_driver.png` | 16×16 / 24×24 | placeholder |
| Sonic Charge | rare | `sprite_charge_sonic_charge.png` | `icon_charge_sonic_charge.png` | 16×16 / 24×24 | needed |
| Gravity Well | rare | `sprite_charge_gravity_well.png` | `icon_charge_gravity_well.png` | 16×16 / 24×24 | needed |
| Bunker Buster | epic | `sprite_charge_bunker_buster.png` | `icon_charge_bunker_buster.png` | 16×16 / 24×24 | needed |
| Nano Drill | epic | `sprite_charge_nano_drill.png` | `icon_charge_nano_drill.png` | 16×16 / 24×24 | needed |
| Volcano Charge | epic | `sprite_charge_volcano_charge.png` | `icon_charge_volcano_charge.png` | 16×16 / 24×24 | needed |
| Black Hole | legendary | `sprite_charge_black_hole.png` | `icon_charge_black_hole.png` | 16×16 / 24×24 | needed |
| Singularity | legendary | `sprite_charge_singularity.png` | `icon_charge_singularity.png` | 16×16 / 24×24 | needed |

Files live in `art/entities/` (sprites) + `art/ui/` (icons).

### T2.2 — Tier glyphs (5)

| Glyph | File | Canvas | Status |
|---|---|---|---|
| common ◇ | `art/ui/glyph_tier_common.png` | 16×16 | needed |
| uncommon ◆ | `art/ui/glyph_tier_uncommon.png` | 16×16 | needed |
| rare ★ | `art/ui/glyph_tier_rare.png` | 16×16 | needed |
| epic ✦ | `art/ui/glyph_tier_epic.png` | 16×16 | needed |
| legendary ☀ | `art/ui/glyph_tier_legendary.png` | 16×16 | needed |

### T2.3 — Crate art (7)

| Crate | File | Canvas | Status | Price |
|---|---|---|---|---|
| Rusty Crate | `art/ui/crate_rusty.png` | 32×32 | placeholder | 50g |
| Miner's Kit | `art/ui/crate_miners_kit.png` | 32×32 | needed | 120g |
| Deep Pack | `art/ui/crate_deep.png` | 32×32 | placeholder | 200g |
| Prospector's Box | `art/ui/crate_prospectors.png` | 32×32 | needed | 400g |
| Heavy Crate | `art/ui/crate_heavy.png` | 32×32 | placeholder | 650g |
| Vault Crate | `art/ui/crate_vault.png` | 32×32 | needed | 1200g |
| Legendary Cache | `art/ui/crate_legendary.png` | 32×32 | needed | 3000g |

### T2.4 — Crate open animation (shared, recolored)

| Asset | File | Canvas | Frames | Status |
|---|---|---|---|---|
| Crate open keyframes | `art/fx/anim_crate_open_{01-08}.png` | 64×64 | 8 | needed |

One shared animation sequence; recolored per crate at runtime (palette swap). 8 keyframes + Aseprite
tweens.

**T2 subtotal:** 18 sprites + 18 icons + 5 glyphs + 7 crates + 8 anim frames = ~56 assets.

---

## T3 — UI (generate third)

### T3.1 — HUD icons

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Money icon | `art/ui/icon_money.png` | 16×16 | exists | `hud.gd` |
| Depth icon | `art/ui/icon_depth.png` | 16×16 | exists | `hud.gd` |
| Relic icon | `art/ui/icon_relic.png` | 16×16 | exists | `hud.gd` |
| Prestige icon | `art/ui/icon_prestige.png` | 16×16 | needed | AC-5.6.6 |
| Nav menu icon | `art/ui/icon_nav_menu.png` | 24×24 | placeholder | `hud.gd`, AC-5.8.1 |
| Throw button icon | `art/ui/icon_throw.png` | 32×32 | placeholder | `throw_button.gd` |

### T3.2 — Setting icons

| Asset | File | Canvas | Status |
|---|---|---|---|
| Motion/shake | `art/ui/icon_setting_motion.png` | 16×16 | needed |
| Text scale | `art/ui/icon_setting_textscale.png` | 16×16 | needed |
| SFX volume | `art/ui/icon_setting_sfx.png` | 16×16 | needed |
| Music volume | `art/ui/icon_setting_music.png` | 16×16 | needed |
| Credits | `art/ui/icon_credits.png` | 16×16 | needed |

### T3.3 — Panel 9-slices

| Asset | File | Canvas | Status |
|---|---|---|---|
| Frame 9-slice | `art/ui/panel_9slice_frame.png` | 16×16 | needed |
| Inset 9-slice | `art/ui/panel_9slice_inset.png` | 16×16 | needed |
| Button normal | `art/ui/panel_9slice_button_normal.png` | 16×16 | needed |
| Button hover | `art/ui/panel_9slice_button_hover.png` | 16×16 | needed |
| Button pressed | `art/ui/panel_9slice_button_pressed.png` | 16×16 | needed |

### T3.4 — Screen backdrops

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Prestige offer panel | `art/ui/bg_prestige_offer.png` | 480×320 | placeholder | `prestige_offer.gd`, AC-5.6.2 |
| Dig-end panel | `art/ui/bg_dig_end.png` | 480×640 | placeholder | `dig_end_panel.gd`, AC-5.8.4 |
| Mine-select backdrop | `art/ui/bg_mine_select.png` | 720×1280 | needed | `mine_select.gd` |

### T3.5 — Title screen

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Title logo | `art/ui/logo_title.png` | 512×256 | needed | title screen (G4) |
| Title bg | `art/ui/bg_title.png` | 256×256 (tiled) | needed | title screen |

### T3.6 — Onboarding hints (one-time, first dig)

| Asset | File | Canvas | Status |
|---|---|---|---|
| Hint: drag to aim | `art/ui/hint_drag_aim.png` | 128×64 | needed |
| Hint: throw button | `art/ui/hint_throw.png` | 128×64 | needed |
| Hint: tray select | `art/ui/hint_tray_select.png` | 128×64 | needed |
| Hint: buy pack | `art/ui/hint_buy_pack.png` | 128×64 | needed |

### T3.7 — Upgrade tree icons (DEFERRED — 24 nodes, names not yet locked)

| Asset | File | Canvas | Status |
|---|---|---|---|
| Upgrade icons ×24 | `art/ui/icon_upgrade_{id}.png` | 24×24 | needed (names deferred) |

**T3 subtotal:** ~6 HUD + 5 settings + 5 panels + 3 backdrops + 2 title + 4 hints + 24 upgrades =
~49 assets.

---

## T4 — Particles & FX (generate fourth)

### T4.1 — Particle textures

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Explosion particle | `art/fx/tex_particle_explosion.png` | 8×8 | exists | AC-5.9.1 |
| Debris particle | `art/fx/tex_particle_debris.png` | 8×8 | exists | AC-5.9.1 |
| Flash core | `art/fx/tex_flash_core.png` | 32×32 | exists | `explosion.tscn` |
| Shockwave ring | `art/fx/tex_shockwave_ring.png` | 64×64 | exists | `explosion.tscn` |
| Charge trail | `art/fx/tex_charge_trail.png` | 16×16 | needed | `charge_trail.tscn` |

### T4.2 — Gradient ramps

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Blast gradient ramp | `art/fx/ramp_blast.png` | 256×8 | needed | AGENTS: "ramps from master palette, in /particles" |
| Depth fade ramp (shared) | `art/fx/ramp_depth.png` | 256×8 | needed | atmosphere fade |

### T4.3 — Animation FX

| Asset | File | Canvas | Frames | Status | Driven by |
|---|---|---|---|---|---|
| Muzzle flash | `art/fx/anim_muzzle_flash_{01-04}.png` | 32×32 | 4 | needed | `muzzle_flash.tscn` |
| Relic glow pulse | `art/fx/anim_relic_pulse_{01-08}.png` | 32×32 | 8 | needed | `relic_pulse.tscn`, `relics.json` (1.6s loop) |
| Coin fly | `art/entities/anim_coin_fly_{01-04}.png` | 8×8 | 4 | needed | `coin_pickup.tscn`, AC-5.5.1 |

### T4.4 — Relic-find animation (shared glow + per-relic portrait)

| Asset | File | Canvas | Frames | Status |
|---|---|---|---|---|
| Relic glow burst (shared) | `art/fx/anim_relic_glow_{01-06}.png` | 64×64 | 6 | needed |
| Relic portrait cards ×9 | `art/biome/*/relic_*_portrait.png` | 64×64 | 1 each | needed (listed in T1 biome sections) |

### T4.5 — Run-end cinematic (final game only)

| Asset | File | Canvas | Frames | Status | Driven by |
|---|---|---|---|---|---|
| Ending cinematic keyframes | `art/fx/anim_ending_{01-12}.png` | 256×256 | 6–12 | needed (content deferred to U22) | AC-5.6.7 |

### T4.6 — Shaders

| Asset | File | Status | Driven by |
|---|---|---|---|
| Light radius shader | `shaders/light_radius.gdshader` | exists | `prestige.json:mining_torch` |

**T4 subtotal:** ~5 particles + 2 ramps + 4+8+4+6+12 anim frames + 9 portraits = ~50 assets.

---

## T5 — Entities (generate with T2/T4)

| Asset | File | Canvas | Status | Driven by |
|---|---|---|---|---|
| Platform / launcher rig | `art/entities/sprite_platform.png` | 64×48 | placeholder | `platform.tscn`, AC-5.7.1/5.3.9 |
| Player figure | `art/entities/sprite_player.png` | 24×32 | placeholder (`player.png`) | decorative |
| Shaft supports decor | `art/entities/decor_shaft_supports.png` | 16×64 | placeholder (`shaft_supports.gd`) | descent dressing |
| Elevator ramp decor | `art/entities/decor_elevator_ramp.png` | 16×64 | needed | `elevator_ramp.gd` |

**T5 subtotal:** 4 assets.

---

## Relic codex (G4 — in scope per your expansion)

| Asset | File | Canvas | Status |
|---|---|---|---|
| Codex backdrop | `art/ui/bg_codex.png` | 720×1280 | needed |
| Codex icon | `art/ui/icon_codex.png` | 16×16 | needed |
| Relic codex entries ×9 | (uses the relic portrait cards from T1/T4) | 64×64 | needed |

---

## Summary

| Tier | Class | Assets | Exists/placeholder | Needed |
|---|---|---|---|---|
| T1 | Tiles & biome art (8 mines, phased) | ~144 | ~10 (surface pair partial) | ~134 |
| T2 | Charges, glyphs, crates, crate anim | ~56 | ~10 | ~46 |
| T3 | UI (HUD, settings, panels, title, hints, upgrades) | ~49 | ~3 | ~46 |
| T4 | Particles, ramps, animation FX, ending cinematic | ~50 | ~4 | ~46 |
| T5 | Entities (platform, player, decor) | 4 | ~3 | 1 |
| — | Relic codex | ~3 | 0 | 3 |
| **Total** | | **~306** | **~30** | **~276** |

> The ~306 count is driven by: 8 biomes × ~18 biome assets, 18 charges × 2 (sprite+icon), 24
> upgrade icons (deferred), 7 crates, ~50 FX frames, 9 relic portraits. Phasing biome art in pairs
> keeps the first deliverable (Surface+Coal) to ~36 biome assets + the non-biome tiers.

---

## Attribution

Every generated asset gets an entry in `spec/ATTRIBUTIONS.md`:
- Tool (Aseprite AI key / SDXL-NIM / Nano Banana) + date
- "No claimed copyright" note
- Source prompt reference (from `art/PROMPTS.md`)

All current placeholder art (`player.png`, `sky.png`, runtime-drawn `charge_icon.gd` output, etc.)
is flagged for replacement — none of it ships in the final build.
