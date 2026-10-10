-- ============================================================================
-- shrine_empower.lua
-- Restaura oShrineEmpower (sprite sShrineEmpower): altar que pide oro Y vida a la
-- vez a cambio de la bendicion "blessing_empower". Solo una vez por fase.
-- Tras bendecir se sobrecarga y estalla con su animacion nativa (sShrineEmpowerDeath).
--
-- Fotogramas de sShrineEmpower (por geometria): 0 reposo, 1 despertar, 2-4 halo
-- creciente. sShrineEmpowerDeath: 0-4 explosion creciente, 5 colapso, 6 escombros.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local SHRINE_OBJ          = gm.constants.oShrineEmpower or 625
local SHRINE_SPRITE       = gm.constants.sShrineEmpower
local SHRINE_DEATH_SPRITE = gm.constants.sShrineEmpowerDeath

-- Precio: ambos se pagan a la vez
local COST_BASE       = 25     -- oro con amenaza 0 (escala con la amenaza)
local COST_PER_THREAT = 0.5
local COST_REFRESH    = 30     -- frames entre recalculos mientras nadie lo activa
local LIFE_FRACTION   = 0.30   -- parte de la vida maxima que se ofrece (nunca letal)

-- Generacion por mapa: probabilidad de que salgan 0, 1 o 2 altares. Aunque salgan
-- varios, solo uno por mapa puede usarse: al tomar la bendicion, los demas se apagan.
local SPAWN_WEIGHTS      = { 0.15, 0.55, 0.30 }
local SPAWN_MIN_DISTANCE = 450    -- px minimos al jugador al generarse
local SPAWN_GAP          = 450    -- px minimos entre altares

local BUFF_SECONDS = 45
local AURA_INTERVAL = 15

-- Animacion (frames; 60 = 1 segundo)
local WAKE_FRAMES     = 18     -- el altar despierta (fotograma 1) con un golpe de escala
local GLOW_FRAMES     = 180    -- 3 s de halo antes de sobrecargarse
local CRUMBLE_FRAMES  = 120    -- sobrecarga previa al estallido
local CRUMBLE_SHAKE   = 3.5
local CRUMBLE_SPARKS  = 12

local DEATH_FRAMES   = 7
local DEATH_HOLDS    = { 4, 4, 4, 5, 6, 12, 1 }
local DEATH_BURST_AT = 1       -- estalla
local DEATH_AFTER_AT = 4       -- replica en el pico de la explosion
local DEBRIS_BURST   = 20
local DEBRIS_AFTER   = 8

local COLOR_WHITE = { 255, 255, 255 }
local COLOR_GOLD  = { 255, 205, 70 }
local COLOR_HOT   = { 255, 245, 200 }

local STATE_IDLE, STATE_WAKING, STATE_GLOWING, STATE_BREAKING, STATE_EXPLODING, STATE_SPENT =
    "idle", "waking", "glowing", "breaking", "exploding", "spent"

local shrine_spawned_this_stage = false
local used_this_stage = false   -- la bendicion solo puede tomarse una vez por fase
local shrine_data = {}          -- estado por id de instancia
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
        shrine_data[id] = { state = STATE_IDLE, timer = 0 }
    end
    return shrine_data[id]
end

-- Reparto de fotogramas segun el numero real de frames del sprite
-- (7: 0 reposo, 1 despertar, 2-4 halo)
local function frame_layout(shrine)
    local count = 7
    pcall(function()
        count = math.floor(gm.sprite_get_number(shrine.sprite_index))
    end)
    local last = math.max(3, count - 1)
    local halo_to = math.max(2, last - 2)
    return { rise = 1, halo_from = 2, halo_to = halo_to, last = last }
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
    local wanted = Util.roll_count(SPAWN_WEIGHTS)
    local made = Util.spawn_shrines(SHRINE_OBJ, wanted, players[1], SPAWN_MIN_DISTANCE, SPAWN_GAP, configure_shrine)
    log.info(string.format("[RestoredCutContent] Altares de empoderamiento en este mapa: %d (sorteados %d)", made, wanted))
end)

-- ----------------------------------------------------------------------------
-- Activacion, halo, sobrecarga y estallido
--   idle > waking > glowing > breaking > exploding > spent
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

-- Escombros inertes (ultimo fotograma de la muerte) o ruina si falta el sprite
local function make_inert(shrine, data)
    data.state = STATE_SPENT
    shrine.active = 3
    shrine.image_speed = 0
    if SHRINE_DEATH_SPRITE then
        shrine.sprite_index = SHRINE_DEATH_SPRITE
        shrine.image_index = DEATH_FRAMES - 1
    else
        shrine.image_index = frame_layout(shrine).last
    end
    shrine.image_blend = Util.BLEND_NORMAL
end

local function start_blessing(shrine, data)
    data.state = STATE_WAKING
    data.timer = 0
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

-- Despertar: golpe de escala que se asienta con un rebote amortiguado
local function update_waking(shrine, data, layout)
    data.timer = data.timer + 1
    shrine.active = 2
    shrine.image_speed = 0
    shrine.image_index = layout.rise

    local t = Util.clamp01(data.timer / WAKE_FRAMES)
    local kick = 1 - Util.ease_out(t)
    local bounce = math.sin(data.timer * 0.8) * 0.02 * kick
    Util.scale_to(shrine, data, 1 + 0.07 * kick + bounce, 1 + 0.07 * kick + bounce)
    shrine.image_blend = Util.mix_blend(COLOR_WHITE, COLOR_GOLD, Util.ease_out(t) * 0.35)
    Util.random_spark(shrine, 0.2, 12, 20, 90)

    if data.timer >= WAKE_FRAMES then
        Util.scale_reset(shrine, data)
        data.state = STATE_GLOWING
        data.timer = 0
    end
end

-- Halo: el fotograma sigue una onda (lento en los extremos, rapido en medio), la onda
-- se acelera con el tiempo, el brillo late y las chispas se hacen mas frecuentes.
local function update_glowing(shrine, data, layout)
    data.timer = data.timer + 1
    shrine.active = 2

    local t = data.timer
    local progress = Util.clamp01(t / GLOW_FRAMES)
    data.phase_acc = (data.phase_acc or 0) + (0.07 + 0.16 * progress)   -- radianes/frame, crece

    local span = layout.halo_to - layout.halo_from
    local wave = (math.sin(data.phase_acc - math.pi / 2) + 1) / 2
    shrine.image_speed = 0
    shrine.image_index = layout.halo_from + math.min(span, math.floor(wave * (span + 0.999)))

    local pulse = (math.sin(data.phase_acc * 0.8) + 1) / 2
    shrine.image_blend = Util.mix_blend(COLOR_WHITE, COLOR_GOLD, progress * (0.5 + 0.5 * pulse))

    local breath = 1 + 0.03 * progress * math.sin(data.phase_acc)
    Util.scale_to(shrine, data, breath, breath)
    Util.shake(shrine, data, 1.1 * Util.ease_in(progress))

    Util.random_spark(shrine, 0.03 + 0.25 * Util.ease_in(progress), 12, 20, 80)

    if t >= GLOW_FRAMES then
        Util.shake_end(shrine, data)
        Util.scale_reset(shrine, data)
        data.state = STATE_BREAKING
        data.crumble_t = nil
        Util.play_sound(gm.constants.wChest1, 0.8, 0.7, shrine.x, shrine.y)
        Util.chat("<y>[Altar de Empoderamiento]</c> El altar no soporta tanta energía...")
    end
end

-- Sobrecarga: el halo en su pico tiembla, se hincha, se vuelve blanco calido y, justo
-- antes de estallar, se contrae y se queda quieto un instante.
local function update_breaking(shrine, data, layout)
    shrine.active = 3

    local progress = Util.clamp01(((data.crumble_t or 0) + 1) / CRUMBLE_FRAMES)
    shrine.image_blend = Util.mix_blend(COLOR_GOLD, COLOR_HOT, Util.ease_in(progress))

    local finished = Util.crumble_step(shrine, data, {
        duration = CRUMBLE_FRAMES,
        frame_from = layout.halo_to,
        frame_to = layout.halo_to,
        max_shake = CRUMBLE_SHAKE,
        spark_interval = CRUMBLE_SPARKS,
        hold_frames = 10,
    })

    if finished then
        data.state = STATE_EXPLODING
        data.timer = 0
    end
end

-- Estallido: animacion nativa sShrineEmpowerDeath, con replica en el pico y el
-- resplandor enfriandose hasta dejar los escombros.
local function update_exploding(shrine, data, layout)
    shrine.active = 3

    if not SHRINE_DEATH_SPRITE then
        Util.break_effects(shrine)
        Util.debris_burst(shrine.x, shrine.y, DEBRIS_BURST)
        shrine.image_index = layout.last
        data.state = STATE_SPENT
        return
    end

    local total = 0
    for _, hold in ipairs(DEATH_HOLDS) do total = total + hold end

    local finished = Util.death_step(shrine, data, {
        sprite = SHRINE_DEATH_SPRITE,
        frames = DEATH_FRAMES,
        holds = DEATH_HOLDS,
        default_hold = 5,
        on_frame = function(frame)
            if frame == DEATH_BURST_AT then
                Util.break_effects(shrine)
                Util.debris_burst(shrine.x, shrine.y, DEBRIS_BURST)
                pcall(function() shrine:screen_shake(10) end)
            elseif frame == DEATH_AFTER_AT then
                Util.debris_burst(shrine.x, shrine.y, DEBRIS_AFTER)
                for _ = 1, 6 do
                    Util.spark_at(shrine.x + gm.random_range(-40, 40), shrine.y - gm.random_range(10, 110))
                end
                pcall(function() shrine:screen_shake(6) end)
            end
        end,
    })

    local cooling = Util.clamp01((data.death_t or 0) / total)
    shrine.image_blend = Util.mix_blend(COLOR_HOT, COLOR_WHITE, Util.ease_out(cooling))

    if finished then
        data.state = STATE_SPENT
        shrine.image_blend = Util.BLEND_NORMAL
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

    elseif data.state == STATE_WAKING then
        update_waking(shrine, data, layout)
    elseif data.state == STATE_GLOWING then
        update_glowing(shrine, data, layout)
    elseif data.state == STATE_BREAKING then
        update_breaking(shrine, data, layout)
    elseif data.state == STATE_EXPLODING then
        update_exploding(shrine, data, layout)
    else
        -- Escombros inertes: impedir cualquier reinteraccion
        shrine.active = 3
        shrine.image_speed = 0
        if SHRINE_DEATH_SPRITE then
            shrine.sprite_index = SHRINE_DEATH_SPRITE
            shrine.image_index = DEATH_FRAMES - 1
        end
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
