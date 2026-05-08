## Creature — base class for all living things in the world.
##
## Handles movement, jump physics, and terrain-driven stat modifiers.
## Subclasses set `dir_input` each frame to drive movement:
##   - Player  → reads from InputMap
##   - AI      → reads from an AIController child node
##
## Terrain system
## ──────────────
## Point `ground_layer` at the TileMapLayer that carries terrain data.
## Add Custom Data Layers to its TileSet in the editor:
##   • "speed_mod"    float  (1.0 = normal, 0.5 = half speed)
##   • "jump_mod"     float  (1.0 = normal, 0.7 = reduced jump)
##   • "friction_mod" float  (1.0 = normal, 0.08 = icy)
##   • "turn_mod"     float  (1.0 = normal, 0.2 = hard to turn)
##   • "terrain_tag"  int    (0 = neutral, 1 = grass, 2 = sand, 3 = ice)
## Tiles that have no value set default to 1.0 / 0 (no effect).
## The `terrain_changed` signal fires whenever the creature crosses into
## a tile with different modifiers — hook it for footstep sounds, particles, etc.

extends CharacterBody2D
class_name Creature

# ─── Movement ────────────────────────────────────────────────────────────────
@export_group("Movement")
@export var max_speed         : float = 40.0
@export var min_speed         : float = 8.0
@export var time_to_max       : float = 0.1
@export var time_to_stop      : float = 0.05
@export var time_to_turn      : float = 0.05
## Sprint raises the speed cap.  Set is_sprinting = true to activate.
@export var sprint_max_mult   : float = 1.6
## Fraction of max_speed while crouching.
@export var crouch_speed_mult : float = 0.5

# Derived — recomputed from exports in _ready().
var _accel      : float
var _friction   : float
var _turn_speed : float

## Isometric projection scale applied to raw input before movement.
const ISO_SCALE := Vector2(1.0, 0.5)

# ─── Jump (fake Z-axis) ──────────────────────────────────────────────────────
@export_group("Jump")
@export var jump_height    : float = 8.0
@export var jump_gravity   : float = 420.0
@export var jump_rise_mult : float = 0.55
@export var jump_fall_mult : float = 1.6

var z_offset     := 0.0
var z_velocity   := 0.0
var is_grounded  := true
var is_crouching := false
var is_sprinting := false  # set by input or AI each frame

# ─── Terrain ─────────────────────────────────────────────────────────────────
@export_group("Terrain")
## TileMapLayer to sample for terrain custom data.
## Leave unset to skip terrain reading (all modifiers stay at 1.0).
@export var ground_layer : TileMapLayer

## Current terrain multipliers — updated every physics frame.
var terrain_speed_mod    : float = 1.0
var terrain_jump_mod     : float = 1.0
var terrain_friction_mod : float = 1.0  # < 1.0 = slippery (ice); 1.0 = normal
var terrain_turn_mod     : float = 1.0  # < 1.0 = hard to turn (ice); 1.0 = normal
var _prev_speed_mod      : float = 1.0
var _prev_jump_mod       : float = 1.0
var _prev_friction_mod   : float = 1.0
var _prev_turn_mod       : float = 1.0
var _prev_terrain_tag    : int   = 0    # last tag emitted to TagRegistry

# ─── Movement state ───────────────────────────────────────────────────────────
## Set this to drive movement.  Zero = apply friction only.
var dir_input  := Vector2.ZERO
var facing     := Vector2.RIGHT
var is_moving  := false

# ─── Footsteps ───────────────────────────────────────────────────────────────
@export_group("Footsteps")
## Volume (dB) of this creature's looping footstep audio.
## Set lower on AI creatures so they don't drown out the player.
@export var footstep_volume_db : float = -6.0

var _footstep_active  : bool = false
var _footstep_terrain : int  = 0

# ─── Signals ─────────────────────────────────────────────────────────────────
signal direction_changed(new_facing: Vector2)
signal movement_started()
signal movement_stopped()
signal jumped()
signal landed()
## Fired when the creature crosses into a tile with different modifiers or tag.
## old_tag / new_tag are terrain_tag int values (0 = no tile / neutral).
signal terrain_changed(speed_mod: float, jump_mod: float, friction_mod: float, turn_mod: float, old_tag: int, new_tag: int)

# ─── Node refs ───────────────────────────────────────────────────────────────
@export var collision : CollisionShape2D

@export_group("Visuals")
## Optional: the main body sprite. If set, its Y position is automatically
## updated each frame to reflect z_offset (visual jump height).
## Player manages its own sprite — this is for AI creatures.
@export var body_sprite : Sprite2D


func _ready() -> void:
	_accel      = max_speed / time_to_max
	_friction   = max_speed / time_to_stop
	_turn_speed = max_speed / time_to_turn


func _physics_process(delta: float) -> void:
	_gather_input()       # virtual — subclass fills dir_input / sets flags
	_read_terrain()
	_apply_movement(delta)
	_apply_jump_physics(delta)
	move_and_slide()
	_handle_slide_collisions()
	_update_footstep()
	if body_sprite != null:
		body_sprite.position.y = z_offset


## Override in subclasses to populate dir_input, is_sprinting, and trigger
## _start_jump() / _start_crouch() / _end_crouch().
## Note: AIController child nodes set dir_input directly before this runs.
func _gather_input() -> void:
	pass


# ─── Terrain ─────────────────────────────────────────────────────────────────
func _read_terrain() -> void:
	if ground_layer == null:
		terrain_speed_mod    = 1.0
		terrain_jump_mod     = 1.0
		terrain_friction_mod = 1.0
		terrain_turn_mod     = 1.0
		return

	var local_pos := ground_layer.to_local(global_position)
	var map_pos   := ground_layer.local_to_map(local_pos)
	var td        := ground_layer.get_cell_tile_data(map_pos)

	if td == null:
		terrain_speed_mod    = 1.0
		terrain_jump_mod     = 1.0
		terrain_friction_mod = 1.0
		terrain_turn_mod     = 1.0
	else:
		# get_custom_data returns 0.0 for unset float layers — treat as 1.0.
		var spd   : float = td.get_custom_data("speed_mod")
		var jmp   : float = td.get_custom_data("jump_mod")
		var frict : float = td.get_custom_data("friction_mod")
		var turn  : float = td.get_custom_data("turn_mod")
		terrain_speed_mod    = spd   if spd   > 0.0 else 1.0
		terrain_jump_mod     = jmp   if jmp   > 0.0 else 1.0
		terrain_friction_mod = frict if frict > 0.0 else 1.0
		terrain_turn_mod     = turn  if turn  > 0.0 else 1.0

	# ── Terrain tag (update TagRegistry before emitting terrain_changed) ────────
	var new_tag : int = 0 if td == null else int(td.get_custom_data("terrain_tag"))
	var old_tag : int = _prev_terrain_tag
	if new_tag != old_tag:
		if has_node("/root/TagRegistry"):
			if old_tag != 0:
				TagRegistry.remove_tag(_terrain_tag_name(old_tag), self)
			if new_tag != 0:
				TagRegistry.add_tag(_terrain_tag_name(new_tag), self, _terrain_tag_priority())
		_prev_terrain_tag = new_tag

	# ── terrain_changed signal ────────────────────────────────────────────────
	var mods_changed := (not is_equal_approx(terrain_speed_mod,    _prev_speed_mod)
		or not is_equal_approx(terrain_jump_mod,     _prev_jump_mod)
		or not is_equal_approx(terrain_friction_mod, _prev_friction_mod)
		or not is_equal_approx(terrain_turn_mod,     _prev_turn_mod))
	if mods_changed or new_tag != old_tag:
		_prev_speed_mod    = terrain_speed_mod
		_prev_jump_mod     = terrain_jump_mod
		_prev_friction_mod = terrain_friction_mod
		_prev_turn_mod     = terrain_turn_mod
		terrain_changed.emit(terrain_speed_mod, terrain_jump_mod, terrain_friction_mod, terrain_turn_mod, old_tag, new_tag)


## Override in subclasses to change this creature's terrain tag priority.
## Player returns 3 (overrides AI creatures at priority 2).
func _terrain_tag_priority() -> int:
	return 2


## Maps a terrain_tag int to the string name used in TagRegistry.
static func _terrain_tag_name(tag: int) -> String:
	match tag:
		1: return "grass"
		2: return "sand"
		3: return "ice"
		4: return "water"
		5: return "tree"
		6: return "stone"
		_: return "terrain:" + str(tag)


# ─── Jump ─────────────────────────────────────────────────────────────────────
func _start_jump() -> void:
	if not is_grounded or is_crouching:
		return
	# Jump height is modified by the current tile — computed fresh each jump.
	z_velocity  = -sqrt(2.0 * jump_gravity * (jump_height * terrain_jump_mod))
	is_grounded = false
	jumped.emit()
	if collision:
		collision.disabled = true


func _apply_jump_physics(delta: float) -> void:
	if is_grounded:
		return
	var grav_mult := jump_rise_mult if z_velocity < 0.0 else jump_fall_mult
	z_velocity   += jump_gravity * grav_mult * delta
	z_offset     += z_velocity * delta
	if z_offset >= 0.0:
		z_offset    = 0.0
		z_velocity  = 0.0
		is_grounded = true
		landed.emit()
		if collision:
			collision.disabled = false


# ─── Crouch ───────────────────────────────────────────────────────────────────
func _start_crouch() -> void:
	is_crouching = true

func _end_crouch() -> void:
	is_crouching = false


# ─── Movement ────────────────────────────────────────────────────────────────
func _apply_movement(delta: float) -> void:
	if dir_input != Vector2.ZERO:
		_accelerate(delta)
		_clamp_speed()
		_track_facing()
	else:
		_apply_friction(delta)


func _current_max_speed() -> float:
	var base := max_speed * terrain_speed_mod
	if is_crouching:  return base * crouch_speed_mult
	if is_sprinting:  return base * sprint_max_mult
	return base


func _accelerate(delta: float) -> void:
	var turning := not dir_input.normalized().is_equal_approx(velocity.normalized())
	var rate    := _turn_speed * terrain_turn_mod if turning else _accel
	if is_crouching:  rate *= 0.4
	elif is_sprinting: rate *= 1.8
	velocity += dir_input * rate * delta


func _clamp_speed() -> void:
	var limit := _current_max_speed()
	if velocity.length() > limit:
		velocity = velocity.normalized() * limit


func _apply_friction(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	velocity -= velocity.normalized() * _friction * terrain_friction_mod * delta
	if velocity.length() < min_speed:
		velocity = Vector2.ZERO


func _track_facing() -> void:
	var new_facing := velocity.normalized() if velocity.length() > 0.0 else dir_input.normalized()
	if not new_facing.is_equal_approx(facing):
		facing = new_facing
		direction_changed.emit(facing)


# ─── Footstep ────────────────────────────────────────────────────────────────
func _update_footstep() -> void:
	if not has_node("/root/EventBus"):
		return
	var moving := is_grounded and velocity.length() > min_speed
	var tag    := _prev_terrain_tag
	if moving:
		if not _footstep_active or tag != _footstep_terrain:
			_footstep_active  = true
			_footstep_terrain = tag
			EventBus.footstep_start.emit(self, tag, global_position)
	else:
		if _footstep_active:
			_footstep_active = false
			EventBus.footstep_stop.emit(self)


# ─── Collision ────────────────────────────────────────────────────────────────
func _handle_slide_collisions() -> void:
	for i in get_slide_collision_count():
		var col   : KinematicCollision2D = get_slide_collision(i)
		var other := col.get_collider()
		if other == null:
			continue
		if other is RigidBody2D:
			other.apply_central_impulse(col.get_normal() * -60.0)
		elif other is Creature:
			# Mutual nudge: push the other creature away and absorb a bit ourselves.
			other.apply_nudge(-col.get_normal() * 30.0)
		if other.has_method("on_creature_touch"):
			other.on_creature_touch(self)


# ─── Public helpers ───────────────────────────────────────────────────────────
func teleport(world_pos: Vector2) -> void:
	global_position = world_pos
	velocity        = Vector2.ZERO

func apply_impulse(impulse: Vector2) -> void:
	velocity += impulse
	_clamp_speed()

## Apply a push impulse that can briefly exceed the normal speed cap.
## Used for creature-vs-creature bumping and knockback effects.
## Friction will naturally bleed off the excess over time.
func apply_nudge(impulse: Vector2) -> void:
	velocity += impulse
	# Soft ceiling: allow up to 2.5× normal max to prevent runaway acceleration.
	var nudge_max := _current_max_speed() * 2.5
	if velocity.length() > nudge_max:
		velocity = velocity.normalized() * nudge_max

func is_in_air() -> bool:
	return not is_grounded
