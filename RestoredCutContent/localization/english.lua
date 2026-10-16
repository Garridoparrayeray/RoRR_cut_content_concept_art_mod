-- ============================================================================
-- english.lua
-- Localization tokens for RestoredCutContent (English)
-- ============================================================================

return {
    item = {
        item_kfl = {
            name        = "Kentucky Fried Lemurian",
            pickup      = "Enemies drop crispy drumsticks that heal and boost speed.",
            description = "&y&25% chance&! (+15% per stack) on kill to drop a &yCrispy Drumstick&!. Collecting it heals &g15 HP&! (+10 per stack) and grants &b+30% movement speed&! for &y3 seconds&!.",
            destination = "Sector 4, Space-Fry Franchise, UES Contact Light",
            date        = "06/12/2056",
            story       = "Secret recipe #11: Take one fresh lemurian tail, season with red sand salt and roasted fiery spores. Deep fry in magma-purified oil until golden and crispy. Guaranteed to keep scavengers running across the plains.",
            priority    = "Standard"
        }
    },

    skill = {
        chef_ice_cube = {
            name        = "Glaze / Ice Cube",
            description = "Launch a &brolling ice cube&! that deals &y220% damage&! and &bchills enemies&!, reducing movement speed by &b40%&!."
        },
        chef_ice_cube_boosted = {
            name        = "Deep Freeze Glaze",
            description = "Launch a &bmassive cryogenic cube&! that deals &y450% damage&! and &bfreezes enemies solid&! for 2.5 seconds."
        },
        impostor_primary = {
            name        = "Knife Shank / Backstab",
            description = "Stab for &y200% damage&!. Striking an enemy from &ybehind deals 350% critical damage&!."
        },
        impostor_secondary = {
            name        = "Sabotage",
            description = "Disrupt nearby equipment in a &y180px radius&!, dealing &y150% electric damage&!, &ystunning for 1.5s&!, and slowing enemies by 50%."
        },
        impostor_utility = {
            name        = "Vent",
            description = "Leap into the vents, becoming &yInvulnerable with +50% movement speed&! for 2s. Emerge with an iron burst dealing &y250% damage&!."
        },
        impostor_special = {
            name        = "Emergency Meeting",
            description = "Call an Emergency Meeting! Stuns all foes and casts a vote against the toughest enemy on screen for &y600% execute damage&!."
        },
        impostor_special_boosted = {
            name        = "Ejected into Space",
            description = "The vote is unanimous. Instantly &yEJECTS non-boss enemies below 30% HP&! into the void, or deals &y1000% damage&! to bosses with a 350% void vortex."
        }
    },

    survivor = {
        impostor = {
            name        = "Impostor",
            name_upper  = "IMPOSTOR",
            description = "The Impostor is an elusive, deceptive killer who sabotages systems, traverses through vents unseen, and executes unsuspecting crewmates from behind.\n\n&y'There is 1 Impostor among us.'&!",
            end_quote   = "...and so he vented away, never to be caught."
        }
    },

    monster = {
        monkey = {
            name = "Space Lemur / Monkey"
        },
        restless_oak = {
            name = "Restless Oak"
        },
        tardigrade = {
            name = "Macrobic Tardigrade"
        }
    }
}


