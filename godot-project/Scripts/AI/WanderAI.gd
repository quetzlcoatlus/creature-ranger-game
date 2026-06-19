## WanderAI — a terrain-aware, time-aware wandering AI controller.
##
## The creature roams within a radius, weighted toward preferred terrain.
## It is aware of the in-game time of day via GameEnvironment and will seek
## its home habitat before sleep time, then sleep until morning.
##
## States (in priority order, high → low):
##   SLEEP        — creature is asleep; no movement
##   SEEK_SAFETY  — unsafe terrain timer expired; find safe ground
##   SEEK_HOME    — approaching sleep time; return to home habitat
##   PLAY         — on a "fun" terrain tag; energetic erratic movement
##   WANDER       — default; roam weighted by terrain preference
##
## Configure per-creature in the Inspector:
##   terrain_weights   — terrain_tag → score  (-1 avoid, 0 neutral, 1 prefer)
##   safe_tags         — tags safe to be on indefinitely (survival)
##   fun_tags          — tags that trigger PLAY
##   home_tags         — tags to sleep on; falls back to safe_tags if empty
##   sleep_start_hour  — in-game hour when creature wants to sleep
##   sleep_end_hour    — in-game hour when creature wakes up
##   seek_home_advance — hours before sleep to start heading home

class_name WanderAI
extends AIController

# ─── Terrain ─────────────────────────────────────────────────────────────────
## terrain_tag → preference weight. Unlisted tags are 0 (neutral).
@export var terrain_weights   : Dictionary = {}
@export var safe_tags         : Array[int] = []
@export var fun_tags          : Array[int] = []
## Where the creature sleeps. Falls back to safe_tags when empty.
@export var home_tags         : Array[int] = []

# ─── Time of day ─────────────────────────────────────────────────────────────
## Hour (0–24) at which the creature wants to be asleep.
@export var sleep_start_hour  : float = 21.0
## Hour (0–24) at which the creature wakes up.
@export var sleep_end_hour    : float = 6.0
## How many in-game hours before sleep to start heading home.
@export var seek_home_advance : float = 2.0

# ─── Movement tuning ─────────────────────────────────────────────────────────
@export var safety_timeout    : float = 6.0
@export var wander_radius     : float = 60.0
@export var arrival_distance  : float = 5.0
## Candidate directions sampled when picking a wander target.
@export var direction_samples : int   = 8
@export var play_linger       : float = 1.5
@export var play_dir_interval : float = 0.4


# ─── Internal state ───────────────────────────────────────────────────────────
enum State { WANDER, PLAY, SEEK_SAFETY, SEEK_HOME, SLEEP }

var _state             : State   = State.WANDER
var _wander_target     : Vector2 = Vector2.ZERO
var _safety_target     : Vector2 = Vector2.ZERO
var _home_target       : Vector2 = Vector2.ZERO
var _unsafe_timer      : float   = 0.0
var _play_linger_timer : float   = 0.0
var _play_dir_timer    : float   = 0.0

var _game_env          : Node    = null


func _ready() -> void:
	super._ready()
	_game_env = get_tree().get_first_node_in_group("game_environment")
	_pick_wander_target()


func _decide(delta: float) -> void:
	var hour : float = _get_current_hour()
	var tag  : int   = _get_current_terrain_tag()
	var sleeping     := _is_sleep_time(hour)

	# ── Safety timer ──────────────────────────────────────────────────────────
	if safe_tags.is_empty() or (tag in safe_tags) or tag == 0:
		_unsafe_timer = 0.0
	else:
		_unsafe_timer += delta

	# ── SLEEP (highest priority) ──────────────────────────────────────────────
	# At sleep time: go to sleep if on a home tile, otherwise seek home first.
	if sleeping:
		if _is_on_home_tile(tag):
			_state = State.SLEEP
		elif _state != State.SEEK_HOME:
			_state = State.SEEK_HOME
			_home_target = _find_home_position()
	elif _state == State.SLEEP:
		# Morning — wake up and resume wandering.
		_state = State.WANDER
		_pick_wander_target()

	# ── SEEK_SAFETY (interrupts all non-sleep states) ─────────────────────────
	if _state != State.SLEEP and _unsafe_timer >= safety_timeout:
		if _state != State.SEEK_SAFETY:
			_safety_target = _find_safe_position()
		_state = State.SEEK_SAFETY

	# ── SEEK_HOME (pre-sleep homing, lower priority than safety) ─────────────
	if _state not in [State.SLEEP, State.SEEK_SAFETY]:
		if not sleeping and _should_seek_home(hour) and not _is_on_home_tile(tag):
			if _state != State.SEEK_HOME:
				_state = State.SEEK_HOME
				_home_target = _find_home_position()
		elif _state == State.SEEK_HOME and _is_on_home_tile(tag):
			# Arrived home before sleep — resume normal life.
			_state = State.WANDER
			_pick_wander_target()

	# ── PLAY / WANDER transitions ─────────────────────────────────────────────
	match _state:
		State.WANDER:
			if tag in fun_tags:
				_state             = State.PLAY
				_play_linger_timer = play_linger
				_play_dir_timer    = 0.0

		State.PLAY:
			if tag not in fun_tags:
				_play_linger_timer -= delta
				if _play_linger_timer <= 0.0:
					_state = State.WANDER
					_pick_wander_target()

		State.SEEK_SAFETY:
			if (tag in safe_tags) or tag == 0:
				_state = State.WANDER
				_pick_wander_target()

	# ── Execute behaviour ─────────────────────────────────────────────────────
	match _state:
		State.SLEEP:       _do_sleep()
		State.SEEK_HOME:   _do_seek_home()
		State.SEEK_SAFETY: _do_seek_safety()
		State.PLAY:        _do_play(delta)
		State.WANDER:      _do_wander()


# ─── WANDER ───────────────────────────────────────────────────────────────────
func _do_wander() -> void:
	var to_target := _wander_target - _creature.global_position
	if to_target.length() < arrival_distance:
		_pick_wander_target()
		return
	_move_dir = to_target.normalized()


func _pick_wander_target() -> void:
	var best_score  : float   = -INF
	var best_target : Vector2 = _creature.global_position

	for _i: int in direction_samples:
		var angle     := randf() * TAU
		var dist      := randf_range(wander_radius * 0.3, wander_radius)
		var offset    := Vector2.from_angle(angle) * dist
		var candidate := _creature.global_position + offset

		var mid_score := _terrain_preference(_get_terrain_tag_at(_creature.global_position + offset * 0.5))
		var end_score := _terrain_preference(_get_terrain_tag_at(candidate))
		var score     := mid_score + end_score + randf() * 0.1

		if score > best_score:
			best_score  = score
			best_target = candidate

	_wander_target = best_target


func _terrain_preference(tag: int) -> float:
	if terrain_weights.has(tag):
		return float(terrain_weights[tag])
	return 0.0


# ─── PLAY ─────────────────────────────────────────────────────────────────────
func _do_play(delta: float) -> void:
	_do_sprint = true
	_play_dir_timer -= delta
	if _play_dir_timer <= 0.0:
		_play_dir_timer = play_dir_interval
		_move_dir = Vector2.from_angle(randf() * TAU)


# ─── SEEK SAFETY ─────────────────────────────────────────────────────────────
func _do_seek_safety() -> void:
	var to_safe := _safety_target - _creature.global_position
	if to_safe.length() < arrival_distance:
		_safety_target = _find_safe_position()
		return
	_move_dir = to_safe.normalized()


func _find_safe_position() -> Vector2:
	for _attempt: int in 16:
		var angle     := randf() * TAU
		var dist      := randf_range(10.0, wander_radius * 1.5)
		var candidate := _creature.global_position + Vector2.from_angle(angle) * dist
		var tag       := _get_terrain_tag_at(candidate)
		if (tag in safe_tags) or tag == 0:
			return candidate
	return _creature.global_position


# ─── SEEK HOME ────────────────────────────────────────────────────────────────
func _do_seek_home() -> void:
	var to_home := _home_target - _creature.global_position
	if to_home.length() < arrival_distance:
		_home_target = _find_home_position()
		return
	_move_dir = to_home.normalized()


func _find_home_position() -> Vector2:
	var tags := home_tags if not home_tags.is_empty() else safe_tags
	for _attempt: int in 16:
		var angle     := randf() * TAU
		var dist      := randf_range(5.0, wander_radius * 1.5)
		var candidate := _creature.global_position + Vector2.from_angle(angle) * dist
		var tag       := _get_terrain_tag_at(candidate)
		if tag in tags or (tags.is_empty() and tag == 0):
			return candidate
	return _creature.global_position


# ─── SLEEP ────────────────────────────────────────────────────────────────────
func _do_sleep() -> void:
	_move_dir = Vector2.ZERO  # stand still


# ─── Time helpers ─────────────────────────────────────────────────────────────
func _get_current_hour() -> float:
	if _game_env == null:
		return 12.0  # assume noon when no GameEnvironment
	return _game_env.hour


func _is_sleep_time(hour: float) -> bool:
	if sleep_start_hour < sleep_end_hour:
		# Simple range — e.g. 2:00–6:00.
		return hour >= sleep_start_hour and hour < sleep_end_hour
	else:
		# Wraps past midnight — e.g. 21:00–6:00.
		return hour >= sleep_start_hour or hour < sleep_end_hour


func _hours_until(from_hour: float, to_hour: float) -> float:
	var d := to_hour - from_hour
	return d if d >= 0.0 else d + 24.0


func _should_seek_home(hour: float) -> bool:
	if _is_sleep_time(hour):
		return false
	return _hours_until(hour, sleep_start_hour) <= seek_home_advance


func _is_on_home_tile(tag: int) -> bool:
	var tags := home_tags if not home_tags.is_empty() else safe_tags
	return (tag in tags) or (tags.is_empty() and tag == 0)
