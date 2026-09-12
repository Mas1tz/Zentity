-- ============================================================
--  MPvp-radial | server/main.lua
--  Kun ÉT server event: report. Noclip og Lobby er rent client-side
--  (selv-kun, ingen server-tillid nødvendig). Revive er ligeledes
--  client-side (uændret esx_ambulancejob-integration).
--
--  Report er 100% server-autoritativt: klientens input bruges KUN til
--  at slå spiller-ID op og som ren tekst — alt valideres/saniteres
--  igen her, uanset hvad client/main.lua allerede tjekkede.
-- ============================================================

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[MPvp-radial] ' .. fmt):format(...))
    end
end

-- ─── DISCORD-LOGGING (kun server-side URL) ────────────────────────
local function SendWebhook(title, color, fields)
    if not Config.Report.webhook or Config.Report.webhook == '' then return end

    local embedFields = {}
    for _, f in ipairs(fields) do
        embedFields[#embedFields + 1] = { name = f[1], value = tostring(f[2] ~= nil and f[2] ~= '' and f[2] or 'n/a'), inline = f[3] ~= false }
    end

    local payload = {
        username = Config.Report.username or 'MPvp Reports',
        embeds = { { title = title, color = color, fields = embedFields, timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ') } },
    }

    PerformHttpRequest(Config.Report.webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function NotifyStaff(reporterName, targetName, reason)
    if not Config.Report.notifyAce then return end

    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid and IsPlayerAceAllowed(pid, Config.Report.notifyAce) then
            TriggerClientEvent('mpvp_radial:staffAlert', pid, reporterName, targetName, reason)
        end
    end
end

-- ─── ANTI-SPAM (server-side, pr. spiller) ─────────────────────────
local lastReportAt = {}

local function CheckReportCooldown(src)
    local now = GetGameTimer()
    local last = lastReportAt[src]
    if last and (now - last) < Config.Report.cooldown then
        return false
    end
    lastReportAt[src] = now
    return true
end

AddEventHandler('playerDropped', function()
    lastReportAt[source] = nil
end)

-- ─── HOVED-HANDLER ─────────────────────────────────────────────────
RegisterNetEvent('mpvp_radial:report', function(targetId, reason)
    local src = source

    if not Config.Report.enabled then return end

    if not CheckReportCooldown(src) then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, ('Vent %d sekunder mellem hver report.'):format(math.ceil(Config.Report.cooldown / 1000)))
        return
    end

    -- Spiller-ID skal være et gyldigt, ikke-negativt heltal.
    targetId = tonumber(targetId)
    if not targetId or targetId ~= math.floor(targetId) or targetId < 0 then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, 'Ugyldigt spiller-ID.')
        DebugPrint('Ugyldigt spiller-ID forsøgt af src=%s: %s', tostring(src), tostring(targetId))
        return
    end

    if targetId == src then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, 'Du kan ikke rapportere dig selv.')
        return
    end

    local targetName = GetPlayerName(targetId)
    if not targetName then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, 'Spilleren blev ikke fundet.')
        return
    end

    -- Årsagen skal være en streng, saniteret og hård-begrænset i længde
    -- SERVER-side — klientens egen min/max i inputDialog er kun UX og
    -- stoles aldrig på.
    if type(reason) ~= 'string' then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, 'Ugyldig årsag.')
        return
    end

    reason = reason:gsub('[%c]', '') -- fjern kontroltegn (nye linjer, etc.)
    reason = reason:gsub('^%s+', ''):gsub('%s+$', '')
    reason = reason:sub(1, Config.Report.maxReasonLength)

    if #reason < Config.Report.minReasonLength then
        TriggerClientEvent('mpvp_radial:reportResult', src, false, 'Årsagen er for kort.')
        return
    end

    local reporterName = GetPlayerName(src) or 'Ukendt'

    SendWebhook('🚩 Ny report', 0xC98B8B, {
        { 'Rapportør', ('%s (%s)'):format(reporterName, src) },
        { 'Rapporteret', ('%s (%s)'):format(targetName, targetId) },
        { 'Årsag', reason, false },
    })
    NotifyStaff(reporterName, targetName, reason)
    DebugPrint('Report: %s (%s) -> %s (%s): %s', reporterName, src, targetName, targetId, reason)

    TriggerClientEvent('mpvp_radial:reportResult', src, true, 'Din report er blevet sendt til staff.')
end)
