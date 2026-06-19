## TagArea — zone-based tag source using Area2D.
##
## Drop this script onto any Area2D node to make it a tag trigger.
## When a Creature (or any CharacterBody2D) enters the area, the tags in
## tags_on_enter are added to TagRegistry.  When it leaves, those tags are
## removed and tags_on_exit (if any) are added.
##
## Priority defaults to 3 so area tags override terrain (priority 2) and
## world/time tags (priority 1).
##
## Usage example — "cave" zone that overrides grass with cave_interior:
##   tags_on_enter = ["cave_interior"]
##   priority      = 3
##
## Usage example — resting zone that forces the "safe_zone" tag:
##   tags_on_enter = ["safe_zone"]
##   one_shot      = true   # remove area once entered

class_name TagArea
extends Area2D

## Tags to add when a Creature enters.
@export var tags_on_enter : Array[String] = []
## Tags to add when a Creature leaves (e.g. "just_left_forest").
@export var tags_on_exit  : Array[String] = []
## Priority used when registering tags.  3 = overrides terrain (2) and world (1).
@export var priority      : int  = 3
## If true, the node removes itself after the first entry.
@export var one_shot      : bool = false

# Track which bodies are inside so we can remove tags on exit.
var _bodies_inside : Array[Node] = []


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Also handle area-exited cleanup if the source node is freed.
	tree_exiting.connect(_on_self_exiting)


func _on_body_entered(body: Node) -> void:
	if not _is_creature(body):
		return
	_bodies_inside.append(body)
	if has_node("/root/TagRegistry"):
		for tag : String in tags_on_enter:
			TagRegistry.add_tag(tag, self, priority)

	if has_node("/root/EventBus"):
		EventBus.area_entered.emit(self, tags_on_enter)

	if one_shot:
		queue_free()


func _on_body_exited(body: Node) -> void:
	if not _is_creature(body):
		return
	_bodies_inside.erase(body)
	if has_node("/root/TagRegistry"):
		for tag : String in tags_on_enter:
			TagRegistry.remove_tag(tag, self)
		for tag : String in tags_on_exit:
			TagRegistry.add_tag(tag, self, priority)

	if has_node("/root/EventBus"):
		EventBus.area_exited.emit(self)


func _on_self_exiting() -> void:
	# Clean up any tags we hold when this node leaves the tree.
	if has_node("/root/TagRegistry"):
		for tag : String in tags_on_enter:
			TagRegistry.remove_tag(tag, self)
		for tag : String in tags_on_exit:
			TagRegistry.remove_tag(tag, self)


static func _is_creature(body: Node) -> bool:
	return body is CharacterBody2D
