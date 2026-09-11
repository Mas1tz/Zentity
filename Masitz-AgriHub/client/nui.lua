-- ============================================================
--  Masitz-AgriHub | client/nui.lua
--  ALLE bridges mellem NUI (web/js/app.js) og Lua. Dette script
--  tager INGEN sikkerhedsbeslutninger selv — det sender ønsker videre
--  til server-callbacks og returnerer svaret uændret til NUI'en.
--  Se server/access.lua/§120: NUI'en erklærer aldrig selv adgang/rolle.
-- ============================================================

AH = AH or {}

local function cb(name, handler)
    RegisterNUICallback(name, function(data, cbFn)
        local ok, result = pcall(handler, data or {})
        if not ok then
            cbFn({ success = false, msg = 'Der opstod en klient-fejl.' })
            return
        end
        cbFn(result)
    end)
end

RegisterNUICallback('ready', function(_, cbFn) cbFn('ok') end)

-- ─── LOGIN / LOGOUT ──────────────────────────────────────────────
cb('login', function()
    local result = lib.callback.await('masitz_agrihub:login', false)
    if result and result.success then
        AH.LoggedIn = true
        AH.Role = result.role
    end
    return result
end)

cb('logout', function()
    TriggerServerEvent('masitz_agrihub:logout')
    AH.LoggedIn = false
    AH.Role = nil
    return { success = true }
end)

-- ─── STATISK VISNINGSDATA (fra det lokale shared config.lua — ren
--     display, ALT prisregning/adgang re-valideres server-side) ────
cb('shopCatalog', function()
    return Config.Agri.Shop
end)

cb('shopCounts', function()
    return lib.callback.await('masitz_agrihub:shop:counts', false)
end)

cb('farmerList', function()
    local out = {}
    for _, f in ipairs(Config.Agri.Farmers) do
        out[#out + 1] = { id = f.id, name = f.name, buys = f.buys, sells = f.sells, tasks = f.tasks, machines = f.machines, animalTypes = f.animalTypes }
    end
    return out
end)

cb('taskTypes', function()
    local out = {}
    for key, t in pairs(Config.Agri.TaskTypes) do
        out[key] = { label = t.label, icon = t.icon }
    end
    return out
end)

-- ─── INDKØB ──────────────────────────────────────────────────────
cb('shopPurchase', function(data)
    return lib.callback.await('masitz_agrihub:shop:purchase', false, data.cart, data.paymentMethod)
end)

-- ─── OPGAVER ─────────────────────────────────────────────────────
cb('tasksList', function()
    return lib.callback.await('masitz_agrihub:tasks:list', false)
end)

cb('tasksClaim', function(data)
    local result = lib.callback.await('masitz_agrihub:tasks:claim', false, data.taskId)
    if result and result.success then
        AH.CloseHub()
        AH.StartTask(result.task)
    end
    return result
end)

cb('tasksCancelActive', function()
    AH.CancelActiveTask()
    return { success = true }
end)

-- ─── UDLEJNING ───────────────────────────────────────────────────
cb('rentalCatalog', function()
    return AH.GetRentalCatalog()
end)

cb('rentalList', function()
    return AH.GetRentalList()
end)

cb('rentalNpcCreate', function(data)
    local result = AH.StartNpcRental(data.machine, data.paymentMethod, data.durationHours)
    if result and result.success then
        AH.CloseHub()
    end
    return result
end)

cb('rentalExtend', function(data)
    return AH.ExtendRental(data.contractId, data.extraHours)
end)

cb('rentalLookupPlayer', function(data)
    return AH.LookupRentalPlayer(data.query)
end)

cb('rentalOfferSublet', function(data)
    return AH.OfferSublet(data.sourceContractId, tonumber(data.targetServerId), data.targetName)
end)

cb('rentalRespondSublet', function(data)
    return AH.RespondToSublet(data.contractId, data.accept and true or false)
end)

cb('rentalSignContract', function(data)
    return AH.SignContract(data.contractId)
end)

cb('rentalCancelSublet', function(data)
    return AH.CancelSublet(data.contractId)
end)

-- ─── ADMIN (server genvalidérer SUPER_ADMIN live ved hvert kald) ──
cb('adminSearchPlayer', function(data)
    return lib.callback.await('masitz_agrihub:admin:searchPlayer', false, data.query)
end)

cb('adminGrantAccess', function(data)
    return lib.callback.await('masitz_agrihub:admin:grantAccess', false, data.targetId)
end)

cb('adminRevokeAccess', function(data)
    return lib.callback.await('masitz_agrihub:admin:revokeAccess', false, data.identifier)
end)

cb('adminListUsers', function()
    return lib.callback.await('masitz_agrihub:admin:listUsers', false)
end)

cb('adminGetLogs', function(data)
    return lib.callback.await('masitz_agrihub:admin:getLogs', false, data.filter)
end)

cb('adminSystemStatus', function()
    return lib.callback.await('masitz_agrihub:admin:systemStatus', false)
end)
