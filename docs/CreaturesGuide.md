# Creatures & AI Guide

How overworld creatures move, sense terrain, and decide what to do. This covers
the `Scripts/Creatures/` and `Scripts/AI/` systems used by the **OverworldScene**.

> ⚠️ Not to be confused with `godot-project/creatures/` (lowercase). That folder
> holds the **capture mini-game** creatures (`CaptureCreature` and its bird /
> dinosaur / fox / urchin subclasses), which are a completely separate system —
> they're loop-to-capture targets, not overworld inhabitants. This guide is only
> about the overworld.

---

## 1. The big picture

An overworld creature is a `CharacterBody2D` built from three layers:

```
Creature (CharacterBody2D)      ← movement, jump, terrain sensing  (Creature.gd)
└── GoalAI (Node)               ← picks ONE goal to drive movement  (GoalAI.gd)
    ├── GoalWander              ← each goal proposes a direction…
    ├── GoalSafety
    ├── GoalSleep
    ├── GoalPlay
    └── GoalExploreTrees
└── Sprite2D                    ← the visible body
└── CollisionShape2D
└── Shadow (Sprite2D)           ← drifts with the sun  (ShadowSprite2D.gd)
```

Each physics frame:

1. **`GoalAI`** (runs first, `process_physics_priority = -1`) asks every child
   goal "how badly do you want control right now?" (`priority()`), lets the
   winner `decide()`, and writes a desired direction into `_move_dir`.
2. **`Creature`** reads that direction as `dir_input`, samples the terrain under
   its feet, applies acceleration / friction / speed caps, and calls
   `move_and_slide()`.

The creature **never** contains behaviour logic. *What* a creature does is
entirely a function of which goal nodes it has and how they're configured in the
Inspector. That's why the species scripts (`Fox.gd`, `Bird.gd`, …) are nearly
empty — they exist for the `class_name` and documentation, not for code.

---

## 2. `Creature.gd` — the body

`Creature.gd` ([Scripts/Creatures/Creature.gd](../godot-project/Scripts/Creatures/Creature.gd))
handles everything physical and is shared by the player and all AI creatures.

### Movement
Subclasses (or an `AIController` child) set `dir_input` each frame; the creature
accelerates toward it and applies friction when it's zero. Tunable exports:
`max_speed`, `min_speed`, `time_to_max`, `time_to_stop`, `time_to_turn`,
`sprint_max_mult`, `crouch_speed_mult`. Input is squashed by `ISO_SCALE`
(`Vector2(1, 0.5)`) for the isometric view.

### Jump (fake Z)
A `z_offset` / `z_velocity` pair fakes height; the body sprite is shifted up by
`z_offset` while collision is disabled mid-air. Tunable via `jump_height`,
`jump_gravity`, `jump_rise_mult`, `jump_fall_mult`.

### Terrain sensing
Point `ground_layer` at the `TileMapLayer` that carries terrain data. Each frame
the creature reads the **Custom Data Layers** of the tile under its origin:

| Custom data layer | Type  | Meaning                                   | Default |
|-------------------|-------|-------------------------------------------|---------|
| `speed_mod`       | float | movement-speed multiplier                 | 1.0     |
| `jump_mod`        | float | jump-height multiplier                    | 1.0     |
| `friction_mod`    | float | < 1.0 = slippery (ice)                    | 1.0     |
| `turn_mod`        | float | < 1.0 = hard to change direction (ice)    | 1.0     |
| `terrain_tag`     | int   | which terrain this is (see table below)   | 0       |

`terrain_changed` fires whenever the creature crosses into a tile with different
modifiers — hook it for footstep SFX, particles, etc. The current tag is also
pushed into the global [TagRegistry](TagSystemGuide.md) so other systems (audio,
zones) can react.

### Terrain tag values
These integers are the shared vocabulary between the TileSet and the AI. They're
defined in `Creature._terrain_tag_name()`:

| tag | terrain |
|----:|---------|
| 0   | none / neutral (empty tile) |
| 1   | grass   |
| 2   | sand    |
| 3   | ice     |
| 4   | water   |
| 5   | tree    |
| 6   | stone   |

> In the OverworldScene the tag lives in **`custom_data_4`** of the TileSet
> (`custom_data_layer_4/name = "terrain_tag"`). Grass tiles are tag 1, sand tag
> 2, ice tag 3, and the tree tiles in the **ObjectLayer** are tag 5.

### Collisions
On a slide collision the creature nudges `RigidBody2D`s and other `Creature`s
apart (`apply_nudge`) and calls `on_creature_touch()` on anything that defines
it — the hook for future interactions (eating, fleeing the player, etc.).

---

## 3. The AI: goals, not state machines

### `AIController.gd` — the base driver
Abstract base for anything that drives a creature. As a direct child of a
`Creature`, it runs *before* the parent each physics frame and writes
`_move_dir`, `_do_sprint`, and (via `_request_jump()`) `_do_jump`. It also offers
terrain helpers: `_get_current_terrain_tag()` and `_get_terrain_tag_at(pos)`.

There are two concrete controllers:

- **`WanderAI.gd`** — the original monolithic state machine
  (WANDER / PLAY / SEEK_SAFETY / SEEK_HOME / SLEEP) in one file. **Legacy** —
  kept for reference but the OverworldScene no longer uses it.
- **`GoalAI.gd`** — the current system. It owns a set of `AIGoal` child nodes
  and each frame picks the highest-priority one to drive movement. This is what
  every overworld creature uses.

### `GoalAI` + `AIGoal` — composable behaviour
Add `AIGoal` subclasses as children of a `GoalAI` node. Every frame `GoalAI`:

1. calls `_process_goal(delta)` on **every** goal (bookkeeping / timers run even
   when inactive),
2. reads each goal's `priority()`,
3. fires `on_activated()` on the new winner if it changed,
4. calls `decide(delta)` on the winner to actually steer the creature.

`priority()` returns `0.0` when a goal doesn't want control; higher wins. The
established tiers:

| Priority | Goal               | When it wants control |
|---------:|--------------------|-----------------------|
| 90       | `GoalSafety`       | stuck on unsafe terrain past `safety_timeout` |
| 85       | `GoalSleep`        | during the sleep window, once on a home tile |
| 50       | `GoalSleep`        | pre-sleep: heading home before bedtime |
| 40       | `GoalPlay`         | standing on a "fun" terrain tag |
| 35       | `GoalExploreTrees` | daytime, with a reachable tree nearby |
| 0        | `GoalWander`       | always-available fallback |

### The five goals

- **`GoalWander`** — terrain-weighted random roaming. Samples
  `direction_samples` candidate directions, scores each by `terrain_weights`
  (`tag → weight`; `1.0` prefer, `0.0` neutral, `-1.0` avoid), and walks toward
  the best. The always-on fallback.
- **`GoalSafety`** — survival. Accumulates an "unsafe" timer whenever the
  creature is on a tag **not** in `safe_tags` (tag 0 / empty is always safe).
  Past `safety_timeout` it takes priority 90 and steers to the nearest safe tile.
- **`GoalSleep`** — time-of-day homing + sleep. Reads the in-game hour from
  `GameEnvironment`. From `seek_home_advance` hours before `sleep_start_hour` it
  heads to a `home_tags` tile (priority 50); during the sleep window it holds
  still on that tile (priority 85). `home_tags` falls back to `safe_tags` if
  empty. Handles midnight-wrapping windows (e.g. 21→6).
- **`GoalPlay`** — sprints and jitters its direction while standing on a
  `fun_tags` terrain. Pure flavour.
- **`GoalExploreTrees`** — daytime tree tourism. Scans the **ObjectLayer**
  (group `object_layer`) for tree tiles (`tree_terrain_tag`, default 5), prefers
  low-[scent](#5-supporting-singletons) ones, walks there, lingers, and deposits
  scent so the next creature picks a *different* tree.

All goals share terrain helpers (`_get_terrain_tag_at`) and time helpers
(`_get_current_hour`, which falls back to noon if no `GameEnvironment` exists).

---

## 4. Time of day & "sleep at night"

`GameEnvironment.gd` ([Scripts/World/GameEnvironment.gd](../godot-project/Scripts/World/GameEnvironment.gd))
is the single source of truth for the clock, sun, and weather. It's in the
`game_environment` group; AI goals find it there to read `.hour` (0–24).

The day advances at `seconds_per_minute` real-seconds per in-game minute (set on
the GameEnvironment node — the OverworldScene uses 40, so a full day is ~16 real
minutes). Daytime is 06:00–18:00.

**"Creatures stop at night" is entirely `GoalSleep`.** With the default window
(`sleep_start_hour = 21`, `sleep_end_hour = 6`) every creature heads to its home
terrain in the evening and stands still through the night, then resumes wandering
at dawn. To make a species nocturnal, swap those two hours.

> **Weather** is modelled (`GameEnvironment.Weather` + sun-intensity modifiers)
> but creatures don't react to it yet — there is no rain-seeking-shelter goal.
> That's the natural next AI extension.

---

## 5. Supporting singletons

Registered as autoloads in `project.godot`:

- **`TagRegistry`** — priority-aware store of active string tags (`"grass"`,
  `"time:night"`, …). Terrain pushes its tag here each frame. See
  [TagSystemGuide.md](TagSystemGuide.md).
- **`EventBus`** — global signal hub so systems stay decoupled (footsteps, time,
  weather, tags). Creatures emit `footstep_start` / `footstep_stop` through it.
- **`ScentRegistry`** — decaying scent trail map. `GoalExploreTrees` deposits
  scent at visited trees; scent fades (`DECAY_RATE`) so creatures spread out.
- **`AudioManager`** — turns footstep/terrain events into sound.

---

## 6. The four overworld species

All four are thin `Creature` subclasses (just `class_name` + docs); their
personality is the goal set configured on each instance in **OverworldScene.tscn**.
See [SpeciesReference.md](SpeciesReference.md) for the exact stat/goal table.

| Species   | Prefers      | Key goals (besides Wander/Safety/Sleep) | Speed |
|-----------|--------------|-----------------------------------------|-------|
| **Fox**   | grass (1)    | GoalPlay on ice, GoalExploreTrees       | 32    |
| **Bird**  | trees (5)    | GoalExploreTrees (wide radius)          | 48    |
| **Dinosaur** | sand (2)  | — (plods the dunes)                      | 24    |
| **Urchin** | ice (3)     | — (slow, homebound)                      | 14    |

> Fox still uses the legacy `abomination001.png` art — the behaviour, not the
> texture, defines the species. Bird / Dinosaur / Urchin use their own 16×16 art
> in `ImageAssets/Creatures/`.

---

## 7. How to… (recipes)

### Add a new creature instance to the overworld
1. Duplicate an existing creature node in `OverworldScene.tscn` (e.g. the Fox).
2. Point its `script` at the right species and swap the `Sprite2D.texture`.
3. Set `ground_layer` to `../BasicTilemapLayer`.
4. Tune the `GoalAI` children (terrain weights, safe/home tags).

### Add a brand-new species
1. Create `Scripts/Creatures/MySpecies.gd` → `extends Creature` /
   `class_name MySpecies` with a doc comment (copy `Fox.gd` as a template).
2. Add an instance in the scene with a `GoalAI` and the goal nodes you want.
3. Document it in [SpeciesReference.md](SpeciesReference.md).

### Add a new *behaviour* (not just a new config)
1. Create `Scripts/AI/Goals/GoalX.gd` → `extends AIGoal`.
2. Override `priority()` (return >0 when it should run) and `decide(delta)`
   (write `_ai._move_dir`). Use `_process_goal(delta)` for timers.
3. Pick a priority tier that slots sensibly into the table in §3.
4. Add it as a child of the `GoalAI` nodes that should have it.

### Make a creature respond to the player
Implement `on_creature_touch(other)` on the creature (or react to the player's
terrain tag / position inside a goal's `decide()`). Nothing reacts to the player
yet — this is open territory.
