-- ============================================================================
-- monkey.lua
-- Restaura el enemigo descartado: Mono Espacial (Space Lemur / Monkey)
-- Enemigo rapido y acrobatico que persigue al jugador y realiza un ataque
-- especial rodando en forma de rueda a gran velocidad.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSETS = path.combine(PATH, "assets/monsters/monkey")

-- Sprites y animaciones sincronizadas al milimetro:
-- Todas con dimensiones 44x36 y origen unificado (22, 32)
-- Contacto con suelo estrictamente alineado en Y = 32
local sprite_idle  = Sprite.new("MonkeyIdle",  path.combine(ASSETS, "idle.png"),  1, 22, 32)
local sprite_walk  = Sprite.new("MonkeyWalk",  path.combine(ASSETS, "walk.png"),  6, 22, 32)
local sprite_wheel = Sprite.new("MonkeyWheel", path.combine(ASSETS, "wheel.png"), 14, 22, 32)
local sprite_fall  = Sprite.new("MonkeyFall",  path.combine(ASSETS, "fall.png"),  7, 22, 32)
local sprite_die   = Sprite.new("MonkeyDie",   path.combine(ASSETS, "die.png"),   11, 22, 32)

-- Parametros de combate (Nerfeados y equilibrados)
local WHEEL_TRIGGER_DIST = 140   -- distancia en px para iniciar el ataque rueda
local WHEEL_SPEED        = 3.8   -- velocidad horizontal de rodamiento (esquivable saltando)
local WHEEL_DURATION     = 42    -- duracion de la embestida (0.7s)
local TIRED_DURATION     = 90    -- 1.5s de descanso vulnerable tras rodar
local WHEEL_COOLDOWN     = 480   -- 8 segundos entre ataques de rueda

-- Estados
local STATE_WALK  = "walk"
local STATE_WHEEL = "wheel"
local STATE_TIRED = "tired"
local STATE_DEAD  = "dead"

-- Definicion del Objeto en ReturnsAPI
local obj_monkey = Object.new("Monkey", Object.Parent.ENEMY_CLASSIC)
obj_monkey:set_sprite(sprite_idle)
obj_monkey:set_depth(11)

local monkey_data = {}

-- Calibracion inicial al nacer (Estadisticas nerfeadas)
Callback.add(obj_monkey.on_create, function(actor)
    actor.sprite_idle  = sprite_idle
    actor.sprite_walk  = sprite_walk
    actor.sprite_jump  = sprite_fall
    actor.sprite_fall  = sprite_fall
    actor.sprite_death = sprite_die

    actor.sound_spawn = gm.constants.wLizardSpawn or gm.constants.wSpawn
    actor.sound_hit   = gm.constants.wLizardHit or gm.constants.wHit
    actor.sound_death = gm.constants.wLizardDeath or gm.constants.wDeath

    actor:enemy_stats_init(7, 60, 20, 8)
    actor.pHmax_base = 2.2       -- Velocidad a pie moderada (2.2)
    actor.pHmax      = 2.2
    actor.can_jump   = true

    actor.image_xscale = 1.0
    actor.image_yscale = 1.0

    monkey_data[actor.id] = {
        state = STATE_WALK,
        state_t = 0,
        wheel_cd = 120, -- 2s de preparacion antes de su primer rodamiento
        hit_cooldown = {}
    }

    actor:init_actor_late()
    Util.snap_to_ground(actor, 80, 40)
end)

-- Comportamiento y maquina de estados paso a paso
Callback.add(obj_monkey.on_step, function(actor)
    local data = monkey_data[actor.id]
    if not data then return end

    if actor.hp <= 0 then
        if data.state ~= STATE_DEAD then
            data.state = STATE_DEAD
            actor.sprite_index = sprite_die
            actor.image_index = 0
            actor.image_speed = 0.25
            Util.play_sound(gm.constants.wLizardDeath or gm.constants.wDeath, 0.8, 1.4, actor.x, actor.y)
        end
        data.death_t = (data.death_t or 0) + 1
        if data.death_t >= 35 then
            pcall(function() actor:destroy() end)
        end
        return
    end

    data.state_t = data.state_t + 1
    if data.wheel_cd > 0 then data.wheel_cd = data.wheel_cd - 1 end

    local player = Search.nearest_player(actor.x, actor.y)
    local dir_to_player = (actor.image_xscale >= 0) and 1 or -1
    local dist_x = 999
    local dist_y = 999

    if player and Instance.exists(player) then
        dir_to_player = (player.x >= actor.x) and 1 or -1
        dist_x = math.abs(player.x - actor.x)
        dist_y = math.abs(player.y - actor.y)
    end

    -- ------------------------------------------------------------------------
    -- Estado: ANDAR / PERSEGUIR (Fisica y animaciones nativas de RoRR)
    -- ------------------------------------------------------------------------
    if data.state == STATE_WALK then
        -- Permitir que GameMaker gestione la sincronizacion natural de andar/quieto/caer
        if actor.free then
            actor:actor_animation_set(sprite_fall, 0.20)
        elseif math.abs(actor.pHspeed or 0) > 0.2 then
            actor:actor_animation_set(sprite_walk, 0.25)
        else
            actor:actor_animation_set(sprite_idle, 0.15)
        end

        -- Iniciar embestida en rueda cuando el jugador este alineado
        if data.wheel_cd <= 0 and dist_x < WHEEL_TRIGGER_DIST and dist_y < 50 and not actor.free then
            data.state = STATE_WHEEL
            data.state_t = 0
            data.wheel_dir = dir_to_player
            actor:actor_animation_set(sprite_wheel, 0.35)
            actor.image_index = 0
            actor.image_xscale = data.wheel_dir
            Util.play_sound(gm.constants.wRoll or gm.constants.wSpawn, 0.85, 1.3, actor.x, actor.y)
        end

    -- ------------------------------------------------------------------------
    -- Estado: RUEDA / EMBESTIDA RODANTE (Fisica segura mediante pHspeed)
    -- ------------------------------------------------------------------------
    elseif data.state == STATE_WHEEL then
        actor.sprite_index = sprite_wheel
        actor.image_xscale = data.wheel_dir
        actor.image_speed = 0.35

        -- Bloquear giro de la IA durante la rodada
        actor.moveLeft = 0
        actor.moveRight = 0
        actor.pHspeed = data.wheel_dir * WHEEL_SPEED

        -- Polvo y arenilla de friccion con el suelo al rodar a gran velocidad (sin estelas azules)
        if data.state_t % 8 == 0 then
            pcall(function()
                if gm.constants.oEfDust1 then
                    gm.instance_create(actor.x - data.wheel_dir * 10, actor.y, gm.constants.oEfDust1)
                end
            end)
        end

        -- Dano por contacto durante la embestida
        local hit_players = Search.in_radius(actor.x, actor.y - 10, 30, gm.constants.oP)
        for _, p in ipairs(hit_players) do
            if not data.hit_cooldown[p.id] or (data.state_t - data.hit_cooldown[p.id] > 20) then
                data.hit_cooldown[p.id] = data.state_t
                pcall(function()
                    actor:fire_direct(p, 0.70, 0, nil, nil, gm.constants.sNone, false)
                    p.pHspeed = data.wheel_dir * 1.5
                    p.pVspeed = -1.2
                    Util.play_sound(gm.constants.wPunch or gm.constants.wHit, 0.85, 1.2, p.x, p.y)
                    pcall(function()
                        if gm.constants.oEfDust1 then
                            gm.instance_create(p.x, p.y - 10, gm.constants.oEfDust1)
                        end
                    end)
                end)
            end
        end

        if data.state_t >= WHEEL_DURATION then
            data.state = STATE_TIRED
            data.state_t = 0
            actor.pHspeed = 0
        end

    -- ------------------------------------------------------------------------
    -- Estado: CANSADO / RECUPERACION TRAS EMBESTIDA
    -- ------------------------------------------------------------------------
    elseif data.state == STATE_TIRED then
        actor.sprite_index = sprite_idle
        actor.image_xscale = dir_to_player
        actor.image_speed = 0.15
        actor.pHspeed = 0
        actor.moveLeft = 0
        actor.moveRight = 0

        if data.state_t >= TIRED_DURATION then
            data.state = STATE_WALK
            data.state_t = 0
            data.wheel_cd = WHEEL_COOLDOWN
        end
    end
end)

Callback.add(obj_monkey.on_destroy, function(actor)
    monkey_data[actor.id] = nil
end)

-- ----------------------------------------------------------------------------
-- Generacion en fases con MonsterCard
-- ----------------------------------------------------------------------------
local card_monkey = MonsterCard.new("monkey")
card_monkey.object_id = obj_monkey.value
card_monkey.spawn_cost = 14
card_monkey.spawn_type = 0 -- Classic ground spawn

local stages_with_monkeys = {
    "desolateForest",
    "skyMeadow",
    "magmaBarracks",
    "templeOfTheElders"
}

for _, stage_name in ipairs(stages_with_monkeys) do
    local stage = Stage.find(stage_name)
    if stage then
        stage:add_monster(card_monkey)
    end
end

-- Registrar en el sistema de busqueda de cut content
if Search and Search.register_cut_content then
    Search.register_cut_content("monkey", {
        name   = "Space Lemur / Monkey",
        object = obj_monkey.value,
        sprite = sprite_walk,
        tags   = { "monster", "enemy", "cut_enemy", "agile", "wheel" }
    })
end

return obj_monkey
