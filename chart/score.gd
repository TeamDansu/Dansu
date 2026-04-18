extends Node
class_name Score

enum {NONE,MISS,PERPECT_PLUS,PERFECT,GREAT,OK,BAD}
enum T {NONE=-1,MISS=105,PERFECT_PLUS=21,PERFECT=42,GREAT=63,OK=84,BAD=105}
enum S {MISS=0,PERFECT_PLUS=100,PERFECT=99,GREAT=50,OK=25,BAD=10}

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
	var judgement = NONE
	if time_gap < T.PERFECT_PLUS && time_gap > T.PERFECT_PLUS * -1:
		judgement = PERPECT_PLUS
	elif time_gap < T.PERFECT && time_gap > T.PERFECT * -1:
		judgement = PERFECT
	elif time_gap < T.GREAT && time_gap > T.GREAT * -1:
		judgement = GREAT
	elif time_gap < T.OK && time_gap > T.OK * -1:
		judgement = OK
	elif time_gap < T.BAD && time_gap > T.BAD * -1:
		judgement = BAD
	add_score(judgement)
	return judgement

func add_score(i):
	if i == NONE:
		return
	max_score += perfect_plus
	notes += 1
	if i == PERPECT_PLUS:
		perfect_plus += 1
		score += S.PERFECT_PLUS
	if i == PERFECT:
		perfect += 1
		score += S.PERFECT
	elif i == GREAT:
		great += 1
		score += S.GREAT
	elif i == OK:
		ok += 1
		score += ok
	elif i == BAD:
		bad += 1
		score += S.BAD
	elif i == MISS:
		miss += 1

var total_score:
	get:
		var f:float = 0
		if notes == 0:
			return 0
		if notes <= perfect_plus + perfect:
			f = (float(perfect_plus) / float(notes)) + 100
		else:
			f = score / max_score * 100
		return f
