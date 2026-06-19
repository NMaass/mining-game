# STYLE.md — Pixel-art style contract

> The cohesion lever that a shared palette alone can't provide. Every generated and hand-authored
> asset in this repo conforms to this document. `tools/validate_art.py` enforces the machine-checkable
> rules; Aseprite cleanup enforces the rest. When an asset and this file disagree, this file wins.
>
> **Status:** v1.0 (2026-06-19). Decisions locked via the art-planning interview. Amend via a PR that
> updates this file AND `tools/validate_art.py` together — the contract and the gate are a pair.

---

## 1. Tone & reference

- **Tone:** **Diggin cheerful/bright.** Saturated, readable, high-contrast, playful. Bright palette
  leans optimistic; material identity is clear at a glance.
- **Structural reference:** Motherload (vertical arcade-mining cross-section, chunky blocks, compact
  instrument HUD). SPEC §1 / AGENTS name Motherload as the primary *feel* reference; the *tone* leans
  Diggin-brighter. Structure from Motherload, saturation from Diggin.
- **NOT the target:** gritty/industrial, muddy, atmospheric-dark, photo-real, or high-detail 32-bit.
  If a generated asset reads as "moody cave" it fails the tone contract.

## 2. Master palette (LOCKED)

- **15 colors**, defined in `data/palette.json` and exported as `art/palettes/mining_game.gpl`
  (Aseprite-native).
- Colorblind-safe (Wong 2011 + Paul Tol hues), luminance-spread (the data gate enforces pairwise
  luminance contrast between block colors — hue alone never carries identity).
- **Every generated asset SHALL quantize to these 15 colors** (transparent pixels exempt). Sourced
  packs are exempt from strict quantization (AGENTS); force-quantizing them destroys their ramps.
- Index map (palette_index → hex → role):

| idx | hex | role in game |
|---|---|---|
| 0 | `#0e1116` | outline / frame / darkest shadow |
| 1 | `#3d2e20` | deep earth / coal shadow |
| 2 | `#7a5530` | dark wood / coal body |
| 3 | `#d4a36a` | dirt / wood / warm mid |
| 4 | `#4a9080` | teal accent / napalm / uncommon tier |
| 5 | `#c8d0d8` | metal / silver / light rock |
| 6 | `#5a6a7a` | shadow metal / hard rock |
| 7 | `#1c1a22` | void / abyss / darkest fill |
| 8 | `#4a9fd0` | blue accent / frost / crystal |
| 9 | `#e06020` | orange accent / copper / warm charge |
| 10 | `#7ad0f0` | cyan accent / ice / bright ore |
| 11 | `#ffe066` | yellow / gold / common-tier glow |
| 12 | `#ff5fd0` | magenta / gem / epic-tier |
| 13 | `#d8f4ff` | diamond / brightest highlight |
| 14 | `#e0a0fc` | purple / relic / legendary-tier |

## 3. Canvas & resolution

| Asset class | Source canvas (px) | Render size (px) | Notes |
|---|---|---|---|
| **Block / ore / relic tiles** | 16×16 | 32×32 (2×) | 1 tile = 1 block cell. Render `cell_px=32` is the canonical value in `/data`. |
| **Crack-stage overlay tiles** | 16×16 | 32×32 | Same canvas as base tiles; composited via the overlay TileMapLayer. |
| **Charge in-world sprites** | 16×16 | 32×32 (2×) | Body silhouette; distinct from tray icon. |
| **Charge tray icons** | 24×24 | 48×48 (2×) | Hit-target-friendly; tier glyph overlaid. |
| **Upgrade / setting / HUD icons** | 16×16 | 32×32 (2×) | Crisp at HUD scale. |
| **Coin pickup** | 8×8 | 16×16 (2×) | Tiny cosmetic; 4 frames. |
| **Particles (explosion, debris, flash, ring, trail, muzzle)** | 8–32×8–32 | as-is | See class table below. |
| **Platform / launcher rig** | 64×48 | 128×96 (2×) | Reads as a rig, not a lid (AC-5.3.9). |
| **Player figure** | 24×32 | 48×64 (2×) | Decorative; sits on/near platform. |
| **Panel 9-slice corners** | 16×16 | scales | Center + edges tileable. |
| **Backgrounds (sky, shaft walls, biome bgs)** | 256×256 | scales (tiled) | Textured parallax layers — see §7. |
| **Mine-select cards** | 128×96 | scales | Biome thumbnail + tint. |
| **Relic portrait cards** | 64×64 | 128×128 (2×) | For relic-find reveal + codex. |
| **Title logo** | 512×256 | scales | One-off signature asset. |

- **Nearest-neighbor** is the ONLY allowed downscale/upscale filter. Never bilinear, never bicubic
  (those introduce anti-aliasing that violates §5).
- Aseprite source files (`.aseprite`) are canonical; exported PNGs are derived. Never edit the PNG
  directly — edit the `.aseprite` and re-export.

## 4. Light direction

- **Light comes from the top-left.** Top and left edges are lit; bottom and right edges are
  shadowed. This is already encoded in `scripts/core/block_art.gd::_fill_block_cell` (bevel:
  top/left = `base.lightened(0.18)`, bottom/right = `base.darkened(0.28)`).
- Every generated asset SHALL be shaded top-left lit. A prompt that omits light direction is
  incomplete; `art/PROMPTS.md` pins it in every row.
- Shadows are flat (single shadow color), not soft. No gradient shadows, no ambient occlusion.

## 5. Outline & frame rules

- **Entity sprites + icons:** 1px dark outline in palette index 0 (`#0e1116`) around the silhouette.
  The outline separates the sprite from any background. No 2px outlines, no colored outlines.
- **Block / ore / relic tiles:** 1px dark frame on the tile border (already in `_fill_block_cell`:
  `frame = base.darkened(0.55)`). This separates adjacent same-type cells visually.
- **Backgrounds + panels:** no outline (they sit behind everything).
- **Particles:** no outline (they're additive/glow).

## 6. Shading & dithering

- **Dithering: NONE.** Anywhere. No Bayer, no Floyd-Steinberg, no noise dither. Gradients are hard
  color bands (see §7).
- **Shading is flat** with at most 3 tones per shape: base, lit (top-left), shadow (bottom-right).
  No soft shading, no smooth normals, no sub-pixel AA.
- **Highlights** are a single brighter palette color, applied to the top-left edge bevel only.
- **No anti-aliasing.** Every pixel is either fully opaque or fully transparent. Semi-transparent
  edge pixels (the classic AI pixel-art tell) MUST be removed in Aseprite cleanup and are rejected
  by `validate_art.py`.

## 7. Backgrounds (parallax)

- **Textured parallax layers** per biome. Each mine has:
  - A **far layer** (sky / surface backdrop, 256×256, slowest parallax).
  - A **mid layer** (cave walls / distant formations, 256×256, medium parallax).
  - A **near layer** (shaft walls immediately beside the mine, 16×256 tileable, fastest parallax).
- **No dithering in gradients.** Sky fades are 2–3 hard horizontal color bands (e.g. lightest band
  top, mid band middle, darkest band near the shaft opening).
- Each biome's 3 layers share the biome's particle ramp hue family so the depth reads cohesive.
- Parallax is implemented via Godot `ParallaxBackground` / `ParallaxLayer` nodes; the art is just
  the layer textures.

## 8. Non-color identity (accessibility, AC-5.10.2/5.10.3)

- **No information by color alone.** Every block type, ore type, and charge type SHALL carry a
  distinct **shape/texture** readable without hue.
- **Ore tiles:** each ore has a distinct inlay shape baked into the tile art (coal = chunks,
  copper = veins, silver = flecks, gold = nuggets, gem = faceted, diamond = crystalline). Shape is
  part of the tile texture, NOT a separate overlay layer (per the v0.5 arcade pass that removed the
  debug-grid glyph overlay).
- **Charge icons:** each charge has a distinct silhouette (dynamite = stick, sticky = blob + spike,
  heavy bomb = sphere + fuse, etc.) PLUS a tier glyph (§9).
- **Block tiles:** material identity (dirt vs rock vs hard_rock) rides texture, not just hue.
- `validate_art.py` enforces pairwise luminance contrast between block colors (extends the existing
  `data_validator` rule); shape identity is verified by the human Verifier-E pass.

## 9. Rarity & tier glyphs

- 5 rarity tiers, each with a **non-color glyph** (shape, not hue) so rarity reads without color:

| tier | glyph | shape | palette accent |
|---|---|---|---|
| common | ◇ | thin diamond | index 5 (`#c8d0d8`) |
| uncommon | ◆ | filled diamond | index 4 (`#4a9080`) |
| rare | ★ | 4-point star | index 8 (`#4a9fd0`) |
| epic | ✦ | 6-point sparkle | index 12 (`#ff5fd0`) |
| legendary | ☀ | radiant sun | index 11 (`#ffe066`) |

- Glyph is overlaid on the charge icon (bottom-right corner, 6×6 px at 24×24 icon canvas).
- The glyph PNGs live in `art/ui/glyph_tier_{tier}.png` (5 files, 16×16 each).

## 10. HUD density

- **Compact instrument HUD** (SPEC AC-5.8.1): minimal top bar + bottom tray only.
  - **Top-left:** money (icon + number) + depth (icon + number) + relic progress (icon + pips).
  - **Top-right:** nav button (≡).
  - **Bottom:** charge tray (horizontal scroll) + throw button.
  - **Depth resource-odds readout:** compact, below the top bar; updates per band (AC-5.8.8).
- No side rails, no stat panels, no minimap. Maximum play field.
- Numbers reflow/abbreviate at max UI text scale (AC-5.8.6).
- Bottom controls sit above the device home-indicator/gesture zone (AC-5.8.5).

## 11. Animation rules

- **AI generates keyframes; Aseprite tweens between.** Image-model frame consistency is unreliable,
  so AI is used for 2–3 keyframes per animation and a human fills in-betweens with onion-skinning.
- **Frame counts:** 2–4 frames for tiny FX (muzzle flash, coin fly); 4–8 frames for reveals (crate
  open, relic find); 6–12 frames for cinematics (run-end).
- **All animation frames share the same palette + outline + light rules** as static art. No frame
  introduces a new color or changes light direction.
- Export as individual PNGs per frame (not sprite sheets) — matches the individual-PNG pipeline and
  simplifies `validate_art.py`. Godot `AnimatedSprite2D` loads the frame list.

## 12. Generation pipeline

1. **Aseprite AI key** is the primary generation tool (in-editor generation → editable layers).
2. **SDXL via NVIDIA NIM** and **Nano Banana (Gemini 2.5 Flash Image) via Gemini API** are backups
   for when Aseprite AI struggles or for batch ideation.
3. Every asset goes through: **generate → nearest-neighbor downscale to target canvas → Aseprite
   indexed-color cleanup (master palette) → strip orphan pixels + semi-transparent edges →
   `tools/validate_art.py` → commit only if green.**
4. The `.aseprite` source is committed alongside the exported `.png` (canonical source per AGENTS).
5. Every AI-generated asset is logged in `spec/ATTRIBUTIONS.md` with tool + date + "no claimed
   copyright" note (AGENTS AI-art policy).

## 13. File organization

```
art/
├── biome/              # Per-mine biome art (phased in pairs)
│   ├── surface/        # tiles, bg layers, particle ramps, relic, select card
│   ├── coal/
│   ├── copper/
│   ├── quartz/
│   ├── silver/
│   ├── gold/
│   ├── diamond/
│   └── abyss/          # capstone mine; most distinct
├── entities/           # Platform, player, charge in-world sprites, coin pickup
├── fx/                 # Particles, gradient ramps, charge trail, muzzle flash, shockwave
├── ui/                 # Icons, tier glyphs, panel 9-slices, crate art, hint overlays, title logo
├── fonts/              # PixelifySans.ttf (OFL, exists)
├── palettes/           # mining_game.gpl (Aseprite palette, exists)
└── STYLE.md            # this file
```

- Each asset directory holds `.aseprite` sources + exported `.png`s side by side.
- **Naming convention:** `{class}_{id}_{variant}.png` — e.g. `tile_surface_dirt_01.png`,
  `icon_charge_dynamite.png`, `bg_surface_far.png`, `ramp_blast.png`, `relic_ancient.png`.

## 14. Verification (the gate)

`tools/validate_art.py` runs in CI and rejects any PNG in `art/` that fails:

1. **Dimensions** match the contract for its class (§3).
2. **Color count** ≤ 15 non-transparent colors, all from `data/palette.json`.
3. **Transparency** — only fully transparent (alpha=0) or fully opaque (alpha=255) pixels. No
   semi-transparent edges.
4. **Luminance contrast** — block/ore tiles differ from adjacent types by ≥ the data-gate threshold.
5. **Tile seam check** — tileable assets (tiles, bg layers) have matching left/right and top/bottom
   edges.
6. **No orphan pixels** — every non-transparent pixel has a non-transparent 4-neighbor (isolated 1px
   specks = AI noise).
7. **Outline check** — entity sprites/icons have a 1px dark frame on the bounding-box edge.

Plus in-engine (headless Godot, extends `tools/screenshot.gd`):

8. **Screenshot baselines** — one per biome + one per UI screen; new art regenerates baselines after
   review.
9. **Atlas consumption** — `block_art.gd` loads the new atlas; `test_level_smoke.gd` asserts no
   magenta fallback tiles render.
10. **Particle COLOR-set** — `tools/screenshot_blast.gd` asserts particles render (web-renderer gate,
    AC-5.9.1).

Plus **Verifier-E** (human, per ROADMAP §V — never claimed green by an agent):

11. CVD simulation on the final palette read.
12. 60 fps on device with new art (extend the perf benchmark scene).
13. Real-thumb hit-targets (do icons read at 44–48px on a real phone?).
14. The feel gate — "reads as a Diggin-bright Motherload-adjacent mine."

## 15. What NOT to do

- No dithering, anywhere.
- No anti-aliasing, anywhere.
- No semi-transparent edge pixels.
- No colors outside the 15-color master palette (in generated/recolored art).
- No 2px or colored outlines.
- No soft shadows, no gradient shadows, no ambient occlusion.
- No frame-by-frame sprite-sheet explosions (explosions are particles — AGENTS).
- No per-tile damage art (crack overlay is shared — AGENTS).
- No generated art on the signature/marketable surface (title logo) without hand-authoring pass
  (AGENTS AI-art policy).
- No asset ships without an `ATTRIBUTIONS.md` entry.
- No asset ships without passing `validate_art.py`.
