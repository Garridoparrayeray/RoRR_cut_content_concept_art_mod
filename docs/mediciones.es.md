# Mediciones en partida
**Español** · [English](measurements.md)

El código del juego va compilado (no hay GML legible), así que el comportamiento de los objetos descartados se
mide en partida con el log del mod (`LogOutput.log`). Esto recoge lo medido hasta ahora.

## Enemigos (vida y recompensa al crearse, fase 1)

| Enemigo | Objeto | Vida | Recompensa (`exp_worth`) |
|---|---|---|---|
| Lemurian | `oLizard` | 100 | 6 |
| Lesser Wisp | `oWisp` | 170 | 12 |
| Spitter | `oSpitter` | 240 | 23 |
| Macrobic Tardigrade | `oMacT` | 100 | 20 |

El motor aplica el escalado por tiempo/dificultad al crear un enemigo con `instance_create` (el Tardígrado
nació con 100 y más tarde con 113 de vida).

## Macrobic Tardigrade (`oMacT`)

| Fase | Sprite | Duración / datos |
|---|---|---|
| Aparición | `sMacTSpawn` | ~57 frames |
| Andar | `sMacTWalk` | persigue al jugador |
| Golpe | `sMacTShoot1` | ~130 frames; **39–45 de daño** a 20–40 px, tras ~1 s de carga |
| Explosión | `sMacTDeath` | en el original anima la explosión pero no daña ni mata: el enemigo vuelve a andar |

El mod completa la explosión para que dañe en área y mate al enemigo (sin recompensa).

## Altares

| Altar | Sprite | Fotogramas | Animación de muerte |
|---|---|---|---|
| Desafío (`oShrine6`) | `sShrine6` | 11 (0–10) | `sShrine6Death`, 8 fotogramas, el último son escombros |
| Empoderamiento (`oShrineEmpower`) | `sShrineEmpower` | 7 (0–6) | `sShrineEmpowerDeath`, 7 fotogramas |

Geometría de `sShrine6`: 4 y 5 miden igual (chispas), 7 es el rayo (altura completa), 8–9 son la onda
expansiva y el 10 es idéntico al 0.

## Objetos del juego que NO deben crearse desde Lua

| Objeto | Efecto |
|---|---|
| `oEfSpawnFlash` | Excepción en su evento Draw: pantalla en blanco |
| `oEfDust1`, `oEfDust2` | Emisores continuos: el polvo no termina nunca |
| `hud:add_gold()` / `gm.add_gold()` | No existen: `ACCESS_VIOLATION` (crash) |
