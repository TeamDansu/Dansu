extends Panel

const SHINE_SHADER := preload("res://resorces/shaders/card_shine.gdshader")

const MAX_ROTATION_DEGREES := 3.0
const HOVER_SCALE := 1.015
const THUMB_PARALLAX := Vector2(10.0, 8.0)
const CONTENT_PARALLAX := Vector2(14.0, 10.0)
const SHADOW_BASE_OFFSET := Vector2(0.0, 8.0)
const SHADOW_MAX_OFFSET := Vector2(18.0, 12.0)
const SHADOW_HOVER_SIZE := 32.0
const SHADOW_REST_COLOR := Color(0, 0, 0, 0)
const SHADOW_HOVER_COLOR := Color(0, 0, 0, 0.32)
const VISUAL_LERP_SPEED := 12.0
const HOVER_LERP_SPEED := 10.0
const THUMB_HIDDEN_ALPHA := 0.0
const THUMB_VISIBLE_ALPHA := 0.8
const THUMB_FADE_DURATION := 0.18

static var _stream_length_cache := {}

@onready var thumb: TextureRect = %Thumb
@onready var content: Control = $Content
@onready var title_label: Label = %Title
@onready var artist_label: Label = %Artist
@onready var desc_label: Label = %Desc

var click_tween: Tween
var thumb_tween: Tween

var current_cover_chart: Chart = null
var hovered := false
var hover_strength := 0.0
var shine_uv := Vector2(0.5, 0.5)
var press_scale_multiplier := 1.0
var base_thumb_position := Vector2.ZERO
var base_content_position := Vector2.ZERO
var panel_style: StyleBoxFlat
var shine_rect: ColorRect
var shine_material: ShaderMaterial


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	gui_input.connect(_on_gui_input)
	resized.connect(_on_resized)
	CM.chart_selected.connect(_refresh)
	CoverLoader.cover_loaded.connect(_on_cover_loaded)
	CoverLoader.cover_failed.connect(_on_cover_failed)

	_setup_stylebox()
	_setup_shine()
	call_deferred("_cache_layout")
	call_deferred("_on_resized")
	set_process(false)

	if CM.selected_chart != null:
		_refresh(CM.selected_chart)


func _process(delta: float) -> void:
	var target_uv := Vector2(0.5, 0.5)
	var normalized := Vector2.ZERO
	var target_hover_strength := 0.0
	var target_scale_value := 1.0

	if hovered and size.x > 0.0 and size.y > 0.0:
		var local_mouse := get_local_mouse_position()
		target_uv = Vector2(
			clampf(local_mouse.x / size.x, 0.0, 1.0),
			clampf(local_mouse.y / size.y, 0.0, 1.0)
		)
		normalized = (target_uv - Vector2(0.5, 0.5)) * 2.0
		target_hover_strength = 1.0
		target_scale_value = HOVER_SCALE

	var visual_weight := minf(delta * VISUAL_LERP_SPEED, 1.0)
	var hover_weight := minf(delta * HOVER_LERP_SPEED, 1.0)
	var target_scale := Vector2.ONE * (target_scale_value * press_scale_multiplier)
	var target_rotation := normalized.x * MAX_ROTATION_DEGREES
	var target_thumb_position := base_thumb_position - Vector2(
		normalized.x * THUMB_PARALLAX.x,
		normalized.y * THUMB_PARALLAX.y
	)
	var target_content_position := base_content_position + Vector2(
		normalized.x * CONTENT_PARALLAX.x,
		normalized.y * CONTENT_PARALLAX.y
	)
	var target_shadow_offset := SHADOW_BASE_OFFSET + Vector2(
		normalized.x * SHADOW_MAX_OFFSET.x,
		normalized.y * SHADOW_MAX_OFFSET.y
	)
	var target_shadow_color := SHADOW_HOVER_COLOR if hovered else SHADOW_REST_COLOR
	var target_shadow_size := SHADOW_HOVER_SIZE if hovered else 0.0

	scale = scale.lerp(target_scale, visual_weight)
	rotation_degrees = lerpf(rotation_degrees, target_rotation, visual_weight)
	thumb.position = thumb.position.lerp(target_thumb_position, visual_weight)
	content.position = content.position.lerp(target_content_position, visual_weight)
	shine_uv = shine_uv.lerp(target_uv, visual_weight)
	hover_strength = lerpf(hover_strength, target_hover_strength, hover_weight)

	if shine_material != null:
		shine_material.set_shader_parameter("cursor_uv", shine_uv)
		shine_material.set_shader_parameter("hover_strength", hover_strength)

	if panel_style != null:
		panel_style.shadow_offset = panel_style.shadow_offset.lerp(target_shadow_offset, visual_weight)
		panel_style.shadow_color = panel_style.shadow_color.lerp(target_shadow_color, hover_weight)
		panel_style.shadow_size = lerpf(panel_style.shadow_size, target_shadow_size, hover_weight)

	if not hovered and _is_visual_resting():
		_snap_to_rest_state()
		set_process(false)


func _refresh(chart: Chart) -> void:
	current_cover_chart = chart

	if chart == null:
		title_label.text = ""
		artist_label.text = ""
		desc_label.text = ""
		thumb.texture = null
		_set_thumb_alpha(THUMB_HIDDEN_ALPHA)
		return

	title_label.text = chart.title
	artist_label.text = _build_artist_text(chart)
	desc_label.text = _build_desc_text(chart)
	_set_thumb_alpha(THUMB_HIDDEN_ALPHA)

	if chart.cover_image != null:
		thumb.texture = chart.cover_image
		_fade_in_thumb()
	else:
		thumb.texture = null
		CoverLoader.request_cover(chart)


func _on_mouse_entered() -> void:
	hovered = true
	set_process(true)


func _on_mouse_exited() -> void:
	hovered = false
	set_process(true)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_play_click_animation()


func _on_resized() -> void:
	pivot_offset = size * 0.5
	if shine_rect != null:
		shine_rect.pivot_offset = shine_rect.size * 0.5


func _on_cover_loaded(chart: Chart, texture: Texture2D) -> void:
	if chart == null or texture == null:
		return
	if chart != current_cover_chart:
		return
	thumb.texture = texture
	_fade_in_thumb()


func _on_cover_failed(chart: Chart) -> void:
	if chart != current_cover_chart:
		return
	thumb.texture = null
	_set_thumb_alpha(THUMB_HIDDEN_ALPHA)


func _cache_layout() -> void:
	base_thumb_position = thumb.position
	base_content_position = content.position
	_snap_to_rest_state()


func _setup_stylebox() -> void:
	var style := get("theme_override_styles/panel") as StyleBoxFlat
	if style == null:
		return

	panel_style = style.duplicate()
	panel_style.shadow_color = SHADOW_REST_COLOR
	panel_style.shadow_size = 0.0
	panel_style.shadow_offset = SHADOW_BASE_OFFSET
	add_theme_stylebox_override("panel", panel_style)


func _setup_shine() -> void:
	shine_material = ShaderMaterial.new()
	shine_material.shader = SHINE_SHADER
	shine_material.set_shader_parameter("cursor_uv", Vector2(0.5, 0.5))
	shine_material.set_shader_parameter("hover_strength", 0.0)

	shine_rect = ColorRect.new()
	shine_rect.name = "Shine"
	shine_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shine_rect.color = Color.WHITE
	shine_rect.material = shine_material
	shine_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shine_rect)
	move_child(shine_rect, get_child_count() - 1)


func _play_click_animation() -> void:
	if click_tween != null:
		click_tween.kill()

	click_tween = create_tween()
	click_tween.set_trans(Tween.TRANS_BACK)
	click_tween.set_ease(Tween.EASE_OUT)
	click_tween.tween_method(Callable(self, "_set_press_scale_multiplier"), press_scale_multiplier, 0.975, 0.06)
	click_tween.tween_method(Callable(self, "_set_press_scale_multiplier"), 0.975, 1.0, 0.16)


func _set_press_scale_multiplier(value: float) -> void:
	press_scale_multiplier = value
	set_process(true)


func _fade_in_thumb() -> void:
	if thumb_tween != null:
		thumb_tween.kill()

	thumb_tween = create_tween()
	thumb_tween.set_trans(Tween.TRANS_SINE)
	thumb_tween.set_ease(Tween.EASE_OUT)
	thumb_tween.tween_property(thumb, "modulate:a", THUMB_VISIBLE_ALPHA, THUMB_FADE_DURATION)


func _set_thumb_alpha(value: float) -> void:
	if thumb_tween != null:
		thumb_tween.kill()
	thumb.modulate.a = value


func _build_artist_text(chart: Chart) -> String:
	if chart == null:
		return ""
	return chart.artist


func _build_desc_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var parts: Array[String] = []
	var timing_text := _build_timing_text(chart)
	var difficulty_text := _build_difficulty_text(chart)

	if not timing_text.is_empty():
		parts.append(timing_text)
	if not difficulty_text.is_empty():
		parts.append(difficulty_text)
	if chart.rating > 0.0:
		parts.append("%.1f★" % chart.rating)
	if not chart.source.is_empty() and chart.source != "?":
		parts.append(chart.source)

	return " • ".join(parts)


func _build_timing_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var length_text := _get_chart_length_text(chart)
	var bpm_text := _get_chart_bpm_text(chart)

	if length_text.is_empty() and bpm_text.is_empty():
		return ""
	if bpm_text.is_empty():
		return length_text
	if length_text.is_empty():
		return bpm_text
	return "%s (%s)" % [length_text, bpm_text]


func _get_chart_bpm_text(chart: Chart) -> String:
	if chart == null or chart.timings.is_empty():
		return ""

	var min_bpm := INF
	var max_bpm := -INF

	for timing in chart.timings:
		if timing == null or timing.bpm <= 0.0:
			continue
		min_bpm = minf(min_bpm, timing.bpm)
		max_bpm = maxf(max_bpm, timing.bpm)

	if min_bpm == INF or max_bpm == -INF:
		return ""
	if is_equal_approx(min_bpm, max_bpm):
		return "%s BPM" % _format_bpm(min_bpm)
	return "%s-%s BPM" % [_format_bpm(min_bpm), _format_bpm(max_bpm)]


func _format_bpm(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return str(int(round(value)))
	return ("%.1f" % value).rstrip("0").rstrip(".")


func _get_chart_length_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var cache_key := chart.uuid if not chart.uuid.is_empty() else chart.file_path
	if _stream_length_cache.has(cache_key):
		return _format_duration(_stream_length_cache[cache_key])

	var stream := chart.get_stream()
	if stream == null:
		return ""

	var length_sec := stream.get_length()
	if length_sec <= 0.0:
		return ""

	_stream_length_cache[cache_key] = length_sec
	return _format_duration(length_sec)


func _format_duration(length_sec: float) -> String:
	var total_seconds = max(0, int(round(length_sec)))
	var minutes = total_seconds / 60
	var seconds = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]


func _build_difficulty_text(chart: Chart) -> String:
	if chart == null:
		return ""

	var difficulty := chart.difficulty
	var creator := chart.creator
	var has_difficulty := not difficulty.is_empty() and difficulty != "?"
	var has_creator := not creator.is_empty() and creator != "?"

	if has_difficulty and has_creator:
		return "%s (%s)" % [difficulty, creator]
	if has_difficulty:
		return difficulty
	if has_creator:
		return creator
	return ""


func _is_visual_resting() -> bool:
	if absf(rotation_degrees) > 0.05:
		return false
	if scale.distance_to(Vector2.ONE) > 0.001:
		return false
	if thumb.position.distance_to(base_thumb_position) > 0.2:
		return false
	if content.position.distance_to(base_content_position) > 0.2:
		return false
	if hover_strength > 0.01:
		return false
	if absf(press_scale_multiplier - 1.0) > 0.001:
		return false
	return true


func _snap_to_rest_state() -> void:
	press_scale_multiplier = 1.0
	scale = Vector2.ONE
	rotation_degrees = 0.0
	thumb.position = base_thumb_position
	content.position = base_content_position
	shine_uv = Vector2(0.5, 0.5)
	hover_strength = 0.0

	if shine_material != null:
		shine_material.set_shader_parameter("cursor_uv", shine_uv)
		shine_material.set_shader_parameter("hover_strength", hover_strength)

	if panel_style != null:
		panel_style.shadow_offset = SHADOW_BASE_OFFSET
		panel_style.shadow_color = SHADOW_REST_COLOR
		panel_style.shadow_size = 0.0
