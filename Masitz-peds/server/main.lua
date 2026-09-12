-- ============================================================
--  Masitz-peds | server/main.lua
--  Den ENESTE server-authoritative overflade i resourcen: en
--  interaktions-gateway. Klienten sender KUN et ped-id + et
--  option-navn (identifikatorer, ikke data) — serveren slår selv den
--  rigtige config-entry op og genvaliderer job/gruppe + afstand, FØR
--  den videresender til det event jeres egen (følsomme) logik lytter
--  på. Intet fra klienten stoles på direkte.
--
--  Noclip/Revive/Lobby findes ikke her — Masitz-peds har INGEN andre
--  server-events end denne ene, fordi peds/target/TextUI i sig selv
--  ikke rører ved noget der kræver server-tillid.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[Masitz-peds] ' .. fmt):format(...))
    end
end

local function LogSecurity(src, fmt, ...)
    print(('^1[Masitz-peds SECURITY]^7 src=%s: ' .. fmt):format(src, ...))
end

-- Samme distance-buffer for alle options — ekstra plads til
-- netværks-latency ift. den afstand ox_target allerede krævede
-- client-side.
local DISTANCE_TOLERANCE = 2.0

local function FindAction(pedCfg, optionName)
    if pedCfg.textui and pedCfg.textui.enabled and optionName == nil then
        return pedCfg.textui
    end
    if pedCfg.target and pedCfg.target.enabled and optionName then
        for _, opt in ipairs(pedCfg.target.options) do
            if opt.name == optionName then return opt end
        end
    end
    return nil
end

local function PassesGroups(xPlayer, groups)
    if not groups then return true end
    local job = xPlayer.job
    if not job then return false end
    local requiredGrade = groups[job.name]
    if requiredGrade == nil then return false end
    return (job.grade or 0) >= requiredGrade
end

local function IsWithinDistance(src, coords, maxDistance)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return false end

    local playerCoords = GetEntityCoords(ped)
    local dx = playerCoords.x - coords.x
    local dy = playerCoords.y - coords.y
    local dz = playerCoords.z - coords.z
    local distSq = dx * dx + dy * dy + dz * dz

    return distSq <= (maxDistance * maxDistance)
end

RegisterNetEvent('Masitz-peds:server:interact', function(pedId, optionName)
    local src = source

    if type(pedId) ~= 'string' then
        LogSecurity(src, 'sendte et ugyldigt ped-id (%s).', tostring(pedId))
        return
    end

    local pedCfg = Config.PedsById[pedId]
    if not pedCfg then
        LogSecurity(src, 'forsøgte at interagere med et ukendt ped-id "%s".', pedId)
        return
    end

    local action = FindAction(pedCfg, optionName)
    if not action then
        LogSecurity(src, 'forsøgte en ukendt option "%s" på ped "%s".', tostring(optionName), pedId)
        return
    end

    if not action.serverEvent then
        LogSecurity(src, 'forsøgte at trigge gatewayen for en option uden serverEvent ("%s" på "%s").', tostring(optionName), pedId)
        return
    end

    local xPlayer = ESX.GetPlayerFromId(src)
    if not xPlayer then
        LogSecurity(src, 'har ingen gyldig ESX-spillerdata.')
        return
    end

    if not PassesGroups(xPlayer, action.groups) then
        LogSecurity(src, 'opfylder ikke job/gruppe-kravet for "%s" på ped "%s".', tostring(optionName), pedId)
        return
    end

    local maxDistance = (action.distance or (pedCfg.target and pedCfg.target.distance) or (pedCfg.textui and pedCfg.textui.distance) or 3.0) + DISTANCE_TOLERANCE
    if not IsWithinDistance(src, pedCfg.coords, maxDistance) then
        LogSecurity(src, 'er for langt fra ped "%s" til at interagere.', pedId)
        return
    end

    DebugPrint('Gateway godkendt: src=%s ped=%s option=%s -> %s', src, pedId, tostring(optionName), action.serverEvent)
    TriggerEvent(action.serverEvent, src, pedId, optionName)
end)
