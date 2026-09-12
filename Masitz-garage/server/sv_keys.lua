-- ============================================================
--  Masitz-garage | server/sv_keys.lua
--  "Giv nøgler" til en ANDEN spiller (§6) — bruger MM-vehiclekeys,
--  UÆNDRET nøgle-eksport-navne. Fuldt server-autoritativ:
--  - target-spiller SKAL eksistere/være online
--  - initiativtager SKAL eje pladen
--  - intet af dette stoler på klienten ud over "her er et ID og en plade"
-- ============================================================

-- ─── TRIN 1: find/vis navn på modtager (før betjenten bekræfter) ──
lib.callback.register('masitz_garage:resolveTargetPlayer', function(src, targetIdRaw)
    local xp = MG.GetXPlayer(src)
    if not xp then return nil end

    local targetId = tonumber(targetIdRaw)
    if not targetId then return nil end
    targetId = math.floor(targetId)

    if targetId == src then return nil end

    local targetXp = MG.GetXPlayer(targetId)
    if not targetXp then return nil end

    return { id = targetId, name = targetXp.getName() }
end)

-- ─── TRIN 2: giv nøglen, efter betjenten har bekræftet navnet ─────
lib.callback.register('masitz_garage:giveKeyToPlayer', function(src, plate, targetIdRaw)
    local xp = MG.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Ikke logget ind.' } end

    plate = MG.NormPlate(plate)
    if not plate then return { success = false, msg = 'Ugyldig nummerplade.' } end

    local targetId = tonumber(targetIdRaw)
    if not targetId then return { success = false, msg = 'Ugyldigt spiller-ID.' } end
    targetId = math.floor(targetId)

    if targetId == src then
        return { success = false, msg = 'Du kan ikke give dig selv nøgler.' }
    end

    -- Re-validér target IGEN her — stol aldrig på resolve-kaldet ovenfor,
    -- spilleren kan være disconnected i mellemtiden.
    local targetXp = MG.GetXPlayer(targetId)
    if not targetXp then
        return { success = false, msg = 'Spilleren findes ikke længere.' }
    end

    -- Ejerskabstjek: kun den REELLE ejer i databasen kan give nøgler.
    local owned = MySQL.scalar.await(
        'SELECT 1 FROM owned_vehicles WHERE owner = ? AND REPLACE(plate," ","") = ? AND impound = 0',
        { xp.identifier, plate }
    )
    if not owned then
        return { success = false, msg = 'Du ejer ikke dette køretøj.' }
    end

    local ok, err = pcall(function()
        exports[Config.KeyExport]:Masitz_giveKey(targetId, plate)
    end)
    if not ok then
        MG.Log('giveKeyToPlayer: Masitz_giveKey fejl: ' .. tostring(err))
        return { success = false, msg = 'Nøgle-systemet fejlede. Prøv igen.' }
    end

    MySQL.query.await(
        'INSERT IGNORE INTO vehicle_keys (identifier, plate) VALUES (?, ?)',
        { targetXp.identifier, plate }
    )

    MG.LogKeyGiven({
        giverName = xp.getName(), giverIdentifier = xp.identifier,
        receiverName = targetXp.getName(), receiverIdentifier = targetXp.identifier,
        plate = plate,
    })
    MG.Log(('KEYS: %s gav nøgle til %s for %s'):format(xp.identifier, targetXp.identifier, plate))

    return { success = true, targetName = targetXp.getName() }
end)
