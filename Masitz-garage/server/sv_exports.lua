-- ============================================================
--  Masitz-garage | server/sv_exports.lua
--  Eksterne, server-til-server exports. Alt her er beregnet til
--  at blive kaldt fra ANDRE resources (fx en fremtidig Discord-bot
--  bridge, eller en bilforhandler-resource) — ikke fra klienten.
-- ============================================================

-- ─── IMPOUND (uændret export-navn — kun ressourcens EGET navn
--     ændres ved omdøbningen MM-garage -> Masitz-garage, så en
--     ekstern kalder skal opdatere til exports['Masitz-garage']) ──
exports('impoundVehicle', function(plate, reason, location)
    return MG.ImpoundVehicle(plate, reason, location)
end)

-- ─── DISCORD BOT-GRUNDLAG (§13) ────────────────────────────────
-- Eksempel: exports['Masitz-garage']:getPlayerVehicles(identifier)
-- Returnerer alle af spillerens køretøjer (uanset garage/impound-status).
exports('getPlayerVehicles', function(identifier)
    if type(identifier) ~= 'string' or identifier == '' then return {} end

    local rows = MySQL.query.await(
        [[SELECT plate, vehicle, vehicle_name, parking, garage_type, stored, impound,
                 impound_location, impound_reason, impound_fee
          FROM   owned_vehicles
          WHERE  owner = ?]],
        { identifier }
    ) or {}

    local out = {}
    for _, row in ipairs(rows) do
        local ok, data = pcall(json.decode, row.vehicle or '{}')
        if not ok or type(data) ~= 'table' then data = {} end

        out[#out + 1] = {
            plate         = row.plate,
            model         = data.model or 'unknown',
            vehicleName   = row.vehicle_name,
            garage        = row.parking,
            garageType    = row.garage_type,
            stored        = row.stored == 1,
            impound       = row.impound == 1,
            impoundLoc    = row.impound_location,
            impoundReason = row.impound_reason,
            impoundFee    = row.impound_fee,
        }
    end
    return out
end)

-- ─── BILKØB — logging-hook til en bilforhandler-resource (§12) ──
-- Eksempel: exports['Masitz-garage']:logVehiclePurchase(identifier, model, plate, price, 'bank')
exports('logVehiclePurchase', function(identifier, model, plate, price, paymentMethod)
    if type(identifier) ~= 'string' or identifier == '' then return false end
    MG.LogPurchase({
        identifier    = identifier,
        model         = model,
        plate         = MG.NormPlate(plate),
        price         = price,
        paymentMethod = paymentMethod,
    })
    return true
end)

-- ─── NUMMERPLADE-ÆNDRING — logging-hook (§21) ──────────────────
-- Denne resource har ikke selv en plade-skift-funktion, men eksponerer
-- et API så et script der HAR den funktion kan logge konsistent herigennem.
-- Eksempel: exports['Masitz-garage']:logPlateChange(identifier, 'ABC123', 'XYZ789')
exports('logPlateChange', function(identifier, oldPlate, newPlate)
    if type(identifier) ~= 'string' or identifier == '' then return false end
    MG.LogPlateChange({
        identifier = identifier,
        oldPlate   = MG.NormPlate(oldPlate),
        newPlate   = MG.NormPlate(newPlate),
    })
    return true
end)
