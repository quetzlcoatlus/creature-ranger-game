## Bird — a light, fast creature that lives around trees.
##
## Birds prefer to be NEAR TREES. During the day a GoalExploreTrees node steers
## them from tree to tree (trees live in the ObjectLayer as terrain_tag 5),
## leaving scent so the flock spreads out instead of mobbing one tree.
## They are quick and skittish, wander loosely over grass, and roost on grass
## near the trees to sleep at night.
##
## Behaviour is data-driven by the GoalAI child node. Birds carry no GoalPlay
## node — tree-exploring is their idle activity. Tune in the Inspector:
##   • Higher max_speed than other creatures (they dart between trees).
##   • GoalExploreTrees.search_radius controls how far they look for trees.
##
## See docs/CreaturesGuide.md for the full creature/AI architecture.

extends Creature
class_name Bird


func species_id() -> StringName:
	return &"bird"
