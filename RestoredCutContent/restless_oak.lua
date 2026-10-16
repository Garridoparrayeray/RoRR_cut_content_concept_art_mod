-- ============================================================================
-- restless_oak.lua
-- Restaura el enemigo descartado: Roble Inquieto (Restless Oak)
-- Un guardián arbóreo ancestral, pesado y resistente. Camina pesadamente y
-- azota el suelo con un pisotón de raíces que causa temblores y daño en área.
-- Solo aparece en rangos de dificultad alta y fases avanzadas.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSETS = path.combine(PATH, "assets/monsters/restless_oak")

-- Sprites y animaciones multi-frame calibradas al milímetro con origen en la base de las raíces
local sprite_idle   = Sprite.new("RestlessOakIdle",   path.combine(ASSETS, "idle.png"),   17, 58, 213)
local sprite_walk   = Sprite.new("RestlessOakWalk",   path.combine(ASSETS, "walk.png"),   24, 64, 225)
local sprite_attack = Sprite.new("RestlessOakAttack", path.combine(ASSETS, "attack.png"), 14, 94, 204)

-- Parametros de combate
local ATTACK_RANGE    = 90     -- distancia en px para pisotón
local ATTACK_DURATION = 56     -- frames de la animacion de ataque (14 frames a 0.25 spd)
local STOMP_FRAME     = 28     -- momento exacto del golpe en el suelo
local ATTACK_COOLDOWN = 180    -- 3 segundos entre pisotones
local AOE_RADIUS      = 115    -- radio de la onda expansiva

local STATE_WALK   = "walk"
local STATE_ATTACK = "attack"
local STATE_DEAD   = "dead"

-- Definicion del Objeto en ReturnsAPI
local obj_oak = Object.new("RestlessOak", Object.Parent.ENEMY_CLASSIC)
obj_oak:set_sprite(sprite_idle)
obj_oak:set_depth(11)

local oak_data = {}

Callback.add(obj_oak.on_create, function(actor)
    actor.sprite_idle  = sprite_idle
    actor.sprite_walk  = sprite_walk
    actor.sprite_jump  = sprite_idle
    actor.sprite_fall  = sprite_idle
    actor.sprite_death = sprite_idle

    actor.sound_spawn = gm.constants.wGolemSpawn or gm.constants.wSpawn
    actor.sound_hit   = gm.constants.wGolemHit or gm.constants.wHit
    actor.sound_death = gm.constants.wGolemDeath or gm.constants.wDeath

    actor:enemy_stats_init(28, 480, 70, 35)
    actor.pHmax_base = 1.15
    actor.pHmax      = 1.15
    actor.can_jump   = false

    actor.image_xscale = 1.0
    actor.image_yscale = 1.0

    oak_data[actor.id] = {
        state = STATE_WALK,
        state_t = 0,
        attack_cd = 60, -- 1 segundo de guardia antes de su primer pisotón
        stomped = false
    }

    actor:init_actor_late()
    Util.snap_to_ground(actor, 90, 40)
end)

Callback.add(obj_oak.on_step, function(actor)
    local data = oak_data[actor.id]
    if not data then return end

    -- ------------------------------------------------------------------------
    -- MUERTE Y DESINTEGRACION ANCESTRAL (Secuencia organica de caida)
    -- ------------------------------------------------------------------------
    if actor.hp <= 0 then
        if data.state ~= STATE_DEAD then
            data.state = STATE_DEAD
            data.death_t = 0
            actor.pHspeed = 0
            actor.moveLeft = 0
            actor.moveRight = 0
            actor.sprite_index = sprite_idle
            actor.image_speed = 0
            Util.play_sound(gm.constants.wGolemDeath or gm.constants.wDeath, 0.9, 0.7, actor.x, actor.y)
            Util.debris_burst(actor.x, actor.y - 35, 14)
            pcall(function() actor:screen_shake(4) end)

            -- Recompensa de oro y experiencia garantizada al morir
            pcall(function()
                if actor.reward_drop then
                    actor:reward_drop(actor.exp_worth or 35, actor.gold_worth or 70)
                end
            end)
        end

        data.death_t = (data.death_t or 0) + 1
        local death_progress = Util.clamp01(data.death_t / 45)

        -- Temblor decreciente, hundimiento gradual de raices en la tierra y fade out
        Util.shake(actor, data, 2.8 * (1.0 - death_progress))
        actor.y = actor.y + 0.5
        actor.image_alpha = math.max(0, 1.0 - death_progress)
        actor.image_blend = Util.mix_blend({255, 255, 255}, {85, 65, 45}, death_progress)

        if data.death_t == 22 then
            Util.play_sound(gm.constants.wChestClose or gm.constants.wChest1, 1.0, 0.75, actor.x, actor.y)
            Util.debris_burst(actor.x, actor.y - 15, 18)
            pcall(function() actor:screen_shake(5) end)
        end

        if data.death_t >= 45 then
            Util.shake_end(actor, data)
            pcall(function() actor:destroy() end)
        end
        return
    end

    data.state_t = data.state_t + 1
    if data.attack_cd > 0 then data.attack_cd = data.attack_cd - 1 end

    local player = Search.nearest_player(actor.x, actor.y)
    local dir = (actor.image_xscale >= 0) and 1 or -1
    local dist_x = 999
    local dist_y = 999

    if player and Instance.exists(player) then
        dir = (player.x >= actor.x) and 1 or -1
        dist_x = math.abs(player.x - actor.x)
        dist_y = math.abs(player.y - actor.y)
    end

    -- ------------------------------------------------------------------------
    -- Estado: ANDAR / PERSEGUIR CON PASO PESADO
    -- ------------------------------------------------------------------------
    if data.state == STATE_WALK then
        actor.image_xscale = dir
        actor.image_yscale = 1.0

        -- Comprobar si esta en rango para pisotón
        if data.attack_cd <= 0 and dist_x < ATTACK_RANGE and dist_y < 60 then
            data.state = STATE_ATTACK
            data.state_t = 0
            data.stomped = false
            actor.pHspeed = 0
            actor.moveLeft = 0
            actor.moveRight = 0
            actor.sprite_index = sprite_attack
            actor.image_index = 0
            actor.image_speed = 0.25
        else
            -- Perseguir activamente al jugador si esta fuera del rango de ataque
            if dist_x >= (ATTACK_RANGE - 15) then
                actor.moveLeft = (dir < 0) and 1 or 0
                actor.moveRight = (dir > 0) and 1 or 0
                actor.pHspeed = dir * (actor.pHmax or 1.15)
                actor.sprite_index = sprite_walk
                actor.image_speed = 0.22
            else
                -- En rango esperando enfriamiento: guardia quieta
                actor.moveLeft = 0
                actor.moveRight = 0
                actor.pHspeed = 0
                actor.sprite_index = sprite_idle
                actor.image_speed = 0.15
            end
        end

    -- ------------------------------------------------------------------------
    -- Estado: PISOTÓN DE RAÍCES (14 frames animados)
    -- ------------------------------------------------------------------------
    elseif data.state == STATE_ATTACK then
        actor.pHspeed = 0
        actor.moveLeft = 0
        actor.moveRight = 0
        actor.sprite_index = sprite_attack
        actor.image_speed = 0.25

        -- Momento de impacto en el suelo (Frame 7-8)
        if (actor.image_index >= 7.0 or data.state_t >= STOMP_FRAME) and not data.stomped then
            data.stomped = true

            -- Sacudida de camara y sonido de impacto pesado
            pcall(function() actor:screen_shake(6) end)
            Util.play_sound(gm.constants.wGolemAttack or gm.constants.wChest1, 1.0, 0.70, actor.x, actor.y)
            Util.debris_burst(actor.x, actor.y - 10, 15)

            -- Nubes de polvo y temblor terrestre (sin aros o estelas azules)
            pcall(function()
                if gm.constants.oEfDust1 then
                    gm.instance_create(actor.x - 30, actor.y, gm.constants.oEfDust1)
                    gm.instance_create(actor.x, actor.y, gm.constants.oEfDust1)
                    gm.instance_create(actor.x + 30, actor.y, gm.constants.oEfDust1)
                end
            end)

            -- Dano radial a jugadores y lanzamiento vertical
            local hit_players = Search.in_radius(actor.x, actor.y - 10, AOE_RADIUS, gm.constants.oP)
            for _, p in ipairs(hit_players) do
                pcall(function()
                    actor:fire_direct(p, 2.8, 0, nil, nil, gm.constants.sNone, false)
                    p.vspeed = -4.5
                end)
            end
        end

        -- Fin de la animacion de ataque
        if actor.image_index >= 13.0 or data.state_t >= ATTACK_DURATION then
            data.state = STATE_WALK
            data.state_t = 0
            data.attack_cd = ATTACK_COOLDOWN
            actor.sprite_index = sprite_idle
            actor.image_index = 0
            actor.image_speed = 0.15
        end
    end
end)

Callback.add(obj_oak.on_destroy, function(actor)
    oak_data[actor.id] = nil
end)

-- ----------------------------------------------------------------------------
-- Generacion en fases con MonsterCard de Alta Dificultad (Mini-Jefe Pesado)
-- ----------------------------------------------------------------------------
local card_oak = MonsterCard.new("restless_oak")
card_oak.object_id = obj_oak.value
card_oak.spawn_cost = 260       -- Coste de aparicion elevado (similar a un Elder Lemurian)
card_oak.spawn_type = 0         -- Classic ground spawn
card_oak.is_boss = true

-- Solo en fases avanzadas y bosques ancestrales (Valle Antiguo Fase 3, Templo Fase 5)
-- Eliminado por completo de Desolate Forest (Fase 1)
local stages_with_oak = {
    "ancientValley",
    "templeOfTheElders"
}

Callback.add(Callback.TYPE.onStageStart, "RestlessOak_StageSpawnCheck", function()
    local stage_num, threat = Util.read_difficulty()
    -- Solo se activa cuando la partida alcanza dificultad alta (fase 3+ o amenaza >= 2.8)
    if stage_num >= 3 or threat >= 2.8 then
        for _, stage_name in ipairs(stages_with_oak) do
            local stage = Stage.find(stage_name)
            if stage then
                stage:add_monster(card_oak)
            end
        end
    end
end)

-- Registrar en el sistema de busqueda de cut content
if Search and Search.register_cut_content then
    Search.register_cut_content("restless_oak", {
        name   = "Restless Oak",
        object = obj_oak.value,
        sprite = sprite_idle,
        tags   = { "monster", "enemy", "cut_enemy", "tank", "forest" }
    })
end

return obj_oak
