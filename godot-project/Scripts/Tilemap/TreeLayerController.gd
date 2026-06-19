## TreeLayerController — adds glow + per-tree cast shadows to the ObjectLayer.
##
## Attaches to the ObjectLayer TileMapLayer. The layer renders its own tiles
## (trees and any other objects) exactly as the editor shows them — we do NOT
## re-spawn tree sprites by hand anymore, because reproducing Godot's tile
## placement math in script is what caused the editor/runtime misalignment.
## In Godot 4 a y_sort_enabled TileMapLayer depth-sorts its individual tiles
## against sibling nodes (the player, creatures) on its own, so letting the
## layer draw the trees keeps both alignment AND sorting correct for free.
##
## This script now only adds two things on top of the rendered tiles:
##   • Glow:    warm golden overlay (shader material on the layer) at sunrise/sunset.
##   • Shadows: one squashed Sprite2D per tree, direction follows the sun angle.

extends TileMapLayer

const TREE_TAG : int = 5
const SHADOW_Z : int = -1  # same z as BasicTilemapLayer; renders on top via scene order

## Nudge where each tree's shadow is anchored (the trunk base).
## Positive moves the anchor down. Only affects shadows, not the tree art —
## the art is placed by the tile's Texture Origin in the TileSet.
@export var tree_foot_y_offset : int = 0

# ── Glow shader ────────────────────────────────────────────────────────────────
const _SHADER_SRC := """
shader_type canvas_item;

uniform float time_glow  : hint_range(0.0, 1.0) = 0.0;
uniform vec4  glow_color : source_color = vec4(1.0, 0.62, 0.12, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) {
		COLOR = vec4(0.0);
	} else {
		float boost  = 1.0 + time_glow * 0.35;
		vec3  warmed = mix(tex.rgb, tex.rgb * glow_color.rgb * boost, time_glow * 0.55);
		COLOR = vec4(warmed, tex.a);
	}
}
"""

# ── Shadow parameters ─────────────────────────────────────────────────────────
@export var shadow_squash : float = 0.28
@export var shadow_alpha  : float = 0.40
@export var shadow_color  : Color = Color(0.05, 0.05, 0.12)

var _mat         : ShaderMaterial = null
var _shadow_root : Node2D         = null
var _game_env    : Node           = null


func _ready() -> void:
	# Keep the layer visible: it draws the trees itself, perfectly aligned with
	# the editor. Apply the glow shader to the whole layer so the trees glow.
	var sh  := Shader.new()
	sh.code = _SHADER_SRC
	_mat        = ShaderMaterial.new()
	_mat.shader = sh
	material = _mat

	_game_env = get_tree().get_first_node_in_group("game_environment")
	call_deferred("_setup_shadows")


func _process(_delta: float) -> void:
	if _game_env == null:
		return
	if _mat != null:
		_mat.set_shader_parameter("time_glow", _calc_glow(_game_env.hour))
	if _shadow_root != null:
		for child in _shadow_root.get_children():
			if child is Sprite2D:
				_update_shadow(child as Sprite2D)


func _exit_tree() -> void:
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.queue_free()
		_shadow_root = null


# ── Shadow setup ───────────────────────────────────────────────────────────────

func _setup_shadows() -> void:
	if _shadow_root != null and is_instance_valid(_shadow_root):
		_shadow_root.queue_free()

	_shadow_root               = Node2D.new()
	_shadow_root.name          = "TreeShadows"
	_shadow_root.z_as_relative = false
	_shadow_root.z_index       = SHADOW_Z
	get_parent().add_child(_shadow_root)

	for cell in get_used_cells():
		var td := get_cell_tile_data(cell)
		if td == null:
			continue
		if int(td.get_custom_data("terrain_tag")) == TREE_TAG:
			_create_shadow(cell)


func _create_shadow(cell: Vector2i) -> void:
	var source_id    := get_cell_source_id(cell)
	var atlas_coords := get_cell_atlas_coords(cell)
	var ts           := tile_set
	if ts == null:
		return
	var source := ts.get_source(source_id) as TileSetAtlasSource
	if source == null:
		return

	var region    := source.get_tile_texture_region(atlas_coords)
	var atlas_tex := AtlasTexture.new()
	atlas_tex.atlas  = source.texture
	atlas_tex.region = region

	# foot_pos: the trunk base = the tile cell (where the tree "stands"),
	# nudged by tree_foot_y_offset. The Texture Origin keeps the art's base here.
	var foot_pos      := to_global(map_to_local(cell)) + Vector2(0.0, tree_foot_y_offset)
	var sprite_half_h := region.size.y * 0.5

	var shadow            := Sprite2D.new()
	shadow.texture        = atlas_tex
	shadow.texture_filter = TEXTURE_FILTER_NEAREST
	shadow.offset         = Vector2.ZERO
	shadow.global_position = foot_pos
	shadow.set_meta("foot_pos",      foot_pos)
	shadow.set_meta("sprite_half_h", sprite_half_h)

	_shadow_root.add_child(shadow)
	_update_shadow(shadow)


func _update_shadow(shadow: Sprite2D) -> void:
	if _game_env == null:
		return

	var eff_angle     : float = _game_env.sun_angle
	var eff_intensity : float = _game_env.sun_intensity

	var sun_dir    := Vector2.from_angle(deg_to_rad(eff_angle))
	var shadow_dir := -sun_dir

	shadow.modulate = Color(
		shadow_color.r, shadow_color.g, shadow_color.b,
		shadow_alpha * eff_intensity
	)

	var foot_pos      : Vector2 = shadow.get_meta("foot_pos")
	var sprite_half_h : float   = shadow.get_meta("sprite_half_h")
	# base: shadow origin anchored so the bottom of the squashed sprite is at foot_pos.
	var base := foot_pos - shadow_dir * shadow_squash * sprite_half_h
	shadow.transform = Transform2D(
		Vector2(1.0, 0.0),
		shadow_dir * shadow_squash,
		base
	)


# ── Glow curve ────────────────────────────────────────────────────────────────

func _calc_glow(hour: float) -> float:
	return clampf(maxf(_bell(hour, 6.5, 1.2), _bell(hour, 18.5, 1.5)), 0.0, 1.0)


func _bell(x: float, center: float, half_width: float) -> float:
	var d := absf(x - center)
	return 0.0 if d >= half_width else 1.0 - d / half_width
