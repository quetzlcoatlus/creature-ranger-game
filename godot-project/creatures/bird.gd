extends CaptureCreature

# Bird: travels in a straight line and wraps around the scene boundary.
# boundary_mode is set to WRAP in bird.tscn.
# boundary_overshoot controls how far off-screen it travels before reappearing.

var _move_dir := Vector2.RIGHT


func _ready() -> void:
	$DamageHitbox.monitoring = false
	_move_dir = Vector2.from_angle(randf() * TAU)


func _do_movement(_delta: float) -> void:
	velocity = _move_dir * speed
