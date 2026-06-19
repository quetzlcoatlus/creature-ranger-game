## Urchin — a very slow, ice-loving creature.
##
## Urchins prefer ICE (terrain_tag 3). They creep around the frozen patches,
## sliding a little on the low-friction surface, and avoid sand. They keep close
## to the ice and return to it to sleep at night.
##
## Behaviour is data-driven by the GoalAI child node. Urchins carry no GoalPlay
## or GoalExploreTrees node — they are passive and homebound. Tune in the
## Inspector:
##   • Very low max_speed; ice's own speed_mod (1.4) and low friction give them
##     their characteristic slow glide.
##
## See docs/CreaturesGuide.md for the full creature/AI architecture.

extends Creature
class_name Urchin


func species_id() -> StringName:
	return &"urchin"
