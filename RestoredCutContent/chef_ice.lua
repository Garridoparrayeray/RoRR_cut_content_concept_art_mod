-- ============================================================================
-- chef_ice.lua
-- Restaura la habilidad descartada de CHEF del concept art: Cubo de Hielo (Ice Cube)
-- CHEF lanza un cubo de hielo rodante/rebotante que atraviesa enemigos,
-- infligiendo dano de escarcha y aplicando una ralentizacion gelida.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSETS = path.combine(PATH, "assets/survivors/chef")

-- Sprites e iconos de habilidad
local sprite_icon      = Sprite.new("ChefIconIce",        path.combine(ASSETS, "chef_icon_ice.png"),        1, 12, 12)
local sprite_icon_ult  = Sprite.new("ChefIconIceUlt",     path.combine(ASSETS, "chef_icon_ice_ULT.png"),    1, 12, 12)
local sprite_attack    = Sprite.new("ChefIceAttack",      path.combine(ASSETS, "chef_schefice_attack.png"), 1, 46, 23)
local sprite_cube      = Sprite.new("ChefIceCubeBounce",  path.combine(ASSETS, "chef_icecube.png"),        4, 12, 12)

-- ----------------------------------------------------------------------------
-- Buff de congelacion / escarcha (Chilling / Glaze)
-- ----------------------------------------------------------------------------
local buff_chill = Buff.new("restored_cut_content", "chef_chill")
buff_chill.max_stack = 3
buff_chill.is_timed  = true
buff_chill.is_debuff = true

pcall(function() buff_chill:clear_callbacks() end)
pcall(function()
    if buff_chill.add_callback then
        buff_chill:add_callback("onPostStatRecalc", function(actor, stack)
            -- Reduce velocidad de movimiento y ataque
            actor.pHmax = actor.pHmax * math.max(0.2, 1.0 - 0.35 * stack)
            actor.attack_speed = actor.attack_speed * math.max(0.3, 1.0 - 0.25 * stack)
            -- Tinte azulado de congelacion
            actor.image_blend = Util.mix_blend({255, 255, 255}, {100, 180, 255}, 0.6)
        end)
    end
end)

-- ----------------------------------------------------------------------------
-- Proyectil: Cubo de Hielo rebotante (oChefIceCube)
-- ----------------------------------------------------------------------------
local obj_ice_cube = Object.new("ChefIceCube", Object.Parent.CUSTOM)
obj_ice_cube:set_sprite(sprite_cube)
obj_ice_cube:set_depth(-5)

local cube_data = {}

Callback.add(obj_ice_cube.on_create, function(inst)
    inst.image_xscale = 1.0
    inst.image_yscale = 1.0
    inst.image_speed = 0.35
    cube_data[inst.id] = {
        lifetime = 180,     -- 3 segundos de rodaje
        damage_coef = 2.2,
        hit_actors = {},
        is_boosted = false,
        parent = nil
    }
end)

Callback.add(obj_ice_cube.on_step, function(inst)
    local data = cube_data[inst.id]
    if not data then return end

    data.lifetime = data.lifetime - 1
    if data.lifetime <= 0 then
        -- Estallido de escarcha al expirar
        Util.spark_at(inst.x, inst.y)
        Util.play_sound(gm.constants.wGlass or gm.constants.wChest1, 0.7, 1.6, inst.x, inst.y)
        cube_data[inst.id] = nil
        pcall(function() inst:destroy() end)
        return
    end

    -- Rebote con el suelo
    if gm.position_meeting(inst.x, inst.y + 4, gm.constants.oB) == 1.0 then
        inst.vspeed = -inst.vspeed * 0.6
        if math.abs(inst.vspeed) < 1.0 then
            inst.vspeed = 0
            inst.gravity = 0
        end
    else
        inst.gravity = 0.28
    end

    -- Chispas heladas
    if data.lifetime % 8 == 0 then
        Util.spark_at(inst.x, inst.y)
    end

    -- Colision con enemigos vivos (atraviesa hordas aplicando escarcha)
    local hit_enemies = Search.in_radius(inst.x, inst.y, 28, gm.constants.pEnemy)
    for _, enemy in ipairs(hit_enemies) do
        if not data.hit_actors[enemy.id] then
            data.hit_actors[enemy.id] = true
            pcall(function()
                if data.parent and Instance.exists(data.parent) then
                    data.parent:fire_direct(enemy, data.damage_coef, 0, nil, nil, gm.constants.sNone, false)
                else
                    enemy:damage(data.damage_coef * 20)
                end
                -- Aplicar debuff de escarcha
                enemy:buff_apply(buff_chill, 240, 1)
                Util.play_sound(gm.constants.wHit, 0.7, 1.5, enemy.x, enemy.y)
                Util.spark_at(enemy.x, enemy.y - 10)
            end)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Registro de la habilidad en ReturnsAPI
-- ----------------------------------------------------------------------------
local skill_ice = Skill.new("chef_ice_cube")
skill_ice.sprite = sprite_icon
skill_ice.subimage = 0
skill_ice.cooldown = 5 * 60   -- 5 segundos
skill_ice.damage = 2.2
skill_ice.is_primary = false
skill_ice.is_utility = false
skill_ice.token_name = "GLAZE: Ice Cube"
skill_ice.token_description = "Hurl a bouncing ice cube dealing &y220% damage&! and chilling enemies."

-- Version mejorada por Cetro Ancestral (Ancient Scepter)
local skill_ice_boosted = Skill.new("chef_ice_cube_boosted")
skill_ice_boosted.sprite = sprite_icon_ult
skill_ice_boosted.subimage = 0
skill_ice_boosted.cooldown = 5 * 60
skill_ice_boosted.damage = 4.5
skill_ice_boosted.token_name = "GLAZE: Mega Iceberg"
skill_ice_boosted.token_description = "Hurl a massive ice cube dealing &y450% damage&! that freezes enemies solid."
skill_ice.upgrade_skill = skill_ice_boosted

-- Logica de activacion
local function fire_ice_cube(actor, is_boosted)
    local dir = 1
    pcall(function()
        dir = (actor.image_xscale >= 0) and 1 or -1
    end)

    actor.sprite_index = sprite_attack
    actor.image_index = 0
    actor.image_speed = 0.35

    Util.play_sound(gm.constants.wChefShoot1 or gm.constants.wChest1, 0.9, 1.3, actor.x, actor.y)

    local cube = obj_ice_cube:create(actor.x + dir * 20, actor.y - 10)
    if cube and cube_data[cube.id] then
        cube_data[cube.id].parent = actor
        cube_data[cube.id].is_boosted = is_boosted
        cube_data[cube.id].damage_coef = is_boosted and 4.5 or 2.2
        cube.hspeed = dir * (is_boosted and 6.0 or 4.5)
        cube.vspeed = -2.0
        if is_boosted then
            cube.image_xscale = 1.4
            cube.image_yscale = 1.4
        end
    end
end

Callback.add(skill_ice.on_activate, function(actor)
    fire_ice_cube(actor, false)
end)

Callback.add(skill_ice_boosted.on_activate, function(actor)
    fire_ice_cube(actor, true)
end)

-- Anadir habilidad secundaria alternativa a CHEF
local chef = Survivor.find("chef")
if chef then
    chef:add_skill(Skill.Slot.SECONDARY, skill_ice)
    log.info("[RestoredCutContent] Habilidad de hielo de CHEF registrada correctamente en su loadout.")
end

-- Registrar en el sistema de busqueda de cut content
if Search and Search.register_cut_content then
    Search.register_cut_content("chef_ice_cube", {
        name  = "CHEF Ice Cube / Glaze",
        skill = skill_ice,
        icon  = sprite_icon,
        tags  = { "skill", "cut_skill", "chef", "ice", "secondary" }
    })
end

return skill_ice

