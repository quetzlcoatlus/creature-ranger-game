## AIGoal — abstract base class for all goal behaviours.
##
## Add AIGoal subclasses as direct children of a GoalAI node.
## GoalAI calls _process_goal(delta) on every child every frame,
## then picks the child with the highest priority() to execute.
##
## To implement a new goal:
##   1. extends AIGoal
##   2. Override priority() — return > 0.0 when the goal wants control
##   3. Override decide(delta) — write to _ai._move_dir, _ai._do_sprint,
##      or call _ai._request_jump() to drive the creature
##   4. Optionally override _process_goal(delta) for timers / bookkeeping
##   5. Optionally override on_activated() for one-shot setup on takeover

class_name AIGoal
extends Node

## Reference to the owning GoalAI controller.
var _ai       : GoalAI  = null
## Reference to the creature being controlled.
var _creature : Creature = null


func _ready() -> void:
	_ai = get_parent() as GoalAI
	assert(_ai != null, name + ": AIGoal must be a direct child of a GoalAI node")
	_creature = _ai._creature


## Return how urgently this goal wants control right now.
## 0.0  = inactive / not applicable this frame.
## Higher values win.  Suggested tiers:
##   90  = safety / survival
##   85  = sleep (on home tile)
##   50  = pre-sleep homing
##   40  = play / fun terrain
##   0   = wander (always-available fallback)
func priority() -> float:
	return 0.0


## Called every physics frame by GoalAI, even when this goal is not active.
## Use this to maintain internal state (timers, sensor readings, etc.).
func _process_goal(_delta: float) -> void:
	pass


## Called when this goal is active and should drive movement.
## Write to _ai._move_dir (normalised vector or zero to brake),
## set _ai._do_sprint = true to sprint, call _ai._request_jump() to jump.
func decide(_delta: float) -> void:
	pass


## Called once when this goal transitions from inactive → active.
## Use for one-shot setup, e.g. picking an initial target position.
func on_activated() -> void:
	pass


# ─── Terrain helpers ─────────────────────────────────────────────────────────

## Returns the terrain_tag at the creature's current map cell.
func _get_current_terrain_tag() -> int:
	return _get_terrain_tag_at(_creature.global_position)


## Returns the terrain_tag at an arbitrary world position.
## Returns 0 when ground_layer is unset, the tile is empty, or no tag is set.
func _get_terrain_tag_at(world_pos: Vector2) -> int:
	var layer := _creature.ground_layer
	if layer == null:
		return 0
	var local_pos := layer.to_local(world_pos)
	var map_pos   := layer.local_to_map(local_pos)
	var td        := layer.get_cell_tile_data(map_pos)
	if td == null:
		return 0
	return int(td.get_custom_data("terrain_tag"))


# ─── Time helpers ─────────────────────────────────────────────────────────────

## Returns the current in-game hour (0–24).  Falls back to noon when
## no GameEnvironment node is in the "game_environment" group.
func _get_current_hour() -> float:
	var env := get_tree().get_first_node_in_group("game_environment")
	if env == null:
		return 12.0
	return env.hour
