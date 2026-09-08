-- ============================================================
-- MM-PolitiJob – client/functions/panic.lua
-- Panic knap: Y – kun politi on-duty, cooldown, lyd, blip
-- Server-valideret, anti-spam, proper cleanup
-- ============================================================

local panicBlips   = {}  -- blips modtaget fra andre
local panicActive  = false
local panicOnCooldown = false

-- ── KEY BIND ─────────────────────────────────────────────────
RegisterCommand('panicbutton', function()
    if not MM.Framework.IsPolice() then
        lib.notify({ title = 'Panic', description = 'Du er ikke ansat i politiet.', type = 'error', position = 'center-right' })
        return
    end

    if panicOnCooldown then
        lib.notify({ title = 'Panic', description = 'Cooldown aktiv – vent venligst.', type = 'error', duration = 2000, position = 'center-right' })
        return
    end

    if panicActive then
        -- Deaktivér
        panicActive = false
        TriggerServerEvent('mm_police:server:panic', false)
        lib.notify({ title = 'Panic', description = 'Panikalarm deaktiveret.', type = 'inform', duration = 4000, position = 'center-right' })
    else
        -- Aktivér
        -- REWORK: fjernet den tidligere 2-sekunders arrest-animation
        -- ('random@arrests'/'generic_radio_chatter') — panic skal være
        -- hurtig og øjeblikkelig, ikke spærre spilleren i en animation.
        -- Serveren sender nu en rigtig rød /me ("Udløser Panikknap!")
        -- til nærtstående spillere i stedet.
        panicActive = true
        panicOnCooldown = true

        -- Lyd
        PlaySoundFrontend(-1, Config.PanicSound, 'HintCamSounds', true)

        TriggerServerEvent('mm_police:server:panic', true)

        lib.notify({
            title       = '🚨 PANIKALARM',
            description = 'Allarmen er aktiveret! Kollegerne er notificeret.',
            type        = 'error',
            duration    = 6000,
            position    = 'center-right',
        })

        -- Cooldown timer
        SetTimeout(Config.PanicCooldown, function()
            panicOnCooldown = false
        end)
    end
end, false)

RegisterKeyMapping('panicbutton', 'Aktiver Panikalarm', 'keyboard', Config.PanicKey)

-- ── MODTAG PANIC FRA ANDEN BETJENT ───────────────────────────
RegisterNetEvent('mm_police:client:panicAlert', function(serverId, playerName, coords, state)
    -- Fjern gammelt blip for denne spiller hvis det eksisterer
    if panicBlips[serverId] then
        if DoesBlipExist(panicBlips[serverId]) then
            RemoveBlip(panicBlips[serverId])
        end
        panicBlips[serverId] = nil
    end

    if not state then return end  -- Deaktivering – blip er allerede fjernet

    -- Vis notifikation
    lib.notify({
        title       = '🚨 PANIKKNAP',
        description = ('%s aktiverede panikknappen!'):format(playerName),
        type        = 'error',
        duration    = 8000,
        position    = 'center-right',
    })

    -- Lyd
    PlaySoundFrontend(-1, Config.PanicSound, 'HintCamSounds', true)

    -- Opret blip
    if coords then
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 161)     -- Panic ikon
        SetBlipColour(blip, 1)       -- Rød
        SetBlipScale(blip, 1.5)
        SetBlipAsShortRange(blip, false)
        SetBlipFlashes(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString('PANIK: ' .. playerName)
        EndTextCommandSetBlipName(blip)

        panicBlips[serverId] = blip

        -- Automatisk fjern efter Config.PanicBlipTime
        SetTimeout(Config.PanicBlipTime, function()
            if panicBlips[serverId] and DoesBlipExist(panicBlips[serverId]) then
                RemoveBlip(panicBlips[serverId])
                panicBlips[serverId] = nil
            end
        end)
    end
end)

-- ── CLEANUP VED RESOURCE STOP ────────────────────────────────
-- FIX: brugte tidligere 'onResourceStop' (server-side event) i et
-- client-script - blev derfor aldrig kaldt.
AddEventHandler('onClientResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, blip in pairs(panicBlips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
    end
    panicBlips = {}
end)