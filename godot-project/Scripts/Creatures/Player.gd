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
@export var anim_player    : AnimationPlayer
@export var sprite         : Sprite2D
## Artistic sun-cast shadow — slides in sun direction as the player rises.
@export var shadow         : Sprite2D
## Landing indicator — always at ground level directly below the player.
@export var landing_shadow : Sprite2D


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
	dir_input  = Vector2(raw.x, raw.y) * ISO_SCALE
	if dir_input.length() > 1.0:
		dir_input = dir_input.normalized()

	is_sprinting = Input.is_action_pressed("Sprint")

	if Input.is_action_just_pressed("Jump"):
		_start_jump()  # Creature checks is_grounded / is_crouching internally

	if Input.is_action_just_pressed("Crouch") and is_grounded:
		_start_crouch()
	elif Input.is_action_just_released("Crouch"):
		_end_crouch()


# ─── Physics loop ─────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	super._physics_process(delta)   # terrain + input + movement + jump + slide
	_update_visual_offset()
	_update_animation()


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
func _update_animation() -> void:
	var was_moving := is_moving
	is_moving      = velocity.length() > min_speed

	if is_moving != was_moving:
		if is_moving: movement_started.emit()
		else:         movement_stopped.emit()

	if anim_player == null:
		return

	var anim: String
	if not is_grounded:
		anim = "jump"
	elif is_moving:
		anim = _facing_to_anim("walk")
	else:
		anim = _facing_to_anim("idle")

	if anim_player.has_animation(anim) and anim_player.current_animation != anim:
		anim_player.play(anim)


func _facing_to_anim(prefix: String) -> String:
	if abs(facing.x) >= abs(facing.y):
		return prefix + ("_right" if facing.x > 0.0 else "_left")
	else:
		return prefix + ("_down" if facing.y > 0.0 else "_up")
