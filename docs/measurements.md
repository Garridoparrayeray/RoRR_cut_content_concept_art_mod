# In-game measurements

[Español](mediciones.es.md) · **English**

The game's code is compiled (there is no readable GML), so the behaviour of cut objects is measured in-game using
the mod's log (`LogOutput.log`). This page collects what has been measured so far.

## Enemies (health and reward at spawn, stage 1)

| Enemy | Object | Health | Reward (`exp_worth`) |
|---|---|---|---|
| Lemurian | `oLizard` | 100 | 6 |
| Lesser Wisp | `oWisp` | 170 | 12 |
| Spitter | `oSpitter` | 240 | 23 |
| Macrobic Tardigrade | `oMacT` | 100 | 20 |

The engine applies time/difficulty scaling when an enemy is created with `instance_create` (the Tardigrade spawned
with 100 health and later with 113).

## Macrobic Tardigrade (`oMacT`)

| Phase | Sprite | Duration / data |
|---|---|---|
| Spawn | `sMacTSpawn` | ~57 frames |
| Walk | `sMacTWalk` | chases the player |
| Strike | `sMacTShoot1` | ~130 frames; **39–45 damage** at 20–40 px, after ~1 s of wind-up |
| Explosion | `sMacTDeath` | the original animates the explosion but it neither damages nor kills: the enemy walks on |

The mod completes the explosion so that it deals area damage and kills the enemy (with no reward).

## Shrines

| Shrine | Sprite | Frames | Death animation |
|---|---|---|---|
| Challenge (`oShrine6`) | `sShrine6` | 11 (0–10) | `sShrine6Death`, 8 frames, the last one is rubble |
| Empowerment (`oShrineEmpower`) | `sShrineEmpower` | 7 (0–6) | `sShrineEmpowerDeath`, 7 frames |

`sShrine6` frame geometry: 4 and 5 are the same size (sparks), 7 is the lightning (full height), 8–9 are the
shockwave and 10 is identical to 0.

## Game objects that must NOT be created from Lua

| Object | Effect |
|---|---|
| `oEfSpawnFlash` | Exception in its Draw event: white screen |
| `oEfDust1`, `oEfDust2` | Continuous emitters: the dust never ends |
| `hud:add_gold()` / `gm.add_gold()` | They do not exist: `ACCESS_VIOLATION` (crash) |
