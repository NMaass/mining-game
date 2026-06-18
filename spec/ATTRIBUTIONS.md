# ATTRIBUTIONS

## Kevin's Mom's House - Mine pico-platformer tileset

- **Asset:** `Mine.png` from *Mine pico-platformer tileset*
- **Source:** https://kevins-moms-house.itch.io/mine-pico-platformer-tileset
- **Author:** Kevin's Mom's House
- **Downloaded:** 2026-06-15
- **License:** LicenseRef-KevinsMomsHouse-Permissive. The itch.io page states that project use is allowed and credit is appreciated but not required.
- **Commercial use:** Allowed by the page terms.
- **Share-alike / copyleft:** No share-alike requirement indicated on the page.
- **No generative AI:** The itch.io metadata marks the asset as no generative AI.
- **Project use:** Terrain/material tiles are sampled into the runtime block atlas through `data/art_sources.json`; the original sourced PNG is preserved under `art/source/`. A derived, brighter color grade is exported to `art/runtime/Mine_Bright.png` via `tools/process_tileset.py`.

## Placeholder art (generated in-engine)

- **Assets:** `art/runtime/player.png`, `art/runtime/sky.png`
- **Author:** Generated programmatically via Pillow from the project master palette (`data/palette.json`) for vertical-slice placeholder use.
- **Generated:** 2026-06-17
- **Tool:** Python Pillow script (one-off, not shipped).
- **License:** No claimed copyright; placeholder assets intended for replacement before release.
- **Project use:** Temporary 8-bit-style player sprite and sky gradient used until final art is authored.
