class_name CrateReveal
extends CanvasLayer
## Dramatic pack-open reveal overlay for ShopModal.
##
## Results are already rolled by RunState; this only visualizes the granted charges.
## It respects motion intensity: common/uncommon/rare share the same information, while
## low motion swaps the shake/hit-stop/light-beam beats for a calm fade.

signal finished

const PIXEL_FONT := preload("res://art/fonts/PixelifySans.ttf")
const ChargeIconScript := preload("res://scripts/ui/charge_icon.gd")
const _PixelUi := preload("res://scripts/ui/pixel_ui.gd")

var _tables: Dictionary = {}
var _motion: float = 1.0
var _tween: Tween = null

var _backdrop: ColorRect
var _panel: PanelContainer
var _crate: TextureRect
var _title: Label
var _caption: Label
var _items: HBoxContainer
var _beam: ColorRect
var _particle_layer: Node2D
var _particle_texture: Texture2D
var _shake_tween: Tween = null

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false

func configure(tables: Dictionary) -> void:
	_tables = tables

func show_pack(pack_id: String, results: Array, motion: float = 1.0) -> void:
	_motion = clampf(motion, 0.0, 1.0)
	visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_reset_visuals(pack_id, results)
	var best: String = best_rarity(results)
	_play_opening_audio(best)
	if _motion <= 0.01:
		_reduced_motion_show(best)
	else:
		_animated_show(best)

static func best_rarity_from_tables(tables: Dictionary, results: Array) -> String:
	var best := "common"
	var best_rank := -1
	for id in results:
		var ex: Dictionary = Registry.explosive(tables, str(id))
		var rarity: String = str(ex.get("rarity", "common"))
		var rank: int = Registry.rarity_rank(tables, rarity)
		# Registry ranks lower rarity as 0; invert by picking highest known rank.
		if rank > best_rank and rank < 1 << 20:
			best_rank = rank
			best = rarity
	return best

func best_rarity(results: Array) -> String:
	return best_rarity_from_tables(_tables, results)

func _build() -> void:
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.color = Color(0, 0, 0, 0.72)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = Vector2(520, 430)
	_PixelUi.apply_panel(_panel)
	center.add_child(_panel)

	var box := VBoxContainer.new()
	box.name = "Box"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	_panel.add_child(box)

	_title = Label.new()
	_title.name = "Title"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_override("font", PIXEL_FONT)
	_title.add_theme_font_size_override("font_size", 32)
	box.add_child(_title)

	var stage := Control.new()
	stage.name = "Stage"
	stage.custom_minimum_size = Vector2(420, 170)
	box.add_child(stage)

	_beam = ColorRect.new()
	_beam.name = "LightBeam"
	_beam.anchor_left = 0.45
	_beam.anchor_right = 0.55
	_beam.offset_top = 0
	_beam.offset_bottom = 170
	_beam.color = Color(1.0, 0.88, 0.32, 0.0)
	_beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(_beam)

	_crate = TextureRect.new()
	_crate.name = "Crate"
	_crate.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_crate.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_crate.custom_minimum_size = Vector2(128, 128)
	_crate.position = Vector2(146, 24)
	stage.add_child(_crate)

	_items = HBoxContainer.new()
	_items.name = "Items"
	_items.alignment = BoxContainer.ALIGNMENT_CENTER
	_items.add_theme_constant_override("separation", 8)
	box.add_child(_items)

	_caption = Label.new()
	_caption.name = "Caption"
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caption.add_theme_font_override("font", PIXEL_FONT)
	_caption.add_theme_font_size_override("font_size", 20)
	box.add_child(_caption)

	_particle_layer = Node2D.new()
	_particle_layer.name = "PixelParticles"
	add_child(_particle_layer)

func _reset_visuals(pack_id: String, results: Array) -> void:
	_backdrop.modulate = Color(1, 1, 1, 0)
	_panel.scale = Vector2(0.95, 0.95)
	_panel.modulate = Color(1, 1, 1, 0)
	_panel.position = Vector2.ZERO
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	_beam.modulate = Color(1, 1, 1, 0)
	_beam.scale = Vector2(1, 1)
	_crate.texture = ChargeIconScript.crate_texture(_tables, pack_id, 64)
	_crate.modulate = Color.WHITE
	_crate.scale = Vector2.ONE
	_crate.position = Vector2(146, 24)
	_title.text = "CRATE OPENED"
	_caption.text = _caption_for(best_rarity(results))
	for c in _items.get_children():
		_items.remove_child(c)
		c.queue_free()
	for p in _particle_layer.get_children():
		p.queue_free()
	for id in _compact_results(results):
		_items.add_child(_make_reward_card(str(id["id"]), int(id["count"])))

func _compact_results(results: Array) -> Array:
	var counts: Dictionary = {}
	for id in results:
		counts[str(id)] = int(counts.get(str(id), 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	var out: Array = []
	for id in keys:
		out.append({"id": id, "count": counts[id]})
	return out

func _make_reward_card(charge_id: String, count: int) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "Reward_%s" % charge_id
	card.custom_minimum_size = Vector2(92, 108)
	var rarity: String = str(Registry.explosive(_tables, charge_id).get("rarity", "common"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.18, 1)
	sb.border_color = Registry.rarity_color(_tables, rarity)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	card.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(56, 56)
	icon.texture = ChargeIconScript.texture_for(_tables, charge_id, 64)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(icon)
	var label := Label.new()
	label.text = "%s x%d" % [str(Registry.explosive(_tables, charge_id).get("display_name", charge_id)), count]
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", PIXEL_FONT)
	label.add_theme_font_size_override("font_size", 14)
	label.clip_text = true
	box.add_child(label)
	var glyph := Label.new()
	glyph.text = "%s %s" % [_rarity_glyph(rarity), _tier_pips(charge_id)]
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.add_theme_font_override("font", PIXEL_FONT)
	glyph.add_theme_font_size_override("font_size", 14)
	box.add_child(glyph)
	card.scale = Vector2(0.4, 0.4)
	card.modulate = Color(1, 1, 1, 0)
	return card

func _animated_show(best: String) -> void:
	var drop_s: float = Registry.ui_crate_f(_tables, "drop_seconds", 0.18)
	var reveal_s: float = Registry.ui_crate_f(_tables, "reveal_seconds", 0.28)
	var settle_s: float = Registry.ui_crate_f(_tables, "settle_seconds", 0.22)
	var hold_s: float = Registry.ui_crate_f(_tables, "hold_seconds", 0.28)
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.set_parallel(true)
	_tween.tween_property(_backdrop, "modulate", Color(1, 1, 1, 1), drop_s)
	_tween.tween_property(_panel, "modulate", Color(1, 1, 1, 1), drop_s)
	_tween.tween_property(_panel, "scale", Vector2.ONE, drop_s).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_crate, "position:y", 42.0, drop_s).from(-60.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.chain()
	if best == "rare":
		_tween.tween_callback(_rare_hitstop)
		_tween.tween_property(_beam, "modulate", Color(1, 1, 1, 0.85), reveal_s * 0.45)
		_tween.parallel().tween_property(_beam, "scale:x", 4.5, reveal_s)
		_tween.parallel().tween_property(_crate, "scale", Vector2(1.22, 0.78), reveal_s * 0.35)
	else:
		_tween.tween_property(_crate, "scale", Vector2(1.10, 0.90), reveal_s * 0.35)
	_tween.chain()
	_tween.tween_property(_crate, "scale", Vector2.ONE, reveal_s * 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for i in range(_items.get_child_count()):
		var card := _items.get_child(i) as Control
		_tween.parallel().tween_property(card, "modulate", Color(1, 1, 1, 1), reveal_s).set_delay(0.06 * float(i))
		_tween.parallel().tween_property(card, "scale", Vector2.ONE, reveal_s).set_delay(0.06 * float(i)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain()
	_tween.tween_property(_beam, "modulate", Color(1, 1, 1, 0), settle_s)
	_tween.parallel().tween_interval(hold_s)
	_tween.chain().tween_callback(_finish)

func _reduced_motion_show(best: String) -> void:
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_backdrop.modulate = Color(1, 1, 1, 1)
	_panel.scale = Vector2.ONE
	_panel.modulate = Color(1, 1, 1, 1)
	_crate.position.y = 42.0
	_caption.text = "%s revealed." % best.capitalize()
	for c in _items.get_children():
		var card := c as Control
		card.scale = Vector2.ONE
		card.modulate = Color(1, 1, 1, 1)
	_tween.tween_interval(Registry.ui_crate_f(_tables, "reduced_hold_seconds", 0.35))
	_tween.tween_callback(_finish)

func _rare_hitstop() -> void:
	var seconds: float = Registry.ui_crate_f(_tables, "rare_hitstop_seconds", 0.055)
	_play("crate_smash")
	_spawn_rare_particles()
	_shake_panel()
	if seconds <= 0.0:
		return
	Engine.time_scale = 0.08
	var timer: SceneTreeTimer = get_tree().create_timer(seconds, true, false, true)
	timer.timeout.connect(func() -> void: Engine.time_scale = 1.0)

func _finish() -> void:
	Engine.time_scale = 1.0
	visible = false
	finished.emit()

func _play_opening_audio(best: String) -> void:
	_play("crate_drop")
	if best == "rare":
		_play("rare_reveal_sting")
	elif best == "uncommon":
		_play("crate_creak")
	else:
		_play("pack_open")

func _play(event: String) -> void:
	var audio: Node = get_node_or_null("/root/Audio")
	if audio != null and audio.has_method("play"):
		audio.call("play", event)


func _spawn_rare_particles() -> void:
	if _motion <= 0.01 or _particle_layer == null:
		return
	var count: int = Registry.ui_crate_i(_tables, "particle_count_rare", 18)
	if count <= 0:
		return
	var fx := GPUParticles2D.new()
	fx.name = "RareBurst"
	fx.amount = mini(count, 48)
	fx.one_shot = true
	fx.explosiveness = 1.0
	fx.lifetime = 0.55
	fx.texture = _pixel_particle_texture()
	var mat := ParticleProcessMaterial.new()
	mat.color = Color(1.0, 0.86, 0.28, 1.0)
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 80.0
	mat.initial_velocity_max = 180.0
	mat.gravity = Vector3(0, 220.0, 0)
	mat.scale_min = 1.0
	mat.scale_max = 2.4
	fx.process_material = mat
	var rect: Rect2 = get_viewport().get_visible_rect() if get_viewport() != null else Rect2(Vector2.ZERO, Vector2(720, 1280))
	fx.position = rect.size * 0.5 + Vector2(0, -80)
	_particle_layer.add_child(fx)
	fx.emitting = true
	var timer: SceneTreeTimer = get_tree().create_timer(fx.lifetime + 0.2, true, false, true)
	timer.timeout.connect(fx.queue_free)


func _shake_panel() -> void:
	if _panel == null or _motion <= 0.01:
		return
	if _shake_tween != null and _shake_tween.is_valid():
		_shake_tween.kill()
	var amp := 7.0 * _motion
	_shake_tween = create_tween()
	_shake_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for i in range(5):
		var dir := -1.0 if i % 2 == 0 else 1.0
		_shake_tween.tween_property(_panel, "position", Vector2(amp * dir, 0), 0.025)
	_shake_tween.tween_property(_panel, "position", Vector2.ZERO, 0.04)


func _pixel_particle_texture() -> Texture2D:
	if _particle_texture != null:
		return _particle_texture
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	_particle_texture = ImageTexture.create_from_image(image)
	return _particle_texture

func _caption_for(best: String) -> String:
	if best == "rare":
		return "Rare charge revealed!"
	if best == "uncommon":
		return "Uncommon charge revealed!"
	return "Charges added."

func _rarity_glyph(rarity: String) -> String:
	if rarity == "rare":
		return "R"
	if rarity == "uncommon":
		return "U"
	return "C"

func _tier_pips(charge_id: String) -> String:
	var tier: int = maxi(1, int(Registry.explosive(_tables, charge_id).get("tier", 1)))
	return "◆".repeat(tier)
