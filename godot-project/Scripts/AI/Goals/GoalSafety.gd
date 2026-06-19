## GoalSafety — flee unsafe terrain before the survival timer expires.
##
## Tracks how long the creature has been on unlisted / unsafe terrain.
## Once the timer exceeds safety_timeout, this goal takes high priority
## and steers the creature toward the nearest safe tile.

class_name GoalSafety
extends AIGoal

## Tags considered indefinitely safe.  Tag 0 (empty / no tile) is always safe.
## Terrain tags outside this list accumulate the unsafe timer.
@export var safe_tags       : Array[int] = []
## Seconds on unsafe terrain before this goal activates.
@export var safety_timeout  : float = 6.0
@export var wander_radius   : float = 60.0
@export var arrival_distance: float = 5.0

var _unsafe_timer  : float   = 0.0
var _safety_target : Vector2 = Vector2.ZERO


func _process_goal(delta: float) -> void:
	var tag := _get_current_terrain_tag()
	if safe_tags.is_empty() or (tag in safe_tags) or tag == 0:
		_unsafe_timer = 0.0
	else:
		_unsafe_timer += delta


func priority() -> float:
	return 90.0 if _unsafe_timer >= safety_timeout else 0.0


func on_activated() -> void:
	_safety_target = _find_safe_position()


func decide(_delta: float) -> void:
	var tag := _get_current_terrain_tag()
	if (tag in safe_tags) or tag == 0:
		_unsafe_timer = 0.0
		return
	var to_safe := _safety_target - _creature.global_position
	if to_safe.length() < arrival_distance:
		_safety_target = _find_safe_position()
		return
	_ai._move_dir = to_safe.normalized()


func _find_safe_position() -> Vector2:
	for _attempt: int in 16:
		var angle     := randf() * TAU
		var dist      := randf_range(10.0, wander_radius * 1.5)
		var candidate := _creature.global_position + Vector2.from_angle(angle) * dist
		var tag       := _get_terrain_tag_at(candidate)
		if (tag in safe_tags) or tag == 0:
			return candidate
	return _creature.global_position
