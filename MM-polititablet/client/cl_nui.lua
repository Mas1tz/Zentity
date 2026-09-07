-- ============================================================
--  kc_mdt | client/cl_nui.lua  (v2.0.3)
--  NUI ↔ Server bridge
--  ALLE callbacks sender ALDRIG nil til NUI — altid en table eller false,
--  så browseren altid får valid JSON og aldrig fejler på res.json().
-- ============================================================

-- Helper: kald et server-callback og garantér NUI altid får valid JSON
local function safeAwait(name, ...)
    local ok, result = pcall(lib.callback.await, name, false, ...)
    if not ok then
        print(('^1[kc_mdt cl_nui]^7 callback %s fejlede: %s'):format(name, tostring(result)))
        return {}
    end
    if result == nil then return {} end
    return result
end

-- ═══════════════════════════════════════════════════════════
--  CLOSE / META
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('close', function(_, cb)
    KCC.CloseMDT(); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  AUTH
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('login', function(data, cb)
    local res = safeAwait('kcmdt:login', data.username, data.password)
    if res and res.ok then
        KCC.isLoggedIn = true
        KCC.StartGPS()
    end
    cb(res)
end)

RegisterNUICallback('logout', function(_, cb)
    KCC.isLoggedIn = false
    KCC.StopGPS()
    TriggerServerEvent('kcmdt:logout')
    cb({ ok = true })
end)

RegisterNUICallback('changePassword', function(data, cb)
    cb(safeAwait('kcmdt:changePassword', data.oldPw, data.newPw))
end)

RegisterNUICallback('resetPassword', function(data, cb)
    cb(safeAwait('kcmdt:resetPassword', data.username, data.newPw))
end)

RegisterNUICallback('setAccountStatus', function(data, cb)
    cb(safeAwait('kcmdt:setAccountStatus', data.username, data.status))
end)

RegisterNUICallback('getRecentAccounts', function(_, cb)
    cb(safeAwait('kcmdt:getRecentAccounts'))
end)

-- ═══════════════════════════════════════════════════════════
--  DASHBOARD
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getDashboard', function(_, cb)
    cb(safeAwait('kcmdt:getDashboard'))
end)

RegisterNUICallback('getStaticConfig', function(_, cb)
    cb(safeAwait('kcmdt:getStaticConfig'))
end)

-- ═══════════════════════════════════════════════════════════
--  PERSONS
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('searchCitizens', function(data, cb)
    cb(safeAwait('kcmdt:searchCitizens', data.query))
end)

RegisterNUICallback('getCitizenFull', function(data, cb)
    local r = safeAwait('kcmdt:getCitizenFull', data.citizenid)
    -- Hvis ikke fundet, returnér en eksplicit struktur så JS kan håndtere det
    if not r or not r.user then
        cb({ user = nil })
    else
        cb(r)
    end
end)

RegisterNUICallback('updateCitizen', function(data, cb)
    TriggerServerEvent('kcmdt:updateCitizen', data); cb({ ok = true })
end)

RegisterNUICallback('addJournal', function(data, cb)
    TriggerServerEvent('kcmdt:addJournal', data.citizenid, data.title, data.body); cb({ ok = true })
end)
RegisterNUICallback('deleteJournal', function(data, cb)
    TriggerServerEvent('kcmdt:deleteJournal', data.id); cb({ ok = true })
end)
RegisterNUICallback('createArrest', function(data, cb)
    TriggerServerEvent('kcmdt:createArrest', data); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  WARRANTS
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getWarrants', function(_, cb)
    cb(safeAwait('kcmdt:getWarrants'))
end)
RegisterNUICallback('addWarrant', function(data, cb)
    TriggerServerEvent('kcmdt:addWarrant', data.citizenid, data.reason, data.risk_level, data.image); cb({ ok = true })
end)
RegisterNUICallback('removeWarrant', function(data, cb)
    TriggerServerEvent('kcmdt:removeWarrant', data.citizenid); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  VEHICLES
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('searchVehicle', function(data, cb)
    local res = safeAwait('kcmdt:searchVehicle', data.plate)
    if res and res.found and res.props and res.props.model then
        local hash = type(res.props.model) == 'number' and res.props.model or GetHashKey(res.props.model)
        local disp = GetDisplayNameFromVehicleModel(hash)
        local lbl  = GetLabelText(disp)
        res.modelName = (lbl ~= '' and lbl ~= 'NULL') and lbl or disp
    end
    cb(res)
end)
RegisterNUICallback('updateVehicleRecord', function(data, cb)
    TriggerServerEvent('kcmdt:updateVehicleRecord', data.plate, data.flags); cb({ ok = true })
end)
RegisterNUICallback('addTrafficStop', function(data, cb)
    TriggerServerEvent('kcmdt:addTrafficStop', data.plate, data.notes); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  CASES
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getCases', function(data, cb)
    cb(safeAwait('kcmdt:getCases', data))
end)
RegisterNUICallback('getCase', function(data, cb)
    cb(safeAwait('kcmdt:getCase', data.id))
end)
RegisterNUICallback('createCase', function(data, cb)
    TriggerServerEvent('kcmdt:createCase', data); cb({ ok = true })
end)
RegisterNUICallback('updateCase', function(data, cb)
    TriggerServerEvent('kcmdt:updateCase', data); cb({ ok = true })
end)
RegisterNUICallback('addCaseComment', function(data, cb)
    TriggerServerEvent('kcmdt:addCaseComment', data.case_id, data.body); cb({ ok = true })
end)
RegisterNUICallback('addEvidence', function(data, cb)
    TriggerServerEvent('kcmdt:addEvidence', data); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  ONLINE PLAYERS (Personregister §10)
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getOnlinePlayers', function(_, cb)
    cb(safeAwait('kcmdt:getOnlinePlayers'))
end)

-- ═══════════════════════════════════════════════════════════
--  ARREST DRAFTS (autosave §21)
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getArrestDraft', function(data, cb)
    local r = safeAwait('kcmdt:getArrestDraft', data.citizenid)
    cb(r or { payload = nil })
end)
RegisterNUICallback('saveArrestDraft', function(data, cb)
    TriggerServerEvent('kcmdt:saveArrestDraft', data.citizenid, data.payload); cb({ ok = true })
end)
RegisterNUICallback('deleteArrestDraft', function(data, cb)
    TriggerServerEvent('kcmdt:deleteArrestDraft', data.citizenid); cb({ ok = true })
end)

-- ═══════════════════════════════════════════════════════════
--  CHARGES / LAWS
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('getCharges', function(_, cb)
    cb(safeAwait('kcmdt:getCharges'))
end)
RegisterNUICallback('getLaws', function(data, cb)
    cb(safeAwait('kcmdt:getLaws', data.query))
end)

-- ═══════════════════════════════════════════════════════════
--  DISPATCH
--  Under udvikling (§9) — menuen er låst i NUI'en, så der er ingen
--  aktiv UI-flow der kalder ind i dispatch-serverkoden fra klienten
--  endnu. Server-siden (sv_dispatch.lua) er bevaret uændret og klar
--  til at blive koblet på, når funktionen færdiggøres i en senere fase.
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
--  PATROL
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('joinUnit', function(data, cb)
    TriggerServerEvent('kcmdt:joinUnit', data.unit_call); cb({ ok = true })
end)
RegisterNUICallback('setUnitStatus', function(data, cb)
    TriggerServerEvent('kcmdt:setUnitStatus', data.status); cb({ ok = true })
end)
RegisterNUICallback('getPatrolUnits', function(_, cb)
    cb(safeAwait('kcmdt:getPatrolUnits'))
end)
RegisterNUICallback('getDutyTime', function(_, cb)
    local sec = safeAwait('kcmdt:getDutyTime')
    cb({ seconds = tonumber(sec) or 0 })
end)

-- ═══════════════════════════════════════════════════════════
--  WAYPOINT
-- ═══════════════════════════════════════════════════════════
RegisterNUICallback('setWaypoint', function(data, cb)
    local x = tonumber(data.x); local y = tonumber(data.y)
    if x and y then
        SetNewWaypoint(x, y)
        lib.notify({ title='Waypoint', description='Markeret på GPS', type='inform' })
    end
    cb({ ok = true })
end)