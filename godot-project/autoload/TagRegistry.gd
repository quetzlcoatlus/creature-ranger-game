## TagRegistry — central, priority-aware storage for all active game tags.
##
## Tags are string identifiers (e.g. "grass", "time:night", "in_combat").
## Any node can add a tag with a source and priority; the highest-priority
## entry wins when multiple sources claim the same tag.
##
## Priority convention (lowest → highest):
##   1 = world  (time of day, weather)
##   2 = terrain (tile the creature is standing on)
##   3 = area   (Area2D zone overrides)
##   99+ = debug / forced overrides
##
## Memory safety: when a source node is freed, all of its tags are
## automatically cleaned up via the tree_exited signal.
##
## Register as autoload named "TagRegistry" in Project → Project Settings → Autoload.

extends Node

## Emitted whenever a tag's active presence changes.
##   added = true  → tag is now active
##   added = false → tag has been removed
signal tag_changed(tag: String, added: bool, source: Node, priority: int)

# tag_name → { "source": Node, "priority": int }
var _tags : Dictionary = {}

# Node → Array[String]  (tags this node is the active winner for)
var _source_tags : Dictionary = {}


# ─── Public API ───────────────────────────────────────────────────────────────

## Add (or upgrade) a tag from source at the given priority.
## If a higher-priority entry already owns this tag, the call is silently ignored.
func add_tag(tag: String, source: Node, priority: int = 1) -> void:
	if _tags.has(tag):
		var existing : Dictionary = _tags[tag]
		if existing["priority"] >= priority:
			return  # Existing entry wins; do nothing.
		# New source outranks the old one — dethrone the previous owner.
		_untrack_source_tag(tag, existing["source"] as Node)

	_tags[tag] = { "source": source, "priority": priority }
	_track_source_tag(tag, source)
	tag_changed.emit(tag, true, source, priority)

	# Mirror to EventBus if present.
	if has_node("/root/EventBus"):
		EventBus.tag_added.emit(tag, source, priority)


## Remove a tag that was previously added by source.
## If a different (higher-priority) source owns the tag, this is a no-op.
func remove_tag(tag: String, source: Node) -> void:
	if not _tags.has(tag):
		return
	var entry : Dictionary = _tags[tag]
	if entry["source"] != source:
		return  # A higher-priority source owns this — don't remove it.
	var priority : int = entry["priority"]
	_tags.erase(tag)
	_untrack_source_tag(tag, source)
	tag_changed.emit(tag, false, source, priority)

	if has_node("/root/EventBus"):
		EventBus.tag_removed.emit(tag, source)


## Returns true if the named tag is currently active.
func has_tag(tag: String) -> bool:
	return _tags.has(tag)


## Returns all currently active tag names.
func get_all_tags() -> Array[String]:
	var result : Array[String] = []
	for key : String in _tags:
		result.append(key)
	return result


## Returns all active tags whose names begin with prefix.
## E.g. get_tags_with_prefix("time:") → ["time:night"]
func get_tags_with_prefix(prefix: String) -> Array[String]:
	var result : Array[String] = []
	for key : String in _tags:
		if key.begins_with(prefix):
			result.append(key)
	return result


# ─── Internal source tracking ─────────────────────────────────────────────────

func _track_source_tag(tag: String, source: Node) -> void:
	if not _source_tags.has(source):
		_source_tags[source] = [] as Array[String]
		# Auto-cleanup when the source is removed from the scene tree.
		source.tree_exited.connect(_on_source_freed.bind(source), CONNECT_ONE_SHOT)
	(_source_tags[source] as Array[String]).append(tag)


func _untrack_source_tag(tag: String, source: Node) -> void:
	if not _source_tags.has(source):
		return
	(_source_tags[source] as Array[String]).erase(tag)
	# Keep the source entry (and its signal connection) until the node is freed.


func _on_source_freed(source: Node) -> void:
	if not _source_tags.has(source):
		return
	# Duplicate so we iterate safely while erasing from _tags.
	var tags : Array[String] = (_source_tags[source] as Array[String]).duplicate()
	for tag : String in tags:
		if _tags.has(tag) and (_tags[tag] as Dictionary)["source"] == source:
			var priority : int = (_tags[tag] as Dictionary)["priority"]
			_tags.erase(tag)
			tag_changed.emit(tag, false, source, priority)
			if has_node("/root/EventBus"):
				EventBus.tag_removed.emit(tag, source)
	_source_tags.erase(source)
