## AudioManager — stem-based dynamic music + per-creature looping footstep SFX.
##
## Open autoload/AudioManager.tscn to configure exported properties in the Inspector.
##
## ─── Music (always playing, terrain-reactive) ─────────────────────────────────
## Three AudioStreamPlayer children (StemBasic, StemAdd01, StemAdd02) start
## simultaneously in _ready().  WAV files are imported with loop_mode=LOOP_FORWARD
## so they never drift.  Each has its own audio bus carrying an AudioEffectPitchShift
## so pitch can shift without changing BPM.
##
## Terrain rules (volume tweened by fade_time):
##   Neutral  → Basic only; Add01 & Add02 muted
##   Grass    → Basic + Add01 + Add02 at 0 dB, no pitch shift
##   Sand     → Basic + Add02 at 0 dB (−sand_pitch_semi st); Add01 muted
##   Ice      → Basic + Add01 at 0 dB (+ice_pitch_semi st);  Add02 muted
##
## ─── Footstep SFX (movement-reactive, per creature) ─────────────────────────
## AudioManager listens to EventBus.footstep_start / footstep_stop.
## For each walking creature it creates one AudioStreamPlayer2D that loops
## the terrain-specific WAV (Grass / Sand / Ice _Footsteps.wav).
## The player's position is updated every frame so it moves with the creature.
## Volume comes from Creature.footstep_volume_db — set it lower in the Inspector
## for AI creatures so they don't overwhelm the player's footsteps.

extends Node

# ─── Inspector ────────────────────────────────────────────────────────────────
## Fade duration when the player crosses terrain boundaries.
@export var fade_time       : float = 1.0
## Semitones to shift Add01 up on ice.
@export var ice_pitch_semi  : float = 0.7
## Semitones to shift Add02 down on sand.
@export var sand_pitch_semi : float = -0.7
## dB offset applied to all stem buses.
@export var music_volume_db : float = 0.0
## Fallback footstep volume used if a source has no footstep_volume_db property.
@export var sfx_volume_db   : float = -6.0

# ─── Constants ────────────────────────────────────────────────────────────────
const STEM_BASIC  := "Music_Basic"
const STEM_ADD01  := "Music_Add01"
const STEM_ADD02  := "Music_Add02"
const MUTE_DB     : float = -80.0
const NEUTRAL_DB  : float = 0.0

# ─── Scene children ───────────────────────────────────────────────────────────
@onready var _stem_basic : AudioStreamPlayer = $StemBasic
@onready var _stem_add01 : AudioStreamPlayer = $StemAdd01
@onready var _stem_add02 : AudioStreamPlayer = $StemAdd02

# ─── Runtime state ────────────────────────────────────────────────────────────
var _current_terrain  : String = ""
var _music_tween      : Tween  = null

## Source Node → AudioStreamPlayer2D  (one looping player per walking creature)
var _footstep_players : Dictionary = {}
## terrain_tag int → AudioStreamWAV (loop mode set on load)
var _footstep_map     : Dictionary = {}
var _debug_frames_remaining : int  = 0


func _ready() -> void:
	print("[AudioManager] _ready — node: ", name, "  children: ", get_child_count())
	_pick_output_device()
	_setup_buses()
	_configure_stems()
	_setup_footstep_map()

	if has_node("/root/EventBus"):
		EventBus.player_terrain_changed.connect(_on_player_terrain_changed)
		EventBus.footstep_start.connect(_on_footstep_start)
		EventBus.footstep_stop.connect(_on_footstep_stop)
	else:
		push_warning("[AudioManager] EventBus not found — footstep/terrain signals won't work")

	_debug_frames_remaining = 10  # print state after 10 frames


# ─── Per-frame: keep footstep players at their creature's position ─────────────
func _process(_delta: float) -> void:
	if _debug_frames_remaining > 0:
		_debug_frames_remaining -= 1
		if _debug_frames_remaining == 0:
			_debug_audio_state()

	for source : Node in _footstep_players:
		if is_instance_valid(source):
			(_footstep_players[source] as AudioStreamPlayer2D).global_position = source.global_position


# ─── 1-second deferred audio state dump ──────────────────────────────────────
func _debug_audio_state() -> void:
	var m  := AudioServer.get_bus_index("Master")
	var b  := AudioServer.get_bus_index(STEM_BASIC)
	print("[AudioManager] === audio state at 1 s ===")
	print("  output_device : ", AudioServer.output_device)
	print("  basic playing=%s  pos=%.2f  vol_db=%.1f  bus=%s" % [
		_stem_basic.playing, _stem_basic.get_playback_position(),
		_stem_basic.volume_db, _stem_basic.bus])
	print("  Master      idx=%d  vol=%.1fdB  muted=%s  peak_L=%.1fdB" % [
		m, AudioServer.get_bus_volume_db(m),
		AudioServer.is_bus_mute(m),
		AudioServer.get_bus_peak_volume_left_db(m, 0)])
	print("  Music_Basic idx=%d  vol=%.1fdB  muted=%s  peak_L=%.1fdB" % [
		b, AudioServer.get_bus_volume_db(b),
		AudioServer.is_bus_mute(b),
		AudioServer.get_bus_peak_volume_left_db(b, 0)])


# ─── Output device selection ──────────────────────────────────────────────────
## Godot on Windows defaults to whatever device WASAPI gives first, which is
## often the NVIDIA HDMI/DP audio device — useless unless a TV is connected.
## This picks the first device whose name doesn't look like a GPU/HDMI output.
func _pick_output_device() -> void:
	var devices : PackedStringArray = AudioServer.get_output_device_list()
	print("[AudioManager] available output devices: ", devices)
	for dev : String in devices:
		var lo := dev.to_lower()
		# "Default" still maps to the OS default which may be NVIDIA HDMI — skip it
		# so we land on an explicit real speaker/headphone device.
		if lo == "default" or "nvidia" in lo or "hdmi" in lo or "displayport" in lo or "dp audio" in lo:
			continue
		AudioServer.output_device = dev
		print("[AudioManager] selected output device: ", dev)
		return
	# Fallback — keep whatever Godot chose.
	print("[AudioManager] no preferred device found, using default: ", AudioServer.output_device)


# ─── Audio bus setup ──────────────────────────────────────────────────────────

func _setup_buses() -> void:
	for bus_name : String in [STEM_BASIC, STEM_ADD01, STEM_ADD02]:
		if AudioServer.get_bus_index(bus_name) != -1:
			continue
		AudioServer.add_bus()
		var idx : int = AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
		# Pitch shift effects are added on demand by _set_pitch() only when a
		# terrain actually needs a non-zero shift.  Adding one at pitch_scale=1.0
		# upfront causes silence on some drivers.


func _get_pitch_effect(bus_name: String) -> AudioEffectPitchShift:
	var idx : int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return null
	return AudioServer.get_bus_effect(idx, 0) as AudioEffectPitchShift


func _set_pitch(bus_name: String, semitones: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	if is_equal_approx(semitones, 0.0):
		# No shift needed — remove any existing effect so the bus stays clean.
		if AudioServer.get_bus_effect_count(idx) > 0:
			AudioServer.remove_bus_effect(idx, 0)
		return
	# Non-zero shift — add the effect if not present, then update its scale.
	var effect := _get_pitch_effect(bus_name)
	if effect == null:
		var ps := AudioEffectPitchShift.new()
		ps.fft_size = AudioEffectPitchShift.FFT_SIZE_2048
		AudioServer.add_bus_effect(idx, ps)
		effect = ps
	effect.pitch_scale = pow(2.0, semitones / 12.0)


# ─── Music stem configuration ─────────────────────────────────────────────────

func _configure_stems() -> void:
	# Null-check — if the .tscn children didn't load, bail with a clear error.
	if _stem_basic == null or _stem_add01 == null or _stem_add02 == null:
		push_error("[AudioManager] Stem AudioStreamPlayer children are null — check AudioManager.tscn")
		return

	print("[AudioManager] streams — basic:%s  add01:%s  add02:%s" % [
		str(_stem_basic.stream), str(_stem_add01.stream), str(_stem_add02.stream)])

	_stem_basic.bus = STEM_BASIC
	_stem_add01.bus = STEM_ADD01
	_stem_add02.bus = STEM_ADD02

	# Guarantee loop mode regardless of import settings.
	for stem : AudioStreamPlayer in [_stem_basic, _stem_add01, _stem_add02]:
		var wav := stem.stream as AudioStreamWAV
		if wav != null:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		else:
			push_warning("[AudioManager] stem '%s' has no AudioStreamWAV stream" % stem.name)

	# Apply master volume offset.
	for bus_name : String in [STEM_BASIC, STEM_ADD01, STEM_ADD02]:
		var idx := AudioServer.get_bus_index(bus_name)
		print("[AudioManager] bus '%s' idx=%d" % [bus_name, idx])
		if idx != -1:
			AudioServer.set_bus_volume_db(idx, music_volume_db)

	# Defer playback — WASAPI needs a moment to reinitialize after the output
	# device is switched in _pick_output_device().  Calling play() immediately
	# in the same frame silently drops the request.
	get_tree().create_timer(0.3).timeout.connect(_start_stems)


func _start_stems() -> void:
	_stem_basic.play()
	_stem_add01.play()
	_stem_add02.play()
	print("[AudioManager] stems started playing (deferred)")


# ─── Footstep asset setup ─────────────────────────────────────────────────────

func _setup_footstep_map() -> void:
	var entries := [
		[1, "res://AudioAssets/SFX/Grass_Footsteps.wav"],
		[2, "res://AudioAssets/SFX/Sand_Footsteps.wav"],
		[3, "res://AudioAssets/SFX/Ice_Footsteps.wav"],
	]
	for entry in entries:
		var stream := load(entry[1]) as AudioStreamWAV
		if stream != null:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			_footstep_map[entry[0]] = stream


# ─── Music terrain rules ──────────────────────────────────────────────────────

func _on_player_terrain_changed(_old: String, new_tag: String) -> void:
	if new_tag == _current_terrain:
		return
	_current_terrain = new_tag
	_apply_terrain_rule(new_tag, fade_time)


## Switch to a terrain mix.  fade = 0 for instant.
func _apply_terrain_rule(tag: String, fade: float) -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = create_tween().set_parallel(true)

	match tag:
		"grass":
			_fade(_stem_add01, NEUTRAL_DB, fade)
			_fade(_stem_add02, NEUTRAL_DB, fade)
			_set_pitch(STEM_ADD01, 0.0)
			_set_pitch(STEM_ADD02, 0.0)
		"ice":
			_fade(_stem_add01, NEUTRAL_DB, fade)
			_fade(_stem_add02, MUTE_DB,    fade)
			_set_pitch(STEM_ADD01, ice_pitch_semi)
			_set_pitch(STEM_ADD02, 0.0)
		"sand":
			_fade(_stem_add01, MUTE_DB,    fade)
			_fade(_stem_add02, NEUTRAL_DB, fade)
			_set_pitch(STEM_ADD01, 0.0)
			_set_pitch(STEM_ADD02, sand_pitch_semi)
		_:
			_fade(_stem_add01, MUTE_DB, fade)
			_fade(_stem_add02, MUTE_DB, fade)
			_set_pitch(STEM_ADD01, 0.0)
			_set_pitch(STEM_ADD02, 0.0)


func _fade(stem: AudioStreamPlayer, target_db: float, duration: float) -> void:
	if duration <= 0.0:
		stem.volume_db = target_db
	else:
		_music_tween.tween_property(stem, "volume_db", target_db, duration)\
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ─── Footstep SFX ─────────────────────────────────────────────────────────────

func _on_footstep_start(source: Node, terrain_tag: int, world_pos: Vector2) -> void:
	var stream : AudioStreamWAV = _footstep_map.get(terrain_tag)
	if stream == null:
		_on_footstep_stop(source)
		return

	# Get or create a dedicated looping player for this creature.
	if not _footstep_players.has(source):
		var p := AudioStreamPlayer2D.new()
		p.max_distance = 600.0
		add_child(p)
		_footstep_players[source] = p
		# Auto-cleanup when the creature is freed.
		source.tree_exited.connect(func() -> void: _cleanup_footstep(source), CONNECT_ONE_SHOT)

	var player : AudioStreamPlayer2D = _footstep_players[source]

	# Read per-creature volume from its footstep_volume_db export (Creature.gd).
	player.volume_db = (source as Creature).footstep_volume_db if source is Creature else sfx_volume_db
	player.global_position = world_pos

	# Only restart when the terrain changed; otherwise keep the loop running.
	if player.stream != stream or not player.playing:
		player.stream = stream
		player.play()


func _on_footstep_stop(source: Node) -> void:
	if _footstep_players.has(source):
		(_footstep_players[source] as AudioStreamPlayer2D).stop()


func _cleanup_footstep(source: Node) -> void:
	if _footstep_players.has(source):
		var p : AudioStreamPlayer2D = _footstep_players[source]
		p.stop()
		p.queue_free()
		_footstep_players.erase(source)


# ─── Public helpers ───────────────────────────────────────────────────────────

## Force a terrain mix instantly.  Useful for debug or cutscenes.
func set_terrain_instant(tag: String) -> void:
	_current_terrain = tag
	_apply_terrain_rule(tag, 0.0)


func get_current_terrain() -> String:
	return _current_terrain
