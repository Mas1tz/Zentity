-- ============================================================
--  kc_mdt | server/sv_persons.lua
--  Person register, warrants, journals, arrests
-- ============================================================

-- ═══════════════════════════════════════════════════════════
--  SEARCH CITIZENS
--  Søger på firstname, lastname, fuld navn, identifier, telefon
--  COALESCE bruges fordi NULL-felter ellers "spiser" hele matchen
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:searchCitizens', function(src, query)
    if not KCS.requireSession(src) then return {} end
    query = KC.trim(query or '')
    if #query < 2 then return {} end
    local needle = '%' .. query .. '%'

    return MySQL.query.await([[
        SELECT u.identifier AS citizenid, u.firstname, u.lastname, u.dateofbirth,
               u.phone_number, u.job, u.job_grade, u.sex,
               mc.risk_level, mc.mugshot_url,
               (SELECT COUNT(*) FROM polititablet_warrants w WHERE w.citizenid = u.identifier AND w.active=1) AS warrant_count
        FROM users u
        LEFT JOIN polititablet_citizens mc ON mc.citizenid = u.identifier
        WHERE COALESCE(u.firstname,'') LIKE ?
           OR COALESCE(u.lastname,'')  LIKE ?
           OR CONCAT(COALESCE(u.firstname,''),' ',COALESCE(u.lastname,'')) LIKE ?
           OR u.identifier LIKE ?
           OR COALESCE(u.phone_number,'') LIKE ?
        ORDER BY u.lastname, u.firstname
        LIMIT 30
    ]], { needle, needle, needle, needle, needle }) or {}
end)

-- ═══════════════════════════════════════════════════════════
--  GET CITIZEN FULL
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getCitizenFull', function(src, citizenid)
    if not KCS.requireSession(src) then return nil end
    citizenid = KC.safeStr(citizenid, 60)
    if citizenid == '' then return nil end

    local user = MySQL.single.await('SELECT * FROM users WHERE identifier=?', { citizenid })
    if not user then return nil end

    return {
        user     = user,
        mdt      = MySQL.single.await('SELECT * FROM polititablet_citizens WHERE citizenid=?', { citizenid }),
        warrants = MySQL.query.await('SELECT * FROM polititablet_warrants WHERE citizenid=? ORDER BY created_at DESC', { citizenid }) or {},
        arrests  = MySQL.query.await('SELECT * FROM polititablet_arrests  WHERE citizenid=? ORDER BY created_at DESC LIMIT 30', { citizenid }) or {},
        journals = MySQL.query.await('SELECT * FROM polititablet_journals  WHERE citizenid=? ORDER BY created_at DESC LIMIT 30', { citizenid }) or {},
        evidence = MySQL.query.await('SELECT * FROM polititablet_evidence  WHERE citizenid=? ORDER BY created_at DESC LIMIT 20', { citizenid }) or {},
    }
end)

-- ═══════════════════════════════════════════════════════════
--  ONLINE PLAYERS (Personregister §10)
--  Viser alle p.t. tilsluttede spillere (uanset job) med samme
--  borgerdata som søgning, så listen kan bruges/åbnes 1:1 med
--  openPerson() i NUI'en.
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getOnlinePlayers', function(src)
    if not KCS.requireSession(src) then return {} end

    local players = ESX.GetExtendedPlayers()
    if not players or #players == 0 then return {} end

    local idents, placeholders = {}, {}
    for _, xp in ipairs(players) do
        idents[#idents+1] = xp.identifier
        placeholders[#placeholders+1] = '?'
    end

    local rows = MySQL.query.await(([[
        SELECT u.identifier AS citizenid, u.firstname, u.lastname, u.dateofbirth,
               u.phone_number, u.job, u.job_grade, u.sex,
               mc.risk_level, mc.mugshot_url,
               (SELECT COUNT(*) FROM polititablet_warrants w WHERE w.citizenid = u.identifier AND w.active=1) AS warrant_count
        FROM users u
        LEFT JOIN polititablet_citizens mc ON mc.citizenid = u.identifier
        WHERE u.identifier IN (%s)
    ]]):format(table.concat(placeholders, ',')), idents) or {}

    -- Slå identifier op så vi kan tilføje job-label + serverId fra den live spiller.
    local byIdent = {}
    for _, xp in ipairs(players) do byIdent[xp.identifier] = xp end

    local out = {}
    for _, row in ipairs(rows) do
        local xp = byIdent[row.citizenid]
        if xp then
            row.serverId = xp.source
            row.jobLabel = xp.job and (xp.job.label or xp.job.name) or row.job
            out[#out+1] = row
        end
    end
    return out
end)

-- ═══════════════════════════════════════════════════════════
--  UPDATE CITIZEN (mugshot, risk, notes)
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('kcmdt:updateCitizen', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end
    if type(payload) ~= 'table' or not payload.citizenid then return end

    local cid   = KC.safeStr(payload.citizenid, 60)
    local risk  = KC.clampInt(payload.risk_level or 0, 0, 4)
    local mug   = KC.safeStr(payload.mugshot_url or '', 1024)
    local notes = KC.safeStr(payload.notes or '', 4000)

    MySQL.query.await([[
        INSERT INTO polititablet_citizens (citizenid, risk_level, mugshot_url, notes)
        VALUES (?,?,?,?)
        ON DUPLICATE KEY UPDATE risk_level=?, mugshot_url=?, notes=?
    ]], { cid, risk, mug, notes, risk, mug, notes })

    KCS.audit(sess.identifier, sess.rawName, 'UPDATE_CITIZEN', cid, ('risk=%d'):format(risk))
    TriggerClientEvent('kcmdt:notify', src, 'Borgerprofil opdateret.', 'success')
end)

-- ═══════════════════════════════════════════════════════════
--  JOURNALS
-- ═══════════════════════════════════════════════════════════
RegisterNetEvent('kcmdt:addJournal', function(citizenid, title, body)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.spamCheck(src) then return end

    citizenid = KC.safeStr(citizenid, 60)
    title     = KC.safeStr(title, 255)
    body      = KC.safeStr(body, 8000)
    if citizenid == '' or title == '' or body == '' then return end

    MySQL.insert('INSERT INTO polititablet_journals (citizenid,author_id,author_name,title,body) VALUES (?,?,?,?,?)',
        { citizenid, sess.identifier, sess.rawName, title, body })
    KCS.audit(sess.identifier, sess.rawName, 'ADD_JOURNAL', citizenid, title)
    TriggerClientEvent('kcmdt:notify', src, 'Journal tilføjet.', 'success')
end)

RegisterNetEvent('kcmdt:deleteJournal', function(journalId)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'deleteJournal') then return end
    journalId = tonumber(journalId); if not journalId then return end

    MySQL.update('DELETE FROM polititablet_journals WHERE id=?', { journalId })
    KCS.audit(sess.identifier, sess.rawName, 'DELETE_JOURNAL', tostring(journalId), nil)
    TriggerClientEvent('kcmdt:notify', src, 'Journal slettet.', 'success')
end)

-- ═══════════════════════════════════════════════════════════
--  ARRESTS (Opret sigtelse — §15-§21)
-- ═══════════════════════════════════════════════════════════

-- Klientens billede/officer/genstand-payloads valideres og trimmes
-- forsigtigt server-side, så et ondsindet/ødelagt NUI-payload aldrig
-- kan give os et kæmpe eller malformed JSON-blob i databasen.
local function sanitizeOfficers(list)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for _, o in ipairs(list) do
        if type(o) == 'table' and o.identifier and o.name then
            out[#out+1] = { identifier = KC.safeStr(o.identifier, 60), name = KC.safeStr(o.name, 100) }
        end
        if #out >= 20 then break end
    end
    return out
end

local function sanitizeImages(list, maxCount)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for _, img in ipairs(list) do
        if type(img) == 'string' and img:match('^data:image/') and #img < 400000 then
            out[#out+1] = img
        end
        if #out >= (maxCount or 4) then break end
    end
    return out
end

local function sanitizeSeizedItems(list)
    if type(list) ~= 'table' then return {} end
    local out = {}
    for _, it in ipairs(list) do
        if type(it) == 'table' and it.item and it.item ~= '' then
            out[#out+1] = {
                category = KC.safeStr(it.category or 'Andre genstande', 60),
                item     = KC.safeStr(it.item, 120),
                qty      = KC.clampInt(it.qty or 1, 1, 9999),
            }
        end
        if #out >= 50 then break end
    end
    return out
end

-- §33 — Server autoritativ: klienten sender kun HVILKE bødeskema-labels der
-- er valgt, aldrig et kronebeløb. Beløb/fængsel beregnes altid her ud fra
-- config.lua, så en manipuleret NUI ikke kan oprette en sigtelse med et
-- vilkårligt/forfalsket bødebeløb.
local chargeLookup = nil
local function getChargeLookup()
    if chargeLookup then return chargeLookup end
    chargeLookup = {}
    for _, list in pairs(Config.Fines or {}) do
        for _, f in ipairs(list) do
            chargeLookup[f.label] = { fine = f.fine or 0, jail = f.jail or 0 }
        end
    end
    return chargeLookup
end
local function computeChargeTotals(labels)
    local lookup = getChargeLookup()
    local validLabels, fine, jail = {}, 0, 0
    if type(labels) == 'table' then
        for _, label in ipairs(labels) do
            local c = type(label) == 'string' and lookup[label]
            if c then
                validLabels[#validLabels+1] = label
                fine = fine + c.fine
                jail = jail + c.jail
            end
        end
    end
    return validLabels, fine, jail
end

RegisterNetEvent('kcmdt:createArrest', function(payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'createArrest') then return end
    if not KCS.spamCheck(src) then return end
    if type(payload) ~= 'table' or not payload.citizenid then return end

    local cid       = KC.safeStr(payload.citizenid, 60)
    local validCharges, fine, jail = computeChargeTotals(payload.charges) -- §33: beløb beregnes server-side, aldrig klient-input
    local notes      = KC.safeStr(payload.notes or '', 8000) -- hændelsesforløb (§17)
    local charges    = json.encode(validCharges)
    local officers   = json.encode(sanitizeOfficers(payload.officers))
    local images     = json.encode(sanitizeImages(payload.images, Config.Images and Config.Images.maxPerEntry))
    local seized     = json.encode(sanitizeSeizedItems(payload.seized_items))
    local warrantId  = tonumber(payload.warrant_id) or nil

    -- NAMED parametre her, ikke positionelle: `warrantId` er typisk nil (de
    -- fleste sigtelser stammer ikke fra en efterlysning), og en `nil` som
    -- SIDSTE element i en Lua-array-konstruktør bliver droppet af `{...}`
    -- selv, så en positionel `?`-liste ville ende med færre parametre end
    -- pladsholdere og fejle hver gang. Named `:key`-parametre (en almindelig
    -- hash-tabel) har intet "sidste element"-problem.
    local id = MySQL.insert.await([[
        INSERT INTO polititablet_arrests
            (citizenid,officer_id,officer_name,officers,charges,total_fine,total_jail,notes,images,seized_items,warrant_id)
        VALUES (:citizenid,:officerId,:officerName,:officers,:charges,:totalFine,:totalJail,:notes,:images,:seizedItems,:warrantId)
    ]], {
        citizenid    = cid,
        officerId    = sess.identifier,
        officerName  = sess.rawName,
        officers     = officers,
        charges      = charges,
        totalFine    = fine,
        totalJail    = jail,
        notes        = notes,
        images       = images,
        seizedItems  = seized,
        warrantId    = warrantId,
    })

    -- Kladden er ikke længere relevant når sigtelsen reelt er oprettet (§21).
    MySQL.update('DELETE FROM polititablet_arrest_drafts WHERE officer_id=? AND citizenid=?', { sess.identifier, cid })

    KCS.audit(sess.identifier, sess.rawName, 'ARREST', cid, ('fine=%d jail=%d'):format(fine, jail))
    TriggerClientEvent('kcmdt:notify', src, 'Sigtelse oprettet.', 'success')

    -- Notify target hvis online
    local target = ESX.GetPlayerFromIdentifier(cid)
    if target then
        TriggerClientEvent('kcmdt:popup', target.source, {
            type    = 'arrest',
            message = ('Du er sigtet af %s. Bøde: %d kr, fængsel: %d md.'):format(sess.rawName, fine, jail),
        })
    end
end)

-- ═══════════════════════════════════════════════════════════
--  ARREST DRAFTS — autosave/kladde (§21)
--  Én kladde pr. (betjent, borger). Overskrives ved hvert autosave.
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getArrestDraft', function(src, citizenid)
    local sess = KCS.requireSession(src); if not sess then return nil end
    citizenid = KC.safeStr(citizenid, 60); if citizenid == '' then return nil end

    local row = MySQL.single.await(
        'SELECT payload, updated_at FROM polititablet_arrest_drafts WHERE officer_id=? AND citizenid=?',
        { sess.identifier, citizenid })
    if not row then return nil end

    local ok, decoded = pcall(json.decode, row.payload)
    if not ok or type(decoded) ~= 'table' then return nil end
    return { payload = decoded, updated_at = row.updated_at }
end)

RegisterNetEvent('kcmdt:saveArrestDraft', function(citizenid, payload)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    citizenid = KC.safeStr(citizenid, 60); if citizenid == '' then return end
    if type(payload) ~= 'table' then return end

    -- Samme sanitisering som ved reel oprettelse, så en kladde aldrig kan
    -- blive et vilkårligt stort/malformed blob.
    local clean = {
        notes        = KC.safeStr(payload.notes or '', 8000),
        charges      = payload.charges,
        officers     = sanitizeOfficers(payload.officers),
        images       = sanitizeImages(payload.images, Config.Images and Config.Images.maxPerEntry),
        seized_items = sanitizeSeizedItems(payload.seized_items),
        warrant_id   = tonumber(payload.warrant_id) or nil,
    }

    MySQL.query([[
        INSERT INTO polititablet_arrest_drafts (officer_id,citizenid,payload)
        VALUES (?,?,?)
        ON DUPLICATE KEY UPDATE payload=?, updated_at=NOW()
    ]], { sess.identifier, citizenid, json.encode(clean), json.encode(clean) })
end)

RegisterNetEvent('kcmdt:deleteArrestDraft', function(citizenid)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    citizenid = KC.safeStr(citizenid, 60); if citizenid == '' then return end

    MySQL.update('DELETE FROM polititablet_arrest_drafts WHERE officer_id=? AND citizenid=?', { sess.identifier, citizenid })
end)

-- ═══════════════════════════════════════════════════════════
--  WARRANTS
-- ═══════════════════════════════════════════════════════════
lib.callback.register('kcmdt:getWarrants', function(src)
    if not KCS.requireSession(src) then return {} end
    return MySQL.query.await([[
        SELECT w.*, u.firstname, u.lastname, mc.risk_level, mc.mugshot_url
        FROM polititablet_warrants w
        LEFT JOIN users u ON u.identifier = w.citizenid
        LEFT JOIN polititablet_citizens mc ON mc.citizenid = w.citizenid
        WHERE w.active = 1
        ORDER BY w.created_at DESC
        LIMIT 50
    ]], {}) or {}
end)

RegisterNetEvent('kcmdt:addWarrant', function(citizenid, reason, riskLevel, image)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'issueWarrant') then return end
    if not KCS.spamCheck(src) then return end

    citizenid = KC.safeStr(citizenid, 60)
    reason    = KC.trim(KC.safeStr(reason, 1000))
    if citizenid == '' or reason == '' then return end
    local risk = KC.clampInt(riskLevel or 1, 0, 4)

    -- Billedet er en data:-URI produceret af client-side canvas-komprimering
    -- (§12) — accepteres kun hvis det reelt ligner et billede og ikke er
    -- absurd stort, ellers gemmes ingen (aldrig hård fejl på selve efterlysningen).
    local img = nil
    if type(image) == 'string' and image:match('^data:image/') and #image < 400000 then
        img = image
    end

    -- Named parametre: `img` er ofte nil (billede er valgfrit), og en nil
    -- midt i en positionel `?`-array kan afkortes af hvordan driveren
    -- itererer arrayet (se AuthorizePlateChange i Masitz-Anticheat for
    -- samme bug/fix) — named `:key` undgår problemet helt.
    MySQL.insert(
        'INSERT INTO polititablet_warrants (citizenid,reason,risk_level,image,issued_by_id,issued_by) VALUES (:citizenid,:reason,:risk,:image,:issuedById,:issuedBy)',
        { citizenid = citizenid, reason = reason, risk = risk, image = img, issuedById = sess.identifier, issuedBy = sess.rawName }
    )

    KCS.audit(sess.identifier, sess.rawName, 'ADD_WARRANT', citizenid, reason)
    KCS.broadcastMDT('kcmdt:warrantAlert', {
        citizenid = citizenid,
        reason    = reason,
        risk      = risk,
        issuedBy  = sess.rawName,
    })
    TriggerClientEvent('kcmdt:notify', src, 'Efterlysning oprettet.', 'success')
end)

-- Redigér en eksisterende AKTIV efterlysning (§16 — "nemme at redigere"),
-- så en betjent ikke behøver fjerne+genoprette den for en tekst-/risiko-rettelse.
RegisterNetEvent('kcmdt:editWarrant', function(warrantId, reason, riskLevel)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'issueWarrant') then return end
    if not KCS.spamCheck(src) then return end

    warrantId = tonumber(warrantId); if not warrantId then return end
    reason = KC.trim(KC.safeStr(reason, 1000))
    if reason == '' then return end
    local risk = KC.clampInt(riskLevel or 1, 0, 4)

    local updated = MySQL.update.await(
        'UPDATE polititablet_warrants SET reason=?, risk_level=? WHERE id=? AND active=1',
        { reason, risk, warrantId }
    )

    if updated and updated > 0 then
        KCS.audit(sess.identifier, sess.rawName, 'EDIT_WARRANT', tostring(warrantId), reason)
        KCS.broadcastMDT('kcmdt:warrantAlert', { edited = true })
        TriggerClientEvent('kcmdt:notify', src, 'Efterlysning opdateret.', 'success')
    else
        TriggerClientEvent('kcmdt:notify', src, 'Efterlysningen findes ikke længere (måske allerede fjernet).', 'error')
    end
end)

RegisterNetEvent('kcmdt:removeWarrant', function(citizenid)
    local src = source
    local sess = KCS.requireSession(src); if not sess then return end
    if not KCS.requirePermission(src, 'removeWarrant') then return end
    citizenid = KC.safeStr(citizenid, 60); if citizenid == '' then return end

    MySQL.update('UPDATE polititablet_warrants SET active=0 WHERE citizenid=? AND active=1', { citizenid })
    KCS.audit(sess.identifier, sess.rawName, 'REMOVE_WARRANT', citizenid, nil)
    KCS.broadcastMDT('kcmdt:warrantAlert', { citizenid = citizenid, removed = true })
    TriggerClientEvent('kcmdt:notify', src, 'Efterlysning fjernet.', 'success')
end)
