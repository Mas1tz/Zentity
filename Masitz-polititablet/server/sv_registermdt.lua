-- ============================================================
--  kc_mdt | server/sv_registermdt.lua  (v2.0.2)
--  Auto-derive rank/grade fra ESX job_grade tabel
-- ============================================================

local registerCooldown = {}

lib.callback.register('kcmdt:getNearbyPlayers', function(src)
    if not KCS.requirePermission(src, 'createAccount') then return {} end

    local xpBoss = KCS.getXP(src); if not xpBoss then return {} end
    local bossPed = GetPlayerPed(src)
    if bossPed == 0 then return {} end
    local bossCoords = GetEntityCoords(bossPed)

    local players = ESX.GetExtendedPlayers()
    local radius  = Config.RegisterMDT.nearestRadius
    local result  = {}

    for _, xp in ipairs(players) do
        local pid = xp.source
        if pid ~= src then
            local ped = GetPlayerPed(pid)
            if ped and ped ~= 0 then
                local pc = GetEntityCoords(ped)
                local d  = #(bossCoords - pc)
                if d <= radius then
                    local hasAccount = MySQL.scalar.await(
                        'SELECT id FROM polititablet_accounts WHERE identifier=?', { xp.identifier }
                    ) ~= nil
                    result[#result+1] = {
                        serverId   = pid,
                        name       = xp.getName(),
                        identifier = xp.identifier,
                        job        = xp.job and xp.job.label or '',
                        jobName    = xp.job and xp.job.name or '',
                        jobGrade   = xp.job and xp.job.grade or 0,
                        jobGradeLabel = xp.job and (xp.job.grade_label or '') or '',
                        isPolice   = (xp.job and Config.AllowedJobs[xp.job.name]) and true or false,
                        distance   = math.floor(d * 10) / 10,
                        hasAccount = hasAccount,
                    }
                end
            end
        end
    end

    table.sort(result, function(a, b) return a.distance < b.distance end)
    if #result > Config.RegisterMDT.nearestMaxShown then
        for i = #result, Config.RegisterMDT.nearestMaxShown + 1, -1 do
            result[i] = nil
        end
    end
    return result
end)

lib.callback.register('kcmdt:getPlayerByServerId', function(src, targetId)
    if not KCS.requirePermission(src, 'createAccount') then return nil end
    targetId = tonumber(targetId)
    if not targetId or targetId <= 0 then return nil end

    local xp = KCS.getXP(targetId)
    if not xp then return { found=false, error='Spiller med ID '..targetId..' er ikke online.' } end

    local hasAccount = MySQL.scalar.await(
        'SELECT id FROM polititablet_accounts WHERE identifier=?', { xp.identifier }
    ) ~= nil

    return {
        found      = true,
        serverId   = targetId,
        name       = xp.getName(),
        identifier = xp.identifier,
        job        = xp.job and xp.job.label or '',
        jobName    = xp.job and xp.job.name or '',
        jobGrade   = xp.job and xp.job.grade or 0,
        jobGradeLabel = xp.job and (xp.job.grade_label or '') or '',
        isPolice   = (xp.job and Config.AllowedJobs[xp.job.name]) and true or false,
        hasAccount = hasAccount,
    }
end)

-- ═══════════════════════════════════════════════════════════
--  CREATE MDT ACCOUNT — Auto-derive rank/grade from job
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:registerMDT', function(src, payload)
    if not KCS.requirePermission(src, 'createAccount') then
        return { ok=false, error='Manglende permission.' }
    end
    local xpBoss = KCS.getXP(src)
    if not xpBoss then return { ok=false, error='ESX-fejl.' } end

    local nowSec = os.time()
    local last = registerCooldown[xpBoss.identifier] or 0
    if (nowSec - last) < Config.RegisterMDT.cooldownSec then
        return { ok=false, error=('Cooldown — vent %d sek.'):format(Config.RegisterMDT.cooldownSec - (nowSec - last)) }
    end

    if type(payload) ~= 'table' then return { ok=false, error='Ugyldig data.' } end
    local targetId = tonumber(payload.targetId)
    local username = KC.normUsername(payload.username)
    local password = tostring(payload.password or Config.RegisterMDT.defaultPassword)
    local badge    = KC.safeStr(payload.badge or '', 20)

    if not targetId then return { ok=false, error='Ugyldigt server ID.' } end
    if not KC.isValidUsername(username) then
        return { ok=false, error='Brugernavn skal være '..Config.Security.minUsernameLen..'-'..Config.Security.maxUsernameLen..' tegn, og kun a-z 0-9 . _ -.' }
    end
    if not KC.isValidPassword(password) then
        return { ok=false, error='Adgangskode skal være '..Config.Security.minPasswordLen..'-'..Config.Security.maxPasswordLen..' tegn.' }
    end

    local targetXP = KCS.getXP(targetId)
    if not targetXP then return { ok=false, error='Spiller med ID '..targetId..' er ikke online.' } end

    -- ═══ AUTO-DERIVE RANK + GRADE FRA POLICE JOB ═══
    if not (targetXP.job and Config.AllowedJobs[targetXP.job.name]) then
        return { ok=false, error='Spilleren skal være politi først. Sæt deres job, kør så /registermdt igen.' }
    end
    local rank  = targetXP.job.grade_label or targetXP.job.label or 'Officer'
    local grade = tonumber(targetXP.job.grade) or 0

    local exists = MySQL.scalar.await('SELECT id FROM polititablet_accounts WHERE username=?', { username })
    if exists then
        return { ok=false, error='Brugernavnet "'..username..'" er allerede taget.' }
    end

    local hasOne = MySQL.scalar.await('SELECT id FROM polititablet_accounts WHERE identifier=?', { targetXP.identifier })
    if hasOne then
        return { ok=false, error='Denne spiller har allerede en MDT-konto.' }
    end

    local salt = KCS.genSalt(16)
    local hash = KCS.hashPassword(password, salt)
    if not hash then return { ok=false, error='Hashing fejlede.' } end

    local insertId
    local ok, err = pcall(function()
        insertId = MySQL.insert.await([[
            INSERT INTO polititablet_accounts
                (identifier, username, password_hash, password_salt, must_change_pw,
                 status, badge_number, rank, grade, created_by, created_by_name)
            VALUES (?,?,?,?,?,?,?,?,?,?,?)
        ]], {
            targetXP.identifier, username, hash, salt,
            (Config.RegisterMDT.forcePwChange and 1 or 0),
            'active', badge, rank, grade,
            xpBoss.identifier, xpBoss.getName()
        })
    end)

    if not ok or not insertId then
        KC.err('registermdt', 'INSERT fejlede: '..tostring(err))
        local dup = MySQL.scalar.await('SELECT id FROM polititablet_accounts WHERE username=?', { username })
        if dup then return { ok=false, error='Brugernavn netop blevet taget.' } end
        return { ok=false, error='Database-fejl ved oprettelse.' }
    end

    registerCooldown[xpBoss.identifier] = nowSec

    KCS.audit(xpBoss.identifier, xpBoss.getName(), 'CREATE_ACCOUNT',
        targetXP.identifier, ('username=%s rank=%s grade=%d badge=%s'):format(username, rank, grade, badge))
    KCS.consoleLog('REGISTERMDT', ('%s created account "%s" for %s (%d) — %s (grade %d)'):format(
        xpBoss.getName(), username, targetXP.getName(), targetId, rank, grade))

    TriggerClientEvent('kcmdt:notify', targetId,
        ('MDT-konto oprettet til dig. Brugernavn: %s | Adgangskode: %s | Skift den ved første login.'):format(username, password),
        'success', 12000)
    TriggerClientEvent('kcmdt:accountCreated', targetId, { username = username })

    KCS.broadcastMDT('kcmdt:newAccountCreated', {
        username = username, rank = rank, grade = grade, badge = badge,
        targetName = targetXP.getName(), createdBy = xpBoss.getName(),
        createdAt  = os.date('%Y-%m-%d %H:%M:%S'),
    })

    return {
        ok=true, username=username, password=password,
        rank=rank, grade=grade, badge=badge,
        targetName=targetXP.getName(), accountId=insertId,
    }
end)

AddEventHandler('playerDropped', function()
    local src = source
    local xp  = KCS.getXP(src)
    if xp and registerCooldown[xp.identifier] then
        registerCooldown[xp.identifier] = nil
    end
end)
