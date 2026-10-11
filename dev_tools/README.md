# Herramientas de desarrollo

Nada de esto forma parte del mod: **quien instala `RestoredCutContent` no tiene modo dios ni teclas de trampa**.
Estas herramientas son para pruebas del equipo.

## `debug_tools.lua`: teclas de prueba y trampas

Para usarlo en local, copia `debug_tools.lua` a la carpeta del mod, junto a `main.lua`
(`ReturnOfModding/plugins/RestoredContent-RestoredCutContent/`). `main.lua` lo carga solo si existe; para
desactivarlo basta con quitar el fichero.

| Tecla | Acción |
|---|---|
| F5 | Altar de Empoderamiento junto al jugador (no gasta el uso de la fase) |
| F9 | Altar de Desafío junto al jugador |
| F6 | Modo Dios (invulnerable, vida máxima, sin cooldowns) |
| F7 | Mata a todos los enemigos por la vía normal de daño |
| F8 | +1000 de oro |
| F10 / F11 | Fotograma siguiente / anterior del altar más cercano |
| F12 | Tardígrado de prueba (con Mayús, un Alfa); el log registra animaciones, daño recibido y daño hecho |

Los altares se crean mediante `Util.dev_hooks`, que registran los propios módulos del mod; el mod en sí no
define ninguna tecla.

## `extract/`: extracción de datos del juego

Scripts de PowerShell que leen `data.win` de tu propia copia del juego para obtener la geometría de los
fotogramas de un sprite y volcar páginas de textura (BZ2 + QOI). Sirvieron para comprobar el tamaño de los
fotogramas de los altares y localizar sus animaciones de muerte.

| Script | Función |
|---|---|
| `extract_sprites.ps1` | Lista fotogramas (origen y destino en la textura) de los sprites indicados |
| `dump_pages.ps1` | Vuelca páginas de textura en bruto |
| `dump_page.ps1` | Decodifica una página QOI y la guarda como PNG |
| `render_frames.ps1` | Recorta fotogramas de una página decodificada y arma una hoja de contacto |

Se ejecutan con `powershell -File`, pasando la ruta de `data.win`. No incluyen ningún recurso del juego.
