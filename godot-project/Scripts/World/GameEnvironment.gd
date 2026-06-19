## WorldEnvironment — register as an AutoLoad in Project Settings.
##
## Single source of truth for time-of-day, weather, and all derived lighting.
## Other systems read from this node rather than tracking their own state.
##
## How each node type should interact with this singleton:
##
##   Terrain   → purely affected by ambient_color via a CanvasModulate node
##               tagged "world_canvas_modulate".  No per-tile shadow logic.
##
##   Objects   → connect to sun_changed once in _ready(); update a simple
##               directional shadow sprite in the handler.  No landing indicator.
##
##   Creatures → read sun_angle / sun_intensity directly each physics frame
##               (cheaper than signals for per-frame shadow updates).
##               Also affected by ambient_color through the global CanvasModulate.

extends Node

# ─── Time of day ─────────────────────────────────────────────────────────────
## Current in-game hour (0.0 – 24.0; 0 and 24 are both midnight).
@export var hour               : float = 8.0
## Real seconds that pass per in-game minute.  1.0 = 1:1 with real time.
@export var seconds_per_minute : float = 1.0
@export var time_running       : bool  = true

# ─── Weather ─────────────────────────────────────────────────────────────────
enum Weather { CLEAR, OVERCAST, RAIN, STORM, FOG }

## Setting this property fires weather_changed and immediately recalculates
## sun intensity so shadows respond without waiting for the next frame.
var weather : Weather = Weather.CLEAR :
	set(v):
		weather = v
		weather_changed.emit(v)
		_compute_sun()

# ─── Derived — read by other nodes every frame ────────────────────────────────
## Screen-space degrees the sun/moon shines FROM (0 = east, counter-clockwise).
## Sun sweeps 345° → 105° from sunrise to sunset; moon drifts at night.
var sun_angle     : float = 215.0
## Warm yellow at noon, orange at dawn/dusk, cool blue at night.
var sun_color     : Color = Color.WHITE
## 0.0 = full dark or heavy overcast, 1.0 = clear noon.
## Creatures multiply shadow alpha by this; at night it drops to ~0.18 (moon).
var sun_intensity : float = 1.0
## Sky colour — applied to every CanvasModulate in "world_canvas_modulate".
var ambient_color : Color = Color.WHITE

# ─── Signals ─────────────────────────────────────────────────────────────────
## Emitted every frame when sun properties change.
## Objects connect here for event-driven shadow updates.
signal sun_changed(angle: float, color: Color, intensity: float)
## Emitted alongside sun_changed when the sky colour changes.
signal ambient_changed(color: Color)
## Emitted when the weather property is assigned.
signal weather_changed(w: Weather)
## Emitted once per in-game hour — connect here for world events (shop opens, etc.)
signal hour_ticked(new_hour: int)

# ─── Internal ────────────────────────────────────────────────────────────────
var _prev_hour_int    : int     = -1
var _prev_is_day      : bool    = true   # tracks last emitted time-of-day tag
var _prev_weather_int : int     = -1     # for EventBus.weather_changed old value
# Ambient gradient keyframes — populated in _ready() for type safety.
var _grad_times  : PackedFloat32Array
var _grad_colors : Array[Color]


func _ready() -> void:
	add_to_group("game_environment")
	# Forward weather changes to EventBus.
	weather_changed.connect(func(w: Weather) -> void:
		if has_node("/root/EventBus"):
			EventBus.weather_changed.emit(_prev_weather_int, int(w))
		_prev_weather_int = int(w)
	)

	_grad_times = PackedFloat32Array([
		0.0, 4.0, 6.0, 7.0, 9.0, 12.0, 17.0, 19.0, 20.5, 22.0, 24.0,
	])
	_grad_colors = [
		Color(0.04, 0.06, 0.18),  #  0 h midnight
		Color(0.05, 0.07, 0.20),  #  4 h pre-dawn
		Color(0.35, 0.18, 0.14),  #  6 h first light
		Color(0.82, 0.46, 0.22),  #  7 h golden hour
		Color(0.95, 0.93, 0.88),  #  9 h morning
		Color(1.00, 0.99, 0.95),  # 12 h noon
		Color(0.92, 0.80, 0.62),  # 17 h late afternoon
		Color(0.76, 0.38, 0.18),  # 19 h sunset
		Color(0.20, 0.12, 0.28),  # 20.5 h twilight
		Color(0.06, 0.07, 0.20),  # 22 h night
		Color(0.04, 0.06, 0.18),  # 24 h midnight (wrap)
	]
	_compute_sun()
	_apply_canvas_modulate()


func _process(delta: float) -> void:
	if time_running:
		hour = fmod(hour + delta * seconds_per_minute / 60.0, 24.0)

	_compute_sun()
	_apply_canvas_modulate()
	_update_time_tags()

	var h := int(hour)
	if h != _prev_hour_int:
		_prev_hour_int = h
		hour_ticked.emit(h)
		if has_node("/root/EventBus"):
			EventBus.time_of_day_changed.emit(hour, is_daytime())


# ─── Time tags ────────────────────────────────────────────────────────────────
func _update_time_tags() -> void:
	if not has_node("/root/TagRegistry"):
		return
	var day_now := is_daytime()
	if day_now == _prev_is_day:
		return
	_prev_is_day = day_now
	if day_now:
		TagRegistry.remove_tag("time:night", self)
		TagRegistry.add_tag("time:day",   self, 1)
	else:
		TagRegistry.remove_tag("time:day", self)
		TagRegistry.add_tag("time:night",  self, 1)


# ─── Sun / moon computation ───────────────────────────────────────────────────
func _compute_sun() -> void:
	var is_day := hour >= 6.0 and hour < 18.0
	var day_t  := clampf((hour - 6.0) / 12.0, 0.0, 1.0)

	var new_angle     : float
	var new_intensity : float
	var new_color     : Color

	if is_day:
		# Angle: 345° at sunrise → 225° at noon → 105° at sunset.
		new_angle     = 345.0 - 240.0 * day_t
		# Intensity: sine bell, peaks at noon.
		new_intensity = sin(day_t * PI)
		# Color: orange at dawn/dusk, near-white at noon.
		var warmth := 1.0 - absf(day_t - 0.5) * 2.0
		new_color  = Color(1.0, lerpf(0.55, 1.0, warmth), lerpf(0.30, 0.95, warmth))
	else:
		# Moon: slow drift across the night sky, cool blue.
		var night_t   := hour / 6.0 if hour < 6.0 else (hour - 18.0) / 6.0
		new_angle     = fmod(165.0 + night_t * 30.0, 360.0)
		new_intensity = 0.18
		new_color     = Color(0.70, 0.75, 1.00)

	# Weather modifiers — stack multiplicatively.
	match weather:
		Weather.OVERCAST: new_intensity *= 0.40
		Weather.RAIN:     new_intensity *= 0.25
		Weather.STORM:    new_intensity *= 0.10
		Weather.FOG:      new_intensity *= 0.50

	var changed := (not is_equal_approx(new_angle,     sun_angle)
				 or not is_equal_approx(new_intensity, sun_intensity))

	sun_angle     = new_angle
	sun_intensity = new_intensity
	sun_color     = new_color
	ambient_color = _sample_gradient(hour)

	if changed:
		sun_changed.emit(sun_angle, sun_color, sun_intensity)
		ambient_changed.emit(ambient_color)




func _sample_gradient(t: float) -> Color:
	for i: int in range(_grad_times.size() - 1):
		if t >= _grad_times[i] and t <= _grad_times[i + 1]:
			var s := (t - _grad_times[i]) / (_grad_times[i + 1] - _grad_times[i])
			return _grad_colors[i].lerp(_grad_colors[i + 1], s)
	return _grad_colors[0]


# ─── CanvasModulate ───────────────────────────────────────────────────────────
func _apply_canvas_modulate() -> void:
	for node: Node in get_tree().get_nodes_in_group("world_canvas_modulate"):
		if node is CanvasModulate:
			(node as CanvasModulate).color = ambient_color


# ─── Public helpers ───────────────────────────────────────────────────────────
## Returns the current time as "HH:MM", e.g. "14:30".
func get_time_string() -> String:
	var h := int(hour)
	var m := int(fmod(hour, 1.0) * 60.0)
	return "%02d:%02d" % [h, m]

func is_daytime() -> bool:
	return hour >= 6.0 and hour < 18.0

## Jump to a specific hour instantly (useful for debug or cutscenes).
func set_time(new_hour: float) -> void:
	hour = clampf(new_hour, 0.0, 24.0)
