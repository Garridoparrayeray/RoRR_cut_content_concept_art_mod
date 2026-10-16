-- ============================================================================
-- spanish.lua
-- Localization tokens for RestoredCutContent (Spanish)
-- ============================================================================

return {
    item = {
        item_kfl = {
            name        = "Lemuriano Frito de Kentucky",
            pickup      = "Los enemigos sueltan muslos crujientes que curan y aumentan la velocidad.",
            description = "&y&25% de probabilidad&! (+15% por acumulacion) al matar un enemigo de soltar un &yMuslo Crujiente&!. Recogerlo cura &g15 PS&! (+10 por acumulacion) y otorga &b+30% de velocidad de movimiento&! durante &y3 segundos&!.",
            destination = "Sector 4, Franquicia Space-Fry, UES Contact Light",
            date        = "12/06/2056",
            story       = "Receta secreta n.º 11: Tome una cola fresca de lemuriano, sazone con sal de arena roja y esporas tostadas de fuego. Freir en aceite purificado por magma hasta que quede dorado y crujiente. Garantizado para mantener a los carroñeros corriendo por las llanuras.",
            priority    = "Standard"
        }
    },

    skill = {
        chef_ice_cube = {
            name        = "Glaseado / Cubo de Hielo",
            description = "Lanza un &bcubo de hielo rodante&! que inflige &y220% de dano&! y &benfria a los enemigos&!, reduciendo su velocidad en un &b40%&!."
        },
        chef_ice_cube_boosted = {
            name        = "Glaseado de Ultracongelacion",
            description = "Lanza un &benorme cubo criogenico&! que inflige &y450% de dano&! y &bcongela por completo a los enemigos&! durante 2,5 segundos."
        },
        impostor_primary = {
            name        = "Puñalada / Degüello",
            description = "Ejecuta un combo rápido de &y3 cuchilladas&!. El tercer golpe asesta un &yremate de 260% de daño&!. Atacar por la &yespalda inflige un golpe crítico letal (hasta 500% daño)&!."
        },
        impostor_secondary = {
            name        = "Pistolazo",
            description = "Dispara a quemarropa con tu pistola oculta infligiendo &y480% de daño perforante&!. A menos de 60 px asesta un &ycrítico de 680% y aturde 1,2 s&!.\n&g¡Matar a un enemigo otorga un subidón de adrenalina (+60% velocidad de movimiento) durante 4 s!&!"
        },
        impostor_utility = {
            name        = "Ventilación",
            description = "Métete en los conductos de ventilación volviéndote &ycompletamente invisible, indetectable e invulnerable (+85% velocidad)&!. Pulsa &yShift / C de nuevo para salir cuando quieras&!, provocando una explosión de &y320% de daño&! que aturde y ejecuta una &yemboscada por la espalda de 500% crítico&!."
        },
        impostor_special = {
            name        = "Reunión de Emergencia",
            description = "¡Botón de pánico! Pulsa el botón de emergencia para &baturdir y congelar a todos los enemigos en pantalla durante 3 s&!, &greiniciar al instante el enfriamiento de la Trampilla y la Pistola&! y volverte &yinvulnerable 2,5 s&!. El enemigo con mayor vida es votado y ejecutado por un &y800% de daño directo&! y una gran explosión."
        },
        impostor_special_boosted = {
            name        = "Expulsado al Espacio",
            description = "La votación es unánime. Aturde a todos los enemigos 3,5 s y &greinicia todas tus habilidades&!. &yEYECTA al vacío del espacio instantáneamente&! a enemigos que no sean jefes con menos del 35% de PS, o inflige un descomunal &y1400% de daño&! a jefes con un vórtice cósmico de 400%."
        }
    },

    survivor = {
        impostor = {
            name        = "Impostor",
            name_upper  = "IMPOSTOR",
            description = "El Impostor es un asesino elusivo y letal que sabotea sistemas electricos, se desplaza por los conductos de ventilacion y ejecuta por la espalda a los tripulantes desprevenidos.\n\n&y'Hay 1 Impostor entre nosotros.'&!",
            end_quote   = "...y asi escapo por la ventilacion, sin ser descubierto jamas."
        }
    },

    monster = {
        monkey = {
            name = "Mono Espacial"
        },
        restless_oak = {
            name = "Roble Inquieto"
        },
        tardigrade = {
            name = "Tardigrado Macrobico"
        }
    }
}


