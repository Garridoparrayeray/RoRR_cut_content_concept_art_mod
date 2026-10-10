-- ============================================================================
-- util.lua
-- Funciones compartidas por todos los modulos de RestoredCutContent
-- ============================================================================

local Util = RCC_UTIL or {}   -- misma tabla aunque el fichero se ejecute de nuevo

-- GameMaker devuelve 1.0 / 0.0 en lugar de booleanos (0.0 es "true" en Lua)
function Util.is_true(value)
    return value == true or value == 1.0 or value == 1
end

function Util.play_sound(snd, volume, pitch, x, y)
    if not snd then return end
    pcall(function()
        gm.sound_play_networked(snd, volume or 1.0, pitch or 1.0, x or 0, y or 0)
    end)
end

function Util.chat(message)
    pcall(function()
        gm.chat_add_message(message)
    end)
end

-- Efectos de rotura de un altar: cristal/piedra, explosion, esquirlas y temblor
function Util.break_effects(shrine)
    Util.play_sound(gm.constants.wGlass or gm.constants.wDrop, 1.0, 0.75, shrine.x, shrine.y)
    Util.play_sound(gm.constants.wChest1, 1.0, 0.85, shrine.x, shrine.y)

    pcall(function()
        if gm.constants.oEfExplosion then
            gm.instance_create(shrine.x, shrine.y - 30, gm.constants.oEfExplosion)
        end
        if gm.constants.oEfSparks then
            gm.instance_create(shrine.x - 12, shrine.y - 20, gm.constants.oEfSparks)
            gm.instance_create(shrine.x + 12, shrine.y - 20, gm.constants.oEfSparks)
        end
        shrine:screen_shake(5)
    end)
end

-- Devuelve la lista de constantes de GameMaker que existen realmente.
-- Evita los huecos nil que cortan los ipairs en las tablas de enemigos.
function Util.resolve_constants(names)
    local list = {}
    for _, name in ipairs(names) do
        local value = gm.constants[name]
        if value then
            table.insert(list, value)
        end
    end
    return list
end

function Util.pick(list, fallback)
    if not list or #list == 0 then return fallback end
    return list[gm.irandom_range(1, #list)]
end

-- Ajusta una instancia al suelo solido (oB): sube si esta enterrada, baja si flota
function Util.snap_to_ground(inst, max_drop, max_lift)
    if not inst or not Instance.exists(inst) then return end
    max_drop = max_drop or 80
    max_lift = max_lift or 40

    pcall(function()
        local solid = gm.constants.oB
        local original_y = inst.y

        local lifted = 0
        while lifted < max_lift and Util.is_true(inst:place_meeting(inst.x, inst.y, solid)) do
            inst.y = inst.y - 1
            lifted = lifted + 1
        end

        local dropped = 0
        while dropped < max_drop and not Util.is_true(inst:place_meeting(inst.x, inst.y + 1, solid)) do
            inst.y = inst.y + 1
            dropped = dropped + 1
        end

        -- Sin suelo debajo (abismo): restaurar la posicion original
        if dropped >= max_drop then
            inst.y = original_y
        end
    end)
end

-- Crea un unico altar del objeto dado, lejos del jugador.
-- Primero intenta el Director nativo; si falla, busca una plataforma oB libre.
-- configure(inst) se ejecuta sobre cada altar presente al terminar.
function Util.spawn_shrine_naturally(object_id, player, min_distance, configure)
    local director = gm._mod_game_getDirector()
    if not director or not Instance.exists(director) then
        director = Instance.find(gm.constants.oDirectorControl)
    end

    local room_width = 3000
    pcall(function()
        room_width = gm._mod_room_get_current_width()
    end)
    local margin = math.floor(min_distance / 2)

    -- Metodo 1: Director
    if director and Instance.exists(director) then
        local attempts = 0
        while Instance.count(object_id) == 0 and attempts < 32 do
            local ok = pcall(function()
                director:mapobject_spawn(object_id, 4, nil, nil, nil, nil, gm.constants.oB,
                    margin, room_width - margin, nil, nil, nil, nil, attempts > 16)
            end)
            if not ok then break end
            attempts = attempts + 1
        end
    end

    -- Metodo 2: plataforma oB aleatoria lejos del jugador
    if Instance.count(object_id) == 0 then
        local blocks = Instance.find_all(gm.constants.oB)
        for _ = 1, 60 do
            if #blocks == 0 then break end
            local block = blocks[gm.irandom_range(1, #blocks)]
            if block and Instance.exists(block) then
                local x = block.x + 16
                local y = block.y
                local far_enough = (not player) or math.abs(x - player.x) > min_distance
                local free_above = gm.position_meeting(x, y - 40, gm.constants.oB) == 0.0
                if far_enough and free_above and y > 120 then
                    local inst = gm.instance_create(x, y, object_id)
                    if inst and Instance.exists(inst) then
                        break
                    end
                end
            end
        end
    end

    for _, inst in ipairs(Instance.find_all(object_id)) do
        if Instance.exists(inst) then
            configure(inst)
        end
    end
end

-- Jugador mas cercano a un punto (o nil si no hay jugadores)
function Util.nearest_player(x, y)
    local best, best_dist = nil, math.huge
    for _, player in ipairs(Instance.find_all(gm.constants.oP)) do
        local dx, dy = player.x - x, player.y - y
        local dist = dx * dx + dy * dy
        if dist < best_dist then
            best, best_dist = player, dist
        end
    end
    return best
end

-- Cache de ids de elite resueltos por nombre (los ids numericos no son fiables)
local elite_ids = nil

local function scan_elites()
    elite_ids = {}
    for id = 0, 24 do
        local ok, identifier = pcall(function()
            return Elite.wrap(id).identifier
        end)
        if ok and type(identifier) == "string" then
            elite_ids[string.lower(identifier)] = id
        end
    end

    local found = {}
    for name, id in pairs(elite_ids) do
        table.insert(found, name .. "=" .. tostring(id))
    end
    log.info("[RestoredCutContent] Elites detectados: " .. table.concat(found, ", "))
end

function Util.elite_id(name, fallback)
    if not elite_ids then scan_elites() end
    return elite_ids[name] or fallback
end

RCC_UTIL = Util

return Util
