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

local FRAME_IMPACT   = 6.5   -- a partir de aqui cae el rayo y se invoca la horda
local FRAME_BEAM     = 7.0
local FRAME_LOOP_MIN = 5.0   -- solo fotogramas 5 y 6 (chispas azules): azul constante durante el combate
local FRAME_LOOP_MAX = 6.95
local FRAME_FADE     = 8.0
local FRAME_FADE_END = 9.8
local FRAME_DEAD     = 10

local RUIN_BLEND = 5263440   -- gris oscuro (0x505050) para las ruinas

local COST_BASE        = 35   -- oro con amenaza 0
local COST_PER_THREAT  = 0.6   -- cada punto de amenaza suma el 60% del coste base
local COST_REFRESH     = 30    -- frames entre recalculos mientras nadie lo activa

local BEAM_HOLD_FRAMES  = 24
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
            started = false,
            fight_active = false,
            completed = false,
            fading_out = false,
            beam_timer = 0,
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
-- ----------------------------------------------------------------------------
local function begin_charge(shrine, data)
    data.started = true
    shrine.active = 2   -- bloquea nuevas interacciones
    shrine.image_index = 0
    shrine.image_speed = 0.2
    Util.play_sound(SND_CHARGE, 0.9, 1.1, shrine.x, shrine.y)
    Util.chat("<y>[Altar de Desafío]</c> ¡El altar canaliza energía celestial...!")
end

local function begin_fight(shrine, data)
    data.fight_active = true
    data.beam_timer = 0
    data.grace_timer = 0

    -- Rayo vertical: un unico fotograma congelado, sin animacion
    shrine.image_index = FRAME_BEAM
    shrine.image_speed = 0
    Util.play_sound(SND_STRIKE, 1.0, 1.0, shrine.x, shrine.y)

    spawn_wave(shrine, data)
end

local function keep_sparking(shrine, data)
    if data.beam_timer < BEAM_HOLD_FRAMES then
        data.beam_timer = data.beam_timer + 1
        shrine.image_index = FRAME_BEAM
        shrine.image_speed = 0
        return
    end

    -- Despues del rayo: aura azul entre los fotogramas 5 y 6, nunca el 7 ni los anteriores
    shrine.image_speed = 0.08
    if shrine.image_index >= FRAME_LOOP_MAX or shrine.image_index < FRAME_LOOP_MIN then
        shrine.image_index = FRAME_LOOP_MIN
    end
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
        data.completed = true
        data.fight_active = false
        data.fading_out = true

        shrine.image_index = FRAME_FADE
        shrine.image_speed = 0.25

        Util.play_sound(SND_WIN, 1.0, 1.0, shrine.x, shrine.y)
        Util.chat("<g>[Altar de Desafío]</c> ¡Horda derrotada! El altar se apaga y entrega tu recompensa.")
        give_reward(shrine, data)
    end
end

local function update_shrine(shrine)
    local data = get_data(shrine)

    -- El precio sube con el avance del mapa hasta que alguien lo paga
    if not data.started and not data.completed then
        data.cost_timer = (data.cost_timer or 0) + 1
        if data.cost_timer >= COST_REFRESH then
            data.cost_timer = 0
            shrine.cost = current_cost()
        end
    end

    if not data.started and not data.completed and (shrine.active == 1 or shrine.active == 2) then
        begin_charge(shrine, data)
    end

    if data.started and not data.fight_active and not data.completed then
        if shrine.image_index >= FRAME_IMPACT then
            begin_fight(shrine, data)
        end
    end

    if data.fight_active then
        keep_sparking(shrine, data)
        track_enemies(shrine, data)
    end

    -- Fin de la disipacion: el altar se quiebra y queda como ruina oscurecida
    if data.fading_out and shrine.image_index >= FRAME_FADE_END then
        shrine.image_index = FRAME_DEAD
        shrine.image_speed = 0
        shrine.image_blend = RUIN_BLEND
        data.fading_out = false
        Util.break_effects(shrine)
        Util.chat("<y>[Altar de Desafío]</c> El altar se quiebra tras entregar su poder.")
    end

    if data.completed then
        shrine.active = 3   -- inerte permanentemente
    end
end

Callback.add(Callback.TYPE.postStep, "ChallengeShrine_Update", function()
    for _, shrine in ipairs(Instance.find_all(SHRINE_OBJ)) do
        pcall(update_shrine, shrine)
    end
end)

log.info("[RestoredCutContent] shrine_challenge.lua cargado")
