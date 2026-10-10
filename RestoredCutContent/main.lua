-- ============================================================================
-- RestoredCutContent - Mod para Risk of Rain Returns
-- Basado en el documento de desarrollo y Concept Art oficial
-- ============================================================================

-- Inicializar Toolkit de modding
if mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"] then
    mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
end

PATH = _ENV["!plugins_mod_folder_path"]
NAMESPACE = "restored_cut_content"

log.info("[RestoredCutContent] Inicializando mod de restauracion de contenido descartado...")

local init = function()
    log.info("[RestoredCutContent] Directorio de assets: " .. tostring(PATH) .. "/assets")

    -- ------------------------------------------------------------------------
    -- 1. Altar de Desafío de Combate (oShrine6)
    -- ------------------------------------------------------------------------
    package.loaded["shrine_challenge.lua"] = nil
    require("shrine_challenge.lua")

    -- ------------------------------------------------------------------------
    -- 2. Altar de Empoderamiento (oShrineEmpower)
    -- ------------------------------------------------------------------------
    package.loaded["shrine_empower.lua"] = nil
    require("shrine_empower.lua")

    -- ------------------------------------------------------------------------
    -- 3. Herramientas de depuración (God Mode, 0 CDs, F6, F7, F8)
    -- ------------------------------------------------------------------------
    package.loaded["debug_cheats.lua"] = nil
    require("debug_cheats.lua")

    log.info("[RestoredCutContent] Assets y hooks listos para ejecucion.")
end

Initialize(init)

if HOTLOAD then
    init()
end
HOTLOAD = true
