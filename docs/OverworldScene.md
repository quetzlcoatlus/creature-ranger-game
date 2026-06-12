# OverworldScene Reference

Node-by-node tour of `Scenes/OverworldScene.tscn` — the main playable world.
For creature AI specifics see [CreaturesGuide.md](CreaturesGuide.md).

```
OverworldScene (Node2D, y_sort_enabled)
├── GameEnvironment      (group "game_environment")   clock / sun / weather
├── CanvasModulate       (group "world_canvas_modulate") global day-night tint
├── BasicTilemapLayer    terrain (grass/sand/ice) + auto border collision
├── ObjectLayer          (group "object_layer")   tree DATA layer (invisible)
├── CharacterBody2D "…"  the Player (script Player.gd, holds the Camera2D)
├── Fox                  creature instances…
├── Bird
├── Dinosaur
└── Urchin
```

## GameEnvironment
`Scripts/World/GameEnvironment.gd`. The world clock and lighting source of
truth, in group `game_environment` so anything can find it. `seconds_per_minute`
= 40 here, so a 24h day passes in ~16 real minutes. Drives `CanvasModulate` tint,
sun angle/intensity (used by shadows), and the day/night state the creatures'
`GoalSleep` reads. Daytime = 06:00–18:00.

## CanvasModulate
Tagged `world_canvas_modulate`. GameEnvironment writes the ambient sky colour
here every frame, giving the whole scene its time-of-day wash.

## BasicTilemapLayer
The walkable terrain, script `TileMapBorderCollision.gd`. Two responsibilities:

1. **Terrain data.** Its TileSet defines five custom data layers —
   `speed_mod`, `jump_mod`, `friction_mod`, `turn_mod` (floats) and
   `terrain_tag` (int, `custom_data_4`). The three atlas sources set:
   - **Grass** → tag 1 (no modifiers)
   - **Sand**  → tag 2, `speed_mod 0.5`, `jump_mod 0.7` (slow, hard to jump)
   - **Ice**   → tag 3, `speed_mod 1.4`, `friction_mod 0.08`, `turn_mod 0.2`
     (fast but slippery and hard to steer)
2. **Auto collision.** On `_ready()` it builds a single `StaticBody2D`
   ("TileBorderCollision") with a diamond collision shape on every empty cell
   bordering the painted terrain — i.e. an invisible wall around the playable
   island. Supports explicit `solid_atlas_coords` (walls) and
   `passthrough_atlas_coords` (ramps that BFS-clear a corridor).

## ObjectLayer
A second `TileMapLayer`, script `TreeLayerController.gd`, in group
`object_layer`. Trees are painted here as tag-5 tiles. The layer is **made
invisible** and used purely as data:

- `GoalExploreTrees` queries it (via the group) to find tree positions.
- On `_ready()` the controller spawns one real `Sprite2D` per tree **into the
  scene root** so each tree y-sorts individually against the player/creatures
  (a whole TileMapLayer would sort at y=0 and always render behind characters).
- It also spawns a squashed shadow sprite per tree that follows the sun, and
  applies a warm glow shader at sunrise/sunset.

## Player
A `CharacterBody2D` running `Player.gd` (a `Creature` subclass). Owns the
`Camera2D` (zoom 5×) and the placeholder "Toby" sprite. Reads WASD/arrow input
(see `[input]` in `project.godot`). `ground_layer` → `../BasicTilemapLayer` so
it gets the same terrain speed/friction effects as creatures.

## Creatures (Fox / Bird / Dinosaur / Urchin)
Four `Creature` instances, each with:
- a species `script` + matching `Sprite2D.texture`,
- `ground_layer` → `../BasicTilemapLayer`,
- a `Shadow` (`ShadowSprite2D.gd`) that mirrors the body sprite and casts a
  sun-driven shadow (lengthens/fades while jumping),
- a `GoalAI` node with the goal children that define its behaviour.

Per-species stats and goal config live in
[SpeciesReference.md](SpeciesReference.md). To add or retune creatures, follow
the recipes in [CreaturesGuide.md](CreaturesGuide.md) §7.

## y-sorting
The root, `BasicTilemapLayer`, and `ObjectLayer` all have `y_sort_enabled`.
Combined with the per-tree real sprites and each creature's foot-anchored
position, this makes characters correctly walk in front of / behind trees.

## Gotchas
- Creature `ground_layer` **must** point at `BasicTilemapLayer`, or terrain
  sensing silently no-ops (all modifiers stay 1.0, terrain_tag stays 0) and the
  AI can't tell grass from ice.
- Trees are tag 5 but live in **ObjectLayer**, not the ground layer — they
  cannot be used as a `GoalSafety`/`GoalSleep` home tag. Tree-seeking is done by
  `GoalExploreTrees` scanning the object layer instead.
- The `TileBorderCollision` body is rebuilt every `_ready()`; don't hand-edit it
  in the scene, it won't persist.
