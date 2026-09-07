--[[
    ALLE callbacks herunder validerer Permissions.IsStaff(source) FØRST,
    uanset hvad en manipuleret NUI måtte sende. Der er bevidst ingen
    "role"-parameter der sendes med fra klienten — rollen bestemmes altid
    på ny, server-side, ud fra source.
]]

local function ProfileFor(identifier)
    local data = Players[identifier]
    if not data then return nil end

    return {
        identifier = identifier,
        name = data.name,
        source = data.source,
        discord_id = data.discord_id,
        discord_name = data.discord_name,
        discord_avatar = data.discord_avatar,
        steam_id = data.steam_id,
        steam_name = data.steam_name,
        steam_avatar = data.steam_avatar,
        trust_factor = data.trust_factor,
        active_tasks = data.active_tasks,
        total_assigned = data.total_assigned,
        total_completed = data.total_completed,
    }
end

-- Bruges af "Online spillere"-listen i Staff/Owner-dashboardet. Viser
-- ALLE spillere der er online lige nu, uden at staff skal kende navn/ID
-- på forhånd. Bygger ALTID profilen live via GetOrCreatePlayerBySource,
-- så listen aldrig viser stale data for en spiller der lige er logget ind.
lib.callback.register('mm_sf:server:staffGetOnlinePlayers', function(source)
    if not Permissions.IsStaff(source) then return {} end

    local out = {}
    for _, playerId in ipairs(GetPlayers()) do
        local numericId = tonumber(playerId)
        local data = GetOrCreatePlayerBySource(numericId)
        if data then
            out[#out + 1] = ProfileFor(data.identifier)
        end
    end

    table.sort(out, function(a, b) return (a.source or 0) < (b.source or 0) end)
    return out
end)

lib.callback.register('mm_sf:server:staffSearch', function(source, query)
    if not Permissions.IsStaff(source) then return {} end
    if not query or #query < 2 then return {} end

    local result = FindPlayerByQuery(query)
    if not result then return {} end

    return { ProfileFor(result.identifier) }
end)

lib.callback.register('mm_sf:server:staffGetProfile', function(source, identifier)
    if not Permissions.IsStaff(source) then return nil end
    if not identifier then return nil end

    return ProfileFor(identifier)
end)

lib.callback.register('mm_sf:server:staffGetHistory', function(source, identifier)
    if not Permissions.IsStaff(source) then return {} end
    if not identifier or not DatabaseReady then return {} end

    return exports.oxmysql:querySync(
        'SELECT amount, reason, actor_name, created_at FROM sf_history WHERE identifier = ? ORDER BY created_at DESC LIMIT 100',
        { identifier }
    ) or {}
end)

local function ActorInfo(source)
    return GetIdentifier(source), GetPlayerName(source)
end

lib.callback.register('mm_sf:server:staffGiveService', function(source, payload)
    if not Permissions.IsStaff(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local target = payload.identifier and Players[payload.identifier] or FindPlayerByQuery(payload.query)
    if not target then return false, 'Spilleren blev ikke fundet.' end

    local _, actorName = ActorInfo(source)
    local ok, err = Tasks.GiveService(target.identifier, payload.amount, payload.reason, source, actorName)
    return ok, err, ok and ProfileFor(target.identifier) or nil
end)

lib.callback.register('mm_sf:server:staffRemoveTasks', function(source, payload)
    if not Permissions.IsStaff(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local target = payload.identifier and Players[payload.identifier]
    if not target then return false, 'Spilleren blev ikke fundet.' end

    local _, actorName = ActorInfo(source)
    local ok, err = Tasks.RemoveTasks(target.identifier, payload.amount, source, actorName)
    return ok, err, ok and ProfileFor(target.identifier) or nil
end)

lib.callback.register('mm_sf:server:staffSetTasks', function(source, payload)
    if not Permissions.IsStaff(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local target = payload.identifier and Players[payload.identifier]
    if not target then return false, 'Spilleren blev ikke fundet.' end

    local _, actorName = ActorInfo(source)
    local ok, err = Tasks.SetTasks(target.identifier, payload.amount, source, actorName)
    return ok, err, ok and ProfileFor(target.identifier) or nil
end)

lib.callback.register('mm_sf:server:staffRelease', function(source, payload)
    if not Permissions.IsStaff(source) then return false, 'Ingen adgang.' end
    payload = payload or {}

    local target = payload.identifier and Players[payload.identifier]
    if not target then return false, 'Spilleren blev ikke fundet.' end

    local _, actorName = ActorInfo(source)
    local ok = Tasks.Release(target.identifier, source, actorName)
    return ok, nil, ok and ProfileFor(target.identifier) or nil
end)
