extends TileMapLayer

## Atlas coords of tiles that mark an explicit collision block.
## Paint these wherever you want a wall or hole boundary —
## the tile itself becomes a collision shape (the "eraser" use case).
@export var solid_atlas_coords: Array[Vector2i] = []

## Atlas coords of tiles that are passable entry points (ramps, transitions).
## All empty cells within `ramp_clearance` hops of these tiles are cleared
## of collision shapes so approach corridors stay fully open.
@export var passthrough_atlas_coords: Array[Vector2i] = []

## How many empty-cell hops from a passthrough tile to clear of collision.
## Increase if your ramp approach corridor is longer than the default.
@export var ramp_clearance: int = 3


func _ready() -> void:
	# Remove any stale collision body left over from a previous run / hot reload.
	var _old := get_parent().get_node_or_null("TileBorderCollision")
	if _old:
		_old.queue_free()

	var all_tiles  := get_used_cells()
	var filled_set: Dictionary = {}
	for t: Vector2i in all_tiles:
		filled_set[t] = true

	# ── Classify every placed tile ────────────────────────────────────────────
	var ground_cells:    Array[Vector2i] = []  # normal walkable → generate edges
	var solid_cells:     Array[Vector2i] = []  # explicit wall → collision at self
	var passthrough_set: Dictionary      = {}  # ramps etc. → BFS-cleared corridors

	for tile: Vector2i in all_tiles:
		var atlas := get_cell_atlas_coords(tile)
		if atlas in solid_atlas_coords:
			solid_cells.append(tile)
		elif atlas in passthrough_atlas_coords:
			passthrough_set[tile] = true
		else:
			ground_cells.append(tile)

	# ── Build collision_cells: empty neighbours of ground tiles ───────────────
	var collision_cells: Dictionary = {}

	for ground_tile: Vector2i in ground_cells:
		for neighbor: Vector2i in get_surrounding_cells(ground_tile):
			if filled_set.has(neighbor):
				continue  # another tile is already here
			# Collision-only: intentionally do NOT paint a visible tile here.
			# The empty edge cell stays empty so the water background shows through,
			# while still getting an invisible wall so the player can't leave the island.
			collision_cells[neighbor] = true

	# Explicit solid tiles: collision sits at the tile's own map position.
	for tile: Vector2i in solid_cells:
		collision_cells[tile] = true

	# ── BFS flood-fill from passthrough tiles to clear approach corridors ─────
	# Spread outward through empty space (not filled tiles unless passthrough),
	# erasing any collision cells found within ramp_clearance hops.
	if not passthrough_set.is_empty() and ramp_clearance > 0:
		# frontier entries: [cell, depth]
		var frontier : Array = []
		var visited  : Dictionary = {}

		for pt: Vector2i in passthrough_set:
			frontier.append([pt, 0])
			visited[pt] = true

		var head := 0
		while head < frontier.size():
			var entry      = frontier[head]
			head += 1
			var cell  : Vector2i = entry[0]
			var depth : int      = entry[1]
			if depth >= ramp_clearance:
				continue
			for nb: Vector2i in get_surrounding_cells(cell):
				if visited.has(nb):
					continue
				# Only traverse into empty space (or other passthrough tiles).
				if filled_set.has(nb) and not passthrough_set.has(nb):
					continue
				visited[nb] = true
				collision_cells.erase(nb)
				frontier.append([nb, depth + 1])

	# ── Build one StaticBody2D with all shapes ────────────────────────────────
	var body := StaticBody2D.new()
	body.name            = "TileBorderCollision"
	body.collision_layer = 1
	body.collision_mask  = 0

	var diamond := PackedVector2Array([
		Vector2(0, -4), Vector2(-8, 0), Vector2(0, 4), Vector2(8, 0),
	])
	for cell: Vector2i in collision_cells:
		var col   := CollisionShape2D.new()
		var shape := ConvexPolygonShape2D.new()
		shape.points = diamond
		col.shape    = shape
		col.position = map_to_local(cell)
		body.add_child(col)

	get_parent().add_child.call_deferred(body)
