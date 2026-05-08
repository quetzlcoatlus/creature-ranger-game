## AIController — abstract base for all creature AI drivers.
##
## Add as a direct child node of any Creature.  The controller uses a higher
## physics process priority (-1) so its decisions are ready before the parent
## Creature's physics step reads dir_input.
##
## How to implement a new AI:
##   1. extends AIController
##   2. override _decide(delta) — the only method you need
##   3. Inside _decide, write to _move_dir (normalised direction, or ZERO to brake),
##      set _do_sprint = true to sprint, call _request_jump() to attempt a jump
##
## Terrain helpers are provided for reading terrain_tag custom data,
## which drives terrain-aware steering in subclasses like WanderAI.

class_name AIController
extends Node

var _creature : Creature = null

## Desired movement direction this frame (normalised, or zero to stop).
var _move_dir  : Vector2 = Vector2.ZERO
## True to hold sprint this frame.
var _do_sprint : bool    = false
# Internal — set via _request_jump() inside _decide().
var _do_jump   : bool    = false


func _ready() -> void:
	_creature = get_parent() as Creature
	assert(_creature != null,
		str(name) + ": AIController must be a direct child of a Creature node")
	# Run before the parent Creature so dir_input is set before movement is applied.
	process_physics_priority = -1


func _physics_process(delta: float) -> void:
	_move_dir  = Vector2.ZERO
	_do_sprint = false
	_do_jump   = false
	_decide(delta)
	_creature.dir_input    = _move_dir
	_creature.is_sprinting = _do_sprint
	if _do_jump:
		_creature._start_jump()


## Override to implement AI logic each physics frame.
## Set _move_dir (normalised direction or zero), _do_sprint,
## and call _request_jump() to attempt a jump.
func _decide(_delta: float) -> void:
	pass


## Call inside _decide() to request a jump this frame.
func _request_jump() -> void:
	_do_jump = true


# ─── Terrain helpers ─────────────────────────────────────────────────────────

## Returns the terrain_tag at the creature's current position.
## Returns 0 if ground_layer is unset, the tile is empty, or the tag is unset.
func _get_current_terrain_tag() -> int:
	return _get_terrain_tag_at(_creature.global_position)


## Returns the terrain_tag at an arbitrary world position.
## Returns 0 if ground_layer is unset, the tile is empty, or the tag is unset.
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
