-- ============================================================
--  kc_mdt | server/sv_cases.lua
--  Cases, comments, evidence
-- ============================================================

lib.callback.register('kcmdt:getCases', function(src, filter)
    if not KCS.requireSession(src) then return {} end
    filter = filter or {}

    local where, params = {}, {}
    if filter.status and filter.status ~= 'all' then
        local allowed = { open=true, investigating=true, closed=true, archived=true }
        if allowed[filter.status] then
            where[#where+1] = 'status = ?'
            params[#params+1] = filter.status
        end
    end
    if filter.query and #filter.query > 0 then
        where[#where+1] = '(case_number LIKE ? OR title LIKE ?)'
        local n = '%' .. KC.safeStr(filter.query, 50) .. '%'
        params[#params+1] = n
        params[#params+1] = n
    end

    local sql = 'SELECT id, case_number, title, status, priority, created_by, created_at, updated_at FROM polititablet_cases'
    if #where > 0 then sql = sql .. ' WHERE ' .. table.concat(where, ' AND ') end
    sql = sql .. ' ORDER BY updated_at DESC LIMIT 100'
    return MySQL.query.await(sql, params) or {}
end)

lib.callback.register('kcmdt:getCase', function(src, caseId)
    if not KCS.requireSession(src) then return nil end
    caseId = tonumber(caseId); if not caseId then return nil end

    local row = MySQL.single.await('SELECT * FROM polititablet_cases WHERE id=?', { caseId })
    if not row then return nil end

    row.comments = MySQL.query.await('SELECT * FROM polititablet_case_comments WHERE case_id=? ORDER BY created_at ASC', { caseId }) or {}
    row.evidenceRows = MySQL.query.await('SELECT * FROM polititablet_evidence WHERE case_id=? ORDER BY created_at DESC', { caseId }) or {}
    return row
end)

RegisterNetEvent('kcmdt:createCase', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end
    if type(payload) ~= 'table' or not payload.title then return end

    local caseNum = KCS.generateCaseNum()
    local id = MySQL.insert.await([[
        INSERT INTO polititablet_cases (case_number,title,description,status,priority,created_by_id,created_by,suspects,officers)
        VALUES (?,?,?,?,?,?,?,?,?)
    ]], {
        caseNum,
        KC.safeStr(payload.title, 255),
        KC.safeStr(payload.description or '', 8000),
        (payload.status == 'investigating' and 'investigating' or 'open'),
        KC.clampInt(payload.priority or 1, 1, 3),
        sess.identifier, sess.rawName,
        json.encode(payload.suspects or {}),
        json.encode(payload.officers or {}),
    })

    KCS.audit(sess.identifier, sess.rawName, 'CREATE_CASE', caseNum, KC.safeStr(payload.title, 200))
    KCS.broadcastMDT('kcmdt:caseCreated', { id = id, case_number = caseNum, title = payload.title })
    TriggerClientEvent('kcmdt:notify', src, 'Sag oprettet: '..caseNum, 'success')
end)

RegisterNetEvent('kcmdt:updateCase', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if type(payload) ~= 'table' or not payload.id then return end
    local id = tonumber(payload.id); if not id then return end

    local newStatus = payload.status
    if newStatus == 'closed' or newStatus == 'archived' then
        if not KCS.requirePermission(src, 'closeCase') then return end
    end

    local allowed = { open=true, investigating=true, closed=true, archived=true }
    if not allowed[newStatus] then newStatus = 'open' end

    -- FIX (fundet under gennemgang, §45): dette var tidligere en positionel
    -- `?`-liste, hvor title/description/suspects/officers ofte er nil (kun
    -- title+description sendes reelt af NUI'en i dag). `ipairs` over en
    -- Lua-array stopper ved det FØRSTE nil-hul, så en positionel liste med
    -- fx `suspects=nil` i position 5 kunne stoppe iterationen der og aldrig
    -- sende `id` (position 7) med — dvs. UPDATE'en ramte enten intet eller
    -- forkert række. Named `:key`-parametre er upåvirket af det.
    MySQL.update([[
        UPDATE polititablet_cases SET
            title=COALESCE(:title,title),
            description=COALESCE(:description,description),
            status=:status,
            priority=:priority,
            suspects=COALESCE(:suspects,suspects),
            officers=COALESCE(:officers,officers)
        WHERE id=:id
    ]], {
        title       = payload.title and KC.safeStr(payload.title, 255) or nil,
        description = payload.description and KC.safeStr(payload.description, 8000) or nil,
        status      = newStatus,
        priority    = KC.clampInt(payload.priority or 1, 1, 3),
        suspects    = payload.suspects and json.encode(payload.suspects) or nil,
        officers    = payload.officers and json.encode(payload.officers) or nil,
        id          = id,
    })
    KCS.audit(sess.identifier, sess.rawName, 'UPDATE_CASE', tostring(id), newStatus)
    TriggerClientEvent('kcmdt:notify', src, 'Sag opdateret.', 'success')
end)

RegisterNetEvent('kcmdt:addCaseComment', function(caseId, body)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end
    caseId = tonumber(caseId); body = KC.safeStr(body, 4000)
    if not caseId or body == '' then return end

    MySQL.insert('INSERT INTO polititablet_case_comments (case_id,author_id,author_name,body) VALUES (?,?,?,?)',
        { caseId, sess.identifier, sess.rawName, body })
    -- Touch sag (updated_at)
    MySQL.update('UPDATE polititablet_cases SET updated_at=NOW() WHERE id=?', { caseId })
    TriggerClientEvent('kcmdt:notify', src, 'Kommentar tilføjet.', 'success')
end)

RegisterNetEvent('kcmdt:addEvidence', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end
    if type(payload) ~= 'table' or not payload.label then return end

    MySQL.insert([[
        INSERT INTO polititablet_evidence (case_id,citizenid,type,label,value,image_url,added_by)
        VALUES (?,?,?,?,?,?,?)
    ]], {
        tonumber(payload.case_id) or nil,
        payload.citizenid and KC.safeStr(payload.citizenid, 60) or nil,
        KC.safeStr(payload.type or 'document', 50),
        KC.safeStr(payload.label, 255),
        KC.safeStr(payload.value or '', 4000),
        KC.safeStr(payload.image_url or '', 1024),
        sess.rawName,
    })
    KCS.audit(sess.identifier, sess.rawName, 'ADD_EVIDENCE', KC.safeStr(payload.label, 100), nil)
    TriggerClientEvent('kcmdt:notify', src, 'Bevis tilføjet.', 'success')
end)
