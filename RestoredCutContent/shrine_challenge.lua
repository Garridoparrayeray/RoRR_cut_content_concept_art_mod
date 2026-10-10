-- ============================================================================
-- shrine_challenge.lua
-- Restaura oShrine6 (sprite sShrine6): altar de desafio de un solo uso que cuesta
-- oro y encarece con la amenaza.
-- Invoca una horda escalada por amenaza; al vencerla entrega un objeto.
--
-- Fotogramas de sShrine6:
--   0-4  carga de piedra        5-6  chispas azules
--   7    rayo vertical (SOLO al invocar)      8-10 disipacion
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local SHRINE_OBJ    = gm.constants.oShrine6 or 624
local SHRINE_SPRITE = gm.constants.sShrine6

-- Todos los fotogramas y tiempos de la animacion estan aqui para ajustarlos
-- sin tocar la logica. Los tiempos son frames (60 = 1 segundo).
local FRAME_CHARGE_LAST = 6     -- la carga recorre 0..6 de uno en uno
local FRAME_BEAM        = 7     -- rayo vertical: solo al invocar
local FRAME_COMBAT      = 6     -- fotograma fijo con chispas azules durante el combate
local FRAME_FADE_FROM   = 8     -- disipacion 8..9
local FRAME_FADE_LAST   = 9
local FRAME_DEAD        = 10    -- estatua apagada

local CHARGE_HOLD     = 14      -- frames que se mantiene cada fotograma de carga
local BEAM_HOLD       = 30      -- duracion del rayo
local FADE_HOLD       = 24      -- frames por fotograma de disipacion
local CRUMBLE_FRAMES  = 150     -- derrumbe final (2,5 s)
local CRUMBLE_SHAKE   = 2.5     -- temblor maximo en px
local CRUMBLE_SPARKS  = 22      -- intervalo inicial entre grietas

local BLEND_CHARGE_FROM = { 255, 255, 255 }
local BLEND_CHARGE_TO   = { 120, 190, 255 }
local BLEND_COMBAT_A    = { 190, 225, 255 }   -- pulso azul claro
local BLEND_COMBAT_B    = { 70, 140, 255 }    -- pulso azul intenso
local BLEND_RUIN        = Util.rgb(80, 80, 80)

local PULSE_PERIOD      = 70    -- frames por latido del tinte
local HEARTBEAT_FRAMES  = 120   -- aro de energia hacia el cielo cada 2 s
local SPARK_FRAMES      = 18

local COST_BASE        = 35   -- oro con amenaza 0
local COST_PER_THREAT  = 0.6   -- cada punto de amenaza suma el 60% del coste base
local COST_REFRESH     = 30    -- frames entre recalculos mientras nadie lo activa

local GRACE_FRAMES      = 60
local BLIGHTED_MIN_THREAT = 4.5
local BLIGHTED_MIN_STAGE  = 3
local BLIGHTED_CHANCE     = 0.35

local SND_CHARGE = gm.constants.wChainLightning or gm.constants.wShrine1
local SND_STRIKE = gm.constants.wLightning
local SND_WIN    = gm.constants.wLevelUp

local FLYING_NAMES = { "oWisp", "oWispB", "oJelly" }

-- Bestiario por fase (nombres de objeto; se resuelven contra gm.constants)
local POOL_NAMES = {
    [1] = { name = "Fase 1", light = { "oLizard", "oWisp" },          medium = { "oSpitter", "oLizard" }, heavy = { "oLizard" } },
    [2] = { name = "Fase 2", light = { "oLizard", "oWisp", "oJelly" }, medium = { "oClay", "oMush" },      heavy = { "oGolem" } },
    [3] = { name = "Fase 3", light = { "oLizard", "oClay" },          medium = { "oGolem", "oSpitter" }, heavy = { "oWispB", "oBison" } },
    [4] = { name = "Fase 4", light = { "oSpider", "oBug" },           medium = { "oImpM", "oGolem" },    heavy = { "oWispB", "oBison" } },
    [5] = { name = "Fase 5+", light = { "oChild", "oImpM" },          medium = { "oGuard", "oGolem" },   heavy = { "oGolemG", "oWispB" } },
}

local shrine_spawned_this_stage = false
local challenge_data = {}   -- estado por id de instancia

local function get_data(shrine)
    local id = shrine.id
    if not challenge_data[id] then
        challenge_data[id] = {
            phase = "idle",     -- idle > charging > beam > combat > fading > crumbling > ruin
            timer = 0,
            grace_timer = 0,
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
local function read_difficulty()
    local stages_passed, enemy_buff = 0, 1.0
    local director = gm._mod_game_getDirector()
    if not director or not Instance.exists(director) then
        director = Instance.find(gm.constants.oDirectorControl)
    end
    if director and Instance.exists(director) then
        if type(director.stages_passed) == "number" then
            stages_passed = math.floor(director.stages_passed)
        end
        if type(director.enemy_buff) == "number" then
            enemy_buff = math.max(1.0, director.enemy_buff)
        end
    end
    local stage_num = stages_passed + 1
    local threat = (enemy_buff * 0.75) + (stages_passed * 1.1)
    return stage_num, threat
end

-- Coste en oro: crece con la amenaza (fases superadas + tiempo de partida)
local function current_cost()
    local _, threat = read_difficulty()
    return math.floor(COST_BASE * (1 + threat * COST_PER_THREAT))
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
    Util.spawn_shrine_naturally(SHRINE_OBJ, players[1], 400, configure_shrine)
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
--   idle > charging > beam > combat > fading > crumbling > ruin
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

local function begin_beam(shrine, data)
    data.phase = "beam"
    data.timer = 0
    shrine.image_index = FRAME_BEAM
    shrine.image_speed = 0
    shrine.image_blend = Util.BLEND_NORMAL
    Util.play_sound(SND_STRIKE, 1.0, 1.0, shrine.x, shrine.y)
    pcall(function()
        shrine:screen_shake(4)
        if gm.constants.oEfCircle then
            gm.instance_create(shrine.x, shrine.y - 40, gm.constants.oEfCircle)
        end
    end)
    spawn_wave(shrine, data)
end

-- Carga: fotogramas 0..6 de uno en uno, el tinte vira a azul y las chispas se aceleran
local function update_charging(shrine, data)
    data.timer = data.timer + 1
    local total = CHARGE_HOLD * (FRAME_CHARGE_LAST + 1)
    local progress = math.min(1, data.timer / total)

    shrine.image_index = math.min(FRAME_CHARGE_LAST, math.floor(data.timer / CHARGE_HOLD))
    shrine.image_blend = Util.mix_blend(BLEND_CHARGE_FROM, BLEND_CHARGE_TO, progress)
    Util.shake(shrine, data, 0.8 * progress)

    local interval = math.max(5, math.floor(SPARK_FRAMES * 1.5 * (1 - progress)))
    if data.timer % interval == 0 then
        Util.spark_at(shrine.x + gm.random_range(-10, 10), shrine.y - gm.random_range(15, 55))
    end

    if data.timer >= total then
        Util.shake_end(shrine, data)
        begin_beam(shrine, data)
    end
end

-- Rayo: un unico fotograma congelado, sin tinte
local function update_beam(shrine, data)
    data.timer = data.timer + 1
    shrine.image_index = FRAME_BEAM
    shrine.image_speed = 0
    if data.timer >= BEAM_HOLD then
        data.phase = "combat"
        data.timer = 0
        data.grace_timer = 0
    end
end

local function victory(shrine, data)
    data.phase = "fading"
    data.timer = 0
    Util.play_sound(SND_WIN, 1.0, 1.0, shrine.x, shrine.y)
    Util.chat("<g>[Altar de Desafío]</c> ¡Horda derrotada! El altar entrega su poder...")
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
        end
    end

    if alive == 0 and data.initial_count > 0 then
        victory(shrine, data)
    end
end

-- Combate: fotograma fijo + latido de color + chispas + aro de energia periodico.
-- Mientras el altar late en azul, el desafio sigue en pie.
local function update_combat(shrine, data)
    data.timer = data.timer + 1

    shrine.image_index = FRAME_COMBAT
    shrine.image_speed = 0
    shrine.image_blend = Util.pulse_blend(data.timer, PULSE_PERIOD, BLEND_COMBAT_A, BLEND_COMBAT_B)

    if data.timer % SPARK_FRAMES == 0 then
        Util.spark_at(shrine.x + gm.random_range(-12, 12), shrine.y - gm.random_range(20, 60))
    end
    if data.timer % HEARTBEAT_FRAMES == 0 and gm.constants.oEfCircle then
        pcall(function()
            gm.instance_create(shrine.x, shrine.y - 40, gm.constants.oEfCircle)
        end)
    end

    track_enemies(shrine, data)
end

-- Disipacion: 8 y 9 con la misma duracion, el azul se apaga gradualmente
local function update_fading(shrine, data)
    data.timer = data.timer + 1
    local total = FADE_HOLD * (FRAME_FADE_LAST - FRAME_FADE_FROM + 1)
    local progress = math.min(1, data.timer / total)

    shrine.image_index = math.min(FRAME_FADE_LAST, FRAME_FADE_FROM + math.floor(data.timer / FADE_HOLD))
    shrine.image_speed = 0
    shrine.image_blend = Util.mix_blend(BLEND_COMBAT_B, BLEND_CHARGE_FROM, progress)

    if data.timer >= total then
        data.phase = "crumbling"
        data.timer = 0
    end
end

-- Derrumbe: temblor creciente, grietas cada vez mas seguidas y oscurecido gradual
local function update_crumbling(shrine, data)
    local progress = math.min(1, ((data.crumble_t or 0) + 1) / CRUMBLE_FRAMES)
    shrine.image_blend = Util.mix_blend(BLEND_CHARGE_FROM, BLEND_RUIN, progress)

    local finished = Util.crumble_step(shrine, data, {
        duration = CRUMBLE_FRAMES,
        frame_from = FRAME_FADE_LAST,
        frame_to = FRAME_DEAD,
        max_shake = CRUMBLE_SHAKE,
        spark_interval = CRUMBLE_SPARKS,
    })

    if finished then
        data.phase = "ruin"
        shrine.image_index = FRAME_DEAD
        shrine.image_blend = BLEND_RUIN
        Util.break_effects(shrine)
        Util.chat("<y>[Altar de Desafío]</c> El altar se quiebra tras entregar su poder.")
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
    elseif phase == "fading" then
        update_fading(shrine, data)
    elseif phase == "crumbling" then
        update_crumbling(shrine, data)
    else
        -- Ruina inerte
        shrine.active = 3
        shrine.image_speed = 0
        shrine.image_index = FRAME_DEAD
        shrine.image_blend = BLEND_RUIN
    end
end

Callback.add(Callback.TYPE.postStep, "ChallengeShrine_Update", function()
    for _, shrine in ipairs(Instance.find_all(SHRINE_OBJ)) do
        pcall(update_shrine, shrine)
    end
end)

log.info("[RestoredCutContent] shrine_challenge.lua cargado")
