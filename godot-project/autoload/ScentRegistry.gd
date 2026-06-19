## ScentRegistry — global scent trail tracker.
##
## Creatures deposit scent when visiting tiles (e.g. trees).
## Scent decays over time so that fresh/unvisited spots become more attractive.
## Other creatures read scent strength to prefer less-visited locations.
##
## Usage:
##   ScentRegistry.deposit(world_pos)          # leave full scent mark
##   ScentRegistry.get_scent(world_pos)        # 0.0 (fresh) … 1.0 (just visited)
##   ScentRegistry.get_nearby_scent(pos, r)    # average scent in radius

extends Node

## How much scent decays per second (full mark fades in ~1/DECAY_RATE seconds).
const DECAY_RATE  : float = 0.008
const MAX_SCENT   : float = 1.0
## Snap resolution in world pixels — positions within this distance share a cell.
const SNAP_SIZE   : float = 8.0

# Vector2i cell → scent strength (float 0–1)
var _scents : Dictionary = {}


func _process(delta: float) -> void:
	var to_remove : Array = []
	for cell in _scents:
		_scents[cell] = maxf(0.0, _scents[cell] - DECAY_RATE * delta)
		if _scents[cell] <= 0.0:
			to_remove.append(cell)
	for cell in to_remove:
		_scents.erase(cell)


## Deposit a scent mark at world_pos. Strength is clamped to MAX_SCENT.
## Calling this repeatedly on the same cell just refreshes it to MAX_SCENT.
func deposit(world_pos: Vector2, strength: float = MAX_SCENT) -> void:
	var cell := _snap(world_pos)
	_scents[cell] = minf(MAX_SCENT, _scents.get(cell, 0.0) + strength)


## Return the scent strength at world_pos (0.0 = fresh, 1.0 = just visited).
func get_scent(world_pos: Vector2) -> float:
	return _scents.get(_snap(world_pos), 0.0)


## Return the average scent of all marked cells within radius of world_pos.
func get_nearby_scent(world_pos: Vector2, radius: float) -> float:
	if _scents.is_empty():
		return 0.0
	var total  : float = 0.0
	var count  : int   = 0
	var r2     : float = radius * radius
	for cell in _scents:
		var cell_world := Vector2(cell) * SNAP_SIZE
		if cell_world.distance_squared_to(world_pos) <= r2:
			total += _scents[cell]
			count += 1
	return total / count if count > 0 else 0.0


func _snap(pos: Vector2) -> Vector2i:
	return Vector2i(int(pos.x / SNAP_SIZE), int(pos.y / SNAP_SIZE))
