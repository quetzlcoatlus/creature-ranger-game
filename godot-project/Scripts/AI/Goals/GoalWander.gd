## GoalWander — terrain-weighted random wandering.
##
## Always available as the lowest-priority fallback (priority 0).
## Samples candidate directions and scores them by terrain preference,
## then moves toward the best target until it arrives and picks a new one.

class_name GoalWander
extends AIGoal

## terrain_tag (int) → preference weight.
##   1.0  = preferred,  0.0 = neutral,  -1.0 = avoid.  Unlisted tags = 0.
@export var terrain_weights   : Dictionary = {}
@export var wander_radius     : float = 60.0
@export var arrival_distance  : float = 5.0
## Number of random direction candidates sampled per target pick.
@export var direction_samples : int   = 8

var _wander_target : Vector2 = Vector2.ZERO
var _target_set    : bool    = false  # true once a real target has been picked


func priority() -> float:
	return 0.0  # always available as fallback


func on_activated() -> void:
	_pick_wander_target()


func decide(_delta: float) -> void:
	if not _target_set:
		_pick_wander_target()
		return
	var to_target := _wander_target - _creature.global_position
	if to_target.length() < arrival_distance:
		_pick_wander_target()
		return
	_ai._move_dir = to_target.normalized()


func _pick_wander_target() -> void:
	_target_set = true
	var best_score  : float   = -INF
	var best_target : Vector2 = _creature.global_position

	for _i: int in direction_samples:
		var angle     := randf() * TAU
		var dist      := randf_range(wander_radius * 0.3, wander_radius)
		var offset    := Vector2.from_angle(angle) * dist
		var candidate := _creature.global_position + offset

		var mid_score := _terrain_preference(_get_terrain_tag_at(_creature.global_position + offset * 0.5))
		var end_score := _terrain_preference(_get_terrain_tag_at(candidate))
		var score     := mid_score + end_score + randf() * 0.1

		if score > best_score:
			best_score  = score
			best_target = candidate

	_wander_target = best_target


func _terrain_preference(tag: int) -> float:
	if terrain_weights.has(tag):
		return float(terrain_weights[tag])
	return 0.0
