extends RefCounted
class_name PlayerAnimation

var id := -1
var frames : Array[Texture2D] = []
var frames_file_name : Array[String] = []
var fps := 10.0
var effect := "none"
var name := "new animation"

var total_time: float:
	get:
		return frames.size() / fps

var time_per_frame: float:
	get:
		return frames.size() / fps

func get_index(time: float) -> int:
	var value = int(time/time_per_frame)
	if value >= frames.size():
		value = frames.size() - 1
	return value
