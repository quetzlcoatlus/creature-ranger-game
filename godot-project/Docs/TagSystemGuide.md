# Tag-Driven Audio & Event System - Design Proposal

## Executive Summary

Implement a **unified tag system** that drives audio mixing, environmental reactions, and game behaviors through declarative rules. The system treats every game state (terrain, weather, time, player state, area triggers) as a set of **tags** that can be added/removed dynamically. An **event bus** propagates tag changes, and the **AudioManager** (plus future systems) watches for tag patterns to trigger responses.

This decouples condition logic from hardcoded checks, enabling modular, data-driven gameplay.


## Core Architecture

### 1. Tag System (Autoload: `TagRegistry`)

Central storage for all active tags in the game world.

**Tag Sources:**
- **Player tags** - biome standing on (`grass`, `ice`, `sand`), state (`sprinting`, `crouching`, `underwater`)
- **World tags** - from `GameEnvironment` (`time:night`, `weather:rain`, `season:winter`)
- **Area tags** - from overlapping `Area2D` nodes (`safe_zone`, `boss_room`, `cave_interior`)
- **Event tags** - temporary story/combat flags (`in_combat`, `cutscene_active`)

**Tag Resolution Rules:**
- **Priority tiers** (highest to lowest): Event > Area > Player > World
- **Merge vs Replace**: Same tag from different sources? Higher priority wins, lower is ignored
- **Tag expiry**: Temporary tags auto-remove after duration or on scene change

**API:**
```gdscript
# Add/remove tags with source tracking
TagRegistry.add_tag("grass", source_node, priority=2)
TagRegistry.remove_tag("grass", source_node)

# Query
TagRegistry.has_tag("grass")  # returns bool
TagRegistry.get_tags_with_prefix("time:")  # returns ["time:night"]

# Signal emission
TagRegistry.tag_changed.emit(tag, added, source, priority)
```

### 2. Event Bus (Autoload: `EventBus`)

Global signal hub for decoupled communication. All systems emit and listen here.

**Core Signals:**
```gdscript
# Tag system
signal tag_added(tag: String, source: Node, priority: int)
signal tag_removed(tag: String, source: Node)
signal tags_batch_changed(added: Array[String], removed: Array[String])

# Audio specific
signal audio_parameter_changed(param: String, value: Variant)
signal audio_rule_evaluated(rule_name: String, active: bool)

# Game state
signal player_terrain_changed(old_tag: String, new_tag: String)
signal time_of_day_changed(hour: float, is_day: bool)
signal weather_changed(old: int, new: int)

# World interaction
signal area_entered(area: Area2D, tags: Array[String])
signal area_exited(area: Area2D)
```

### 3. Audio Manager (Autoload: `AudioManager`)

Listens to `EventBus` and `TagRegistry`, applies audio mixing rules defined in **Resources**.

**Components:**
- `MusicMixer` - Stem-based layering with tempo-synced crossfades
- `SFXPool` - Object pool for one-shot sounds (footsteps, UI, impacts)
- `AmbiencePlayer` - Continuous environmental layers (rain, wind, crickets)
- `RuleEngine` - Evaluates tag patterns to trigger audio changes

**Audio Rule Resources:**
```gdscript
# music_rule.tres (custom Resource)
@export var rule_name: String = "ice_terrain_music"
@export var condition: AudioCondition  # Tag pattern
@export var actions: Array[AudioAction]  # What to do when condition met

# Example condition: requires "ice" tag, excludes "underwater"
@export var required_tags: Array[String] = ["ice"]
@export var forbidden_tags: Array[String] = ["underwater"]
@export var match_any: bool = false  # false = need ALL required tags
```

**AudioAction Types:**
- `SetStemVolume(stem: String, db: float, fade_time: float)`
- `SetStemPitch(stem: String, semitones: float, preserve_tempo: bool)`
- `CrossfadeToTrack(new_basic_track: AudioStream, duration: float)`
- `ApplyEffect(bus: String, effect: AudioEffect, enabled: bool)`
- `PlayOneShot(sound: AudioStream, bus: String)`

### 4. Terrain Integration (Modify `Creature` class)

Extend existing terrain reading to emit tags rather than direct modifiers.

**Current approach (keep for movement physics):**
```gdscript
# Creature.gd already reads terrain custom data:
terrain_speed_mod = td.get_custom_data("speed_mod")
```

**Add tag emission:**
```gdscript
# In _read_terrain(), after reading custom data:
var terrain_tag := td.get_custom_data("terrain_tag")  # int: 0=neutral, 1=grass, 2=sand, 3=ice
if terrain_tag != _prev_terrain_tag:
    TagRegistry.remove_tag(_tag_from_int(_prev_terrain_tag), self)
    TagRegistry.add_tag(_tag_from_int(terrain_tag), self, priority=2)
    _prev_terrain_tag = terrain_tag
```

**TileSet Custom Data Layers (add to existing):**
- `terrain_tag` (int) - 0=neutral, 1=grass, 2=sand, 3=ice, 4=water, 5=stone
- `audio_effect` (String) - optional: "echo", "muffle", "reverb_cave"

### 5. Area2D Trigger System

Create reusable `TagArea` node for zone-based tagging.

```gdscript
# TagArea.gd
@export var tags_on_enter: Array[String] = []
@export var tags_on_exit: Array[String] = []  # Added when leaving
@export var priority: int = 3  # Higher than terrain (priority 2)
@export var one_shot: bool = false

func _on_body_entered(body: Node) -> void:
    if body is Creature:
        for tag in tags_on_enter:
            TagRegistry.add_tag(tag, self, priority)
        if one_shot: queue_free()

func _on_body_exited(body: Node) -> void:
    if body is Creature:
        for tag in tags_on_exit:
            TagRegistry.add_tag(tag, self, priority)
        for tag in tags_on_enter:
            TagRegistry.remove_tag(tag, self)
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1)

**Goal:** Working tag system + event bus with console logging.

**Tasks:**
1. Create `TagRegistry` autoload with dictionary storage: `{ "tag_name": { "source": node, "priority": int } }`
2. Create `EventBus` autoload with basic signals
3. Modify `Creature._read_terrain()` to emit `terrain_tag` via tags (not audio yet)
4. Add test console command: `add_tag grass` / `remove_tag grass`
5. Verify tags persist across scene changes

**Success Criteria:** Console shows tags added/removed when player walks on different terrain.

### Phase 2: Audio Stems & Mixing (Week 2)

**Goal:** Three terrain types trigger different stem combinations.

**Tasks:**
1. Create `AudioManager` autoload with `MusicMixer` inner class
2. Load three forestOak stems as `AudioStreamPlayer` nodes
3. Implement pitch shifting (use `AudioEffectPitchShift` for tempo preservation)
4. Create `AudioRule` resource with tag conditions
5. Write rule evaluator that checks `TagRegistry` every 0.2 seconds (or on tag change)

**Rule Examples:**
```gdscript
# grass_rule.tres
required_tags: ["grass"]
actions: [
    { "type": "set_stem_volume", "stem": "Addition01", "db": 0.0, "fade": 1.0 },
    { "type": "set_stem_volume", "stem": "Addition02", "db": 0.0, "fade": 1.0 },
    { "type": "set_stem_pitch", "stem": "Addition01", "semitones": 0 },
    { "type": "set_stem_pitch", "stem": "Addition02", "semitones": 0 }
]

# ice_rule.tres
required_tags: ["ice"]
actions: [
    { "type": "set_stem_volume", "stem": "Addition01", "db": 0.0, "fade": 1.0 },
    { "type": "set_stem_volume", "stem": "Addition02", "db": -80.0, "fade": 1.0 },
    { "type": "set_stem_pitch", "stem": "Addition01", "semitones": 0.7 }  # ~5% up
]

# sand_rule.tres
required_tags: ["sand"]
actions: [
    { "type": "set_stem_volume", "stem": "Addition01", "db": -80.0, "fade": 1.0 },
    { "type": "set_stem_volume", "stem": "Addition02", "db": 0.0, "fade": 1.0 },
    { "type": "set_stem_pitch", "stem": "Addition02", "semitones": -0.7 }  # ~5% down
]
```

**Crossfade Implementation:**
- Use `Tween` on `AudioStreamPlayer.volume_db`
- Default transition: 1.0 seconds linear
- Inspector property on `AudioManager` for default fade time

**Success Criteria:** Walking on sand → Addition02 plays pitched down, Addition01 silent. Ice → opposite.

### Phase 3: Event Bus Integration (Week 3)

**Goal:** All systems communicate via signals, no direct coupling.

**Tasks:**
1. Refactor `GameEnvironment` to emit `EventBus.time_of_day_changed` and `weather_changed`
2. Make `AudioManager` listen to these events instead of polling tags
3. Add `TagArea` nodes to test zones (e.g., "cave" area overrides terrain)
4. Implement priority system: Area (priority 3) > Terrain (priority 2) > World (priority 1)

**Tag Override Test:**
- Place `TagArea` with `tags_on_enter: ["ice"]` over grass terrain
- Expected: Ice music plays while inside area, reverts to grass when leaving

**Success Criteria:** Console logs show `tag_added` with correct priorities. Audio changes on area entry/exit.

### Phase 4: Footsteps & Environmental SFX (Week 4)

**Goal:** One-shot sounds trigger from tags.

**Tasks:**
1. Create `FootstepMapper` Resource: `{ "grass": preload("footstep_grass.wav"), "ice": preload("footstep_ice.wav") }`
2. In `Creature._physics_process()`, detect when `is_grounded` and velocity changed direction
3. Emit `EventBus.footstep(terrain_tag, position)`
4. `AudioManager` plays appropriate sound from pool

**SFX Pool Pattern:**
- Pre-create 4 `AudioStreamPlayer2D` nodes per sound type
- Rotate through them to avoid cutting off previous footsteps
- Use `AudioStreamPlayer2D.position` for positional audio (isometric world)

**Success Criteria:** Different footstep sounds on each terrain type.

### Phase 5: Advanced Features (Weeks 5-6)

**Goal:** Production-ready dynamic audio.

**Features to Implement:**

**A. Time-of-day layers**
```gdscript
# Add to AudioManager rules
if TagRegistry.has_tag("time:night"):
    play_ambience("night_crickets", volume=-15)
else:
    play_ambience("day_birds", volume=-12)
```

**B. Weather effects**
- Rain: Duck music volume by -6dB, add rain ambience layer
- Storm: Add thunder one-shots on random intervals (15-45 seconds)

**C. Underwater filtering**
- Detect `underwater` tag (from water tile or TagArea)
- Enable low-pass filter on master bus with tweened cutoff frequency

**D. Combat music**
- Combat tag triggers alternate percussion layer
- Sidechain compression to duck bass on snare hits (optional stretch goal)

**E. Parameter automation**
```gdscript
# Example: Pitch rises with player speed
var speed_ratio = velocity.length() / max_speed
AudioManager.set_parameter("movement_intensity", speed_ratio)
# Music filter cutoff modulates with intensity
```

---

## File Structure

```
res://
├── autoload/
│   ├── tag_registry.gd
│   ├── event_bus.gd
│   └── audio_manager.gd
├── audio/
│   ├── rules/
│   │   ├── grass_rule.tres
│   │   ├── ice_rule.tres
│   │   ├── sand_rule.tres
│   │   ├── night_rule.tres
│   │   └── rain_rule.tres
│   ├── stems/
│   │   ├── forestOak_Basic.wav
│   │   ├── forestOak_Addition01.wav
│   │   └── forestOak_Addition02.wav
│   ├── sfx/
│   │   ├── footsteps/
│   │   │   ├── grass_step.wav
│   │   │   ├── ice_step.wav
│   │   │   └── sand_step.wav
│   │   └── ambience/
│   └── footstep_mapper.tres
├── nodes/
│   └── tag_area.gd
└── scripts/
    ├── creature.gd (modified)
    └── game_environment.gd (modified)
```

---

## AI Agent Implementation Notes

### Freedom to Adapt

The above is a **suggested architecture**, not a strict mandate. The implementing AI agent should feel free to:

1. **Simplify where possible** - If Godot 4's `AudioStreamPlayer` sync is good enough, skip complex timing code
2. **Choose different data structures** - `Dictionary` vs `HashSet` for tags, signals vs direct method calls
3. **Optimize performance** - Polling tags every frame is fine (<1000 tags), but events are better
4. **Use Godot-specific patterns** - `@tool` scripts for rule editing, `Resource` for all data, `AudioEffect` chain
5. **Prioritize working code** - A simple polling-based audio switcher that works is better than a perfect event-driven system that's buggy

### Key Constraints to Preserve

1. **Tempo preservation** - Pitch shifting must NOT change BPM. Use `AudioEffectPitchShift` or similar.
2. **Modularity** - Audio rules should be data-driven (Resources), not hardcoded if conditions.
3. **Tag priority** - Higher priority tags must override lower ones. Clear resolution rules needed.
4. **Inspector configurability** - Fade times, pitch amounts, volumes must be tweakable without code changes.

### Testing Strategy

The AI agent should include a simple debug panel:

```gdscript
# DebugAudio.gd (attach to UI)
func _ready():
    $AddTagButton.pressed.connect(func(): TagRegistry.add_tag("ice", self, 99))
    $RemoveTagButton.pressed.connect(func(): TagRegistry.remove_tag("ice", self))
    $ListTagsButton.pressed.connect(func(): print(TagRegistry.get_all_tags()))
```

### Potential Pitfalls to Avoid

1. **Don't recreate the wheel** - Godot 4 has `AudioStreamPlayer` sync flags; use them
2. **Avoid polling when events work** - Connect to `TagRegistry.tag_changed` instead of `_process` checks
3. **Watch for memory leaks** - Remove tags when sources are freed (use `Node.tree_exited` signal)
4. **Test hot reloading** - Ensure `AudioManager` survives scene reloads (autoloads do by design)

---

## Future Expansion Possibilities

- **Dynamic music composition** - Procedurally generate stems from MIDI
- **Reactive ambience** - Enemy proximity increases tension layer volume
- **Dialogue system** - Duck music during voice lines
- **Accessibility** - Separate volume controls for music/ambience/SFX, mono mix option
- **Streaming integration** - Load music stems from disk for large soundtracks

---

## Questions for AI Agent

1. **Pitch shifting without tempo change** - What's the most CPU-efficient approach in Godot 4? `AudioEffectPitchShift` per stem, or pre-processed audio files?

2. **Tag storage** - Should `TagRegistry` use `Dictionary[String, Dictionary]` or `Dictionary[String, Array[TagSource]]`? Need priority-based retrieval.

3. **Rule evaluation frequency** - On every tag change (event-driven) or periodic polling (simpler)? Event-driven is cleaner but requires careful setup.

4. **Crossfade implementation** - `Tween` on `volume_db`, or `AudioStreamPlayer` crossfade plugin? Custom solution?

5. **Footstep detection** - In `Creature`, check `velocity.length() > min_speed and is_grounded and just_touched_ground`? Need step rhythm.

---

## Success Metrics

- [ ] Tags appear in console when walking on different terrain
- [ ] Music stems change when crossing between grass/ice/sand
- [ ] Pitch shift preserves tempo (listen for beat match)
- [ ] Crossfades smooth over 1 second
- [ ] Area triggers override terrain tags
- [ ] Footstep sounds play with correct terrain mapping
- [ ] No audio glitches on scene reload
- [ ] Inspector properties work at runtime

---

*This document is a living design. The AI agent should adapt as needed while preserving core requirements.*
```