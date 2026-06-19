#!/usr/bin/env python3
"""Art validation gate — enforces art/STYLE.md on every PNG in art/.

Exit 0 = all assets pass. Non-zero = at least one asset violates the style contract.
Wired into CI alongside tools/validate_data.sh.

Checks (per art/STYLE.md §14):
  1. Dimensions match the contract for the asset's class (by filename prefix).
  2. Color count <= 15 non-transparent colors, all from data/palette.json.
  3. Transparency — only fully transparent (alpha < 16) or fully opaque (alpha >= 240).
     Semi-transparent edge pixels (the AI pixel-art tell) are rejected.
  4. Luminance contrast — block/ore tiles differ from adjacent types by >= threshold.
  5. Tile seam check — tileable assets have matching left/right + top/bottom edges.
  6. No orphan pixels — every non-transparent pixel has a non-transparent 4-neighbor.
  7. Outline check — entity sprites/icons have a 1px dark frame on the bounding-box edge.

Usage:
  python3 tools/validate_art.py              # validate all art/
  python3 tools/validate_art.py --fix-report  # write a JSON report to reports/
  python3 tools/validate_art.py --only art/biome/surface/  # validate a subtree
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

from PIL import Image

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ART_DIR = PROJECT_ROOT / "art"
PALETTE_JSON = PROJECT_ROOT / "data" / "palette.json"
REPORT_DIR = PROJECT_ROOT / "reports"

# ── Palette ────────────────────────────────────────────────────────────────

def load_palette() -> List[Tuple[int, int, int]]:
    """Load the 15-color master palette from data/palette.json as RGB tuples."""
    with open(PALETTE_JSON) as f:
        data = json.load(f)
    hexes = data.get("colors", [])
    palette = []
    for h in hexes:
        h = h.lstrip("#")
        palette.append((int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)))
    return palette

PALETTE_RGB: List[Tuple[int, int, int]] = load_palette()
PALETTE_SET: Set[Tuple[int, int, int]] = set(PALETTE_RGB)
OUTLINE_COLOR = PALETTE_RGB[0]  # #0e1116 — the 1px outline color

# ── Asset class contract (art/STYLE.md §3) ──────────────────────────────────
# Maps filename prefix → (expected_dimensions, is_tileable, needs_outline)
# None dimension = skip dimension check (e.g. backgrounds scale).

@dataclass
class ClassRule:
    prefix: str
    dims: Optional[Tuple[int, int]]  # (w, h) or None to skip
    tileable: bool = False
    needs_outline: bool = False
    description: str = ""

CLASS_RULES: List[ClassRule] = [
    # Tiles (16×16, tileable, no outline — they have a frame not an outline)
    ClassRule("tile_", (16, 16), tileable=True, description="block/ore/relic tile"),
    ClassRule("tile_crack", (16, 16), tileable=True, description="crack-stage overlay"),
    # Charge in-world sprites (16×16, outline)
    ClassRule("sprite_charge_", (16, 16), needs_outline=True, description="charge in-world sprite"),
    # Charge tray icons (24×24, outline)
    ClassRule("icon_charge_", (24, 24), needs_outline=True, description="charge tray icon"),
    # Tier glyphs (16×16, outline)
    ClassRule("glyph_tier_", (16, 16), needs_outline=True, description="rarity tier glyph"),
    # HUD/setting icons (16×16 or 24×24, outline)
    ClassRule("icon_setting_", (16, 16), needs_outline=True, description="setting icon"),
    ClassRule("icon_upgrade_", (24, 24), needs_outline=True, description="upgrade node icon"),
    ClassRule("icon_", (16, 16), needs_outline=True, description="HUD icon"),
    # Nav/throw icons (24×24, outline)
    ClassRule("icon_nav", (24, 24), needs_outline=True, description="nav button icon"),
    ClassRule("icon_throw", (32, 32), needs_outline=True, description="throw button icon"),
    # Crate icons (32×32, outline)
    ClassRule("crate_", (32, 32), needs_outline=True, description="crate icon"),
    # Panel 9-slices (16×16, tileable, no outline)
    ClassRule("panel_9slice_", (16, 16), tileable=True, description="9-slice panel"),
    # Particle textures (variable, no outline, not tileable)
    ClassRule("tex_particle_", (8, 8), description="particle texture"),
    ClassRule("tex_flash_core", (32, 32), description="flash core"),
    ClassRule("tex_shockwave", (64, 64), description="shockwave ring"),
    ClassRule("tex_charge_trail", (16, 16), description="charge trail"),
    # Gradient ramps (256×8, tileable horizontally)
    ClassRule("ramp_", (256, 8), tileable=True, description="gradient ramp"),
    # Animation frames (variable by class)
    ClassRule("anim_muzzle_flash", (32, 32), description="muzzle flash frame"),
    ClassRule("anim_relic_pulse", (32, 32), description="relic pulse frame"),
    ClassRule("anim_coin_fly", (8, 8), needs_outline=True, description="coin fly frame"),
    ClassRule("anim_relic_glow", (64, 64), description="relic glow frame"),
    ClassRule("anim_crate_open", (64, 64), description="crate open frame"),
    ClassRule("anim_ending", (256, 256), description="ending cinematic frame"),
    # Entities
    ClassRule("sprite_platform", (64, 48), needs_outline=True, description="platform rig"),
    ClassRule("sprite_player", (24, 32), needs_outline=True, description="player figure"),
    ClassRule("decor_", None, description="decorative element"),
    # Relic portraits (64×64, outline)
    ClassRule("relic_", (64, 64), needs_outline=True, description="relic portrait"),
    # Mine-select cards (128×96)
    ClassRule("card_mine", (128, 96), description="mine-select card"),
    # Backgrounds (256×256 unless bg_near which is 16×256)
    ClassRule("bg_far", (256, 256), tileable=True, description="far parallax bg"),
    ClassRule("bg_mid", (256, 256), tileable=True, description="mid parallax bg"),
    ClassRule("bg_near", (16, 256), tileable=True, description="near parallax bg"),
    ClassRule("bg_", None, description="background/backdrop"),
    # Title logo (512×256)
    ClassRule("logo_", (512, 256), description="title logo"),
    # Hint overlays (128×64)
    ClassRule("hint_", (128, 64), description="onboarding hint"),
]

def match_rule(filename: str) -> Optional[ClassRule]:
    """Find the first class rule whose prefix matches the filename."""
    name = filename.lower()
    for rule in CLASS_RULES:
        if name.startswith(rule.prefix):
            return rule
    return None

# ── Violation ──────────────────────────────────────────────────────────────

@dataclass
class Violation:
    file: str
    check: str
    message: str

@dataclass
class ValidationResult:
    file: str
    passed: bool
    violations: List[Violation] = field(default_factory=list)

# ── Helpers ────────────────────────────────────────────────────────────────

def relative_luminance(c: Tuple[int, int, int]) -> float:
    """WCAG relative luminance (0..1) for an RGB tuple (0-255)."""
    def lin(ch: float) -> float:
        ch = ch / 255.0
        return ch / 12.92 if ch <= 0.04045 else ((ch + 0.055) / 1.055) ** 2.4
    return 0.2126 * lin(c[0]) + 0.7152 * lin(c[1]) + 0.0722 * lin(c[2])

def color_distance(a: Tuple[int, int, int], b: Tuple[int, int, int]) -> float:
    """Euclidean RGB distance."""
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))

def is_transparent(px: Tuple[int, int, int, int]) -> bool:
    return px[3] < 16

def is_opaque(px: Tuple[int, int, int, int]) -> bool:
    return px[3] >= 240

def nearest_palette_color(c: Tuple[int, int, int]) -> Tuple[int, int, int]:
    """Closest palette color by Euclidean RGB distance."""
    best = PALETTE_RGB[0]
    best_d = float("inf")
    for pc in PALETTE_RGB:
        d = color_distance(c, pc)
        if d < best_d:
            best_d = d
            best = pc
    return best

# ── Checks ─────────────────────────────────────────────────────────────────

def check_dimensions(img: Image.Image, rule: ClassRule) -> Optional[str]:
    if rule.dims is None:
        return None
    w, h = img.size
    if (w, h) != rule.dims:
        return f"dimensions {w}×{h}, expected {rule.dims[0]}×{rule.dims[1]}"
    return None

def check_palette_compliance(img: Image.Image) -> Optional[str]:
    """All non-transparent pixels must be in the 15-color master palette."""
    rgba = img.convert("RGBA")
    px = list(rgba.getdata())
    bad = []
    for p in px:
        if is_transparent(p):
            continue
        rgb = (p[0], p[1], p[2])
        if rgb not in PALETTE_SET:
            # Allow if it's very close (rounding tolerance)
            nearest = nearest_palette_color(rgb)
            if color_distance(rgb, nearest) > 10:  # tolerance for minor rounding
                bad.append(rgb)
    if bad:
        unique_bad = list(set(bad))[:5]
        return f"{len(bad)} pixels off-palette (e.g. {unique_bad}); must quantize to the 15-color master palette"
    return None

def check_transparency(img: Image.Image) -> Optional[str]:
    """No semi-transparent pixels (alpha between 16 and 240)."""
    rgba = img.convert("RGBA")
    px = list(rgba.getdata())
    bad_count = sum(1 for p in px if not is_transparent(p) and not is_opaque(p))
    if bad_count > 0:
        return f"{bad_count} semi-transparent pixels (anti-aliasing); only fully transparent or fully opaque allowed"
    return None

def check_orphan_pixels(img: Image.Image) -> Optional[str]:
    """No isolated 1px specks — every non-transparent pixel has a non-transparent 4-neighbor."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()
    orphans = 0
    for y in range(h):
        for x in range(w):
            if is_transparent(px[x, y]):
                continue
            neighbors = 0
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and not is_transparent(px[nx, ny]):
                    neighbors += 1
            if neighbors == 0:
                orphans += 1
    if orphans > 0:
        return f"{orphans} orphan pixels (isolated 1px specks); AI noise — remove in Aseprite cleanup"
    return None

def check_tile_seams(img: Image.Image) -> Optional[str]:
    """Tileable assets: left/right edges match, top/bottom edges match."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    if w < 2 or h < 2:
        return None
    px = rgba.load()
    mismatches = 0
    # Left vs right edge
    for y in range(h):
        lp = px[0, y]
        rp = px[w - 1, y]
        if is_transparent(lp) != is_transparent(rp) or (
            not is_transparent(lp) and color_distance((lp[0], lp[1], lp[2]), (rp[0], rp[1], rp[2])) > 5
        ):
            mismatches += 1
    # Top vs bottom edge
    for x in range(w):
        tp = px[x, 0]
        bp = px[x, h - 1]
        if is_transparent(tp) != is_transparent(bp) or (
            not is_transparent(tp) and color_distance((tp[0], tp[1], tp[2]), (bp[0], bp[1], bp[2])) > 5
        ):
            mismatches += 1
    if mismatches > 0:
        return f"{mismatches} seam mismatches (edges don't tile); must fix for tileable assets"
    return None

def check_outline(img: Image.Image) -> Optional[str]:
    """Entity sprites/icons: 1px dark outline on the bounding-box edge of the silhouette."""
    rgba = img.convert("RGBA")
    w, h = rgba.size
    px = rgba.load()

    # Find the bounding box of non-transparent pixels
    min_x, min_y, max_x, max_y = w, h, -1, -1
    for y in range(h):
        for x in range(w):
            if not is_transparent(px[x, y]):
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < 0:  # fully transparent
        return None

    # Check that the border pixels of the silhouette are dark (outline color or close)
    outline_dist_threshold = 40  # tolerance
    missing = 0
    total = 0
    # Top edge of bounding box
    for x in range(min_x, max_x + 1):
        p = px[x, min_y]
        if not is_transparent(p):
            total += 1
            if color_distance((p[0], p[1], p[2]), OUTLINE_COLOR) > outline_dist_threshold:
                missing += 1
    # Bottom edge
    for x in range(min_x, max_x + 1):
        p = px[x, max_y]
        if not is_transparent(p):
            total += 1
            if color_distance((p[0], p[1], p[2]), OUTLINE_COLOR) > outline_dist_threshold:
                missing += 1
    # Left edge
    for y in range(min_y, max_y + 1):
        p = px[min_x, y]
        if not is_transparent(p):
            total += 1
            if color_distance((p[0], p[1], p[2]), OUTLINE_COLOR) > outline_dist_threshold:
                missing += 1
    # Right edge
    for y in range(min_y, max_y + 1):
        p = px[max_x, y]
        if not is_transparent(p):
            total += 1
            if color_distance((p[0], p[1], p[2]), OUTLINE_COLOR) > outline_dist_threshold:
                missing += 1

    if total == 0:
        return None
    ratio = missing / total
    if ratio > 0.3:  # >30% of border pixels aren't dark = no outline
        return f"missing 1px dark outline ({missing}/{total} border pixels not dark); entity sprites/icons need a #0e1116 outline"
    return None

# ── Luminance contrast (block tiles only) ───────────────────────────────────

MIN_LUMINANCE_DELTA = 0.08  # WCAG-ish; data_validator uses a similar threshold

def collect_block_tiles(art_tree: Path) -> Dict[str, Image.Image]:
    """Collect all tile_*.png files keyed by filename for luminance comparison."""
    tiles: Dict[str, Image.Image] = {}
    for png in art_tree.rglob("tile_*.png"):
        if png.name.startswith("tile_crack"):
            continue
        tiles[str(png.relative_to(ART_DIR))] = Image.open(png).convert("RGBA")
    return tiles

def check_luminance_contrast(tiles: Dict[str, Image.Image]) -> List[Violation]:
    """Pairwise luminance check between block tile types — not just hue."""
    violations: List[Violation] = []
    names = sorted(tiles.keys())
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            # Only compare tiles in the same biome directory
            dir_i = Path(names[i]).parent
            dir_j = Path(names[j]).parent
            if dir_i != dir_j:
                continue
            # Skip relic tiles (they're objectives, not adjacent materials)
            if "relic" in names[i] or "relic" in names[j]:
                continue
            avg_i = _avg_color(tiles[names[i]])
            avg_j = _avg_color(tiles[names[j]])
            if avg_i is None or avg_j is None:
                continue
            lum_i = relative_luminance(avg_i)
            lum_j = relative_luminance(avg_j)
            delta = abs(lum_i - lum_j)
            if delta < MIN_LUMINANCE_DELTA:
                violations.append(Violation(
                    file=names[i],
                    check="luminance_contrast",
                    message=f"luminance delta {delta:.3f} vs {names[j]} < {MIN_LUMINANCE_DELTA}; adjacent block types need luminance contrast, not just hue"
                ))
    return violations

def _avg_color(img: Image.Image) -> Optional[Tuple[int, int, int]]:
    """Average non-transparent RGB color."""
    px = list(img.getdata())
    r = g = b = n = 0
    for p in px:
        if is_transparent(p):
            continue
        r += p[0]
        g += p[1]
        b += p[2]
        n += 1
    if n == 0:
        return None
    return (r // n, g // n, b // n)

# ── Main validation ────────────────────────────────────────────────────────

def validate_file(png_path: Path) -> ValidationResult:
    """Run all applicable checks on a single PNG."""
    rel = str(png_path.relative_to(ART_DIR))
    result = ValidationResult(file=rel, passed=True)
    rule = match_rule(png_path.name)

    if rule is None:
        result.violations.append(Violation(
            file=rel, check="class",
            message="no class rule matched (filename prefix unknown); add a rule or rename"
        ))
        result.passed = False
        return result

    try:
        img = Image.open(png_path)
    except Exception as e:
        result.violations.append(Violation(file=rel, check="load", message=f"cannot open PNG: {e}"))
        result.passed = False
        return result

    # 1. Dimensions
    msg = check_dimensions(img, rule)
    if msg:
        result.violations.append(Violation(file=rel, check="dimensions", message=msg))

    # 2. Palette compliance
    msg = check_palette_compliance(img)
    if msg:
        result.violations.append(Violation(file=rel, check="palette", message=msg))

    # 3. Transparency (no AA)
    msg = check_transparency(img)
    if msg:
        result.violations.append(Violation(file=rel, check="transparency", message=msg))

    # 4. Orphan pixels
    msg = check_orphan_pixels(img)
    if msg:
        result.violations.append(Violation(file=rel, check="orphan_pixels", message=msg))

    # 5. Tile seams (if tileable)
    if rule.tileable:
        msg = check_tile_seams(img)
        if msg:
            result.violations.append(Violation(file=rel, check="tile_seam", message=msg))

    # 6. Outline (if needed)
    if rule.needs_outline:
        msg = check_outline(img)
        if msg:
            result.violations.append(Violation(file=rel, check="outline", message=msg))

    result.passed = len(result.violations) == 0
    return result

def validate_all(art_tree: Path) -> Tuple[List[ValidationResult], List[Violation]]:
    """Validate every PNG in the art tree. Returns per-file results + luminance violations."""
    results: List[ValidationResult] = []
    pngs = sorted(art_tree.rglob("*.png"))

    # Only auto-skip legacy dirs when validating the full art/ tree;
    # if the user explicitly targets a subtree (--only), respect that.
    skip_legacy = (art_tree == ART_DIR)
    for png in pngs:
        if png.name.endswith(".import"):
            continue
        if skip_legacy:
            try:
                rel = png.relative_to(ART_DIR)
                if str(rel).startswith("runtime/") or str(rel).startswith("source/"):
                    continue
            except ValueError:
                pass
        results.append(validate_file(png))

    # Luminance contrast is a pairwise check across all block tiles
    tiles = collect_block_tiles(art_tree)
    lum_violations = check_luminance_contrast(tiles)

    return results, lum_violations

def main() -> int:
    parser = argparse.ArgumentParser(description="Validate art/ against art/STYLE.md")
    parser.add_argument("--only", type=str, default=None, help="validate only this subtree")
    parser.add_argument("--fix-report", action="store_true", help="write JSON report to reports/")
    args = parser.parse_args()

    art_tree = ART_DIR
    if args.only:
        art_tree = Path(args.only)
        if not art_tree.is_absolute():
            art_tree = PROJECT_ROOT / args.only

    if not art_tree.exists():
        print(f"ERROR: art tree not found: {art_tree}", file=sys.stderr)
        return 2

    print(f"Validating PNGs in {art_tree} against art/STYLE.md...")
    results, lum_violations = validate_all(art_tree)

    passed = sum(1 for r in results if r.passed)
    failed = len(results) - passed
    total = len(results)

    # Print per-file results
    for r in results:
        if r.passed:
            print(f"  PASS  {r.file}")
        else:
            print(f"  FAIL  {r.file}")
            for v in r.violations:
                print(f"        [{v.check}] {v.message}")

    # Print luminance violations
    for v in lum_violations:
        print(f"  FAIL  {v.file}")
        print(f"        [{v.check}] {v.message}")

    failed += len(lum_violations)

    print(f"\n{passed}/{total} files passed, {failed} violations.")

    # Optional JSON report
    if args.fix_report:
        REPORT_DIR.mkdir(parents=True, exist_ok=True)
        report = {
            "total": total,
            "passed": passed,
            "failed": failed,
            "results": [
                {"file": r.file, "passed": r.passed,
                 "violations": [{"check": v.check, "message": v.message} for v in r.violations]}
                for r in results
            ],
            "luminance_violations": [
                {"file": v.file, "check": v.check, "message": v.message}
                for v in lum_violations
            ],
        }
        report_path = REPORT_DIR / "art_validation.json"
        with open(report_path, "w") as f:
            json.dump(report, f, indent=2)
        print(f"Report written to {report_path}")

    return 0 if failed == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
