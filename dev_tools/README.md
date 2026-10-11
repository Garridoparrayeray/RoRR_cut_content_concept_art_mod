# Development tools

[Español](README.es.md) · **English**

None of this is part of the mod: **whoever installs `RestoredCutContent` gets no god mode and no cheat keys.**
These tools are for the team's own testing.

## `debug_tools.lua`: test keys and cheats

To use it locally, copy `debug_tools.lua` into the mod folder, next to `main.lua`
(`ReturnOfModding/plugins/RestoredContent-RestoredCutContent/`). `main.lua` loads it only if it exists; to turn it
off just remove the file.

| Key | Action |
|---|---|
| F5 | Empowerment Shrine next to the player (does not use up the stage's single use) |
| F9 | Challenge Shrine next to the player |
| F6 | God mode (invulnerable, full health, no cooldowns) |
| F7 | Kill every enemy through the normal damage path |
| F8 | +1000 gold |
| F10 / F11 | Next / previous frame of the nearest shrine |
| F12 | Test Tardigrade (with Shift, an Alpha); the log records its animations, damage taken and damage dealt |

Shrines are created through `Util.dev_hooks`, which the mod's own modules register; the mod itself defines no keys.

## `extract/`: extracting data from the game

PowerShell scripts that read `data.win` from your own copy of the game to get the frame geometry of a sprite and to
dump texture pages (BZ2 + QOI). They were used to check the frame sizes of the shrines and to find their death
animations.

| Script | Purpose |
|---|---|
| `extract_sprites.ps1` | Lists the frames (source and target rectangles in the texture) of the given sprites |
| `dump_pages.ps1` | Dumps raw texture pages |
| `dump_page.ps1` | Decodes a QOI page and saves it as PNG |
| `render_frames.ps1` | Crops frames from a decoded page and builds a contact sheet |

Run them with `powershell -File`, passing the path to `data.win`. They contain no game resources.
