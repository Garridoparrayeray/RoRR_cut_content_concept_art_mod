-- ============================================================================
-- shrine_challenge.lua
-- Restaura oShrine6 (sprite sShrine6): altar de desafio de un solo uso que cuesta
-- oro y encarece con la amenaza.
-- Invoca una horda escalada por amenaza; al vencerla entrega un objeto y el altar
-- estalla con su animacion nativa de muerte (sShrine6Death), dejando escombros.
--
-- Fotogramas de sShrine6 (por geometria):
--   0-3  carga de piedra     4-5  chispas sobre la estatua (103 px, identicos)
--   6    pico de carga       7    rayo vertical     8-9 onda expansiva
--   10   estatua intacta
-- sShrine6Death: 0-1 estatua, 2-5 explosion creciente, 6 resto, 7 escombros.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local SHRINE_OBJ          = gm.constants.oShrine6 or 624
local SHRINE_SPRITE       = gm.constants.sShrine6
local SHRINE_DEATH_SPRITE = gm.constants.sShrine6Death

-- ----------------------------------------------------------------------------
-- Parametros de animacion (frames; 60 = 1 segundo). Todo se ajusta aqui.
-- ----------------------------------------------------------------------------
local FRAME_COMBAT_A = 4        -- chispas sobre la estatua (103 px de alto, igual que el 5)
local FRAME_COMBAT_B = 5
local FRAME_IDLE     = 10       -- estatua intacta (idem fotograma 0)

-- Carga: duracion de cada fotograma 0..6. Empieza lenta, se acelera y el pico (6) se
-- sostiene un poco mas, como una respiracion que se carga.
local CHARGE_HOLDS = { 24, 19, 15, 13, 12, 12, 18 }

-- Rayo completo: { fotograma, frames de duracion }
local BEAM_SEQUENCE = {
    { 7, 14 },   -- el rayo cae
    { 8, 9 },    -- onda expansiva (112 px de alto)
    { 9, 12 },   -- onda ancha que se disipa
}

-- Destruccion nativa: duracion de cada fotograma de sShrine6Death
local DEATH_FRAMES    = 8
local DEATH_HOLDS     = { 5, 5, 6, 6, 7, 10, 9, 1 }
local DEATH_BURST_AT  = 3       -- estalla: explosion grande + escombros
local DEATH_AFTER_AT  = 5       -- replica con el pico de la explosion
local DEBRIS_BURST    = 16
local DEBRIS_AFTER    = 7

local CRUMBLE_FRAMES  = 110     -- sobrecarga previa al estallido
local CRUMBLE_SHAKE   = 3.2     -- temblor maximo en px
local CRUMBLE_SPARKS  = 14      -- intervalo base entre chispas

local BLEND_WHITE     = { 255, 255, 255 }
local BLEND_CHARGE_TO = { 120, 190, 255 }
local BLEND_COMBAT_A  = { 190, 225, 255 }   -- pulso azul claro
local BLEND_COMBAT_B  = { 70, 140, 255 }    -- pulso azul intenso
local BLEND_HOT       = { 150, 200, 255 }   -- pulso cuando quedan pocos enemigos
local BLEND_OVERLOAD  = { 255, 245, 200 }   -- blanco calido justo antes de estallar

local PULSE_PERIOD_CALM = 74    -- frames por latido con la horda entera
local PULSE_PERIOD_HOT  = 30    -- frames por latido con pocos enemigos

-- Generacion por mapa: probabilidad de que salgan 0, 1, 2 o 3 altares.
-- Normalmente hay alguno, pero a veces el mapa no trae ninguno. No hay limite de usos:
-- cada uno se paga por separado con oro.
local SPAWN_WEIGHTS      = { 0.12, 0.43, 0.30, 0.15 }
local SPAWN_MIN_DISTANCE = 400    -- px minimos al jugador al generarse
local SPAWN_GAP          = 450    -- px minimos entre altares

local COST_BASE       = 35      -- oro con amenaza 0
local COST_PER_THREAT = 0.6     -- cada punto de amenaza suma el 60% del coste base
local COST_REFRESH    = 30      -- frames entre recalculos mientras nadie lo activa

local GRACE_FRAMES        = 60
local BLIGHTED_MIN_THREAT = 4.5
local BLIGHTED_MIN_STAGE  = 3
local BLIGHTED_CHANCE     = 0.35

local SND_CHARGE = gm.constants.wChainLightning or gm.constants.wShrine1
local SND_STRIKE = gm.constants.wLightning
local SND_WIN    = gm.constants.wLevelUp

local FLYING_NAMES = { "oWisp", "oWispB", "oJelly" }

-- Bestiario por fase (nombres de objeto; se resuelven contra gm.constants)
local POOL_NAMES = {
    [1] = { name = "Fase 1",  light = { "oLizard", "oWisp" },           medium = { "oSpitter", "oLizard" }, heavy = { "oLizard" } },
    [2] = { name = "Fase 2",  light = { "oLizard", "oWisp", "oJelly" }, medium = { "oClay", "oMush" },      heavy = { "oGolem" } },
    [3] = { name = "Fase 3",  light = { "oLizard", "oClay" },           medium = { "oGolem", "oSpitter" },  heavy = { "oWispB", "oBison" } },
    [4] = { name = "Fase 4",  light = { "oSpider", "oBug" },            medium = { "oImpM", "oGolem" },     heavy = { "oWispB", "oBison" } },
    [5] = { name = "Fase 5+", light = { "oChild", "oImpM" },            medium = { "oGuard", "oGolem" },    heavy = { "oGolemG", "oWispB" } },
}

local shrine_spawned_this_stage = false
local challenge_data = {}   -- estado por id de instancia

local function get_data(shrine)
    local id = shrine.id
    if not challenge_data[id] then
        challenge_data[id] = {
            phase = "idle",     -- idle > charging > beam > combat > crumbling > exploding > ruin
            timer = 0,
            grace_timer = 0,
            flip_left = 0,
            use_frame_b = false,
            mobs = {},
            alive_count = 0,
            initial_count = 0,
            threat = 1.0,
            stage_num = 1,
        }
    end
    return challenge_data[id]
end

local function get_pool(stage_num)
    local tier = math.min(math.max(stage_num, 1), 5)
    local names = POOL_NAMES[tier]
    return {
        name = names.name,
        tier = tier,
        light = Util.resolve_constants(names.light),
        medium = Util.resolve_constants(names.medium),
        heavy = Util.resolve_constants(names.heavy),
    }
end

local function is_flying(object_id)
    for _, name in ipairs(FLYING_NAMES) do
        if gm.constants[name] == object_id then return true end
    end
    return false
end

local function is_mob_alive(mob)
    if not mob or not Instance.exists(mob) then return false end
    if Util.is_true(mob.dead) then return false end
    if type(mob.hp) == "number" and mob.hp <= 0 then return false end
    return true
end

-- ----------------------------------------------------------------------------
-- Amenaza y coste
-- ----------------------------------------------------------------------------
local read_difficulty = Util.read_difficulty

local function current_cost()
    return Util.gold_cost(COST_BASE, COST_PER_THREAT)
end

-- ----------------------------------------------------------------------------
-- Configuracion y generacion del altar
-- ----------------------------------------------------------------------------
local function configure_shrine(shrine)
    shrine.cost        = current_cost()
    shrine.cost_type   = 0   -- oro
    shrine.active      = 0
    shrine.use_max     = 1
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
        log.error("[RestoredCutContent] No se pudo crear oShrine6")
        return nil
    end
    configure_shrine(shrine)
    return shrine
end

-- Tecla de prueba F9: altar de desafio a la izquierda del jugador
local KEY_DEBUG_SPAWN = 120

Callback.add(Callback.TYPE.postStep, "ChallengeShrine_DebugSpawn", function()
    if gm.keyboard_check_pressed(KEY_DEBUG_SPAWN) ~= 1.0 then return end
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if not player then return end

    local ok, result = pcall(spawn_shrine_at, player.x - 60, player.y)
    if ok and result then
        Util.chat("<g>[DEBUG F9]</c> Altar de Desafío creado ($" .. tostring(result.cost) .. "). Pulsa E para activarlo.")
        log.info(string.format("[RestoredCutContent] F9: altar de desafio en (%.1f, %.1f), coste %s", result.x, result.y, tostring(result.cost)))
    else
        log.error("[RestoredCutContent] F9 fallo: " .. tostring(result))
    end
end)

Callback.add(Callback.TYPE.onStageStart, "ChallengeShrine_ResetStage", function()
    shrine_spawned_this_stage = false
    challenge_data = {}
end)

Callback.add(Callback.TYPE.postStep, "ChallengeShrine_SpawnLoop", function()
    if shrine_spawned_this_stage or gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    if #players == 0 then return end

    shrine_spawned_this_stage = true
    local wanted = Util.roll_count(SPAWN_WEIGHTS)
    local made = Util.spawn_shrines(SHRINE_OBJ, wanted, players[1], SPAWN_MIN_DISTANCE, SPAWN_GAP, configure_shrine)
    log.info(string.format("[RestoredCutContent] Altares de desafio en este mapa: %d (sorteados %d)", made, wanted))
end)

-- ----------------------------------------------------------------------------
-- Diseno de la oleada
-- ----------------------------------------------------------------------------
local function clamp_count(base, minimum, maximum)
    return math.min(maximum, math.max(minimum, math.floor(base)))
end

-- Devuelve titulo y lista { {obj=, is_elite=}, ... }
local function plan_wave(pool, threat)
    local tier = pool.tier

    local archetypes = { "swarm", "assault" }
    if tier >= 2 and threat >= 2.5 then table.insert(archetypes, "brute") end
    if tier >= 3 and threat >= 3.0 then table.insert(archetypes, "elite") end
    local archetype = archetypes[gm.irandom_range(1, #archetypes)]

    local fallback = gm.constants.oLizard
    local plan = {}
    local title

    local function add(object_id, is_elite)
        table.insert(plan, { obj = object_id, is_elite = is_elite })
    end

    if archetype == "swarm" then
        title = "¡Un Enjambre se ha manifestado!"
        local count, elite_chance
        if tier == 1 then
            count = clamp_count(3 + threat * 0.5, 3, 5)
            elite_chance = 0.08
        else
            count = clamp_count(3 + threat * 0.9, 4, 8)
            elite_chance = math.min(0.30, 0.05 + threat * 0.05)
        end
        local light_count = math.floor(count * 0.8)
        for i = 1, count do
            local list = (i <= light_count) and pool.light or pool.medium
            add(Util.pick(list, fallback), gm.random(1.0) < elite_chance)
        end

    elseif archetype == "assault" then
        title = "¡Un Escuadrón de Asalto te rodea!"
        local count, elite_chance
        if tier == 1 then
            count = clamp_count(2 + threat * 0.5, 3, 4)
            elite_chance = 0.10
        else
            count = clamp_count(3 + threat * 0.8, 3, 6)
            elite_chance = math.min(0.40, 0.10 + threat * 0.07)
        end
        for i = 1, count do
            local list = (i % 2 == 1) and pool.light or pool.medium
            add(Util.pick(list, fallback), gm.random(1.0) < elite_chance)
        end

    elseif archetype == "brute" then
        title = "¡Una Guardia Pesada responde al desafío!"
        local count = clamp_count(2 + threat * 0.5, 2, 4)
        local elite_chance = math.min(0.50, 0.20 + threat * 0.08)
        for i = 1, count do
            local list = (i == 1) and pool.heavy or pool.medium
            add(Util.pick(list, fallback), gm.random(1.0) < elite_chance)
        end

    else
        title = "¡Una Patrulla de Élite te acecha!"
        local count = clamp_count(2 + threat * 0.4, 2, 3)
        for i = 1, count do
            local list = (i == 1) and pool.heavy or pool.medium
            add(Util.pick(list, fallback), true)
        end
    end

    return title, plan
end

-- Elite elemental seguro; Blighted solo con amenaza y fase altas, 1 por oleada
local function choose_elite(allow_blighted, blighted_used)
    if allow_blighted and not blighted_used and gm.random(1.0) < BLIGHTED_CHANCE then
        return Util.elite_id("blighted", 6), true
    end

    local safe = {}
    for _, name in ipairs({ "blazing", "frenzied", "leeching", "overloading", "volatile" }) do
        local id = Util.elite_id(name, nil)
        if id then table.insert(safe, id) end
    end
    if #safe == 0 then safe = { 1, 2, 4 } end
    return safe[gm.irandom_range(1, #safe)], false
end

local function spawn_wave(shrine, data)
    local stage_num, threat = read_difficulty()
    local pool = get_pool(stage_num)
    local title, plan = plan_wave(pool, threat)

    local allow_blighted = threat >= BLIGHTED_MIN_THREAT and stage_num >= BLIGHTED_MIN_STAGE
    local blighted_used = false

    Util.chat("<y>[Altar de Desafío]</c> " .. title .. " (" .. #plan .. " enemigos | " .. pool.name .. ")")

    data.mobs = {}
    local ground_y = shrine.y

    for i, entry in ipairs(plan) do
        local side = (i % 2 == 0) and 1 or -1
        local distance = math.min(100, 54 + math.floor((i - 1) / 2) * 16)
        local x = shrine.x + side * distance
        local mob

        if is_flying(entry.obj) then
            mob = gm.instance_create(x, ground_y - 75 - i * 8, entry.obj)
        else
            mob = gm.instance_create(x, ground_y, entry.obj)
            if mob and Instance.exists(mob) then
                -- Empujar hacia el altar si ha nacido dentro de una pared
                local pushed = 0
                while pushed < 40 and Util.is_true(mob:place_meeting(mob.x, mob.y, gm.constants.oB)) do
                    mob.x = mob.x - side * 2
                    pushed = pushed + 2
                end
                Util.snap_to_ground(mob, 80, 40)
            end
        end

        if mob and Instance.exists(mob) then
            if entry.is_elite then
                local elite_id, is_blighted = choose_elite(allow_blighted, blighted_used)
                if is_blighted then
                    blighted_used = true
                    Util.chat("<r>[Altar de Desafío]</c> ¡Una Aberración Umbría (élite Sombra) acecha en el desafío!")
                end
                pcall(function()
                    gm.elite_set(mob, elite_id)
                end)
            end
            table.insert(data.mobs, mob)
        end
    end

    data.alive_count = #data.mobs
    data.initial_count = #data.mobs
    data.threat = threat
    data.stage_num = stage_num
    log.info(string.format("[RestoredCutContent] Horda: %d enemigos (%s, amenaza %.2f)", #data.mobs, pool.name, threat))
end

-- ----------------------------------------------------------------------------
-- Recompensa
-- ----------------------------------------------------------------------------
local function pick_reward_tier(threat, stage_num)
    if threat < 2.2 and stage_num == 1 then
        return Item.TIER.common
    elseif threat < 4.2 then
        if gm.irandom_range(1, 2) == 1 then return Item.TIER.uncommon end
        return Item.TIER.common
    elseif threat < 6.8 then
        return Item.TIER.uncommon
    end
    if gm.irandom_range(1, 3) == 1 then return Item.TIER.rare end
    return Item.TIER.uncommon
end

local function give_reward(shrine, data)
    local item = Item.get_random(pick_reward_tier(data.threat, data.stage_num))
    if item then
        item:create(shrine.x, shrine.y - 32)
    else
        gm.instance_create(shrine.x, shrine.y - 16, gm.constants.oChest1)
    end
end

-- ----------------------------------------------------------------------------
-- Maquina de estados del altar
--   idle > charging > beam > combat > crumbling > exploding > ruin
-- ----------------------------------------------------------------------------
local function begin_charge(shrine, data)
    data.phase = "charging"
    data.timer = 0
    shrine.active = 2   -- bloquea nuevas interacciones
    shrine.image_index = 0
    shrine.image_speed = 0
    Util.play_sound(SND_CHARGE, 0.9, 1.1, shrine.x, shrine.y)
    Util.chat("<y>[Altar de Desafío]</c> ¡El altar canaliza energía celestial...!")
end

local function charge_total()
    local total = 0
    for _, hold in ipairs(CHARGE_HOLDS) do total = total + hold end
    return total
end

local function begin_beam(shrine, data)
    data.phase = "beam"
    data.timer = 0
    Util.shake_end(shrine, data)
    shrine.image_blend = Util.BLEND_NORMAL
    Util.play_sound(SND_STRIKE, 1.0, 1.0, shrine.x, shrine.y)
    pcall(function()
        shrine:screen_shake(5)
        if gm.constants.oEfCircle then
            gm.instance_create(shrine.x, shrine.y - 40, gm.constants.oEfCircle)
        end
    end)
    for _ = 1, 6 do
        Util.spark_at(shrine.x + gm.random_range(-14, 14), shrine.y - gm.random_range(10, 90))
    end
    spawn_wave(shrine, data)
end

-- Carga: cada fotograma dura menos que el anterior (se acelera), el tinte vira a azul,
-- la estatua respira mas hondo, y en el pico se encoge un instante antes del rayo.
local function update_charging(shrine, data)
    data.timer = data.timer + 1
    local total = charge_total()
    local progress = Util.clamp01(data.timer / total)

    local remaining, frame = data.timer, #CHARGE_HOLDS - 1
    for i, hold in ipairs(CHARGE_HOLDS) do
        if remaining <= hold then
            frame = i - 1
            break
        end
        remaining = remaining - hold
    end
    shrine.image_index = frame
    shrine.image_speed = 0
    shrine.image_blend = Util.mix_blend(BLEND_WHITE, BLEND_CHARGE_TO, Util.ease_in_out(progress))

    local frames_left = total - data.timer
    if frames_left < 8 then
        -- Anticipacion: se contrae justo antes de soltar el rayo
        Util.shake_end(shrine, data)
        Util.scale_to(shrine, data, 0.97, 0.95)
    else
        Util.shake(shrine, data, 1.3 * Util.ease_in(progress))
        local breath = 1 + 0.035 * progress * math.sin(data.timer * (0.22 + 0.35 * progress))
        Util.scale_to(shrine, data, breath, breath)
    end

    Util.random_spark(shrine, 0.02 + 0.30 * Util.ease_in(progress), 12, 12, 62)

    if data.timer >= total then
        Util.scale_reset(shrine, data)
        begin_beam(shrine, data)
    end
end

local function beam_total()
    local total = 0
    for _, step in ipairs(BEAM_SEQUENCE) do total = total + step[2] end
    return total
end

-- Rayo completo: cae (7) y se expande en onda (8, 9). El golpe estira la estatua
-- hacia arriba y el rebote se amortigua hasta asentarse (squash & stretch).
local function update_beam(shrine, data)
    data.timer = data.timer + 1
    shrine.image_speed = 0

    local total = beam_total()
    local kick = 1 - Util.ease_out(Util.clamp01(data.timer / total))   -- 1 -> 0
    local wobble = math.sin(data.timer * 0.9) * 0.02 * kick
    Util.scale_to(shrine, data, 1 - 0.05 * kick + wobble, 1 + 0.10 * kick - wobble)
    Util.shake(shrine, data, 3.5 * kick)

    local remaining = data.timer
    for _, step in ipairs(BEAM_SEQUENCE) do
        if remaining <= step[2] then
            shrine.image_index = step[1]
            -- Blanco puro al caer el rayo, azul claro al disiparse
            shrine.image_blend = Util.mix_blend(BLEND_WHITE, BLEND_COMBAT_A, Util.ease_out(remaining / step[2]))
            return
        end
        remaining = remaining - step[2]
    end

    Util.shake_end(shrine, data)
    Util.scale_reset(shrine, data)
    data.phase = "combat"
    data.timer = 0
    data.grace_timer = 0
    data.flip_left = 0
end

local function victory(shrine, data)
    data.phase = "crumbling"
    data.timer = 0
    data.crumble_t = nil
    Util.play_sound(SND_WIN, 1.0, 1.0, shrine.x, shrine.y)
    Util.chat("<g>[Altar de Desafío]</c> ¡Horda derrotada! El altar se sobrecarga...")
    give_reward(shrine, data)
end

local function track_enemies(shrine, data)
    data.grace_timer = data.grace_timer + 1
    if data.grace_timer < GRACE_FRAMES then return end

    local alive_mobs = {}
    for _, mob in ipairs(data.mobs) do
        if is_mob_alive(mob) then table.insert(alive_mobs, mob) end
    end
    data.mobs = alive_mobs

    local alive = #alive_mobs
    if alive ~= data.alive_count then
        data.alive_count = alive
        if alive > 0 then
            Util.chat("<y>[Altar de Desafío]</c> Enemigos restantes: " .. alive)
            -- Cada baja le arranca un destello al altar
            Util.spark_at(shrine.x, shrine.y - 40)
            pcall(function()
                gm.instance_create(shrine.x, shrine.y - 40, gm.constants.oEfCircle)
            end)
        end
    end

    if alive == 0 and data.initial_count > 0 then
        victory(shrine, data)
    end
end

-- Combate: el altar responde a la horda. Con la horda entera late despacio y tranquilo;
-- al quedar pocos enemigos late mas rapido, mas brillante y suelta mas chispas.
local function update_combat(shrine, data)
    data.timer = data.timer + 1

    local intensity = 0
    if data.initial_count > 0 then
        intensity = 1 - (data.alive_count / data.initial_count)
    end
    local period = PULSE_PERIOD_CALM + (PULSE_PERIOD_HOT - PULSE_PERIOD_CALM) * intensity

    -- 4 y 5 alternan con duraciones irregulares (no un parpadeo metronomico)
    data.flip_left = data.flip_left - 1
    if data.flip_left <= 0 then
        data.use_frame_b = not data.use_frame_b
        data.flip_left = gm.irandom_range(6, 14)
    end
    if data.use_frame_b then
        shrine.image_index = FRAME_COMBAT_B
    else
        shrine.image_index = FRAME_COMBAT_A
    end
    shrine.image_speed = 0

    local bright = Util.mix_blend(BLEND_COMBAT_B, BLEND_HOT, intensity)
    shrine.image_blend = Util.pulse_blend(data.timer, period, BLEND_COMBAT_A, bright)

    -- Respiracion sincronizada con el latido
    local breath = 1 + 0.014 * math.sin(data.timer * 2 * math.pi / period)
    Util.scale_to(shrine, data, breath, breath)

    Util.random_spark(shrine, 0.04 + 0.12 * intensity, 14, 20, 66)
    if data.timer % math.floor(period * 1.8) == 0 and gm.constants.oEfCircle then
        pcall(function()
            gm.instance_create(shrine.x, shrine.y - 40, gm.constants.oEfCircle)
        end)
    end

    track_enemies(shrine, data)
end

-- Sobrecarga: tiembla cada vez mas, se hincha, se pone al blanco calido y, en los
-- ultimos instantes, se contrae y se queda quieta antes de estallar.
local function update_crumbling(shrine, data)
    local progress = Util.clamp01(((data.crumble_t or 0) + 1) / CRUMBLE_FRAMES)
    shrine.image_blend = Util.mix_blend(BLEND_COMBAT_B, BLEND_OVERLOAD, Util.ease_in(progress))

    local finished = Util.crumble_step(shrine, data, {
        duration = CRUMBLE_FRAMES,
        frame_from = FRAME_IDLE,
        frame_to = FRAME_IDLE,
        max_shake = CRUMBLE_SHAKE,
        spark_interval = CRUMBLE_SPARKS,
        hold_frames = 10,
    })

    if finished then
        data.phase = "exploding"
        data.timer = 0
    end
end

-- Estallido: animacion nativa sShrine6Death. El estallido principal, una replica con el
-- pico de la explosion y el resplandor que se enfria hasta dejar los escombros.
local function update_exploding(shrine, data)
    if not SHRINE_DEATH_SPRITE then
        Util.break_effects(shrine)
        Util.debris_burst(shrine.x, shrine.y, DEBRIS_BURST)
        data.phase = "ruin"
        pcall(function() shrine:destroy() end)
        return
    end

    local total = 0
    for _, hold in ipairs(DEATH_HOLDS) do total = total + hold end

    local finished = Util.death_step(shrine, data, {
        sprite = SHRINE_DEATH_SPRITE,
        frames = DEATH_FRAMES,
        holds = DEATH_HOLDS,
        default_hold = 6,
        on_frame = function(frame)
            if frame == DEATH_BURST_AT then
                Util.break_effects(shrine)
                Util.debris_burst(shrine.x, shrine.y, DEBRIS_BURST)
                pcall(function() shrine:screen_shake(9) end)
            elseif frame == DEATH_AFTER_AT then
                Util.debris_burst(shrine.x, shrine.y, DEBRIS_AFTER)
                for _ = 1, 5 do
                    Util.spark_at(shrine.x + gm.random_range(-30, 30), shrine.y - gm.random_range(10, 90))
                end
                pcall(function() shrine:screen_shake(5) end)
            end
        end,
    })

    -- El resplandor del estallido se enfria mientras avanza la animacion
    local cooling = Util.clamp01((data.death_t or 0) / total)
    shrine.image_blend = Util.mix_blend(BLEND_OVERLOAD, BLEND_WHITE, Util.ease_out(cooling))

    if finished then
        data.phase = "ruin"
        shrine.image_blend = Util.BLEND_NORMAL
        Util.chat("<y>[Altar de Desafío]</c> El altar estalla en pedazos.")
    end
end

local function update_shrine(shrine)
    local data = get_data(shrine)
    local phase = data.phase

    if phase == "idle" then
        -- El precio sube con el avance del mapa hasta que alguien lo paga
        data.cost_timer = (data.cost_timer or 0) + 1
        if data.cost_timer >= COST_REFRESH then
            data.cost_timer = 0
            shrine.cost = current_cost()
        end
        if shrine.active == 1 or shrine.active == 2 then
            begin_charge(shrine, data)
        end

    elseif phase == "charging" then
        update_charging(shrine, data)
    elseif phase == "beam" then
        update_beam(shrine, data)
    elseif phase == "combat" then
        update_combat(shrine, data)
    elseif phase == "crumbling" then
        update_crumbling(shrine, data)
    elseif phase == "exploding" then
        update_exploding(shrine, data)
    else
        -- Escombros inertes: ultimo fotograma de la animacion de muerte
        shrine.active = 3
        shrine.image_speed = 0
        if SHRINE_DEATH_SPRITE then
            shrine.sprite_index = SHRINE_DEATH_SPRITE
            shrine.image_index = DEATH_FRAMES - 1
            shrine.image_blend = Util.BLEND_NORMAL
        end
    end
end

Callback.add(Callback.TYPE.postStep, "ChallengeShrine_Update", function()
    for _, shrine in ipairs(Instance.find_all(SHRINE_OBJ)) do
        pcall(update_shrine, shrine)
    end
end)

log.info("[RestoredCutContent] shrine_challenge.lua cargado")
