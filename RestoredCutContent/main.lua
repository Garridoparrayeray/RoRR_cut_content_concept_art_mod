-- ============================================================================
-- RestoredCutContent - Mod para Risk of Rain Returns
-- Restaura contenido descartado segun el documento de desarrollo y concept art
-- ============================================================================

if mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"] then
    mods["RoRRModdingToolkit-RoRR_Modding_Toolkit"].auto(true)
end

PATH = _ENV["!plugins_mod_folder_path"]
NAMESPACE = "restored_cut_content"

-- Inicializar ReturnsAPI con espacio de nombres propio (Search, wrappers y FindCache)
if mods["ReturnsAPI-ReturnsAPI"] then
    mods["ReturnsAPI-ReturnsAPI"].auto({ namespace = NAMESPACE, mp = true })
end

-- Capa de compatibilidad Callback.TYPE y Callback.add (ReturnsAPI / Toolkit)
if Callback then
    if not Callback.TYPE then
        Callback.TYPE = {
            postStep     = Callback.POST_STEP or 4,
            post_step    = Callback.POST_STEP or 4,
            preStep      = Callback.PRE_STEP or 3,
            pre_step     = Callback.PRE_STEP or 3,
            onStep       = Callback.ON_STEP or 2,
            on_step      = Callback.ON_STEP or 2,
            onDraw       = Callback.ON_DRAW or 5,
            on_draw      = Callback.ON_DRAW or 5,
            onStageStart = Callback.ON_STAGE_START or 14,
            on_stage_start = Callback.ON_STAGE_START or 14,
            onGameStart  = Callback.ON_GAME_START or 11,
            onGameEnd    = Callback.ON_GAME_END or 12,
            onKillProc   = Callback.ON_DEATH or 24,
            onAttackHit  = Callback.ON_ATTACK_HIT or 18,
        }
    end

    local orig_callback_add = Callback.add
    Callback.add = function(...)
        local n = select("#", ...)
        local args = { ... }
        if n == 2 and type(args[2]) == "function" then
            local cb_type = args[1]
            if type(cb_type) == "string" then
                cb_type = (Callback.TYPE and Callback.TYPE[cb_type]) or Callback[cb_type] or Callback[cb_type:upper()] or 0
            end
            return orig_callback_add(cb_type, 0, args[2])
        elseif n == 3 and type(args[3]) == "function" and type(args[2]) == "string" then
            local cb_type = args[1]
            if type(cb_type) == "string" then
                cb_type = (Callback.TYPE and Callback.TYPE[cb_type]) or Callback[cb_type] or Callback[cb_type:upper()] or 0
            end
            return orig_callback_add(cb_type, 0, args[3])
        end
        return orig_callback_add(...)
    end
end

-- Orden de carga: util y search primero (los demas dependen de ellos)
local MODULES = {
    "util.lua",
    "search.lua",             -- Motor de busqueda, resolucion y consultas espaciales
    "item_kfl.lua",           -- Item descartado: Kentucky Fried Lemurian (curacion + velocidad)
    "monkey.lua",             -- Enemigo descartado: Mono Espacial (acrobatico + ataque rueda)
    "restless_oak.lua",       -- Enemigo descartado: Roble Inquieto (tanque forestal + pisoton)
    "chef_ice.lua",           -- Habilidad descartada: Cubo de hielo para CHEF
    "emotes.lua",             -- Sistema de emoticonos flotantes sobre el jugador
    "shrine_challenge.lua",   -- oShrine6: altar de desafio
    "shrine_empower.lua",     -- oShrineEmpower: altar de empoderamiento
    "tardigrade.lua",         -- oMacT: Tardigrado
    "impostor.lua",           -- Superviviente Among Us (Impostor): pixel art, habilidades y mecanicas
    "debug_tools.lua",        -- Herramientas de desarrollo: panel ImGui y atajos F1-F12
}

local function load_modules()
    for _, name in ipairs(MODULES) do
        package.loaded[name] = nil
        require(name)
    end

    log.info("[RestoredCutContent] Modulos cargados: " .. #MODULES .. " (build 2026-10-16-ad)")
    HOTLOADING = true
end

if type(Initialize) == "table" and Initialize.add then
    Initialize.add(load_modules)
elseif type(Initialize) == "function" then
    Initialize(load_modules)
end

if HOTLOADING then
    load_modules()
end


