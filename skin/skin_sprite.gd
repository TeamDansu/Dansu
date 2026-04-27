extends Sprite3D
class_name PlayerSprite

@export var effectplayer : AnimationPlayer

var skin : PlayerSkinData = PlayerSkinData.new()
var hit_index = 0
var _animation : PlayerAnimation
var _frame_index : int = 0
var _animation_time : float = 0.0

func _setup() -> void:
	if not skin:
		return
	play_animation(skin.idle,true)
	
func _process(delta: float) -> void:
	if not skin or not _animation:
		return
	_animation_time += delta
	if _frame_index != _animation.get_index(_animation_time):
		_frame_index = _animation.get_index(_animation_time)
		texture = _animation.frames[_frame_index]
		offset = Vector2(0,texture.get_size().y / 2)

func play_animation_id(id: int) -> void:
	play_animation(skin.get_animation_via_id(id))

func get_hit_animation() -> PlayerAnimation:
	var size = skin.hits.size()
	if size < 1:
		return skin.idle
	if hit_index >= size:
		hit_index = 0
	var anim = skin.hits[hit_index]
	hit_index += 1
	return anim

func play_animation(anim: PlayerAnimation,play_effect:bool = true):
	if not anim:
		anim = get_hit_animation() 
	_animation = anim
	_animation_time= 0.0
	_frame_index = -1
	if play_effect and anim.effect != "none":
		effectplayer.play(anim.effect)
		effectplayer.seek(0,true,false)
	print(anim.effect)
