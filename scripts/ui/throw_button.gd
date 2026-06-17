class_name ThrowControls
extends Node
## Thin throw + tray-selection controller. The throw button commits the active
## charge; tapping a tray slot selects it as active (AC-5.3.6). Both behaviours are
## pure selection/commit logic with no Node deps in the hot path, so they are driven
## directly by headless tests (input events don't fire headless). Spawning the rigid
## body + decrementing the tray is the caller's job (RunState/U9) — this only decides
## WHICH slot is active and WHEN to fire a throw.
##
## A throw is ALWAYS possible: the free unlimited charge is a permanent slot, so the
## tray is never empty and there is no out-of-charges / lose state (AC-5.3.8).
##
## ACs: AC-5.3.3 (throw commits the active charge — emits a request to spawn it),
##       AC-5.3.6 (tap selects the active tray slot; free slot always selectable),
##       AC-5.3.7 (mouse/touch parity — taps run one shared path),
##       AC-5.3.8 (no lose state — a throw is always possible).

## Emitted when the throw button commits the active charge. The view spawns the
## rigid body (via RunState/Charge) in response; this controller stays UI-thin.
signal throw_requested(slot_index: int)

## Emitted when the active tray slot changes (so the view can re-highlight).
signal selection_changed(slot_index: int)

## Index of the currently selected tray slot. 0 is the permanent free slot.
var _selected_index: int = 0

## How many slots the tray currently has (free slot + bought charges). >= 1 always.
var _slot_count: int = 1

## Whether a throw can currently be committed (false while a charge is in flight).
var _can_throw: bool = true

## Cooldown state (v0.5): seconds remaining and total for the current cooldown.
var _cooldown_remaining: float = 0.0
var _cooldown_total: float = 0.0

# ── Public state ───────────────────────────────────────────────────────────

## The currently selected tray slot index.
var selected_index: int:
	get:
		return _selected_index

## The number of tray slots known to the controller.
var slot_count: int:
	get:
		return _slot_count

## Update the known tray size (called by the view when the tray changes). Clamps
## the selection so it never points past the end; never drops below the free slot.
func set_slot_count(count: int) -> void:
	_slot_count = maxi(count, 1)  # free slot guarantees >= 1 (AC-5.3.8)
	_selected_index = clampi(_selected_index, 0, _slot_count - 1)

## Enable/disable committing a throw (e.g. while a charge is mid-flight).
func set_can_throw(value: bool) -> void:
	_can_throw = value

## Start a throw cooldown of `seconds`. The button is disabled until it expires.
func start_cooldown(seconds: float) -> void:
	_cooldown_total = maxf(seconds, 0.0)
	_cooldown_remaining = _cooldown_total

## Advance the cooldown timer by `delta`. Returns true if the cooldown expired
## this tick (so the view can refresh button state once).
func advance_cooldown(delta: float) -> bool:
	if _cooldown_remaining <= 0.0:
		return false
	_cooldown_remaining = maxf(_cooldown_remaining - delta, 0.0)
	return _cooldown_remaining <= 0.0

## Whether the throw button is currently in a cooldown window.
var is_cooling_down: bool:
	get:
		return _cooldown_remaining > 0.0

## Cooldown progress in [0, 1]: 0 = just started, 1 = finished.
var cooldown_progress: float:
	get:
		if _cooldown_total <= 0.0:
			return 1.0
		return clampf(1.0 - (_cooldown_remaining / _cooldown_total), 0.0, 1.0)

## Human-readable countdown text (e.g. "1.2s"), or "" when ready.
var cooldown_text: String:
	get:
		if _cooldown_remaining <= 0.0:
			return ""
		return "%.1fs" % _cooldown_remaining

# ── Tray selection (AC-5.3.6) — shared tap path (AC-5.3.7) ─────────────────

## Select a tray slot by index. Out-of-range taps are ignored (the selection is
## unchanged). The free slot (index 0) is always a valid target (AC-5.3.6/8).
## Returns the resulting selected index. Pure selection logic; same call for
## mouse-click and touch-tap (the view passes a slot index for either).
func select_slot(index: int) -> int:
	if index < 0 or index >= _slot_count:
		return _selected_index  # ignore taps outside the tray
	if index != _selected_index:
		_selected_index = index
		selection_changed.emit(_selected_index)
	return _selected_index

# ── Throw commit (AC-5.3.3) ────────────────────────────────────────────────

## Whether a throw can be committed right now. True only when no charge is in
## flight AND the throw cooldown has expired. There is no empty-tray block
## (AC-5.3.8): the free slot is always throwable once the cooldown ends.
func can_throw() -> bool:
	return _can_throw and _cooldown_remaining <= 0.0

## Commit the active charge. Emits `throw_requested(selected_index)` so the view
## spawns it. Returns true if a throw was committed, false if currently blocked
## (charge in flight or on cooldown). Never blocked by an empty tray (AC-5.3.8).
func commit_throw() -> bool:
	if not can_throw():
		return false
	throw_requested.emit(_selected_index)
	return true
