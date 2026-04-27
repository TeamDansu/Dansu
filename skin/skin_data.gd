extends RefCounted
class_name PlayerSkinData

enum TYPE { BUILT_IN, IN_CHART, IN_SKIN_FOLDER }

var skin_name: String = "none"

var type : TYPE
var folder_name: String = ""
var json_name: String = ""

var texture_cache = {}

var animations: Array[PlayerAnimation] = []

# player_animation

var idle: PlayerAnimation = null
var left: PlayerAnimation = null
var right: PlayerAnimation = null
var jump: PlayerAnimation = null
var land: PlayerAnimation = null
var hits: Array[PlayerAnimation] = []
var repeat_idle := false

func get_folder_path() -> String:
	match type:
		TYPE.BUILT_IN:
			return "res://resorces/skins/".path_join(folder_name)
		TYPE.IN_CHART:
			return CM.selected_chart.folder_path
		TYPE.IN_SKIN_FOLDER:
			return "user://skins".path_join(folder_name)
	return ""

func parse_objects(_type:TYPE,_folder_name:String,_json_name:String) -> bool:

	type = _type
	folder_name = _folder_name
	json_name = _json_name
	var folder_path = get_folder_path()

	var file = FileAccess.open(folder_path.path_join(json_name), FileAccess.READ)
	if not file:
		push_warning("FILE : %s is missing" , folder_path.path_join(folder_name))
		return false
	var json = JSON.parse_string(file.get_as_text())
	skin_name = json.get(["name"],"new skin")
	if "animations" in json:
		for animation in json["animations"]:
			var _frames = animation.get("frames", [])
			var textures: Array[Texture2D] = []
			for _frame in _frames:
				var _texture = load_texture(_frame)
				if _texture:
					textures.append(_texture)
			var new_animation = PlayerAnimation.new()
			new_animation.id = animation.get("id", -1)
			new_animation.frames = textures
			new_animation.name = animation.get("name", "new animation")
			new_animation.fps = float(animation.get("fps", 10.0))
			new_animation.effect = animation.get("effect","none")
			animations.append(new_animation)
	if "player" in json:
		if "hits" in json["player"]:
			for id in json["player"]["hits"]:
				hits.append(get_animation_via_id(int(id)))
		idle = get_animation_via_id(int(json["player"].get("idle",-1)))
		print((int(json["player"].get("idle",-1))))
		jump = get_animation_via_id(int(json["player"].get("jump",-1)))
		land = get_animation_via_id(int(json["player"].get("land",-1)))
		left = get_animation_via_id(int(json["player"].get("left",-1)))
		right = get_animation_via_id(int(json["player"].get("right",-1)))
		repeat_idle = bool(json["player"]["repeat_idle"])
	
	if not idle:
		return false
	
	return true

func get_animation_via_id(id:int) -> PlayerAnimation:
	if id == -1:
		return
	for animation in animations:
		if animation.id == id:
			return animation
	return null

func load_texture(file_name: String) -> Texture2D:
	if texture_cache.has(file_name):
		return texture_cache[file_name]
	var base_dir = get_folder_path()
	var texture_path = base_dir.path_join("sprite").path_join(file_name)
	var _texture: Texture2D = null

	if texture_path.begins_with("res://"):
		_texture = load(texture_path)

	elif FileAccess.file_exists(texture_path):
		var image = Image.new()
		if image.load(texture_path) == OK:
			_texture = ImageTexture.create_from_image(image)
		else:
			_texture = load("res://resorces/sprite/danshe_dance_1.png")

	if _texture:
		texture_cache[file_name] = _texture

	return _texture
