-- ============================================================
--  Masitz-mehandler | client/client.lua
--
--  Detekterer relevante spillerhandlinger og sender automatisk den
--  tilhørende /me-besked. Se README.md for en fuld forklaring af
--  hvordan ox_inventory-detektionen fungerer uden at hooke et
--  bestemt keybind.
-- ============================================================

if not lib then return end

local M = Config.MeHandler

local function DebugPrint(fmt, ...)
    if not M.Debug then return end
    print(('[Masitz-mehandler] ' .. fmt):format(...))
end

-- ------------------------------------------------------------------
--  /ME-DISPATCH
-- ------------------------------------------------------------------

local function SendMe(message)
    local integ = M.MeIntegration

    if integ.Mode == 'event' then
        if not integ.Event then
            DebugPrint('MeIntegration.Mode er "event", men intet Event er konfigureret - besked droppet.')
            return
        end
        TriggerEvent(integ.Event, message)
        return
    end

    -- 'command' (standard): udføres PRÆCIS som hvis spilleren selv
    -- havde skrevet det i chatten. FiveM videresender automatisk
    -- ukendte client-side kommandoer til serveren med spillerens
    -- rigtige source bevaret, så dette virker uanset om /me er
    -- registreret client- eller server-side.
    ExecuteCommand(('%s %s'):format(integ.Command, message))
end

-- ------------------------------------------------------------------
--  CENTRAL HANDLINGS-TRIGGER
--  Alt (auto-detektion OG manuelle export-kald) går igennem denne
--  ene funktion, så cooldown/enabled-tjek kun findes ét sted.
-- ------------------------------------------------------------------

local lastActionTime = {}

local function FireAction(actionId, overrideMessage)
    if not actionId then return false end
    if not M.Enabled then return false end

    local action = M.Actions[actionId]
    if not action or not action.enabled then
        DebugPrint('Handling "%s" er deaktiveret eller findes ikke - ignoreret.', tostring(actionId))
        return false
    end

    local now = GetGameTimer()
    local cooldown = action.cooldown or M.Cooldown
    local last = lastActionTime[actionId]
    if last and (now - last) < cooldown then
        DebugPrint('Handling "%s" blokeret af cooldown (%dms tilbage).', actionId, cooldown - (now - last))
        return false
    end
    lastActionTime[actionId] = now

    local message = overrideMessage or action.message
    SendMe(message)
    DebugPrint('/me sendt for handling "%s": %s', actionId, message)
    return true
end

-- ============================================================
--  EXPORTS - grundlaget for nem udvidelse senere
-- ============================================================

exports('TriggerAction', FireAction)

exports('RegisterAction', function(actionId, def)
    if type(actionId) ~= 'string' or type(def) ~= 'table' or type(def.message) ~= 'string' then
        DebugPrint('RegisterAction kaldt med ugyldige argumenter.')
        return false
    end
    M.Actions[actionId] = {
        enabled = def.enabled ~= false,
        message = def.message,
        cooldown = def.cooldown,
    }
    DebugPrint('Ny handling registreret via export: %s', actionId)
    return true
end)

exports('IsActionEnabled', function(actionId)
    local action = M.Actions[actionId]
    return action ~= nil and action.enabled == true
end)

exports('SetActionEnabled', function(actionId, enabled)
    local action = M.Actions[actionId]
    if not action then return false end
    action.enabled = enabled and true or false
    return true
end)

-- ============================================================
--  HJÆLPEFUNKTIONER
-- ============================================================

-- Enkelt, billig scan af nærliggende køretøjer. Kaldes KUN på
-- veldefinerede "edges" (inventar åbnet/lukket, dør-poll mens tæt på
-- et køretøj) - aldrig som en løbende per-frame operation.
local function GetNearestVehicle(coords, maxDist)
    local vehicles = GetGamePool('CVehicle')
    local closest, closestDist = nil, maxDist

    for i = 1, #vehicles do
        local v = vehicles[i]
        local dist = #(coords - GetEntityCoords(v))
        if dist <= closestDist then
            closest = v
            closestDist = dist
        end
    end

    return closest, closest and closestDist or nil
end

-- ============================================================
--  OX_INVENTORY-DETEKTION
--
--  ox_inventory sætter altid 'invOpen' på spillerens EGEN player
--  state bag ('player:<serverId>') lige inden UI'et åbnes/lukkes -
--  uanset om det blev udløst af ox_inventory's eget 'inv2'-keybind,
--  et ox_target-valg, et andet script der kalder
--  exports.ox_inventory:openInventory(...), eller et server-tvunget
--  open. Vi lytter derfor på selve DETTE state bag-flag i stedet for
--  at gætte på et bestemt keybind eller command - det gør
--  detektionen fuldstændig uafhængig af hvilken fysisk tast/keybind
--  spilleren selv har sat i FiveM Settings.
--
--  State bags fyrer KUN handleren ved en reel værdiændring, så der
--  er ingen indbygget risiko for dobbelt-/spam-fyring fra selve
--  denne mekanisme.
--
--  ox_inventory afslører ikke selv HVILKEN inventar-type der blev
--  åbnet (kun at "en" blev åbnet), så vi klassificerer selv ud fra
--  samme logik ox_inventory bruger internt:
--    - Spiller sidder i et køretøj  -> handskerum (ox_inventory har
--      ingen anden inventar-mulighed mens man sidder i en bil).
--    - Spiller står tæt på et køretøj (samme radius som
--      ox_inventory's egen trunk-adgangstjek) -> bagagerum.
--    - Ellers -> ukendt (spillerens eget inventar, en stash, en
--      shop, en anden spillers inventar osv.) - der sendes bevidst
--      INGEN /me for disse, da vi ikke kan skelne dem pålideligt
--      udefra uden at ændre i selve ox_inventory.
-- ============================================================

local currentInvContext = nil -- nil | 'trunk' | 'glovebox' | 'other'

local function ClassifyAndFireOpen()
    if cache.vehicle then
        currentInvContext = 'glovebox'
        DebugPrint('ox_inventory åbnet: handskerum (spiller sidder i køretøj).')
        FireAction(M.Inventory.GloveboxAction.open)
        return
    end

    local vehicle, dist = GetNearestVehicle(GetEntityCoords(cache.ped), M.Inventory.TrunkProximity)
    if vehicle then
        currentInvContext = 'trunk'
        DebugPrint('ox_inventory åbnet: bagagerum (køretøj %.2fm væk, indenfor %.2fm).', dist, M.Inventory.TrunkProximity)
        FireAction(M.Inventory.TrunkAction.open)
        return
    end

    currentInvContext = 'other'
    DebugPrint('ox_inventory åbnet, men kunne ikke klassificeres som bagagerum/handskerum - ingen /me sendt.')
end

local function FireCloseForContext()
    if currentInvContext == 'glovebox' then
        FireAction(M.Inventory.GloveboxAction.close)
    elseif currentInvContext == 'trunk' then
        FireAction(M.Inventory.TrunkAction.close)
    end
    currentInvContext = nil
end

CreateThread(function()
    local serverId = GetPlayerServerId(PlayerId())
    while serverId == 0 do
        Wait(500)
        serverId = GetPlayerServerId(PlayerId())
    end

    local stateId = ('player:%s'):format(serverId)

    AddStateBagChangeHandler('invOpen', stateId, function(_, _, value)
        if not M.Enabled then return end
        if GetResourceState('ox_inventory') ~= 'started' then return end

        if value then
            ClassifyAndFireOpen()
        else
            FireCloseForContext()
        end
    end)

    DebugPrint('State bag-lytter for ox_inventory (invOpen) er nu aktiv for player:%s.', serverId)
end)
