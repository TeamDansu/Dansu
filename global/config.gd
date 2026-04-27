extends Node
class_name AppConfig


#SECTION
const FILE_PATH := "user://config.cfg"
const SECTION_GRAPHICS := "Graphics"
const SECTION_GAMEPLAY := "GamePlay"
const SECTION_KEYBINDS := "KeyBinds"
const SECTION_AUDIO := "Audio"
const SECTION_ETC := "ETC"

## CONST
const FILE_EXTENSION = ".dansu"
const DEFAULT_SKIN_PATH = "res://resorces/skins/danshe/skin.json"
const DEFAULT_API_URL = "https://dansu.h4ya.net/api/v1"

var config := ConfigFile.new()

func apply_settings() -> void:
	max_fps = max_fps
	action_left = action_left
	action_right = action_right
	action_hit1 = action_hit1
	action_hit2 = action_hit2
	ignore_chart_skin = ignore_chart_skin
	window_size = window_size
	window_mode = window_mode
	ticks_per_second = ticks_per_second
	master_db = master_db
	music_db = music_db
	sfx_db = sfx_db
	hit_effect_db = hit_effect_db
	offset = offset
	note_speed = note_speed
	vsync_mode = vsync_mode
	taa = taa
	msaa = msaa
	postaa = postaa
	chart_load_threads = chart_load_threads
	server_api_url = server_api_url
	

var language: String:
	get:
		return str(config.get_value(SECTION_GAMEPLAY, "language", "en"))
	set(value):
		config.set_value(SECTION_GAMEPLAY, "language", value)

## KEY BINDS

func _set_key_event(key_bind:Key,action_name:String):
	if key_bind != 0 and key_bind != KEY_ESCAPE:
		config.set_value(SECTION_KEYBINDS,action_name,key_bind)
		var input_event = InputEventKey.new()
		input_event.physical_keycode = key_bind
		InputMap.action_erase_events(action_name)
		InputMap.action_add_event(action_name, input_event)

var action_left: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_left",KEY_LEFT)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_left",value)
		_set_key_event(value,"action_left")

var action_right: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_right",KEY_RIGHT)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_right",value)
		_set_key_event(value,"action_right")
	
var action_hit1: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_hit1",KEY_Z)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_hit1",value)
		_set_key_event(value,"action_hit1")

var action_hit2: Key:
	get:
		return config.get_value(SECTION_KEYBINDS,"action_hit2",KEY_X)
	set(value):
		config.set_value(SECTION_KEYBINDS,"action_hit2",value)
		_set_key_event(value,"action_hit2")

## GRAPHICS

var max_fps: int:
	get:
		return int(config.get_value(SECTION_GRAPHICS, "max_fps", 0))
	set(value):
		config.set_value(SECTION_GRAPHICS, "max_fps", value)
		Engine.max_fps = value

var window_size: Vector2i:
	get:
		var main_display = DisplayServer.get_primary_screen()
		var screen_size = DisplayServer.screen_get_size(main_display)
		return config.get_value(SECTION_GRAPHICS, "window_size", screen_size) as Vector2i
	set(value):
		get_window().size = value
		config.set_value(SECTION_GRAPHICS, "window_size", value)

var window_mode: DisplayServer.WindowMode:
	get:
		var value = config.get_value(SECTION_GRAPHICS,"window_mode",DisplayServer.WINDOW_MODE_FULLSCREEN)
		if value > 4:
			value = DisplayServer.WINDOW_MODE_FULLSCREEN
		return value
	set(value):
		if value > 4:
			value = DisplayServer.WINDOW_MODE_FULLSCREEN
		config.set_value(SECTION_GRAPHICS,"window_mode",value)
		DisplayServer.window_set_mode(value)

var vsync_mode: DisplayServer.VSyncMode:
	get:
		var value = config.get_value(SECTION_GRAPHICS,"vsync_mode",DisplayServer.VSYNC_ADAPTIVE)
		if value > 4:
			value = DisplayServer.VSYNC_ADAPTIVE
		return value
	set(value):
		if value > 4:
			value = DisplayServer.VSYNC_ADAPTIVE
		config.set_value(SECTION_GRAPHICS,"vsync_mode",value)
		DisplayServer.window_set_vsync_mode(value)

var msaa: Viewport.MSAA:
	get:
		return config.get_value(SECTION_GRAPHICS,"msaa",Viewport.MSAA_2X)
	set(value):
		var vp := get_viewport()
		vp.msaa_3d = value
		config.set_value(SECTION_GRAPHICS,"msaa",value)

var postaa : Viewport.ScreenSpaceAA:
	get:
		return config.get_value(SECTION_GRAPHICS,"post_aa",Viewport.SCREEN_SPACE_AA_FXAA)
	set(value):
		var vp := get_viewport()
		config.set_value(SECTION_GRAPHICS,"post_aa",value)
		vp.screen_space_aa = value

var taa : bool:
	get:
		return config.get_value(SECTION_GRAPHICS,"taa",false)
	set(value):
		var vp := get_viewport()
		vp.use_taa = value
		config.set_value(SECTION_GRAPHICS,"taa",value)

## Gameplay

var ignore_chart_skin: bool:
	get:
		return config.get_value(SECTION_GAMEPLAY,"ignore_chart_skin",false)
	set(value):
		config.set_value(SECTION_GAMEPLAY,"ignore_chart_skin",value)

var custom_skin_path: String:
	get:
		return config.get_value(SECTION_GAMEPLAY,"custom_skin_path","")
	set(value):
		config.set_value(SECTION_GAMEPLAY,"custom_skin_path",value)

var note_speed: float:
	get:
		return config.get_value(SECTION_GAMEPLAY,"note_speed",50)
	set(value):
		config.set_value(SECTION_GAMEPLAY,"note_speed",value)

var ticks_per_second: int:
	get:
		return config.get_value(SECTION_GAMEPLAY,"ticks_per_second",1000)
	set(value):
		config.set_value(SECTION_GAMEPLAY,"ticks_per_second",value)
		Engine.physics_ticks_per_second = value

## Audio
var master_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"master_db",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)
		config.set_value(SECTION_AUDIO,"master_db",value)

var music_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"music_db",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)
		config.set_value(SECTION_AUDIO,"music_db",value)
		
var sfx_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"sfx_db",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)
		config.set_value(SECTION_AUDIO,"sfx_db",value)

var hit_effect_db: float:
	get:
		return config.get_value(SECTION_AUDIO,"hit_effect",1)
	set(value):
		var db = linear_to_db(value)
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("HitEffect"), db)
		config.set_value(SECTION_AUDIO,"hit_effect",value)

var offset: int:
	get:
		return config.get_value(SECTION_AUDIO,"audio_offset",0)
	set(value):
		config.set_value(SECTION_AUDIO,"audio_offset",value)

## ETC

var chart_load_threads: int:
	get:
		return config.get_value(SECTION_ETC,"chart_load_threads",2)
	set(value):
		config.set_value(SECTION_ETC,"chart_load_threads",value)

var server_api_url:
	get:
		return config.get_value(SECTION_ETC,"server_api_url",DEFAULT_API_URL)
	set(value):
		config.set_value(SECTION_ETC,"server_api_url",value)

func _ready() -> void:
	config.load(FILE_PATH)
	save_config()

func save_config() -> void:
	apply_settings()
	config.save(FILE_PATH)
