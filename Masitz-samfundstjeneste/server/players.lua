--[[
    Players-modulet er det centrale lag mellem databasen og resten af
    systemet (task-engine, trust factor, NUI). Alt andet server-kode skal
    læse/skrive spillerdata GENNEM dette modul — aldrig direkte via
    exports.oxmysql selv. Det holder databaselogikken ét sted og gør det
    muligt at cache i hukommelsen uden at hver eneste modul skal vide,
    hvordan cachen er struktureret.
]]

-- Players[identifier] = {
--     identifier, name, discord_id, discord_name, discord_avatar,
--     steam_id, steam_name, steam_avatar,
--     active_tasks, total_assigned, total_completed, total_removed_manual,
--     trust_factor, active_minutes_since_recovery, escape_pause_until,
--     source = <nuværende server-ID, eller nil hvis offline>
-- }
Players = {}

-- ------------------------------------------------------------
-- IDENTIFIER
-- Permanent identifier (license), IKKE server-ID. Bevaret fra V1 —
-- forhindrer at en ny spiller ved et tilfælde arver en andens straf,
-- hvis de får tildelt samme genbrugte server-ID.
-- ------------------------------------------------------------
function GetIdentifier(source)
    if not source or source == 0 or source == '' then
        return nil
    end

    return GetPlayerIdentifierByType(source, 'license')
        or GetPlayerIdentifierByType(source, 'license2')
        or GetPlayerIdentifierByType(source, 'fivem')
        or GetPlayerIdentifierByType(source, 'discord')
end

-- ------------------------------------------------------------
-- CACHE <-> DATABASE MAPPING
-- ------------------------------------------------------------
local function RowToCache(row, source)
    return {
        identifier = row.identifier,
        name = row.name,

        discord_id = row.discord_id,
        discord_name = row.discord_name,
        discord_avatar = row.discord_avatar,

        steam_id = row.steam_id,
        steam_name = row.steam_name,
        steam_avatar = row.steam_avatar,

        active_tasks = row.active_tasks,
        total_assigned = row.total_assigned,
        total_completed = row.total_completed,
        total_removed_manual = row.total_removed_manual or 0,

        trust_factor = tonumber(row.trust_factor),
        active_minutes_since_recovery = row.active_minutes_since_recovery,
        escape_pause_until = row.escape_pause_until,
        steam_avatar_updated_at = row.steam_avatar_updated_at,

        -- ------------------------------------------------------------
        -- IN-MEMORY-ONLY RUNTIME STATE
        -- Gemmes ALDRIG i databasen — nulstilles hver gang spilleren
        -- logger ind. Bruges af service/task/anti-escape-modulerne.
        -- ------------------------------------------------------------
        inService = false,          -- false, eller siteKey (fx 'boat')
        session = nil,              -- { sessionId, taskKey, startedAt, minDuration }
        lastActivityAt = 0,         -- os.time() for sidst registrerede aktivitet (AFK-tjek)

        source = source,
    }
end

-- ------------------------------------------------------------
-- HENT / OPRET
-- Bruges når systemet skal have fat i en spillers data — enten fordi de
-- lige er logget ind, eller fordi staff/owner slår dem op mens de er
-- offline (fx via søgning).
-- ------------------------------------------------------------
function GetOrCreatePlayerByIdentifier(identifier, name, source)
    if not identifier then return nil end

    if Players[identifier] then
        if source then
            Players[identifier].source = source
        end
        return Players[identifier]
    end

    if not DatabaseReady then
        print('^1[Masitz-samfundstjeneste]^7 Databasen er ikke klar endnu, kan ikke hente spiller: ' .. identifier)
        return nil
    end

    local row = exports.oxmysql:singleSync('SELECT * FROM sf_players WHERE identifier = ?', { identifier })

    if not row then
        exports.oxmysql:insertSync(
            'INSERT INTO sf_players (identifier, name) VALUES (?, ?)',
            { identifier, name or 'Ukendt' }
        )
        row = exports.oxmysql:singleSync('SELECT * FROM sf_players WHERE identifier = ?', { identifier })
    elseif name and row.name ~= name then
        -- Navnet kan have ændret sig siden sidst (fx nyt characternavn) — hold det opdateret.
        exports.oxmysql:update('UPDATE sf_players SET name = ? WHERE identifier = ?', { name, identifier })
        row.name = name
    end

    Players[identifier] = RowToCache(row, source)
    return Players[identifier]
end

-- Bruges når man kun har et server-ID (fx fra en /kommando med et target-ID).
function GetOrCreatePlayerBySource(source)
    local identifier = GetIdentifier(source)
    if not identifier then return nil end

    return GetOrCreatePlayerByIdentifier(identifier, GetPlayerName(source), source)
end

-- ------------------------------------------------------------
-- GEM
-- Skriver den cachede version tilbage til databasen. Kaldes eksplicit af
-- moduler der ændrer et felt (task-engine, trust factor osv.) — IKKE via
-- et periodisk loop, for at undgå unødvendige queries når intet har ændret sig.
-- ------------------------------------------------------------
function SavePlayer(identifier)
    local data = Players[identifier]
    if not data or not DatabaseReady then return end

    exports.oxmysql:update([[
        UPDATE sf_players SET
            name = ?,
            discord_id = ?, discord_name = ?, discord_avatar = ?,
            steam_id = ?, steam_name = ?, steam_avatar = ?,
            active_tasks = ?, total_assigned = ?, total_completed = ?, total_removed_manual = ?,
            trust_factor = ?, active_minutes_since_recovery = ?, escape_pause_until = ?,
            steam_avatar_updated_at = ?
        WHERE identifier = ?
    ]], {
        data.name,
        data.discord_id, data.discord_name, data.discord_avatar,
        data.steam_id, data.steam_name, data.steam_avatar,
        data.active_tasks, data.total_assigned, data.total_completed, data.total_removed_manual or 0,
        data.trust_factor, data.active_minutes_since_recovery, data.escape_pause_until,
        data.steam_avatar_updated_at,
        identifier,
    })
end

-- ------------------------------------------------------------
-- PUSH TIL KLIENT
-- Sender den friske spiller-cache til NUI'en, hvis dashboardet er åbent.
-- Bruges efter ALT der ændrer spillerens tal (tasks, trust factor osv.),
-- så dashboardet altid viser live data uden reconnect.
-- ------------------------------------------------------------
function PushPlayerUpdate(identifier)
    local data = Players[identifier]
    if not data or not data.source then return end

    TriggerClientEvent('mm_sf:client:playerUpdate', data.source, {
        active_tasks = data.active_tasks,
        total_assigned = data.total_assigned,
        total_completed = data.total_completed,
        total_removed_manual = data.total_removed_manual or 0,
        trust_factor = data.trust_factor,
        inService = data.inService,
    })
end

-- ------------------------------------------------------------
-- OPSLAG PÅ TVÆRS AF ONLINE + OFFLINE (bruges af staff-søgning)
-- ------------------------------------------------------------
function FindPlayerByQuery(query)
    if not query or query == '' then return nil end
    query = tostring(query)

    -- 1) Er det et online server-ID?
    local asNumber = tonumber(query)
    if asNumber and GetPlayerName(asNumber) then
        return GetOrCreatePlayerBySource(asNumber)
    end

    -- 2) Online spillere: match navn (case-insensitive, delvist).
    local lowered = query:lower()
    for _, playerId in ipairs(GetPlayers()) do
        local name = GetPlayerName(playerId)
        if name and name:lower():find(lowered, 1, true) then
            return GetOrCreatePlayerBySource(tonumber(playerId))
        end
    end

    -- 3) Database: navn, discord_id/name, steam_id/name.
    if not DatabaseReady then return nil end

    local row = exports.oxmysql:singleSync([[
        SELECT * FROM sf_players
        WHERE name LIKE ? OR discord_id = ? OR discord_name LIKE ?
           OR steam_id = ? OR steam_name LIKE ?
        LIMIT 1
    ]], { '%' .. query .. '%', query, '%' .. query .. '%', query, '%' .. query .. '%' })

    if not row then return nil end

    if Players[row.identifier] then
        return Players[row.identifier]
    end

    return GetOrCreatePlayerByIdentifier(row.identifier, row.name, nil)
end

-- ------------------------------------------------------------
-- LIVSCYKLUS-HOOKS
-- ------------------------------------------------------------

-- esx:playerLoaded fyrer først når ESX's spillerobjekt er fuldt initialiseret
-- (identifiers, job, penge osv. er klar) — mere robust end V1's rå
-- playerSpawned, som kan fyre før alt er loadet ordentligt.
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = GetIdentifier(playerId)
    if not identifier then return end

    GetOrCreatePlayerByIdentifier(identifier, GetPlayerName(playerId), playerId)

    -- Havde spilleren allerede aktive opgaver fra en tidligere session
    -- (fx de disconnectede midt i tjenesten), sendes de automatisk ud
    -- igen nu — de skal aldrig selv skulle bede om det. Lille delay så
    -- pedet er nået at spawne helt ind client-side, før vi teleporterer.
    SetTimeout(3000, function()
        if Tasks and Tasks.TryAutoStart then
            Tasks.TryAutoStart(identifier)
        end
    end)
end)

AddEventHandler('playerDropped', function()
    local src = source
    local identifier = GetIdentifier(src)
    if not identifier or not Players[identifier] then return end

    -- Gem den sidste kendte tilstand, og fjern derefter fra cachen. Vi
    -- beholder IKKE offline-spillere i hukommelsen ubegrænset — de bliver
    -- hentet fra databasen igen næste gang de er relevante (login, eller
    -- staff der søger efter dem).
    SavePlayer(identifier)
    Players[identifier].source = nil
    Players[identifier] = nil
end)
