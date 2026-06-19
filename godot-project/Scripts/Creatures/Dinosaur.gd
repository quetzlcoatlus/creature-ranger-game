## Dinosaur — a slow, heavy creature of the dunes.
##
## Dinosaurs prefer SAND (terrain_tag 2). They plod around their sandy home,
## avoid ice, and flee back toward sand if they stray onto other terrain for
## too long (GoalSafety with safe_tags = sand). At night they bed down on the
## sand and sleep.
##
## Behaviour is data-driven by the GoalAI child node. Dinosaurs carry no
## GoalPlay or GoalExploreTrees node — they are content to lumber over the dunes.
## Tune in the Inspector:
##   • Low max_speed and a longer time_to_stop give them weight/momentum.
##
## See docs/CreaturesGuide.md for the full creature/AI architecture.

extends Creature
class_name Dinosaur


func species_id() -> StringName:
	return &"dinosaur"
