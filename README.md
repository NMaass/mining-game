# Mining Game — Vertical Slice

A portrait, physics-driven mining-game vertical slice built in Godot 4.6. The project is designed around a machine-verifiable product specification: gameplay requirements are written as acceptance criteria and traced to automated tests so both human and agentic development workflows can make changes without relying on vague “looks done” judgments.

## Current slice

The implemented core loop is:

```text
procedural mine
    ↓
throw / aim explosives
    ↓
destroy blocks and collect ore
    ↓
convert ore to money
    ↓
find the relic and end the dig
    ↓
prestige into a stronger next run
```

The slice includes responsive portrait UI, safe-area handling, persisted settings, save/recovery logic, color-independent block identity, deterministic data validation, and headless acceptance-criteria coverage.

This is a **vertical slice**, not a complete game. Remaining roadmap work includes production art/audio, additional hub/shop progression, reduced-motion OS integration, and full web persistence.

## Stack

| Area | Choice |
| --- | --- |
| Engine | Godot 4.6.3 |
| Physics | Rapier 2D |
| Tests | gdUnit4 6.1.3 |
| Tunables | Schema-validated JSON in `data/` |

## Verification

A feature is considered complete only when both gates pass:

```sh
tools/validate_data.sh
tools/run_tests.sh tests
```

Run one suite during development with:

```sh
tools/run_tests.sh tests/unit/test_block_gen.gd
```

CI runs the validation and test gates on every push. Coverage and known gaps are tracked in [`reports/spec-coverage.md`](reports/spec-coverage.md).

## Start here

- [`spec/SPEC.md`](spec/SPEC.md) — product design and acceptance criteria
- [`spec/AGENTS.md`](spec/AGENTS.md) — engine and implementation conventions
- [`spec/VERTICAL_SLICE.md`](spec/VERTICAL_SLICE.md) — slice decomposition and build contract
- [`reports/spec-coverage.md`](reports/spec-coverage.md) — acceptance-criteria traceability
- [`spec/AUDIT.md`](spec/AUDIT.md) — design/audit history

## Local development

```sh
godot --path .
godot --headless --path . --import
```

## Repository layout

```text
scenes/                    authored scenes
scripts/core/              pure, headless-testable game logic
scripts/systems/           game-state and economy systems
scripts/ui/                input and HUD code
data/                      validated tunables
tests/{unit,integration,golden}/
tools/                     validation and test runners
reports/                   coverage and verification artifacts
spec/                      product and implementation contracts
.claude/workflows/         saved build/verification workflows
```

## Agentic workflow experiments

The repository includes saved workflows for building one verified unit, progressing through the vertical slice, and performing a clean-room verification pass. These workflows are part of the project’s broader experiment: whether a sufficiently explicit specification, test contract, and evidence trail can make long-running agentic game development reliable.

Green tests alone are not treated as proof when the tests do not demonstrate the acceptance criterion they claim to cover.
