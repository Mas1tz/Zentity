--[[
    Selve AFSTANDS-tjekket sker på klienten (client/antiescape.lua), fordi
    det skal køre hvert par sekunder og server-side positionstjek for alle
    spillere samtidig ville være unødvendigt dyrt. Klienten kan IKKE selv
    sætte pausen eller undgå at blive teleporteret tilbage — den kan kun
    RAPPORTERE at den mener grænsen er overskredet, hvorefter serveren
    selv verificerer spillerens position, før noget som helst sker.
]]

-- Minimum tid (ms, GetGameTimer) mellem to escape-rapporter fra samme
-- spiller, så et NUI/event-spam-forsøg ikke kan spamme audit-loggen.
local REPORT_COOLDOWN_MS = 3000
local lastReportAt = {}

RegisterNetEvent('mm_sf:server:escapeDetected', function()
    local src = source
    local identifier = GetIdentifier(src)
    local data = identifier and Players[identifier]
    if not data or not data.inService then return end

    local now = GetGameTimer()
    if lastReportAt[identifier] and (now - lastReportAt[identifier]) < REPORT_COOLDOWN_MS then
        return
    end
    lastReportAt[identifier] = now

    local settings = Settings.AntiEscape()
    if not settings.enabled then return end

    local site = Config.Samfundstjeneste.Sites[data.inService]
    if not site then return end

    -- Server-side verifikation: stol ikke blindt på klientens egen
    -- vurdering af at den er uden for zonen.
    local ped = GetPlayerPed(src)
    if ped == 0 then return end

    local coords = GetEntityCoords(ped)
    local distance = #(coords - site.antiEscape.center)

    if distance <= site.antiEscape.radius then
        return -- klienten tog fejl (eller forsøgte at snyde) — ignorér
    end

    data.escape_pause_until = (os.time() * 1000) + (settings.pauseDuration * 1000)
    SavePlayer(identifier)

    InsertAuditLog('escape', identifier, data.name, identifier, data.name, {
        pauseDuration = settings.pauseDuration,
    })

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'Samfundstjeneste',
        description = ('Du har forsøgt at forlade området.\nAutomatisk opgavefjernelse er sat på pause i %d minutter.'):format(math.ceil(settings.pauseDuration / 60)),
        type = 'error',
        position = 'center-right',
    })

    TriggerClientEvent('mm_sf:client:teleportBack', src, site.sendCoords)
end)
