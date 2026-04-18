extends Sprite3D

@export var effectplayer : AnimationPlayer

var skin : PlayerSkinData
var next_hit_animation_index = 0
var _animation : PlayerAnimation
var _frame_index : int = 0
var _animation_time : float = 0.0

func _ready() -> void:
	return
	_play_animation(skin.anim_idle,false)
	_animation_time = 99999999
	
func _process(delta: float) -> void:
	return
	_animation_time += delta
	if _frame_index != _animation.get_index(_animation_time):
		_frame_index = _animation.get_index(_animation_time)
		texture = _animation.frames[_frame_index]
		offset = Vector2(0,texture.get_size().y / 2)

func set_animation(id: int) -> void:
	_play_animation(skin.get_animation_via_id(id))

func _play_animation(anim: PlayerAnimation,play_effect:bool = true):
	_animation = anim
	_animation_time= 0.0
	_frame_index = 0
	if play_effect:
		match anim.effect:
			anim.EFFECT_NONE:
				pass
			anim.EFFECT_GROOVE:
				effectplayer.play("groove")
			anim.EFFECT_SPIN:
				effectplayer.play("spin")
