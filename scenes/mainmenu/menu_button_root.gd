@tool
extends Control
class_name MenuBigButton

@export var bg_color : Color = Color("705bde")

@export var button_text := "PLAY":
	set(value):
		button_text = value
		_update_button()

@export var icon_texture :Texture:
	set(value):
		icon_texture = value
		$Pivot/Icon.texture = value

@export var hover_scale := 1.1
@export var hover_rotation := -2.0
@export var hover_offset := Vector2(-8, 0)

@export var hover_time := 0.15

@onready var pivot: Control = $Pivot
@onready var background: ColorRect = $Pivot/Background
@onready var button: Button = $Pivot/Button

var tween: Tween

func _ready() -> void:
	await get_tree().process_frame
	
	$Pivot/Background.color = bg_color
	pivot.offset_transform_enabled = true
	background.offset_transform_enabled = true
	background.offset_transform_pivot_ratio = Vector2(0.0, 0.5)

	_update_button()

	background.size = Vector2.ZERO
	background.scale = Vector2.ONE
	background.offset_transform_scale = Vector2.ZERO
	background.modulate.a = 0.0

	if not Engine.is_editor_hint():
		button.mouse_entered.connect(_hover_enter)
		button.mouse_exited.connect(_hover_exit)
		button.pressed.connect(_pressed)


func _update_button() -> void:
	if not is_node_ready():
		return

	button.text = button_text

	await get_tree().process_frame

	var min_size := button.get_combined_minimum_size()

	background.size.x = min_size.x + 40
	background.size.y = min_size.y + 10
	background.offset_transform_scale = Vector2.ZERO


func _hover_enter() -> void:
	$hover.play()
	_play_hover(true)

func _hover_exit() -> void:
	_play_hover(false)


func _pressed() -> void:
	$click.play(0.1)
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	pivot.offset_transform_scale = Vector2.ONE * 0.96

	tween.tween_property(
		pivot,
		"offset_transform_scale",
		Vector2.ONE * hover_scale,
		0.12
	)


func _play_hover(state: bool) -> void:
	if tween:
		tween.kill()

	tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)

	if state:
		tween.parallel().tween_property(
			pivot,
			"offset_transform_scale",
			Vector2.ONE * hover_scale,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_position",
			hover_offset,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_rotation",
			deg_to_rad(hover_rotation),
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:x",
			1.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:y",
			1.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"modulate:a",
			0.8,
			hover_time
		)

	else:
		tween.parallel().tween_property(
			pivot,
			"offset_transform_scale",
			Vector2.ONE,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_position",
			Vector2.ZERO,
			hover_time
		)

		tween.parallel().tween_property(
			pivot,
			"offset_transform_rotation",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:x",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"offset_transform_scale:y",
			0.0,
			hover_time
		)

		tween.parallel().tween_property(
			background,
			"modulate:a",
			0.0,
			hover_time
		)
