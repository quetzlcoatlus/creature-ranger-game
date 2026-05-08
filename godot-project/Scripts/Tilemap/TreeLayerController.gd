## TreeLayerController — manages tree visuals, glow, and per-tree shadow sprites.
##
## Attaches to the ObjectLayer TileMapLayer, which is used as a data layer only
## (made invisible by this script). One visual Sprite2D is spawned per tree tile
## directly in the parent scene so each tree participates in y_sort against
## characters individually (a TileMapLayer as a whole sorts at y=0, which is
## always behind any character — spawning real nodes fixes this).
##
## Glow: warm golden overlay during sunrise / sunset.
## Shadows: one squashed Sprite2D per tree, direction follows GameEnvironment sun angle.

extends TileMapLayer

const TREE_TAG : int = 5
const SHADOW_Z : int = -1  # same z as BasicTilemapLayer; renders on top via scene order

## Nudge the y foot-anchor of the shadow and y-sort position.
## Positive moves the anchor down. Adjust if the sprite's visual bottom
## isn't exactly at the tile centre after tweaking texture_origin.
@export var tree_foot_y_offset : int = 0

# ── Glow shader ────────────────────────────────────────────────────────────────
const _SHADER_SRC := """
shader_type canvas_item;

uniform float time_glow  : hint_range(0.0, 1.0) = 0.0;
uniform vec4  glow_color : source_color = vec4(1.0, 0.62, 0.12, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	if (tex.a < 0.01) { COLOR = vec4(0.0); return; }
	float boost  = 1.0 + time_glow * 0.35;
	vec3  warmed = mix(tex.rgb, tex.rgb * glow_color.rgb * boost, time_glow * 0.55);
	COLOR = vec4(warmed, tex.a);
}
"""

# ── Shadow parameters ─────────────────────────────────────────────────────────
@export var shadow_squash : float = 0.28
@export var shadow_alpha  : float = 0.40
@export var shadow_color  : Color = Color(0.05, 0.05, 0.12)

var _mat            : ShaderMaterial  = null
var _shadow_root    : Node2D          = null
var _game_env       : Node            = null
var _visual_sprites : Array[Sprite2D] = []


func _ready() -> void:
	# This TileMapLayer is a data store only; GoalExploreTrees still queries it.
	visible = false

	var sh  := Shader.new()
	sh.code = _SHADER_SRC
	_mat        = ShaderMaterial.new()
	_mat.shader = sh

	_game_env = get_tree().get_first_node_in_group("game_environment")
	call_deferred("_setup_trees")


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
	for s in _visual_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_visual_sprites.clear()


# ── Tree + shadow setup ────────────────────────────────────────────────────────

func _setup_trees() -> void:
	for s in _visual_sprites:
		if is_instance_valid(s):
			s.queue_free()
	_visual_sprites.clear()

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
		if int(td.get_custom_data("terrain_tag")) != TREE_TAG:
			continue
		_create_tree(cell, td)


func _create_tree(cell: Vector2i, td: TileData) -> void:
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

	var cell_world    := to_global(map_to_local(cell))
	var sprite_half_h := region.size.y * 0.5
	# foot_pos: the base of the tree sprite in world space (visual bottom).
	# With texture_origin.y = -32 and sprite_half_h = 32 this equals cell_world exactly.
	var foot_pos := cell_world + Vector2(0.0, td.texture_origin.y + sprite_half_h + tree_foot_y_offset)

	# ── Visual sprite ─────────────────────────────────────────────────────────
	# Added directly to the parent scene (OverworldScene) so it is a real node
	# in the y_sort group alongside the player and creatures.
	# global_position.y = foot_pos.y (sprite bottom) → that is the sort key.
	# offset.y = -sprite_half_h shifts the visual up so its bottom sits at global_position.y.
	var vis            := Sprite2D.new()
	vis.texture        = atlas_tex
	vis.texture_filter = TEXTURE_FILTER_NEAREST
	vis.material       = _mat
	vis.offset         = Vector2(0.0, -sprite_half_h)
	vis.global_position = foot_pos
	get_parent().add_child(vis)
	_visual_sprites.append(vis)

	# ── Shadow sprite ─────────────────────────────────────────────────────────
	var shadow              := Sprite2D.new()
	shadow.texture          = atlas_tex
	shadow.texture_filter   = TEXTURE_FILTER_NEAREST
	shadow.offset           = Vector2.ZERO
	shadow.use_parent_material = false

	shadow.global_position = foot_pos
	shadow.set_meta("foot_pos",     foot_pos)
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
