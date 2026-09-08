-- ============================================================
-- MM-PolitiJob – client/functions/loadout.lua
-- Ped-baseret våbenskab med ox_target + NUI Loadout Menu
-- ============================================================

local pedsSpawned      = {}
local menuOpen          = false
local requestInProgress = false

-- ── HELPERS ──────────────────────────────────────────────────

-- Slår Config.Attachments op for hvert våben i loadoutet og
-- bygger en liste af { weapon = ..., attachments = { ... } },
-- så NUI'et kan vise hvilke attachments der må sættes på hvad.
local function BuildAttachmentsPayload(weapons)
    local list = {}

    for _, weapon in ipairs(weapons or {}) do
        local allowed = Config.Attachments and Config.Attachments[weapon]
        if allowed then
            list[#list + 1] = {
                weapon      = weapon,
                attachments = allowed
            }
        end
    end

    return list
end

-- Bygger den data-payload NUI'et har brug for, ud fra
-- Config.LoadoutOrder / Config.Loadouts. Config forbliver source of truth.
local function BuildLoadoutPayload()
    local loadouts = {}

    for _, name in ipairs(Config.LoadoutOrder) do
        local cfg = Config.Loadouts[name]
        if cfg then
            loadouts[#loadouts + 1] = {
                name        = name,
                metadata    = cfg.metadata,
                icon        = cfg.icon or 'fa-solid fa-gun',
                image       = cfg.image,
                weapons     = cfg.weapons or {},
                items       = cfg.items or {},
                attachments = BuildAttachmentsPayload(cfg.weapons),
                isShop      = cfg.isShop == true
            }
        end
    end

    return loadouts
end

local function CloseLoadoutMenu()
    if not menuOpen then return end
    menuOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
end

-- ── PUBLIC ───────────────────────────────────────────────────

function OpenLoadoutMenu()
    if menuOpen then return end

    if not MM.Framework.IsPolice() then
        lib.notify({
            title       = 'Adgang nægtet',
            description = 'Du har ikke adgang til politiets våbenskab.',
            type        = 'error', position = 'center-right' })
        return
    end

    menuOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action    = 'open',
        imageBase = Config.LoadoutImageBasePath or 'nui://ox_inventory/web/images/',
        loadouts  = BuildLoadoutPayload()
    })
end

exports('OpenLoadoutMenu', OpenLoadoutMenu)

-- ── PED SPAWN + OX_TARGET ────────────────────────────────────

CreateThread(function()
    -- Vent på at state er klar
    while not MM.State do Wait(200) end
    Wait(500)

    for i, pedCfg in ipairs(Config.Peds) do
        lib.requestModel(pedCfg.model)

        local ped = CreatePed(
            4,
            GetHashKey(pedCfg.model),
            pedCfg.coords.x, pedCfg.coords.y, pedCfg.coords.z - 1.0,
            pedCfg.heading,
            false, true
        )

        FreezeEntityPosition(ped, true)
        SetEntityInvincible(ped, true)
        SetBlockingOfNonTemporaryEvents(ped, true)
        SetModelAsNoLongerNeeded(GetHashKey(pedCfg.model))

        pedsSpawned[#pedsSpawned + 1] = ped

        exports.ox_target:addLocalEntity(ped, {
            {
                name     = 'mm_loadout_' .. i,
                label    = pedCfg.label or 'Vælg Loadout',
                icon     = 'fa-solid fa-gun',
                distance = 2.0,
                canInteract = function()
                    return MM.Framework.IsPolice()
                end,
                onSelect = function()
                    OpenLoadoutMenu()
                end,
            }
        })
    end
end)

-- ── NUI CALLBACKS ────────────────────────────────────────────

RegisterNUICallback('close', function(_, cb)
    CloseLoadoutMenu()
    cb({ ok = true })
end)

RegisterNUICallback('selectLoadout', function(data, cb)
    if requestInProgress then
        cb({ ok = false, error = 'busy' })
        return
    end

    local name = data and data.name
    local cfg  = name and Config.Loadouts[name]

    if not cfg then
        lib.notify({
            title       = 'Loadout',
            description = 'Dette loadout findes ikke.',
            type        = 'error', position = 'center-right' })
        cb({ ok = false, error = 'not_found' })
        return
    end

    requestInProgress = true

    if cfg.isShop then
        -- Luk NUI FØRST, og vent lidt før ox_inventory åbner,
        -- for at undgå NUI focus-konflikter og race conditions.
        CloseLoadoutMenu()
        Wait(180)

        local success = pcall(function()
            exports.ox_inventory:openInventory('shop', { type = cfg.shopId })
        end)

        if success then
            lib.notify({
                title       = 'Politilager',
                description = 'Åbner politiets lager...',
                type        = 'success', position = 'center-right' })
        else
            lib.notify({
                title       = 'Politilager',
                description = 'Kunne ikke åbne politiets lager.',
                type        = 'error', position = 'center-right' })
        end
    else
        -- Eksisterende server-flow bibeholdes uændret.
        -- Serveren validerer job/loadout og sender selv success/error notify.
        TriggerServerEvent('mm_police:server:giveLoadout', name)
        CloseLoadoutMenu()
    end

    requestInProgress = false
    cb({ ok = true })
end)

-- ── CLEANUP ──────────────────────────────────────────────────
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end

    if menuOpen then
        SetNuiFocus(false, false)
        SendNUIMessage({ action = 'close' })
        menuOpen = false
    end

    for _, ped in ipairs(pedsSpawned) do
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
    pedsSpawned = {}
end)