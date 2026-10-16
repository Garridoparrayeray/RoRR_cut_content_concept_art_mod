-- ============================================================================
-- debug_tools.lua  -  HERRAMIENTAS DE DESARROLLO Y PANEL DE PRUEBAS
--
-- Proporciona tanto atajos de teclado como un PANEL INTERACTIVO EN PANTALLA (ImGui)
-- para probar cada una de las caracteristicas restauradas e implementadas.
--
--   F1 / Boton        Equipar habilidades del Impostor (Among Us)
--   Mayus+F1 / Boton  Dar Ancient Scepter (Habilidad V: Expulsion al Espacio)
--   F2 / Boton        Dar Item KFL (Kentucky Fried Lemurian)
--   F3 / Boton        Spawnear Mono Espacial (Lemuriano)
--   F4 / Boton        Spawnear Roble Inquieto (Restless Oak)
--   F5 / Boton        Spawnear Altar de Empoderamiento (oShrineEmpower)
--   F6 / Boton        Modo Dios (Vida infinita, invulnerable, sin cooldowns)
--   F7 / Boton        Matar a todos los enemigos en pantalla
--   F8 / Boton        +1000 de Oro
--   F9 / Boton        Spawnear Altar de Desafio (oShrine6)
--   F10 / F11         Inspeccionar fotograma siguiente / anterior de altares
--   F12 / Boton       Spawnear Tardigrado (con Mayus, version Alfa)
--   H / Boton         Mostrar Emoticono flotante de Aplausos
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL

local KEY = { 
    F1 = 112, F2 = 113, F3 = 114, F4 = 115, F5 = 116, F6 = 117, 
    F7 = 118, F8 = 119, F9 = 120, F10 = 121, F11 = 122, F12 = 123, 
    SHIFT = 16, H = 72 
}

local GOLD_AMOUNT        = 1000
local LETHAL_COEFFICIENT = 1000000
local SHRINE_OFFSET_X    = 60
local SPAWN_OFFSET_X     = 150
local TARDIGRADE_OBJ     = gm.constants.oMacT
local MONITOR_FRAMES     = 1500
local MONITOR_INTERVAL   = 90

local god_mode = false
local show_dev_window = true

local function pressed(key)
    return Util.bool(gm.keyboard_check_pressed(key))
end

local function is_down(key)
    return Util.bool(gm.keyboard_check(key))
end

-- ----------------------------------------------------------------------------
-- 1. Trampas y Ventajas (God Mode, Kill All, Gold)
-- ----------------------------------------------------------------------------
local function toggle_god_mode(player)
    god_mode = not god_mode
    if god_mode then
        Util.chat("<g>[MODO DIOS]</c> Activado: vida infinita y sin cooldowns.")
    else
        player.invincible = 0
        Util.chat("<r>[MODO DIOS]</c> Desactivado.")
    end
end

local function apply_god_mode(player)
    player.invincible = 60
    if type(player.maxhp) == "number" then
        player.hp = player.maxhp
    end
    for slot = 0, 3 do
        pcall(function() player:refresh_skill(slot) end)
    end
    if type(player.equipment_cooldown) == "number" and player.equipment_cooldown > 0 then
        player.equipment_cooldown = 0
    end
end

local function kill_all_enemies(player)
    local killed = 0
    for _, enemy in ipairs(Instance.find_all(gm.constants.pEnemy)) do
        local ok = pcall(function()
            player:fire_direct(enemy, LETHAL_COEFFICIENT, 0, nil, nil, gm.constants.sNone, false)
        end)
        if ok then killed = killed + 1 end
    end
    Util.chat("<y>[DEV F7]</c> Enemigos eliminados: " .. killed)
end

local function add_gold(amount)
    for _, hud in ipairs(Instance.find_all(gm.constants.oHUD)) do
        if type(hud.gold) == "number" then
            hud.gold = hud.gold + amount
            Util.play_sound(gm.constants.wCoin or gm.constants.wChest1, 1.0, 1.0)
            Util.chat("<y>[DEV F8]</c> +$" .. amount)
            return true
        end
    end
    Util.chat("<r>[DEV F8]</c> No se encontro el HUD; oro no anadido.")
    return false
end

-- ----------------------------------------------------------------------------
-- 2. Habilidades de Supervivientes (Impostor & CHEF)
-- ----------------------------------------------------------------------------
local function equip_impostor_skills(player)
    local imp = RCC_IMPOSTOR or Survivor.find("impostor") or Survivor.find("restored_cut_content", "impostor")
    if not imp then
        Util.chat("<r>[DEV]</c> El superviviente Impostor no se encuentra cargado.")
        return
    end

    for slot = 0, 3 do
        local skills = imp:get_skills(slot)
        if skills and skills[1] then
            pcall(function()
                player:add_skill_override(slot, skills[1], 100)
            end)
        end
    end

    if imp.sprite_idle then
        pcall(function()
            player.sprite_idle = imp.sprite_idle
            player.sprite_walk = imp.sprite_walk
            player.sprite_jump = imp.sprite_jump
            player.sprite_jump_peak = imp.sprite_jump
            player.sprite_fall = imp.sprite_fall
            player.sprite_climb = imp.sprite_climb
            player.sprite_death = imp.sprite_death
            player.sprite_decoy = imp.sprite_idle
            player.sprite_spawn = imp.sprite_idle
            player.sprite_hit = imp.sprite_idle
            player.sprite_drown = imp.sprite_death
            player.sprite_shoot1 = imp.sprite_shoot1
            player.sprite_shoot2 = imp.sprite_shoot2
            player.sprite_shoot3 = imp.sprite_shoot3
            player.sprite_shoot4 = imp.sprite_shoot4
            player.sprite_shoot5 = imp.sprite_shoot4
            player.sprite_index2 = -4

            player.sprite_idle_half = -4
            player.sprite_walk_half = -4
            player.sprite_jump_half = -4
            player.sprite_jump_peak_half = -4
            player.sprite_fall_half = -4
        end)
    end

    Util.chat("<color=#FF3030>[DEV F1]</color> Habilidades del Impostor equipadas: Z (Punalada), X (Pistolazo), C (Vent), V (Reunion).")
    Util.play_sound(gm.constants.wAlarm or gm.constants.wChestOpen, 1.0, 1.0, player.x, player.y)
end

local function give_ancient_scepter(player)
    local scepter = Item.find("ancientScepter")
    if scepter then
        player:item_give(scepter, 1)
        Util.chat("<g>[DEV Mayus+F1]</c> Ancient Scepter entregado. Habilidad Especial potenciada: Expulsion al Espacio.")
        Util.play_sound(gm.constants.wChest1, 1.0, 1.2, player.x, player.y)
    end
end

local function equip_chef_ice_skill(player)
    local skill_ice = Skill.find("chef_ice_cube")
    if skill_ice then
        player:add_skill_override(Skill.Slot.SECONDARY, skill_ice, 100)
        Util.chat("<b>[DEV]</c> Habilidad descartada Cubo de Hielo (CHEF) equipada en la tecla X.")
        Util.play_sound(gm.constants.wChefShoot1 or gm.constants.wChest1, 1.0, 1.2, player.x, player.y)
    else
        Util.chat("<r>[DEV]</c> Habilidad chef_ice_cube no encontrada.")
    end
end

-- ----------------------------------------------------------------------------
-- 3. Items & Emoticonos
-- ----------------------------------------------------------------------------
local function give_kfl_item(player)
    local item_kfl = Item.find("item_kfl")
    if item_kfl then
        player:item_give(item_kfl, 1)
        Util.chat("<g>[DEV F2]</c> Item KFL entregado (Kentucky Fried Lemurian).")
        Util.play_sound(gm.constants.wChest1, 1.0, 1.0, player.x, player.y)
    else
        Util.chat("<r>[DEV F2]</c> Item item_kfl no encontrado.")
    end
end

local function play_emote(player)
    if Util.show_emote then
        Util.show_emote(player, "clapping")
        Util.chat("<y>[DEV H]</c> Emoticono de aplausos activado.")
    end
end

-- ----------------------------------------------------------------------------
-- 4. Enemigos Descartados (Mono Espacial, Roble Inquieto, Tardigrado)
-- ----------------------------------------------------------------------------
local function spawn_monkey(player)
    local obj = Object.find("Monkey")
    if obj then
        obj:create(player.x + 80, player.y)
        Util.chat("<g>[DEV F3]</c> Mono Espacial creado junto al jugador.")
    else
        Util.chat("<r>[DEV F3]</c> Objeto Monkey no encontrado.")
    end
end

local function spawn_restless_oak(player)
    local obj = Object.find("RestlessOak")
    if obj then
        obj:create(player.x + 100, player.y)
        Util.chat("<g>[DEV F4]</c> Roble Inquieto creado junto al jugador.")
    else
        Util.chat("<r>[DEV F4]</c> Objeto RestlessOak no encontrado.")
    end
end

local watched = nil
local watch_timer = 0
local last_sprite = nil
local last_player_hp = nil
local last_hp = nil

local function read_field(inst, field)
    local ok, value = pcall(function() return inst[field] end)
    if not ok then return "<error>" end
    return tostring(value)
end

local function sprite_name(inst)
    local ok, name = pcall(function() return gm.sprite_get_name(inst.sprite_index) end)
    if ok then return tostring(name) end
    return "?"
end

local function describe(inst)
    return string.format("pos=(%.0f,%.0f) sprite=%s frame=%s hp=%s/%s team=%s",
        inst.x, inst.y, sprite_name(inst), read_field(inst, "image_index"),
        read_field(inst, "hp"), read_field(inst, "maxhp"), read_field(inst, "team"))
end

local function spawn_tardigrade(player, force_alpha)
    if not TARDIGRADE_OBJ then
        Util.chat("<r>[DEV F12]</c> oMacT no existe en este juego.")
        return
    end

    local inst = gm.instance_create(player.x + SPAWN_OFFSET_X, player.y, TARDIGRADE_OBJ)
    if not inst or not Instance.exists(inst) then
        Util.chat("<r>[DEV F12]</c> No se pudo crear la instancia.")
        return
    end

    Util.snap_to_ground(inst, 80, 40)

    local is_alpha = force_alpha or is_down(KEY.SHIFT)
    local variant = is_alpha and "boss" or nil
    Util.tune_enemy(inst, TARDIGRADE_OBJ, variant)

    watched, watch_timer = inst, 0
    last_sprite, last_player_hp, last_hp = nil, nil, nil

    log.info("[DevTools] Tardigrado creado" .. (variant and " (ALFA)" or "") .. ": " .. describe(inst))
    if variant then
        Util.chat("<g>[DEV F12]</c> Tardigrado ALFA creado. El log registra su comportamiento durante 25 s.")
    else
        Util.chat("<g>[DEV F12]</c> Tardigrado creado (Mayus+F12 = Alfa). El log lo registra 25 s.")
    end
end

local function update_monitor()
    if not watched then return end
    watch_timer = watch_timer + 1

    if not Instance.exists(watched) then
        log.info(string.format("[DevTools] Tardigrado destruido tras %d frames.", watch_timer))
        watched = nil
        return
    end

    if watch_timer >= MONITOR_FRAMES then
        log.info(string.format("[DevTools] Monitor de tardigrado finalizado (%d frames). Estado final: %s",
            MONITOR_FRAMES, describe(watched)))
        watched = nil
        return
    end

    local current_sprite = watched.sprite_index
    local current_hp = watched.hp
    local player = Instance.find_all(gm.constants.oP)[1]
    local current_player_hp = player and Instance.exists(player) and player.hp or nil

    local changed = (current_sprite ~= last_sprite)
        or (current_hp ~= last_hp)
        or (current_player_hp ~= last_player_hp)
        or (watch_timer % MONITOR_INTERVAL == 0)

    if changed then
        local delta_hp = (last_hp and current_hp) and (current_hp - last_hp) or 0
        local delta_php = (last_player_hp and current_player_hp) and (current_player_hp - last_player_hp) or 0
        log.info(string.format("[DevTools][t=%4d] %s | dHP=%+.0f dPlayerHP=%+.0f",
            watch_timer, describe(watched), delta_hp, delta_php))
        last_sprite = current_sprite
        last_hp = current_hp
        last_player_hp = current_player_hp
    end
end

-- ----------------------------------------------------------------------------
-- 5. Altares Descartados (Empoderamiento & Desafio)
-- ----------------------------------------------------------------------------
local function spawn_empower(player)
    local hook = Util.dev_hooks.spawn_empower_shrine
    if not hook then
        Util.chat("<r>[DEV F5]</c> El modulo del altar de empoderamiento no esta cargado.")
        return
    end
    local shrine = hook(player.x + SHRINE_OFFSET_X, player.y)
    if shrine then
        Util.chat("<g>[DEV F5]</c> Altar de Empoderamiento creado ($" .. tostring(shrine.cost) .. " + vida). F8 da oro.")
    end
end

local function spawn_challenge(player)
    local hook = Util.dev_hooks.spawn_challenge_shrine
    if not hook then
        Util.chat("<r>[DEV F9]</c> El modulo del altar de desafio no esta cargado.")
        return
    end
    local shrine = hook(player.x - SHRINE_OFFSET_X, player.y)
    if shrine then
        Util.chat("<g>[DEV F9]</c> Altar de Desafio creado ($" .. tostring(shrine.cost) .. "). F8 da oro.")
    end
end

local function step_frame(player, direction)
    local best, best_dist = nil, math.huge
    for _, object_name in ipairs({ "oShrine6", "oShrineEmpower" }) do
        local object_id = gm.constants[object_name]
        if object_id then
            for _, shrine in ipairs(Instance.find_all(object_id)) do
                local dx, dy = shrine.x - player.x, shrine.y - player.y
                local dist = dx * dx + dy * dy
                if dist < best_dist then best, best_dist = shrine, dist end
            end
        end
    end
    if not best then
        Util.chat("<r>[FRAMES]</c> No hay altares en el mapa.")
        return
    end

    local count = math.floor(gm.sprite_get_number(best.sprite_index))
    local index = (math.floor(best.image_index) + direction) % count
    best.image_speed = 0
    best.image_index = index
    Util.chat(string.format("<y>[FRAMES]</c> %s: fotograma %d de %d",
        tostring(gm.sprite_get_name(best.sprite_index)), index, count - 1))
end

-- ----------------------------------------------------------------------------
-- 6. PANEL INTERACTIVO EN PANTALLA (ImGui)
-- ----------------------------------------------------------------------------
if gui then
    if gui.add_to_menu_bar then
        gui.add_to_menu_bar(function()
            if ImGui.Button("🛠️ Cut Content Panel") then
                show_dev_window = not show_dev_window
            end
        end)
    end

    if gui.add_imgui then
        gui.add_imgui(function()
            if not show_dev_window then return end

            local open, should_draw = ImGui.Begin("Restored Cut Content - Panel de Pruebas", true)
            if not open then
                show_dev_window = false
                ImGui.End()
                return
            end

            local player = Instance.find_all(gm.constants.oP)[1]
            if not player or not Instance.exists(player) then
                ImGui.TextColored(1.0, 0.4, 0.4, 1.0, "Entra a una partida para usar los controles.")
            else
                ImGui.TextColored(0.4, 1.0, 0.4, 1.0, "Superviviente conectado. Haz clic para probar:")

                -- SECCION 1: TRAMPAS Y GOD MODE
                ImGui.Separator()
                ImGui.Text("=== 1. TRAMPAS Y RECURSOS ===")
                local god_label = god_mode and "👑 Modo Dios: ACTIVADO [F6]" or "👑 Modo Dios: DESACTIVADO [F6]"
                if ImGui.Button(god_label) then
                    toggle_god_mode(player)
                end
                ImGui.SameLine()
                if ImGui.Button("💀 Matar Enemigos [F7]") then
                    kill_all_enemies(player)
                end
                ImGui.SameLine()
                if ImGui.Button("💰 +1000 Oro [F8]") then
                    add_gold(GOLD_AMOUNT)
                end

                -- SECCION 2: SUPERVIVIENTES Y HABILIDADES
                ImGui.Separator()
                ImGui.Text("=== 2. HABILIDADES (AMONG US & CHEF) ===")
                if ImGui.Button("🔪 Equipar Impostor (Z:Punalada, X:Pistolazo, C:Vent, V:Reunion) [F1]") then
                    equip_impostor_skills(player)
                end
                ImGui.SameLine()
                if ImGui.Button("🌌 Dar Ancient Scepter (Votacion al Espacio) [Mayus+F1]") then
                    give_ancient_scepter(player)
                end

                if ImGui.Button("🍧 Equipar Cubo de Hielo CHEF (Habilidad Descartada X)") then
                    equip_chef_ice_skill(player)
                end

                -- SECCION 3: ITEMS Y EMOTICONES
                ImGui.Separator()
                ImGui.Text("=== 3. ITEMS Y EMOTES ===")
                if ImGui.Button("🍗 Dar Kentucky Fried Lemurian (KFL) [F2]") then
                    give_kfl_item(player)
                end
                ImGui.SameLine()
                if ImGui.Button("👏 Mostrar Emoticono de Aplausos [H]") then
                    play_emote(player)
                end

                -- SECCION 4: ENEMIGOS DESCARTADOS
                ImGui.Separator()
                ImGui.Text("=== 4. SPAWN ENEMIGOS DESCARTADOS ===")
                if ImGui.Button("🐵 Mono Espacial [F3]") then
                    spawn_monkey(player)
                end
                ImGui.SameLine()
                if ImGui.Button("🌳 Roble Inquieto [F4]") then
                    spawn_restless_oak(player)
                end
                ImGui.SameLine()
                if ImGui.Button("🔬 Tardigrado [F12]") then
                    spawn_tardigrade(player, false)
                end
                ImGui.SameLine()
                if ImGui.Button("🧬 Tardigrado Alfa [Mayus+F12]") then
                    spawn_tardigrade(player, true)
                end

                -- SECCION 5: ALTARES DESCARTADOS
                ImGui.Separator()
                ImGui.Text("=== 5. ALTARES DESCARTADOS ===")
                if ImGui.Button("⚡ Altar Empoderamiento [F5]") then
                    spawn_empower(player)
                end
                ImGui.SameLine()
                if ImGui.Button("🏆 Altar Desafio [F9]") then
                    spawn_challenge(player)
                end

                -- SECCION 6: INSPECTOR DE ANIMACIONES
                ImGui.Separator()
                ImGui.Text("=== 6. INSPECTOR DE FOTOGRAMAS ===")
                if ImGui.Button("⏩ Frame Sig. Altar [F10]") then
                    step_frame(player, 1)
                end
                ImGui.SameLine()
                if ImGui.Button("⏪ Frame Ant. Altar [F11]") then
                    step_frame(player, -1)
                end
            end

            ImGui.End()
        end)
    end
end

-- ----------------------------------------------------------------------------
-- 7. Bucle de Teclas de Acceso Directo (Hotkeys)
-- ----------------------------------------------------------------------------
Callback.add(Callback.POST_STEP, function()
    if gm._mod_net_isClient and gm._mod_net_isClient() then return end

    local player = Instance.find_all(gm.constants.oP)[1]
    if not player or not Instance.exists(player) then return end

    local function guarded(fn, ...)
        local ok, err = pcall(fn, ...)
        if not ok then Util.log_once("DevTools", tostring(err)) end
    end

    if pressed(KEY.F1) then
        guarded(function()
            if is_down(KEY.SHIFT) then
                give_ancient_scepter(player)
            else
                equip_impostor_skills(player)
            end
        end)
    end

    if pressed(KEY.F2) then guarded(give_kfl_item, player) end
    if pressed(KEY.F3) then guarded(spawn_monkey, player) end
    if pressed(KEY.F4) then guarded(spawn_restless_oak, player) end
    if pressed(KEY.F5) then guarded(spawn_empower, player) end
    if pressed(KEY.F6) then guarded(toggle_god_mode, player) end
    if pressed(KEY.F7) then guarded(kill_all_enemies, player) end
    if pressed(KEY.F8) then guarded(add_gold, GOLD_AMOUNT) end
    if pressed(KEY.F9) then guarded(spawn_challenge, player) end
    if pressed(KEY.F10) then guarded(step_frame, player, 1) end
    if pressed(KEY.F11) then guarded(step_frame, player, -1) end
    if pressed(KEY.F12) then guarded(spawn_tardigrade, player) end
    if pressed(KEY.H) then guarded(play_emote, player) end

    if god_mode then guarded(apply_god_mode, player) end
    guarded(update_monitor)
end)

log.info("[DevTools] debug_tools.lua cargado con exito: Panel ImGui interactivo y teclas F1-F12 activas.")
