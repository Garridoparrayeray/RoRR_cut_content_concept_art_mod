-- ============================================================================
-- search.lua
-- Sistema unificado de busqueda y resolucion para RestoredCutContent
-- Inspirado en la arquitectura FindCache de ReturnsAPI y la resolucion multicapa de ENVY
-- ============================================================================

local Search = RCC_SEARCH or {}

-- ----------------------------------------------------------------------------
-- 1. Cache de contenido y resolucion de identificadores (ReturnsAPI / Global)
-- ----------------------------------------------------------------------------
Search.Cache = Search.Cache or {}

local DEFAULT_NAMESPACE = "restored_cut_content"
local FALLBACK_NAMESPACES = { DEFAULT_NAMESPACE, "ssr", "ror", "rapi" }

-- Aliases y nombres estandarizados para busquedas insensibles a mayusculas/guiones
local ELITE_ALIASES = {
    ["blazing"]     = "blazing",
    ["fire"]        = "blazing",
    ["frenzied"]    = "frenzied",
    ["speed"]       = "frenzied",
    ["overloading"] = "overloading",
    ["lightning"]   = "overloading",
    ["shock"]       = "overloading",
    ["leeching"]    = "leeching",
    ["heal"]        = "leeching",
    ["volatile"]    = "volatile",
    ["missile"]     = "volatile",
    ["chilling"]    = "chilling",
    ["ice"]         = "chilling",
    ["freeze"]      = "chilling",
    ["armored"]     = "armored",
    ["teleporter"]  = "teleporter",
    ["boss"]        = "teleporter",
}

-- Resolucion segura de Elite por identificador/alias
function Search.elite(identifier, fallback)
    if not identifier then return fallback end
    local query = string.lower(tostring(identifier)):gsub("[_%-%s]", "")
    local standard_name = ELITE_ALIASES[query] or query

    -- 1. Intentar con ReturnsAPI Elite.find si esta disponible
    if Elite and Elite.find then
        local found = Elite.find(standard_name)
        if found and found.value then return found.value end

        -- Probar con el nombre original por si acaso
        found = Elite.find(tostring(identifier))
        if found and found.value then return found.value end
    end

    -- 2. Fallback de constantes directas en el motor GM
    local constant_candidates = {
        "elite_" .. standard_name,
        "elite" .. standard_name,
        standard_name,
    }
    for _, name in ipairs(constant_candidates) do
        if gm.constants[name] ~= nil then
            return gm.constants[name]
        end
    end

    return fallback
end

-- Resolucion segura de objetos de GameMaker (GM Object / ReturnsAPI Object)
function Search.object(identifier, fallback)
    if not identifier then return fallback end

    -- Si ya es un numero (object index), validarlo
    if type(identifier) == "number" then return identifier end

    local name = tostring(identifier)

    -- 1. Buscar en gm.constants
    if gm.constants[name] ~= nil then
        return gm.constants[name]
    end

    -- 2. Buscar en ReturnsAPI Object.find
    if Object and Object.find then
        local obj = Object.find(name)
        if obj and obj.value then return obj.value end
    end

    -- 3. Variantes con prefijo 'o' tipico de RoR (ej: 'Shrine6' -> 'oShrine6')
    local prefixed = "o" .. name
    if gm.constants[prefixed] ~= nil then
        return gm.constants[prefixed]
    end

    return fallback
end

-- Resolucion segura de Items
function Search.item(identifier, namespace)
    if not Item or not Item.find then return nil end
    if namespace then
        return Item.find(identifier, namespace)
    end
    -- Cascada automatica a traves de namespaces
    for _, ns in ipairs(FALLBACK_NAMESPACES) do
        local found = Item.find(identifier, ns)
        if found then return found end
    end
    return Item.find(identifier)
end

-- Resolucion segura de Buffs
function Search.buff(identifier, namespace)
    if not Buff or not Buff.find then return nil end
    if namespace then
        return Buff.find(identifier, namespace)
    end
    for _, ns in ipairs(FALLBACK_NAMESPACES) do
        local found = Buff.find(identifier, ns)
        if found then return found end
    end
    return Buff.find(identifier)
end

-- Resolucion de Stages por identificador o sala
function Search.stage(room_or_identifier)
    if not Stage then return nil end

    if type(room_or_identifier) == "string" then
        return Stage.find(room_or_identifier)
    end

    local room = room_or_identifier or gm.variable_global_get("room")
    if not room then return nil end

    for _, stage in ipairs(Stage.find_all()) do
        if stage.room_list then
            local room_list = List and List.wrap and List.wrap(stage.room_list) or stage.room_list
            for _, r in ipairs(room_list) do
                if r == room then return stage end
            end
        end
    end
    return nil
end

-- ----------------------------------------------------------------------------
-- 2. Consultas espaciales de instancias (Spatial Queries)
-- ----------------------------------------------------------------------------

-- Instancia mas cercana a un punto (x, y) de un objeto dado con filtro opcional
function Search.nearest(x, y, object, filter_fn)
    local obj = Search.object(object)
    if not obj then return nil end

    -- Optimizacion rapida de GameMaker si no hay funcion de filtro
    if not filter_fn and Instance and Instance.nearest then
        local inst = Instance.nearest(x, y, obj)
        if inst and Instance.exists(inst) and inst ~= Instance.INVALID then
            return inst
        end
    end

    -- Busqueda con calculo euclidiano si hay filtro o no hay Instance.nearest nativo
    local best, best_dist_sq = nil, math.huge
    local instances = Instance and Instance.find_all and Instance.find_all(obj) or {}

    for _, inst in ipairs(instances) do
        if Instance.exists(inst) then
            if not filter_fn or filter_fn(inst) then
                local dx = inst.x - x
                local dy = inst.y - y
                local dist_sq = dx * dx + dy * dy
                if dist_sq < best_dist_sq then
                    best = inst
                    best_dist_sq = dist_sq
                end
            end
        end
    end
    return best, (best and math.sqrt(best_dist_sq) or math.huge)
end

-- Jugador mas cercano a una posicion (x, y)
function Search.nearest_player(x, y, max_radius)
    local player_obj = gm.constants.oP
    if not player_obj then return nil end

    local best, best_dist_sq = nil, math.huge
    local max_dist_sq = max_radius and (max_radius * max_radius) or math.huge

    local players = Instance and Instance.find_all and Instance.find_all(player_obj) or {}
    for _, p in ipairs(players) do
        if Instance.exists(p) then
            local dx = p.x - x
            local dy = p.y - y
            local dist_sq = dx * dx + dy * dy
            if dist_sq <= max_dist_sq and dist_sq < best_dist_sq then
                best = p
                best_dist_sq = dist_sq
            end
        end
    end
    return best, (best and math.sqrt(best_dist_sq) or nil)
end

-- Todas las instancias de un objeto dentro de un radio R
function Search.in_radius(x, y, radius, object, filter_fn)
    local obj = Search.object(object)
    if not obj then return {} end

    local radius_sq = radius * radius
    local results = {}

    local instances = Instance and Instance.find_all and Instance.find_all(obj) or {}
    for _, inst in ipairs(instances) do
        if Instance.exists(inst) then
            local dx = inst.x - x
            local dy = inst.y - y
            local dist_sq = dx * dx + dy * dy
            if dist_sq <= radius_sq then
                if not filter_fn or filter_fn(inst, math.sqrt(dist_sq)) then
                    table.insert(results, inst)
                end
            end
        end
    end
    return results
end

-- Cuenta instancias dentro de un radio sin crear tablas intermedias innecesarias
function Search.count_in_radius(x, y, radius, object, filter_fn)
    local obj = Search.object(object)
    if not obj then return 0 end

    local radius_sq = radius * radius
    local count = 0

    local instances = Instance and Instance.find_all and Instance.find_all(obj) or {}
    for _, inst in ipairs(instances) do
        if Instance.exists(inst) then
            local dx = inst.x - x
            local dy = inst.y - y
            local dist_sq = dx * dx + dy * dy
            if dist_sq <= radius_sq then
                if not filter_fn or filter_fn(inst) then
                    count = count + 1
                end
            end
        end
    end
    return count
end

-- Instancias dentro de una caja delimitadora (AABB: x1, y1 a x2, y2)
function Search.in_box(x1, y1, x2, y2, object, filter_fn)
    local obj = Search.object(object)
    if not obj then return {} end

    local min_x, max_x = math.min(x1, x2), math.max(x1, x2)
    local min_y, max_y = math.min(y1, y2), math.max(y1, y2)
    local results = {}

    local instances = Instance and Instance.find_all and Instance.find_all(obj) or {}
    for _, inst in ipairs(instances) do
        if Instance.exists(inst) then
            if inst.x >= min_x and inst.x <= max_x and inst.y >= min_y and inst.y <= max_y then
                if not filter_fn or filter_fn(inst) then
                    table.insert(results, inst)
                end
            end
        end
    end
    return results
end

-- Todos los enemigos vivos en la sala con filtro opcional
function Search.all_enemies(filter_fn)
    local enemy_obj = gm.constants.pEnemy
    if not enemy_obj then return {} end

    local results = {}
    local enemies = Instance and Instance.find_all and Instance.find_all(enemy_obj) or {}
    for _, enemy in ipairs(enemies) do
        if Instance.exists(enemy) then
            if not filter_fn or filter_fn(enemy) then
                table.insert(results, enemy)
            end
        end
    end
    return results
end

-- ----------------------------------------------------------------------------
-- 3. Registro y descubrimiento de contenido descartado (Cut Content Registry)
-- ----------------------------------------------------------------------------
Search.CutRegistry = Search.CutRegistry or {
    by_id  = {},
    by_tag = {}
}

-- Registra un elemento de contenido restaurado para permitir su busqueda e inspeccion
function Search.register_cut_content(id, data)
    data = data or {}
    data.id = id
    data.tags = data.tags or {}
    Search.CutRegistry.by_id[id] = data

    for _, tag in ipairs(data.tags) do
        Search.CutRegistry.by_tag[tag] = Search.CutRegistry.by_tag[tag] or {}
        Search.CutRegistry.by_tag[tag][id] = data
    end
end

-- Obtiene la definicion de un contenido restaurado por ID
function Search.get_cut_content(id)
    return Search.CutRegistry.by_id[id]
end

-- Encuentra todos los contenidos que coincidan con una etiqueta
function Search.find_cut_content_by_tag(tag)
    local group = Search.CutRegistry.by_tag[tag]
    if not group then return {} end

    local list = {}
    for _, entry in pairs(group) do
        table.insert(list, entry)
    end
    return list
end

-- Encuentra todas las instancias vivas en el mapa que correspondan a un contenido restaurado
function Search.find_cut_instances(id_or_tag)
    local results = {}

    -- 1. Si es un ID de elemento registrado
    local entry = Search.CutRegistry.by_id[id_or_tag]
    if entry and entry.object then
        return Instance and Instance.find_all and Instance.find_all(entry.object) or {}
    end

    -- 2. Si es una etiqueta, agregar todas las instancias de cada objeto registrado
    local tagged = Search.CutRegistry.by_tag[id_or_tag]
    if tagged then
        for _, item in pairs(tagged) do
            if item.object then
                local insts = Instance and Instance.find_all and Instance.find_all(item.object) or {}
                for _, inst in ipairs(insts) do
                    table.insert(results, inst)
                end
            end
        end
    end

    return results
end

-- Inicializar registros base del mod RestoredCutContent
Search.register_cut_content("shrine_challenge", {
    name        = "Altar de Desafio",
    object      = gm.constants.oShrine6 or 624,
    sprite      = gm.constants.sShrine6,
    death_sprite= gm.constants.sShrine6Death,
    tags        = { "shrine", "interactable", "challenge" }
})

Search.register_cut_content("shrine_empower", {
    name        = "Altar de Empoderamiento",
    object      = gm.constants.oShrineEmpower or 625,
    sprite      = gm.constants.sShrineEmpower,
    death_sprite= gm.constants.sShrineEmpowerDeath,
    tags        = { "shrine", "interactable", "empower", "blessing" }
})

Search.register_cut_content("tardigrade", {
    name        = "Tardigrado Macrobico",
    object      = gm.constants.oMacT,
    sprite      = gm.constants.sMacTIdle,
    tags        = { "monster", "enemy", "cut_enemy", "suicide_exploder" }
})

RCC_SEARCH = Search

return Search

