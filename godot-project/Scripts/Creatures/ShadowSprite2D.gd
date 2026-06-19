## ShadowSprite2D — reusable sun-cast shadow for any creature.
##
## Drop this as a sibling Sprite2D alongside a creature's body sprite.
## It mirrors the body sprite's texture/frame each frame and applies a
## directional squash transform driven by the GameEnvironment sun angle.
## Works correctly for jumping creatures (z_offset shifts shadow length)
## and non-jumping creatures (shadow stays flat at ground level).
##
## Setup in the scene:
##   • Add a Sprite2D child to your creature, attach this script.
##   • Set target_sprite → the body sprite to mirror.
##   • Set creature → the parent Creature node.
##   • Leave override_sun false to follow GameEnvironment automatically.

extends Sprite2D
class_name ShadowSprite2D

# ─── Required refs ────────────────────────────────────────────────────────────
## The body sprite whose texture and frame this shadow mirrors.
@export var target_sprite : Sprite2D
## The Creature node — used to read z_offset (visual jump height).
@export var creature      : Creature

# ─── Sun fallback ─────────────────────────────────────────────────────────────
@export_group("Sun Fallback")
## Sun angle used when override_sun is true or GameEnvironment is absent.
@export var sun_angle_deg        : float = 215.0
@export var shadow_length_factor : float = 1.2
@export var shadow_squash        : float = 0.3
@export var shadow_alpha_ground  : float = 0.45
@export var shadow_alpha_air     : float = 0.12
@export var shadow_color         : Color = Color(0.05, 0.05, 0.12)
## When true, use sun_angle_deg above instead of GameEnvironment.
@export var override_sun         : bool  = false

var _game_env : Node = null


func _ready() -> void:
	_game_env = get_tree().get_first_node_in_group("game_environment")


func _process(_delta: float) -> void:
	if target_sprite == null or creature == null:
		return
	_sync_from_target()
	_update_transform()


# ─── Internal ─────────────────────────────────────────────────────────────────
func _sync_from_target() -> void:
	# Mirror texture and animation frame from the body sprite.
	texture = target_sprite.texture
	if hframes != target_sprite.hframes: hframes = target_sprite.hframes
	if vframes != target_sprite.vframes: vframes = target_sprite.vframes
	frame  = target_sprite.frame
	flip_h = target_sprite.flip_h
	# Shadow always renders one layer behind the creature.
	z_index = creature.z_index - 1


func _update_transform() -> void:
	var eff_angle     : float = sun_angle_deg
	var eff_intensity : float = 1.0
	if not override_sun and _game_env != null:
		eff_angle     = _game_env.sun_angle
		eff_intensity = _game_env.sun_intensity

	# height > 0 while in the air (z_offset is negative when up).
	var height := -creature.z_offset
	var t      := clampf(height / maxf(creature.jump_height, 0.01), 0.0, 1.0)

	modulate = Color(
		shadow_color.r, shadow_color.g, shadow_color.b,
		lerpf(shadow_alpha_ground, shadow_alpha_air, t) * eff_intensity
	)

	var sun_dir       := Vector2.from_angle(deg_to_rad(eff_angle))
	var shadow_dir    := -sun_dir
	# ground_offset slides the shadow away from the body as height increases.
	var ground_offset := shadow_dir * height * shadow_length_factor

	# Build transform directly: x-axis unchanged, y-axis collapsed onto shadow
	# direction (squash), translation is the ground-level offset.
	transform = Transform2D(
		Vector2(target_sprite.scale.x, 0.0),
		shadow_dir * target_sprite.scale.y * shadow_squash,
		ground_offset
	)
