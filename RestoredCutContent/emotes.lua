-- ============================================================================
-- emotes.lua
-- Restaura el sistema de Emoticonos descartado de RoRR
-- Muestra animaciones flotantes sobre los supervivientes basadas en los GIF
-- de concept art (Peligro/Auxilio, Aplausos/Victoria, Muerte/Lapida).
-- ============================================================================

local loaded = require("util.lua")
local Util = (type(loaded) == "table") and loaded or RCC_UTIL
local Search = RCC_SEARCH or Util.Search

local ASSETS = path.combine(PATH, "assets/ui/emotes")

-- Sprites de los emoticonos
local sprite_clapping = Sprite.new("EmoteClapping", path.combine(ASSETS, "Emote_Clapping_Hands.gif"), 1, 31, 47)
local sprite_die      = Sprite.new("EmoteDie",      path.combine(ASSETS, "Emote_Die.gif"),            1, 41, 50)
local sprite_danger   = Sprite.new("EmoteDanger",   path.combine(ASSETS, "Emote_HelpDanger.gif"),     1, 38, 67)

local EMOTE_SPRITES = {
    ["clapping"] = sprite_clapping,
    ["clap"]     = sprite_clapping,
    ["die"]      = sprite_die,
    ["death"]    = sprite_die,
    ["danger"]   = sprite_danger,
    ["help"]     = sprite_danger
}

-- ----------------------------------------------------------------------------
-- Objeto flotante de emoticono (oEmoteBubble)
-- ----------------------------------------------------------------------------
local obj_emote = Object.new("PlayerEmoteBubble", Object.Parent.CUSTOM)
obj_emote:set_sprite(sprite_danger)
obj_emote:set_depth(-20) -- dibujar por encima de actores y tiles

local emote_instances = {}

Callback.add(obj_emote.on_create, function(inst)
    inst.image_speed = 0.30
    emote_instances[inst.id] = {
        parent = nil,
        lifetime = 150, -- 2.5 segundos
        initial_time = 150,
        bob_frame = 0
    }
end)

Callback.add(obj_emote.on_step, function(inst)
    local data = emote_instances[inst.id]
    if not data then return end

    data.lifetime = data.lifetime - 1
    data.bob_frame = data.bob_frame + 1

    -- Destruccion al expirar o si el padre ya no existe
    if data.lifetime <= 0 or not data.parent or not Instance.exists(data.parent) then
        emote_instances[inst.id] = nil
        pcall(function() inst:destroy() end)
        return
    end

    -- Flotar suavemente encima de la cabeza del superviviente
    local parent = data.parent
    local float_offset = math.sin(data.bob_frame * 0.08) * 3
    inst.x = parent.x
    inst.y = parent.bbox_top - 24 + float_offset

    -- Desvanecimiento progresivo en los ultimos 30 frames
    if data.lifetime < 30 then
        inst.image_alpha = data.lifetime / 30
    else
        inst.image_alpha = 1.0
    end
end)

-- ----------------------------------------------------------------------------
-- API para invocar un emoticono sobre un actor
-- ----------------------------------------------------------------------------
function Util.show_emote(actor, emote_name)
    if not actor or not Instance.exists(actor) then return nil end
    local spr = EMOTE_SPRITES[emote_name] or sprite_danger

    local inst = obj_emote:create(actor.x, actor.bbox_top - 24)
    if inst and emote_instances[inst.id] then
        inst.sprite_index = spr
        inst.image_index = 0
        emote_instances[inst.id].parent = actor
        Util.play_sound(gm.constants.wSpawn, 0.4, 1.8, actor.x, actor.y)
    end
    return inst
end

-- ----------------------------------------------------------------------------
-- Reacciones automaticas inteligentes en partida
-- ----------------------------------------------------------------------------
local player_cooldowns = {}

Callback.add(Callback.TYPE.postStep, "RestoredCutContent_Emotes_Auto", function()
    local players = Search.in_radius(0, 0, math.huge, gm.constants.oP)
    for _, p in ipairs(players) do
        if Instance.exists(p) then
            player_cooldowns[p.id] = (player_cooldowns[p.id] or 0) - 1

            -- Reaccion de PELIGRO / AUXILIO si la vida baja del 25%
            if type(p.hp) == "number" and type(p.maxhp) == "number" and p.maxhp > 0 then
                if (p.hp / p.maxhp) < 0.25 and p.hp > 0 and (player_cooldowns[p.id] <= 0) then
                    player_cooldowns[p.id] = 400 -- no repetir en casi 7 segundos
                    Util.show_emote(p, "danger")
                end
            end
        end
    end
end)

-- Reaccion de APLAUSO / VICTORIA al derrotar un altar de desafio o teletransportador
Callback.add(Callback.TYPE.onStageStart, "RestoredCutContent_Emotes_Reset", function()
    player_cooldowns = {}
end)

-- Registrar en el sistema de busqueda de cut content
if Search and Search.register_cut_content then
    Search.register_cut_content("emotes", {
        name  = "Restored Emotes System",
        tags  = { "ui", "cut_feature", "emotes", "danger", "clapping", "death" }
    })
end

return {
    show = Util.show_emote,
    sprites = EMOTE_SPRITES
}

