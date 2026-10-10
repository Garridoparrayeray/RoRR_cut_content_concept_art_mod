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

-- ----------------------------------------------------------------------------
-- Animacion: tinte, temblor y derrumbe progresivo
-- ----------------------------------------------------------------------------
Util.BLEND_NORMAL = 16777215   -- blanco: sprite sin tinte

-- GameMaker usa colores BGR en un entero
function Util.rgb(r, g, b)
    return r + g * 256 + b * 65536
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

-- Mezcla de dos colores {r, g, b}; t = 0 devuelve from, t = 1 devuelve to
function Util.mix_blend(from_rgb, to_rgb, t)
    return Util.rgb(
        math.floor(lerp(from_rgb[1], to_rgb[1], t)),
        math.floor(lerp(from_rgb[2], to_rgb[2], t)),
        math.floor(lerp(from_rgb[3], to_rgb[3], t)))
end

-- Tinte que oscila suavemente entre dos colores; period en frames
function Util.pulse_blend(frame, period, from_rgb, to_rgb)
    local t = (math.sin(frame * 2 * math.pi / period) + 1) / 2
    return Util.mix_blend(from_rgb, to_rgb, t)
end

function Util.spark_at(x, y)
    if gm.constants.oEfSparks then
        pcall(function()
            gm.instance_create(x, y, gm.constants.oEfSparks)
        end)
    end
end

-- Curvas de suavizado (t entre 0 y 1)
function Util.clamp01(t)
    return math.max(0, math.min(1, t))
end

function Util.ease_in(t)
    return t * t
end

function Util.ease_out(t)
    return 1 - (1 - t) * (1 - t)
end

function Util.ease_in_out(t)
    return t * t * (3 - 2 * t)
end

-- Temblor organico: dos senos desfasados mas un poco de ruido (sin saltos uniformes)
function Util.tremble(frame, intensity)
    return intensity * (0.6 * math.sin(frame * 0.9)
        + 0.4 * math.sin(frame * 2.3 + 1.7)
        + 0.25 * gm.random_range(-1, 1))
end

-- Chispa con probabilidad por frame, cerca de la estatua (y_min/y_max sobre el suelo)
function Util.random_spark(shrine, chance, spread, y_min, y_max)
    if gm.random(1.0) < chance then
        Util.spark_at(shrine.x + gm.random_range(-spread, spread), shrine.y - gm.random_range(y_min, y_max))
    end
end

-- Escala relativa (1 = tamano original) conservando el espejado del sprite
function Util.scale_to(shrine, data, sx, sy)
    if not data.base_xscale then
        data.base_xscale = shrine.image_xscale
        data.base_yscale = shrine.image_yscale
        if type(data.base_xscale) ~= "number" or data.base_xscale == 0 then data.base_xscale = 1 end
        if type(data.base_yscale) ~= "number" or data.base_yscale == 0 then data.base_yscale = 1 end
    end
    shrine.image_xscale = data.base_xscale * sx
    shrine.image_yscale = data.base_yscale * sy
end

function Util.scale_reset(shrine, data)
    if data.base_xscale then
        shrine.image_xscale = data.base_xscale
        shrine.image_yscale = data.base_yscale
        data.base_xscale = nil
        data.base_yscale = nil
    end
end

-- Sacude la x del altar alrededor de su posicion original
function Util.shake(shrine, data, intensity)
    if not data.base_x then data.base_x = shrine.x end
    data.shake_t = (data.shake_t or 0) + 1
    shrine.x = data.base_x + Util.tremble(data.shake_t, intensity)
end

function Util.shake_end(shrine, data)
    if data.base_x then
        shrine.x = data.base_x
        data.base_x = nil
    end
end

-- Un paso de derrumbe. cfg = { duration, frame_from, frame_to, max_shake, spark_interval }
-- Recorre los fotogramas despacio, con temblor y grietas cada vez mas frecuentes.
-- Devuelve true en el frame en que termina.
function Util.crumble_step(shrine, data, cfg)
    data.crumble_t = (data.crumble_t or 0) + 1
    local raw = math.min(1, data.crumble_t / cfg.duration)
    local progress = Util.ease_in(raw)   -- empieza suave y se acelera hacia el final

    -- Contencion: en los ultimos frames todo se queda quieto y la estatua se encoge
    -- un instante (anticipacion) justo antes del estallido
    local hold_frames = cfg.hold_frames or 8
    local frames_left = cfg.duration - data.crumble_t
    if frames_left < hold_frames then
        Util.shake_end(shrine, data)
        Util.scale_to(shrine, data, 0.97, 0.95)
    else
        Util.shake(shrine, data, cfg.max_shake * progress)
        -- Hinchazon con latido cada vez mas rapido
        local swell = 1 + 0.045 * progress + 0.012 * progress * math.sin(data.crumble_t * (0.25 + 0.6 * progress))
        Util.scale_to(shrine, data, swell, swell)
    end

    local span = cfg.frame_to - cfg.frame_from
    shrine.image_speed = 0
    shrine.image_index = cfg.frame_from + math.min(span, math.floor(raw * (span + 1)))

    -- Chispas: la probabilidad por frame crece con la sobrecarga
    local chance = (1 / cfg.spark_interval) * (1 + 3.5 * progress)
    Util.random_spark(shrine, chance, 16, 8, 60)

    if data.crumble_t >= cfg.duration then
        Util.shake_end(shrine, data)
        Util.scale_reset(shrine, data)
        data.crumble_t = nil
        return true
    end
    return false
end

-- Lluvia de cascotes (sEfRubble sobre oEfExplosion, que se autodestruye al acabar
-- la animacion) lanzados hacia arriba, mas nubes de polvo en la base
function Util.debris_burst(x, y, count)
    local rubble = gm.constants.sEfRubble
    local explosion = gm.constants.oEfExplosion
    if rubble and explosion then
        for _ = 1, count do
            pcall(function()
                local piece = gm.instance_create(x + gm.random_range(-24, 24), y - gm.random_range(15, 80), explosion)
                piece.sprite_index = rubble
                piece.hspeed = gm.random_range(-3.5, 3.5)
                piece.vspeed = -gm.random_range(2.0, 6.0)
                piece.gravity = 0.3
            end)
        end
    end

    for _, dust in ipairs({ gm.constants.oEfDust1, gm.constants.oEfDust2 }) do
        for _ = 1, 3 do
            pcall(function()
                gm.instance_create(x + gm.random_range(-30, 30), y - gm.random_range(0, 12), dust)
            end)
        end
    end
end

-- Reproduce de principio a fin la animacion nativa de muerte de un altar.
-- cfg = { sprite, frames, holds = {frames por fotograma}, default_hold, on_frame(frame) }
-- Devuelve true cuando llega al ultimo fotograma (los escombros), que se mantiene.
function Util.death_step(shrine, data, cfg)
    if not data.death_t then
        data.death_t = 0
        data.death_frame = -1
        shrine.sprite_index = cfg.sprite
        shrine.image_speed = 0
        shrine.image_blend = Util.BLEND_NORMAL
        Util.shake_end(shrine, data)
        Util.scale_reset(shrine, data)
    end
    data.death_t = data.death_t + 1

    local last = cfg.frames - 1
    local remaining, frame = data.death_t, last
    for i = 0, last do
        local hold = cfg.holds[i + 1] or cfg.default_hold
        if remaining <= hold then
            frame = i
            break
        end
        remaining = remaining - hold
    end

    shrine.image_index = frame
    shrine.image_speed = 0
    if frame ~= data.death_frame then
        data.death_frame = frame
        if cfg.on_frame then cfg.on_frame(frame) end
    end
    return frame >= last
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

-- Fase actual y nivel de amenaza (fases superadas + tiempo de partida)
function Util.read_difficulty()
    local stages_passed, enemy_buff = 0, 1.0
    local director = gm._mod_game_getDirector()
    if not director or not Instance.exists(director) then
        director = Instance.find(gm.constants.oDirectorControl)
    end
    if director and Instance.exists(director) then
        if type(director.stages_passed) == "number" then
            stages_passed = math.floor(director.stages_passed)
        end
        if type(director.enemy_buff) == "number" then
            enemy_buff = math.max(1.0, director.enemy_buff)
        end
    end
    local stage_num = stages_passed + 1
    local threat = (enemy_buff * 0.75) + (stages_passed * 1.1)
    return stage_num, threat
end

-- Coste en oro que crece con la amenaza: base * (1 + amenaza * por_amenaza)
function Util.gold_cost(base, per_threat)
    local _, threat = Util.read_difficulty()
    return math.floor(base * (1 + threat * per_threat))
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

-- ----------------------------------------------------------------------------
-- Generacion aleatoria de altares por mapa
-- ----------------------------------------------------------------------------

-- Posiciones x de los altares generados en esta fase (comun a todos los modulos,
-- para que no se amontonen entre si)
Util.shrine_marks = {}

Callback.add(Callback.TYPE.onStageStart, "RCC_Util_ResetMarks", function()
    Util.shrine_marks = {}
end)

-- Cuantos altares salen en este mapa. weights[i] es la probabilidad de generar i-1
-- (por ejemplo { 0.12, 0.43, 0.30, 0.15 } -> 0, 1, 2 o 3).
function Util.roll_count(weights)
    local roll, accumulated = gm.random(1.0), 0
    for i, weight in ipairs(weights) do
        accumulated = accumulated + weight
        if roll < accumulated then return i - 1 end
    end
    return #weights - 1
end

local function far_from_marks(x, gap)
    for _, mark in ipairs(Util.shrine_marks) do
        if math.abs(mark - x) < gap then return false end
    end
    return true
end

local function existing_ids(object_id)
    local ids = {}
    for _, inst in ipairs(Instance.find_all(object_id)) do
        ids[inst.id] = true
    end
    return ids
end

-- Metodo 1: Director nativo. Devuelve la instancia nueva o nil.
local function spawn_with_director(object_id, margin)
    local director = gm._mod_game_getDirector()
    if not director or not Instance.exists(director) then
        director = Instance.find(gm.constants.oDirectorControl)
    end
    if not director or not Instance.exists(director) then return nil end

    local room_width = 3000
    pcall(function()
        room_width = gm._mod_room_get_current_width()
    end)

    local before = existing_ids(object_id)
    local ok = pcall(function()
        director:mapobject_spawn(object_id, 4, nil, nil, nil, nil, gm.constants.oB,
            margin, room_width - margin, nil, nil, nil, nil, false)
    end)
    if not ok then return nil end

    for _, inst in ipairs(Instance.find_all(object_id)) do
        if not before[inst.id] then return inst end
    end
    return nil
end

-- Metodo 2: plataforma oB aleatoria libre, lejos del jugador y de otros altares
local function spawn_on_platform(object_id, player, min_distance, gap)
    local blocks = Instance.find_all(gm.constants.oB)
    if #blocks == 0 then return nil end

    for _ = 1, 60 do
        local block = blocks[gm.irandom_range(1, #blocks)]
        if block and Instance.exists(block) then
            local x = block.x + 16
            local y = block.y
            local far_from_player = (not player) or math.abs(x - player.x) > min_distance
            local free_above = gm.position_meeting(x, y - 40, gm.constants.oB) == 0.0
            if far_from_player and free_above and y > 120 and far_from_marks(x, gap) then
                local inst = gm.instance_create(x, y, object_id)
                if inst and Instance.exists(inst) then return inst end
            end
        end
    end
    return nil
end

-- Genera hasta `count` altares del objeto dado, separados entre si al menos `gap` px.
-- configure(inst) se ejecuta sobre cada uno. Devuelve cuantos se crearon.
function Util.spawn_shrines(object_id, count, player, min_distance, gap, configure)
    local margin = math.floor(min_distance / 2)
    local made = 0

    for _ = 1, count do
        local inst = spawn_with_director(object_id, margin)
        if inst and not far_from_marks(inst.x, gap) then
            -- El Director lo dejo pegado a otro altar: descartar y buscar otro sitio
            pcall(function() inst:destroy() end)
            inst = nil
        end
        if not inst then
            inst = spawn_on_platform(object_id, player, min_distance, gap)
        end

        if inst and Instance.exists(inst) then
            table.insert(Util.shrine_marks, inst.x)
            configure(inst)
            made = made + 1
        end
    end
    return made
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
