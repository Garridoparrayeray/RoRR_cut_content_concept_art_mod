-- ============================================================================
-- item_kfl.lua
-- Restaura el item descartado del concept art: Kentucky Fried Lemurian (KFL)
-- Los enemigos derrotados tienen probabilidad de soltar un muslo frito crujiente
-- que cura salud y otorga velocidad temporal.
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSET_PATH = path.combine(PATH, "assets/items/kfl/item_KFL_KentuckyFriedLemurian.png")

-- Sprite del item
local sprite_kfl = Sprite.new("ItemKFL", ASSET_PATH, 1, 16, 16)

-- Definicion del Item en ReturnsAPI
local item_kfl = Item.new("item_kfl")
item_kfl:set_sprite(sprite_kfl)
item_kfl:set_tier(ItemTier.UNCOMMON)
item_kfl.loot_tags = Item.LootTag.CATEGORY_HEALING

-- Registro en el Logbook
ItemLog.new_from_item(item_kfl)

-- ----------------------------------------------------------------------------
-- Buff de velocidad al comer el muslo crujiente (Speed / Rush)
-- ----------------------------------------------------------------------------
local buff_kfl_rush = Buff.new("restored_cut_content", "kfl_rush")
buff_kfl_rush.max_stack = 3
buff_kfl_rush.is_timed  = true

pcall(function() buff_kfl_rush:clear_callbacks() end)
pcall(function()
    if buff_kfl_rush.add_callback then
        buff_kfl_rush:add_callback("onPostStatRecalc", function(actor, stack)
            -- +30% velocidad de movimiento por stack
            actor.pHmax = actor.pHmax * (1 + 0.30 * stack)
        end)
    end
end)

-- ----------------------------------------------------------------------------
-- Objeto recolectable: Muslo crujiente en el suelo (oKFLDrumstick)
-- ----------------------------------------------------------------------------
local obj_drumstick = Object.new("KFLDrumstick", Object.Parent.CUSTOM)
obj_drumstick:set_sprite(sprite_kfl)
obj_drumstick:set_depth(-10)

local drumstick_data = {}

Callback.add(obj_drumstick.on_create, function(inst)
    inst.image_xscale = 0.5
    inst.image_yscale = 0.5
    inst.vspeed = -3.5
    inst.hspeed = gm.random_range(-2.0, 2.0)
    inst.gravity = 0.22

    drumstick_data[inst.id] = {
        lifetime = 900, -- 15 segundos antes de desaparecer si no se recoge
        bounce = 2,
        heal_amount = 25
    }
end)

Callback.add(obj_drumstick.on_step, function(inst)
    local data = drumstick_data[inst.id]
    if not data then return end

    data.lifetime = data.lifetime - 1
    if data.lifetime <= 0 then
        drumstick_data[inst.id] = nil
        pcall(function() inst:destroy() end)
        return
    end

    -- Rebote con el suelo solido
    if gm.position_meeting(inst.x, inst.y + 4, gm.constants.oB) == 1.0 then
        if data.bounce > 0 then
            inst.vspeed = -inst.vspeed * 0.45
            inst.hspeed = inst.hspeed * 0.7
            data.bounce = data.bounce - 1
        else
            inst.vspeed = 0
            inst.hspeed = 0
            inst.gravity = 0
        end
    end

    -- Parpadeo en los ultimos 3 segundos
    if data.lifetime < 180 then
        inst.visible = (math.floor(data.lifetime / 8) % 2 == 0)
    end

    -- Deteccion de recogida por un jugador cercano (radio 24 px)
    local player = Search.nearest_player(inst.x, inst.y, 32)
    if player and Instance.exists(player) then
        -- Curar al jugador
        local heal = data.heal_amount or 25
        pcall(function()
            if type(player.hp) == "number" and type(player.maxhp) == "number" then
                player.hp = math.min(player.maxhp, player.hp + heal)
            end
            -- Otorgar buff de velocidad
            player:buff_apply(buff_kfl_rush, 180, 1)
            -- Sonido y chispas
            Util.play_sound(gm.constants.wBite or gm.constants.wChest1, 0.9, 1.2, player.x, player.y)
            Util.spark_at(player.x, player.y - 10)
        end)

        drumstick_data[inst.id] = nil
        pcall(function() inst:destroy() end)
    end
end)

-- ----------------------------------------------------------------------------
-- Probabilidad de soltar el muslo al derrotar enemigos
-- ----------------------------------------------------------------------------
Callback.add(Callback.TYPE.onKillProc, "RestoredCutContent_KFL_Kill", function(actor, victim)
    if not actor or not Instance.exists(actor) then return end
    if not victim or not Instance.exists(victim) then return end

    local count = 0
    pcall(function()
        count = actor:item_count(item_kfl)
    end)
    if count <= 0 then return end

    -- 25% base + 15% por stack adicional (maximo 85%)
    local drop_chance = math.min(0.85, 0.25 + 0.15 * (count - 1))
    if gm.random(1.0) < drop_chance then
        pcall(function()
            local drum = obj_drumstick:create(victim.x, victim.y - 12)
            if drum and drumstick_data[drum.id] then
                drumstick_data[drum.id].heal_amount = 15 + 10 * count
            end
        end)
    end
end)

-- Registrar en el sistema de busqueda de contenido restaurado
if Search and Search.register_cut_content then
    Search.register_cut_content("item_kfl", {
        name = "Kentucky Fried Lemurian",
        item = item_kfl,
        sprite = sprite_kfl,
        tags = { "item", "cut_item", "healing", "speed", "uncommon" }
    })
end

return item_kfl

