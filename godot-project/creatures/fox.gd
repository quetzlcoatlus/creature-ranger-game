extends CaptureCreature

# Fox: fast, erratic zigzag bursts separated by short coasting periods.
# speed export = burst speed; coast is 20% of that.
# Punishes slow loop closure.

const BURST_DURATION := 0.4
const COAST_DURATION := 0.8
const COAST_FRACTION := 0.2

enum State { BURST, COAST }
var _state := State.COAST
var _state_timer := COAST_DURATION
var _move_dir := Vector2.RIGHT


func _ready() -> void:
	$DamageHitbox.monitoring = false
	_move_dir = Vector2.from_angle(randf() * TAU)


func _do_movement(delta: float) -> void:
	_state_timer -= delta
	match _state:
		State.COAST:
			velocity = _move_dir * (speed * COAST_FRACTION)
			if _state_timer <= 0.0:
				_start_burst()
		State.BURST:
			velocity = _move_dir * speed
			if _state_timer <= 0.0:
				_start_coast()


func _on_boundary_bounce(normal: Vector2) -> void:
	_move_dir = _move_dir.bounce(normal)


func _start_burst() -> void:
	var angle := _move_dir.angle() + (randf() - 0.5) * (PI * 0.5)
	_move_dir = Vector2.from_angle(angle)
	_state = State.BURST
	_state_timer = BURST_DURATION


func _start_coast() -> void:
	_state = State.COAST
	_state_timer = COAST_DURATION
