class_name UiLayout
extends RefCounted
## Pure portrait-HUD layout math (AC-5.8.5 / AC-5.8.6). No Node/scene/DisplayServer
## deps — the caller (hud.gd) reads the live device metrics and passes them in, so this
## logic is fully headless-testable with synthetic device profiles (notch phone, gesture-
## bar phone, inset-free desktop/web). Keeping it pure is what lets the safety-critical
## "are the controls inside the safe region" assertions run in the gate, not on a device.
##
## The HUD renders in LOGICAL (viewport) coordinates (e.g. 720x1280). The device safe area
## comes back in WINDOW pixels. safe_insets() converts the per-side device inset into the
## logical space the controls live in, and floors each at a data-driven base margin so a
## control never sits flush to the edge (and so inset-free targets still get breathing room).

## Convert a device safe area into logical-space HUD insets {top,bottom,left,right}.
##   window_px  — the OS window size in pixels (DisplayServer.window_get_size()).
##   safe_px    — the usable region in window pixels (DisplayServer.get_display_safe_area()).
##   logical    — the HUD's logical viewport size (get_viewport().get_visible_rect().size).
##   base_margin— the minimum edge margin (logical px) always applied (Registry.ui_edge_margin_px).
## Each device inset (the gap between a window edge and the safe rect) is scaled into logical
## units by the per-axis logical/window ratio, then floored at base_margin. The per-axis ratio
## is exact under stretch=expand and conservatively-correct under stretch=keep (where a device
## inset that falls in the letterbox bar maps to a near-zero logical inset — correct, since the
## bar already separates the control from the system UI). Over-insetting is always safe; the
## base_margin floor guarantees a usable result on desktop/web where safe_px == the full window.
static func safe_insets(window_px: Vector2i, safe_px: Rect2i, logical: Vector2i, base_margin: float) -> Dictionary:
	var win_w: float = maxf(1.0, float(window_px.x))
	var win_h: float = maxf(1.0, float(window_px.y))
	var ratio_x: float = float(logical.x) / win_w
	var ratio_y: float = float(logical.y) / win_h
	# Raw device insets in window px (clamped >= 0 — the safe rect is inside the window).
	var top_px: float = maxf(0.0, float(safe_px.position.y))
	var left_px: float = maxf(0.0, float(safe_px.position.x))
	var bottom_px: float = maxf(0.0, win_h - float(safe_px.position.y + safe_px.size.y))
	var right_px: float = maxf(0.0, win_w - float(safe_px.position.x + safe_px.size.x))
	var m: float = maxf(0.0, base_margin)
	return {
		"top": maxf(m, top_px * ratio_y),
		"bottom": maxf(m, bottom_px * ratio_y),
		"left": maxf(m, left_px * ratio_x),
		"right": maxf(m, right_px * ratio_x),
	}

## True if a control rect meets the minimum thumb-safe touch target on BOTH axes (AC-5.8.5,
## ~44–48px). Used by the HUD to size controls and by the gate test to verify them.
static func meets_touch_target(size: Vector2, min_px: float) -> bool:
	return size.x >= min_px and size.y >= min_px

## The vertical span [top_y, bottom_y) a bottom-anchored control strip of height `strip_h`
## occupies inside `logical`, given the safe insets. The strip's bottom edge sits at
## logical.y - insets.bottom (clear of the home-indicator/gesture zone — AC-5.8.5), and it
## extends up by strip_h. Returned as {top, bottom} in logical Y.
static func bottom_strip_span(logical: Vector2i, insets: Dictionary, strip_h: float) -> Dictionary:
	var bottom: float = float(logical.y) - float(insets.get("bottom", 0.0))
	return {"top": bottom - maxf(0.0, strip_h), "bottom": bottom}
