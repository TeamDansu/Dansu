extends Control
class_name EditorEventPreview

@export var event_editor: EventEditor

var _texture_cache: Dictionary = {}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true

func _draw() -> void:
	var chart := event_editor.chart if event_editor != null else null
	var events := CM.parsed_chart.events if CM.parsed_chart != null else []
	var theme_colors := _evaluate_theme(events, Game.current_time)
	_draw_gradient(theme_colors[0], theme_colors[1])
	_draw_stage_grid()
	_draw_overlays(chart, events, Game.current_time)
	_draw_stage_labels(events, Game.current_time)

func _draw_gradient(top_color: Color, bottom_color: Color) -> void:
	var strips := 48
	for index in range(strips):
		var alpha := float(index) / float(maxi(1, strips - 1))
		var y := size.y * float(index) / float(strips)
		draw_rect(Rect2(0.0, y, size.x, ceilf(size.y / strips) + 1.0), top_color.lerp(bottom_color, alpha))

func _draw_stage_grid() -> void:
	var center := size * 0.5
	for index in range(1, 8):
		var x := size.x * float(index) / 8.0
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), Color(1.0, 1.0, 1.0, 0.045), 1.0)
	for index in range(1, 6):
		var y := size.y * float(index) / 6.0
		draw_line(Vector2(0.0, y), Vector2(size.x, y), Color(1.0, 1.0, 1.0, 0.045), 1.0)
	draw_line(Vector2(center.x, 0.0), Vector2(center.x, size.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	draw_line(Vector2(0.0, center.y), Vector2(size.x, center.y), Color(1.0, 1.0, 1.0, 0.12), 1.0)
	var safe_size := Vector2(minf(size.x * 0.82, size.y * 1.45), minf(size.y * 0.82, size.x / 1.45))
	draw_rect(Rect2(center - safe_size * 0.5, safe_size), Color(1.0, 1.0, 1.0, 0.18), false, 1.0)

func _draw_overlays(chart: Chart, events: Array, time_ms: float) -> void:
	var overlays: Array[OverlayEvent] = []
	for event in events:
		if event is OverlayEvent and time_ms >= event.time and time_ms <= event.end_time:
			overlays.append(event)
	overlays.sort_custom(func(a: OverlayEvent, b: OverlayEvent) -> bool:
		if a.layer == b.layer:
			return a.time < b.time
		return a.layer < b.layer
	)
	for overlay in overlays:
		var state := _evaluate_overlay(overlay, time_ms - overlay.time)
		var sprite_ref := String(state.get("sprite", ""))
		var texture := _load_event_texture(chart, sprite_ref)
		if texture == null:
			continue
		var position: Vector2 = state.get("position", Vector2.ZERO)
		var anchor := OverlayEventFrame.anchor_to_vector(overlay.anchor)
		var scale_value: Vector2 = state.get("scale", Vector2.ONE)
		var rotation := deg_to_rad(float(state.get("rotation", 0.0)))
		var opacity := clampf(float(state.get("opacity", 1.0)), 0.0, 1.0)
		draw_set_transform(size * anchor + position, rotation, scale_value)
		draw_texture(texture, -texture.get_size() * 0.5, Color(1.0, 1.0, 1.0, opacity))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _evaluate_theme(events: Array, time_ms: float) -> Array[Color]:
	var result: Array[Color] = [Color("101018"), Color("1a1c28")]
	var active: ThemeEvent = null
	for event in events:
		if event is ThemeEvent and time_ms >= event.time and time_ms <= event.end_time:
			if active == null or event.time >= active.time:
				active = event
	if active == null or active.frames.is_empty():
		return result
	var pair := _find_frame_pair(active.frames, time_ms - active.time)
	var previous: ThemeEventFrame = pair[0]
	var next: ThemeEventFrame = pair[1]
	var alpha := _frame_alpha(previous, next, time_ms - active.time)
	result[0] = previous.bg_color.lerp(next.bg_color, alpha)
	result[1] = previous.bg_color_2.lerp(next.bg_color_2, alpha)
	return result

func _evaluate_overlay(event: OverlayEvent, local_time: float) -> Dictionary:
	if event.frames.is_empty():
		return {}
	var pair := _find_frame_pair(event.frames, local_time)
	var previous: OverlayEventFrame = pair[0]
	var next: OverlayEventFrame = pair[1]
	var alpha := _frame_alpha(previous, next, local_time)
	var previous_state := _overlay_state_at(event.frames, event.frames.find(previous))
	var next_state := _overlay_state_at(event.frames, event.frames.find(next))
	return {
		"sprite": previous_state["sprite"],
		"position": (previous_state["position"] as Vector2).lerp(next_state["position"], alpha),
		"scale": (previous_state["scale"] as Vector2).lerp(next_state["scale"], alpha),
		"rotation": lerpf(float(previous_state["rotation"]), float(next_state["rotation"]), alpha),
		"opacity": lerpf(float(previous_state["opacity"]), float(next_state["opacity"]), alpha),
	}

func _overlay_state_at(frames: Array[OverlayEventFrame], target_index: int) -> Dictionary:
	var sprite := ""
	var opacity := 1.0
	for index in range(clampi(target_index, 0, frames.size() - 1) + 1):
		if not frames[index].sprite.is_empty():
			sprite = frames[index].sprite
		if frames[index].has_opacity:
			opacity = frames[index].opacity
	var frame := frames[clampi(target_index, 0, frames.size() - 1)]
	return {
		"sprite": sprite,
		"opacity": opacity,
		"position": frame.position,
		"scale": frame.scale,
		"rotation": frame.rotation,
	}

func _find_frame_pair(frames: Array, local_time: float) -> Array:
	var previous = frames[0]
	var next = frames[frames.size() - 1]
	for frame in frames:
		if frame.time <= local_time:
			previous = frame
		if frame.time >= local_time:
			next = frame
			break
	return [previous, next]

func _frame_alpha(previous: ChartEventFrame, next: ChartEventFrame, local_time: float) -> float:
	if previous == next or next.time <= previous.time:
		return 0.0
	var alpha := clampf((local_time - previous.time) / float(next.time - previous.time), 0.0, 1.0)
	return _apply_ease(alpha, next.ease)

func _apply_ease(value: float, ease_name: String) -> float:
	match ease_name:
		"in_sine": return 1.0 - cos(value * PI * 0.5)
		"out_sine": return sin(value * PI * 0.5)
		"in_out_sine": return -(cos(PI * value) - 1.0) * 0.5
		"in_quad": return value * value
		"out_quad": return 1.0 - (1.0 - value) * (1.0 - value)
		"in_out_quad": return 2.0 * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 2.0) * 0.5
		"in_cubic": return value * value * value
		"out_cubic": return 1.0 - pow(1.0 - value, 3.0)
		"in_out_cubic": return 4.0 * value * value * value if value < 0.5 else 1.0 - pow(-2.0 * value + 2.0, 3.0) * 0.5
		_:
			return value

func _load_event_texture(chart: Chart, reference: String) -> Texture2D:
	if chart == null or reference.is_empty() or not EventResourceRef.is_valid(reference):
		return null
	var path := EventResourceRef.resolve_sprite(chart, reference)
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if path.begins_with("res://"):
		texture = load(path) as Texture2D
	elif FileAccess.file_exists(path):
		var image := Image.load_from_file(path)
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	_texture_cache[path] = texture
	return texture

func _draw_stage_labels(events: Array, time_ms: float) -> void:
	var overlay_count := 0
	for event in events:
		if event is OverlayEvent and time_ms >= event.time and time_ms <= event.end_time:
			overlay_count += 1
	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	draw_string(font, Vector2(18.0, 28.0), "STAGE PREVIEW", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.88, 0.91, 0.96, 0.92))
	draw_string(font, Vector2(18.0, 50.0), "%d active overlays" % overlay_count, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size - 2, Color(0.62, 0.67, 0.76, 0.9))
