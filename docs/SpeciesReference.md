# Species Reference

Exact stats and goal configuration for each overworld creature, as set on the
instances in `OverworldScene.tscn`. For *how* the system works, read
[CreaturesGuide.md](CreaturesGuide.md) first.

Terrain tags: `1 = grass`, `2 = sand`, `3 = ice`, `5 = tree` (ObjectLayer).

---

## Fox  — `Scripts/Creatures/Fox.gd`
*Curious grass-dweller that detours to trees and goes wild on ice.*

- **Sprite:** `abomination001.png` (legacy art — fox art TBD)
- **max_speed:** 32 · **time_to_stop:** 0.1
- **Goals:**
  | Goal | Config |
  |------|--------|
  | GoalWander | weights `{grass: 1.0, sand: -0.8, ice: 0.0}`, radius 50 |
  | GoalSafety | safe `[grass]`, timeout 8s |
  | GoalSleep  | home `[grass]`, safe `[grass]` |
  | GoalPlay   | fun `[ice]` — sprints & jitters on ice |
  | GoalExploreTrees | default (visits trees by day) |

## Bird — `Scripts/Creatures/Bird.gd`
*Fast, skittish, lives around trees; roosts on grass at night.*

- **Sprite:** `bird.png`
- **max_speed:** 48 · **time_to_stop:** 0.1
- **Goals:**
  | Goal | Config |
  |------|--------|
  | GoalWander | weights `{grass: 0.4, sand: 0.0, ice: 0.0}`, radius 70 |
  | GoalSafety | safe `[grass]`, timeout 10s |
  | GoalSleep  | home `[grass]`, safe `[grass]` |
  | GoalExploreTrees | search_radius 160, linger 3.0 |
- **No GoalPlay** — tree-hopping is its idle activity.

## Dinosaur — `Scripts/Creatures/Dinosaur.gd`
*Slow, heavy dune-plodder that sticks to the sand.*

- **Sprite:** `dinosaur.png`
- **max_speed:** 24 · **time_to_stop:** 0.15 (extra momentum/weight)
- **Goals:**
  | Goal | Config |
  |------|--------|
  | GoalWander | weights `{sand: 1.0, grass: 0.0, ice: -0.8}`, radius 50 |
  | GoalSafety | safe `[sand]`, timeout 10s (flees back to sand) |
  | GoalSleep  | home `[sand]`, safe `[sand]` |
- **No GoalPlay, no GoalExploreTrees.**

## Urchin — `Scripts/Creatures/Urchin.gd`
*Very slow, ice-loving, homebound. Slides a little on the low-friction ice.*

- **Sprite:** `urchin.png`
- **max_speed:** 14 · **time_to_stop:** 0.1
- **Goals:**
  | Goal | Config |
  |------|--------|
  | GoalWander | weights `{ice: 1.0, grass: 0.0, sand: -0.5}`, radius 40 |
  | GoalSafety | safe `[ice]`, timeout 12s |
  | GoalSleep  | home `[ice]`, safe `[ice]` |
- **No GoalPlay, no GoalExploreTrees.**

---

## Shared behaviour
All four use the default sleep window from `GoalSleep`
(`sleep_start_hour = 21`, `sleep_end_hour = 6`): they head to their home terrain
in the evening and **stop moving overnight**, resuming at dawn. Weather has no
effect on creatures yet.

## Tuning notes
- A species' "preference" comes from two cooperating knobs: **GoalWander
  weights** (gentle pull toward favoured terrain) and **GoalSafety `safe_tags`**
  (hard pull — it flees anything *not* listed after the timeout). Keeping
  `safe_tags` = `[home terrain]` makes a creature hug its habitat; widen it to
  reduce that.
- If a creature's preferred terrain is a tiny patch, it may oscillate
  (flee out → get pulled back). Raise that species' `safety_timeout` or add a
  second tolerated tag to `safe_tags`.
- Birds "prefer trees," but trees live in the **ObjectLayer**, not the ground
  layer, so they can't be a `safe`/`home` tag. Birds home on grass and rely on
  `GoalExploreTrees` to keep them near trees during the day.
