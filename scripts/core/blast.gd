class_name Blast
extends RefCounted
## Pure blast damage computation. No Node/scene/input deps; headless-testable.
##
## v0.4: the blast is FUZZY. Per-cell damage = intensity * falloff[dist] * fuzz,
## where `fuzz` is drawn from an INJECTED, seedable RNG in a fixed grid-walk order.
## A fixed seed therefore yields a fixed result (golden-pinned); a different seed
## varies the cleared set. When no rng is injected (rng == null), the fuzz factor is
## a flat 1.0 — the deterministic baseline that keeps the pre-fuzz golden + callers
## that do not yet thread an rng (block_grid, level smoke) green. (SPEC §3 blast
## contract, AC-5.2.3, AC-5.2.4.)
##
## resolve() takes a snapshot of current HP values and computes damage/clears against
## that snapshot — no chain propagation through cells broken in the same blast
## (AC-5.2.3). The cleared cavity is a pure function of (snapshot, center, radius,
## intensity, falloff, fuzz_pct, rng-seed).
##
## ACs: AC-5.2.3 (fuzzy radial damage, injected rng, pre-blast snapshot),
##       AC-5.2.4 (single-source-of-truth grid walk, fixed rng walk order),
##       AC-5.2.5 (crack stage mapping), AC-5.2.6 (block break), AC-5.4.6.

## Default fuzz spread when an rng is injected but no explicit fuzz_pct is given.
## Real gameplay passes balance.blast_fuzz_pct (data, never hardcoded) — this is only
## the in-code fallback for direct callers/tests that opt into fuzz without a table.
const DEFAULT_FUZZ_PCT := 0.25

## Result of a blast resolution.
## - damaged: Dictionary mapping Vector2i cell → int damage dealt
## - cleared: Array of Vector2i cells whose HP reached 0
## - new_hp: Dictionary mapping Vector2i cell → int remaining HP (post-blast)
##
## Walk order is FIXED: dy outer (-radius..radius), dx inner (-radius..radius). When
## `rng` is supplied, exactly one fuzz draw is consumed per in-radius cell (Chebyshev
## dist <= radius) in that order — independent of whether the cell is solid — so the
## RNG sequence is a pure function of (center, radius, seed), not of grid contents
## (AC-5.2.4). `fuzz_pct` scales the spread: fuzz ∈ [1 - fuzz_pct, 1 + fuzz_pct].
static func resolve(
	hp_snapshot: Dictionary,  # {Vector2i: int} — current HP of each cell
	center: Vector2i,         # blast center cell
	radius: int,              # blast_radius_cells (single source of truth)
	intensity: int,           # blast_intensity
	falloff: Array,           # blast_falloff array, length == radius + 1
	rng: RandomNumberGenerator = null,  # injected; null = no fuzz (flat 1.0)
	fuzz_pct: float = DEFAULT_FUZZ_PCT  # spread used only when rng != null
) -> Dictionary:
	var damaged: Dictionary = {}   # Vector2i → int damage dealt
	var cleared: Array = []        # Array[Vector2i]
	var new_hp: Dictionary = {}    # Vector2i → int remaining HP

	var spread: float = clampf(fuzz_pct, 0.0, 1.0)

	# Grid walk over the bounding box of the radius (AC-5.2.4). `radius` is the ONE
	# source of truth for reach; the falloff array is sampled by index but never
	# extends the radius (the data gate enforces falloff length == radius + 1).
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			# Grid-cell distance (Chebyshev for square blocks).
			var dist: int = maxi(absi(dx), absi(dy))
			if dist > radius:
				continue

			# Draw the per-cell fuzz factor HERE — once per in-radius cell, in the
			# fixed dy/dx walk order, BEFORE the solid/air branch. This keeps the rng
			# walk a pure function of (center, radius, seed): the same seed advances
			# the rng identically no matter which cells happen to be solid (AC-5.2.4).
			var fuzz: float = 1.0
			if rng != null and spread > 0.0:
				fuzz = 1.0 + rng.randf_range(-spread, spread)

			var cell := Vector2i(center.x + dx, center.y + dy)

			# Skip cells not in the snapshot (air/empty/out of bounds). The fuzz draw
			# above has already advanced the rng, so the sequence stays stable.
			if not hp_snapshot.has(cell):
				continue

			# Look up the falloff factor for this distance. Index is bounded by the
			# walk (dist <= radius) and the gate (len == radius + 1), so this is in range.
			if dist >= falloff.size():
				continue  # defensive: malformed falloff shorter than radius
			var factor: float = float(falloff[dist])
			if factor <= 0.0:
				continue

			# Fuzzy damage = intensity * falloff * fuzz, floored to int (grid is int).
			var dmg: int = int(float(intensity) * factor * fuzz)
			if dmg <= 0:
				continue

			# Apply against the PRE-BLAST snapshot HP (AC-5.2.3 — no chain prop).
			var original_hp: int = int(hp_snapshot[cell])
			var remaining: int = maxi(0, original_hp - dmg)

			damaged[cell] = dmg
			new_hp[cell] = remaining

			if remaining <= 0:
				cleared.append(cell)

	return {
		"damaged": damaged,
		"cleared": cleared,
		"new_hp": new_hp,
	}

## Maps current HP to a crack stage. Explicit contract (AC-5.2.5):
##   full HP            → stage 0
##   0 < HP < max_hp    → 1 .. crack_stages - 1 (the visible crack range)
##   HP <= 0 (broken)   → crack_stages (sentinel; the cell is removed, no overlay)
## Monotonically non-decreasing as HP falls. The maximum *visible* stage is
## crack_stages - 1; `stages` itself only ever maps to the broken sentinel.
static func crack_stage(current_hp: int, max_hp: int, stages: int) -> int:
	if max_hp <= 0 or stages <= 0:
		return 0
	if current_hp <= 0:
		return stages
	if current_hp >= max_hp:
		return 0

	# Linear mapping: fraction of HP lost → stage, clamped to the visible range.
	var fraction_lost: float = 1.0 - (float(current_hp) / float(max_hp))
	var stage: int = int(fraction_lost * float(stages))
	return mini(stage, stages - 1)

## Convenience: compute blast damage from an explosive data dict on a grid. Threads
## the same injected rng + fuzz spread through to resolve(). `fuzz_pct` defaults to
## the explosive's own value if present, else the in-code baseline — callers that
## want data-driven fuzz pass balance.blast_fuzz_pct explicitly.
static func resolve_explosive(
	hp_snapshot: Dictionary,
	center: Vector2i,
	explosive_data: Dictionary,
	rng: RandomNumberGenerator = null,
	fuzz_pct: float = DEFAULT_FUZZ_PCT
) -> Dictionary:
	var radius: int = int(explosive_data.get("blast_radius_cells", 0))
	var intensity: int = int(explosive_data.get("blast_intensity", 0))
	var falloff: Array = explosive_data.get("blast_falloff", [])
	return resolve(hp_snapshot, center, radius, intensity, falloff, rng, fuzz_pct)
