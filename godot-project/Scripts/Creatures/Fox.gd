## Fox — a curious, grass-dwelling wanderer.
##
## Foxes prefer GRASS (terrain_tag 1). They roam the meadows, occasionally
## detour to explore trees, and turn playful and erratic on ICE (terrain_tag 3).
## Like every creature they head home and sleep through the night.
##
## All behaviour is data-driven by the GoalAI child node — there is no
## per-frame logic in this script. Tune the creature in the Inspector:
##   • Movement stats (max_speed, etc.) on this Creature node.
##   • Habitat preferences on the GoalAI's child goal nodes
##     (GoalWander.terrain_weights, GoalSleep.home_tags, GoalPlay.fun_tags, …).
##
## Sprite note: foxes still use the legacy "abomination001.png" art until
## dedicated fox art exists. The behaviour, not the texture, defines the type.
##
## See docs/CreaturesGuide.md for the full creature/AI architecture.

extends Creature
class_name Fox


func species_id() -> StringName:
	return &"fox"
