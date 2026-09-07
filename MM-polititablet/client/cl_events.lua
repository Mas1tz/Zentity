-- ============================================================
--  kc_mdt | client/cl_events.lua
--  Inbound events from server → notify/UI updates
-- ============================================================

local SendNUI = function(action, data) KCC.SendNUI(action, data) end

-- ─── NOTIFICATIONS ───────────────────────────────────────────
RegisterNetEvent('kcmdt:notify', function(msg, ntype, duration)
    lib.notify({
        title       = 'MDT',
        description = msg,
        type        = ntype or 'inform',
        duration    = duration or 4000,
        position    = 'top-right',
    })
    if KCC.isOpen then SendNUI('notify', { msg = msg, type = ntype or 'inform' }) end
end)

-- ─── FORCE LOGOUT (timeout / status change) ──────────────────
RegisterNetEvent('kcmdt:forceLogout', function(reason)
    KCC.isLoggedIn = false
    KCC.StopGPS()
    lib.notify({ title='MDT', description=reason or 'Logget ud.', type='warning', duration=8000 })
    if KCC.isOpen then SendNUI('forceLogout', { reason = reason }) end
end)

-- ─── WARRANT ALERT ───────────────────────────────────────────
RegisterNetEvent('kcmdt:warrantAlert', function(data)
    if KCC.isOpen then SendNUI('warrantAlert', data) end
    if not data.removed then
        lib.notify({
            title='🚨 Ny Efterlysning',
            description=(data.reason or 'Ny efterlysning aktiv.'),
            type='error', duration=8000
        })
    end
end)

-- ─── NEW DISPATCH BROADCAST ──────────────────────────────────
RegisterNetEvent('kcmdt:newDispatch', function(data)
    if KCC.isOpen then SendNUI('newDispatch', data) end
    lib.notify({
        title       = '📡 Dispatch ' .. (data.code or ''),
        description = (data.description or ''),
        type        = 'warning',
        duration    = 10000,
    })
    -- Spil radio-lyd
    PlaySoundFrontend(-1, 'CHALLENGE_UNLOCKED', 'HUD_AWARDS', true)
end)

RegisterNetEvent('kcmdt:dispatchResolved', function(data)
    if KCC.isOpen then SendNUI('dispatchResolved', data) end
end)

-- ─── PATROL LIST ─────────────────────────────────────────────
RegisterNetEvent('kcmdt:updatePatrolList', function(list)
    if KCC.isOpen then SendNUI('updatePatrolList', list) end
end)

-- ─── PANIC ALERT ─────────────────────────────────────────────
RegisterNetEvent('kcmdt:panicAlert', function(data)
    lib.notify({
        title       = '⚠️ PANIC BUTTON',
        description = (data.officer or '?') .. ' aktiverede panikknap! Enhed: ' .. (data.unit or '-'),
        type        = 'error',
        duration    = 15000,
        position    = 'top',
    })
    if KCC.isOpen then SendNUI('panicAlert', data) end
    if data.coords_x and data.coords_y then
        SetNewWaypoint(data.coords_x + 0.0, data.coords_y + 0.0)
    end
    PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
end)

-- ─── POPUP MESSAGE (e.g. warrant ping, arrest ping) ──────────
RegisterNetEvent('kcmdt:popup', function(data)
    if not data then return end
    if data.type == 'warrant' then
        lib.notify({ title='🚨 Efterlysning', description=data.message, type='error', duration=10000 })
    elseif data.type == 'arrest' then
        lib.notify({ title='⚖️ Sigtelse', description=data.message, type='warning', duration=12000 })
    end
end)

-- ─── CASE CREATED BROADCAST ──────────────────────────────────
RegisterNetEvent('kcmdt:caseCreated', function(data)
    if KCC.isOpen then SendNUI('caseCreated', data) end
end)

-- ─── NEW MDT ACCOUNT CREATED (live update for bosses) ────────
RegisterNetEvent('kcmdt:newAccountCreated', function(data)
    if KCC.isOpen then SendNUI('newAccountCreated', data) end
end)

-- ─── ACCOUNT CREATED FOR ME (target side) ────────────────────
RegisterNetEvent('kcmdt:accountCreated', function(data)
    lib.alertDialog({
        header  = 'MDT-konto oprettet',
        content = ('Du har fået en ny MDT-konto.\n\n**Brugernavn:** %s\n**Adgangskode:** %s\n\nDu skal ændre adgangskoden ved første login. Brug **/%s** for at åbne MDT.'):format(
            data.username or '?', Config.RegisterMDT.defaultPassword, Config.Command),
        centered = true,
        size = 'md',
    })
end)