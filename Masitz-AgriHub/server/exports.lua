-- ============================================================
--  Masitz-AgriHub | server/exports.lua
--  Server-exports til brug for andre ressourcer (fx HUD/scoreboard/
--  admin-panels). Alt returneres server-autoritativt — ingen af disse
--  stoler på nogen client-tilstand.
-- ============================================================

AH = AH or {}

-- Returnerer spillerens ene aktive kontrakt for en given plade, hvis
-- den findes (bruges fx af MM-vehiclekeys eller andre garage-scripts
-- der vil vide om et køretøj er en AgriHub-leje).
local function GetActiveContract(identifier)
    return MySQL.single.await(
        'SELECT * FROM agrihub_contracts WHERE renter_identifier = ? AND status = "active" ORDER BY created_at DESC LIMIT 1',
        { identifier }
    )
end

exports('getActiveContract', function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return nil end
    return GetActiveContract(xp.identifier)
end)

exports('getPlayerTasks', function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return {} end
    return MySQL.query.await(
        'SELECT task_id, type, status, reward, claimed_at, expires_at FROM agrihub_tasks WHERE player_identifier = ? ORDER BY claimed_at DESC LIMIT 50',
        { xp.identifier }
    ) or {}
end)

exports('getPlayerRentals', function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return {} end
    return MySQL.query.await(
        'SELECT contract_id, vehicle_model, vehicle_plate, status, deposit, rent, start_at, expires_at FROM agrihub_contracts WHERE renter_identifier = ? ORDER BY created_at DESC LIMIT 50',
        { xp.identifier }
    ) or {}
end)

exports('getPlayerAgriStats', function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return nil end

    local completedTasks = MySQL.scalar.await(
        'SELECT COUNT(*) FROM agrihub_tasks WHERE player_identifier = ? AND status = "completed"',
        { xp.identifier }
    ) or 0
    local totalEarned = MySQL.scalar.await(
        'SELECT COALESCE(SUM(reward), 0) FROM agrihub_tasks WHERE player_identifier = ? AND status = "completed"',
        { xp.identifier }
    ) or 0
    local activeRentals = MySQL.scalar.await(
        'SELECT COUNT(*) FROM agrihub_contracts WHERE renter_identifier = ? AND status = "active"',
        { xp.identifier }
    ) or 0
    local hasAccess = AH.Sessions[src] ~= nil

    return {
        identifier      = xp.identifier,
        completedTasks  = completedTasks,
        totalEarned     = totalEarned,
        activeRentals   = activeRentals,
        loggedIntoHub   = hasAccess,
    }
end)

AH.Log('server/exports.lua indlæst.')
