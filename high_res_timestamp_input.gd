static var _native = null

static func _get_native():
	if _native == null:
		_native = Engine.get_singleton("TimestampInput")
	return _native

static func is_available() -> bool:
	return _get_native() != null

static func start() -> bool:
	var native = _get_native()
	if native == null:
		return false
	return bool(native.start())

static func stop() -> void:
	var native = _get_native()
	if native == null:
		return
	native.stop()

static func poll_events() -> Array[RawInputEvent]:
	var native = _get_native()
	if native == null:
		return []
	var raw_events: Array = native.poll_events()
	var events: Array[RawInputEvent] = []
	for raw_event in raw_events:
		var event_variant := raw_event as RawInputEvent
		if event_variant != null:
			events.append(event_variant)
	return events

static func get_time_usec() -> int:
	var native = _get_native()
	if native == null:
		return 0
	return int(native.get_time_usec())
