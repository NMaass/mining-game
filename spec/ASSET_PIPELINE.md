# Asset Pipeline

## Aseprite

- Aseprite app: `/Applications/Aseprite.app`
- CLI binary: `/Applications/Aseprite.app/Contents/MacOS/aseprite`
- Claude Code MCP server: `aseprite`, backed by `@iborymagic/aseprite-mcp`
- Portable project MCP config: `.mcp.json`

Use `art/source/generated/` for project-authored `.aseprite` source files and export shipping PNGs to
`art/runtime/`. Keep source files; do not edit only the exported PNG.

Import `art/palettes/mining_game.gpl` into Aseprite before generating or cleaning project-authored art.
Generated and recolored art should quantize to this palette. Sourced packs remain exempt from strict
quantization, per `spec/AGENTS.md`.

## Export

For simple one-image exports:

```bash
tools/aseprite_export.sh art/source/generated/charge_v2.aseprite art/runtime/charge_v2.png
```

For sprite sheets, frame extraction, metadata, or Lua cleanup/recolor operations, use the `aseprite`
MCP server from Claude Code. The server exposes export and safe Lua automation tools.

## Attribution

Any generated asset needs an entry in `spec/ATTRIBUTIONS.md` with:

- asset path
- author/tool
- generation date
- "no claimed copyright" note
- project use

Do not prompt for named artists, existing IP, or market-facing signature art.
