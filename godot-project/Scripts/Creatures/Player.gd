## Player — a Creature driven by keyboard/gamepad input.
##
## All movement stats, jump constants, and terrain reading live in Creature.
## This script only adds:
##   • Input reading (_gather_input override)
##   • Shadow rendering (sun-cast + landing indicator)
##   • Sprite animation

extends Creature
class_name Player

# ─── Sun / Shadow ─────────────────────────────────────────────────────────────
@export_group("Sun")
## Fallback sun angle used when override_sun is true or GameEnvironment is absent.
@export var sun_angle_deg        : float = 215.0
@export var shadow_length_factor : float = 1.2
@export var shadow_squash        : float = 0.3
@export var shadow_alpha_ground  : float = 0.55
@export var shadow_alpha_air     : float = 0.15
@export var shadow_color         : Color = Color(0.05, 0.05, 0.12)
## When true, ignore GameEnvironment and use sun_angle_deg above.
@export var override_sun         : bool  = false

var _sprite_origin_scale := Vector2.ONE
var _game_env            : Node = null

# ─── Node refs ───────────────────────────────────────────────────────────────
@export var sprite         : Sprite2D
## Artistic sun-cast shadow — slides in sun direction as the player rises.
@export var shadow         : Sprite2D
## Landing indicator — always at ground level directly below the player.
@export var landing_shadow : Sprite2D

# ─── Sprite-sheet animation (8-directional) ───────────────────────────────────
# Each sheet is a grid: 8 rows (the facings) × N columns (the animation frames).
# All frames are 64×64. Assign the sheets and tune every knob in the Inspector
# (on the player CharacterBody2D) — nothing here is hardcoded.
@export_group("Sprite Animation")
@export var idle_sheet  : Texture2D
@export var walk_sheet  : Texture2D
@export var run_sheet   : Texture2D
@export var punch_sheet : Texture2D
## Frames per direction (columns) in each sheet.
@export var idle_frames  : int = 8
@export var walk_frames  : int = 12
@export var run_frames   : int = 6
@export var punch_frames : int = 4
## Playback speed, frames per second.
@export var anim_fps     : float = 10.0
## Which sheet ROW to show for each of the 8 facings, in this screen order:
##   0:E  1:SE  2:S  3:SW  4:W  5:NW  6:N  7:NE
## Sheet rows run S(0) → rotating → N(4) → back to S. Front/back are correct
## here; if left/right come out mirrored, use [2, 1, 0, 7, 6, 5, 4, 3] instead.
@export var direction_rows : Array[int] = [6, 7, 0, 1, 2, 3, 4, 5]

const SHEET_ROWS := 8
var _anim_clip   := ""
var _anim_time   := 0.0
var _dir_index   := 2  # default facing S

# ─── Interaction / punch ──────────────────────────────────────────────────────
# The "Interact" action (F key / controller A) plays the punch animation once and
# interacts with every creature within `interact_radius` of a point sitting
# `interact_distance` in front of the player. No damage — just a highlight.
@export_group("Interaction")
## Distance (px) in front of the player where the interaction point sits.
@export var interact_distance : float = 24.0
## Radius (px) around that point; creatures inside it are interacted with.
@export var interact_radius   : float = 20.0
## Punch animation speed (frames/sec). The clip plays through once per press.
@export var punch_fps         : float = 14.0
## Draw the interaction point + radius for tuning (visible while the game runs).
@export var show_interact_gizmo : bool = false

var _punch_time_left := 0.0


func _terrain_tag_priority() -> int:
	return 3  # Player terrain overrides AI creatures (priority 2).


func _ready() -> void:
	super._ready()  # init _accel, _friction, _turn_speed

	add_to_group("player")
	terrain_changed.connect(_on_terrain_changed)

	_game_env = get_tree().get_first_node_in_group("game_environment")

	if sprite != null:
		_sprite_origin_scale = sprite.scale

	for sh: Sprite2D in [shadow, landing_shadow]:
		if sh != null and sprite != null:
			sh.texture = sprite.texture
			sh.hframes = sprite.hframes
			sh.vframes = sprite.vframes


# ─── Terrain (EventBus forwarding) ──────────────────────────────────────────
func _on_terrain_changed(_spd: float, _jmp: float, _frict: float, _turn: float, old_tag: int, new_tag: int) -> void:
	if has_node("/root/EventBus"):
		EventBus.player_terrain_changed.emit(
			Creature._terrain_tag_name(old_tag),
			Creature._terrain_tag_name(new_tag)
		)


# ─── Input (Creature virtual) ────────────────────────────────────────────────
func _gather_input() -> void:
	var raw   := Input.get_vector("Left", "Right", "Up", "Down")
	# Screen-relative: Up/Down/Left/Right go straight on screen. Y is foreshortened
	# so single diagonals (key combos) travel along the tile grid, and the matching
	# SPEED foreshortening in Creature._clamp_speed (iso_y_squash) keeps north/south
	# slower than east/west — the isometric feel without the diagonal disorientation.
	dir_input = Vector2(raw.x, raw.y * iso_y_squash)
	if dir_input.length() > 1.0:
		dir_input = dir_input.normalized()

	is_sprinting = Input.is_action_pressed("Sprint")

	if Input.is_action_just_pressed("Jump"):
		_start_jump()  # Creature checks is_grounded / is_crouching internally

	if Input.is_action_just_pressed("Crouch") and is_grounded:
		_start_crouch()
	elif Input.is_action_just_released("Crouch"):
		_end_crouch()

	if Input.is_action_just_pressed("Interact") and _punch_time_left <= 0.0:
		_do_interact()


# ─── Physics loop ─────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	super._physics_process(delta)   # terrain + input + movement + jump + slide
	_update_animation(delta)
	_update_visual_offset()
	if show_interact_gizmo:
		queue_redraw()


# ─── Crouch (override to squash sprite) ──────────────────────────────────────
func _start_crouch() -> void:
	super._start_crouch()
	if sprite != null:
		sprite.scale = Vector2(_sprite_origin_scale.x, _sprite_origin_scale.y * 0.6)

func _end_crouch() -> void:
	super._end_crouch()
	if sprite != null:
		sprite.scale = _sprite_origin_scale


# ─── Visuals ──────────────────────────────────────────────────────────────────
func _update_visual_offset() -> void:
	if sprite:
		sprite.position.y = z_offset
	_update_shadow()
	_update_landing_shadow()


func _update_shadow() -> void:
	if shadow == null or sprite == null:
		return

	shadow.z_index = z_index - 1

	shadow.texture = sprite.texture
	if shadow.hframes != sprite.hframes: shadow.hframes = sprite.hframes
	if shadow.vframes != sprite.vframes: shadow.vframes = sprite.vframes
	shadow.frame  = sprite.frame
	shadow.flip_h = sprite.flip_h

	var eff_angle     : float = sun_angle_deg
	var eff_intensity : float = 1.0
	if not override_sun and _game_env != null:
		eff_angle     = _game_env.sun_angle
		eff_intensity = _game_env.sun_intensity

	var height := -z_offset
	var t      := clampf(height / jump_height, 0.0, 1.0)
	shadow.modulate = Color(
		shadow_color.r, shadow_color.g, shadow_color.b,
		lerpf(shadow_alpha_ground, shadow_alpha_air, t) * eff_intensity
	)

	var sun_dir       := Vector2.from_angle(deg_to_rad(eff_angle))
	var shadow_dir    := -sun_dir
	var ground_offset := shadow_dir * height * shadow_length_factor
	shadow.transform = Transform2D(
		Vector2(sprite.scale.x, 0.0),
		shadow_dir * sprite.scale.y * shadow_squash,
		ground_offset
	)


func _update_landing_shadow() -> void:
	if landing_shadow == null or sprite == null:
		return

	landing_shadow.z_index = z_index - 1

	landing_shadow.texture = sprite.texture
	if landing_shadow.hframes != sprite.hframes: landing_shadow.hframes = sprite.hframes
	if landing_shadow.vframes != sprite.vframes: landing_shadow.vframes = sprite.vframes
	landing_shadow.frame  = sprite.frame
	landing_shadow.flip_h = sprite.flip_h

	var height        := -z_offset
	var t             := clampf(height / jump_height, 0.0, 1.0)
	var eff_intensity : float = 1.0
	if not override_sun and _game_env != null:
		eff_intensity = maxf(_game_env.sun_intensity, 0.35)
	landing_shadow.modulate = Color(
		shadow_color.r, shadow_color.g, shadow_color.b,
		lerpf(shadow_alpha_ground, shadow_alpha_air, t) * eff_intensity
	)
	landing_shadow.transform = Transform2D(
		Vector2(sprite.scale.x, 0.0),
		Vector2(0.0, sprite.scale.y * shadow_squash),
		Vector2.ZERO
	)


# ─── Animation ───────────────────────────────────────────────────────────────
func _update_animation(delta: float) -> void:
	var was_moving := is_moving
	is_moving      = velocity.length() > min_speed

	if is_moving != was_moving:
		if is_moving: movement_started.emit()
		else:         movement_stopped.emit()

	if sprite == null:
		return

	# Decide the clip. Punch is a one-shot that overrides movement while it runs.
	var clip  := "idle"
	var tex   : Texture2D = idle_sheet
	var cols  : int       = idle_frames
	var fps   : float     = anim_fps
	var loops := true
	if _punch_time_left > 0.0:
		_punch_time_left -= delta
		clip = "punch"; tex = punch_sheet; cols = punch_frames; fps = punch_fps; loops = false
	elif is_moving:
		if is_sprinting: clip = "run";  tex = run_sheet;  cols = run_frames
		else:            clip = "walk"; tex = walk_sheet; cols = walk_frames
	if tex == null:
		return
	cols = maxi(cols, 1)

	# Restart the frame clock when the clip changes.
	if clip != _anim_clip:
		_anim_clip = clip
		_anim_time = 0.0
	_anim_time += delta * fps

	# Hold facing during the punch (you face the way you threw it).
	if clip != "punch":
		_dir_index = _facing_to_dir_index()
	var row : int = direction_rows[_dir_index] if _dir_index < direction_rows.size() else 0
	var col : int = mini(int(_anim_time), cols - 1) if not loops else int(_anim_time) % cols

	sprite.texture = tex
	sprite.hframes = cols
	sprite.vframes = SHEET_ROWS
	sprite.frame   = clampi(row * cols + col, 0, cols * SHEET_ROWS - 1)


## Screen-space facing → one of 8 sectors: 0:E 1:SE 2:S 3:SW 4:W 5:NW 6:N 7:NE
func _facing_to_dir_index() -> int:
	# Un-compress the isometric Y so diagonal facings split evenly.
	var v := Vector2(facing.x, facing.y * 2.0)
	if v.length() < 0.001:
		return _dir_index  # hold the last facing while idle
	var sector := int(round(v.angle() / (PI / 4.0)))
	return ((sector % 8) + 8) % 8


# ─── Interaction ──────────────────────────────────────────────────────────────
## Plays the punch once and interacts with every creature within `interact_radius`
## of a point `interact_distance` in front of the player. No damage is dealt.
func _do_interact() -> void:
	_punch_time_left = float(maxi(punch_frames, 1)) / maxf(punch_fps, 0.001)

	var point := global_position + _interact_dir() * interact_distance
	for node in get_tree().get_nodes_in_group("creatures"):
		if node == self or not (node is Node2D):
			continue
		if (node as Node).is_in_group("player"):
			continue
		var c := node as Node2D
		if c.global_position.distance_to(point) <= interact_radius and c.has_method("interact"):
			c.interact(self)

	if show_interact_gizmo:
		queue_redraw()


## Unit vector for "in front of the player" — current facing, or last facing.
func _interact_dir() -> Vector2:
	return facing.normalized() if facing.length() > 0.001 else Vector2.RIGHT


func _draw() -> void:
	if not show_interact_gizmo:
		return
	var point := _interact_dir() * interact_distance  # local space (player is origin)
	draw_line(Vector2.ZERO, point, Color(1, 1, 0, 0.4), 1.0)
	draw_circle(point, interact_radius, Color(1, 1, 0, 0.12))
	draw_arc(point, interact_radius, 0.0, TAU, 40, Color(1, 1, 0, 0.7), 1.0)
