# Creature Ranger Game Prototype

## Game Pitch	

A short top-down creature capture prototype inspired heavily by Pokemon Ranger, where the player captures creatures by drawing loops around them and avoiding their behaviors. The game features a small overworld with NPC interactions and encounterable wild creatures showcasing 4 different behavior sets.

## Core Gameplay Loop

1. Player explores overworld 
    - NPCs and environment
2. Player encounters creature 
    - Upon seeing the player they might be aggressive, docile, or afraid
3. Player walks into creature to enter capture scene
    - Player hitbox collides with theirs
4. Perform capture interaction
    - Drawing loops, taking damage, run away
5. Success or failure
    - Success: draw enough loops to capture/run away
    - Failure: run out of HP
6. Return to overworld with state change
    - New creature in party
    - Run away nothing happens and the creature is frozen temporarily
    - Run out of HP then return to main menu/last save

## Player Actions

### Overworld

| What          | When                                                    | Result                                                |
|---------------|---------------------------------------------------------|-------------------------------------------------------|
| Move          | Overworld                                               | Travel to destinations  Start creature capture scenes |
| Talk          | Next to non-creature NPC                                | Text display on screen  Event triggers                |
| Start capture | Colliding with creature or triggered by NPC interaction | Enter capture scene with associated creature          |

### Capture Scene

| What                                     | When                    | Result                               |
|------------------------------------------|-------------------------|--------------------------------------|
| Draw capture loops with mouse/controller | Creature loop count met | Creature captured after enough loops |
| Cancel capture                           | Run away                | Return player to overworld           |
| Fail capture                             | Player HP == 0          | Return player to main menu           |

### Creature Design

| Name     | Movement Pattern                                                           | Capture Complication                       |
|----------|----------------------------------------------------------------------------|--------------------------------------------|
| Urchin   | Very slow. Stops periodically, moves to destinations within short distance | Punishes imprecise/tight loops with damage |
| Fox      | Erratic. Moves in zigzag patterns quickly in bursts                        | Punishes slow enclosure                    |
| Dinosaur | Medium speed. Creates damage hitbox infront of itself (bite).              | Teaches attack avoidance                   |
| Bird     | Medium speed. Travels off the capture scene in a straight line             | Teaches timing and collision avoidance     |

## Capture System Rules

Valid capture: requires N completed loops (mimicking first Ranger game). When creature has N loops, remove from scene. If no creatures in scene, update state and return to overworld.

Loop must fully enclose creature to increment. If line breaks, reset loops for creature. If line hits creature hitbox, break line. If creature creates damage hitbox and line intersects, reduce HP and break line. Line has maximum length.

Capture Failure: when HP <= 0, return to main menu

## Overworld Scope

Top down camera perspective, centered on player

Single small overworld map

2-3 NPCs: Provide tutorial, flavor and soft goals (e.g. “Try capturing X”)

Purpose is to facilitate captures and add flavor/setting to the prototype

## NPC Interaction Rules

NPCs have 1-2 dialogue lines, one choice that triggers capture scene (e.g. “Do you want to fight my creature?” Y/N). Dialogue update after capture for this NPC.

## Art and Audio Assumptions

Simple stylized models, placeholder animations acceptable.

1 successful capture sound, 1 failure capture sound, 1 capture scene start sound, 1 overworld ambient loop, 1 battle loop

## Technical Scope

- Engine: Godot
- Input: Mouse
- Hardest problems: loop detection around moving targets, creature behavior and creating damaging/non-damaging collision detection

## Not in Prototype
- No save system
- No quest system
- No branching dialogue	
- No boss fights
- No inventory
- No controller implementation
- No creature assists in capture
- No player level up for stat increases
