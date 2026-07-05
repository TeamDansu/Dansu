extends RefCounted
class_name Score

enum {NONE,MISS,PERPECT_PLUS,PERFECT,GREAT,OK,BAD}
# Timing
enum T {NONE=-1,MISS=105,PERFECT_PLUS=21,PERFECT=42,GREAT=63,OK=84,BAD=105}
# Scores
enum S {MISS=0,PERFECT_PLUS=100,PERFECT=99,GREAT=50,OK=25,BAD=10}
const TRACE_TOP_SCORE := 50.0
const SPIKE_DODGE_SCORE := 25.0

# count of judgement for result
var notes := 0
var perfect_plus := 0
var perfect := 0 
var great := 0
var ok := 0
var bad := 0
var miss := 0

# current score
var score :float = 0
# max score for the map
var max_score :float = 0
var high_combo := 0

var object_hash = ""

func get_judgement(time_gap) -> int:
	if abs(time_gap) < T.PERFECT_PLUS:
		return PERPECT_PLUS
	elif abs(time_gap) < T.PERFECT:
		return PERFECT
	elif abs(time_gap) < T.GREAT:
		return GREAT
	elif abs(time_gap) < T.OK:
		return OK
	elif abs(time_gap) < T.BAD:
		return BAD
	return NONE

func add_note_result(note: Note, judgement: int) -> void:
	var max_points := _get_max_points_for_note(note)
	if judgement == NONE and max_points <= 0.0:
		return

	max_score += max_points
	notes += 1

	var awarded_points := _get_awarded_points_for_note(note, judgement)

	if judgement == PERPECT_PLUS:
		perfect_plus += 1
	elif judgement == PERFECT:
		perfect += 1
	elif judgement == GREAT:
		great += 1
	elif judgement == OK:
		ok += 1
	elif judgement == BAD:
		bad += 1
	elif judgement == MISS:
		miss += 1
	elif judgement == NONE:
		return

	score += awarded_points


func add_spike_dodge(note: Note) -> void:
	var max_points := _get_max_points_for_note(note)
	if max_points <= 0.0:
		return

	max_score += max_points
	score += SPIKE_DODGE_SCORE
	notes += 1
	ok += 1


func _get_max_points_for_note(note: Note) -> float:
	if note == null:
		return S.PERFECT_PLUS

	match int(note.type):
		int(Note.NoteType.TRACE):
			return TRACE_TOP_SCORE
		int(Note.NoteType.SPIKE):
			return SPIKE_DODGE_SCORE
		_:
			return S.PERFECT_PLUS


func _get_awarded_points_for_note(note: Note, judgement: int) -> float:
	if note != null:
		match int(note.type):
			int(Note.NoteType.TRACE):
				if judgement == PERPECT_PLUS:
					return TRACE_TOP_SCORE
				if judgement == MISS:
					return S.MISS
				return 0.0
			int(Note.NoteType.SPIKE):
				if judgement == MISS:
					return S.MISS
				return 0.0

	match judgement:
		PERPECT_PLUS:
			return S.PERFECT_PLUS
		PERFECT:
			return S.PERFECT
		GREAT:
			return S.GREAT
		OK:
			return S.OK
		BAD:
			return S.BAD
		_:
			return S.MISS

var rank_color: Color:
	get:
		if total_score >= 101.0:
			return Color(0.702, 0.846, 0.935, 1.0)
		if total_score >= 100.0:
			return Color(0.915, 0.643, 0.895, 1.0)
		if total_score >= 99.0:
			return Color(0.977, 0.872, 0.698, 1.0)
		if total_score >= 95.0:
			return Color(0.965, 0.925, 0.745, 1.0)
		if total_score >= 90.0:
			return Color("c6fbb7ff")
		if total_score >= 85.0:
			return Color(0.902, 0.518, 0.565, 1.0)
		if total_score >= 70.0:
			return Color(0.22, 0.191, 0.215, 1.0)
		return Color(0.274, 0.062, 0.071, 1.0)

var rank_str: String:
	get:
		if total_score >= 101.0:
			return "X+"
		if total_score >= 100.0:
			return "SS"
		if total_score >= 99.0:
			return "S+"
		if total_score >= 95.0:
			return "S"
		if total_score >= 90.0:
			return "A"
		if total_score >= 85.0:
			return "B"
		if total_score >= 70.0:
			return "C"
		return "D"

var total_score: float:
	get:
		if notes == 0:
			return 0.0
		if _is_all_just_result():
			return minf(101.0, 100.0 + (float(perfect_plus) / float(notes)))
		if max_score <= 0.0:
			return 0.0
		return score / max_score * 100.0

func _is_all_just_result() -> bool:
	return great == 0 and ok == 0 and bad == 0 and miss == 0
