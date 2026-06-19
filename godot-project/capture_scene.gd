extends Node2D

@onready var creature_layer: Node2D = $CreatureLayer
@onready var drawing_system: Node2D = $DrawingSystem
@onready var hp_value: Label = $HUD/HPBar/HPValue
@onready var loop_value: Label = $HUD/LoopCounter/LoopValue
@onready var run_away_button: Button = $HUD/RunAwayButton

const MAX_HP := 10
var player_hp := MAX_HP
var creatures_remaining := 0
var _active_creature: CaptureCreature = null

enum SceneResult { SUCCESS, FLED, DEAD }

## Emitted when the encounter ends. SceneManager listens and returns to the
## overworld, removing captured creatures on SUCCESS. `result` is a SceneResult.
signal finished(result: int)


func _ready() -> void:
	drawing_system.creature_layer = creature_layer
	drawing_system.loop_completed.connect(_on_loop_completed)
	drawing_system.line_broke.connect(_on_line_broke)
	drawing_system.line_cleared.connect(_on_line_cleared)
	drawing_system.player_damaged.connect(_on_player_damaged)
	run_away_button.pressed.connect(_on_run_away_pressed)

	var bounds := ($Background/BoundaryRect as ColorRect).get_global_rect()
	for child in creature_layer.get_children():
		var creature := child as CaptureCreature
		if not creature:
			continue
		creatures_remaining += 1
		creature.scene_bounds = bounds
		creature.captured.connect(_on_creature_captured.bind(creature))

	var boundary_rect := $Background/BoundaryRect as ColorRect
	var window := get_tree().root
	window.content_scale_size = Vector2i(boundary_rect.get_rect().size)
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	RenderingServer.set_default_clear_color(boundary_rect.color)

	_update_hp_display()
	_update_loop_display()


func _on_loop_completed(node: Node2D) -> void:
	var creature := node as CaptureCreature
	if not creature:
		return
	_active_creature = creature
	creature.add_loop()
	_update_loop_display()


func _on_line_broke() -> void:
	pass


func _on_line_cleared() -> void:
	_active_creature = null
	for child in creature_layer.get_children():
		var creature := child as CaptureCreature
		if creature:
			creature.reset_loops()
	_update_loop_display()


func _on_player_damaged(amount: int) -> void:
	player_hp -= amount
	_update_hp_display()
	if player_hp <= 0:
		_finish_scene(SceneResult.DEAD)


func _on_creature_captured(_creature: Node2D) -> void:
	creatures_remaining -= 1
	_active_creature = null
	_update_loop_display()
	if creatures_remaining <= 0:
		_finish_scene(SceneResult.SUCCESS)


func _on_run_away_pressed() -> void:
	_finish_scene(SceneResult.FLED)


func _update_hp_display() -> void:
	hp_value.text = str(max(player_hp, 0)) + "/" + str(MAX_HP)


func _update_loop_display() -> void:
	if _active_creature and is_instance_valid(_active_creature):
		loop_value.text = str(_active_creature.loop_count) + "/" + str(_active_creature.loops_needed)
	else:
		loop_value.text = "0"


var _finished := false

func _finish_scene(result: SceneResult) -> void:
	if _finished:
		return  # guard against double-fire (e.g. last capture + flee same frame)
	_finished = true
	match result:
		SceneResult.SUCCESS: print("Capture success! Returning to overworld.")
		SceneResult.FLED:    print("Player fled. Returning to overworld.")
		SceneResult.DEAD:    print("Player fainted.")
	finished.emit(result)
