## GoalAI — goals-based AI controller.
##
## Each goal is a child AIGoal node.  Every frame GoalAI:
##   1. Calls _process_goal(delta) on every child (bookkeeping / timers).
##   2. Picks the child with the highest priority().
##   3. Fires on_activated() on the new winner if it changed.
##   4. Calls decide(delta) on the winner to drive movement.
##
## This replaces the monolithic WanderAI state machine with composable,
## individually-configurable behaviour nodes.

class_name GoalAI
extends AIController

var _active_goal : AIGoal = null


# Override _ready so that after super._ready() sets _creature (via AIController),
# we can propagate the reference to all AIGoal children whose own _ready() already
# ran (Godot calls children _ready() before parents).
func _ready() -> void:
	super._ready()
	for child in get_children():
		if child is AIGoal:
			child._creature = _creature


func _decide(delta: float) -> void:
	var best_goal     : AIGoal = null
	var best_priority : float  = -INF

	for child in get_children():
		if child is AIGoal:
			child._process_goal(delta)
			var p : float = child.priority()
			if p > best_priority:
				best_priority = p
				best_goal     = child

	# Fire on_activated only on a genuine transition.
	if best_goal != _active_goal:
		_active_goal = best_goal
		if _active_goal != null:
			_active_goal.on_activated()

	# Let the winning goal drive movement this frame.
	if _active_goal != null:
		_active_goal.decide(delta)
