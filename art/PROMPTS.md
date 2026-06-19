# PROMPTS.md — AI generation prompt sheet

> Generation driver for every art asset. Primary tool: **Retro Diffusion** (Aseprite AI plugin)
> with palette-lock to `art/palettes/mining_game.gpl`. Backup: SDXL via NVIDIA NIM, Nano Banana via
> Gemini API. Every asset follows the shared style prefix (§1) + the per-asset prompt (§3).
>
> **Workflow per asset:** load palette in Aseprite → run Retro Diffusion with the prompt →
> nearest-neighbor downscale to target canvas (if generated larger) → Aseprite indexed-mode cleanup
> (strip orphan pixels, fix AA edges, enforce outline) → export PNG → run `tools/validate_art.py`
> → commit only if green → log in `spec/ATTRIBUTIONS.md`.
>
> **Priority order:** T1 tiles → T2 charges → T3 UI → T4 particles → T5 screens.

---

## 1. Shared style prefix (prepend to every prompt)

```
pixel art, {CANVAS}px, cheerful bright Diggin-style mining game, top-left lighting,
flat shading 3 tones (base, lit top-left, shadow bottom-right), 1px dark outline {OUTLINE_RULE},
no dithering, no anti-aliasing, no soft shadows, no gradient shadows, no ambient occlusion,
transparent background, palette-locked to 15 colors, side-view cross-section
```

**Where:**
- `{CANVAS}` = the asset's source canvas (16, 24, 32, 64, 128, 256, 512)
- `{OUTLINE_RULE}` = `around silhouette` for sprites/icons; `frame on tile border` for tiles; `none` for backgrounds/particles

## 2. Shared negative prompt (append to every prompt)

```
blurry, smooth, anti-aliased, gradient, soft shadow, ambient occlusion, 3d render,
photorealistic, high detail, 32-bit, dithering, noise, semi-transparent edges,
more than 15 colors, muddy, dark, moody, gritty, industrial, cinematic, bokeh,
text, watermark, signature, frame border, checkerboard
```

## 3. Shared palette (paste into palette-lock or prompt)

```
#0e1116 #3d2e20 #7a5530 #d4a36a #4a9080 #c8d0d8 #5a6a7a #1c1a22
#4a9fd0 #e06020 #7ad0f0 #ffe066 #ff5fd0 #d8f4ff #e0a0fc
```

---

## T1 — Tiles & biome art

### T1.0 — Shared crack overlay

| Asset | Canvas | Prompt (after prefix) | Notes |
|---|---|---|---|
| `tile_crack_01` | 16×16 | `crack overlay stage 1, single diagonal fracture across a square block, dark cracks with light halo, minimal` | Stage 1: one crack. Monotonic — later stages keep + add. |
| `tile_crack_02` | 16×16 | `crack overlay stage 2, branching fractures, shattered look, darker than stage 1` | Keeps stage 1 + adds. |
| `tile_crack_03` | 16×16 | `crack overlay stage 3, heavy damage, many branching cracks, darkest stage` | Maximum visible damage. |

### T1.1 — Surface mine tiles

> **Biome theme:** Surface. Warm dirt, grass-touched top, standard rock. Brightest mine. Reads as
> "fresh dig start." Top-left lit, 1px dark frame on each tile, tileable edges.

| Asset | Canvas | Prompt (after prefix) | Notes |
|---|---|---|---|
| `tile_dirt_01` | 16×16 | `dirt block, warm brown soil, chunky texture, small pebbles, top edge lighter (grass-touched), bottom edge darker, tileable` | Variant 1 of 3. |
| `tile_dirt_02` | 16×16 | `dirt block, warm brown soil, slightly different pebble arrangement, tileable` | Variant 2 — break monotony. |
| `tile_dirt_03` | 16×16 | `dirt block, warm brown soil, small root or stone fragment, tileable` | Variant 3. |
| `tile_rock_01` | 16×16 | `rock block, light grey stone, cracked surface texture, chunky, tileable` | Common rock. |
| `tile_rock_02` | 16×16 | `rock block, light grey stone, different crack pattern, tileable` | Variant 2. |
| `tile_rock_03` | 16×16 | `rock block, light grey stone, small crystal fleck, tileable` | Variant 3. |
| `tile_hard_rock_01` | 16×16 | `hard rock block, dark grey-blue stone, dense cracked texture, very chunky, tileable` | Harder than rock. |
| `tile_hard_rock_02` | 16×16 | `hard rock block, dark grey-blue stone, different crack pattern, tileable` | Variant 2. |
| `tile_hard_rock_03` | 16×16 | `hard rock block, dark grey-blue stone, compact pressure lines, tileable` | Variant 3. |
| `tile_coal_01` | 16×16 | `coal ore block, black chunks embedded in dark brown rock, shiny black inclusions, tileable` | Ore shape: chunks. |
| `tile_coal_02` | 16×16 | `coal ore block, different chunk arrangement, tileable` | Variant 2. |
| `tile_coal_03` | 16×16 | `coal ore block, larger coal seam, tileable` | Variant 3. |
| `tile_ore_copper_01` | 16×16 | `copper ore block, orange-copper veins running through light rock, metallic sheen on veins, tileable` | Ore shape: veins. |
| `tile_ore_copper_02` | 16×16 | `copper ore block, different vein pattern, tileable` | Variant 2. |
| `tile_ore_copper_03` | 16×16 | `copper ore block, thicker copper vein, tileable` | Variant 3. |
| `tile_ore_silver_01` | 16×16 | `silver ore block, bright silver flecks scattered in grey rock, shiny spots, tileable` | Ore shape: flecks. |
| `tile_ore_silver_02` | 16×16 | `silver ore block, different fleck pattern, tileable` | Variant 2. |
| `tile_ore_silver_03` | 16×16 | `silver ore block, clustered silver flecks, tileable` | Variant 3. |
| `tile_ore_gold_01` | 16×16 | `gold ore block, yellow-gold nuggets embedded in warm rock, bright metallic lumps, tileable` | Ore shape: nuggets. |
| `tile_ore_gold_02` | 16×16 | `gold ore block, different nugget arrangement, tileable` | Variant 2. |
| `tile_ore_gold_03` | 16×16 | `gold ore block, larger gold nugget, tileable` | Variant 3. |
| `tile_ore_gem_01` | 16×16 | `gemstone ore block, magenta faceted crystal in dark rock, geometric cut, shiny, tileable` | Ore shape: faceted. |
| `tile_ore_gem_02` | 16×16 | `gemstone ore block, different facet angle, tileable` | Variant 2. |
| `tile_ore_gem_03` | 16×16 | `gemstone ore block, cluster of small gems, tileable` | Variant 3. |
| `tile_diamond_01` | 16×16 | `diamond ore block, bright cyan-white crystalline structure in dark rock, brilliant sparkle, tileable` | Ore shape: crystalline. |
| `tile_diamond_02` | 16×16 | `diamond ore block, different crystal angle, tileable` | Variant 2. |
| `tile_diamond_03` | 16×16 | `diamond ore block, larger diamond crystal, tileable` | Variant 3. |
| `tile_relic` | 16×16 | `relic core block, glowing purple-orange gem in dark stone, emits soft light, ornate carved frame, tileable` | Ancient Relic — surface mine. |

### T1.1 — Surface mine backgrounds

| Asset | Canvas | Prompt (after prefix, outline=none) | Notes |
|---|---|---|---|
| `bg_far` | 256×256 | `far parallax background, bright blue sky with 2 hard color bands fading to lighter horizon, cheerful surface mining scene, no details` | Far parallax layer. |
| `bg_mid` | 256×256 | `mid parallax background, distant cave entrance silhouette, warm earth tones, simple shapes, 2-3 color bands` | Mid parallax layer. |
| `bg_near` | 16×256 | `near parallax shaft wall, warm brown rock texture, vertical, tileable top-bottom, simple shading` | Near parallax, tileable. |
| `ramp_particles` | 256×8 | `gradient ramp, warm orange to dark brown, horizontal, 15-color palette, hard bands no dither` | Particle color falloff. |
| `ramp_depth` | 256×8 | `gradient ramp, light blue to dark earth, horizontal, hard bands no dither` | Atmosphere fade. |
| `decor_surface_frame` | 256×32 | `grass line and surface dirt frame, top of mine opening, green grass blades on brown dirt, cheerful` | Mine top decor. |

### T1.1 — Surface mine select card + relic portrait

| Asset | Canvas | Prompt (after prefix) | Notes |
|---|---|---|---|
| `card_mine` | 128×96 | `mine select card thumbnail, surface mine, bright blue sky above warm brown dirt cross-section, small platform silhouette at top, cheerful` | Mine-select thumbnail. |
| `relic_ancient_portrait` | 64×64 | `ancient relic, glowing purple gemstone in ornate gold frame, emits soft light, mysterious artifact, centered, dark background` | Relic-find reveal + codex. |

### T1.2–T1.8 — Other biome tiles

> **Copy the Surface tile prompt set** and replace the biome theme. The tile structure (dirt, rock,
> hard_rock, 6 ores, relic) is identical across biomes — only the theme keywords change. Each biome
> reskins the same 6 ores with biome-appropriate colors + textures.

| Biome | Theme keywords (replace in prompts) | Relic name |
|---|---|---|
| **Coal** | dark sooty black seams, coal dust, dim warm light, industrial | Coalheart |
| **Copper** | reddish-brown rock, copper-tinted earth, warm rust tones | Copper Idol |
| **Quartz** | white crystalline rock, bright reflective surfaces, pale tones | Quartz Crystal |
| **Silver** | cool grey-blue rock, metallic sheen, cold tones | Silver Chalice |
| **Gold** | warm yellow rock, golden veins everywhere, luxurious | Golden Crown |
| **Diamond** | deep dark rock with brilliant cyan crystals, high contrast | Diamond Eye |
| **Abyss** | near-black void, bioluminescent glowing ores, purple-cyan glow, most distinct, eerie | Abyssal Core |

> **Abyss (capstone) prompts add:** `near-black background, bioluminescent ores that emit their own
> glow, most visually distinct mine, eerie but still readable, capstone final mine`

---

## T2 — Charges & crates

### T2.1 — Charge in-world sprites (16×16) + tray icons (24×24)

> Each charge needs TWO generations: a 16×16 in-world sprite + a 24×24 tray icon. The icon is a
> cleaner, more readable version of the sprite. Both need a distinct silhouette + the tier glyph
> overlaid manually in Aseprite after generation.

| Charge | Rarity | Prompt (after prefix, outline=around silhouette) | Silhouette cue |
|---|---|---|---|
| free_charge | common | `scrap charge, makeshift bomb, rusty metal cylinder with orange fuse, cheap improvised look` | cylinder + fuse |
| dynamite | common | `dynamite stick, red-orange wrapped explosive with yellow fuse cord, classic bundle` | stick + fuse |
| cluster_bomb | common | `cluster bomb, three small orange bombs bundled together, fuses tangled` | 3 spheres |
| shaped_charge | common | `shaped charge, conical metal directional explosive, flat front cone back, orange accent stripe` | cone |
| concussion | common | `concussion charge, wide flat disc explosive, wide shallow blast profile, blue accent` | flat disc |
| charge_sticky | uncommon | `sticky charge, green blob bomb with suction spikes, adheres to surfaces, yellow band` | blob + spikes |
| drill_charge | uncommon | `drill charge, blue cylindrical charge with rotating drill tip, pointed nose, yellow accent` | cylinder + drill |
| napalm | uncommon | `napalm charge, canister with orange flame trail, burning liquid explosive, warm glow` | canister + flame |
| frost_charge | uncommon | `frost charge, blue ice bomb with crystalline surface, cold mist, freezes on impact` | ice crystal |
| heavy_bomb | rare | `heavy bomb, large dark metal sphere with yellow fuse, chunky weighty look, military` | big sphere |
| pile_driver | rare | `pile driver, purple cylindrical charge with heavy metal tip, concentrated force, downward` | cylinder + tip |
| sonic_charge | rare | `sonic charge, blue ring emitter, wave-like surface, skips rock targets ore only, energy` | ring emitter |
| gravity_well | rare | `gravity well charge, dark sphere with swirling ring, pulls collectibles inward, distortion` | sphere + ring |
| bunker_buster | epic | `bunker buster, elongated penetrating bomb with delayed fuse, punches through then detonates, military green` | elongated shell |
| nano_drill | epic | `nano drill, tiny precise blue drill charge, surgical single-cell intensity, high-tech` | tiny drill |
| volcano_charge | epic | `volcano charge, red-black bomb with lava cracks, erupts on detonation, molten glow` | lava bomb |
| black_hole | legendary | `black hole charge, dark void sphere with purple accretion ring, implodes on detonation, cosmic` | void + ring |
| singularity | legendary | `singularity charge, reality-bent sphere with distorted space, magenta-gold distortion, ultimate` | distorted sphere |

### T2.2 — Tier glyphs (16×16)

| Glyph | Prompt (after prefix, outline=around silhouette) |
|---|---|
| `glyph_tier_common` | `thin diamond outline shape, simple, 4-point, rarity marker, centered, minimalist` |
| `glyph_tier_uncommon` | `filled diamond shape, 4-point, solid, rarity marker, centered` |
| `glyph_tier_rare` | `4-point star shape, rarity marker, centered, bright` |
| `glyph_tier_epic` | `6-point sparkle star shape, rarity marker, centered, ornate` |
| `glyph_tier_legendary` | `radiant sun shape with rays, rarity marker, centered, majestic` |

### T2.3 — Crate icons (32×32)

| Crate | Prompt (after prefix, outline=around silhouette) |
|---|---|
| `crate_rusty` | `rusty wooden crate, old brown wood with rusted metal bands, cheap, worn, common tier` |
| `crate_miners_kit` | `miner's kit box, sturdy wood with metal corners, pickaxe icon on lid, uncommon tier` |
| `crate_deep` | `deep pack crate, reinforced dark wood with blue metal bands, heavy duty, deep mining` |
| `crate_prospectors` | `prospector's box, ornate wooden chest with gold trim, rare tier, treasure feel` |
| `crate_heavy` | `heavy crate, iron-bound wooden box with warning stripes, reinforced, rare tier` |
| `crate_vault` | `vault crate, metal safe box with purple accent, locked, epic tier, valuable` |
| `crate_legendary` | `legendary cache, ornate gold-and-purple chest, glowing, legendary tier, ultimate treasure` |

### T2.4 — Crate open animation (64×64, 8 keyframes)

| Frame | Prompt (after prefix, outline=none) |
|---|---|
| `anim_crate_open_01` | `closed wooden crate sitting on ground, intact, stationary` |
| `anim_crate_open_02` | `wooden crate shaking, slight wobble, dust particles rising` |
| `anim_crate_open_03` | `crate lid lifting, cracks of light escaping from inside, creaking` |
| `anim_crate_open_04` | `crate lid open halfway, bright light burst from inside, wood splinters` |
| `anim_crate_open_05` | `crate fully open, bright light explosion outward, contents revealed as silhouette` |
| `anim_crate_open_06` | `light fading, charge icons visible inside crate, sparkle particles` |
| `anim_crate_open_07` | `light gone, crate empty, items floating up, dust settling` |
| `anim_crate_open_08` | `empty crate, lid off, dust settled, items gone, aftermath` |

> Generate all 8 keyframes with the same composition/camera. Aseprite onion-skin tween between
> keyframes. Recolor per crate tier at runtime (palette swap).

---

## T3 — UI

### T3.1 — HUD icons

| Asset | Canvas | Prompt (after prefix, outline=around silhouette) |
|---|---|---|
| `icon_prestige` | 16×16 | `prestige star icon, bright gold star with radiant points, achievement marker, centered` |
| `icon_nav_menu` | 24×24 | `navigation menu icon, three horizontal lines hamburger menu, simple, clear` |
| `icon_throw` | 32×32 | `throw button icon, downward arrow with charge silhouette below, action button, bold` |

### T3.2 — Setting icons

| Asset | Canvas | Prompt (after prefix, outline=around silhouette) |
|---|---|---|
| `icon_setting_motion` | 16×16 | `motion icon, screen with vibration lines, shake indicator, simple` |
| `icon_setting_textscale` | 16×16 | `text scale icon, letter A with small and large arrows, size indicator` |
| `icon_setting_sfx` | 16×16 | `sfx volume icon, speaker with sound waves, audio effects, simple` |
| `icon_setting_music` | 16×16 | `music volume icon, speaker with musical note, audio music, simple` |
| `icon_credits` | 16×16 | `credits icon, open book or info circle, attribution, simple` |

### T3.3 — Panel 9-slices (16×16, tileable, no outline)

| Asset | Prompt (after prefix, outline=none) |
|---|---|
| `panel_9slice_frame` | `ui panel frame corner, dark border with lighter interior, 9-slice tileable, pixel art window frame` |
| `panel_9slice_inset` | `inset panel, recessed dark rectangle with lighter border, 9-slice tileable, slot background` |
| `panel_9slice_button_normal` | `button normal state, flat raised rectangle, medium tone, 9-slice tileable` |
| `panel_9slice_button_hover` | `button hover state, slightly brighter raised rectangle, 9-slice tileable` |
| `panel_9slice_button_pressed` | `button pressed state, darker inset rectangle, 9-slice tileable` |

### T3.4 — Screen backdrops

| Asset | Canvas | Prompt (after prefix, outline=none) |
|---|---|---|
| `bg_prestige_offer` | 480×320 | `prestige offer panel backdrop, dark purple gradient with ornate gold border, relic silhouette center, ceremonial` |
| `bg_dig_end` | 480×640 | `dig end panel backdrop, warm dark earth tones with relic glow center, achievement feel, ornate border` |
| `bg_mine_select` | 720×1280 | `mine select backdrop, dark cave wall with 8 mine card slots, ornate frame, hub feel` |
| `bg_codex` | 720×1280 | `relic codex backdrop, dark parchment with ornate border, 9 relic display slots, ancient book feel` |

### T3.5 — Title screen

| Asset | Canvas | Prompt (after prefix) |
|---|---|---|
| `logo_title` | 512×256 | `mining game title logo, bold pixel-art lettering with pickaxe and gem motifs, cheerful bright, gold and brown, centered` |
| `bg_title` | 256×256 | `title screen background, bright blue sky over warm brown mine cross-section, cheerful, simple, tileable` |

### T3.6 — Onboarding hints (128×64, no outline)

| Asset | Prompt (after prefix, outline=none) |
|---|---|
| `hint_drag_aim` | `onboarding hint, finger dragging to adjust aim angle, dotted arc showing trajectory, simple diagram on dark panel` |
| `hint_throw` | `onboarding hint, finger pressing throw button, downward arrow, simple diagram on dark panel` |
| `hint_tray_select` | `onboarding hint, finger tapping charge slot in tray, highlight on selected charge, simple diagram` |
| `hint_buy_pack` | `onboarding hint, finger tapping crate in shop, coin icon, simple diagram on dark panel` |

### T3.7 — Upgrade icons (24×24, outline) — NAMES DEFERRED

> When the 24-node upgrade tree is locked, generate one icon per node. Prompt template:
> `upgrade icon, {NODE_DESCRIPTION}, centered, simple, readable at small size`
> The 24 node descriptions come from the deferred upgrade tree design.

---

## T4 — Particles & FX

### T4.1 — Particle textures

| Asset | Canvas | Prompt (after prefix, outline=none) |
|---|---|---|
| `tex_charge_trail` | 16×16 | `charge trail particle, bright streak with fading tail, motion blur effect, simple` |

### T4.2 — Gradient ramps (256×8, tileable)

| Asset | Prompt (after prefix, outline=none) |
|---|---|
| `ramp_blast` | `gradient ramp, bright yellow to orange to dark red, horizontal, hard color bands, explosion color falloff` |
| `ramp_depth` | `gradient ramp, light blue to dark earth brown, horizontal, hard color bands, atmosphere depth fade` |

### T4.3 — Animation FX

| Asset | Canvas | Frames | Prompt per frame |
|---|---|---|---|
| `anim_muzzle_flash` | 32×32 | 4 | `muzzle flash frame {N}, bright spark burst at launch point, expanding flash, 4-frame sequence: tiny→burst→fade→gone` |
| `anim_relic_pulse` | 32×32 | 8 | `relic glow pulse frame {N}, soft purple glow expanding and contracting, 8-frame loop at 1.6s, steady pulse` |
| `anim_coin_fly` | 8×8 | 4 | `coin spin frame {N}, gold coin rotating, 4-frame spin cycle, shiny` |

### T4.4 — Relic-find animation

| Asset | Canvas | Frames | Prompt per frame |
|---|---|---|---|
| `anim_relic_glow` | 64×64 | 6 | `relic glow burst frame {N}, bright purple-white light explosion, expanding rays, 6-frame reveal sequence: charge→burst→radiate→fade` |

> Per-relic portrait cards are in T1 biome sections — each is a single 64×64 still, not animated.

### T4.5 — Run-end cinematic (256×256, 6-12 keyframes)

> Content deferred to U22. Prompt template (when content is locked):
> `ending cinematic frame {N}, {ENDING_SCENE_DESCRIPTION}, dramatic lighting, capstone moment, 6-12 keyframe sequence`

---

## T5 — Entities

| Asset | Canvas | Prompt (after prefix, outline=around silhouette) |
|---|---|---|
| `sprite_platform` | 64×48 | `mining platform launcher rig, chunky metal gantry with central launch slot, warning stripes, reads as a rig not a lid, wheels and support legs, side view` |
| `sprite_player` | 24×32 | `miner character, cheerful bright outfit with helmet, small pickaxe, standing pose, side view, Diggin-style cute proportions` |
| `decor_shaft_supports` | 16×64 | `shaft support beam, metal elevator rail with cross-braces, vertical, tileable, industrial mining infrastructure` |
| `decor_elevator_ramp` | 16×64 | `elevator ramp segment, metal track with gear teeth, vertical, tileable, descent mechanism` |

---

## Post-generation checklist (per asset)

1. [ ] Generated via Retro Diffusion (or backup: SDXL-NIM / Nano Banana)
2. [ ] Nearest-neighbor downscaled to target canvas (if generated larger)
3. [ ] Aseprite indexed-mode cleanup: master palette applied
4. [ ] Orphan pixels removed
5. [ ] Semi-transparent edge pixels removed (no AA)
6. [ ] 1px outline verified (sprites/icons) or 1px frame (tiles)
7. [ ] Tileable edges verified (tiles, bgs, ramps)
8. [ ] Tier glyph overlaid (charge icons only)
9. [ ] Exported as individual PNG to the correct `art/{class}/` path
10. [ ] `.aseprite` source saved alongside the PNG
11. [ ] `tools/validate_art.py` passes (exit 0)
12. [ ] Entry added to `spec/ATTRIBUTIONS.md` (tool + date + "no claimed copyright")
13. [ ] `art/ASSET_CHECKLIST.md` status updated to `done`
