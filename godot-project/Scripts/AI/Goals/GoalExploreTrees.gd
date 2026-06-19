## GoalExploreTrees — seek out tree tiles during the day, leave scent behind.
##
## Creatures with this goal will explore tree tiles in the ObjectLayer,
## preferring trees with low scent (unvisited or long-ago visited).
## When they arrive at a tree they linger briefly, depositing scent so
## other creatures know someone was already here and should try a different tree.
##
## Priority tier: 35 (below GoalPlay 40, above GoalWander 0).
## Only active during daytime hours (6 – 20).

class_name GoalExploreTrees
extends AIGoal

## World-unit radius to scan for tree tiles.
@export var search_radius    : float = 140.0
## How close the creature must be to "arrive" at a tree.
@export var arrival_distance : float = 8.0
## Base seconds the creature lingers at a tree (±50% randomized per visit).
@export var linger_time      : float = 4.0
## terrain_tag value that marks a tile as a tree (must match TileSet custom data).
@export var tree_terrain_tag : int   = 5
## Scent strength deposited each visit.
@export var scent_deposit    : float = 0.8

var _target_pos   : Vector2      = Vector2.ZERO
var _has_target   : bool         = false
var _linger_timer : float        = 0.0
var _is_lingering : bool         = false
var _object_layer : TileMapLayer = null


func priority() -> float:
	var hour := _get_current_hour()
	if hour < 6.0 or hour >= 20.0:
		return 0.0
	# Only claim priority when trees are actually reachable.
	if not _has_target and not _find_tree_target():
		return 0.0
	return 35.0


func on_activated() -> void:
	_is_lingering = false
	if not _has_target:
		_find_tree_target()


func _process_goal(delta: float) -> void:
	if _is_lingering:
		_linger_timer -= delta


func decide(_delta: float) -> void:
	if _is_lingering:
		_ai._move_dir = Vector2.ZERO
		if _linger_timer <= 0.0:
			_is_lingering = false
			_has_target   = false  # pick a new tree next activation
		return

	if not _has_target:
		if not _find_tree_target():
			return  # no trees found, GoalAI will fall back
	var to_target := _target_pos - _creature.global_position
	if to_target.length() < arrival_distance:
		_on_arrived()
		return
	_ai._move_dir = to_target.normalized()


# ─── Internal ──────────────────────────────────────────────────────────────────

func _on_arrived() -> void:
	if has_node("/root/ScentRegistry"):
		ScentRegistry.deposit(_creature.global_position, scent_deposit)
	_is_lingering = true
	_linger_timer = linger_time * randf_range(0.5, 1.5)  # vary per visit
	_has_target   = false


## Scan the ObjectLayer for tree tiles within search_radius.
## Scores each candidate:  low scent + slight randomness – small distance penalty.
## Returns true if a target was found.
func _find_tree_target() -> bool:
	var layer := _get_object_layer()
	if layer == null:
		return false

	var local_center := layer.to_local(_creature.global_position)
	var center_cell  := layer.local_to_map(local_center)
	# Rough cell radius — isometric tile is 16×8, use 8 as min axis.
	var cell_r       := int(search_radius / 8.0) + 2

	var best_score : float   = -INF
	var best_pos   : Vector2 = Vector2.ZERO
	var found      : bool    = false

	for dx in range(-cell_r, cell_r + 1):
		for dy in range(-cell_r, cell_r + 1):
			var cell := Vector2i(center_cell.x + dx, center_cell.y + dy)
			var td   := layer.get_cell_tile_data(cell)
			if td == null:
				continue
			if int(td.get_custom_data("terrain_tag")) != tree_terrain_tag:
				continue
			var world_pos := layer.to_global(layer.map_to_local(cell))
			var dist      := _creature.global_position.distance_to(world_pos)
			if dist > search_radius:
				continue
			var scent : float = 0.0
			if has_node("/root/ScentRegistry"):
				scent = ScentRegistry.get_scent(world_pos)
			# Prefer unexplored trees; add noise so creatures don't all pick same one.
			var score := -scent * 2.0 + randf() * 0.4 - dist * 0.002
			if score > best_score:
				best_score = score
				best_pos   = world_pos
				found      = true

	if found:
		_target_pos = best_pos
		_has_target = true
	return found


func _get_object_layer() -> TileMapLayer:
	if _object_layer != null and is_instance_valid(_object_layer):
		return _object_layer
	var nodes := get_tree().get_nodes_in_group("object_layer")
	if nodes.is_empty():
		return null
	_object_layer = nodes[0] as TileMapLayer
	return _object_layer
