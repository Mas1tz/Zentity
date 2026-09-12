-- ============================================================
--  kc_mdt | server/sv_auth.lua
--  Login, password hashing, sessions, account management
--  Sikker: server-side hashing kun, salt+pepper, rate limit,
--          brute-force lockout, status, must-change-pw flag.
-- ============================================================

-- ─── HASHING ─────────────────────────────────────────────────
local function genSalt(len)
    len = len or 16
    local chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    local n = #chars
    local t = {}
    for i = 1, len do
        local idx = math.random(n)        -- vælg ÉT tegn (én random pr. iteration)
        t[i] = chars:sub(idx, idx)
    end
    return table.concat(t)
end

local function hashPassword(plain, salt)
    if type(plain) ~= 'string' or type(salt) ~= 'string' then return nil end
    return KC_SHA256(Config.PasswordPepper .. ':' .. salt .. ':' .. plain)
end

-- Expose to other server files
KCS.hashPassword = hashPassword
KCS.genSalt      = genSalt

-- ─── SESSION LIFECYCLE ───────────────────────────────────────
local function startSession(src, account, xp)
    local sess = {
        source     = src,
        identifier = xp.identifier,
        name       = (account.rank and (account.rank .. ' ') or '') .. xp.getName(),
        rawName    = xp.getName(),
        rank       = account.rank or 'Officer',
        grade      = tonumber(xp.job.grade) or 0,  -- ESX grade (live)
        mdtGrade   = tonumber(account.grade) or 0, -- account.grade (audit)
        badgeNum   = account.badge_number,
        unit       = nil,
        status     = 1,
        dutyStart  = os.time(),
        lastActive = os.time(),
        accountId  = account.id,
    }
    KCS.online[xp.identifier] = sess
    KCS.bySrc[src]            = xp.identifier

    -- Start duty log
    MySQL.insert(
        'INSERT INTO polititablet_duty_log (identifier, duty_on) VALUES (?, NOW())',
        { xp.identifier }
    )

    KCS.consoleLog('LOGIN', ('%s (%s) logged in'):format(xp.getName(), xp.identifier))
    return sess
end

function KCS.endSession(identifier, reason)
    local sess = KCS.online[identifier]
    if not sess then return end

    -- Close any open duty rows
    MySQL.update(
        "UPDATE polititablet_duty_log SET duty_off=NOW(), seconds=TIMESTAMPDIFF(SECOND,duty_on,NOW()) WHERE identifier=? AND duty_off IS NULL",
        { identifier }
    )
    -- Remove from patrol units
    MySQL.update('DELETE FROM polititablet_patrol_units WHERE officer_id=?', { identifier })

    if sess.source then
        KCS.bySrc[sess.source] = nil
    end
    KCS.online[identifier] = nil
    KCS.gpsCache[identifier] = nil

    KCS.consoleLog('LOGOUT', ('%s (%s) reason=%s'):format(sess.rawName or '?', identifier, reason or 'unknown'))
    KCS.broadcastPatrolList()
end

-- ═══════════════════════════════════════════════════════════
--  CALLBACK: LOGIN
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:login', function(src, username, password)
    local xp = KCS.getXP(src)
    if not xp then return { ok=false, error='ESX-fejl.' } end

    -- Job-check
    if not Config.AllowedJobs[xp.job and xp.job.name] then
        return { ok=false, error='Dit job har ikke adgang til MDT.' }
    end

    -- Input validation
    username = KC.normUsername(username)
    if not KC.isValidUsername(username) or not KC.isValidPassword(password) then
        return { ok=false, error='Ugyldigt brugernavn eller adgangskode.' }
    end

    -- Anti-spam per source
    if not KCS.spamCheck(src) then
        return { ok=false, error='For mange forsøg — vent et øjeblik.' }
    end

    -- Find account
    local row = MySQL.single.await(
        'SELECT * FROM polititablet_accounts WHERE username=? LIMIT 1',
        { username }
    )

    -- Generic error msg for unknown user (don't leak account existence)
    if not row then
        KCS.audit(xp.identifier, xp.getName(), 'LOGIN_FAIL', username, 'no such user')
        return { ok=false, error='Forkert brugernavn eller adgangskode.' }
    end

    -- Check account is linked to this player (security: account belongs to whoever it was made for)
    if row.identifier ~= xp.identifier then
        KCS.audit(xp.identifier, xp.getName(), 'LOGIN_FAIL', username, 'identifier mismatch')
        return { ok=false, error='Denne konto tilhører ikke dig.' }
    end

    -- Status check
    if row.status == 'banned' then
        return { ok=false, error='Denne konto er bannet.' }
    elseif row.status == 'suspended' then
        return { ok=false, error='Denne konto er suspenderet — kontakt en boss.' }
    end

    -- Lockout check
    if row.locked_until then
        local lockTs = MySQL.scalar.await(
            'SELECT TIMESTAMPDIFF(SECOND, NOW(), locked_until) FROM polititablet_accounts WHERE id=?',
            { row.id }
        )
        if lockTs and tonumber(lockTs) > 0 then
            return { ok=false, error=('Konto låst — prøv igen om %d minutter.'):format(math.ceil(tonumber(lockTs)/60)) }
        else
            -- Lock expired, clear it
            MySQL.update('UPDATE polititablet_accounts SET locked_until=NULL, failed_attempts=0 WHERE id=?', { row.id })
            row.failed_attempts = 0
        end
    end

    -- Verify password
    local expectedHash = hashPassword(password, row.password_salt or '')
    if row.password_hash ~= expectedHash then
        local attempts = (row.failed_attempts or 0) + 1
        local maxAtt   = Config.Security.loginMaxAttempts
        if attempts >= maxAtt then
            MySQL.update(
                'UPDATE polititablet_accounts SET failed_attempts=?, locked_until=DATE_ADD(NOW(), INTERVAL ? MINUTE) WHERE id=?',
                { attempts, Config.Security.loginLockoutMin, row.id }
            )
            KCS.audit(xp.identifier, xp.getName(), 'LOGIN_LOCKED', username, 'too many failed attempts')
            return { ok=false, error=('Konto låst i %d minutter pga. for mange fejlede forsøg.'):format(Config.Security.loginLockoutMin) }
        else
            MySQL.update('UPDATE polititablet_accounts SET failed_attempts=? WHERE id=?', { attempts, row.id })
            return { ok=false, error=('Forkert brugernavn eller adgangskode. (%d/%d)'):format(attempts, maxAtt) }
        end
    end

    -- SUCCESS — reset attempts, set last_login
    MySQL.update(
        'UPDATE polititablet_accounts SET failed_attempts=0, locked_until=NULL, last_login=NOW(), last_login_ip=? WHERE id=?',
        { GetPlayerEndpoint(src) or '', row.id }
    )

    -- ═══ AUTO-SYNC RANK/GRADE FRA ESX JOB ═══
    -- Hvis spilleren er blevet forfremmet/degraderet siden sidste login,
    -- så opdater MDT-kontoens rang og grade til den nuværende job_grade.
    if xp.job and Config.AllowedJobs[xp.job.name] then
        local currentRank  = xp.job.grade_label or xp.job.label or row.rank or 'Officer'
        local currentGrade = tonumber(xp.job.grade) or row.grade or 0
        if currentRank ~= row.rank or currentGrade ~= (row.grade or 0) then
            MySQL.update('UPDATE polititablet_accounts SET rank=?, grade=? WHERE id=?',
                { currentRank, currentGrade, row.id })
            KCS.audit(xp.identifier, xp.getName(), 'RANK_SYNC', username,
                ('%s grade %d → %s grade %d'):format(row.rank or '?', row.grade or 0, currentRank, currentGrade))
            row.rank  = currentRank
            row.grade = currentGrade
        end
    end

    local sess = startSession(src, row, xp)
    KCS.broadcastPatrolList()
    KCS.audit(xp.identifier, xp.getName(), 'LOGIN_OK', username, nil)

    return {
        ok           = true,
        identifier   = xp.identifier,
        name         = xp.getName(),
        rank         = row.rank,
        grade        = row.grade,
        liveGrade    = xp.job.grade,
        badge        = row.badge_number,
        profileImage = row.profile_image,
        mustChangePw = row.must_change_pw == 1,
        accountId    = row.id,
    }
end)

-- ═══════════════════════════════════════════════════════════
--  EVENT: LOGOUT
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('kcmdt:logout', function()
    local src = source
    local xp  = KCS.getXP(src); if not xp then return end
    if KCS.online[xp.identifier] then
        KCS.endSession(xp.identifier, 'manual')
        KCS.audit(xp.identifier, xp.getName(), 'LOGOUT', nil, nil)
    end
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACK: CHANGE PASSWORD
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:changePassword', function(src, oldPw, newPw)
    local sess = KCS.requireSession(src); if not sess then return { ok=false, error='Ikke logget ind.' } end
    if not KC.isValidPassword(newPw) then
        return { ok=false, error='Adgangskoden skal være mellem '..Config.Security.minPasswordLen..'-'..Config.Security.maxPasswordLen..' tegn.' }
    end
    if oldPw == newPw then
        return { ok=false, error='Den nye adgangskode skal være forskellig fra den gamle.' }
    end

    local row = MySQL.single.await('SELECT password_hash, password_salt FROM polititablet_accounts WHERE identifier=?', { sess.identifier })
    if not row then return { ok=false, error='Konto ikke fundet.' } end

    if row.password_hash ~= hashPassword(oldPw, row.password_salt) then
        return { ok=false, error='Forkert nuværende adgangskode.' }
    end

    local newSalt = genSalt(16)
    local newHash = hashPassword(newPw, newSalt)
    MySQL.update.await(
        'UPDATE polititablet_accounts SET password_hash=?, password_salt=?, must_change_pw=0 WHERE identifier=?',
        { newHash, newSalt, sess.identifier }
    )
    KCS.audit(sess.identifier, sess.rawName, 'PASSWORD_CHANGE', nil, nil)
    return { ok=true }
end)

-- ═══════════════════════════════════════════════════════════
--  RESET PASSWORD (boss kan resette en andens password)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:resetPassword', function(src, targetUsername, newPw)
    if not KCS.requirePermission(src, 'resetPassword') then return { ok=false } end
    local xp = KCS.getXP(src); if not xp then return { ok=false } end

    targetUsername = KC.normUsername(targetUsername)
    newPw = newPw or Config.RegisterMDT.defaultPassword
    if not KC.isValidUsername(targetUsername) or not KC.isValidPassword(newPw) then
        return { ok=false, error='Ugyldigt input.' }
    end

    local row = MySQL.single.await('SELECT id, identifier FROM polititablet_accounts WHERE username=?', { targetUsername })
    if not row then return { ok=false, error='Konto ikke fundet.' } end

    local salt = genSalt(16)
    local hash = hashPassword(newPw, salt)
    MySQL.update.await(
        'UPDATE polititablet_accounts SET password_hash=?, password_salt=?, must_change_pw=1, failed_attempts=0, locked_until=NULL WHERE id=?',
        { hash, salt, row.id }
    )
    KCS.audit(xp.identifier, xp.getName(), 'PASSWORD_RESET', targetUsername, nil)
    return { ok=true }
end)

-- ═══════════════════════════════════════════════════════════
--  SET ACCOUNT STATUS (active / suspended / banned)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:setAccountStatus', function(src, targetUsername, newStatus)
    if not KCS.requirePermission(src, 'deactivateAccount') then return { ok=false } end
    local xp = KCS.getXP(src); if not xp then return { ok=false } end

    local allowed = { active=true, suspended=true, banned=true }
    if not allowed[newStatus] then return { ok=false, error='Ugyldig status.' } end

    targetUsername = KC.normUsername(targetUsername)
    local row = MySQL.single.await('SELECT id, identifier FROM polititablet_accounts WHERE username=?', { targetUsername })
    if not row then return { ok=false, error='Konto ikke fundet.' } end

    MySQL.update.await('UPDATE polititablet_accounts SET status=? WHERE id=?', { newStatus, row.id })

    -- Hvis brugeren er online og blev suspenderet/bannet, force-logout dem
    if (newStatus == 'suspended' or newStatus == 'banned') and KCS.online[row.identifier] then
        if KCS.online[row.identifier].source then
            TriggerClientEvent('kcmdt:forceLogout', KCS.online[row.identifier].source, 'Din konto er '..newStatus..'.')
        end
        KCS.endSession(row.identifier, 'status_change')
    end

    KCS.audit(xp.identifier, xp.getName(), 'ACCOUNT_STATUS', targetUsername, newStatus)
    return { ok=true }
end)

-- ═══════════════════════════════════════════════════════════
--  CALLBACK: USERNAME AVAILABLE?
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:usernameAvailable', function(src, username)
    if not KCS.requirePermission(src, 'createAccount') then return false end
    username = KC.normUsername(username)
    if not KC.isValidUsername(username) then return false end
    local row = MySQL.scalar.await('SELECT id FROM polititablet_accounts WHERE username=?', { username })
    return row == nil
end)

-- ═══════════════════════════════════════════════════════════
--  GET RECENT ACCOUNTS (til boss-panel)
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getRecentAccounts', function(src)
    if not KCS.requirePermission(src, 'createAccount') then return {} end
    return MySQL.query.await([[
        SELECT username, rank, grade, badge_number, status, created_by_name, created_at, last_login
        FROM polititablet_accounts
        ORDER BY created_at DESC
        LIMIT 25
    ]], {}) or {}
end)
