-- ============================================================================
-- debug_tools.lua  -  HERRAMIENTAS DE DESARROLLO (no forman parte del mod)
--
-- Teclas de prueba y trampas para el equipo. NO se distribuye con el mod: vive en la
-- carpeta dev_tools/ del repositorio. Para usarla en local, copiarla junto a main.lua;
-- main.lua la carga solo si existe. Quien instala el mod no tiene nada de esto.
--
--   F5   Altar de Empoderamiento junto al jugador (no gasta el uso de la fase)
--   F9   Altar de Desafio junto al jugador
--   F6   Modo Dios (invulnerable, vida maxima, sin cooldowns)
--   F7   Matar a todos los enemigos (por la via normal de dano)
--   F8   +1000 de oro
--   F10 / F11  Fotograma siguiente / anterior del altar mas cercano (inspector)
--   F12  Tardigrado de prueba (con Mayus, Alfa) + registro de su comportamiento en el log
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local KEY = { F5 = 116, F6 = 117, F7 = 118, F8 = 119, F9 = 120, F10 = 121, F11 = 122, F12 = 123, SHIFT = 16 }

local GOLD_AMOUNT        = 1000
local LETHAL_COEFFICIENT = 1000000
local SHRINE_OFFSET_X    = 60

local TARDIGRADE_OBJ   = gm.constants.oMacT
local SPAWN_OFFSET_X   = 150    -- px a la derecha del jugador
local MONITOR_FRAMES   = 1500   -- 25 s de observacion
local MONITOR_INTERVAL = 90     -- frames entre lineas del log

local god_mode = false

local function pressed(key)
    return gm.keyboard_check_pressed(key) == 1.0
end

-- ----------------------------------------------------------------------------
-- Altares (usan los ganchos que registran los modulos del mod)
-- ----------------------------------------------------------------------------
local function spawn_empower(player)
    local hook = Util.dev_hooks.spawn_empower_shrine
    if not hook then
        Util.chat("<r>[DEV F5]</c> El modulo del altar de empoderamiento no esta cargado.")
        return
    end
    local shrine = hook(player.x + SHRINE_OFFSET_X, player.y)
    if shrine then
        Util.chat("<g>[DEV F5]</c> Altar de Empoderamiento creado ($" .. tostring(shrine.cost) .. " + vida). F8 da oro.")
    end
end

local function spawn_challenge(player)
    local hook = Util.dev_hooks.spawn_challenge_shrine
    if not hook then
        Util.chat("<r>[DEV F9]</c> El modulo del altar de desafio no esta cargado.")
        return
    end
    local shrine = hook(player.x - SHRINE_OFFSET_X, player.y)
    if shrine then
        Util.chat("<g>[DEV F9]</c> Altar de Desafio creado ($" .. tostring(shrine.cost) .. "). F8 da oro.")
    end
end

-- ----------------------------------------------------------------------------
-- Trampas
-- ----------------------------------------------------------------------------
local function toggle_god_mode(player)
    god_mode = not god_mode
    if god_mode then
        Util.chat("<g>[MODO DIOS]</c> Activado: vida infinita y sin cooldowns.")
    else
        player.invincible = 0
        Util.chat("<r>[MODO DIOS]</c> Desactivado.")
    end
end

local function apply_god_mode(player)
    player.invincible = 60
    if type(player.maxhp) == "number" then
        player.hp = player.maxhp
    end
    for slot = 0, 3 do
        pcall(function()
            player:refresh_skill(slot)
        end)
    end
    if type(player.equipment_cooldown) == "number" and player.equipment_cooldown > 0 then
        player.equipment_cooldown = 0
    end
end

-- Dano letal por el flujo normal del juego: la muerte, el oro y la experiencia
-- se procesan igual que en una partida (nada de tocar hp/dead a mano)
local function kill_all_enemies(player)
    local killed = 0
    for _, enemy in ipairs(Instance.find_all(gm.constants.pEnemy)) do
        local ok = pcall(function()
            player:fire_direct(enemy, LETHAL_COEFFICIENT, 0, nil, nil, gm.constants.sNone, false)
        end)
        if ok then killed = killed + 1 end
    end
    Util.chat("<y>[DEV F7]</c> Enemigos eliminados: " .. killed)
end

-- El oro vive en el HUD. Se escribe directamente en el campo: llamar a
-- hud:add_gold() o gm.add_gold() no existe en el motor y provoca un crash.
local function add_gold(amount)
    for _, hud in ipairs(Instance.find_all(gm.constants.oHUD)) do
        if type(hud.gold) == "number" then
            hud.gold = hud.gold + amount
            return true
        end
    end
    return false
end

-- Inspector de fotogramas: recorre a mano los frames del altar mas cercano
-- (solo altares sin activar) para identificar cuales se ven mal
local function step_frame(player, direction)
    local best, best_dist = nil, math.huge
    for _, object_name in ipairs({ "oShrine6", "oShrineEmpower" }) do
        local object_id = gm.constants[object_name]
        if object_id then
            for _, shrine in ipairs(Instance.find_all(object_id)) do
                local dx, dy = shrine.x - player.x, shrine.y - player.y
                local dist = dx * dx + dy * dy
                if dist < best_dist then best, best_dist = shrine, dist end
            end
        end
    end
    if not best then
        Util.chat("<r>[FRAMES]</c> No hay altares en el mapa.")
        return
    end

    local count = math.floor(gm.sprite_get_number(best.sprite_index))
    local index = (math.floor(best.image_index) + direction) % count
    best.image_speed = 0
    best.image_index = index
    Util.chat(string.format("<y>[FRAMES]</c> %s: fotograma %d de %d",
        tostring(gm.sprite_get_name(best.sprite_index)), index, count - 1))
end

-- ----------------------------------------------------------------------------
-- Tardigrado de prueba: se crea con el mismo ajuste que en una partida y el log
-- registra sus animaciones, el dano que recibe y el que hace.
-- ----------------------------------------------------------------------------
local watched = nil
local watch_timer = 0
local last_sprite = nil
local last_player_hp = nil
local last_hp = nil

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
        Util.chat("<r>[DEV F12]</c> oMacT no existe en este juego.")
        return
    end

    local inst = gm.instance_create(player.x + SPAWN_OFFSET_X, player.y, TARDIGRADE_OBJ)
    if not inst or not Instance.exists(inst) then
        Util.chat("<r>[DEV F12]</c> No se pudo crear la instancia.")
        return
    end

    Util.snap_to_ground(inst, 80, 40)

    local variant = nil
    if gm.keyboard_check(KEY.SHIFT) == 1.0 then
        variant = "boss"
    end
    Util.tune_enemy(inst, TARDIGRADE_OBJ, variant)

    watched, watch_timer = inst, 0
    last_sprite, last_player_hp, last_hp = nil, nil, nil

    log.info("[DevTools] Tardigrado creado" .. (variant and " (ALFA)" or "") .. ": " .. describe(inst))
    if variant then
        Util.chat("<g>[DEV F12]</c> Alfa creado. El log registra su comportamiento durante 25 s.")
    else
        Util.chat("<g>[DEV F12]</c> Tardigrado creado (Mayus+F12 = Alfa). El log lo registra 25 s.")
    end
end

local function update_monitor()
    if not watched then return end
    watch_timer = watch_timer + 1

    if not Instance.exists(watched) then
        log.info(string.format("[DevTools] Tardigrado: desaparecio tras %d frames", watch_timer))
        Util.chat("<y>[DEV F12]</c> Ya no existe (murio o se destruyo).")
        watched = nil
        return
    end

    local sprite = sprite_name(watched)
    local player = Instance.find_all(gm.constants.oP)[1]
    local distance = -1
    if player then
        distance = math.sqrt((player.x - watched.x) ^ 2 + (player.y - watched.y) ^ 2)
    end

    if sprite ~= last_sprite then
        log.info(string.format("[DevTools] Tardigrado t=%d: animacion %s -> %s (distancia al jugador %.0f px)",
            watch_timer, tostring(last_sprite), sprite, distance))
        last_sprite = sprite
    end

    if type(watched.hp) == "number" then
        if last_hp and watched.hp < last_hp then
            log.info(string.format("[DevTools] Tardigrado t=%d: recibe %.0f de dano (%.0f -> %.0f de %s)",
                watch_timer, last_hp - watched.hp, last_hp, watched.hp, read_field(watched, "maxhp")))
        end
        last_hp = watched.hp
    end

    if player and type(player.hp) == "number" then
        if last_player_hp and player.hp < last_player_hp then
            log.info(string.format("[DevTools] Tardigrado t=%d: el jugador pierde %.1f de vida (sprite %s, distancia %.0f px)",
                watch_timer, last_player_hp - player.hp, sprite, distance))
        end
        last_player_hp = player.hp
    end

    if watch_timer % MONITOR_INTERVAL == 0 then
        log.info(string.format("[DevTools] Tardigrado t=%d: %s", watch_timer, describe(watched)))
    end

    if watch_timer >= MONITOR_FRAMES then
        log.info("[DevTools] Tardigrado: fin de la observacion")
        watched = nil
    end
end

-- ----------------------------------------------------------------------------
-- Bucle de teclas
-- ----------------------------------------------------------------------------
Callback.add(Callback.TYPE.postStep, "DevTools_Loop", function()
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if not player or not player:exists() then return end

    local function guarded(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then Util.log_once("DevTools", err) end
    end

    if pressed(KEY.F5) then guarded(spawn_empower, player) end
    if pressed(KEY.F9) then guarded(spawn_challenge, player) end
    if pressed(KEY.F6) then guarded(toggle_god_mode, player) end
    if pressed(KEY.F7) then guarded(kill_all_enemies, player) end
    if pressed(KEY.F10) then guarded(step_frame, player, 1) end
    if pressed(KEY.F11) then guarded(step_frame, player, -1) end
    if pressed(KEY.F12) then guarded(spawn_tardigrade, player) end

    if pressed(KEY.F8) then
        if add_gold(GOLD_AMOUNT) then
            Util.play_sound(gm.constants.wCoin or gm.constants.wChest1, 1.0, 1.0, player.x, player.y)
            Util.chat("<y>[DEV F8]</c> +$" .. GOLD_AMOUNT)
        else
            Util.chat("<r>[DEV F8]</c> No se encontro el HUD; oro no anadido.")
        end
    end

    if god_mode then guarded(apply_god_mode, player) end
    guarded(update_monitor)
end)

log.info("[DevTools] debug_tools.lua cargado: F5 empoderamiento, F9 desafio, F6 dios, F7 matar, F8 oro, F10/F11 frames, F12 tardigrado")
