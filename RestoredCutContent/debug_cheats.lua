-- ============================================================================
-- debug_cheats.lua
-- Herramientas de prueba de RestoredCutContent
--   F5  Altar de Empoderamiento junto al jugador (a la derecha)
--   F9  Altar de Desafio junto al jugador (a la izquierda)
--   F6  Modo Dios (invulnerable, vida maxima, sin cooldowns)
--   F7  Matar a todos los enemigos (por la via normal de dano)
--   F8  +1000 de oro
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9 = 116, 117, 118, 119, 120
local GOLD_AMOUNT = 1000
local LETHAL_COEFFICIENT = 1000000

local god_mode = false

local function pressed(key)
    return gm.keyboard_check_pressed(key) == 1.0
end

local function spawn_empower_shrine(player)
    if not Util.spawn_empower_shrine then return end
    if Util.spawn_empower_shrine(player.x + 60, player.y) then
        Util.chat("<g>[DEBUG F5]</c> Altar de Empoderamiento creado. Pulsa E para probarlo.")
    end
end

local function spawn_challenge_shrine(player)
    if not Util.spawn_challenge_shrine then return end
    local shrine = Util.spawn_challenge_shrine(player.x - 60, player.y)
    if shrine then
        Util.chat("<g>[DEBUG F9]</c> Altar de Desafío creado ($" .. tostring(shrine.cost) .. "). F8 da oro; pulsa E para activarlo.")
    end
end

local function toggle_god_mode(player)
    god_mode = not god_mode
    if god_mode then
        Util.chat("<g>[MODO DIOS]</c> Activado: vida infinita y sin cooldowns.")
    else
        player.invincible = 0
        Util.chat("<r>[MODO DIOS]</c> Desactivado.")
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
    Util.chat("<y>[DEBUG F7]</c> Enemigos eliminados: " .. killed)
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

Callback.add(Callback.TYPE.postStep, "DebugCheats_Loop", function()
    if gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    local player = players[1]
    if not player or not player:exists() then return end

    if pressed(KEY_F5) then
        pcall(spawn_empower_shrine, player)
    end

    if pressed(KEY_F9) then
        pcall(spawn_challenge_shrine, player)
    end

    if pressed(KEY_F6) then
        toggle_god_mode(player)
    end

    if pressed(KEY_F7) then
        kill_all_enemies(player)
    end

    if pressed(KEY_F8) then
        if add_gold(GOLD_AMOUNT) then
            Util.play_sound(gm.constants.wCoin or gm.constants.wChest1, 1.0, 1.0, player.x, player.y)
            Util.chat("<y>[DEBUG F8]</c> +$" .. GOLD_AMOUNT)
        else
            Util.chat("<r>[DEBUG F8]</c> No se encontró el HUD; oro no añadido.")
        end
    end

    if god_mode then
        pcall(apply_god_mode, player)
    end
end)

log.info("[RestoredCutContent] debug_cheats.lua cargado (F5 empoderamiento, F9 desafio, F6 dios, F7 matar, F8 oro)")
