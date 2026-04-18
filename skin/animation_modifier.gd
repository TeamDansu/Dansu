extends Node
class_name AnimationModifier

var skindata : PlayerSkinData = null

func add_sprite():
	pass

func remove_sprite():
	pass

func add_animation():
	pass

func change_sprite_file_name(prev_name: String, new_name: String):
	for anim in skindata.animations:
		for file_name in anim.frames_file_name:
			if file_name == prev_name:
				file_name = new_name
	if skindata.texture_cache.has(prev_name):
		skindata.texture_cache.erase(prev_name)
	load_sprite_texture(new_name)

func load_sprite_texture(file_name: String):
	pass

func remove_animation(_anim: PlayerAnimation):
	for note in CM.notes:
		if note.animation == _anim.id:
			note.animation = null
