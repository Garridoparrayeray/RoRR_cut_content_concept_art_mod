# RoRR_cut_content_concept_art_mod
In this repo u will see implementations of the cut content of Risk of Rain Returns and implementation of some. concept arts. 

## Restored Cut Content — mod para Risk of Rain Returns

Mod de [ReturnOfModding](https://thunderstore.io/c/risk-of-rain-returns/) que **restaura contenido recortado o
inacabado** de *Risk of Rain Returns* a partir de lo que los desarrolladores dejaron en los archivos del juego y
del documento público de contenido descartado y concept art.

> Estado: **en desarrollo (0.1.0)**. Varias partes se ajustan con mediciones hechas en partida.

## Qué incluye

### Altar de Desafío (`oShrine6`)
Altar recortado, de un solo uso, que cuesta oro y encarece con la amenaza (fases superadas + tiempo).

- Carga, rayo completo, combate con latido azul que responde a la horda, sobrecarga y **destrucción con su
  animación nativa** (`sShrine6Death`), dejando escombros y soltando un objeto.
- Hordas de **4 a 8 enemigos** que aparecen **uno a uno**; tamaño, élites y recompensa escalan con la amenaza.
- El bestiario depende del **mapa** (Lago Seco, Bosque Desolado, Cavernas Húmedas, Pradera Celestial, Valle
  Antiguo, Tumbas Hundidas, Cuartel de Magma, Colmena, Templo de los Ancianos).
- Puede haber 0–3 por mapa; cada uno se paga por separado.

### Altar de Empoderamiento (`oShrineEmpower`)
Altar recortado que pide **oro y vida a la vez** (nunca letal) a cambio de una bendición temporal (daño,
velocidad de ataque, crítico y movimiento, más un golpe sagrado). **Solo uno por fase.** Se destruye con su
animación nativa (`sShrineEmpowerDeath`).

### Macrobic Tardigrade (`oMacT`)
Enemigo descartado que sigue en los archivos del juego.

- Camina hacia el jugador, golpea cuerpo a cuerpo y explota; el mod completa esa explosión para que dañe y lo
  mate (el original la animaba pero seguía andando).
- Aparece como rareza en hordas y de forma natural junto a paredes.
- Con amenaza alta puede aparecer como **Alfa** (jefe): más vida, más grande y mejor recompensa.

## Instalación

Copia la carpeta `RestoredCutContent` en `ReturnOfModding/plugins/` (o instálalo con r2modman en un perfil que
tenga las dependencias de `manifest.json`). El mod funciona directamente: **no incluye modo dios ni teclas de
trampa**.

Dependencias: ReturnOfModding, ReturnsAPI y RoRR Modding Toolkit.

## Herramientas de desarrollo (aparte del mod)

Las teclas de prueba y las trampas **no forman parte del mod**: están en [`dev_tools/`](dev_tools/) para el equipo.
Se activan copiando `dev_tools/debug_tools.lua` junto a `main.lua`; sin ese fichero, el mod no carga nada de eso.
Ver [`dev_tools/README.md`](dev_tools/README.md).

## Estructura

| Ruta | Contenido |
|---|---|
| `RestoredCutContent/` | El mod (lo único que se instala) |
| `RestoredCutContent/main.lua` | Punto de entrada y orden de carga |
| `RestoredCutContent/util.lua` | Utilidades compartidas: animación, generación de altares, ajuste de enemigos, bioma |
| `RestoredCutContent/shrine_challenge.lua` | Altar de Desafío |
| `RestoredCutContent/shrine_empower.lua` | Altar de Empoderamiento |
| `RestoredCutContent/tardigrade.lua` | Tardígrado: explosión y aparición natural |
| `dev_tools/` | Herramientas de prueba y de extracción de datos (no se instalan) |
| `docs/mediciones.md` | Datos medidos en partida |
| `CHANGELOG.md` | Versiones, en orden |

## Cómo se trabaja

El código del juego va compilado (no hay GML legible), así que el comportamiento de los objetos descartados se
**mide en partida**: el mod escribe en `LogOutput.log` animaciones, daños, vida y recompensa de cada enemigo, y los
valores se ajustan con esos datos. Los ajustes viven en constantes al inicio de cada fichero o en
`Util.ENEMY_TUNING`. El historial de git conserva cada versión, con la `build` que llevaba.

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

## Aviso

- Contenido original: **Hopoo Games / Gearbox** — *Risk of Rain Returns*.
- Proyecto de aficionados, sin afiliación con los desarrolladores.
