-- ============================================================
--  Masitz-AgriHub | server/access.lua
--  Login, session, adgangsstyring (grant/revoke), admin-kommandoer.
--
--  SIKKERHED (§120): NUI'en bestemmer ALDRIG selv om en spiller har
--  adgang. Hvert eneste kald herunder genvalidérer server-side.
--  SUPER_ADMIN afgøres KUN af en live Discord-ID-sammenligning
--  (AH.RequireAdmin), aldrig af en cachet client-værdi.
-- ============================================================

-- ─── LOGIN ───────────────────────────────────────────────────
lib.callback.register('masitz_agrihub:login', function(src)
    local xp = AH.GetXPlayer(src)
    if not xp then return { success = false, reason = 'Spillerdata ikke fundet.' } end

    local discordId = AH.GetDiscordId(src)
    local isSuperAdmin = discordId ~= nil and discordId == Config.Agri.Admin.discordId

    local role, hasAccess = 'USER', false

    if isSuperAdmin then
        role, hasAccess = 'SUPER_ADMIN', true
        -- Registreres for audit-formål — kræves IKKE for selve adgangen.
        local ok, err = pcall(function()
            MySQL.insert.await(
                [[INSERT INTO agrihub_users (identifier, discord_id, player_name, granted_by, status, granted_at, revoked_at)
                  VALUES (?, ?, ?, 'SYSTEM', 'active', NOW(), NULL)
                  ON DUPLICATE KEY UPDATE discord_id = VALUES(discord_id), player_name = VALUES(player_name), status = 'active']],
                { xp.identifier, discordId, xp.getName() }
            )
        end)
        if not ok then AH.Log('SUPER_ADMIN audit-upsert fejlede: %s', tostring(err)) end
    else
        local row = MySQL.single.await('SELECT status FROM agrihub_users WHERE identifier = ? LIMIT 1', { xp.identifier })
        hasAccess = row ~= nil and row.status == 'active'
    end

    if not hasAccess then
        AH.LogAction('login', 'LOGIN_DENIED', src, {})
        return { success = false, reason = 'Du har ikke adgang til AgriHub. Kontakt en administrator.' }
    end

    AH.Sessions[src] = {
        identifier = xp.identifier,
        discordId  = discordId,
        name       = xp.getName(),
        role       = role,
    }

    AH.LogAction('login', 'LOGIN_SUCCESS', src, { role = role })

    return { success = true, role = role, name = xp.getName() }
end)

RegisterNetEvent('masitz_agrihub:logout', function()
    local src = source
    if AH.Sessions[src] then
        AH.LogAction('login', 'LOGOUT', src, {})
    end
    AH.Sessions[src] = nil
end)

-- ─── ADMIN: SPILLERSØGNING (§111, §74) ─────────────────────────
lib.callback.register('masitz_agrihub:admin:searchPlayer', function(src, query)
    if not AH.RequireAdmin(src) then return {} end
    query = tostring(query or ''):lower()
    if query == '' then return {} end

    local results = {}
    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        local name = GetPlayerName(pid) or ''
        local discordId = AH.GetDiscordId(pid) or ''

        if tostring(pid) == query or name:lower():find(query, 1, true) or (discordId ~= '' and discordId:find(query, 1, true)) then
            local xp = AH.GetXPlayer(pid)
            results[#results + 1] = {
                serverId   = pid,
                name       = name,
                identifier = xp and xp.identifier or nil,
                discordId  = discordId ~= '' and discordId or nil,
            }
        end
        if #results >= 10 then break end
    end
    return results
end)

-- ─── ADMIN: GIV ADGANG (§98, §112) ──────────────────────────────
lib.callback.register('masitz_agrihub:admin:grantAccess', function(src, targetIdRaw)
    local admin = AH.RequireAdmin(src)
    if not admin then return { success = false, msg = 'Ikke autoriseret.' } end

    local targetId = tonumber(targetIdRaw)
    if not targetId then return { success = false, msg = 'Ugyldigt spiller-ID.' } end

    local targetXp = AH.GetXPlayer(targetId)
    if not targetXp then return { success = false, msg = 'Spilleren blev ikke fundet.' } end

    local discordId = AH.GetDiscordId(targetId)

    MySQL.insert.await(
        [[INSERT INTO agrihub_users (identifier, discord_id, player_name, granted_by, status, granted_at, revoked_at)
          VALUES (?, ?, ?, ?, 'active', NOW(), NULL)
          ON DUPLICATE KEY UPDATE status = 'active', granted_by = VALUES(granted_by), granted_at = NOW(),
                                   revoked_at = NULL, discord_id = VALUES(discord_id), player_name = VALUES(player_name)]],
        { targetXp.identifier, discordId, targetXp.getName(), admin.identifier }
    )

    AH.LogAction('access', 'ACCESS_GRANTED', src, {
        targetName = targetXp.getName(), targetIdentifier = targetXp.identifier, targetDiscord = discordId or 'n/a',
    })
    AH.Notify(targetId, 'Du har fået adgang til AgriHub.', 'success')

    return { success = true, name = targetXp.getName() }
end)

-- ─── ADMIN: FJERN ADGANG (§102, §112) ───────────────────────────
lib.callback.register('masitz_agrihub:admin:revokeAccess', function(src, identifierRaw)
    local admin = AH.RequireAdmin(src)
    if not admin then return { success = false, msg = 'Ikke autoriseret.' } end

    local targetIdentifier = tostring(identifierRaw or '')
    if targetIdentifier == '' then return { success = false, msg = 'Ugyldig bruger.' } end

    local changed = MySQL.update.await(
        'UPDATE agrihub_users SET status = "revoked", revoked_at = NOW() WHERE identifier = ? AND status = "active"',
        { targetIdentifier }
    )

    if not changed or changed < 1 then
        return { success = false, msg = 'Brugeren blev ikke fundet, eller har allerede ingen adgang.' }
    end

    for src2, session in pairs(AH.Sessions) do
        if session.identifier == targetIdentifier then
            AH.Sessions[src2] = nil
            TriggerClientEvent('masitz_agrihub:forceLogout', src2)
            AH.Notify(src2, 'Din AgriHub-adgang er blevet fjernet.', 'error')
        end
    end

    AH.LogAction('access', 'ACCESS_REVOKED', src, { targetIdentifier = targetIdentifier })
    return { success = true }
end)

-- ─── ADMIN: BRUGERLISTE / LOGS / STATUS ─────────────────────────
lib.callback.register('masitz_agrihub:admin:listUsers', function(src)
    if not AH.RequireAdmin(src) then return {} end
    return MySQL.query.await(
        'SELECT identifier, discord_id, player_name, granted_by, granted_at, revoked_at, status FROM agrihub_users ORDER BY created_at DESC LIMIT 200',
        {}
    ) or {}
end)

lib.callback.register('masitz_agrihub:admin:getLogs', function(src, filter)
    if not AH.RequireAdmin(src) then return {} end
    filter = tostring(filter or '')
    if filter ~= '' then
        return MySQL.query.await(
            'SELECT action, identifier, discord_id, player_name, data, created_at FROM agrihub_logs WHERE action LIKE ? ORDER BY created_at DESC LIMIT 100',
            { '%' .. filter .. '%' }
        ) or {}
    end
    return MySQL.query.await(
        'SELECT action, identifier, discord_id, player_name, data, created_at FROM agrihub_logs ORDER BY created_at DESC LIMIT 100',
        {}
    ) or {}
end)

lib.callback.register('masitz_agrihub:admin:systemStatus', function(src)
    if not AH.RequireAdmin(src) then return {} end
    return {
        activeUsers     = MySQL.scalar.await('SELECT COUNT(*) FROM agrihub_users WHERE status = "active"', {}) or 0,
        activeTasks     = MySQL.scalar.await('SELECT COUNT(*) FROM agrihub_tasks WHERE status = "active"', {}) or 0,
        activeContracts = MySQL.scalar.await('SELECT COUNT(*) FROM agrihub_contracts WHERE status = "active"', {}) or 0,
        onlinePlayers   = #GetPlayers(),
    }
end)

-- ─── ADMIN-KOMMANDOER (§98, alternativ til NUI) ────────────────
RegisterCommand('agriaccess', function(source, args)
    local src = source
    if src == 0 then print('[Masitz-AgriHub] Brug /agriaccess fra spillet, ikke serverkonsollen.') return end
    if not AH.RequireAdmin(src) then AH.Notify(src, 'Du har ikke adgang til denne kommando.', 'error') return end

    local targetId = tonumber(args[1])
    if not targetId then AH.Notify(src, 'Brug: /agriaccess [server id]', 'error') return end

    local targetXp = AH.GetXPlayer(targetId)
    if not targetXp then AH.Notify(src, 'Spilleren blev ikke fundet.', 'error') return end

    local discordId = AH.GetDiscordId(targetId)
    local adminSession = AH.Sessions[src]

    MySQL.insert.await(
        [[INSERT INTO agrihub_users (identifier, discord_id, player_name, granted_by, status, granted_at, revoked_at)
          VALUES (?, ?, ?, ?, 'active', NOW(), NULL)
          ON DUPLICATE KEY UPDATE status = 'active', granted_by = VALUES(granted_by), granted_at = NOW(), revoked_at = NULL]],
        { targetXp.identifier, discordId, targetXp.getName(), adminSession and adminSession.identifier or 'CONSOLE-CMD' }
    )

    AH.LogAction('access', 'ACCESS_GRANTED', src, { targetName = targetXp.getName(), targetIdentifier = targetXp.identifier, via = 'command' })
    AH.Notify(src, ('Adgang givet til %s.'):format(targetXp.getName()), 'success')
    AH.Notify(targetId, 'Du har fået adgang til AgriHub.', 'success')
end, false)

RegisterCommand('agrirevoke', function(source, args)
    local src = source
    if src == 0 then print('[Masitz-AgriHub] Brug /agrirevoke fra spillet, ikke serverkonsollen.') return end
    if not AH.RequireAdmin(src) then AH.Notify(src, 'Du har ikke adgang til denne kommando.', 'error') return end

    local targetId = tonumber(args[1])
    if not targetId then AH.Notify(src, 'Brug: /agrirevoke [server id]', 'error') return end

    local targetXp = AH.GetXPlayer(targetId)
    if not targetXp then AH.Notify(src, 'Spilleren blev ikke fundet.', 'error') return end

    local changed = MySQL.update.await(
        'UPDATE agrihub_users SET status = "revoked", revoked_at = NOW() WHERE identifier = ? AND status = "active"',
        { targetXp.identifier }
    )

    if changed and changed > 0 then
        if AH.Sessions[targetId] then
            AH.Sessions[targetId] = nil
            TriggerClientEvent('masitz_agrihub:forceLogout', targetId)
        end
        AH.LogAction('access', 'ACCESS_REVOKED', src, { targetIdentifier = targetXp.identifier, via = 'command' })
        AH.Notify(src, 'Adgang fjernet.', 'success')
    else
        AH.Notify(src, 'Brugeren har ikke adgang i forvejen.', 'error')
    end
end, false)

AH.Log('server/access.lua indlæst.')
