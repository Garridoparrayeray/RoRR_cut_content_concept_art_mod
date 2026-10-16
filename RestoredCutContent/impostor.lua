-- ============================================================================
-- impostor.lua
-- Superviviente completo: Impostor (Among Us) para Risk of Rain Returns
-- Incluye animaciones personalizadas pixel art, mecanicas de apunalada trapera,
-- pistolazo a quemarropa, ventilacion sigilosa y reunion de emergencia.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSETS = path.combine(PATH, "assets/survivors/impostor")

-- ----------------------------------------------------------------------------
-- Carga de Sprites y Animaciones con Origenes Precisos (Pies al suelo)
-- ----------------------------------------------------------------------------
-- En GameMaker / RoRR, la base de colision del jugador descansa a y + 11.
-- Para que los pies toquen el suelo sin flotar: yoffset = pies_y - 11.
local sprite_loadout        = Sprite.new("ImpostorSelect",        path.combine(ASSETS, "select.png"),         1, 28, 0)
local sprite_portrait       = Sprite.new("ImpostorPortrait",      path.combine(ASSETS, "portrait.png"),       1, 0, 0)
local sprite_portrait_small = Sprite.new("ImpostorPortraitSmall", path.combine(ASSETS, "portrait_small.png"), 1, 0, 0)

local sprite_idle           = Sprite.new("ImpostorIdle",          path.combine(ASSETS, "idle.png"),           4, 16, 15)
local sprite_walk           = Sprite.new("ImpostorWalk",          path.combine(ASSETS, "walk.png"),           8, 16, 15)
local sprite_jump           = Sprite.new("ImpostorJump",          path.combine(ASSETS, "jump.png"),           1, 16, 15)
local sprite_fall           = Sprite.new("ImpostorFall",          path.combine(ASSETS, "fall.png"),           1, 16, 15)
local sprite_climb          = Sprite.new("ImpostorClimb",         path.combine(ASSETS, "climb.png"),          4, 16, 15)
local sprite_death          = Sprite.new("ImpostorDeath",         path.combine(ASSETS, "death.png"),          6, 16, 15)

local sprite_shoot1         = Sprite.new("ImpostorShoot1",        path.combine(ASSETS, "shoot1.png"),         18, 16, 36)
local sprite_shoot2         = Sprite.new("ImpostorShoot2",        path.combine(ASSETS, "shoot2.png"),         8, 24, 16)
local sprite_shoot3         = Sprite.new("ImpostorShoot3",        path.combine(ASSETS, "shoot3.png"),         8, 24, 15)
local sprite_shoot4         = Sprite.new("ImpostorShoot4",        path.combine(ASSETS, "shoot4.png"),         6, 16, 15)

local sprite_palette        = Sprite.new("ImpostorPalette",       path.combine(ASSETS, "palette.png"),        1, 0, 0)

local sprite_skill_z        = Sprite.new("ImpostorSkillZ",        path.combine(ASSETS, "skill_z.png"),        1, 12, 12)
local sprite_skill_x        = Sprite.new("ImpostorSkillX",        path.combine(ASSETS, "skill_x.png"),        1, 12, 12)
local sprite_skill_c        = Sprite.new("ImpostorSkillC",        path.combine(ASSETS, "skill_c.png"),        1, 12, 12)
local sprite_skill_v        = Sprite.new("ImpostorSkillV",        path.combine(ASSETS, "skill_v.png"),        1, 12, 12)
local sprite_skill_vscepter = Sprite.new("ImpostorSkillVScepter", path.combine(ASSETS, "skill_v_scepter.png"),1, 12, 12)

-- Efectos de sonido nativos optimizados
local SND_SLASH1   = gm.constants.wMercenaryShoot1_1
local SND_SLASH2   = gm.constants.wMercenaryShoot1_2
local SND_SLASH3   = gm.constants.wMercenaryShoot1_3
local SND_SWING     = gm.constants.wMercenaryShoot1_1
local SND_EMERGENCY = gm.constants.wCutsceneAlarm or gm.constants.wAlarm

-- ----------------------------------------------------------------------------
-- Inicializacion del Superviviente
-- ----------------------------------------------------------------------------
local impostor = Survivor.find("impostor")
if not impostor then
    local ok, res = pcall(Survivor.new, "impostor")
    if ok and res then
        impostor = res
    else
        impostor = Survivor.new(NAMESPACE, "impostor")
    end
end

-- Estadisticas equilibradas y fieles a Risk of Rain Returns
impostor:set_stats_base({
    health          = 110,
    damage          = 13,
    regen           = 0.012,
    armor           = 5,
    attack_speed    = 1.0,
    critical_chance = 1.0
})

impostor:set_stats_level({
    health          = 28,
    damage          = 2.8,
    regen           = 0.0015,
    armor           = 1.5,
    attack_speed    = 0.0,
    critical_chance = 0.0
})

impostor.primary_color = Color.from_rgb(197, 17, 17)
impostor.sprite_loadout = sprite_loadout
impostor.sprite_portrait = sprite_portrait
impostor.sprite_portrait_small = sprite_portrait_small
impostor.sprite_idle = sprite_idle
impostor.sprite_title = sprite_walk     -- Camina en el mini-planeta del menu principal
impostor.sprite_credits = sprite_walk

impostor.sprite_palette = sprite_palette
impostor.sprite_portrait_palette = sprite_palette
impostor.sprite_loadout_palette = sprite_palette

pcall(function()
    impostor:add_skin("default", sprite_palette, sprite_palette, sprite_palette)
end)

impostor.token_name = "Impostor"
impostor.token_name_upper = "IMPOSTOR"
impostor.token_description = "The Impostor is an elusive, deceptive killer who ambushes unsuspecting victims, draws a lethal pistol at point-blank range, traverses through vents unseen, and calls emergency meetings to eliminate targets.\n\n&y'There is 1 Impostor among us.'&!"
impostor.token_end_quote = "...and so he vented away, never to be caught."

-- Almacenamiento seguro de datos por instancia de actor
local imp_actor_data = {}
local function get_actor_data(actor)
    if not actor then return {} end
    local id = actor.id or tostring(actor)
    if not imp_actor_data[id] then
        imp_actor_data[id] = {}
    end
    return imp_actor_data[id]
end

-- Asignacion limpia de sprites al actor (neutralizando sprites de Commando por completo)
Callback.add(impostor.on_init, function(actor)
    actor.sprite_idle = sprite_idle
    actor.sprite_walk = sprite_walk
    actor.sprite_jump = sprite_jump
    actor.sprite_jump_peak = sprite_jump
    actor.sprite_fall = sprite_fall
    actor.sprite_climb = sprite_climb
    actor.sprite_death = sprite_death
    actor.sprite_decoy = sprite_idle
    actor.sprite_spawn = sprite_idle
    actor.sprite_hit = sprite_idle
    actor.sprite_drown = sprite_death
    actor.sprite_palette = sprite_palette
    actor.sprite_shoot1 = sprite_shoot1
    actor.sprite_shoot2 = sprite_shoot2
    actor.sprite_shoot3 = sprite_shoot3
    actor.sprite_shoot4 = sprite_shoot4
    actor.sprite_shoot5 = sprite_shoot4

    -- Desactivar el desglose de medio-cuerpo por completo (-4 = noone en GameMaker)
    actor.sprite_idle_half = -4
    actor.sprite_walk_half = -4
    actor.sprite_jump_half = -4
    actor.sprite_jump_peak_half = -4
    actor.sprite_fall_half = -4
    actor.sprite_index2 = -4

    local d = get_actor_data(actor)
    d.is_impostor = true
end)

-- Garantizar frame a frame que no se dibuje el torso/mitad superior de Commando
local function neutralize_commando_sprites()
    for _, player in ipairs(Instance.find_all(gm.constants.oP)) do
        local d = get_actor_data(player)
        if player.class == impostor.value or d.is_impostor or player.sprite_idle == sprite_idle then
            player.sprite_spawn = sprite_idle
            player.sprite_hit = sprite_idle
            player.sprite_drown = sprite_death
            player.sprite_shoot1 = sprite_shoot1
            player.sprite_shoot2 = sprite_shoot2
            player.sprite_shoot3 = sprite_shoot3
            player.sprite_shoot4 = sprite_shoot4
            player.sprite_shoot5 = sprite_shoot4
            player.sprite_idle_half = -4
            player.sprite_walk_half = -4
            player.sprite_jump_half = -4
            player.sprite_jump_peak_half = -4
            player.sprite_fall_half = -4
            player.sprite_index2 = -4
            if player.sprite_index == gm.constants.sCommandoHit or player.sprite_index == gm.constants.sCommandoSpawn then
                player.sprite_index = sprite_idle
            end
        end
    end
end

local function impostor_post_step()
    neutralize_commando_sprites()
    for _, player in ipairs(Instance.find_all(gm.constants.oP)) do
        local d = get_actor_data(player)
        if player.class == impostor.value or d.is_impostor or player.sprite_idle == sprite_idle then
            -- Invisibilidad e indetectabilidad total mientras este bajo la trampilla
            if d.vent_phase == "entering" or d.vent_phase == "submerged" then
                for _, foe in ipairs(Instance.find_all(gm.constants.pEnemy)) do
                    if Instance.exists(foe) and (foe.target == player or foe.target == player.id or foe.target == player.value) then
                        foe.target = -4
                        foe.target_priority = 0
                        foe.provoke = 0
                        foe.target_x = 0
                        foe.target_y = 0
                        foe.moveLeft = 0
                        foe.moveRight = 0
                        foe.moveUp = 0
                    end
                end
            end

            -- Subidon de adrenalina (+60% velocidad al matar con pistola)
            if d.speed_boost_timer and d.speed_boost_timer > 0 then
                d.speed_boost_timer = d.speed_boost_timer - 1
                if (Global._current_frame or 0) % 12 == 0 then
                    pcall(function()
                        if gm.constants.oEfDust1 then
                            gm.instance_create(player.x, player.y, gm.constants.oEfDust1)
                        end
                    end)
                end
                if d.speed_boost_timer == 0 then
                    pcall(function() player:queue_recalculate_stats() end)
                end
            end
        end
    end
end
Callback.add(Callback.TYPE.postStep, impostor_post_step)
Callback.add(Callback.TYPE.preStep, neutralize_commando_sprites)
Callback.add(Callback.TYPE.onDraw, neutralize_commando_sprites)

-- ----------------------------------------------------------------------------
-- HABILIDAD 1 (Z): Punalada / Apunalada Trapera (Knife Shank / Backstab)
-- ----------------------------------------------------------------------------
local primary = impostor:get_skills(Skill.Slot.PRIMARY)[1]
if not primary then
    primary = Skill.new("impostorPrimary")
    impostor:add_skill(Skill.Slot.PRIMARY, primary)
end

primary.sprite = sprite_skill_z
primary.subimage = 0
primary.cooldown = 14          -- Breve pausa de recuperacion tras terminar el combo
primary.damage = 2.0           -- 200% dano promedio
primary.require_key_press = true -- Requiere soltar y pulsar para iniciar un nuevo combo, evitando que se dispare un golpe de mas al mantener apretado
primary.is_primary = true
primary.does_change_activity_state = true
primary.token_name = "Shank / Backstab"
primary.token_description = "Perform a swift, deadly 3-hit knife combo. Striking an enemy from &ybehind deals lethal critical damage&!. Tap to chain slashes or hold for the full sequence."

local statePrimary = ActorState.new("impostorStatePrimary")

local function is_primary_input_down(actor)
    if Util.bool(gm.keyboard_check(90)) then return true end -- Z
    if Util.bool(gm.mouse_check_button(1)) then return true end -- Clic izquierdo
    if actor.key_shoot1 and Util.bool(actor.key_shoot1) then return true end
    if actor.input_shoot1 and Util.bool(actor.input_shoot1) then return true end
    local gp_down = false
    pcall(function()
        if gm.gamepad_is_connected and Util.bool(gm.gamepad_is_connected(0)) and gm.gamepad_button_check then
            if Util.bool(gm.gamepad_button_check(0, 32769)) or Util.bool(gm.gamepad_button_check(0, 32771)) or Util.bool(gm.gamepad_button_check(0, 32775)) then
                gp_down = true
            end
        end
    end)
    return gp_down
end

local function is_primary_input_pressed(actor)
    if Util.bool(gm.keyboard_check_pressed(90)) then return true end -- Z
    if Util.bool(gm.mouse_check_button_pressed(1)) then return true end -- Clic izquierdo
    if actor.key_shoot1_pressed and Util.bool(actor.key_shoot1_pressed) then return true end
    if actor.input_shoot1_pressed and Util.bool(actor.input_shoot1_pressed) then return true end
    local gp_pressed = false
    pcall(function()
        if gm.gamepad_is_connected and Util.bool(gm.gamepad_is_connected(0)) and gm.gamepad_button_check_pressed then
            if Util.bool(gm.gamepad_button_check_pressed(0, 32769)) or Util.bool(gm.gamepad_button_check_pressed(0, 32771)) or Util.bool(gm.gamepad_button_check_pressed(0, 32775)) then
                gp_pressed = true
            end
        end
    end)
    return gp_pressed
end

Callback.add(primary.on_activate, function(actor, skill, slot)
    actor:set_state(statePrimary)
end)

Callback.add(statePrimary.on_enter, function(actor, data)
    local d = get_actor_data(actor)
    local atk_spd = (actor.attack_speed and actor.attack_speed > 0) and actor.attack_speed or 1.0

    -- Cada vez que se inicia el ataque desde fuera (idle, correr, etc.),
    -- siempre comienza desde la primera cuchillada (Hit 1).
    d.combo_stage = 1
    d.strike_done = false
    d.wants_next_combo = false
    d.button_released = false
    d.combo_end = 5.5

    actor.sprite_index = sprite_shoot1
    actor.image_index = 0
    actor.image_speed = 0.35 * atk_spd
    actor:skill_util_fix_hspeed()
    actor:actor_animation_set(sprite_shoot1, 0.35 * atk_spd, false)

    -- Sonido de tajo / cuchillada en el aire inmediato al blandir
    Util.play_sound(SND_SLASH1, 1.4, 1.25, actor.x, actor.y)
end)

Callback.add(statePrimary.on_step, function(actor, data)
    local atk_spd = (actor.attack_speed and actor.attack_speed > 0) and actor.attack_speed or 1.0
    actor.sprite_index = sprite_shoot1
    actor.image_speed = 0.35 * atk_spd

    local d = get_actor_data(actor)
    local dir = (actor.image_xscale >= 0) and 1 or -1

    -- Eliminar interferencia de movimiento al andar durante el ataque
    actor.moveLeft = 0
    actor.moveRight = 0

    -- Paso agil hacia adelante con cada estocada
    if d.combo_stage == 1 then
        actor.pHspeed = dir * 0.8
    elseif d.combo_stage == 2 then
        actor.pHspeed = dir * 1.1
    else
        actor.pHspeed = dir * 1.6 -- Salto hacia adelante en el remate
    end

    -- Gestion precisa de la pulsacion / mantenimiento del boton
    local input_down = is_primary_input_down(actor)
    local input_pressed = is_primary_input_pressed(actor)

    if not input_down then
        d.button_released = true
    end

    -- Peticion de encadenamiento de combo:
    -- Caso 1 (Toque manual): El usuario solto el boton y presiono de nuevo para el siguiente golpe
    if d.button_released and (input_pressed or input_down) then
        if d.combo_stage < 3 then
            d.wants_next_combo = true
        end
    end

    -- Caso 2 (Mantenimiento continuo): Si el usuario mantiene pulsado sin soltar el boton,
    -- encadena automaticamente en los ultimos fotogramas de la animacion actual
    if not d.button_released and input_down and actor.image_index >= (d.combo_end - 1.2) then
        if d.combo_stage < 3 then
            d.wants_next_combo = true
        end
    end

    local function is_behind_target()
        local foes = Instance.find_all(gm.constants.pEnemy)
        for _, foe in ipairs(foes) do
            if foe.team ~= actor.team and Instance.exists(foe) then
                local dx = (foe.x - actor.x) * dir
                local dy = math.abs(foe.y - actor.y)
                if dx >= 0 and dx <= 65 and dy <= 32 then
                    if (foe.image_xscale > 0 and dir > 0) or (foe.image_xscale < 0 and dir < 0) then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Golpe 1: Cuchillada diagonal (Frame 2: gran arco de corte blanco/plateado original)
    if d.combo_stage == 1 and not d.strike_done and actor.image_index >= 2.0 then
        d.strike_done = true
        local backstab = is_behind_target()
        local sparks = backstab and (gm.constants.sSparksCrit or gm.constants.sNone) or gm.constants.sNone
        local atk = actor:fire_explosion(actor.x + dir * 24, actor.y - 4, 56, 36, backstab and 2.6 or 1.4, -4, sparks, true)
        if atk and atk.attack_info and backstab then
            atk.attack_info.critical = true
            atk.attack_info.damage_color = Color.from_rgb(255, 30, 30)
            Util.play_sound(gm.constants.wCut, 1.3, 1.1, actor.x, actor.y)
        elseif atk then
            Util.play_sound(gm.constants.wCut, 1.1, 1.25, actor.x, actor.y)
        end
    end

    -- Golpe 2: Estocada frontal horizontal (Frame 7: destello de punta y estocada)
    if d.combo_stage == 2 and not d.strike_done and actor.image_index >= 7.0 then
        d.strike_done = true
        local backstab = is_behind_target()
        actor:screen_shake(2)
        local sparks = backstab and (gm.constants.sSparksCrit or gm.constants.sNone) or gm.constants.sNone
        local atk = actor:fire_explosion(actor.x + dir * 28, actor.y - 4, 62, 34, backstab and 3.4 or 1.8, -4, sparks, true)
        if atk and atk.attack_info and backstab then
            atk.attack_info.critical = true
            atk.attack_info.damage_color = Color.from_rgb(255, 30, 30)
            Util.play_sound(gm.constants.wCut, 1.4, 1.0, actor.x, actor.y)
        elseif atk then
            Util.play_sound(gm.constants.wCut, 1.2, 1.15, actor.x, actor.y)
        end
    end

    -- Golpe 3: Remate letal con apunalada profunda (Frame 13: tajo vertical descendente)
    if d.combo_stage == 3 and not d.strike_done and actor.image_index >= 13.0 then
        d.strike_done = true
        local backstab = is_behind_target()
        actor:screen_shake(5)
        local sparks = backstab and (gm.constants.sSparksCrit or gm.constants.sNone) or (gm.constants.sSparksCrit or gm.constants.sNone)
        local atk = actor:fire_explosion(actor.x + dir * 32, actor.y - 4, 70, 40, backstab and 5.0 or 2.6, -4, sparks, true)
        if atk and atk.attack_info then
            if backstab then
                atk.attack_info.critical = true
                atk.attack_info.damage_color = Color.from_rgb(255, 10, 10)
            end
            Util.play_sound(gm.constants.wCut, 1.5, 0.9, actor.x, actor.y)
        end
    end

    -- Deteccion de fin de fotograma por etapa (previene bucles y wrap-around en GameMaker)
    local is_stage_finished = false
    if d.combo_stage == 1 and (actor.image_index >= (d.combo_end or 5.5) or actor.image_index < 0.0) then
        is_stage_finished = true
    elseif d.combo_stage == 2 and (actor.image_index >= (d.combo_end or 11.5) or actor.image_index < 6.0) then
        is_stage_finished = true
    elseif d.combo_stage == 3 and (actor.image_index >= (d.combo_end or 16.8) or (d.strike_done and actor.image_index < 12.0)) then
        is_stage_finished = true
    end

    if is_stage_finished then
        if d.wants_next_combo and d.combo_stage < 3 then
            -- Continuar fluidamente el combo encadenado (golpe 2 o golpe 3)
            d.combo_stage = d.combo_stage + 1
            d.strike_done = false
            d.wants_next_combo = false
            d.button_released = false

            if d.combo_stage == 2 then
                actor.image_index = 6.0
                d.combo_end = 11.5
                Util.play_sound(SND_SLASH2, 1.4, 1.15, actor.x, actor.y)
            elseif d.combo_stage == 3 then
                actor.image_index = 12.0
                d.combo_end = 16.8
                Util.play_sound(SND_SLASH3, 1.5, 1.05, actor.x, actor.y)
            end
        else
            -- Si se dejo de pulsar, se llego al limite o ya se ejecuto el remate del combo:
            -- Se restablece SIEMPRE al golpe 1 para que el siguiente ataque empiece desde el inicio.
            d.combo_stage = 1
            d.strike_done = false
            d.wants_next_combo = false
            d.button_released = false
            actor:skill_util_reset_activity_state()
            if actor.state == statePrimary.value then
                actor:set_state(actor.state_default or 0)
            end
        end
    end
end)

Callback.add(statePrimary.on_exit, function(actor, data)
    actor.image_speed = 1.0
    local d = get_actor_data(actor)
    d.combo_stage = 1
    d.strike_done = false
    d.wants_next_combo = false
    d.button_released = false
    d.hold_frames = 0
end)

-- ----------------------------------------------------------------------------
-- HABILIDAD 2 (X): Pistolazo / Ejecucion a Quemarropa (Gun Shot)
-- ----------------------------------------------------------------------------
local secondary = impostor:get_skills(Skill.Slot.SECONDARY)[1]
if not secondary then
    secondary = Skill.new("impostorSecondary")
    impostor:add_skill(Skill.Slot.SECONDARY, secondary)
end

secondary.sprite = sprite_skill_x
secondary.subimage = 0
secondary.cooldown = 3.0 * 60  -- 3.0 segundos (reducido 1s)
secondary.damage = 4.8         -- 480% de dano base (+100% de potencia)
secondary.require_key_press = true
secondary.token_name = "Pistolazo"
secondary.token_description = "Draw a hidden pistol and fire a piercing shot for &y480% damage&!. Targets within point-blank range (<60px) suffer a &ycritical execution for 680% damage&! and are &ystunned for 1.2s&!.\n&gKills grant +60% movement speed for 4 seconds!&!"

local stateSecondary = ActorState.new("impostorStateSecondary")

Callback.add(secondary.on_activate, function(actor, skill, slot)
    actor:set_state(stateSecondary)
end)

Callback.add(stateSecondary.on_enter, function(actor, data)
    actor.sprite_index = sprite_shoot2
    actor.image_index = 0
    actor.image_speed = 0.22 -- Disparo potente con anticipacion calculada
    local d = get_actor_data(actor)
    d.imp_shot_fired = false
end)

Callback.add(stateSecondary.on_step, function(actor, data)
    actor.sprite_index = sprite_shoot2
    actor.image_speed = 0.22
    local d = get_actor_data(actor)
    local dir = (actor.image_xscale >= 0) and 1 or -1
    local angle = (dir > 0) and 0 or 180

    -- Frenado y firmeza al apuntar sin desestabilizarse al andar
    actor.moveLeft = 0
    actor.moveRight = 0
    if not d.imp_shot_fired then
        actor.pHspeed = (actor.pHspeed or 0) * 0.15
    end

    -- Frame 5: Disparo letal (Fogonazo autentico en la animacion de corte)
    if not d.imp_shot_fired and actor.image_index >= 5.0 then
        d.imp_shot_fired = true
        d.pistol_fired_frame = Global._current_frame or 0
        actor:screen_shake(6)

        -- Sonido potente de arma de fuego
        local gun_sound = gm.constants.wBullet1 or gm.constants.wSniperShoot1 or gm.constants.wChestOpen
        Util.play_sound(gun_sound, 1.25, 0.95, actor.x, actor.y)

        -- Fogonazo y humo de polvora en la boca del arma (sin estelas azules)
        pcall(function()
            if gm.constants.oEfDust1 then
                gm.instance_create(actor.x + dir * 28, actor.y - 3, gm.constants.oEfDust1)
            end
        end)

        -- Deteccion de enemigo a quemarropa (<60px)
        local close_execute = false
        local foes = Instance.find_all(gm.constants.pEnemy)
        for _, foe in ipairs(foes) do
            if foe.team ~= actor.team and Instance.exists(foe) then
                local dx = (foe.x - actor.x) * dir
                local dy = math.abs(foe.y - actor.y)
                if dx >= 0 and dx <= 60 and dy <= 28 then
                    close_execute = true
                    if foe.actor_set_stunned then
                        pcall(function() foe:actor_set_stunned(72) end)
                    elseif foe.stunned ~= nil then
                        foe.stunned = true
                    end
                end
            end
        end

        local shot_damage = close_execute and 6.8 or 4.8
        local hit_sparks = close_execute and (gm.constants.sSparksCrit or gm.constants.sNone) or gm.constants.sNone
        -- tracer = 0 (Tracer.NONE) para evitar cualquier estela / trazador azul del motor
        local bullet = actor:fire_bullet(actor.x + dir * 18, actor.y - 3, 500, angle, shot_damage, 1.0, hit_sparks, 0, true)
        if bullet and bullet.attack_info then
            bullet.attack_info.impostor_pistol = 1
            bullet.attack_info.pistol_shooter_id = actor.id
            if close_execute then
                bullet.attack_info.critical = true
                bullet.attack_info.damage_color = Color.from_rgb(255, 40, 20)
            else
                bullet.attack_info.damage_color = Color.from_rgb(255, 175, 40)
            end
        end

        -- Retroceso del disparo
        actor.pHspeed = -dir * 2.5
    end

    if actor.image_index >= 7.5 then
        actor:skill_util_reset_activity_state()
        if actor.state == stateSecondary.value then
            actor:set_state(actor.state_default or 0)
        end
    end
end)

Callback.add(stateSecondary.on_exit, function(actor, data)
    actor.image_speed = 1.0
end)

-- ----------------------------------------------------------------------------
-- Subidon de Adrenalina por Baja con Pistola (+60% Velocidad de Movimiento)
-- ----------------------------------------------------------------------------
local buffSpeed = nil
pcall(function()
    buffSpeed = Buff.new("impostorAdrenaline")
    buffSpeed.show_icon = false
end)

local function trigger_pistol_kill_speed_boost(actor)
    if not actor or not Instance.exists(actor) then return end
    local d = get_actor_data(actor)
    d.speed_boost_timer = 240 -- 4 segundos de velocidad extrema (240 frames a 60fps)

    pcall(function()
        if buffSpeed then
            actor:buff_apply(buffSpeed, 240)
        end
    end)
    pcall(function() actor:queue_recalculate_stats() end)

    Util.play_sound(gm.constants.wWhip or gm.constants.wLevelUp, 1.25, 1.35, actor.x, actor.y)
    pcall(function()
        if gm.constants.oEfDust1 then
            gm.instance_create(actor.x - 8, actor.y, gm.constants.oEfDust1)
            gm.instance_create(actor.x + 8, actor.y, gm.constants.oEfDust1)
        end
    end)
    Util.chat("<g>[Impostor]</c> ¡Baja con pistola! Subidón de adrenalina (+60% Velocidad).")
    log.info("[RestoredCutContent] Impostor: Baja con pistola confirmada -> Buff de velocidad activado")
end

-- Callback 1: Fin del ataque (AttackInfo con kill_number > 0)
Callback.add(Callback.ON_ATTACK_HANDLE_END, function(attack_info)
    if attack_info and attack_info.impostor_pistol == 1 then
        local kills = attack_info.kill_number or 0
        if kills > 0 then
            local shooter = attack_info.parent
            if (not shooter or not Instance.exists(shooter)) and attack_info.pistol_shooter_id then
                shooter = Instance.wrap(attack_info.pistol_shooter_id)
            end
            if shooter and Instance.exists(shooter) then
                trigger_pistol_kill_speed_boost(shooter)
            end
        end
    end
end)

-- Callback 2: Muerte directa por proc (ON_KILL_PROC)
Callback.add(Callback.ON_KILL_PROC, function(victim, killer)
    if not killer or not Instance.exists(killer) then return end
    local d = get_actor_data(killer)
    local now = Global._current_frame or 0
    if d and (killer.state == stateSecondary.value or (d.pistol_fired_frame and (now - d.pistol_fired_frame <= 35))) then
        trigger_pistol_kill_speed_boost(killer)
    end
end)

-- Recalculo de estadisticas: Multiplica pHmax x 1.60 (+60% velocidad)
RecalculateStats.add(function(actor, api)
    local d = get_actor_data(actor)
    local has_boost = (d and d.speed_boost_timer and d.speed_boost_timer > 0)
    if not has_boost and actor.buff_count and buffSpeed then
        has_boost = (actor:buff_count(buffSpeed) > 0)
    end
    if has_boost then
        api.pHmax_mult(1.60)       -- +60% Velocidad de carrera
        api.attack_speed_add(0.20) -- +20% Velocidad de ataque durante el subidon
    end
end)

-- ----------------------------------------------------------------------------
-- HABILIDAD 3 (C): Ventilacion (Vent / Subterranean Stealth & Ambush)
-- ----------------------------------------------------------------------------
local utility = impostor:get_skills(Skill.Slot.UTILITY)[1]
if not utility then
    utility = Skill.new("impostorUtility")
    impostor:add_skill(Skill.Slot.UTILITY, utility)
end

utility.sprite = sprite_skill_c
utility.subimage = 0
utility.cooldown = 6 * 60      -- 6 segundos
utility.damage = 3.2           -- 320% al emerger
utility.is_utility = true
utility.require_key_press = true
utility.does_change_activity_state = true
utility.token_name = "Vent"
utility.token_description = "Dive into the floor vents, becoming &yInvulnerable and completely undetectable to enemies, with +85% move speed&! in stealth for up to 6.0s. Press &yJump, Shift, or C&! to burst out at will (or wait 6.0s), dealing &y320% explosion damage&!, &ystunning for 1.5s&!, and executing a lethal &y500% Backstab Ambush&!."

local stateUtility = ActorState.new("impostorStateUtility")

Callback.add(utility.on_activate, function(actor, skill, slot)
    actor:set_state(stateUtility)
end)

Callback.add(stateUtility.on_enter, function(actor, data)
    actor.sprite_index = sprite_shoot3
    actor.image_index = 0
    actor.image_speed = 0.16   -- Animacion visible y clara de meterse a la trampilla (~0.4s)
    local d = get_actor_data(actor)
    d.vent_phase = "entering"  -- entering -> submerged -> emerging
    d.vent_timer = 360         -- 6.0 segundos bajo tierra tras entrar
    d.submerged_frames = 0
    d.emerge_timer = 0
    d.prev_jump = true         -- Inicializado en true para evitar falso disparo de salto en los primeros frames

    -- Salto de Mario Bros al entrar a la tuberia / trampilla
    actor.pVspeed = -3.5
    actor.pHspeed = (actor.pHspeed or 0) * 0.35 -- Reduce inercia horizontal para no salirse del punto de entrada

    -- Activar sigilo nativo e invisibilidad del motor
    actor.shadow = true
    actor.invisible = true

    -- Desenganchar el aggro y objetivo de todos los enemigos en el mapa
    local enemy_parents = {
        gm.constants.pEnemy,
        gm.constants.pEnemyClassic,
        gm.constants.pEnemyFlying,
        gm.constants.pBoss,
        gm.constants.pBossClassic,
    }
    for _, parent in ipairs(enemy_parents) do
        if parent then
            for _, foe in ipairs(Instance.find_all(parent)) do
                if Instance.exists(foe) and (foe.target == actor or foe.target == actor.id or foe.target == actor.value) then
                    foe.target = -4
                    foe.target_priority = 0
                    foe.provoke = 0
                    foe.target_x = 0
                    foe.target_y = 0
                    foe.moveLeft = 0
                    foe.moveRight = 0
                    foe.moveUp = 0
                end
            end
        end
    end

    actor.invincible = math.max(actor.invincible, 400)
    actor.visible = true
    actor.image_alpha = 1.0    -- Completamente visible mientras salta y se mete
    Util.play_sound(gm.constants.wDoorClose or gm.constants.wChestClose or gm.constants.wChest1, 1.1, 1.25, actor.x, actor.y)
    pcall(function()
        if gm.constants.oEfDust1 then
            gm.instance_create(actor.x, actor.y + 8, gm.constants.oEfDust1)
        end
    end)
end)

Callback.add(stateUtility.on_step, function(actor, data)
    local d = get_actor_data(actor)
    actor.invincible = math.max(actor.invincible, 20)
    actor.shadow = false
    actor.invisible = true

    -- Mantiene al jugador indetectable para los enemigos mientras este en la trampilla
    if d.vent_phase == "entering" or d.vent_phase == "submerged" then
        local enemy_parents = {
            gm.constants.pEnemy,
            gm.constants.pEnemyClassic,
            gm.constants.pEnemyFlying,
            gm.constants.pBoss,
            gm.constants.pBossClassic,
        }
        for _, parent in ipairs(enemy_parents) do
            if parent then
                for _, foe in ipairs(Instance.find_all(parent)) do
                    if Instance.exists(foe) and (foe.target == actor or foe.target == actor.id or foe.target == actor.value) then
                        foe.target = -4
                        foe.target_priority = 0
                        foe.provoke = 0
                        foe.target_x = 0
                        foe.target_y = 0
                        foe.moveLeft = 0
                        foe.moveRight = 0
                        foe.moveUp = 0
                    end
                end
            end
        end
    end

    -- FASE 1: METIÉNDOSE A LA TRAMPILLA (Frames 0 a 4 se ven con total claridad en el salto)
    if d.vent_phase == "entering" then
        actor.sprite_index = sprite_shoot3
        actor.image_speed = 0.16
        actor.visible = true
        actor.image_alpha = 1.0

        if actor.image_index >= 3.9 then
            d.vent_phase = "submerged"
            d.submerged_frames = 0
            d.vent_timer = 360 -- 6.0 segundos bajo tierra tras entrar
            d.prev_jump = true -- Asegura que no se dispare de inmediato
            actor.visible = false
            actor.image_alpha = 0.0
            actor.sprite_index = -4
            actor.image_speed = 0
            actor.image_index = 4.0
            actor.pVspeed = 0
            actor.pHspeed = 0
            Util.play_sound(gm.constants.wDoorClose or gm.constants.wChestClose or gm.constants.wChest1, 1.15, 1.3, actor.x, actor.y)
            pcall(function()
                if gm.constants.oEfDust1 then
                    gm.instance_create(actor.x, actor.y + 6, gm.constants.oEfDust1)
                end
            end)
        end

    -- FASE 2: BAJO TIERRA (Totalmente oculto, con movimiento rapido y espera)
    elseif d.vent_phase == "submerged" then
        actor.visible = false
        actor.image_alpha = 0.0
        actor.sprite_index = -4
        actor.image_speed = 0

        -- Control de movimiento bajo tierra
        local move_dir = 0
        if (actor.moveLeft and actor.moveLeft > 0) or Util.bool(gm.keyboard_check(37)) or Util.bool(gm.keyboard_check(65)) then
            move_dir = -1
        end
        if (actor.moveRight and actor.moveRight > 0) or Util.bool(gm.keyboard_check(39)) or Util.bool(gm.keyboard_check(68)) then
            move_dir = 1
        end

        if move_dir ~= 0 then
            actor.image_xscale = move_dir
            actor.pHspeed = move_dir * (actor.pHmax or 2.8) * 1.85
            if (Global._current_frame or 0) % 8 == 0 then
                pcall(function()
                    if gm.constants.oEfDust1 then
                        gm.instance_create(actor.x, actor.y + 8, gm.constants.oEfDust1)
                    end
                end)
            end
        else
            actor.pHspeed = 0
            -- Sutil indicacion de polvo cada 25 frames para que el jugador recuerde donde esta parado
            if (Global._current_frame or 0) % 25 == 0 then
                pcall(function()
                    if gm.constants.oEfDust1 then
                        gm.instance_create(actor.x, actor.y + 8, gm.constants.oEfDust1)
                    end
                end)
            end
        end

        d.submerged_frames = (d.submerged_frames or 0) + 1
        d.vent_timer = d.vent_timer - 1

        -- Deteccion de salida:
        -- 1. Si salta (Barra espaciadora o salto en mando)
        -- 2. Si vuelve a pulsar la habilidad (C, Shift, LShift o clics)
        -- 3. Si se agota el tiempo maximo bajo tierra (6.0 segundos = 360 frames)
        local request_exit = false
        if d.vent_timer <= 0 then
            request_exit = true
        elseif d.submerged_frames >= 20 then -- al menos ~0.33s bajo tierra para evitar activacion accidental al entrar
            local jump_hit = false
            local action_hit = false

            -- Teclado: Salto
            if Util.bool(gm.keyboard_check_pressed(32)) then
                jump_hit = true
            end

            -- Teclado / Ratón: Reactivar habilidad o ataque
            if Util.bool(gm.keyboard_check_pressed(67))   -- C
                or Util.bool(gm.keyboard_check_pressed(16))  -- Shift
                or Util.bool(gm.keyboard_check_pressed(160)) -- LShift
                or Util.bool(gm.keyboard_check_pressed(90))  -- Z
                or Util.bool(gm.keyboard_check_pressed(88))  -- X
                or Util.bool(gm.mouse_check_button_pressed(1)) then
                action_hit = true
            end

            -- Input de salto de RoRR (detectando pulsacion de cambio 0 -> 1)
            local cur_jump = (actor.key_jump and Util.bool(actor.key_jump)) or false
            if cur_jump and not d.prev_jump then
                jump_hit = true
            end
            d.prev_jump = cur_jump

            -- Gamepad (comprobando conexion y envolviendo en Util.bool para evitar evaluar 0.0 como true)
            pcall(function()
                if gm.gamepad_is_connected and Util.bool(gm.gamepad_is_connected(0)) and gm.gamepad_button_check_pressed then
                    for _, btn in ipairs({ 32769, 32770, 32771, 32772 }) do
                        if Util.bool(gm.gamepad_button_check_pressed(0, btn)) then
                            jump_hit = true
                            break
                        end
                    end
                end
            end)

            if jump_hit or action_hit then
                request_exit = true
            end
        end

        if request_exit then
            d.vent_phase = "emerging"
            actor.visible = true
            actor.image_alpha = 1.0     -- Vuelve a verse la animacion
            actor.sprite_index = sprite_shoot3
            actor.image_index = 4.8     -- Inicia la animacion de salir de la trampilla (Frames 5 a 7)
            actor.image_speed = 0.18    -- Velocidad clara y visible de salida
            actor.shadow = false
            actor.invisible = false
            actor:screen_shake(7)

            -- Salto impulsado hacia arriba saliendo de la tuberia (estilo Mario Bros)
            actor.pVspeed = -5.4
            local dir = (actor.image_xscale >= 0) and 1 or -1
            if move_dir ~= 0 then
                actor.pHspeed = move_dir * (actor.pHmax or 2.8) * 1.25
            else
                actor.pHspeed = dir * 1.1
            end

            -- Estallido y apertura de la trampilla
            Util.play_sound(gm.constants.wDoorOpen or gm.constants.wChestOpen or gm.constants.wChest1, 1.25, 1.1, actor.x, actor.y)
            actor:fire_explosion(actor.x, actor.y, 130, 80, 3.2, gm.constants.sEfExplosion, gm.constants.sNone, true)
            pcall(function()
                if gm.constants.oEfDust1 then
                    gm.instance_create(actor.x, actor.y + 6, gm.constants.oEfDust1)
                end
            end)

            -- Aturdimiento a enemigos en la zona
            local victims = Search and Search.in_radius and Search.in_radius(actor.x, actor.y, 120) or {}
            for _, foe in ipairs(victims) do
                if foe.team ~= actor.team and Instance.exists(foe) then
                    if foe.actor_set_stunned then
                        pcall(function() foe:actor_set_stunned(90) end)
                    elseif foe.stunned ~= nil then
                        foe.stunned = true
                    end
                end
            end

            -- Golpe de emboscada por la espalda
            Util.play_sound(gm.constants.wCut, 1.35, 0.85, actor.x, actor.y)
            local atk = actor:fire_explosion(actor.x + dir * 28, actor.y, 80, 50, 5.0, -4, gm.constants.sSparksCrit, true)
            if atk and atk.attack_info then
                atk.attack_info.critical = true
                atk.attack_info.damage_color = Color.from_rgb(255, 15, 15)
            end
        end

    -- FASE 3: SALIENDO DE LA TRAMPILLA (Frames 5 a 7 se ven enteros en el aire en pleno salto de Mario)
    elseif d.vent_phase == "emerging" then
        actor.sprite_index = sprite_shoot3
        actor.visible = true
        actor.image_alpha = 1.0
        actor.image_speed = 0.18

        -- Al completar el fotograma final de la animacion de salida
        if actor.image_index >= 7.6 then
            d.vent_phase = nil
            actor.visible = true
            actor.image_alpha = 1.0
            actor.image_speed = 1.0
            actor.shadow = false
            actor.invisible = false
            actor:skill_util_reset_activity_state()
            if actor.state == stateUtility.value then
                actor:set_state(actor.state_default or 0)
            end
        end
    end
end)

Callback.add(stateUtility.on_exit, function(actor, data)
    local d = get_actor_data(actor)
    actor.invincible = 0
    actor.visible = true
    actor.image_alpha = 1.0
    actor.image_speed = 1.0
    actor.shadow = false
    actor.invisible = false
    d.vent_phase = nil
end)

-- ----------------------------------------------------------------------------
-- HABILIDAD 4 (V): Reunion de Emergencia (Emergency Meeting / Ejection Vote)
-- ----------------------------------------------------------------------------
local special = impostor:get_skills(Skill.Slot.SPECIAL)[1]
if not special then
    special = Skill.new("impostorSpecial")
    impostor:add_skill(Skill.Slot.SPECIAL, special)
end

local specialS = Skill.new("impostorSpecialBoosted")
specialS.sprite = sprite_skill_vscepter
specialS.subimage = 0
specialS.cooldown = 11 * 60    -- 11 segundos
specialS.damage = 14.0         -- 1400% con Ancient Scepter
specialS.require_key_press = true
specialS.token_name = "Ejected into Space"
specialS.token_description = "The vote is unanimous. &yFreezes and stuns all nearby enemies for 3.5s&!, &ginstantly resets Pistol and Vent cooldowns&!, and grants 3s invulnerability. Instantly &yEJECTS non-boss enemies below 35% HP into the void&!, or crushes bosses for &y1400% execute damage&! with a 400% void vortex."

special.sprite = sprite_skill_v
special.subimage = 0
special.cooldown = 12 * 60     -- 12 segundos
special.damage = 8.0           -- 800% dano de ejecucion
special.require_key_press = true
special.upgrade_skill = specialS
special.token_name = "Emergency Meeting"
special.token_description = "Hit the panic button! &yFreezes and stuns all nearby enemies for 3.0s&!, &ginstantly resets Pistol and Vent cooldowns&!, and grants 2.5s invulnerability. The highest-HP enemy on screen is voted out for &y800% execution damage&! and a massive explosion."

local stateSpecial = ActorState.new("impostorStateSpecial")

Callback.add(special.on_activate, function(actor, skill, slot)
    -- Sonido autentico de alarma de emergencia de la reunion
    Util.play_sound(SND_EMERGENCY, 1.1, 1.0, actor.x, actor.y)
    actor:set_state(stateSpecial)
end)

Callback.add(specialS.on_activate, function(actor, skill, slot)
    -- Sonido autentico de alarma de emergencia de la reunion
    Util.play_sound(SND_EMERGENCY, 1.1, 1.0, actor.x, actor.y)
    actor:set_state(stateSpecial)
end)

Callback.add(stateSpecial.on_enter, function(actor, data)
    actor.sprite_index = sprite_shoot4
    actor.image_index = 0
    actor.image_speed = 0.25
    local d = get_actor_data(actor)
    d.imp_voted = false
    local scepter_item = Item.find("ancientScepter")
    d.imp_has_scepter = (scepter_item and actor:item_count(scepter_item) > 0) or false
end)

Callback.add(stateSpecial.on_step, function(actor, data)
    actor.sprite_index = sprite_shoot4
    actor.image_speed = 0.25
    local d = get_actor_data(actor)

    -- Mantener al impostor firme al golpear el boton
    actor.pHspeed = (actor.pHspeed or 0) * 0.1

    -- Frame 2: Golpetazo al gran boton rojo de emergencia
    if not d.imp_voted and actor.image_index >= 2.0 then
        d.imp_voted = true
        actor:screen_shake(12)

        -- Golpe seco al boton de emergencia
        Util.play_sound(gm.constants.wPunch or gm.constants.wHit, 1.4, 0.9, actor.x, actor.y)
        Util.chat("<color=#FF2020>[REUNIÓN DE EMERGENCIA]</color> ¡" .. (actor.user_name or "Impostor") .. " ha pulsado el botón de emergencia!")

        -- REINICIO DE HABILIDADES (Panic Button / Reset)
        -- En Among Us la reunion reinicia el estado y salva al jugador de cualquier peligro
        pcall(function() actor:refresh_skill(1) end) -- Secundaria (Pistola)
        pcall(function() actor:refresh_skill(2) end) -- Utilidad (Trampilla / Vent)
        if actor.skills then
            pcall(function() if actor.skills[2] then actor.skills[2].cooldown = 0 end end)
            pcall(function() if actor.skills[3] then actor.skills[3].cooldown = 0 end end)
        end
        actor.invincible = math.max(actor.invincible, 150) -- 2.5s de invulnerabilidad garantizada

        -- 1. Congelar / Aturdir a todos los enemigos en 850px durante 3.0s (180 ticks)
        local all_enemies = Instance.find_all(gm.constants.pEnemy)
        local target = nil
        local max_hp = -1

        for _, foe in ipairs(all_enemies) do
            if foe.team ~= actor.team and Instance.exists(foe) then
                local dist = math.sqrt((foe.x - actor.x)^2 + (foe.y - actor.y)^2)
                if dist <= 850 then
                    -- Aturdimiento masivo y frenado en seco
                    if foe.actor_set_stunned then
                        pcall(function() foe:actor_set_stunned(180) end)
                    elseif foe.stunned ~= nil then
                        foe.stunned = true
                    end
                    foe.pHspeed = 0

                    -- Buscar al enemigo con mayor vida (Boss / Elite / el mas sospechoso)
                    if type(foe.hp) == "number" and foe.hp > max_hp then
                        max_hp = foe.hp
                        target = foe
                    end
                end
            end
        end

        -- 2. Ejecucion y votacion contra el mas sospechoso / peligroso
        if target and Instance.exists(target) then
            local is_boss = (GM.actor_is_boss and GM.actor_is_boss(target)) or false
            local threshold = (target.maxhp or 100) * 0.35

            -- Efectos visuales de ejecucion centrados en el culpable (rojo critico letal)
            pcall(function()
                if gm.constants.oEfDust1 then
                    gm.instance_create(target.x, target.y - 10, gm.constants.oEfDust1)
                end
            end)

            if d.imp_has_scepter and not is_boss and target.hp <= threshold then
                -- EXPULSION AL ESPACIO (Ancient Scepter)
                Util.chat("<color=#FF4040>¡" .. (target.user_name or "Sospechoso") .. " fue expulsado al espacio exterior! (0 Impostores restantes)</color>")
                actor:fire_direct(target, 99999, 270, target.x, target.y, gm.constants.sSparksCrit, true)
                actor:fire_explosion(target.x, target.y, 180, 110, 4.0, gm.constants.sEfExplosion, gm.constants.sSparksCrit, true)
            else
                local dmg = d.imp_has_scepter and 14.0 or 8.0
                Util.chat("<color=#FFAA20>[VOTACIÓN]</color> ¡" .. (target.user_name or "Sospechoso") .. " recibe la máxima sospecha! (" .. math.floor(dmg * 100) .. "% Daño).")
                actor:fire_direct(target, dmg, 270, target.x, target.y, gm.constants.sSparksCrit, true)
                actor:fire_explosion(target.x, target.y, 160, 100, 3.0, gm.constants.sEfExplosion, gm.constants.sSparksCrit, true)
            end
        else
            -- Si no habia sospechosos en rango, la reunion concede adrenalina y sigilo extendido
            actor.invincible = math.max(actor.invincible, 180)
            Util.chat("<color=#50FF50>[REUNIÓN DE EMERGENCIA]</color> No hay sospechosos cerca. Enfriamientos reiniciados e invulnerabilidad activada.")
        end
    end

    if actor.image_index >= 5.0 then
        actor:skill_util_reset_activity_state()
        if actor.state == stateSpecial.value then
            actor:set_state(actor.state_default or 0)
        end
    end
end)

Callback.add(stateSpecial.on_exit, function(actor, data)
    actor.image_speed = 1.0
end)

-- ----------------------------------------------------------------------------
-- Registro en el sistema de busqueda y catalogo de contenido
-- ----------------------------------------------------------------------------
if Search and Search.register_cut_content then
    Search.register_cut_content("impostor", {
        name     = "Among Us Impostor",
        survivor = impostor,
        icon     = sprite_portrait,
        tags     = { "survivor", "among_us", "impostor", "crewmate", "custom_survivor" }
    })
end

RCC_IMPOSTOR = impostor
log.info("[RestoredCutContent] Superviviente Impostor (Among Us) registrado exitosamente.")
return impostor
