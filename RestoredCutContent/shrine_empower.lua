-- ============================================================================
-- shrine_empower.lua
-- Restaura oShrineEmpower (sprite sShrineEmpower): altar de un solo uso que pide
-- oro Y vida a la vez a cambio de la bendicion "blessing_empower"; despues se quiebra.
--
-- Fotogramas de sShrineEmpower (por geometria): 0 reposo, 1 despertar,
-- 2-4 halo creciente, 5-6 estatua agrietada/rota.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local SHRINE_OBJ    = gm.constants.oShrineEmpower or 625
local SHRINE_SPRITE = gm.constants.sShrineEmpower

-- Precio: ambos se pagan a la vez
local COST_BASE       = 25     -- oro con amenaza 0 (escala con la amenaza)
local COST_PER_THREAT = 0.5
local COST_REFRESH    = 30     -- frames entre recalculos mientras nadie lo activa
local LIFE_FRACTION   = 0.30   -- parte de la vida maxima que se ofrece (nunca letal)

local BUFF_SECONDS   = 45
local GLOW_FRAMES    = 180   -- 3 s de resplandor antes de quebrarse
local SPARK_INTERVAL = 20
local AURA_INTERVAL  = 15

local STATE_IDLE, STATE_GLOWING, STATE_BREAKING, STATE_SPENT = "idle", "glowing", "breaking", "spent"

local shrine_spawned_this_stage = false
local used_this_stage = false   -- la bendicion solo puede tomarse una vez por fase
local shrine_data = {}        -- estado por id de instancia
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

-- Reparto de fotogramas segun el numero real de frames del sprite
-- (7: 0 reposo, 1 despertar, 2-4 halo, 5-6 rotura)
local function frame_layout(shrine)
    local count = 7
    pcall(function()
        count = math.floor(gm.sprite_get_number(shrine.sprite_index))
    end)
    local last = math.max(3, count - 1)
    local halo_to = math.max(2, last - 2)
    return {
        rise = 1,
        halo_from = 2,
        halo_to = halo_to,
        crumble_from = halo_to,
        crumble_to = math.max(halo_to, last - 1),
        last = last,
    }
end

-- Oro que cuesta ahora y vida que se descontara al activarlo
local function current_gold_cost()
    return Util.gold_cost(COST_BASE, COST_PER_THREAT)
end

local function life_cost_for(player)
    local max_hp = player.maxhp
    local hp = player.hp
    if type(max_hp) ~= "number" or type(hp) ~= "number" then return 0 end
    -- Nunca mata: como minimo queda 1 de vida
    return math.max(0, math.min(math.floor(max_hp * LIFE_FRACTION), math.floor(hp) - 1))
end

local function configure_shrine(shrine)
    shrine.active      = 0
    shrine.use_max     = 1
    shrine.cost        = current_gold_cost()
    shrine.cost_type   = 0   -- oro (la vida se descuenta al activarlo)
    shrine.visible     = true
    shrine.image_index = 0
    shrine.image_speed = 0
    shrine.image_blend = Util.BLEND_NORMAL
    if SHRINE_SPRITE then
        shrine.sprite_index = SHRINE_SPRITE
    end

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
        get_data(result).debug = true   -- las pruebas no gastan el uso de la fase
        Util.chat("<g>[DEBUG F5]</c> Altar de Empoderamiento creado: $" .. tostring(result.cost) .. " + " .. math.floor(LIFE_FRACTION * 100) .. "% de vida. F8 da oro; pulsa E para probarlo.")
    else
        log.error("[RestoredCutContent] F5 fallo: " .. tostring(result))
    end
end)

-- ----------------------------------------------------------------------------
-- Generacion por fase
-- ----------------------------------------------------------------------------
-- Cada fase empieza con la bendicion disponible de nuevo
Callback.add(Callback.TYPE.onStageStart, "EmpowerShrine_ResetStage", function()
    shrine_spawned_this_stage = false
    used_this_stage = false
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
-- Activacion, resplandor y derrumbe
--   idle > glowing (3 s) > breaking (2,5 s) > spent
-- ----------------------------------------------------------------------------
local GLOW_HOLD      = 14    -- frames por fotograma del halo
local GLOW_PULSE     = 50    -- frames por latido del brillo
local CRUMBLE_FRAMES = 150
local CRUMBLE_SHAKE  = 3
local CRUMBLE_SPARKS = 18

local COLOR_WHITE = { 255, 255, 255 }
local COLOR_GOLD  = { 255, 205, 70 }
local COLOR_RUIN  = { 110, 110, 110 }

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

-- Altar ya gastado (o vetado por haberse usado en la fase): ruina inerte
local function make_inert(shrine, data)
    data.state = STATE_SPENT
    shrine.active = 3
    shrine.image_speed = 0
    shrine.image_index = frame_layout(shrine).last
    shrine.image_blend = Util.rgb(COLOR_RUIN[1], COLOR_RUIN[2], COLOR_RUIN[3])
end

local function start_blessing(shrine, data)
    data.state = STATE_GLOWING
    data.glow_timer = 0
    shrine.active = 2   -- bloquea nuevas interacciones
    if not data.debug then
        used_this_stage = true
    end

    local player = find_activator(shrine)
    if player and player:exists() then
        -- El oro ya lo cobro el motor; aqui se ofrece la vida
        local life = life_cost_for(player)
        if life > 0 then
            player.hp = player.hp - life
        end

        player:buff_apply(buff_empower, BUFF_SECONDS * 60)
        Util.play_sound(gm.constants.wLevelUp, 1.0, 1.1, shrine.x, shrine.y)
        if gm.constants.oEfCircle then
            gm.instance_create(shrine.x, shrine.y - 48, gm.constants.oEfCircle)
        end
        Util.chat("<y>[Altar de Empoderamiento]</c> Ofreciste oro y " .. life .. " de vida. ¡Bendición Sagrada! (+35% daño, +30% vel. ataque, +20% crítico, +25% movimiento durante 45 s)")
    end

    shrine.image_index = frame_layout(shrine).rise
    shrine.image_speed = 0
end

-- Halo: fotogramas del halo uno a uno, brillo dorado que late y crece, chispas que se aceleran
local function update_glowing(shrine, data, layout)
    data.glow_timer = data.glow_timer + 1
    shrine.active = 2

    local t = data.glow_timer
    local progress = math.min(1, t / GLOW_FRAMES)

    -- Despertar (1) y despues el halo 2..4 yendo y viniendo (2,3,4,3,2...)
    shrine.image_speed = 0
    if t < GLOW_HOLD then
        shrine.image_index = layout.rise
    else
        local span = layout.halo_to - layout.halo_from
        local step = math.floor((t - GLOW_HOLD) / GLOW_HOLD) % (span * 2)
        if step > span then step = span * 2 - step end
        shrine.image_index = layout.halo_from + step
    end

    local pulse = (math.sin(t * 2 * math.pi / GLOW_PULSE) + 1) / 2
    shrine.image_blend = Util.mix_blend(COLOR_WHITE, COLOR_GOLD, progress * (0.55 + 0.45 * pulse))

    local interval = math.max(6, math.floor(SPARK_INTERVAL * (1 - progress * 0.7)))
    if t % interval == 0 then
        Util.spark_at(shrine.x + gm.random_range(-10, 10), shrine.y - 50)
    end

    if t >= GLOW_FRAMES then
        data.state = STATE_BREAKING
        Util.play_sound(gm.constants.wChest1, 0.8, 0.7, shrine.x, shrine.y)
        Util.chat("<y>[Altar de Empoderamiento]</c> El altar no soporta tanta energía...")
    end
end

-- Derrumbe lento: temblor creciente, grietas cada vez mas seguidas y rotura final
local function update_breaking(shrine, data, layout)
    shrine.active = 3

    local progress = math.min(1, ((data.crumble_t or 0) + 1) / CRUMBLE_FRAMES)
    shrine.image_blend = Util.mix_blend(COLOR_GOLD, COLOR_RUIN, progress)

    local finished = Util.crumble_step(shrine, data, {
        duration = CRUMBLE_FRAMES,
        frame_from = layout.crumble_from,
        frame_to = layout.crumble_to,
        max_shake = CRUMBLE_SHAKE,
        spark_interval = CRUMBLE_SPARKS,
    })

    if finished then
        data.state = STATE_SPENT
        shrine.image_index = layout.last
        shrine.image_blend = Util.rgb(COLOR_RUIN[1], COLOR_RUIN[2], COLOR_RUIN[3])
        Util.break_effects(shrine)
        Util.chat("<y>[Altar de Empoderamiento]</c> ¡El altar se hace pedazos!")
    end
end

local function update_shrine(shrine)
    local data = get_data(shrine)
    local layout = frame_layout(shrine)

    if data.state == STATE_IDLE and used_this_stage and not data.debug then
        make_inert(shrine, data)
        return
    end

    if data.state == STATE_IDLE then
        -- El precio sube con el avance del mapa hasta que alguien lo paga
        data.cost_timer = (data.cost_timer or 0) + 1
        if data.cost_timer >= COST_REFRESH then
            data.cost_timer = 0
            shrine.cost = current_gold_cost()
        end

        if shrine.active == 1 or shrine.active == 2 then
            start_blessing(shrine, data)
        end

    elseif data.state == STATE_GLOWING then
        update_glowing(shrine, data, layout)

    elseif data.state == STATE_BREAKING then
        update_breaking(shrine, data, layout)

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
    Util.spark_at(player.x + gm.random_range(-8, 8), player.y - 12)
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
