class_name Creature
extends CharacterBody2D

signal captured

enum BoundaryMode { BOUNCE, WRAP }

## Loops required to capture this creature.
@export var loops_needed: int = 3

## Damage dealt to the player when the drawing line crosses DamageHitbox.
@export var damage_amount: int = 0

## Base movement speed in pixels per second.
@export var speed: float = 100.0

## How far outside the scene boundary the creature may travel (pixels).
## Positive: creature can overshoot by this many pixels before being bounced/wrapped.
## Zero: creature is strictly contained within the boundary.
## Negative: creature is pushed back before reaching the boundary edge.
@export var boundary_overshoot: float = 0.0

## Whether the creature bounces off or wraps around the scene boundary.
@export var boundary_mode: BoundaryMode = BoundaryMode.BOUNCE

## Set by CaptureScene._ready() once the scene is built.
var scene_bounds: Rect2

var loop_count: int = 0

@onready var _loop_label: Label = $LoopLabel


func _physics_process(delta: float) -> void:
	_do_movement(delta)
	move_and_slide()
	_apply_boundary()


## Override in subclasses to implement creature-specific movement.
## Set [member velocity] here — do not call move_and_slide() directly.
func _do_movement(_delta: float) -> void:
	pass


## Called when the boundary bounces the creature.
## Override to update internal direction variables so movement stays consistent.
## [param normal] points away from the wall that was hit.
func _on_boundary_bounce(_normal: Vector2) -> void:
	pass


func add_loop() -> void:
	loop_count += 1
	if loop_count >= loops_needed:
		emit_signal("captured")
		queue_free()
	else:
		_loop_label.text = str(loops_needed - loop_count)
		_loop_label.visible = true


func reset_loops() -> void:
	loop_count = 0
	_loop_label.visible = false


func _apply_boundary() -> void:
	if scene_bounds == Rect2():
		return
	var limit := scene_bounds.grow(boundary_overshoot)
	match boundary_mode:
		BoundaryMode.BOUNCE:
			var normal := Vector2.ZERO
			if global_position.x < limit.position.x:
				velocity.x = abs(velocity.x)
				normal.x = 1.0
			elif global_position.x > limit.end.x:
				velocity.x = -abs(velocity.x)
				normal.x = -1.0
			if global_position.y < limit.position.y:
				velocity.y = abs(velocity.y)
				normal.y = 1.0
			elif global_position.y > limit.end.y:
				velocity.y = -abs(velocity.y)
				normal.y = -1.0
			global_position = Vector2(
				clampf(global_position.x, limit.position.x, limit.end.x),
				clampf(global_position.y, limit.position.y, limit.end.y)
			)
			if normal != Vector2.ZERO:
				_on_boundary_bounce(normal.normalized())
		BoundaryMode.WRAP:
			var pos := global_position
			if pos.x < limit.position.x:
				pos.x = limit.end.x
			elif pos.x > limit.end.x:
				pos.x = limit.position.x
			if pos.y < limit.position.y:
				pos.y = limit.end.y
			elif pos.y > limit.end.y:
				pos.y = limit.position.y
			global_position = pos
