-- ============================================================================
-- debug_cheats.lua
-- Herramientas de depuración seguras para RestoredCutContent
-- F5: Invocar Altar de Empoderamiento (oShrineEmpower) a tus pies
-- F6: Modo Dios (Invencible + HP al máximo) + 0 Cooldowns en habilidades y equipo
-- F7: Eliminar a todos los enemigos actuales (para probar drops instantáneos)
-- F8: Añadir 1000 de oro
-- ============================================================================

local god_mode_enabled = false

local function play_sound_safe(snd, vol, pitch, x, y)
    if snd then
        pcall(function()
            gm.sound_play_networked(snd, vol or 1.0, pitch or 1.0, x or 0, y or 0)
        end)
    end
end

-- Bucle de teclado y cheats en cada frame
Callback.add(Callback.TYPE.postStep, "DebugCheats_Loop", function()
    if gm._mod_net_isClient() then return end

    local players = Instance.find_all(gm.constants.oP)
    if #players == 0 then return end
    local player = players[1]

    -- ------------------------------------------------------------------------
    -- F5 (116): Spawn Altar de Empoderamiento (oShrineEmpower / ID 625)
    -- ------------------------------------------------------------------------
    if gm.keyboard_check_pressed(116) == 1.0 then -- 116 = F5
        local ground_y = player.bbox_bottom or player.y
        local shrine_obj = gm.constants.oShrineEmpower or 625
        local shrine = gm.instance_create(player.x + 60, ground_y, shrine_obj)
        if shrine and Instance.exists(shrine) then
            shrine.active = 0
            shrine.use_max = 1
            shrine.cost = 0
            shrine.cost_type = 0
            shrine.visible = true
            shrine.image_index = 0
            shrine.image_speed = 0
            if gm.constants.sShrineEmpower then
                shrine.sprite_index = gm.constants.sShrineEmpower
            end
            pcall(function()
                if gm.interactable_init_cost then
                    gm.interactable_init_cost(shrine.id, 0, 0)
                end
            end)
            pcall(function()
                for dy = 1, 80 do
                    if shrine:place_meeting(shrine.x, shrine.y + dy, gm.constants.oB) then
                        shrine.y = shrine.y + (dy - 1)
                        break
                    end
                end
            end)
            gm.chat_add_message("<g>[DEBUG F5]</c> Altar de Empoderamiento creado a tus pies. ¡Pulsa E para probar la bendicion y su fractura!")
            log.info("[RestoredCutContent] Debug F5: Altar de Empoderamiento creado.")
        end
    end

    -- ------------------------------------------------------------------------
    -- F6 (117): Alternar Modo Dios y 0 Cooldowns
    -- ------------------------------------------------------------------------
    if gm.keyboard_check_pressed(117) == 1.0 then -- 117 = F6
        god_mode_enabled = not god_mode_enabled
        if god_mode_enabled then
            gm.chat_add_message("<g>[MODO DIOS & 0 CDS: ACTIVADO]</c> Salud infinita y habilidades sin recarga.")
            play_sound_safe(gm.constants.wLevelUp, 1.0, 1.2, player.x, player.y)
            log.info("[RestoredCutContent] Debug: God Mode y 0 Cooldowns ACTIVADO.")
        else
            gm.chat_add_message("<r>[MODO DIOS: DESACTIVADO]</c> Estado normal restaurado.")
            pcall(function()
                player.invincible = 0
            end)
            log.info("[RestoredCutContent] Debug: God Mode DESACTIVADO.")
        end
    end

    -- ------------------------------------------------------------------------
    -- F7 (118): Matar / Eliminar a todos los enemigos limpiamente (sin congelar mobs)
    -- ------------------------------------------------------------------------
    if gm.keyboard_check_pressed(118) == 1.0 then -- 118 = F7
        local count = 0
        local enemies = Instance.find_all(gm.constants.pEnemy)
        local act = Actor.wrap(player)
        for _, enemy in ipairs(enemies) do
            pcall(function()
                if enemy and Instance.exists(enemy) then
                    -- 1. Intentar infligir daño letal a través del Actor del jugador
                    if act and act.fire_direct then
                        act:fire_direct(enemy, 999999, 0, nil, nil, gm.constants.sNone, false)
                    end
                    -- 2. Asegurar destrucción limpia de la instancia para evitar cualquier congelamiento
                    if enemy and Instance.exists(enemy) then
                        enemy:destroy()
                    end
                    count = count + 1
                end
            end)
        end
        gm.chat_add_message("<y>[DEBUG F7]</c> Enemigos eliminados limpiamente: " .. tostring(count))
        log.info("[RestoredCutContent] Debug F7: " .. tostring(count) .. " enemigos eliminados limpiamente.")
    end

    -- ------------------------------------------------------------------------
    -- F8 (119): Otorgar +1000 de oro
    -- ------------------------------------------------------------------------
    if gm.keyboard_check_pressed(119) == 1.0 then -- 119 = F8
        pcall(function()
            -- 1. Soltar orbes de oro directamente sobre el jugador para que se absorban al instante
            if gm.drop_gold_and_exp then
                gm.drop_gold_and_exp(player.x, player.y - 12, 1000, 0)
            end
            -- 2. Llamar a script nativo si existe
            if gm.add_gold then
                gm.add_gold(1000)
            end
            -- 3. Actualizar contadores del HUD
            local huds = Instance.find_all(gm.constants.oHUD)
            for _, hud in ipairs(huds) do
                if hud and Instance.exists(hud) then
                    if hud.add_gold then hud:add_gold(1000) end
                    if hud.gold then hud.gold = hud.gold + 1000 end
                end
            end
            -- 4. Modificar variables de actor
            if player.gold then player.gold = player.gold + 1000 end
            if player.money then player.money = player.money + 1000 end

            play_sound_safe(gm.constants.wCoin or gm.constants.wChest1, 1.0, 1.0, player.x, player.y)
            gm.chat_add_message("<y>[DEBUG F8]</c> +$1000 oro otorgado.")
            log.info("[RestoredCutContent] Debug F8: +1000 oro otorgado.")
        end)
    end

    -- ------------------------------------------------------------------------
    -- Efectos continuos de Modo Dios y 0 Cooldowns (100% SEGURO, sin punteros C++)
    -- ------------------------------------------------------------------------
    if god_mode_enabled and player and Instance.exists(player) then
        pcall(function()
            -- 1. Invencibilidad y Salud Infinita
            player.invincible = 60
            if player.maxhp then
                player.hp = player.maxhp
            end

            -- 2. Habilidades sin enfriamiento usando el método oficial del Toolkit
            local actor = Actor.wrap(player)
            if actor then
                for slot = 0, 3 do
                    pcall(function()
                        actor:refresh_skill(slot)
                    end)
                end
            end

            -- 3. Objeto de Equipo (Equipment) sin tiempo de recarga
            if player.equipment_cooldown and player.equipment_cooldown > 0 then
                player.equipment_cooldown = 0
            end
        end)
    end
end)

log.info("[RestoredCutContent] Modulo de depuracion (debug_cheats.lua) cargado. F5=EmpowerShrine, F6=GodMode/0CD, F7=KillMobs, F8=Gold.")
