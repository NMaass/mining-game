#!/usr/bin/env python3
"""Derive brighter, Diggin-like runtime art from the sourced Mine pico-platformer tileset.

The source asset is preserved; this script writes derived PNGs under art/runtime/ that are
sampled by data/art_sources.json and the Godot scenes. Run whenever the source tileset or the
color targets change.

License: source tileset by Kevin's Mom's House (itch.io, permissive project-use license).
Derivation is a color/transformation pass + original generated shapes; log it in ATTRIBUTIONS.md.
"""

from __future__ import annotations

import json
import math
import os
from pathlib import Path
from typing import Tuple

from PIL import Image, ImageEnhance, ImageDraw

PROJECT_ROOT = Path(__file__).resolve().parent.parent
SOURCE_PNG = PROJECT_ROOT / "art/source/kevin_moms_house/mine_pico_platformer_tileset/Mine/Mine.png"
OUT_DIR = PROJECT_ROOT / "art/runtime"
TILE_PX = 8

# Brighter Diggin-like target palette (RGBA hex). Indices match data/palette.json.
PALETTE = [
    "#0e1116",  # 0  bg / void
    "#3d2e20",  # 1  dark earth
    "#7a5530",  # 2  brown earth
    "#d4a36a",  # 3  dirt (bright, warm)
    "#4a9080",  # 4  teal accent
    "#c8d0d8",  # 5  rock (light gray)
    "#5a6a7a",  # 6  hard rock
    "#8a6fc0",  # 7  purple crystal
    "#4a9fd0",  # 8  blue crystal
    "#e06020",  # 9  copper ore
    "#7ad0f0",  # 10 light crystal
    "#ffe066",  # 11 gold ore
]


def hex_to_rgba(hexstr: str) -> Tuple[int, int, int, int]:
    hexstr = hexstr.lstrip("#")
    return tuple(int(hexstr[i : i + 2], 16) for i in (0, 2, 4)) + (255,)


def ensure_dirs() -> None:
    (OUT_DIR / "icons").mkdir(parents=True, exist_ok=True)


def _avg_color(img: Image.Image) -> Tuple[int, int, int, int]:
    """Average non-transparent color of an image."""
    px = list(img.getdata())
    r = g = b = n = 0
    for p in px:
        if p[3] < 128:
            continue
        r += p[0]
        g += p[1]
        b += p[2]
        n += 1
    if n == 0:
        return (0, 0, 0, 255)
    return (r // n, g // n, b // n, 255)


def _nearest_palette_index(color: Tuple[int, int, int, int]) -> int:
    """Find the palette index whose target color is closest in RGB space."""
    best_i = 0
    best_d = float("inf")
    for i, hexcol in enumerate(PALETTE):
        target = hex_to_rgba(hexcol)
        d = sum((color[j] - target[j]) ** 2 for j in range(3))
        if d < best_d:
            best_d = d
            best_i = i
    return best_i


def recolor_tileset(source: Image.Image) -> Image.Image:
    """Brighten and saturate the 8x8 source tileset for a cheerful Diggin-like look.

    The source tileset is already a cohesive pixel-art set; the derivation is a
    conservative color grade (brightness + saturation + contrast) that keeps the
    authored detail while making the mine read as brighter and more inviting.
    """
    img = source.convert("RGBA")
    img = ImageEnhance.Brightness(img).enhance(1.45)
    img = ImageEnhance.Color(img).enhance(1.55)
    img = ImageEnhance.Contrast(img).enhance(1.12)
    return img


def generate_platform(size: int = 144) -> Image.Image:
    """A chunky pixel-art mining platform / launcher gantry."""
    h = max(16, size // 6)
    img = Image.new("RGBA", (size, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    dark = hex_to_rgba("#3d3d45")
    mid = hex_to_rgba("#5a5a6a")
    light = hex_to_rgba("#7a7a8a")
    accent = hex_to_rgba("#f0a040")
    # Main deck
    d.rectangle([0, 4, size - 1, h - 1], fill=mid)
    # Rivet strip
    for x in range(8, size, 16):
        d.rectangle([x, 6, x + 3, 8], fill=light)
    # Side rails
    d.rectangle([0, 0, 5, h - 1], fill=dark)
    d.rectangle([size - 6, 0, size - 1, h - 1], fill=dark)
    # Center launch slot
    d.rectangle([size // 2 - 8, h - 5, size // 2 + 7, h - 2], fill=(20, 20, 24, 255))
    # Warning stripe
    d.rectangle([size // 2 - 4, 4, size // 2 + 3, 7], fill=accent)
    return img


def generate_charge(size: int = 16) -> Image.Image:
    """A small bomb/dynamite charge sprite."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    body = hex_to_rgba("#5a5a6a")
    highlight = hex_to_rgba("#7a7a8a")
    shadow = hex_to_rgba("#3d3d45")
    fuse = hex_to_rgba("#e06020")
    # Body
    d.ellipse([2, 4, size - 2, size - 2], fill=body)
    d.ellipse([3, 5, size - 3, size - 3], fill=highlight)
    # Fuse
    d.line([(size // 2, 4), (size // 2 + 3, 0)], fill=fuse, width=2)
    # Band
    d.rectangle([4, size // 2 - 2, size - 4, size // 2 + 1], fill=shadow)
    return img


def generate_explosion_particle(size: int = 8) -> Image.Image:
    """A soft pixel puff for GPUParticles2D."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    center = size // 2
    for r, color in [(size // 2 - 1, (255, 230, 120, 200)), (size // 2 - 2, (255, 160, 60, 180)), (1, (255, 80, 40, 160))]:
        d.ellipse([center - r, center - r, center + r, center + r], fill=color)
    return img


def generate_debris_particle(size: int = 4) -> Image.Image:
    """A small angular debris chunk for block-break particles."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, size - 1, size - 1], fill=(200, 180, 160, 255))
    return img


def generate_icon(name: str, size: int = 24) -> Image.Image:
    """Generate simple HUD icons."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if name == "money":
        d.ellipse([2, 2, size - 2, size - 2], fill=(240, 200, 80, 255))
        d.text((size // 2 - 4, size // 2 - 5), "$", fill=(60, 45, 20, 255))
    elif name == "depth":
        d.polygon([(size // 2, size - 2), (2, 4), (size - 2, 4)], fill=(100, 200, 240, 255))
        d.rectangle([2, 2, size - 2, 4], fill=(200, 200, 210, 255))
    elif name == "relic":
        d.polygon([(size // 2, 2), (size - 2, size // 2), (size // 2, size - 2), (2, size // 2)], fill=(180, 100, 220, 255))
        d.polygon([(size // 2, 6), (size - 5, size // 2), (size // 2, size - 5), (4, size // 2)], fill=(220, 160, 255, 255))
    return img


def main() -> None:
    ensure_dirs()
    src = Image.open(SOURCE_PNG).convert("RGBA")

    # Derived tileset
    recolored = recolor_tileset(src)
    recolored.save(OUT_DIR / "Mine_Bright.png")

    # Generated sprites
    generate_platform().save(OUT_DIR / "platform.png")
    generate_charge().save(OUT_DIR / "charge.png")
    generate_explosion_particle().save(OUT_DIR / "explosion_particle.png")
    generate_debris_particle().save(OUT_DIR / "debris_particle.png")

    # Icons
    for icon_name in ["money", "depth", "relic"]:
        generate_icon(icon_name).save(OUT_DIR / f"icons/{icon_name}.png")

    print(f"Wrote derived art to {OUT_DIR}")


if __name__ == "__main__":
    main()
