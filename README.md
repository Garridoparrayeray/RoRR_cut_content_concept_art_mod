# RoRR_cut_content_concept_art_mod

[Español](README.es.md) · **English**

In this repo u will see implementations of the cut content of Risk of Rain Returns and implementation of some. concept arts. 

## Restored Cut Content — a mod for Risk of Rain Returns

A [ReturnOfModding](https://thunderstore.io/c/risk-of-rain-returns/) mod that **restores cut or unfinished
content** from *Risk of Rain Returns*, based on what the developers left in the game files and on the public
cut content and concept art document.

> Status: **work in progress (0.1.0)**. Several values are tuned from measurements taken in-game.

## What it includes

### Challenge Shrine (`oShrine6`)
A cut, single-use shrine that costs gold and gets more expensive with threat (stages cleared + time).

- Charge-up, a full lightning strike, a combat phase with a blue pulse that reacts to the horde, an overload and a
  **destruction using its native animation** (`sShrine6Death`) that leaves rubble and drops an item.
- Hordes of **4 to 8 enemies** that spawn **one by one**; size, elites and reward scale with threat.
- The bestiary depends on the **map** (Dried Lake, Desolate Forest, Damp Caverns, Sky Meadow, Ancient Valley,
  Sunken Tombs, Magma Barracks, Hive Cluster, Temple of the Elders).
- There can be 0–3 per map; each one is paid for separately.

### Empowerment Shrine (`oShrineEmpower`)
A cut shrine that asks for **gold and health at the same time** (never lethal) in exchange for a temporary blessing
(damage, attack speed, crit and movement, plus a holy strike). **Only one per stage.** It is destroyed with its
native animation (`sShrineEmpowerDeath`).

### Macrobic Tardigrade (`oMacT`)
A cut enemy that is still in the game files.

- It walks towards the player, hits in melee and explodes; the mod finishes that explosion so it deals damage and
  kills the enemy (the original animated it but the enemy kept walking).
- It appears as a rarity in hordes and naturally next to walls.
- At high threat it can show up as an **Alpha** (boss): more health, bigger and a better reward.

## Installation

Copy the `RestoredCutContent` folder into `ReturnOfModding/plugins/` (or install it with r2modman in a profile that
has the dependencies listed in `manifest.json`). The mod works out of the box: **it ships with no god mode and no
cheat keys**.

Dependencies: ReturnOfModding, ReturnsAPI and RoRR Modding Toolkit.

## Development tools (separate from the mod)

Test keys and cheats are **not part of the mod**: they live in [`dev_tools/`](dev_tools/) for the team. They are
enabled by copying `dev_tools/debug_tools.lua` next to `main.lua`; without that file the mod loads none of it.
See [`dev_tools/README.md`](dev_tools/README.md).

## Structure

| Path | Contents |
|---|---|
| `RestoredCutContent/` | The mod (the only thing you install) |
| `RestoredCutContent/main.lua` | Entry point and module load order |
| `RestoredCutContent/util.lua` | Shared utilities: animation, shrine spawning, enemy tuning, biome detection |
| `RestoredCutContent/shrine_challenge.lua` | Challenge Shrine |
| `RestoredCutContent/shrine_empower.lua` | Empowerment Shrine |
| `RestoredCutContent/tardigrade.lua` | Tardigrade: explosion and natural spawning |
| `RestoredCutContent/assets/` | Sprites and animations of the cut content (Monkey, Restless Oak, drones, items, Chef...), taken from the cut content document and sorted by type |
| `dev_tools/` | Test and data-extraction tools (not installed) |
| `docs/mediciones.md` | Measurements taken in-game (in Spanish) |
| `CHANGELOG.md` | Versions, in order (in Spanish) |

## How it is developed

The game's code is compiled (there is no readable GML), so the behaviour of cut objects is **measured in-game**:
the mod writes animations, damage, health and rewards of each enemy to `LogOutput.log`, and values are tuned from
that data. Settings live in constants at the top of each file or in `Util.ENEMY_TUNING`. The git history keeps
every version, together with the `build` it carried.

## Credits
potato: Doc creator and maintainer (Discord: garlicism)  
Matsan: Compiled all the initial images on discord, wrote the intro, and refined the doc (Discord: .matsan)  
  
  
Massive thanks to these developers for providing all of the great content in this document:  
  
RareThistle  
(Art Lead)  
Sarn  
(Lead Programmer)  
Bizzozeron  
(Art and Animation)  
Dee  
(Additional programming, animation, and design)  
Thanks for doing this job accessible.  

## License

The code and documentation in this repository are released under the **MIT license** (see [`LICENSE`](LICENSE)):
you are free to use, copy, modify and redistribute them, keeping the copyright notice.

**The MIT license does not cover the third-party resources** in `RestoredCutContent/assets/` (concept art, sprites
and animations from *Risk of Rain Returns*), which belong to their original authors. They are included because they
are content the development team made public, and they remain subject to their own rights.

## Notice

- Original content: **Hopoo Games / Gearbox** — *Risk of Rain Returns*.
- Fan project, not affiliated with the developers.
