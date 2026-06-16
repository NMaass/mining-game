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

## Whether a throw can be committed right now. Always true except while a charge is
## already in flight — there is no empty-tray block (AC-5.3.8): the free slot is
## always throwable.
func can_throw() -> bool:
	return _can_throw

## Commit the active charge. Emits `throw_requested(selected_index)` so the view
## spawns it. Returns true if a throw was committed, false if currently blocked
## (charge in flight). Never blocked by an empty tray (AC-5.3.8).
func commit_throw() -> bool:
	if not _can_throw:
		return false
	throw_requested.emit(_selected_index)
	return true
