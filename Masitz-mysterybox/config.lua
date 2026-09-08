-- ============================================================
--  Masitz-mysterybox | config.lua
--  ox_inventory · ox_lib
--
--  Alt herunder er trygt at ændre uden at røre Lua-koden i
--  client/ eller server/. Nye mystery boxes, rewards, chances,
--  bonus rewards, vehicle tickets og conversion styres 100% herfra.
-- ============================================================

Config = Config or {}
Config.MysteryBox = {}

local M = Config.MysteryBox

-- Console-logs prefixet [Masitz-MysteryBox]. Fejl/advarsler printes
-- ALTID (aldrig stille), men info-linjer ("Loaded X boxes...") og
-- detaljeret reward-logning vises kun når Debug = true.
M.Debug = false

-- Item-navn der bruges når en reward af typen "money" ikke selv
-- angiver et "name"-felt (se REWARDS herunder).
M.MoneyItem = 'money'

M.Notifications = {
    -- Position for alle ox_lib notifications sendt af dette script.
    position = 'center-right',
}

-- ============================================================
--  CONVERSION
--  Konverterer ét "kilde-item" til en valgt mystery box-type.
--  Menuen i client bygges 100% dynamisk ud fra "targets" herunder -
--  intet er hardcoded i client/server koden. Tilføj en ny linje i
--  "targets" for at gøre en ny box konverterbar, uden at ændre
--  client.lua eller server.lua.
-- ============================================================
M.Conversion = {
    enabled = true,

    -- Dialogens titel i client (lib.inputDialog).
    dialogTitle = 'Mystery Box',

    -- Item spilleren konverterer FRA.
    sourceItem = 'mysterybox',

    -- key = intern box-nøgle (skal matche en nøgle i M.Boxes herunder).
    -- value = item spilleren modtager for hver konverteret box.
    targets = {
        legal = 'lovlig_mysterybox',
        illegal = 'ulovlig_mysterybox',
    },
}

-- ============================================================
--  VEHICLE TICKETS (standardværdier)
--  Bruges af enhver reward/bonusReward med type = 'vehicle_ticket',
--  medmindre den enkelte reward selv angiver "item", "prefix" eller
--  "vehicles" og dermed overskriver disse standardværdier.
-- ============================================================
M.VehicleTicket = {
    -- Item der gives til spilleren når de vinder et vehicle ticket.
    item = 'car_ticket',

    -- Præfiks for det genererede ticketId (fx "TDI-482913").
    prefix = 'TDI-',

    -- Standard bilpulje. Kan overskrives pr. reward via "vehicles".
    vehicles = {
        'club', 'z190', 'coquette2', 'feltzer3',
        'sugoi', 'tenf', 'schafter3', 'toros',
    },
}

-- ============================================================
--  CHANCE SYSTEM - LÆS DETTE FØR DU ÆNDRER TAL
--
--  "rewards" (hoved-belønningen for en box):
--      WEIGHTED. Der vælges ALTID præcis 1 reward fra listen.
--      "chance" fungerer som en relativ VÆGT i forhold til de andre
--      rewards i samme liste - de behøver IKKE at summere til 100.
--      Eksempel: chance = 60, 50, 25 giver hhv. ~44%, ~37%, ~19% af
--      selve trækningen (60+50+25 = 135 -> 60/135, 50/135, 25/135).
--      Vil du have "rene" procenter, så sørg for at chance-værdierne
--      i listen summerer til 100.
--
--  "bonusRewards" (ekstra belønninger oveni hoved-rewarden):
--      INDEPENDENT CHANCE. Hver reward i listen rangeres helt for
--      sig selv som en selvstændig procent-chance (0-100, decimaler
--      er tilladt, fx chance = 2.5). Der kan udløses 0, 1 eller flere
--      bonusRewards samtidig - de påvirker IKKE hinanden og skal
--      IKKE summere til 100.
-- ============================================================

-- ============================================================
--  MYSTERY BOXES
--  Tilføj/fjern/ændr en box HELT uden at røre client.lua/server.lua.
--  Nøglen ("legal", "illegal", ...) er boxens interne id - brug den
--  også i Config.MysteryBox.Conversion.targets hvis boxen skal kunne
--  konverteres til.
-- ============================================================
M.Boxes = {

    legal = {
        item = 'lovlig_mysterybox',
        label = 'Lovlig Mystery Box',
        description = 'En mystery box med lovlige belønninger.',

        -- Hoved-reward: præcis 1 vælges (weighted, se forklaring ovenfor).
        rewards = {
            { type = 'item', name = 'diamond', amount = 50, chance = 60 },
            { type = 'money', name = 'money', amount = 30000, chance = 50 },
            { type = 'item', name = 'ticket', amount = 1, chance = 25 },
        },

        -- Bonus rewards: hver rangeres uafhængigt (independent chance).
        bonusRewards = {
            {
                type = 'vehicle_ticket',
                chance = 2, -- 2% chance for et car-ticket oveni hoved-rewarden
                vehicles = {
                    'club', 'z190', 'coquette2', 'feltzer3',
                    'sugoi', 'tenf', 'schafter3', 'toros',
                },
            },
        },
    },

    illegal = {
        item = 'ulovlig_mysterybox',
        label = 'Ulovlig Mystery Box',
        description = 'En mystery box med ulovlige belønninger.',

        rewards = {
            { type = 'item', name = 'ammo1', amount = 500, chance = 60 },
            { type = 'item', name = 'meth', amount = 250, chance = 50 },
            { type = 'item', name = 'coca_leaf', amount = 500, chance = 45 },
            { type = 'item', name = 'vinkelsliber', amount = 1, chance = 40 },
            { type = 'item', name = 'bolt_cutter', amount = 1, chance = 40 },
        },

        bonusRewards = {
            { type = 'item', name = 'gasmask', amount = 1, chance = 5 }, -- 5% chance
        },
    },

    -- ------------------------------------------------------------
    -- Eksempel på hvordan en helt ny box tilføjes (kopiér, tilret,
    -- fjern "--" foran linjerne, og husk evt. at tilføje den i
    -- Config.MysteryBox.Conversion.targets hvis den skal kunne
    -- konverteres til fra "mysterybox"):
    --
    -- premium = {
    --     item = 'premium_mysterybox',
    --     label = 'Premium Mystery Box',
    --     description = 'En mystery box med premium belønninger.',
    --     rewards = {
    --         { type = 'item', name = 'goldbar', amount = { min = 1, max = 3 }, chance = 40 },
    --         { type = 'money', amount = 100000, chance = 30 },
    --     },
    --     bonusRewards = {
    --         { type = 'vehicle_ticket', chance = 1 },
    --     },
    -- },
    -- ------------------------------------------------------------
}
