-- ============================================================================
-- shrine_empower.lua
-- Restaura oShrineEmpower (sprite sShrineEmpower): altar gratuito de un solo uso
-- que concede la bendicion "blessing_empower" y despues se quiebra.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local SHRINE_OBJ    = gm.constants.oShrineEmpower or 625
local SHRINE_SPRITE = gm.constants.sShrineEmpower

local BUFF_SECONDS   = 45
local GLOW_FRAMES    = 180   -- 3 s de resplandor antes de quebrarse
local SPARK_INTERVAL = 20
local AURA_INTERVAL  = 15

local STATE_IDLE, STATE_GLOWING, STATE_BREAKING, STATE_SPENT = "idle", "glowing", "breaking", "spent"

local shrine_spawned_this_stage = false
local shrine_data = {}   -- estado por id de instancia
local frame_counter = 0

-- ----------------------------------------------------------------------------
-- Buff: Bendicion de Empoderamiento
-- ----------------------------------------------------------------------------
local BONUS_DAMAGE   = 0.35
local BONUS_ATTACK   = 0.30
local BONUS_CRIT     = 20
local BONUS_SPEED    = 0.25
local PROC_CHANCE    = 0.25
local PROC_COEFF     = 0.50

local buff_empower = Buff.new("restored_cut_content", "blessing_empower")
buff_empower.max_stack = 1
buff_empower.is_timed  = true
buff_empower.show_icon = false

-- Buff.new devuelve el buff existente al recargar: limpiar para no duplicar callbacks
buff_empower:clear_callbacks()

buff_empower:add_callback("onPostStatRecalc", function(actor, stack)
    actor.damage          = actor.damage * (1 + BONUS_DAMAGE * stack)
    actor.attack_speed    = actor.attack_speed * (1 + BONUS_ATTACK * stack)
    actor.critical_chance = actor.critical_chance + BONUS_CRIT * stack
    actor.pHmax           = actor.pHmax * (1 + BONUS_SPEED * stack)
end)

-- Impacto sagrado: el golpe extra no puede volver a disparar el efecto
local firing_bonus_hit = false

buff_empower:add_callback("onAttackHit", function(actor, victim, stack, hit_info)
    if firing_bonus_hit then return end
    if gm.random(1.0) >= PROC_CHANCE then return end

    firing_bonus_hit = true
    pcall(function()
        if not victim:exists() then return end
        actor:fire_direct(victim, PROC_COEFF * stack, 0, nil, nil, gm.constants.sNone, false)
        if gm.constants.oEfCircle then
            gm.instance_create(victim.x, victim.y, gm.constants.oEfCircle)
        end
        Util.play_sound(gm.constants.wLevelUp, 0.5, 1.8, victim.x, victim.y)
    end)
    firing_bonus_hit = false
end)

-- ----------------------------------------------------------------------------
-- Datos y configuracion del altar
-- ----------------------------------------------------------------------------
local function get_data(shrine)
    local id = shrine.id
    if not shrine_data[id] then
        shrine_data[id] = { state = STATE_IDLE, glow_timer = 0 }
    end
    return shrine_data[id]
end

-- Frames del sprite: [0] reposo, [1..mid) halo pulsante, [mid..last] rotura
local function frame_layout(shrine)
    local count = 7
    pcall(function()
        count = math.floor(gm.sprite_get_number(shrine.sprite_index))
    end)
    local last = math.max(2, count - 1)
    return { glow_from = 1, break_from = math.floor(last / 2), last = last }
end

local function configure_shrine(shrine)
    shrine.active      = 0
    shrine.use_max     = 1
    shrine.cost        = 0
    shrine.cost_type   = 0
    shrine.visible     = true
    shrine.image_index = 0
    shrine.image_speed = 0
    if SHRINE_SPRITE then
        shrine.sprite_index = SHRINE_SPRITE
    end

    pcall(function()
        gm.interactable_init_cost(shrine.id, 0, 0)
    end)

    Util.snap_to_ground(shrine, 80, 40)
    get_data(shrine)
end

local function spawn_shrine_at(x, y)
    local shrine = gm.instance_create(x, y, SHRINE_OBJ)
    if not shrine or not Instance.exists(shrine) then
        log.error("[RestoredCutContent] No se pudo crear oShrineEmpower")
        return nil
    end
    configure_shrine(shrine)
    log.info(string.format("[RestoredCutContent] Altar de Empoderamiento creado en (%.1f, %.1f)", shrine.x, shrine.y))
    return shrine
end

-- Tecla de prueba F5: altar de empoderamiento a la derecha del jugador
local KEY_DEBUG_SPAWN = 116

Callback.add(Callback.TYPE.postStep, "EmpowerShrine_DebugSpawn", function()
    if gm.keyboard_check_pressed(KEY_DEBUG_SPAWN) ~= 1.0 then return end
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if not player then return end

    local ok, result = pcall(spawn_shrine_at, player.x + 60, player.y)
    if ok and result then
        Util.chat("<g>[DEBUG F5]</c> Altar de Empoderamiento creado. Pulsa E para probarlo.")
    else
        log.error("[RestoredCutContent] F5 fallo: " .. tostring(result))
    end
end)

-- ----------------------------------------------------------------------------
-- Generacion por fase
-- ----------------------------------------------------------------------------
Callback.add(Callback.TYPE.onStageStart, "EmpowerShrine_ResetStage", function()
    shrine_spawned_this_stage = false
    shrine_data = {}
end)

Callback.add(Callback.TYPE.postStep, "EmpowerShrine_SpawnLoop", function()
    if shrine_spawned_this_stage or gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    if #players == 0 then return end

    shrine_spawned_this_stage = true
    Util.spawn_shrine_naturally(SHRINE_OBJ, players[1], 450, configure_shrine)
end)

-- ----------------------------------------------------------------------------
-- Activacion, resplandor y rotura
-- ----------------------------------------------------------------------------
local function find_activator(shrine)
    local activator = nil
    pcall(function()
        if shrine.activator then
            local wrapped = Instance.wrap(shrine.activator)
            if wrapped:exists() then activator = wrapped end
        end
    end)
    return activator or Util.nearest_player(shrine.x, shrine.y)
end

local function start_blessing(shrine, data)
    data.state = STATE_GLOWING
    data.glow_timer = 0
    shrine.active = 2   -- bloquea nuevas interacciones

    local player = find_activator(shrine)
    if player and player:exists() then
        player:buff_apply(buff_empower, BUFF_SECONDS * 60)
        Util.play_sound(gm.constants.wLevelUp, 1.0, 1.1, shrine.x, shrine.y)
        if gm.constants.oEfCircle then
            gm.instance_create(shrine.x, shrine.y - 48, gm.constants.oEfCircle)
        end
        Util.chat("<y>[Altar de Empoderamiento]</c> ¡Bendición Sagrada! (+35% daño, +30% vel. ataque, +20% crítico, +25% movimiento durante 45 s)")
    end

    shrine.image_index = frame_layout(shrine).glow_from
    shrine.image_speed = 0.15
end

local function shatter(shrine, data, layout)
    data.state = STATE_BREAKING
    shrine.image_index = layout.break_from
    shrine.image_speed = 0.15

    Util.break_effects(shrine)
    Util.chat("<y>[Altar de Empoderamiento]</c> ¡El altar canaliza toda su energía y se quiebra!")
end

local function update_shrine(shrine)
    local data = get_data(shrine)
    local layout = frame_layout(shrine)

    if data.state == STATE_IDLE then
        if shrine.active == 1 or shrine.active == 2 then
            start_blessing(shrine, data)
        end

    elseif data.state == STATE_GLOWING then
        data.glow_timer = data.glow_timer + 1
        shrine.active = 2

        if shrine.image_index >= layout.break_from then
            shrine.image_index = layout.glow_from
        end

        if data.glow_timer % SPARK_INTERVAL == 0 and gm.constants.oEfSparks then
            gm.instance_create(shrine.x, shrine.y - 50, gm.constants.oEfSparks)
        end

        if data.glow_timer >= GLOW_FRAMES then
            shatter(shrine, data, layout)
        end

    elseif data.state == STATE_BREAKING then
        shrine.active = 3
        if shrine.image_index >= layout.last then
            shrine.image_index = layout.last
            shrine.image_speed = 0
            data.state = STATE_SPENT
        end

    else
        -- Ruinas inertes: impedir cualquier reinteraccion
        shrine.active = 3
        shrine.image_speed = 0
        shrine.image_index = layout.last
    end
end

-- Aura dorada sobre quien tenga la bendicion
local function update_aura(player)
    if frame_counter % AURA_INTERVAL ~= 0 then return end
    if player:buff_stack_count(buff_empower) <= 0 then return end
    if gm.constants.oEfSparks then
        gm.instance_create(player.x + gm.random_range(-8, 8), player.y - 12, gm.constants.oEfSparks)
    end
end

Callback.add(Callback.TYPE.postStep, "EmpowerShrine_Update", function()
    frame_counter = frame_counter + 1

    for _, shrine in ipairs(Instance.find_all(SHRINE_OBJ)) do
        pcall(update_shrine, shrine)
    end

    for _, player in ipairs(Instance.find_all(gm.constants.oP)) do
        pcall(update_aura, player)
    end
end)

log.info("[RestoredCutContent] shrine_empower.lua cargado")
