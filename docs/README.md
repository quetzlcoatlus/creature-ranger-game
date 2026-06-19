# Creature Ranger — Developer Docs

Reference docs for the Godot project under `godot-project/`. Start here.

## Index

| Doc | What's in it |
|-----|--------------|
| [CreaturesGuide.md](CreaturesGuide.md) | How overworld creatures move, sense terrain, and decide what to do (the `Creature` + `GoalAI`/`AIGoal` systems). **Read this first** to understand creature AI. |
| [SpeciesReference.md](SpeciesReference.md) | Exact stats & goal config for each species (Fox, Bird, Dinosaur, Urchin). |
| [OverworldScene.md](OverworldScene.md) | Node layout of `OverworldScene.tscn`: tilemaps, terrain data, environment, creatures. |
| [TagSystemGuide.md](TagSystemGuide.md) | The `TagRegistry` tag system used by terrain, time-of-day, and zones. |

## Project layout cheat-sheet

```
godot-project/
├── Scenes/OverworldScene.tscn      the overworld (terrain + player + creatures)
├── Scripts/
│   ├── Creatures/                  Creature base, species, Player, ShadowSprite2D
│   ├── AI/                         AIController, GoalAI, AIGoal + Goals/
│   ├── World/GameEnvironment.gd    clock / sun / weather (autoload-style singleton)
│   └── Tilemap/                    border collision, tree Y-sort layering
├── autoload/                       TagRegistry, EventBus, ScentRegistry, AudioManager
├── ImageAssets/ · AudioAssets/     art & sound
└── creatures/  (lowercase)         SEPARATE capture mini-game — not the overworld
```

> ⚠️ **Two creature systems exist.** `Scripts/Creatures/` (this set of docs) is
> the **overworld**. The lowercase `creatures/` folder is the **capture
> mini-game** (`CaptureCreature`), a different game mode. Don't mix them up.

## Conventions worth knowing

- **Behaviour is data, not code.** Species scripts are nearly empty; what a
  creature *does* is the set of `AIGoal` nodes + Inspector values on its
  instance. Add behaviour by adding/configuring goals, not by writing creature
  code. (See CreaturesGuide §7.)
- **Terrain tags** are a shared int vocabulary between the TileSet's
  `terrain_tag` custom data and the AI: `1 grass · 2 sand · 3 ice · 4 water ·
  5 tree · 6 stone`.
- **Singletons over references.** Systems talk through `EventBus` signals and
  read `GameEnvironment` / `TagRegistry` / `ScentRegistry`, rather than holding
  direct node references.
