## GoalSleep — sleep at night, seek home habitat before sleep time.
##
## Priority tiers:
##   85  — during sleep window; stay on home tile (or seek it if not there yet)
##   50  — pre-sleep: seek_home_advance hours before sleep_start_hour
##   0   — otherwise (let lower-priority goals run)
##
## home_tags falls back to safe_tags when empty.
## sleep_start_hour > sleep_end_hour handles midnight-wrapping windows
## (e.g. 21 → 6 means sleep from 9 PM to 6 AM).

class_name GoalSleep
extends AIGoal

## Tags that count as valid sleeping spots.  Falls back to safe_tags if empty.
@export var home_tags         : Array[int] = []
## Tags used as fallback home when home_tags is empty.
@export var safe_tags         : Array[int] = []
## In-game hour (0–24) when the creature wants to be asleep.
@export var sleep_start_hour  : float = 21.0
## In-game hour (0–24) when the creature wakes up.
@export var sleep_end_hour    : float = 6.0
## How many in-game hours before sleep_start_hour to start seeking home.
@export var seek_home_advance : float = 2.0
@export var wander_radius     : float = 60.0
@export var arrival_distance  : float = 5.0

var _home_target : Vector2 = Vector2.ZERO


func priority() -> float:
	var hour := _get_current_hour()
	if _is_sleep_time(hour):
		return 85.0
	if _should_seek_home(hour) and not _is_on_home_tile():
		return 50.0
	return 0.0


func on_activated() -> void:
	if not _is_on_home_tile():
		_home_target = _find_home_position()


func decide(_delta: float) -> void:
	var hour := _get_current_hour()
	# Sleep in place once on a home tile during the sleep window.
	if _is_sleep_time(hour) and _is_on_home_tile():
		_ai._move_dir = Vector2.ZERO
		return
	# Otherwise move toward the home target.
	var to_home := _home_target - _creature.global_position
	if to_home.length() < arrival_distance:
		_home_target = _find_home_position()
		return
	_ai._move_dir = to_home.normalized()


# ─── Internal helpers ─────────────────────────────────────────────────────────

func _effective_home_tags() -> Array[int]:
	return home_tags if not home_tags.is_empty() else safe_tags


func _is_on_home_tile() -> bool:
	var tag  := _get_current_terrain_tag()
	var tags := _effective_home_tags()
	return (tag in tags) or (tags.is_empty() and tag == 0)


func _find_home_position() -> Vector2:
	var tags := _effective_home_tags()
	for _attempt: int in 16:
		var angle     := randf() * TAU
		var dist      := randf_range(5.0, wander_radius * 1.5)
		var candidate := _creature.global_position + Vector2.from_angle(angle) * dist
		var tag       := _get_terrain_tag_at(candidate)
		if (tag in tags) or (tags.is_empty() and tag == 0):
			return candidate
	return _creature.global_position


func _is_sleep_time(hour: float) -> bool:
	if sleep_start_hour < sleep_end_hour:
		# Simple range e.g. 2:00–6:00.
		return hour >= sleep_start_hour and hour < sleep_end_hour
	else:
		# Wraps past midnight e.g. 21:00–6:00.
		return hour >= sleep_start_hour or hour < sleep_end_hour


func _hours_until(from_hour: float, to_hour: float) -> float:
	var d := to_hour - from_hour
	return d if d >= 0.0 else d + 24.0


func _should_seek_home(hour: float) -> bool:
	if _is_sleep_time(hour):
		return false
	return _hours_until(hour, sleep_start_hour) <= seek_home_advance
