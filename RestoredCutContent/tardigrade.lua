-- ============================================================================
-- tardigrade.lua
-- Macrobic Tardigrade (oMacT): enemigo descartado que sigue en los archivos del
-- juego con todos sus sprites (Idle, Spawn, Walk, Climb, Shoot1, Death).
--
-- Prueba: F12 lo crea junto al jugador y el log registra su
-- comportamiento unos segundos, para saber que hace el enemigo original antes de
-- meterlo en los bestiarios.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local TARDIGRADE_OBJ = gm.constants.oMacT

local KEY_DEBUG_SPAWN  = 123    -- F12 (con Mays: Tardigrado Alfa)
local KEY_SHIFT        = 16
local SPAWN_OFFSET_X   = 150    -- px a la derecha del jugador
local MONITOR_FRAMES   = 1500   -- 25 s de observacion
local MONITOR_INTERVAL = 90     -- frames entre lineas del log

local watched = nil             -- instancia observada
local watch_timer = 0
local last_sprite = nil
local last_player_hp = nil

-- Lee un campo sin que un campo inexistente rompa la observacion
local function read_field(inst, field)
    local ok, value = pcall(function()
        return inst[field]
    end)
    if not ok then return "<error>" end
    return tostring(value)
end

local function sprite_name(inst)
    local ok, name = pcall(function()
        return gm.sprite_get_name(inst.sprite_index)
    end)
    if ok then return tostring(name) end
    return "?"
end

local function describe(inst)
    return string.format("pos=(%.0f,%.0f) sprite=%s frame=%s hp=%s/%s team=%s",
        inst.x, inst.y, sprite_name(inst), read_field(inst, "image_index"),
        read_field(inst, "hp"), read_field(inst, "maxhp"), read_field(inst, "team"))
end

local function spawn_tardigrade(player)
    if not TARDIGRADE_OBJ then
        Util.chat("<r>[TARDIGRADO]</c> oMacT no existe en este juego.")
        log.error("[RestoredCutContent] oMacT no encontrado en gm.constants")
        return
    end

    local inst = gm.instance_create(player.x + SPAWN_OFFSET_X, player.y, TARDIGRADE_OBJ)
    if not inst or not Instance.exists(inst) then
        Util.chat("<r>[TARDIGRADO]</c> No se pudo crear la instancia.")
        log.error("[RestoredCutContent] gm.instance_create devolvio una instancia invalida")
        return
    end

    Util.snap_to_ground(inst, 80, 40)

    -- Con Mays pulsada sale el Alfa (jefe); sin ella, el Tardigrado base. Se le aplica el
    -- mismo ajuste de vida/recompensa/tamano que en una partida normal.
    local variant = nil
    if gm.keyboard_check(KEY_SHIFT) == 1.0 then
        variant = "boss"
    end
    Util.tune_enemy(inst, TARDIGRADE_OBJ, variant)

    watched = inst
    watch_timer = 0
    last_sprite = nil
    last_player_hp = nil

    log.info("[RestoredCutContent] Tardigrado creado" .. (variant and " (ALFA)" or "") .. ": " .. describe(inst))
    if variant then
        Util.chat("<g>[TARDIGRADO]</c> Alfa creado. El log registra su comportamiento durante 25 s.")
    else
        Util.chat("<g>[TARDIGRADO]</c> Creado. El log registra su comportamiento durante 25 s. (Mays+F12 = Alfa)")
    end
end

local function update_monitor()
    if not watched then return end

    watch_timer = watch_timer + 1

    if not Instance.exists(watched) then
        log.info(string.format("[RestoredCutContent] Tardigrado: desaparecio tras %d frames", watch_timer))
        Util.chat("<y>[TARDIGRADO]</c> Ya no existe (murio o se destruyo).")
        watched = nil
        return
    end

    -- Cada cambio de animacion (para ver cuando ataca y cuanto dura cada fase)
    local sprite = sprite_name(watched)
    local player = Instance.find_all(gm.constants.oP)[1]
    local distance = -1
    if player then
        distance = math.sqrt((player.x - watched.x) ^ 2 + (player.y - watched.y) ^ 2)
    end
    if sprite ~= last_sprite then
        log.info(string.format("[RestoredCutContent] Tardigrado t=%d: animacion %s -> %s (distancia al jugador %.0f px)",
            watch_timer, tostring(last_sprite), sprite, distance))
        last_sprite = sprite
    end

    -- Dano al jugador: atribuido a la animacion en curso
    if player and type(player.hp) == "number" then
        if last_player_hp and player.hp < last_player_hp then
            log.info(string.format("[RestoredCutContent] Tardigrado t=%d: el jugador pierde %.1f de vida (sprite %s, distancia %.0f px)",
                watch_timer, last_player_hp - player.hp, sprite, distance))
        end
        last_player_hp = player.hp
    end

    if watch_timer % MONITOR_INTERVAL == 0 then
        log.info(string.format("[RestoredCutContent] Tardigrado t=%d: %s", watch_timer, describe(watched)))
    end

    if watch_timer >= MONITOR_FRAMES then
        log.info("[RestoredCutContent] Tardigrado: fin de la observacion")
        watched = nil
    end
end

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

Callback.add(Callback.TYPE.postStep, "Tardigrade_Debug", function()
    if gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if player and gm.keyboard_check_pressed(KEY_DEBUG_SPAWN) == 1.0 then
        local ok, err = pcall(spawn_tardigrade, player)
        if not ok then Util.log_once("Tardigrade", err) end
    end

    local ok, err = pcall(update_monitor)
    if not ok then Util.log_once("Tardigrade", err) end
end)

log.info("[RestoredCutContent] tardigrade.lua cargado (F12 = crear Tardigrado de prueba)")
