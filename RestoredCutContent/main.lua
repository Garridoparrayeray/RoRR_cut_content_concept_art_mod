-- ============================================================================
-- RestoredCutContent - Mod para Risk of Rain Returns
-- Restaura contenido descartado segun el documento de desarrollo y concept art
-- ============================================================================

if mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"] then
    mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
end

PATH = _ENV["!plugins_mod_folder_path"]
NAMESPACE = "restored_cut_content"

-- Orden de carga: util primero (los demas dependen de el)
local MODULES = {
    "util.lua",
    "shrine_challenge.lua",   -- oShrine6: altar de desafio
    "shrine_empower.lua",     -- oShrineEmpower: altar de empoderamiento
    "tardigrade.lua",         -- oMacT: Tardigrado (F12 = prueba)
    "debug_cheats.lua",       -- F5-F8
}

local function load_modules()
    for _, name in ipairs(MODULES) do
        package.loaded[name] = nil
        require(name)
    end
    log.info("[RestoredCutContent] Modulos cargados: " .. #MODULES .. " (build 2026-10-11-x: F5 empoderamiento, F9 desafio, F6 dios, F7 matar, F8 oro, F10-F11 frames, F12 tardigrado)")
end

Initialize(load_modules)

-- Recarga en caliente: Initialize solo corre en el arranque
if HOTLOAD then
    load_modules()
end
HOTLOAD = true
