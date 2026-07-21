extends Node
class_name DatabaseManager

const DATABASE_PATH := "user://dansu.db"

var connection: DansuDB = null


func _ready() -> void:
	connection = DansuDB.new()
	if not connection.open(DATABASE_PATH):
		push_error("[database] open failed: %s" % connection.get_last_error_message())
		connection = null
		return
	print("[database] opened %s (schema %d, SQLite %s)" % [
		DATABASE_PATH,
		connection.get_schema_version(),
		connection.get_sqlite_version(),
	])


func _exit_tree() -> void:
	if connection != null:
		connection.close()


func is_available() -> bool:
	return connection != null and connection.is_open()
