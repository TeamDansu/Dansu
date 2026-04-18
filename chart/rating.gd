extends RefCounted
class_name Rating

const SEGMENT_DURATION_MS := 2000
const POWER := 10.5
const WEIGHT := 2.15

const TYPE_OBSTACLE := 4

static func calculate_rating() -> float:
	if CM.notes.is_empty():
		return 0.0

	var notes: Array = CM.notes.duplicate()
	var rails: Array = CM.rails.duplicate()

	if notes.is_empty() or rails.is_empty():
		return 0.0

	notes.sort_custom(func(a, b): return a.time < b.time)

	var start_time := _get_first_note_time(notes)
	var end_time := _get_last_relevant_time(notes, rails)

	if end_time <= start_time:
		return 0.0

	@warning_ignore("integer_division")
	var segment_count := int((end_time - start_time) / SEGMENT_DURATION_MS) + 1
	var segments: Array[float] = []
	segments.resize(segment_count)
	for i in range(segment_count):
		segments[i] = 0.0

	var notes_by_time := _group_notes_by_time(notes)
	var event_times := _build_event_times(notes, rails)
	if event_times.is_empty():
		return 0.0

	var state := {
		"occupied_rail_id": -1,
		"free_x": 0.0
	}

	for time_ms in event_times:
		_resolve_occupancy_at_time(state, rails, time_ms)

		if notes_by_time.has(time_ms):
			_process_notes_at_time(
				state,
				rails,
				time_ms,
				notes_by_time[time_ms],
				segments,
				start_time
			)

	for i in range(segments.size()):
		segments[i] /= (SEGMENT_DURATION_MS / 1000.0)

	var acc := 0.0
	var valid_count := 0

	for ips in segments:
		if ips > 0.0:
			acc += pow(ips, POWER)
			valid_count += 1

	if valid_count == 0:
		return 0.0

	var mean := pow(acc / valid_count, 1.0 / POWER)
	return mean * WEIGHT

static func _get_first_note_time(notes: Array) -> int:
	if notes.is_empty():
		return 0
	return int(notes[0].time)


static func _get_last_relevant_time(notes: Array, rails: Array) -> int:
	var last_time := 0

	for note in notes:
		last_time = max(last_time, int(note.time))
		last_time = max(last_time, int(note.time) + int(note.length))

	for rail in rails:
		if rail == null:
			continue
		if rail.points.is_empty():
			continue
		last_time = max(last_time, int(rail.points[rail.points.size() - 1].time))

	return last_time


static func _group_notes_by_time(notes: Array) -> Dictionary:
	var result := {}

	for note in notes:
		var time_ms := int(note.time)
		if not result.has(time_ms):
			result[time_ms] = []
		result[time_ms].append(note)

	return result


static func _build_event_times(notes: Array, rails: Array) -> Array[int]:
	var time_map := {}

	for note in notes:
		time_map[int(note.time)] = true

	for rail in rails:
		if rail == null:
			continue
		if rail.points.is_empty():
			continue

		var start_time := int(rail.points[0].time)
		var end_time := int(rail.points[rail.points.size() - 1].time)

		time_map[start_time] = true
		time_map[end_time] = true

	var result: Array[int] = []
	for key in time_map.keys():
		result.append(int(key))

	result.sort()
	return result

static func _resolve_occupancy_at_time(state: Dictionary, rails: Array, time_ms: int) -> void:
	var occupied_rail_id := int(state["occupied_rail_id"])
	var active_rails := _get_sorted_active_rails_at_time(rails, time_ms)

	if occupied_rail_id != -1:
		var occupied_rail = _find_rail_by_id(rails, occupied_rail_id)

		if occupied_rail != null and _is_rail_active_at_time(occupied_rail, time_ms):
			state["free_x"] = occupied_rail._get_rail_x_at_time(time_ms)
			return

		if occupied_rail != null:
			var last_time :int = occupied_rail.end_time
			state["free_x"] = occupied_rail._get_rail_x_at_time(last_time)

		state["occupied_rail_id"] = -1
		occupied_rail_id = -1

	if occupied_rail_id == -1 and not active_rails.is_empty():
		var target_rail = _find_closest_rail_by_x(active_rails, float(state["free_x"]), time_ms)
		if target_rail != null:
			state["occupied_rail_id"] = int(target_rail.id)
			state["free_x"] = target_rail._get_rail_x_at_time(time_ms)


static func _process_notes_at_time(
	state: Dictionary,
	rails: Array,
	time_ms: int,
	note_group: Array,
	segments: Array[float],
	start_time: int
) -> void:
	var active_rails := _get_sorted_active_rails_at_time(rails, time_ms)
	if active_rails.is_empty():
		return

	var blocked_rail_ids := {}
	var playable_notes: Array = []

	for note in note_group:
		var rail_id := int(note.rail)
		if int(note.type) == TYPE_OBSTACLE:
			blocked_rail_ids[rail_id] = true
		else:
			playable_notes.append(note)

	if int(state["occupied_rail_id"]) == -1:
		var auto_rail = _find_closest_rail_by_x(active_rails, float(state["free_x"]), time_ms)
		if auto_rail != null:
			state["occupied_rail_id"] = int(auto_rail.id)
			state["free_x"] = auto_rail._get_rail_x_at_time(time_ms)

	var occupied_rail_id := int(state["occupied_rail_id"])

	if not playable_notes.is_empty():
		var candidate_targets := _collect_unique_playable_target_rails(playable_notes, blocked_rail_ids)

		if candidate_targets.is_empty():
			return

		var best_target_rail_id := _choose_best_target_rail(
			occupied_rail_id,
			candidate_targets,
			active_rails,
			time_ms
		)

		if best_target_rail_id == -1:
			return

		var move_inputs := _get_required_move_inputs_by_order(
			occupied_rail_id,
			best_target_rail_id,
			active_rails
		)

		_add_inputs_at_time(segments, start_time, time_ms, float(move_inputs))

		var note_inputs := 0
		for note in playable_notes:
			if int(note.rail) == best_target_rail_id:
				note_inputs += 1

		_add_inputs_at_time(segments, start_time, time_ms, float(note_inputs))

		state["occupied_rail_id"] = best_target_rail_id
		var target_rail = _find_rail_by_id(rails, best_target_rail_id)
		if target_rail != null:
			state["free_x"] = target_rail._get_rail_x_at_time(time_ms)

		return

	if occupied_rail_id != -1 and blocked_rail_ids.has(occupied_rail_id):
		var safe_target_rail_id := _choose_nearest_safe_rail(
			occupied_rail_id,
			active_rails,
			blocked_rail_ids
		)

		if safe_target_rail_id != -1:
			var evade_inputs := _get_required_move_inputs_by_order(
				occupied_rail_id,
				safe_target_rail_id,
				active_rails
			)

			_add_inputs_at_time(segments, start_time, time_ms, float(evade_inputs))

			state["occupied_rail_id"] = safe_target_rail_id
			var safe_rail: Rail = _find_rail_by_id(rails, safe_target_rail_id)
			if safe_rail != null:
				state["free_x"] = safe_rail._get_rail_x_at_time(time_ms)

static func _collect_unique_playable_target_rails(playable_notes: Array, blocked_rail_ids: Dictionary) -> Array[int]:
	var result: Array[int] = []
	var seen := {}

	for note in playable_notes:
		var rail_id := int(note.rail)
		if blocked_rail_ids.has(rail_id):
			continue
		if seen.has(rail_id):
			continue
		seen[rail_id] = true
		result.append(rail_id)

	return result


static func _choose_best_target_rail(
	occupied_rail_id: int,
	candidate_targets: Array[int],
	active_rails: Array,
	_time_ms: int
) -> int:
	if candidate_targets.is_empty():
		return -1

	if occupied_rail_id == -1:
		return candidate_targets[0]

	var best_target := -1
	var best_cost := INF

	for rail_id in candidate_targets:
		var cost := _get_required_move_inputs_by_order(occupied_rail_id, rail_id, active_rails)
		if cost < best_cost:
			best_cost = cost
			best_target = rail_id

	return best_target


static func _choose_nearest_safe_rail(
	occupied_rail_id: int,
	active_rails: Array,
	blocked_rail_ids: Dictionary
) -> int:
	var current_index := _get_rail_index_in_sorted_active(active_rails, occupied_rail_id)
	if current_index == -1:
		return -1

	var best_rail_id := -1
	var best_cost := INF

	for i in range(active_rails.size()):
		var rail_id := int(active_rails[i].id)
		if rail_id == occupied_rail_id:
			continue
		if blocked_rail_ids.has(rail_id):
			continue

		var cost = abs(i - current_index)
		if cost < best_cost:
			best_cost = cost
			best_rail_id = rail_id

	return best_rail_id


static func _get_required_move_inputs_by_order(
	current_rail_id: int,
	target_rail_id: int,
	active_rails: Array
) -> int:
	if current_rail_id == target_rail_id:
		return 0

	var current_index := _get_rail_index_in_sorted_active(active_rails, current_rail_id)
	var target_index := _get_rail_index_in_sorted_active(active_rails, target_rail_id)

	if current_index == -1 or target_index == -1:
		return 0

	return abs(target_index - current_index)


static func _get_rail_index_in_sorted_active(active_rails: Array[Rail], rail_id: int) -> int:
	for i in range(active_rails.size()):
		if int(active_rails[i].id) == rail_id:
			return i
	return -1


static func _get_sorted_active_rails_at_time(rails: Array[Rail], time_ms: int) -> Array[Rail]:
	var active :Array[Rail]= []

	for rail in rails:
		if rail == null:
			continue
		if _is_rail_active_at_time(rail, time_ms):
			active.append(rail)

	active.sort_custom(func(a:Rail, b:Rail):
		var ax = a._get_rail_x_at_time(time_ms)
		var bx = b._get_rail_x_at_time(time_ms)

		if is_equal_approx(ax, bx):
			return int(a.id) < int(b.id)

		return ax < bx
	)

	return active


static func _is_rail_active_at_time(rail: Rail, time_ms: int) -> bool:
	if rail == null:
		return false
	if rail.points.is_empty():
		return false

	var start_time := rail.start_time
	var end_time := rail.end_time

	return time_ms >= start_time and time_ms <= end_time

static func _find_rail_by_id(rails: Array[Rail], rail_id: int) -> Rail:
	for rail in rails:
		if rail == null:
			continue
		if int(rail.id) == rail_id:
			return rail
	return null


static func _find_closest_rail_by_x(active_rails: Array[Rail], x: float, time_ms: int):
	var best_rail = null
	var best_dist := INF

	for rail in active_rails:
		var rail_x :float = rail._get_rail_x_at_time(time_ms)
		var dist = abs(rail_x - x)

		if dist < best_dist:
			best_dist = dist
			best_rail = rail

	return best_rail

static func _add_inputs_at_time(
	segments: Array[float],
	start_time: int,
	time_ms: int,
	amount: float
) -> void:
	if amount <= 0.0:
		return

	@warning_ignore("integer_division")
	var seg_index := int((time_ms - start_time) / SEGMENT_DURATION_MS)
	if seg_index < 0 or seg_index >= segments.size():
		return

	segments[seg_index] += amount
