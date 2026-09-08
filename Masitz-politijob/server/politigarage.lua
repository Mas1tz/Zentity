-- ============================================================
-- MM-PolitiJob – server/politigarage.lua  REWORK
-- Garagen kørte tidligere 100% client-side: enhver klient kunne
-- spawne og "parkere" (slette) et vilkårligt køretøj uden at
-- serveren nogensinde blev spurgt. ParkVehicle havde intet
-- jobtjek overhovedet client-side, hvilket var den direkte årsag
-- til at alle spillere kunne parkere biler i politi-garagen.
--
-- Nu er garagen server-godkendt:
--   1. Klienten beder om lov til at spawne en model (job + model
--      valideres mod Config.Vehicles + et loft pr. spiller).
--   2. Klienten spawner (uundgåeligt lokalt i FiveM), og
--      REGISTRERER netId'et hos serveren, som gemmer det i en
--      pr.-spiller liste over "legitimt spawnede" køretøjer.
--   3. Parkering kræver at netId'et findes i den liste, OG at
--      køretøjets faktiske model stadig matcher whitelisten
--      (server-side native-tjek af det networked entity).
-- ============================================================

-- ── BYG MODEL-WHITELIST UD FRA Config.Vehicles ───────────────
local validModels  = {}   -- [modelName] = true
local heliModels   = {}   -- [modelName] = true (kun Config.Vehicles.Heli)

for category, list in pairs(Config.Vehicles or {}) do
    for _, v in ipairs(list) do
        validModels[v.model] = true
        if category == 'Heli' then
            heliModels[v.model] = true
        end
    end
end

-- ── TRACKING: hvilke køretøjer har hver spiller hentet ud ─────
local spawnedVehicles = {}   -- [src] = { [netId] = model }
local pendingApproval  = {}  -- [src] = { model = ..., expires = GetGameTimer()+N }

local function CountSpawned(src)
    local n = 0
    for _ in pairs(spawnedVehicles[src] or {}) do n = n + 1 end
    return n
end

-- ── ANMOD OM AT SPAWNE ────────────────────────────────────────
lib.callback.register('mm_police:cb:requestSpawnVehicle', function(src, model, spawnType)
    if not SV.Framework.IsPolice(src) then
        return false, 'Du er ikke ansat i politiet.'
    end

    if type(model) ~= 'string' or not validModels[model] then
        if Config.Debug then
            print(('[MM-PolitiJob] %s forsøgte at spawne ukendt model: %s'):format(src, tostring(model)))
        end
        return false, 'Ukendt køretøj.'
    end

    if spawnType == 'heli' and not heliModels[model] then
        return false, 'Den model er ikke en helikopter.'
    end
    if spawnType ~= 'heli' and heliModels[model] then
        return false, 'Brug helikopter-garagen til den model.'
    end

    if CountSpawned(src) >= (Config.GarageMaxVehicles or 3) then
        return false, ('Du har allerede %d køretøjer ude. Parkér et først.'):format(Config.GarageMaxVehicles or 3)
    end

    pendingApproval[src] = { model = model, expires = GetGameTimer() + 15000 }
    return true
end)

-- ── REGISTRÉR ET SPAWNET KØRETØJ ─────────────────────────────
RegisterNetEvent('mm_police:server:registerSpawnedVehicle', function(netId)
    local src = source
    netId = tonumber(netId)

    local approval = pendingApproval[src]
    pendingApproval[src] = nil

    if not netId or not approval or GetGameTimer() > approval.expires then
        if Config.Debug then
            print(('[MM-PolitiJob] %s forsøgte at registrere køretøj uden gyldig godkendelse.'):format(src))
        end
        return
    end

    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end

    local model = GetEntityModel(entity)
    -- Bekræft at det networked køretøj rent faktisk har den model vi godkendte
    local ok = false
    for name in pairs(validModels) do
        if GetHashKey(name) == model then
            ok = (name == approval.model)
            break
        end
    end
    if not ok then return end

    spawnedVehicles[src] = spawnedVehicles[src] or {}
    spawnedVehicles[src][netId] = approval.model
end)

-- ── PARKÉR (KUN KØRETØJER SPAWNET VIA GARAGEN) ───────────────
lib.callback.register('mm_police:cb:parkVehicle', function(src, netId)
    if not SV.Framework.IsPolice(src) then return false end

    netId = tonumber(netId)
    if not netId then return false end

    local owned = spawnedVehicles[src] and spawnedVehicles[src][netId]
    if not owned then
        if Config.Debug then
            print(('[MM-PolitiJob] %s forsøgte at parkere et køretøj de ikke selv har hentet.'):format(src))
        end
        return false
    end

    spawnedVehicles[src][netId] = nil
    return true
end)

-- ── CLEANUP ───────────────────────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    spawnedVehicles[src] = nil
    pendingApproval[src] = nil
end)
