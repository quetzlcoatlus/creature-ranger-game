## EventBus — global signal hub for decoupled system communication.
##
## All game systems emit and listen here instead of holding direct references
## to each other.  Register as an autoload named "EventBus" in project settings.
##
## Signals are organised by subsystem (tags, audio, game state, world).

extends Node

# ─── Tag system ──────────────────────────────────────────────────────────────
signal tag_added(tag: String, source: Node, priority: int)
signal tag_removed(tag: String, source: Node)
signal tags_batch_changed(added: Array[String], removed: Array[String])

# ─── Audio ────────────────────────────────────────────────────────────────────
signal audio_parameter_changed(param: String, value: Variant)
signal audio_rule_evaluated(rule_name: String, active: bool)

# ─── Game state ───────────────────────────────────────────────────────────────
signal player_terrain_changed(old_tag: String, new_tag: String)
signal time_of_day_changed(hour: float, is_day: bool)
signal weather_changed(old_weather: int, new_weather: int)

# ─── World interaction ────────────────────────────────────────────────────────
signal area_entered(area: Area2D, tags: Array[String])
signal area_exited(area: Area2D)
## Emitted by the player's interact/"punch" when it catches one or more creatures.
## SceneManager batches these and launches the capture scene. `creatures` are the
## live overworld Creature nodes that were hit.
signal creatures_interacted(creatures: Array)

# ─── Footsteps ───────────────────────────────────────────────────────────────
## Emitted when a creature starts moving on a terrain (or crosses to a new one).
## AudioManager starts/crossfades the looping terrain sound for that source.
signal footstep_start(source: Node, terrain_tag: int, world_position: Vector2)
## Emitted when a creature stops moving.  AudioManager stops that source's loop.
signal footstep_stop(source: Node)
