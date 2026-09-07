--[[
    server/main.lua er bootstrap-laget: det binder Config.Commands sammen
    med Permissions og Players, og fortæller klienten hvilken rolle
    dashboardet skal åbne i.

    VIGTIGT: "role" der sendes til klienten bestemmer KUN hvad NUI'en
    VISER (fx om Staff/Owner-fanerne overhovedet vises). Det er IKKE en
    autorisation. Enhver reel handling (give opgaver, ændre trust factor
    osv., se server/staff.lua og server/owner.lua) validerer permission
    igen server-side via Permissions.IsStaff/IsOwner. En spiller kan
    aldrig få adgang til staff/owner-funktioner ved blot at manipulere
    den client-side "role"-værdi, fordi den værdi aldrig bruges til
    andet end UI-visning.
]]

local function OpenDashboard(source)
    local src = source

    if src == 0 then
        print('^3[Masitz-samfundstjeneste]^7 Kommandoen kan ikke bruges fra konsollen.')
        return
    end

    local playerData = GetOrCreatePlayerBySource(src)
    if not playerData then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Samfundstjeneste',
            description = 'Kunne ikke hente dine data. Prøv igen om lidt.',
            type = 'error',
            position = 'center-right',
        })
        return
    end

    local role = 'player'
    if Permissions.IsOwner(src) then
        role = 'owner'
    elseif Permissions.IsStaff(src) then
        role = 'staff'
    end

    TriggerClientEvent('mm_sf:client:openDashboard', src, role, playerData)
end

for _, commandName in ipairs(Config.Samfundstjeneste.Commands) do
    RegisterCommand(commandName, function(source)
        OpenDashboard(source)
    end, false)
end

-- ------------------------------------------------------------
-- HISTORIK
-- Returnerer KUN den kaldende spillers egen historik. Der er bevidst
-- ikke noget "target"-parameter her — funktionen kan fysisk ikke bruges
-- til at hente andres historik, uanset hvad en manipuleret NUI-callback
-- måtte sende med.
-- ------------------------------------------------------------
lib.callback.register('mm_sf:server:getHistory', function(source)
    local identifier = GetIdentifier(source)
    if not identifier or not DatabaseReady then
        return {}
    end

    local rows = exports.oxmysql:querySync(
        'SELECT amount, reason, actor_name, created_at FROM sf_history WHERE identifier = ? ORDER BY created_at DESC LIMIT 50',
        { identifier }
    )

    return rows or {}
end)

