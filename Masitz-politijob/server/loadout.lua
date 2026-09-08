-- ============================================================
-- MM-PolitiJob – server/loadout.lua
-- Registrerer Politilager som ox_inventory shop
-- ============================================================

exports.ox_inventory:RegisterShop('PoliceArmoury', {
    name = 'Politiets Lager',
    inventory = {

        -- ── AMMO ──────────────────────────────────────────────
        { name = 'politi-ammo1', price = 0 },
        { name = 'politi-ammo2', price = 0 },
        { name = 'politi-ammo3', price = 0 },
        { name = 'politi-ammo4', price = 0 },
        { name = 'politi-ammo9', price = 0 },

        -- ── HÅNDVÅBEN (PISTOLER) ──────────────────────────────
        { name = 'WEAPON_COMBATPISTOL',    price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_HEAVYPISTOL',     price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_MARKSMANPISTOL',  price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_REVOLVER_MK2',    price = 0, metadata = { registered = true, serial = 'POL' } },

        -- ── SMG ────────────────────────────────────────────────
        { name = 'WEAPON_SMG',             price = 0, metadata = { registered = true, serial = 'POL' } },

        -- ── RIFLER / SHOTGUN ─────────────────────────────────
        { name = 'WEAPON_CARBINERIFLE',    price = 0, metadata = { registered = true, serial = 'POL' }, grade = 3 },
        { name = 'WEAPON_CARBINERIFLE_MK2',price = 0, metadata = { registered = true, serial = 'POL' }, grade = 3 },
        { name = 'WEAPON_PUMPSHOTGUN_MK2', price = 0, metadata = { registered = true, serial = 'POL' }, grade = 3 },

        -- ── NON-LETHAL / VÆRKTØJ ──────────────────────────────
        { name = 'WEAPON_STUNGUN',         price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_BZGAS',           price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'WEAPON_NIGHTSTICK',      price = 0 },
        { name = 'WEAPON_FLASHLIGHT',      price = 0 },
        { name = 'WEAPON_FIREEXTINGUISHER',price = 0, metadata = { registered = true, serial = 'POL' } },
        { name = 'HANDCUFFS',              price = 0 },

        -- ── ATTACHMENTS ───────────────────────────────────────
        { name = 'at_flashlight',   price = 0 },
        { name = 'small_scope',     price = 0 },
        { name = 'medium_scope',    price = 0 },
        { name = 'large_scope',     price = 0 },
        { name = 'extended_clip',   price = 0 },
        { name = 'suppressor',      price = 0 },
        { name = 'at_grip',         price = 0 },
        { name = 'at_barrel',       price = 0 },
        { name = 'at_skin_camo',    price = 0 },

        -- ── GEAR ──────────────────────────────────────────────
        { name = 'policearmour',   price = 0 },
        { name = 'polititaske',    price = 0 },
        { name = 'politispikes',   price = 0 },
        { name = 'bodycam',        price = 0 },

        -- ── RADIOER ───────────────────────────────────────────
        { name = 'radio',          price = 1000, count = 1 },
        { name = 'radio_blue',     price = 1000, count = 1 },
        { name = 'radio_green',    price = 1000, count = 1 },
        { name = 'radio_pink',     price = 1000, count = 1 },
        { name = 'radio_purple',   price = 1000, count = 1 },
        { name = 'radio_red',      price = 1000, count = 1 },
        { name = 'radio_white',    price = 1000, count = 1 },
        { name = 'radio_yellow',   price = 1000, count = 1 },
    },
    groups = {
        police  = 0,
        sheriff = 0,
    },
})