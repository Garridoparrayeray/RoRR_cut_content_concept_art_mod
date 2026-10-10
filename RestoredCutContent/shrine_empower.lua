-- ============================================================================
-- shrine_empower.lua
-- Restaura y transforma oShrineEmpower (ID 625, Sprite sShrineEmpower)
-- Altar de Empoderamiento Sagrado (Concept Art & Contenido Descartado)
-- ============================================================================

local shrine_spawned_this_stage = false
local SHRINE_OBJ = gm.constants.oShrineEmpower or 625
local SHRINE_SPRITE = gm.constants.sShrineEmpower

-- Almacén de estado en Lua para los altares de empoderamiento
local empower_data = {}

local function get_empower_data(shrine)
    local s_id = shrine.id
    if not empower_data[s_id] then
        empower_data[s_id] = {
            uses_left = 2,
            active_time = 0,
            state = "idle",      -- "idle", "glowing", "spent"
            glow_timer = 0
        }
    end
    return empower_data[s_id]
end

-- ============================================================================
-- 1. CREACIÓN DEL BUFF: BENDICIÓN DE EMPODERAMIENTO
-- ============================================================================
local buff_empower = nil
pcall(function()
    buff_empower = Buff.new("restored_cut_content", "blessing_empower")
    if buff_empower then
        buff_empower.max_stack = 2
        buff_empower.is_timed = true
        buff_empower.show_icon = false

        -- Modificadores de estadísticas mientras el buff está activo
        buff_empower:add_callback("onPostStatRecalc", function(actor, stack)
            if not actor or not Instance.exists(actor) then return end
            pcall(function()
                actor.damage = actor.damage * (1 + 0.35 * stack)
                actor.attack_speed = actor.attack_speed * (1 + 0.30 * stack)
                actor.critical_chance = actor.critical_chance + (20 * stack)
                actor.pHmax = actor.pHmax * (1 + 0.25 * stack)
            end)
        end)

        -- Rayo Sagrado / Daño bonus en impacto
        buff_empower:add_callback("onAttackHit", function(actor, victim, stack, hit_info)
            if not actor or not victim or not Instance.exists(victim) then return end
            if gm.random(1.0) < 0.25 then
                pcall(function()
                    if gm.constants.oEfCircle then
                        gm.instance_create(victim.x, victim.y, gm.constants.oEfCircle)
                    end
                    if gm.constants.wLevelUp then
                        gm.sound_play_networked(gm.constants.wLevelUp, 0.5, 1.8, victim.x, victim.y)
                    end
                    local extra_dmg = (actor.damage or 10) * (0.50 * stack)
                    if victim.hp then
                        victim.hp = math.max(0, victim.hp - extra_dmg)
                    end
                end)
            end
        end)
        log.info("[RestoredCutContent] Buff blessing_empower registrado con éxito.")
    end
end)

-- Sonido seguro
local function play_sound_safe(snd, vol, pitch, x, y)
    if snd then
        pcall(function()
            gm.sound_play_networked(snd, vol or 1.0, pitch or 1.0, x or 0, y or 0)
        end)
    end
end

-- ============================================================================
-- 2. SNAP TO GROUND
-- ============================================================================
local function snap_to_ground(inst, max_drop, max_lift)
    if not inst or not Instance.exists(inst) then return end
    pcall(function()
        if not inst.place_meeting then return end
        local original_y = inst.y

        -- 1. Si está flotando sobre el vacío, bajarlo hasta tocar bloque oB
        if not inst:place_meeting(inst.x, inst.y + 1, gm.constants.oB) then
            for dy = 1, (max_drop or 80) do
                if inst:place_meeting(inst.x, inst.y + dy, gm.constants.oB) then
                    inst.y = inst.y + (dy - 1)
                    return
                end
            end
        end

        -- 2. Si está enterrado dentro de un bloque sólido, subirlo al ras
        if inst:place_meeting(inst.x, inst.y, gm.constants.oB) then
            for dy = 1, (max_lift or 40) do
                if not inst:place_meeting(inst.x, inst.y - dy, gm.constants.oB) then
                    inst.y = inst.y - dy + 1
                    return
                end
            end
            inst.y = original_y
        end
    end)
end

-- ============================================================================
-- 3. FUNCIÓN PARA CREAR EL ALTAR DE EMPODERAMIENTO
-- ============================================================================
local function spawn_empower_shrine_at(x, y)
    local shrine = gm.instance_create(x, y, SHRINE_OBJ)
    if shrine and Instance.exists(shrine) then
        shrine.active = 0
        shrine.use_max = 1
        shrine.cost = 0
        shrine.cost_type = 0
        shrine.visible = true
        shrine.image_index = 0
        shrine.image_speed = 0

        if SHRINE_SPRITE then
            shrine.sprite_index = SHRINE_SPRITE
        end

        pcall(function()
            if gm.interactable_init_cost then
                gm.interactable_init_cost(shrine.id, 0, 0)
            end
        end)

        snap_to_ground(shrine, 80, 40)
        get_empower_data(shrine)
        log.info(string.format("[RestoredCutContent] Altar de Empoderamiento creado en (%.1f, %.1f) - Gratuito (1 uso)", shrine.x, shrine.y))
        return shrine
    else
        log.error("[RestoredCutContent] Error al crear instancia de oShrineEmpower!")
        return nil
    end
end

-- ============================================================================
-- 4. GENERACIÓN NATURAL EN EL ESCENARIO (LEJOS DEL JUGADOR)
-- ============================================================================
local function spawn_natural_empower_shrine(player)
    local director = gm._mod_game_getDirector() or Instance.find(gm.constants.oDirectorControl)
    local w = 3000
    pcall(function()
        if gm._mod_room_get_current_width then
            w = gm._mod_room_get_current_width()
        end
    end)

    local spawned = false

    -- Método 1: Intentar con el director nativo
    if director and Instance.exists(director) then
        local attempts = 0
        while Instance.count(SHRINE_OBJ) == 0 and attempts < 32 do
            local ok = pcall(function()
                director:mapobject_spawn(SHRINE_OBJ, 4, nil, nil, nil, nil, gm.constants.oB, 200, w - 200, nil, nil, nil, nil, attempts > 16)
            end)
            if not ok then break end
            attempts = attempts + 1
        end
        if Instance.count(SHRINE_OBJ) > 0 then
            spawned = true
            log.info("[RestoredCutContent] Altar de Empoderamiento generado por el Director.")
        end
    end

    -- Método 2: Fallback buscando una plataforma oB lejana
    if not spawned and Instance.count(SHRINE_OBJ) == 0 then
        local blocks = Instance.find_all(gm.constants.oB)
        if #blocks > 0 then
            for _ = 1, 60 do
                local b = blocks[gm.irandom_range(1, #blocks)]
                if b and Instance.exists(b) then
                    local bx = b.x + 16
                    local by = b.y
                    local dist = player and math.abs(bx - player.x) or 999
                    if dist > 450 and by > 120 then
                        local free_above = (gm.position_meeting(bx, by - 40, gm.constants.oB) == 0.0)
                        if free_above then
                            local s = spawn_empower_shrine_at(bx, by)
                            if s then
                                spawned = true
                                log.info(string.format("[RestoredCutContent] Altar de Empoderamiento generado en plataforma (%.1f, %.1f)", s.x, s.y))
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    -- Configuración estándar para cualquier altar de empoderamiento presente
    local shrines = Instance.find_all(SHRINE_OBJ)
    for _, s in ipairs(shrines) do
        if s and Instance.exists(s) then
            s.visible = true
            if SHRINE_SPRITE then
                s.sprite_index = SHRINE_SPRITE
            end
            snap_to_ground(s, 80, 40)
            get_empower_data(s)
        end
    end
end

-- Resetear bandera al cambiar de fase
Callback.add(Callback.TYPE.onStageStart, "EmpowerShrine_ResetStage", function()
    shrine_spawned_this_stage = false
    empower_data = {}
    log.info("[RestoredCutContent] Fase iniciada. Altar de Empoderamiento listo.")
end)

-- Bucle de spawn orgánico en la fase
Callback.add(Callback.TYPE.postStep, "EmpowerShrine_SpawnLoop", function()
    if gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    if #players == 0 then return end
    local player = players[1]

    if not shrine_spawned_this_stage then
        shrine_spawned_this_stage = true
        spawn_natural_empower_shrine(player)
    end
end)

-- ============================================================================
-- 5. ANIMACIÓN, ACTIVACIÓN Y GESTIÓN DEL HALO DORADO
-- ============================================================================
Callback.add(Callback.TYPE.postStep, "EmpowerShrine_AnimationAndLogic", function()
    local shrines = Instance.find_all(SHRINE_OBJ)
    for _, shrine in ipairs(shrines) do
        local data = get_empower_data(shrine)

        -- --------------------------------------------------------------------
        -- A) Interacción del jugador (Pulsa E - Gratuito)
        -- --------------------------------------------------------------------
        if (shrine.active == 1 or shrine.active == 2) and data.state == "idle" then
            data.state = "glowing"
            data.glow_timer = 0
            shrine.active = 2 -- Bloquear para evitar reuso

            -- Localizar al jugador activador
            local activator = shrine.activator or Instance.find_nearest(shrine.x, shrine.y, gm.constants.oP)
            if activator and Instance.exists(activator) then
                -- Aplicar buff de 45 segundos (45 * 60 = 2700 frames)
                if buff_empower then
                    pcall(function()
                        activator:buff_apply(buff_empower, 45 * 60)
                    end)
                end

                -- Efectos celestiales de activación
                play_sound_safe(gm.constants.wLevelUp, 1.0, 1.1, shrine.x, shrine.y)
                if gm.constants.oEfCircle then
                    gm.instance_create(shrine.x, shrine.y - 48, gm.constants.oEfCircle)
                end

                gm.chat_add_message("<y>[Altar de Empoderamiento]</c> ¡Has recibido la Bendición Sagrada! (+35% Daño, +30% Vel. Ataque, +20% Crítico durante 45s)")
                log.info("[RestoredCutContent] Bendición de Empoderamiento otorgada al jugador.")
            end

            -- Encender el halo dorado (animación hacia fotograma 2)
            shrine.image_index = 1.0
            shrine.image_speed = 0.15
        end

        -- --------------------------------------------------------------------
        -- B) Estado Resplandeciente (Halo dorado activo y pulsante)
        -- --------------------------------------------------------------------
        if data.state == "glowing" then
            data.glow_timer = data.glow_timer + 1

            -- Mantener el halo oscilando radiantemente en su apogeo
            if shrine.image_index >= 2.5 then
                shrine.image_index = 1.6
            end

            -- Emitir destellos dorados suaves hacia arriba periódicamente
            if data.glow_timer % 20 == 0 then
                pcall(function()
                    if gm.constants.oEfSparks then
                        gm.instance_create(shrine.x, shrine.y - 50, gm.constants.oEfSparks)
                    end
                end)
            end

            -- Tras 3 segundos de resplandor (180 frames):
            -- ¡EL ALTAR SE QUIEBRA / ROMPE!
            if data.glow_timer >= 180 then
                data.state = "breaking"
                shrine.image_index = 3.0
                shrine.image_speed = 0.15

                -- Efectos de ruptura: Sonido de cristal / fractura de roca
                play_sound_safe(gm.constants.wGlass or gm.constants.wDrop, 1.0, 0.75, shrine.x, shrine.y)
                play_sound_safe(gm.constants.wChest1, 1.0, 0.85, shrine.x, shrine.y)

                -- Destello y escombros
                pcall(function()
                    if gm.constants.oEfExplosion then
                        gm.instance_create(shrine.x, shrine.y - 30, gm.constants.oEfExplosion)
                    end
                    if gm.constants.oEfSparks then
                        gm.instance_create(shrine.x - 12, shrine.y - 20, gm.constants.oEfSparks)
                        gm.instance_create(shrine.x + 12, shrine.y - 20, gm.constants.oEfSparks)
                    end
                    if shrine.screen_shake then
                        shrine:screen_shake(5)
                    end
                end)

                gm.chat_add_message("<y>[Altar de Empoderamiento]</c> ¡El altar canaliza toda su energía sagrada y se quiebra en pedazos!")
                log.info("[RestoredCutContent] Altar de Empoderamiento quebrado tras completar su bendicion.")
            end
        end

        -- --------------------------------------------------------------------
        -- C) Estado Quebrado / Inerte: Queda en ruinas agrietadas
        -- --------------------------------------------------------------------
        if data.state == "breaking" then
            if shrine.image_index >= 6.0 then
                shrine.image_index = 6.0
                shrine.image_speed = 0
                shrine.active = 3 -- Inerte permanentemente
            end
        end
    end
end)

-- ============================================================================
-- 6. EFECTO VISUAL EN EL JUGADOR DURANTE EL BUFF
-- ============================================================================
Callback.add(Callback.TYPE.postStep, "EmpowerShrine_PlayerAura", function()
    local players = Instance.find_all(gm.constants.oP)
    for _, player in ipairs(players) do
        if buff_empower and player:buff_stack_count(buff_empower) > 0 then
            -- Partículas doradas suaves alrededor del jugador cada 15 frames
            if gm.variable_global_get("time") and (gm.variable_global_get("time") % 15 == 0) then
                pcall(function()
                    if gm.constants.oEfSparks then
                        gm.instance_create(player.x + gm.random_range(-8, 8), player.y - 12, gm.constants.oEfSparks)
                    end
                end)
            end
        end
    end
end)

log.info("[RestoredCutContent] Modulo de Altar de Empoderamiento (shrine_empower.lua) cargado con exito.")

