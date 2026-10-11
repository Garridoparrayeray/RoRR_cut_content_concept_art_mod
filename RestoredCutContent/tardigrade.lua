-- ============================================================================
-- tardigrade.lua
-- Macrobic Tardigrade (oMacT): enemigo descartado que sigue en los archivos del
-- juego con todos sus sprites (Idle, Spawn, Walk, Climb, Shoot1, Death).
--
-- Este modulo completa dos cosas que el original dejo a medias:
--   - su explosion (se animaba pero ni daniaba ni mataba)
--   - su aparicion natural en el mapa, junto a paredes
-- Su presencia en las hordas del altar de desafio esta en shrine_challenge.lua, y su
-- vida y recompensa en Util.ENEMY_TUNING.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local TARDIGRADE_OBJ = gm.constants.oMacT

-- ----------------------------------------------------------------------------
-- Explosion: el juego original reproduce la animacion de explotar (sMacTDeath) pero ni
-- hace dano ni mata: el enemigo explota y sigue andando. Aqui se completa: al entrar en
-- esa animacion con vida, la explosion golpea a los jugadores cercanos y el enemigo muere
-- (sin dar recompensa: se ha suicidado). Para quitarlo, EXPLODE_ON_DEATH_ANIM = false.
-- ----------------------------------------------------------------------------
local EXPLODE_ON_DEATH_ANIM = true
local EXPLOSION_WIDTH       = 150   -- px de ancho de la zona (se multiplica por el tamano)
local EXPLOSION_HEIGHT      = 110
local EXPLOSION_DAMAGE      = 2.0   -- coeficiente sobre el dano del propio enemigo
local EXPLOSION_SPARKS      = 8

local exploded = {}   -- ids que ya explotaron (una sola vez por enemigo)

local function explode(enemy)
    local scale = 1
    pcall(function() scale = math.abs(enemy.image_xscale) end)
    if scale == 0 then scale = 1 end

    local x, y = enemy.x, enemy.y - 20
    enemy:fire_explosion(x, y, EXPLOSION_WIDTH * scale, EXPLOSION_HEIGHT * scale,
        EXPLOSION_DAMAGE, nil, nil, false)

    if gm.constants.oEfExplosion then
        pcall(function() gm.instance_create(x, y, gm.constants.oEfExplosion) end)
    end
    for _ = 1, EXPLOSION_SPARKS do
        Util.spark_at(x + gm.random_range(-30, 30) * scale, y + gm.random_range(-25, 25))
    end

    log.info(string.format("[RestoredCutContent] Tardigrado explota en (%.0f,%.0f), tamano x%.2f, coef. dano %.1f",
        x, y, scale, EXPLOSION_DAMAGE))

    -- Muere sin dar experiencia ni oro: se ha suicidado
    pcall(function() enemy.exp_worth = 0 end)
    enemy:kill()
end

local function update_explosions()
    if not TARDIGRADE_OBJ or not gm.constants.sMacTDeath then return end

    for _, enemy in ipairs(Instance.find_all(TARDIGRADE_OBJ)) do
        local id = enemy.id
        if not exploded[id]
            and enemy.sprite_index == gm.constants.sMacTDeath
            and type(enemy.hp) == "number" and enemy.hp > 0 then
            exploded[id] = true
            explode(enemy)
        end
    end
end

Callback.add(Callback.TYPE.postStep, "Tardigrade_Explosion", function()
    if not EXPLODE_ON_DEATH_ANIM or gm._mod_net_isClient() then return end
    local ok, err = pcall(update_explosions)
    if not ok then Util.log_once("Tardigrade", err) end
end)

Callback.add(Callback.TYPE.onStageStart, "Tardigrade_ResetExploded", function()
    exploded = {}
end)

-- ----------------------------------------------------------------------------
-- Aparicion natural: al empezar la fase pueden colocarse Tardigrados por el mapa,
-- en el suelo junto a una pared (para que pueda trepar). Al techo no: segun el
-- documento de los desarrolladores no funciona si se invoca alli.
-- ----------------------------------------------------------------------------
local NATURAL_ENABLED      = true
local NATURAL_WEIGHTS      = { 0.50, 0.38, 0.12 }   -- probabilidad de 0, 1 o 2 por mapa
local NATURAL_MIN_STAGE    = 2      -- no en la fase 1: es un enemigo para jugadores rodados
local NATURAL_BOSS_FACTOR  = 0.5    -- el Alfa natural es la mitad de probable que en un desafio
local NATURAL_MIN_DISTANCE = 700    -- px minimos al jugador al generarse
local NATURAL_TRIES        = 150
local WALL_SCAN_MIN, WALL_SCAN_MAX, WALL_SCAN_STEP = 24, 96, 8
local WALL_STAND_OFF       = 18     -- px de separacion entre el enemigo y la pared

local natural_done_this_stage = false

Callback.add(Callback.TYPE.onStageStart, "Tardigrade_ResetStage", function()
    natural_done_this_stage = false
end)

-- Devuelve x, y de un hueco en el suelo pegado a una pared, o nil
local function find_wall_spot(player)
    local blocks = Instance.find_all(gm.constants.oB)
    if #blocks == 0 then return nil end
    local room_width = Util.room_width()
    local solid = gm.constants.oB

    for _ = 1, NATURAL_TRIES do
        local block = blocks[gm.irandom_range(1, #blocks)]
        if block and Instance.exists(block) then
            local x, y = block.x + 16, block.y
            local far_enough = math.abs(x - player.x) > NATURAL_MIN_DISTANCE
            local free_above = gm.position_meeting(x, y - 40, solid) == 0.0
            if far_enough and free_above and y > 120 then
                for _, side in ipairs({ -1, 1 }) do
                    for dx = WALL_SCAN_MIN, WALL_SCAN_MAX, WALL_SCAN_STEP do
                        -- Pared: solido a la altura del cuerpo y despejado justo encima
                        local wall_x = x + side * dx
                        if gm.position_meeting(wall_x, y - 20, solid) == 1.0
                            and gm.position_meeting(wall_x, y - 56, solid) == 1.0 then
                            local spot_x = wall_x - side * WALL_STAND_OFF
                            if Util.has_firm_ground(spot_x, y, room_width) then
                                return spot_x, y
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function spawn_natural_tardigrades(player)
    local stage_num, threat = Util.read_difficulty()
    if stage_num < NATURAL_MIN_STAGE then return end

    local identifier = Util.current_stage_identifier()
    if not identifier or not Util.TARDIGRADE_BIOMES[string.lower(identifier)] then return end

    local wanted = Util.roll_count(NATURAL_WEIGHTS)
    local made = 0
    for _ = 1, wanted do
        local x, y = find_wall_spot(player)
        if x then
            local inst = gm.instance_create(x, y, TARDIGRADE_OBJ)
            if inst and Instance.exists(inst) then
                Util.snap_to_ground(inst, 80, 40)

                -- Con amenaza alta (y fase 3+) puede ser un Alfa, aunque menos que en un desafio
                local variant = nil
                if stage_num >= 3 and gm.random(1.0) < Util.boss_chance(threat) * NATURAL_BOSS_FACTOR then
                    variant = "boss"
                    Util.chat("<r>[Tardígrado]</c> Un Tardígrado Alfa ronda por este mapa...")
                end

                Util.tune_enemy(inst, TARDIGRADE_OBJ, variant)
                made = made + 1
                log.info(string.format("[RestoredCutContent] Tardigrado natural%s en (%.0f,%.0f)",
                    variant and " ALFA" or "", inst.x, inst.y))
            end
        end
    end
    log.info(string.format("[RestoredCutContent] Tardigrados naturales en %s: %d (sorteados %d, amenaza %.2f)",
        identifier, made, wanted, threat))
end

Callback.add(Callback.TYPE.postStep, "Tardigrade_NaturalSpawn", function()
    if not NATURAL_ENABLED or natural_done_this_stage or not TARDIGRADE_OBJ then return end
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if not player then return end

    natural_done_this_stage = true
    local ok, err = pcall(spawn_natural_tardigrades, player)
    if not ok then Util.log_once("Tardigrade", err) end
end)

log.info("[RestoredCutContent] tardigrade.lua cargado")
