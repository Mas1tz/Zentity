-- ============================================================
-- MM-PolitiJob - server/panic.lua
-- Panic: kun politi, broadcast til alle politi
-- Anti-spam: server-side cooldown
-- ============================================================

local panicCooldowns = {}  -- [src] = true (cooldown aktiv)

RegisterNetEvent('mm_police:server:panic', function(state)
    local src = source

    -- Validering
    if not SV.Framework.IsPolice(src) then return end

    -- Anti-spam cooldown (server-side)
    if state and panicCooldowns[src] then return end

    if state then
        panicCooldowns[src] = true
        SetTimeout(Config.PanicCooldown or 30000, function()
            panicCooldowns[src] = nil
        end)
    end

    local name   = SV.Framework.GetName(src)
    local ped    = GetPlayerPed(src)
    local coords = DoesEntityExist(ped) and GetEntityCoords(ped) or nil

    -- Send kun til politi
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        if pid ~= src and SV.Framework.IsPolice(pid) then
            TriggerClientEvent('mm_police:client:panicAlert', pid,
                src, name, coords, state)
        end
    end

    -- ── RØD /me VED AKTIVERING ────────────────────────────────
    -- REWORK: rigtig /me-besked ("Udløser Panikknap!") i rødt til
    -- nærtstående spillere, i stedet for kun en notification.
    if state and coords then
        local meText = ('** %s Udløser Panikknap! **'):format(name)
        local radius = Config.PanicMeRadius or 20.0

        for _, playerId in ipairs(GetPlayers()) do
            local pid = tonumber(playerId)
            local otherPed = GetPlayerPed(pid)
            if DoesEntityExist(otherPed) then
                local dist = #(coords - GetEntityCoords(otherPed))
                if dist <= radius then
                    TriggerClientEvent('chat:addMessage', pid, {
                        color     = { 255, 0, 0 },
                        multiline = true,
                        args      = { '', meText },
                    })
                end
            end
        end
    end
end)

-- Cleanup ved disconnect
AddEventHandler('playerDropped', function()
    panicCooldowns[source] = nil
end)