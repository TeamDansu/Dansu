extends TextureRect

const NORMAL_BRIGHTNESS := 0.75
const SELECTED_BRIGHTNESS := 1.0
const NORMAL_ALPHA := 0.82
const HOVER_ALPHA := 1.0
const NORMAL_SCALE := Vector2.ONE
const SELECTED_SCALE := Vector2(1.06, 1.06)
const HOVER_SCALE := Vector2(1.12, 1.12)
const CLICK_SCALE := Vector2(0.92, 0.92)

var rating := 0.0
var chart : Chart

var hover_tween: Tween
var click_tween: Tween
var appear_tween: Tween
var hovered := false
var base_color := Color.WHITE

func _ready() -> void:
	offset_transform_enabled = true
	offset_transform_pivot_ratio = Vector2(0.5, 0.5)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)
	gui_input.connect(_on_gui_input)
	CM.chart_selected.connect(_update_selected_state)

	base_color = Game.get_color_from_rating(rating)
	$Label.text = str(int(rating))
	modulate.a = NORMAL_ALPHA
	_update_selected_state(CM.selected_chart)


func play_appear_animation(delay: float = 0.0) -> void:
	if appear_tween:
		appear_tween.kill()

	offset_transform_scale = Vector2(0.78, 0.78)
	modulate.a = 0.0

	appear_tween = create_tween()
	appear_tween.set_trans(Tween.TRANS_BACK)
	appear_tween.set_ease(Tween.EASE_OUT)

	if delay > 0.0:
		appear_tween.tween_interval(delay)

	var rest_scale := SELECTED_SCALE if chart != null and chart == CM.selected_chart else NORMAL_SCALE
	appear_tween.tween_property(self, "offset_transform_scale", rest_scale, 0.22)
	appear_tween.parallel().tween_property(self, "modulate:a", NORMAL_ALPHA, 0.18)


func _on_enter() -> void:
	hovered = true
	_apply_hover_state()


func _on_exit() -> void:
	hovered = false
	_apply_hover_state()


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pressed()


func _pressed() -> void:
	if chart == null:
		return

	_play_click_animation()
	if CM.selected_chartset != chart.chart_set:
		CM.select_chartset(chart.chart_set)
	CM.select_chart(chart)


func _apply_hover_state() -> void:
	if hover_tween:
		hover_tween.kill()

	hover_tween = create_tween()
	hover_tween.set_trans(Tween.TRANS_BACK)
	hover_tween.set_ease(Tween.EASE_OUT)

	var rest_scale := SELECTED_SCALE if chart != null and chart == CM.selected_chart else NORMAL_SCALE

	if hovered:
		hover_tween.tween_property(self, "offset_transform_scale", HOVER_SCALE, 0.15)
		hover_tween.parallel().tween_property(self, "modulate:a", HOVER_ALPHA, 0.15)
	else:
		hover_tween.tween_property(self, "offset_transform_scale", rest_scale, 0.2)
		hover_tween.parallel().tween_property(self, "modulate:a", NORMAL_ALPHA, 0.2)


func _play_click_animation() -> void:
	if click_tween:
		click_tween.kill()

	if hover_tween:
		hover_tween.kill()

	click_tween = create_tween()
	click_tween.set_trans(Tween.TRANS_BACK)
	click_tween.set_ease(Tween.EASE_OUT)
	click_tween.tween_property(self, "offset_transform_scale", CLICK_SCALE, 0.05)
	click_tween.tween_property(
		self,
		"offset_transform_scale",
		HOVER_SCALE if hovered else (SELECTED_SCALE if chart != null and chart == CM.selected_chart else NORMAL_SCALE),
		0.14
	)
	click_tween.parallel().tween_property(self, "modulate:a", HOVER_ALPHA if hovered else NORMAL_ALPHA, 0.12)


func _update_selected_state(_selected_chart: Chart) -> void:
	var is_selected := chart != null and chart == CM.selected_chart
	var brightness := SELECTED_BRIGHTNESS if is_selected else NORMAL_BRIGHTNESS
	self_modulate = Color(
		base_color.r * brightness,
		base_color.g * brightness,
		base_color.b * brightness,
		1.0
	)
	if not hovered:
		offset_transform_scale = SELECTED_SCALE if is_selected else NORMAL_SCALE
