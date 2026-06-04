extends Creature

# Dinosaur: medium speed wander, periodically stops to bite in front of itself.
# DamageHitbox enabled only during the bite window — teaches attack timing/avoidance.

const WANDER_TIME_MIN := 1.5
const WANDER_TIME_MAX := 3.0
const BITE_DURATION := 0.5
const BITE_RANGE := 32.0

enum State { WANDER, BITE }
var _state := State.WANDER
var _state_timer := 0.0
var _move_dir := Vector2.RIGHT


func _ready() -> void:
	$DamageHitbox.monitoring = false
	_move_dir = Vector2.from_angle(randf() * TAU)
	_state_timer = randf_range(WANDER_TIME_MIN, WANDER_TIME_MAX)


func _do_movement(delta: float) -> void:
	_state_timer -= delta
	match _state:
		State.WANDER:
			velocity = _move_dir * speed
			if _state_timer <= 0.0:
				_start_bite()
		State.BITE:
			velocity = Vector2.ZERO
			if _state_timer <= 0.0:
				_end_bite()


func _on_boundary_bounce(normal: Vector2) -> void:
	_move_dir = _move_dir.bounce(normal)


func _start_bite() -> void:
	_state = State.BITE
	_state_timer = BITE_DURATION
	$DamageHitbox.position = _move_dir * BITE_RANGE
	$DamageHitbox.monitoring = true


func _end_bite() -> void:
	$DamageHitbox.monitoring = false
	_state = State.WANDER
	_state_timer = randf_range(WANDER_TIME_MIN, WANDER_TIME_MAX)
	_move_dir = Vector2.from_angle(randf() * TAU)
