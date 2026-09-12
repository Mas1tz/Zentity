-- ============================================================
--  kc_mdt | client/cl_registermdt.lua  (v2.0.2)
--  /registermdt — auto-derive rank/grade fra ESX job
-- ============================================================

local function hasRegisterPermission()
    local pdata = ESX.GetPlayerData()
    if not pdata or not pdata.job then return false end
    if not Config.AllowedJobs[pdata.job.name] then return false end
    local minGrade = (Config.Permissions and Config.Permissions.createAccount) or 10
    return (pdata.job.grade or 0) >= minGrade
end

local function suggestUsername(name)
    if not name or name == '' then return '' end
    local s = name:lower():gsub('[^%w%._%-]', '.')
    s = s:gsub('%.+', '.'):gsub('^%.+',''):gsub('%.+$','')
    if #s > Config.Security.maxUsernameLen then s = s:sub(1, Config.Security.maxUsernameLen) end
    return s
end

local function flowSelectTarget()
    if not hasRegisterPermission() then
        lib.notify({ title='MDT', description='Du har ikke tilladelse til at oprette MDT-konti.', type='error' })
        return
    end

    local players = lib.callback.await('kcmdt:getNearbyPlayers', false)

    local options = {}
    if players and #players > 0 then
        for _, p in ipairs(players) do
            local subtitle
            if not p.isPolice then
                subtitle = ('⚠ Ikke politi · ID: %d · %.1fm'):format(p.serverId, p.distance or 0)
            elseif p.hasAccount then
                subtitle = ('✓ Har allerede konto · %s (grade %d)'):format(p.jobGradeLabel or '-', p.jobGrade or 0)
            else
                subtitle = ('%s (grade %d) · ID: %d · %.1fm'):format(p.jobGradeLabel or p.job or '-', p.jobGrade or 0, p.serverId, p.distance or 0)
            end

            options[#options+1] = {
                title       = p.name,
                description = subtitle,
                icon        = p.hasAccount and 'circle-check' or (p.isPolice and 'user-plus' or 'user-slash'),
                iconColor   = p.hasAccount and '#22c55e' or (p.isPolice and '#3b82f6' or '#f59e0b'),
                disabled    = p.hasAccount or not p.isPolice,
                readOnly    = p.hasAccount or not p.isPolice,
                onSelect    = function() flowEnterCredentials(p) end,
                arrow       = not p.hasAccount and p.isPolice,
            }
        end
    end

    options[#options+1] = {
        title       = 'Indtast Server ID manuelt',
        description = 'Brug denne hvis spilleren ikke er i nærheden',
        icon        = 'keyboard',
        iconColor   = '#a855f7',
        onSelect    = function() flowManualId() end,
        arrow       = true,
    }

    lib.registerContext({
        id = 'kc_mdt_register_targets',
        title = '📋 /registermdt — Vælg spiller',
        options = options,
    })
    lib.showContext('kc_mdt_register_targets')
end

function flowManualId()
    local input = lib.inputDialog('Manuel Server ID', {
        { type='number', label='Server ID', description='Spillerens server ID', required=true, min=1, max=2048 },
    })
    if not input then return end

    local target = lib.callback.await('kcmdt:getPlayerByServerId', false, input[1])
    if not target or not target.found then
        lib.notify({ title='MDT', description=(target and target.error) or 'Spiller ikke fundet.', type='error' })
        return
    end
    if target.hasAccount then
        lib.notify({ title='MDT', description=target.name..' har allerede en MDT-konto.', type='warning' })
        return
    end
    if not target.isPolice then
        lib.notify({ title='MDT', description=target.name..' er ikke politi. Sæt deres job først.', type='error', duration=6000 })
        return
    end
    flowEnterCredentials(target)
end

function flowEnterCredentials(target)
    local suggestion = suggestUsername(target.name)

    -- Vis tydeligt hvilken rang spilleren får (auto fra ESX)
    local rankPreview = ('%s (grade %d)'):format(target.jobGradeLabel or target.job or '-', target.jobGrade or 0)

    local input = lib.inputDialog(('Ny MDT-konto for %s'):format(target.name), {
        { type='input',  label='Brugernavn',  description='Skal være unikt. Kun a-z 0-9 . _ -', default=suggestion, required=true, min=Config.Security.minUsernameLen, max=Config.Security.maxUsernameLen },
        { type='input',  label='Adgangskode', description='Standard er 1234 — spilleren skal skifte den ved første login.', default=Config.RegisterMDT.defaultPassword, required=true, min=Config.Security.minPasswordLen, max=Config.Security.maxPasswordLen, password=true },
        { type='input',  label='Badge nummer (frivilligt)', default=Config.RegisterMDT.badgePrefix .. tostring(math.random(1000, 9999)) },
        { type='input',  label='Auto-rang fra job', description='Hentes automatisk fra spillerens politi-job', default=rankPreview, disabled=true },
    }, { allowCancel = true })

    if not input then return end

    local username = (input[1] or ''):lower():gsub('%s+','')
    local password = input[2] or Config.RegisterMDT.defaultPassword
    local badge    = input[3] or ''

    local available = lib.callback.await('kcmdt:usernameAvailable', false, username)
    if not available then
        lib.notify({ title='MDT', description='Brugernavnet "'..username..'" er allerede taget. Vælg et andet.', type='error' })
        return flowEnterCredentials(target)
    end

    local res = lib.callback.await('kcmdt:registerMDT', false, {
        targetId = target.serverId,
        username = username,
        password = password,
        badge    = badge,
    })

    if not res or not res.ok then
        lib.notify({ title='MDT', description=(res and res.error) or 'Ukendt fejl.', type='error', duration=6000 })
        return
    end

    PlaySoundFrontend(-1, 'Hack_Success', 'DLC_HEIST_BIOLAB_PREP_HACKING_SOUNDS', false)
    local alertRes = lib.alertDialog({
        header  = '✅ MDT-konto oprettet',
        content = (
            '**Spiller:** '..res.targetName..'\n'..
            '**Brugernavn:** `'..res.username..'`\n'..
            '**Adgangskode:** `'..res.password..'`\n'..
            '**Rang:** '..res.rank..' (grade '..res.grade..')\n'..
            (res.badge ~= '' and ('**Badge:** '..res.badge..'\n') or '')..
            '\n_Spilleren skal skifte adgangskoden ved første login._'
        ),
        centered = true, size = 'md', cancel = true,
        labels = { confirm = 'Kopiér login', cancel = 'Luk' },
    })

    if alertRes == 'confirm' then
        local clip = ('Brugernavn: %s | Adgangskode: %s'):format(res.username, res.password)
        lib.setClipboard(clip)
        lib.notify({ title='MDT', description='Login kopieret til udklipsholder.', type='success' })
    end
end

RegisterCommand(Config.RegisterCommand, function() flowSelectTarget() end, false)
TriggerEvent('chat:addSuggestion', '/'..Config.RegisterCommand, 'Opret MDT-konto til en politibetjent (kræver grade '..(Config.Permissions.createAccount or 10)..'+)')
