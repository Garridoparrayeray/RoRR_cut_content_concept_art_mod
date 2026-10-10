-- ============================================================================
-- shrine_challenge.lua
-- Transforma oShrine6 en un Altar de Desafío de Combate Dinámico (estilo RoR2)
-- Correcciones y mejoras:
-- 1. Se mantiene AZUL pulsante durante todo el combate (fotogramas 5.5 a 7.8).
--    Una vez eliminada la horda, el azul se disipa (frames 8 a 10) y se apaga.
-- 2. Dificultad escalada: En Fase 1 / Drizzle NUNCA spawnea Blighted (bicho negro gordo)
--    ni Gólems pesados. Solo Lemurians, Wisps y élites elementales suaves (Fuego/Rayo/Hielo).
-- 3. Los enemigos muertos se purgan de la lista de seguimiento; el contador nunca sube.
-- 4. Snap to ground milimétrico garantizado.
-- ============================================================================

local shrine_spawned_this_stage = false
local SHRINE_OBJ = gm.constants.oShrine6 or 624

-- Almacén puro de estado en Lua indexado por el ID nativo del altar
local challenge_data = {}

local function get_challenge(shrine)
    local s_id = shrine.id
    if not challenge_data[s_id] then
        challenge_data[s_id] = {
            started = false,
            spawned = false,
            fight_active = false,
            completed = false,
            fading_out = false,
            spawn_timer = 0,
            mobs = {},
            alive_count = 0,
            initial_count = 0,
            threat = 1.0,
            stage_num = 1
        }
    end
    return challenge_data[s_id]
end

-- Sonidos seguros nativos
local SND_CHARGE = gm.constants.wChainLightning or gm.constants.wShrine1
local SND_STRIKE = gm.constants.wLightning
local SND_WIN    = gm.constants.wLevelUp

local function play_sound_safe(snd, vol, pitch, x, y)
    if snd then
        pcall(function()
            gm.sound_play_networked(snd, vol or 1.0, pitch or 1.0, x or 0, y or 0)
        end)
    end
end

-- ============================================================================
-- FUNCIÓN DE AJUSTE MILIMÉTRICO AL SUELO (SNAP TO GROUND)
-- ============================================================================
local function snap_to_ground(inst, max_drop, max_lift)
    if not inst or not Instance.exists(inst) then return end
    pcall(function()
        if not inst.place_meeting then return end
        local original_y = inst.y

        -- 1. Si está incrustado dentro de oB (bloques sólidos), subirlo píxel a píxel
        local lifted = 0
        while lifted < (max_lift or 40) and (inst:place_meeting(inst.x, inst.y, gm.constants.oB) == 1.0) do
            inst.y = inst.y - 1
            lifted = lifted + 1
        end

        -- 2. Si está en el aire (no toca oB justo debajo), bajarlo píxel a píxel
        local dropped = 0
        while dropped < (max_drop or 80) and (inst:place_meeting(inst.x, inst.y + 1, gm.constants.oB) ~= 1.0) do
            inst.y = inst.y + 1
            dropped = dropped + 1
        end

        -- 3. Si al bajarlo quedó 1px metido, ajuste final
        while inst:place_meeting(inst.x, inst.y, gm.constants.oB) == 1.0 do
            inst.y = inst.y - 1
        end

        -- Si no encontró suelo en max_drop (abismo o no tiene colisión), restaurar original_y
        if dropped >= (max_drop or 80) then
            inst.y = original_y
        end
    end)
end

-- ============================================================================
-- FUNCIÓN AUXILIAR PARA COMPROBAR SI UN ENEMIGO ESTÁ VIVO
-- ============================================================================
local function is_mob_alive(mob)
    if not mob or not Instance.exists(mob) then
        return false
    end
    -- Si el motor marca muerte
    if mob.dead and (mob.dead == true or mob.dead == 1 or mob.dead == 1.0) then
        return false
    end
    -- Si tiene hp numérico y está muerto o agonizando
    if mob.hp and type(mob.hp) == "number" and mob.hp <= 0 then
        return false
    end
    return true
end

-- ============================================================================
-- GENERACIÓN DE BESTIARIO CANÓNICO SEGÚN BIOMA EXACTO DE MAPA
-- ============================================================================
local function get_stage_pool(stage_num)
    local room_name = ""
    pcall(function()
        local r = gm.variable_global_get("room")
        if type(r) == "number" and r >= 0 then
            room_name = string.lower(tostring(gm.room_get_name(r)))
        end
    end)

    log.info(string.format("[RestoredCutContent] Seleccionando pool para room: '%s', stage_num: %d", room_name, stage_num))

    -- Detección directa por bioma de mapa si room_name contiene nombres canónicos
    if room_name:find("lake") or room_name:find("dried") then
        return {
            name = "Lago Seco (Fase 1)",
            tier = 1,
            light = { gm.constants.oLizard, gm.constants.oWisp },
            medium = { gm.constants.oCrab, gm.constants.oLizard },
            heavy = { gm.constants.oLizard }
        }
    elseif room_name:find("forest") or room_name:find("desolate") then
        return {
            name = "Bosque Desolado (Fase 1)",
            tier = 1,
            light = { gm.constants.oLizard, gm.constants.oWisp },
            medium = { gm.constants.oSpitter, gm.constants.oLizard },
            heavy = { gm.constants.oLizard }
        }
    elseif room_name:find("damp") or room_name:find("cavern") then
        return {
            name = "Cavernas Húmedas (Fase 2)",
            tier = 2,
            light = { gm.constants.oLizard, gm.constants.oWisp },
            medium = { gm.constants.oClay, gm.constants.oMush },
            heavy = { gm.constants.oGolem }
        }
    elseif room_name:find("meadow") or room_name:find("sky") then
        return {
            name = "Pradera Celestial (Fase 2)",
            tier = 2,
            light = { gm.constants.oLizard, gm.constants.oJelly },
            medium = { gm.constants.oClay, gm.constants.oSpitter },
            heavy = { gm.constants.oGolem }
        }
    elseif room_name:find("sunken") or room_name:find("tomb") then
        return {
            name = "Tumbas Hundidas (Fase 3)",
            tier = 3,
            light = { gm.constants.oLizard, gm.constants.oClay },
            medium = { gm.constants.oGolem, gm.constants.oSpitter },
            heavy = { gm.constants.oWispB, gm.constants.oBison }
        }
    elseif room_name:find("valley") or room_name:find("ancient") then
        return {
            name = "Valle Antiguo (Fase 3)",
            tier = 3,
            light = { gm.constants.oLizard, gm.constants.oClay },
            medium = { gm.constants.oGolem, gm.constants.oBison },
            heavy = { gm.constants.oWispB, gm.constants.oBison }
        }
    elseif room_name:find("magma") or room_name:find("barrack") then
        return {
            name = "Cuartel de Magma (Fase 4)",
            tier = 4,
            light = { gm.constants.oSpider, gm.constants.oClay },
            medium = { gm.constants.oImpM, gm.constants.oGolem },
            heavy = { gm.constants.oWispB, gm.constants.oBison }
        }
    elseif room_name:find("hive") or room_name:find("cluster") then
        return {
            name = "Colmena (Fase 4)",
            tier = 4,
            light = { gm.constants.oSpider, gm.constants.oBug },
            medium = { gm.constants.oImpM, gm.constants.oGolem },
            heavy = { gm.constants.oWispB }
        }
    elseif room_name:find("temple") or room_name:find("elder") then
        return {
            name = "Templo de los Ancianos (Fase 5)",
            tier = 5,
            light = { gm.constants.oChild, gm.constants.oImpM },
            medium = { gm.constants.oGuard, gm.constants.oGolem },
            heavy = { gm.constants.oGolemG, gm.constants.oWispB }
        }
    else
        -- Fallback por número de stage (ej. __newroom20 es Fase 1)
        if stage_num == 1 then
            return {
                name = "Fase 1 (Inicial)",
                tier = 1,
                light = { gm.constants.oLizard, gm.constants.oWisp },
                medium = { gm.constants.oSpitter, gm.constants.oLizard },
                heavy = { gm.constants.oLizard } -- Estrictamente Lemurian, CERO gólems/jefes
            }
        elseif stage_num == 2 then
            return {
                name = "Fase 2",
                tier = 2,
                light = { gm.constants.oLizard, gm.constants.oWisp, gm.constants.oJelly },
                medium = { gm.constants.oClay, gm.constants.oMush },
                heavy = { gm.constants.oGolem }
            }
        elseif stage_num == 3 then
            return {
                name = "Fase 3",
                tier = 3,
                light = { gm.constants.oLizard, gm.constants.oClay },
                medium = { gm.constants.oGolem, gm.constants.oSpitter },
                heavy = { gm.constants.oWispB, gm.constants.oBison }
            }
        elseif stage_num == 4 then
            return {
                name = "Fase 4",
                tier = 4,
                light = { gm.constants.oSpider, gm.constants.oBug },
                medium = { gm.constants.oImpM, gm.constants.oGolem },
                heavy = { gm.constants.oWispB, gm.constants.oBison }
            }
        else
            return {
                name = "Fase 5+",
                tier = 5,
                light = { gm.constants.oChild, gm.constants.oImpM },
                medium = { gm.constants.oGuard, gm.constants.oGolem },
                heavy = { gm.constants.oGolemG, gm.constants.oWispB }
            }
        end
    end
end

local function pick_from(tbl)
    local valid = {}
    for _, item in ipairs(tbl or {}) do
        if item ~= nil then table.insert(valid, item) end
    end
    if #valid == 0 then return gm.constants.oLizard end
    return valid[gm.irandom_range(1, #valid)]
end

-- Resetear bandera y datos al cambiar de fase
Callback.add(Callback.TYPE.onStageStart, "ChallengeShrine_ResetStage", function()
    shrine_spawned_this_stage = false
    challenge_data = {}
    log.info("[RestoredCutContent] Nueva fase iniciada. Altar de Desafio listo.")
end)

-- ----------------------------------------------------------------------------
-- Función para crear el altar sobre el suelo
-- ----------------------------------------------------------------------------
local function spawn_shrine_at(x, y, is_silent)
    local shrine = gm.instance_create(x, y, SHRINE_OBJ)
    if shrine and Instance.exists(shrine) then
        shrine.cost = 0
        shrine.cost_type = 0 -- Gratuito
        shrine.active = 0    -- Listo para interactuar
        shrine.use_max = 1
        shrine.visible = true
        shrine.image_index = 0
        shrine.image_speed = 0

        if gm.constants.sShrine6 then
            shrine.sprite_index = gm.constants.sShrine6
        end

        -- Ajuste milimétrico al suelo de la plataforma
        snap_to_ground(shrine, 80, 40)

        get_challenge(shrine)

        if not is_silent then
            gm.chat_add_message("<y>[Altar de Desafío]</c> ¡Altar de combate generado con éxito! Pulsa E para comenzar.")
        end
        log.info(string.format("[RestoredCutContent] Altar creado con exito en (%.1f, %.1f)", shrine.x, shrine.y))
        return shrine
    else
        log.error("[RestoredCutContent] Error al crear instancia de oShrine6!")
        return nil
    end
end

-- ----------------------------------------------------------------------------
-- Generación natural del altar en el escenario (lejos del jugador)
-- ----------------------------------------------------------------------------
local function spawn_natural_shrine(player)
    local director = gm._mod_game_getDirector() or Instance.find(gm.constants.oDirectorControl)
    local w = 3000
    pcall(function()
        if gm._mod_room_get_current_width then
            w = gm._mod_room_get_current_width()
        end
    end)

    local spawned = false

    -- Método 1: Intentar con director:mapobject_spawn nativo del motor
    if director and Instance.exists(director) then
        local attempts = 0
        while Instance.count(SHRINE_OBJ) == 0 and attempts < 32 do
            local ok = pcall(function()
                director:mapobject_spawn(SHRINE_OBJ, 4, nil, nil, nil, nil, gm.constants.oB, 150, w - 150, nil, nil, nil, nil, attempts > 16)
            end)
            if not ok then break end
            attempts = attempts + 1
        end
        if Instance.count(SHRINE_OBJ) > 0 then
            spawned = true
            log.info("[RestoredCutContent] Altar generado naturalmente mediante el Director.")
        end
    end

    -- Método 2: Fallback buscando una plataforma oB aleatoria en el mapa lejos del jugador
    if not spawned and Instance.count(SHRINE_OBJ) == 0 then
        local blocks = Instance.find_all(gm.constants.oB)
        if #blocks > 0 then
            for _ = 1, 60 do
                local b = blocks[gm.irandom_range(1, #blocks)]
                if b and Instance.exists(b) then
                    local bx = b.x + 16
                    local by = b.y
                    local dist = player and math.abs(bx - player.x) or 999
                    if dist > 400 and by > 120 then
                        local free_above = (gm.position_meeting(bx, by - 40, gm.constants.oB) == 0.0)
                        if free_above then
                            local s = spawn_shrine_at(bx, by, true)
                            if s then
                                spawned = true
                                log.info(string.format("[RestoredCutContent] Altar generado en plataforma lejana (%.1f, %.1f)", s.x, s.y))
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Configuración estándar para cualquier altar en el mapa
    local shrines = Instance.find_all(SHRINE_OBJ)
    for _, s in ipairs(shrines) do
        if s and Instance.exists(s) then
            s.cost = 0
            s.cost_type = 0
            s.active = 0
            s.use_max = 1
            s.visible = true
            s.image_index = 0
            s.image_speed = 0
            if gm.constants.sShrine6 then
                s.sprite_index = gm.constants.sShrine6
            end
            snap_to_ground(s, 80, 40)
            get_challenge(s)
        end
    end
end

-- ----------------------------------------------------------------------------
-- 1. Generación natural del altar en el escenario
-- ----------------------------------------------------------------------------
Callback.add(Callback.TYPE.postStep, "ChallengeShrine_MainLoop", function()
    if gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    if #players == 0 then return end
    local player = players[1]

    -- Generación natural del altar en el escenario (lejos del jugador)
    if not shrine_spawned_this_stage then
        shrine_spawned_this_stage = true
        spawn_natural_shrine(player)
    end
end)

-- ----------------------------------------------------------------------------
-- 2. Animación Azul Celestial + Combate en Vivo + Finalización Dinámica
-- ----------------------------------------------------------------------------
Callback.add(Callback.TYPE.postStep, "ChallengeShrine_AnimationAndSpawn", function()
    local shrines = Instance.find_all(SHRINE_OBJ)
    for _, shrine in ipairs(shrines) do
        local data = get_challenge(shrine)

        -- --------------------------------------------------------------------
        -- Paso A: El jugador pulsa E (Inicio de carga)
        -- --------------------------------------------------------------------
        if (shrine.active == 1 or shrine.active == 2) and not data.started and not data.completed then
            data.started = true
            shrine.active = 2 -- Bloquear para evitar reuso

            -- Iniciar animación de carga eléctrica azul (fotogramas 0 a 7)
            if gm.constants.sShrine6 then
                shrine.sprite_index = gm.constants.sShrine6
            end
            shrine.image_index = 0
            shrine.image_speed = 0.2

            play_sound_safe(SND_CHARGE, 0.9, 1.1, shrine.x, shrine.y)
            gm.chat_add_message("<y>[Altar de Desafío]</c> ¡El altar canaliza energía celestial...!")
            log.info("[RestoredCutContent] Desafio activado por el jugador.")
        end

        -- --------------------------------------------------------------------
        -- Paso B: Impacto del rayo azul en fotograma 7 -> Creación de la horda
        -- --------------------------------------------------------------------
        if data.started and not data.spawned then
            if shrine.image_index >= 6.5 then
                data.spawned = true
                data.fight_active = true
                data.spawn_timer = 0

                -- Fijar el altar en su punto álgido azul
                shrine.image_index = 7.0
                shrine.image_speed = 0.12

                -- Trueno de impacto celestial
                play_sound_safe(SND_STRIKE, 1.0, 1.0, shrine.x, shrine.y)

                -- ------------------------------------------------------------
                -- CÁLCULO DINÁMICO DE DIFICULTAD
                -- ------------------------------------------------------------
                local director = gm._mod_game_getDirector() or Instance.find(gm.constants.oDirectorControl)
                local stages_passed = 0
                local enemy_buff = 1.0

                if director and Instance.exists(director) then
                    if director.stages_passed then
                        stages_passed = math.floor(director.stages_passed)
                    end
                    if director.enemy_buff and type(director.enemy_buff) == "number" then
                        enemy_buff = math.max(1.0, director.enemy_buff)
                    end
                end

                local stage_num = stages_passed + 1
                local threat = (enemy_buff * 0.75) + (stages_passed * 1.1)

                -- Obtener pool estricto según la fase y mapa actual
                local current_pool = get_stage_pool(stage_num)
                local pool_tier = current_pool.tier or stage_num

                -- ------------------------------------------------------------
                -- SELECCIÓN DE ARQUETIPO DE OLEADA ADECUADO
                -- En Fase 1 (Drizzle o inicio), NUNCA permitir Brute ni Élite
                -- ------------------------------------------------------------
                local archetypes = {"swarm", "assault"}
                if pool_tier >= 2 and threat >= 2.5 then
                    table.insert(archetypes, "brute")
                end
                if pool_tier >= 3 and threat >= 3.0 then
                    table.insert(archetypes, "elite")
                end

                local chosen_archetype = archetypes[gm.irandom_range(1, #archetypes)]
                local wave_title = ""
                local mobs_plan = {}

                -- Detección de dificultad actual del juego (0 = Drizzle, 1 = Rainstorm, 2 = Monsoon)
                local current_difficulty = 1
                pcall(function()
                    if gm._mod_game_getDifficulty then
                        current_difficulty = gm._mod_game_getDifficulty()
                    end
                end)

                -- El élite Blighted (ID 6 - Negro / Sombra / Mini-boss) solo se permite:
                -- 1) Con un nivel de Amenaza (Threat) >= 4.5 (estrictamente a partir de 4.5, nunca en 3.0)
                -- 2) En Fase 3 o superior (stage_num >= 3)
                local allow_blighted = false
                if threat >= 4.5 and stage_num >= 3 then
                    allow_blighted = true
                end

                -- Tipos de élite canónicos elementales seguros (Fuego, Rayo, Hielo)
                local safe_elite_ids = {1, 2, 4}

                if chosen_archetype == "swarm" then
                    -- 1. ENJAMBRE: Monstruos ligeros de esta fase
                    wave_title = "¡Un Enjambre se ha manifestado!"
                    local count = (pool_tier == 1) and math.min(5, math.max(3, math.floor(3 + threat * 0.5)))
                                                   or math.min(8, math.max(4, math.floor(3 + threat * 0.9)))
                    local elite_chance = (pool_tier == 1) and 0.08 or math.min(0.30, 0.05 + threat * 0.05)

                    for i = 1, count do
                        local obj = (i <= math.floor(count * 0.8))
                                    and pick_from(current_pool.light)
                                    or pick_from(current_pool.medium)
                        local is_elite = (gm.random(1.0) < elite_chance)
                        table.insert(mobs_plan, {obj = obj, is_elite = is_elite})
                    end

                elseif chosen_archetype == "assault" then
                    -- 2. ASALTO: Combinación equilibrada de la fase
                    wave_title = "¡Un Escuadrón de Asalto te rodea!"
                    local count = (pool_tier == 1) and math.min(4, math.max(3, math.floor(2 + threat * 0.5)))
                                                   or math.min(6, math.max(3, math.floor(3 + threat * 0.8)))
                    local elite_chance = (pool_tier == 1) and 0.10 or math.min(0.40, 0.10 + threat * 0.07)

                    for i = 1, count do
                        local obj = (i % 2 == 1)
                                    and pick_from(current_pool.light)
                                    or pick_from(current_pool.medium)
                        local is_elite = (gm.random(1.0) < elite_chance)
                        table.insert(mobs_plan, {obj = obj, is_elite = is_elite})
                    end

                elseif chosen_archetype == "brute" then
                    -- 3. GUARDIA PESADA: Solo fases 2+
                    wave_title = "¡Una Guardia Pesada responde al desafío!"
                    local count = math.min(4, math.max(2, math.floor(2 + threat * 0.5)))
                    local elite_chance = math.min(0.50, 0.20 + threat * 0.08)

                    for i = 1, count do
                        local obj = (i == 1)
                                    and pick_from(current_pool.heavy)
                                    or pick_from(current_pool.medium)
                        local is_elite = (gm.random(1.0) < elite_chance)
                        table.insert(mobs_plan, {obj = obj, is_elite = is_elite})
                    end

                else
                    -- 4. PATRULLA DE ÉLITE: Solo fases 3+
                    wave_title = "¡Una Patrulla de Élite te acecha!"
                    local count = math.min(3, math.max(2, math.floor(2 + threat * 0.4)))

                    for i = 1, count do
                        local obj = (i == 1)
                                    and pick_from(current_pool.heavy)
                                    or pick_from(current_pool.medium)
                        table.insert(mobs_plan, {obj = obj, is_elite = true})
                    end
                end

                -- Aviso en chat
                gm.chat_add_message("<y>[Altar de Desafío]</c> " .. wave_title .. " (" .. tostring(#mobs_plan) .. " enemigos | " .. current_pool.name .. ")")
                log.info(string.format("[RestoredCutContent] Horda generada: %d enemigos (%s)", #mobs_plan, wave_title))

                -- ------------------------------------------------------------
                -- SPAWN A RAS DE SUELO (Fuera de la base de 96px del altar)
                -- ------------------------------------------------------------
                data.mobs = {}
                local ground_y = shrine.y -- La base del altar es el suelo exacto

                local blighted_spawned_in_wave = false

                local function apply_elite_status(mob_inst, is_elite_flag)
                    if is_elite_flag then
                        local chosen_elite
                        -- El Blighted solo puede aparecer si allow_blighted está activo (Amenaza >= 4.5),
                        -- con probabilidad (~35%) y como máximo 1 por oleada (nunca 100% garantizado)
                        if allow_blighted and not blighted_spawned_in_wave and (gm.random(1.0) < 0.35) then
                            chosen_elite = 6 -- Blighted (Sombra / Negro)
                            blighted_spawned_in_wave = true
                            gm.chat_add_message("<r>[Altar de Desafío]</c> ¡Una Aberración Umbría (Élite Sombra) acecha en el desafío!")
                            log.info("[RestoredCutContent] Aberracion Umbria (Blighted ID 6) invocada por probabilidad (Amenaza >= 4.5).")
                        else
                            chosen_elite = safe_elite_ids[gm.irandom_range(1, #safe_elite_ids)]
                        end
                        gm.elite_set(mob_inst, chosen_elite)
                    end
                end

                for i, entry in ipairs(mobs_plan) do
                    local is_flying = (entry.obj == gm.constants.oWisp or entry.obj == gm.constants.oWispB or entry.obj == gm.constants.oJelly)

                    -- Dispersión horizontal limpia a izquierda y derecha del altar
                    local side = (i % 2 == 0) and 1 or -1
                    local dist = 54 + (math.floor((i - 1) / 2) * 16)
                    dist = math.min(100, dist)

                    local sx = shrine.x + (side * dist)

                    if is_flying then
                        -- Enemigos voladores: flotan a media/alta altura sobre la estatua
                        local sy = ground_y - 75 - (i * 8)
                        local mob = gm.instance_create(sx, sy, entry.obj)
                        if mob and Instance.exists(mob) then
                            apply_elite_status(mob, entry.is_elite)
                            table.insert(data.mobs, mob)
                        end
                    else
                        -- Enemigos terrestres: primero spawn a ras de ground_y
                        local mob = gm.instance_create(sx, ground_y, entry.obj)
                        if mob and Instance.exists(mob) then
                            -- Si está dentro de una pared sólida, empujar hacia el altar
                            pcall(function()
                                local push = 0
                                while push < 40 and mob:place_meeting(mob.x, mob.y, gm.constants.oB) == 1.0 do
                                    mob.x = mob.x - (side * 2)
                                    push = push + 2
                                end
                            end)

                            -- Snap milimétrico al suelo
                            snap_to_ground(mob, 80, 40)

                            -- Si por alguna razón quedó en el aire o dentro de pared
                            pcall(function()
                                if mob:place_meeting(mob.x, mob.y, gm.constants.oB) == 1.0 or mob:place_meeting(mob.x, mob.y + 1, gm.constants.oB) ~= 1.0 then
                                    mob.x = shrine.x + (side * 52)
                                    mob.y = ground_y
                                    snap_to_ground(mob, 80, 40)
                                end
                            end)

                            apply_elite_status(mob, entry.is_elite)
                            table.insert(data.mobs, mob)
                        end
                    end
                end

                data.alive_count = #data.mobs
                data.initial_count = #data.mobs
                data.threat = threat
                data.stage_num = stage_num
                log.info(string.format("[RestoredCutContent] Total instancias creadas activas: %d", #data.mobs))
            end
        end

        -- --------------------------------------------------------------------
        -- Paso C: MANTENER EL ALTAR EN AZUL PULSANTE MIENTRAS DURE EL COMBATE
        -- --------------------------------------------------------------------
        if data.fight_active and not data.completed then
            -- Oscilar en bucle entre los fotogramas 5.5 y 7.6 (aura celestial azul radiante)
            if shrine.image_index >= 7.8 then
                shrine.image_index = 5.6
            elseif shrine.image_index < 5.6 then
                shrine.image_index = 5.6
            end
            shrine.image_speed = 0.12
        end

        -- --------------------------------------------------------------------
        -- Paso D: Comprobación continua de victoria y disipación del azul
        -- --------------------------------------------------------------------
        if data.started and data.spawned and data.fight_active and not data.completed then
            data.spawn_timer = data.spawn_timer + 1

            -- Periodo de gracia: esperar 60 fotogramas (1 segundo) antes de evaluar
            if data.spawn_timer >= 60 then
                -- Purga estricta: retirar permanentemente a los muertos para que la cuenta nunca suba
                local live_mobs = {}
                for _, mob in ipairs(data.mobs) do
                    if is_mob_alive(mob) then
                        table.insert(live_mobs, mob)
                    end
                end
                data.mobs = live_mobs
                local alive = #data.mobs

                -- Notificar al jugador si disminuyen los enemigos restantes
                if alive ~= data.alive_count then
                    data.alive_count = alive
                    if alive > 0 then
                        gm.chat_add_message("<y>[Altar de Desafío]</c> Enemigos restantes: " .. tostring(alive))
                        log.info(string.format("[RestoredCutContent] Progreso combate: %d enemigos restantes", alive))
                    end
                end

                -- Condición estricta de victoria: toda la horda eliminada
                if alive == 0 and (data.initial_count or 0) > 0 then
                    data.completed = true
                    data.fight_active = false
                    data.fading_out = true

                    -- Iniciar disipación del azul: avanza desde el fotograma 8 al 10
                    shrine.image_index = 8.0
                    shrine.image_speed = 0.25

                    -- Fanfarria de victoria
                    play_sound_safe(SND_WIN, 1.0, 1.0, shrine.x, shrine.y)
                    gm.chat_add_message("<g>[Altar de Desafío]</c> ¡Horda derrotada! El altar se apaga y entrega tu recompensa.")
                    log.info("[RestoredCutContent] Combate superado! El azul se disipa...")

                    -- ------------------------------------------------------------
                    -- RECOMPENSA ESCALADA SEGÚN EL PELIGRO SUPERADO
                    -- ------------------------------------------------------------
                    local threat = data.threat or 1.0
                    local stage_num = data.stage_num or 1
                    local reward_tier = Item.TIER.common

                    if threat < 2.2 and stage_num == 1 then
                        reward_tier = Item.TIER.common
                    elseif threat < 4.2 then
                        reward_tier = (gm.irandom_range(1, 2) == 1) and Item.TIER.uncommon or Item.TIER.common
                    elseif threat < 6.8 then
                        reward_tier = Item.TIER.uncommon
                    else
                        reward_tier = (gm.irandom_range(1, 3) == 1) and Item.TIER.rare or Item.TIER.uncommon
                    end

                    local reward_item = Item.get_random(reward_tier)
                    if reward_item then
                        reward_item:create(shrine.x, shrine.y - 32)
                    else
                        gm.instance_create(shrine.x, shrine.y - 16, gm.constants.oChest1)
                    end
                end
            end
        end

        -- --------------------------------------------------------------------
        -- Paso E: Final de disipación -> La estatua queda completamente inerte
        -- --------------------------------------------------------------------
        if data.fading_out and shrine.image_speed > 0 then
            if shrine.image_index >= 9.8 then
                shrine.image_speed = 0
                shrine.image_index = 10 -- Fotograma inerte y apagado
                data.fading_out = false
                log.info("[RestoredCutContent] Altar completamente apagado tras la victoria.")
            end
        end
    end
end)

log.info("[RestoredCutContent] Modulo de Altar de Desafio (shrine_challenge.lua) cargado con exito.")

