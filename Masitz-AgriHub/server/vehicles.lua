-- ============================================================
--  Masitz-AgriHub | server/vehicles.lua
--  Plate-generering, server-side spawned-vehicle-registry,
--  MM-vehiclekeys-integration.
-- ============================================================

AH = AH or {}

-- [plate] = { src=, type='task'|'rental'|'diesel'|'equipment', refId=, model= }
AH.ActiveVehicles = {}

-- ─── PLATES (§37, §69) — unikke, max 8 tegn, kollisions-tjekket ──
function AH.GenerateJobPlate()
    for i = 1, 999 do
        local plate = ('%s%03d'):format(Config.Agri.Plates.jobPrefix, i)
        if #plate <= Config.Agri.Plates.maxLength and not AH.ActiveVehicles[plate] then
            return plate
        end
    end
    return nil
end

function AH.GenerateRentalPlate()
    for i = 1, 99 do
        local plate = ('%s%02d'):format(Config.Agri.Plates.rentalPrefix, i)
        if #plate <= Config.Agri.Plates.maxLength and not AH.ActiveVehicles[plate] then
            return plate
        end
    end
    return nil
end

function AH.RegisterVehicle(plate, data)
    AH.ActiveVehicles[plate] = data
end

function AH.UnregisterVehicle(plate)
    AH.ActiveVehicles[plate] = nil
end

function AH.GetVehicleRecord(plate)
    return AH.ActiveVehicles[plate]
end

-- ─── MM-vehiclekeys (§38, §68) ───────────────────────────────────
-- exports['MM-vehiclekeys']:Masitz_giveKey(src, plate) kan ikke kaldes
-- med `:`-syntaks når export-navnet er en runtime-variabel — vi
-- replikerer selv self-arg-videregivelsen som `:` ellers gør.
function AH.GiveKey(src, plate)
    if not Config.Agri.Keys.enabled then return true end
    local exp = exports[Config.Agri.Keys.resource]
    local ok, err = pcall(function()
        exp[Config.Agri.Keys.giveExport](exp, src, plate)
    end)
    if not ok then
        AH.Log('GiveKey fejlede for plate %s: %s', plate, tostring(err))
        return false
    end
    return true
end

function AH.RemoveKey(src, plate)
    if not Config.Agri.Keys.enabled then return true end
    local exp = exports[Config.Agri.Keys.resource]
    local ok, err = pcall(function()
        exp[Config.Agri.Keys.removeExport](exp, src, plate)
    end)
    if not ok then
        AH.Log('RemoveKey fejlede for plate %s: %s', plate, tostring(err))
        return false
    end
    return true
end

-- ─── CLEANUP VED DISCONNECT (§50, §78) ───────────────────────────
-- Vi kan ikke pålideligt fjerne en spawned entity fra en client der
-- netop er disconnected (ingen netværksforbindelse tilbage til dem).
-- Køretøjet bliver "ambient" og ryddes naturligt op af GTA's
-- population-system, når ingen længere er i nærheden. Her rydder vi
-- kun vores EGET bogføringsregister, så data ikke hænger i en korrupt
-- tilstand — tasks.lua/rental.lua har egne hooks der håndterer selve
-- task-/kontrakt-tilstanden (annullér ufærdig task, behold aktiv
-- kontrakt til spilleren evt. reconnecter).
AH.RegisterCleanupHook(function(src)
    for plate, record in pairs(AH.ActiveVehicles) do
        if record.src == src then
            AH.ActiveVehicles[plate] = nil
        end
    end
end)

AH.Log('server/vehicles.lua indlæst.')
