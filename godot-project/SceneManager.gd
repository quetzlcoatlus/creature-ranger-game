## SceneManager — owns top-level game flow and the overworld ⇄ capture loop.
##
## Lives at the root of Game.tscn. The overworld is instanced and kept in memory
## the whole time; when the player punches creatures we DETACH it (state frozen,
## not freed), run the capture scene, then re-attach the very same overworld. On a
## win we free the exact creatures that were captured — no save/restore needed.

extends Node

const OVERWORLD_SCENE : PackedScene = preload("res://Scenes/OverworldScene.tscn")
const CAPTURE_SCENE   : PackedScene = preload("res://capture_scene.tscn")

## Maps an overworld creature's species_id() to its capture-scene counterpart.
const CAPTURE_CREATURES := {
	"fox":      preload("res://creatures/fox.tscn"),
	"bird":     preload("res://creatures/bird.tscn"),
	"dinosaur": preload("res://creatures/dinosaur.tscn"),
	"urchin":   preload("res://creatures/urchin.tscn"),
}

# capture_scene.gd SceneResult values.
const RESULT_SUCCESS := 0
const RESULT_FLED    := 1
const RESULT_DEAD    := 2

## Seconds to keep collecting punched creatures before launching, so one punch on
## a group (or a quick flurry of punches) becomes a single capture encounter.
@export var batch_window : float = 0.25

## Where capture creatures spawn (inset from the capture scene's 640×480 boundary).
@export var spawn_rect : Rect2 = Rect2(60, 60, 520, 360)

@onready var _tally_label : Label = $HUD/CaptureTally

var _overworld       : Node       = null
var _capture         : Node       = null
var _pending         : Array      = []   # overworld creatures waiting to be sent
var _captured_counts : Dictionary = {}   # species_id -> total captured

# Window stretch settings the capture scene overrides; saved so we can restore them.
var _win_scale_size
var _win_scale_mode
var _win_scale_aspect
var _win_scale_stretch


func _ready() -> void:
	var w := get_window()
	_win_scale_size    = w.content_scale_size
	_win_scale_mode    = w.content_scale_mode
	_win_scale_aspect  = w.content_scale_aspect
	_win_scale_stretch = w.content_scale_stretch

	EventBus.creatures_interacted.connect(_on_creatures_interacted)
	_show_overworld()
	_update_tally()


# ─── Batching punched creatures ───────────────────────────────────────────────
func _on_creatures_interacted(creatures: Array) -> void:
	if _capture != null:
		return  # already in an encounter — ignore further punches
	var was_empty := _pending.is_empty()
	for c in creatures:
		if is_instance_valid(c) and not _pending.has(c):
			_pending.append(c)
	if was_empty and not _pending.is_empty():
		# Open one batching window from the first punch, then launch.
		var t := get_tree().create_timer(batch_window)
		t.timeout.connect(_launch_capture, CONNECT_ONE_SHOT)


# ─── Overworld → capture ──────────────────────────────────────────────────────
func _launch_capture() -> void:
	_pending = _pending.filter(func(c): return is_instance_valid(c))
	if _pending.is_empty():
		return

	_hide_overworld()

	_capture = CAPTURE_SCENE.instantiate()
	var layer : Node = _capture.get_node("CreatureLayer")

	# Replace the capture scene's placeholder creatures with one per punched creature.
	for child in layer.get_children():
		layer.remove_child(child)
		child.free()
	for c in _pending:
		var scene : PackedScene = CAPTURE_CREATURES.get(_species_of(c), null)
		if scene == null:
			continue
		var cc : Node2D = scene.instantiate()
		cc.position = Vector2(
			randf_range(spawn_rect.position.x, spawn_rect.end.x),
			randf_range(spawn_rect.position.y, spawn_rect.end.y)
		)
		layer.add_child(cc)

	_capture.finished.connect(_on_capture_finished, CONNECT_ONE_SHOT)
	add_child(_capture)        # capture_scene._ready() now counts the spawned creatures
	_set_tally_visible(false)


# ─── Capture → overworld ──────────────────────────────────────────────────────
func _on_capture_finished(result: int) -> void:
	if result == RESULT_SUCCESS:
		for c in _pending:
			if is_instance_valid(c):
				var sid := _species_of(c)
				_captured_counts[sid] = int(_captured_counts.get(sid, 0)) + 1
				var p : Node = c.get_parent()  # detach now so it doesn't flash back in
				if p != null:
					p.remove_child(c)
				c.queue_free()               # captured — gone from the overworld for good
		_update_tally()
	_pending.clear()

	if is_instance_valid(_capture):
		_capture.queue_free()
	_capture = null
	_show_overworld()


# ─── Overworld show / hide (detach keeps it alive & paused) ───────────────────
func _show_overworld() -> void:
	if _overworld == null:
		_overworld = OVERWORLD_SCENE.instantiate()
	if _overworld.get_parent() == null:
		add_child(_overworld)
	_restore_window()
	_set_tally_visible(true)


func _hide_overworld() -> void:
	if _overworld != null and _overworld.get_parent() != null:
		remove_child(_overworld)   # detached but still referenced — state preserved


func _restore_window() -> void:
	var w := get_window()
	w.content_scale_size    = _win_scale_size
	w.content_scale_mode    = _win_scale_mode
	w.content_scale_aspect  = _win_scale_aspect
	w.content_scale_stretch = _win_scale_stretch


# ─── HUD tally ────────────────────────────────────────────────────────────────
func _update_tally() -> void:
	if _tally_label == null:
		return
	if _captured_counts.is_empty():
		_tally_label.text = "Captured: none"
		return
	var lines : PackedStringArray = []
	for sid in _captured_counts:
		lines.append("%s: %d" % [String(sid).capitalize(), int(_captured_counts[sid])])
	_tally_label.text = "Captured\n" + "\n".join(lines)


func _set_tally_visible(v: bool) -> void:
	if _tally_label != null:
		_tally_label.visible = v


func _species_of(c: Node) -> String:
	return String(c.species_id()) if c.has_method("species_id") else ""
