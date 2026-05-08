## GoalPlay — energetic erratic movement when on "fun" terrain.
##
## Sprints and changes direction frequently while the creature is on
## a tile whose terrain_tag is in fun_tags.

class_name GoalPlay
extends AIGoal

## Terrain tags that trigger playful behaviour.
@export var fun_tags          : Array[int] = []
## Seconds between random direction changes while playing.
@export var play_dir_interval : float = 0.4

var _play_dir_timer : float = 0.0


func _process_goal(delta: float) -> void:
	_play_dir_timer -= delta


func priority() -> float:
	return 40.0 if _get_current_terrain_tag() in fun_tags else 0.0


func decide(_delta: float) -> void:
	_ai._do_sprint = true
	if _play_dir_timer <= 0.0:
		_play_dir_timer = play_dir_interval
		_ai._move_dir   = Vector2.from_angle(randf() * TAU)
