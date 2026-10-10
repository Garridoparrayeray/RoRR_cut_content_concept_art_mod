-- ============================================================================
-- tardigrade.lua
-- Macrobic Tardigrade (oMacT): enemigo descartado que sigue en los archivos del
-- juego con todos sus sprites (Idle, Spawn, Walk, Climb, Shoot1, Death).
--
-- Fase 1 (esta): prueba aislada. F12 lo crea junto al jugador y el log registra su
-- comportamiento unos segundos, para saber que hace el enemigo original antes de
-- meterlo en los bestiarios.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local TARDIGRADE_OBJ = gm.constants.oMacT

local KEY_DEBUG_SPAWN  = 123    -- F12
local SPAWN_OFFSET_X   = 150    -- px a la derecha del jugador
local MONITOR_FRAMES   = 1500   -- 25 s de observacion
local MONITOR_INTERVAL = 90     -- frames entre lineas del log

local watched = nil             -- instancia observada
local watch_timer = 0

-- Lee un campo sin que un campo inexistente rompa la observacion
local function read_field(inst, field)
    local ok, value = pcall(function()
        return inst[field]
    end)
    if not ok then return "<error>" end
    return tostring(value)
end

local function sprite_name(inst)
    local ok, name = pcall(function()
        return gm.sprite_get_name(inst.sprite_index)
    end)
    if ok then return tostring(name) end
    return "?"
end

local function describe(inst)
    return string.format("pos=(%.0f,%.0f) sprite=%s frame=%s hp=%s/%s team=%s",
        inst.x, inst.y, sprite_name(inst), read_field(inst, "image_index"),
        read_field(inst, "hp"), read_field(inst, "maxhp"), read_field(inst, "team"))
end

local function spawn_tardigrade(player)
    if not TARDIGRADE_OBJ then
        Util.chat("<r>[TARDIGRADO]</c> oMacT no existe en este juego.")
        log.error("[RestoredCutContent] oMacT no encontrado en gm.constants")
        return
    end

    local inst = gm.instance_create(player.x + SPAWN_OFFSET_X, player.y, TARDIGRADE_OBJ)
    if not inst or not Instance.exists(inst) then
        Util.chat("<r>[TARDIGRADO]</c> No se pudo crear la instancia.")
        log.error("[RestoredCutContent] gm.instance_create devolvio una instancia invalida")
        return
    end

    Util.snap_to_ground(inst, 80, 40)
    watched = inst
    watch_timer = 0

    log.info("[RestoredCutContent] Tardigrado creado: " .. describe(inst))
    Util.chat("<g>[TARDIGRADO]</c> Creado. El log registra su comportamiento durante 25 s.")
end

local function update_monitor()
    if not watched then return end

    watch_timer = watch_timer + 1

    if not Instance.exists(watched) then
        log.info(string.format("[RestoredCutContent] Tardigrado: desaparecio tras %d frames", watch_timer))
        Util.chat("<y>[TARDIGRADO]</c> Ya no existe (murio o se destruyo).")
        watched = nil
        return
    end

    if watch_timer % MONITOR_INTERVAL == 0 then
        log.info(string.format("[RestoredCutContent] Tardigrado t=%d: %s", watch_timer, describe(watched)))
    end

    if watch_timer >= MONITOR_FRAMES then
        log.info("[RestoredCutContent] Tardigrado: fin de la observacion")
        watched = nil
    end
end

Callback.add(Callback.TYPE.postStep, "Tardigrade_Debug", function()
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if player and gm.keyboard_check_pressed(KEY_DEBUG_SPAWN) == 1.0 then
        local ok, err = pcall(spawn_tardigrade, player)
        if not ok then Util.log_once("Tardigrade", err) end
    end

    local ok, err = pcall(update_monitor)
    if not ok then Util.log_once("Tardigrade", err) end
end)

log.info("[RestoredCutContent] tardigrade.lua cargado (F12 = crear Tardigrado de prueba)")
