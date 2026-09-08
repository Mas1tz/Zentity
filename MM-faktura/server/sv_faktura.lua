-- ============================================================
--  server/sv_faktura.lua  –  Faktura Tablet V2
-- ============================================================

local Framework = Config.Framework
if Framework == "auto" then
    Framework = GetResourceState("qb-core") == "started" and "qb" or "esx"
end

local QBCore, ESX = nil, nil
if Framework == "esx" then
    ESX = exports["es_extended"]:getSharedObject()
elseif Framework == "qb" then
    QBCore = exports['qb-core']:GetCoreObject()
end

-- ============================================================
--  IDENTITET / FRAMEWORK HELPERS
-- ============================================================
local function GetIdentifier(src)
    for _, id in ipairs(GetPlayerIdentifiers(src)) do
        if id:find("license:") then return id end
    end
    return tostring(src)
end

local function GetIdentity(src)
    local ok, result = pcall(function()
        if Framework == "esx" then
            local xPlayer = ESX.GetPlayerFromId(src)
            if not xPlayer then return nil end
            local job = xPlayer.job or {}
            local grade = job.grade
            if type(grade) == "table" then grade = grade.level or grade.grade or 0 end
            return {
                name  = xPlayer.getName(),
                job   = job.name or "unemployed",
                grade = tonumber(grade) or 0,
                gradeLabel = job.grade_label or job.grade_name or "",
            }
        else
            local player = QBCore.Functions.GetPlayer(src)
            if not player then return nil end
            local char = player.PlayerData.charinfo or {}
            local job = player.PlayerData.job or {}
            local grade = job.grade
            if type(grade) == "table" then grade = grade.level or 0 end
            return {
                name  = ((char.firstname or "?") .. " " .. (char.lastname or "?")),
                job   = job.name or "unemployed",
                grade = tonumber(grade) or 0,
                gradeLabel = job.label or "",
            }
        end
    end)

    if not ok then
        print(("^1[mm-faktura] Fejl i GetIdentity for src %s: %s^0"):format(tostring(src), tostring(result)))
        return nil
    end
    return result
end

local function GetMoney(src, amount)
    -- Prøver bank først, derefter kontanter. Returnerer true ved succes.
    if Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if not xPlayer then return false end
        if xPlayer.getAccount('bank').money >= amount then
            xPlayer.removeAccountMoney('bank', amount)
            return true
        elseif xPlayer.getMoney() >= amount then
            xPlayer.removeMoney(amount)
            return true
        end
        return false
    else
        local player = QBCore.Functions.GetPlayer(src)
        if not player then return false end
        if player.Functions.RemoveMoney("bank", amount) then return true end
        if player.Functions.RemoveMoney("cash", amount) then return true end
        return false
    end
end

local function AddMoney(src, amount)
    if Framework == "esx" then
        local xPlayer = ESX.GetPlayerFromId(src)
        if xPlayer then xPlayer.addAccountMoney('bank', amount) end
    else
        local player = QBCore.Functions.GetPlayer(src)
        if player then player.Functions.AddMoney("bank", amount) end
    end
end

-- ============================================================
--  PERMISSIONS – hvem må sende regninger / redigere kategorier
-- ============================================================
local function CanBill(src)
    local identity = GetIdentity(src)
    return identity and Config.BillingJobs[identity.job] ~= nil, identity
end

local function IsAdmin(src)
    if IsPlayerAceAllowed(src, Config.CategoryManagement.aceGroup) then return true end
    local identifier = GetIdentifier(src)
    for _, id in ipairs(Config.CategoryManagement.superAdmins or {}) do
        if id == identifier then return true end
    end
    return false
end

local function CanManageCategory(src, job)
    if IsAdmin(src) then
        return true, "admin"
    end
    local identity = GetIdentity(src)
    if not identity then return false end
    if identity.job == job then
        local minGrade = Config.CategoryManagement.jobGradeOverride[job]
        if minGrade and identity.grade >= minGrade then
            return true, "job"
        end
    end
    return false
end

-- ============================================================
--  KATEGORI-REGISTER (config.lua + runtime export + DB-custom)
-- ============================================================
local runtimeCategories = {} -- [job] = { {group=, items={...}}, ... }  (fra andre resources' exports)
local customCategories  = {} -- [job] = { {group=, items={...}}, ... }  (fra DB, spiller-oprettet)

local function loadCustomCategories()
    customCategories = {}
    MySQL.Async.fetchAll("SELECT * FROM mm_faktura_custom_categories ORDER BY id ASC", {}, function(rows)
        for _, row in ipairs(rows or {}) do
            customCategories[row.job] = customCategories[row.job] or {}
            local groupList = customCategories[row.job]
            local targetGroup = nil
            for _, g in ipairs(groupList) do
                if g.group == row.group_name then targetGroup = g break end
            end
            if not targetGroup then
                targetGroup = { group = row.group_name, items = {}, custom = true }
                table.insert(groupList, targetGroup)
            end
            table.insert(targetGroup.items, { id = row.cat_id, label = row.label, price = row.price, custom = true, dbId = row.id })
        end
    end)
end
CreateThread(function() Wait(1000) loadCustomCategories() end)

-- Slår grupper med samme navn sammen på tværs af de tre kilder
local function mergeGroupsInto(target, source)
    for _, srcGroup in ipairs(source or {}) do
        local existing = nil
        for _, g in ipairs(target) do
            if g.group == srcGroup.group then existing = g break end
        end
        if existing then
            for _, item in ipairs(srcGroup.items) do table.insert(existing.items, item) end
        else
            local copy = { group = srcGroup.group, items = {} }
            for _, item in ipairs(srcGroup.items) do table.insert(copy.items, item) end
            table.insert(target, copy)
        end
    end
end

function GetMergedCategories(job)
    local merged = {}
    mergeGroupsInto(merged, Config.Categories[job])
    mergeGroupsInto(merged, runtimeCategories[job])
    mergeGroupsInto(merged, customCategories[job])
    return merged
end

local function findCategoryItem(job, catId)
    for _, group in ipairs(GetMergedCategories(job)) do
        for _, item in ipairs(group.items) do
            if item.id == catId then return item, group end
        end
    end
    return nil
end

-- ============================================================
--  DATABASE / AUTO-MIGRATION
--  Tidligere afhang resourcen 100% af at masitzfaktura.sql var kørt
--  manuelt mod databasen - blev det glemt, fejlede hver eneste query
--  med "Table ... doesn't exist". Opretter nu selv tabellerne ved
--  resource-start (skal være 100% identisk med masitzfaktura.sql).
-- ============================================================
local function EnsureTables()
    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `mm_faktura_invoices` (
            `id`                INT             AUTO_INCREMENT,
            `target_identifier` VARCHAR(60)     NOT NULL,
            `target_name`       VARCHAR(50)     DEFAULT NULL,
            `from_identifier`   VARCHAR(60)     DEFAULT NULL,
            `from_name`         VARCHAR(50)     DEFAULT NULL,
            `job`               VARCHAR(50)     DEFAULT NULL,
            `category_label`    VARCHAR(255)    DEFAULT NULL,
            `meta`              LONGTEXT,
            `amount`            INT             NOT NULL DEFAULT 0,
            `paid`              TINYINT(1)      NOT NULL DEFAULT 0,
            `paid_at`           TIMESTAMP       NULL DEFAULT NULL,
            `created_at`        TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            INDEX `idx_target` (`target_identifier`),
            INDEX `idx_created` (`created_at`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})

    MySQL.Sync.execute([[
        CREATE TABLE IF NOT EXISTS `mm_faktura_custom_categories` (
            `id`           INT             AUTO_INCREMENT,
            `job`          VARCHAR(50)     NOT NULL,
            `group_name`   VARCHAR(100)    NOT NULL,
            `cat_id`       VARCHAR(60)     NOT NULL,
            `label`        VARCHAR(255)    NOT NULL,
            `price`        INT             NOT NULL DEFAULT 0,
            `created_by`   VARCHAR(60)     DEFAULT NULL,
            `created_at`   TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            UNIQUE KEY `uniq_job_cat` (`job`, `cat_id`),
            INDEX `idx_job` (`job`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]], {})
end

CreateThread(function()
    while GetResourceState('oxmysql') ~= 'started' do
        Wait(100)
    end

    local ok, err = pcall(EnsureTables)
    if ok then
        print('^2[MM-faktura]^7 Database klar (tabeller verificeret)')
    else
        print('^1[MM-faktura]^7 Kunne ikke oprette tabeller automatisk: ' .. tostring(err))
        print('^1[MM-faktura]^7 Kør masitzfaktura.sql manuelt mod databasen.')
    end
end)

-- ============================================================
--  INVOICE HELPERS (DB)
-- ============================================================
local function purgeOldInvoices()
    MySQL.Async.execute(
        "DELETE FROM mm_faktura_invoices WHERE created_at < (NOW() - INTERVAL @days DAY)",
        { ["@days"] = Config.InvoiceRetentionDays }
    )
end
CreateThread(function()
    Wait(5000)
    purgeOldInvoices()
    while true do
        Wait(60 * 60 * 1000) -- hver time
        purgeOldInvoices()
    end
end)

local function pushInvoicesToOnlinePlayer(identifier)
    local src = nil
    for _, pid in ipairs(GetPlayers()) do
        if GetIdentifier(tonumber(pid)) == identifier then src = tonumber(pid) break end
    end
    if not src then return end

    MySQL.Async.fetchAll(
        "SELECT * FROM mm_faktura_invoices WHERE target_identifier = @id ORDER BY created_at DESC",
        { ["@id"] = identifier },
        function(rows)
            TriggerClientEvent('mm_faktura:client:invoicesUpdated', src, rows or {})
        end
    )
end

-- Opret regning. Bruges både af NUI-flowet og af eksterne resources via export.
-- opts = {
--   targetIdentifier / targetSrc, fromIdentifier / fromSrc, fromName, job,
--   amount (trusted, valgfrit hvis items er sat), items = {{id, antal}} (slås op server-side),
--   categoryLabel (bruges kun hvis items ikke er sat), meta
-- }
function CreateInvoice(opts)
    local targetIdentifier = opts.targetIdentifier
    local targetName = opts.targetName
    if not targetIdentifier and opts.targetSrc then
        targetIdentifier = GetIdentifier(opts.targetSrc)
        local id = GetIdentity(opts.targetSrc)
        targetName = id and id.name or targetName
    end
    if not targetIdentifier then return false, "Ugyldig modtager" end

    local fromIdentifier = opts.fromIdentifier
    local fromName = opts.fromName or "System"
    if not fromIdentifier and opts.fromSrc then
        fromIdentifier = GetIdentifier(opts.fromSrc)
        local id = GetIdentity(opts.fromSrc)
        fromName = id and id.name or fromName
    end

    local amount = tonumber(opts.amount) or 0
    local categoryLabel = opts.categoryLabel or "Diverse"

    if opts.items and #opts.items > 0 then
        amount = 0
        local labels = {}
        local breakdown = {}
        for _, entry in ipairs(opts.items) do
            local item = findCategoryItem(opts.job, entry.id)
            if item then
                local antal = tonumber(entry.antal) or 1
                local subtotal = item.price * antal
                amount = amount + subtotal
                table.insert(labels, ("%s x%d"):format(item.label, antal))
                table.insert(breakdown, { label = item.label, price = item.price, antal = antal, subtotal = subtotal })
            end
        end
        categoryLabel = table.concat(labels, ", ")
        if opts.discountPct and opts.discountPct > 0 then
            amount = math.floor(amount * (1 - opts.discountPct / 100))
        end
        if not opts.meta then
            opts.meta = { items = breakdown, discountPct = opts.discountPct or 0 }
        end
    end

    if amount <= 0 then return false, "Ugyldigt beløb" end

    MySQL.Async.execute([[
        INSERT INTO mm_faktura_invoices
            (target_identifier, target_name, from_identifier, from_name, job, category_label, meta, amount)
        VALUES
            (@target, @targetName, @from, @fromName, @job, @label, @meta, @amount)
    ]], {
        ["@target"]     = targetIdentifier,
        ["@targetName"] = targetName,
        ["@from"]       = fromIdentifier,
        ["@fromName"]   = fromName,
        ["@job"]        = opts.job,
        ["@label"]      = categoryLabel,
        ["@meta"]       = opts.meta and json.encode(opts.meta) or nil,
        ["@amount"]     = amount,
    }, function(insertId)
        if not insertId or insertId == 0 then
            print(("^1[mm-faktura] INSERT af regning fejlede muligvis (target=%s, amount=%s)^0"):format(tostring(targetIdentifier), tostring(amount)))
        end

        -- Notificér + opdatér modtageren hvis online – KUN efter INSERT er bekræftet gennemført,
        -- ellers kan opdateringen nå frem før regningen reelt er gemt.
        for _, pid in ipairs(GetPlayers()) do
            local pidNum = tonumber(pid)
            if GetIdentifier(pidNum) == targetIdentifier then
                TriggerClientEvent('mm_faktura:client:notify', pidNum, { type = 'inform', text = ('Ny regning modtaget: %s DKK (%s)'):format(amount, categoryLabel) })
                pushInvoicesToOnlinePlayer(targetIdentifier)
                break
            end
        end
    end)

    return true, amount
end

-- ============================================================
--  NET EVENTS – klient (Faktura-tabletten)
-- ============================================================
RegisterNetEvent('mm_faktura:server:getInvoices', function()
    local src = source
    pushInvoicesToOnlinePlayer(GetIdentifier(src))
end)

RegisterNetEvent('mm_faktura:server:whoAmI', function()
    local src = source
    local admin = IsAdmin(src)
    local manageableJobs = {}
    if admin then
        for job, _ in pairs(Config.BillingJobs) do table.insert(manageableJobs, job) end
    else
        local identity = GetIdentity(src)
        if identity and CanManageCategory(src, identity.job) then
            table.insert(manageableJobs, identity.job)
        end
    end
    TriggerClientEvent('mm_faktura:client:permissions', src, { isAdmin = admin, manageableJobs = manageableJobs })
end)

RegisterNetEvent('mm_faktura:server:getPlayerInfo', function(targetId)
    local src = source
    targetId = tonumber(targetId)
    if not targetId then return end

    local identity = GetIdentity(targetId)
    if not identity then
        return TriggerClientEvent('mm_faktura:client:playerInfo', src, targetId, nil)
    end

    -- Svar med det samme, så UI'en reagerer uden at vente på databasen.
    TriggerClientEvent('mm_faktura:client:playerInfo', src, targetId, {
        name = identity.name, job = identity.job, grade = identity.gradeLabel,
        unpaidCount = 0, unpaidTotal = 0, totalCount = 0,
    })

    -- Ubetalt-oversigten efterfølges separat, når/hvis databasen svarer.
    local identifier = GetIdentifier(targetId)
    local ok, err = pcall(function()
        MySQL.Async.fetchAll([[
            SELECT
                COUNT(*) AS total,
                SUM(CASE WHEN paid = 0 THEN 1 ELSE 0 END) AS unpaid_count,
                COALESCE(SUM(CASE WHEN paid = 0 THEN amount ELSE 0 END), 0) AS unpaid_total
            FROM mm_faktura_invoices WHERE target_identifier = @id
        ]], { ["@id"] = identifier }, function(rows)
            local summary = rows and rows[1] or { total = 0, unpaid_count = 0, unpaid_total = 0 }
            TriggerClientEvent('mm_faktura:client:playerSummary', src, targetId, {
                unpaidCount = summary.unpaid_count or 0,
                unpaidTotal = summary.unpaid_total or 0,
                totalCount  = summary.total or 0,
            })
        end)
    end)
    if not ok then
        print(("^1[mm-faktura] DB-fejl i getPlayerInfo (er install.sql kørt?): %s^0"):format(tostring(err)))
    end
end)

RegisterNetEvent('mm_faktura:server:sendInvoice', function(payload)
    local src = source
    local canBill, senderIdentity = CanBill(src)
    if not canBill then
        return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Dit job har ikke adgang' })
    end

    local targetId = tonumber(payload.targetId)
    if not targetId or not GetPlayerName(targetId) then
        return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Ugyldig spiller' })
    end

    local ok, result = CreateInvoice({
        targetSrc   = targetId,
        fromSrc     = src,
        job         = senderIdentity.job,
        items       = payload.items,
        discountPct = tonumber(payload.discountPct) or 0,
    })

    if ok then
        TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = ('Regning sendt – %s DKK'):format(result) })
    else
        TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = result })
    end
end)

RegisterNetEvent('mm_faktura:server:payInvoice', function(invoiceId)
    local src = source
    local identifier = GetIdentifier(src)
    invoiceId = tonumber(invoiceId)
    if not invoiceId then return end

    MySQL.Async.fetchAll("SELECT * FROM mm_faktura_invoices WHERE id = @id AND target_identifier = @target AND paid = 0",
        { ["@id"] = invoiceId, ["@target"] = identifier },
        function(rows)
            local inv = rows and rows[1]
            if not inv then
                return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Regningen findes ikke længere' })
            end

            if not GetMoney(src, inv.amount) then
                return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Du har ikke nok penge' })
            end

            MySQL.Async.execute("UPDATE mm_faktura_invoices SET paid = 1, paid_at = NOW() WHERE id = @id", { ["@id"] = invoiceId }, function()
                if inv.from_identifier then
                    for _, pid in ipairs(GetPlayers()) do
                        local pidNum = tonumber(pid)
                        if GetIdentifier(pidNum) == inv.from_identifier then
                            AddMoney(pidNum, inv.amount)
                            break
                        end
                    end
                end

                TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = 'Regning betalt! Du kan nu slette den fra listen.' })
                pushInvoicesToOnlinePlayer(identifier)
            end)
        end)
end)

RegisterNetEvent('mm_faktura:server:deleteInvoice', function(invoiceId)
    local src = source
    local identifier = GetIdentifier(src)
    invoiceId = tonumber(invoiceId)
    if not invoiceId then return end

    MySQL.Async.fetchAll("SELECT * FROM mm_faktura_invoices WHERE id = @id", { ["@id"] = invoiceId }, function(rows)
        local inv = rows and rows[1]
        if not inv then return end

        local allowed = IsAdmin(src)
            or (inv.target_identifier == identifier and inv.paid == 1)
            or (inv.from_identifier == identifier)

        if not allowed then
            return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Du kan ikke slette denne regning' })
        end

        MySQL.Async.execute("DELETE FROM mm_faktura_invoices WHERE id = @id", { ["@id"] = invoiceId }, function()
            pushInvoicesToOnlinePlayer(identifier)
        end)
    end)
end)

-- ============================================================
--  KATEGORI-STYRING (Administrer-fanen i tabletten)
-- ============================================================
RegisterNetEvent('mm_faktura:server:requestCategories', function(job)
    local src = source
    local canManage = CanManageCategory(src, job)
    TriggerClientEvent('mm_faktura:client:categoriesData', src, job, GetMergedCategories(job), canManage)
end)

-- Bemærk: der er bevidst ingen separat "opret tom gruppe"-handling.
-- En gruppe oprettes automatisk første gang en vare tilføjes med et nyt
-- gruppenavn (se addItem herunder) – det undgår tomme grupper der ikke
-- kan gemmes i databasen.

RegisterNetEvent('mm_faktura:server:addItem', function(job, groupName, label, price)
    local src = source
    if not CanManageCategory(src, job) then return end

    label = tostring(label or ""):sub(1, 255)
    price = tonumber(price) or 0
    if label == "" or price <= 0 then
        return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Udfyld navn og en gyldig pris' })
    end

    local catId = ("custom_%s_%d"):format(job, os.time() + math.random(1, 9999))
    local identifier = GetIdentifier(src)

    MySQL.Async.execute([[
        INSERT INTO mm_faktura_custom_categories (job, group_name, cat_id, label, price, created_by)
        VALUES (@job, @group, @catId, @label, @price, @by)
    ]], { ["@job"] = job, ["@group"] = groupName, ["@catId"] = catId, ["@label"] = label, ["@price"] = price, ["@by"] = identifier },
    function()
        loadCustomCategories()
        Wait(300)
        TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = 'Vare tilføjet' })
        TriggerEvent('__mm_faktura_refresh', src, job)
    end)
end)

RegisterNetEvent('mm_faktura:server:editItem', function(job, catId, label, price)
    local src = source
    if not CanManageCategory(src, job) then return end

    local item = findCategoryItem(job, catId)
    if not item or not item.dbId then
        return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Kun selv-oprettede varer kan redigeres' })
    end

    label = tostring(label or ""):sub(1, 255)
    price = tonumber(price) or 0
    if label == "" or price <= 0 then return end

    MySQL.Async.execute("UPDATE mm_faktura_custom_categories SET label = @label, price = @price WHERE id = @id",
        { ["@label"] = label, ["@price"] = price, ["@id"] = item.dbId },
        function()
            loadCustomCategories()
            Wait(300)
            TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = 'Vare opdateret' })
            TriggerEvent('__mm_faktura_refresh', src, job)
        end)
end)

RegisterNetEvent('mm_faktura:server:deleteItem', function(job, catId)
    local src = source
    if not CanManageCategory(src, job) then return end

    local item = findCategoryItem(job, catId)
    if not item or not item.dbId then
        return TriggerClientEvent('mm_faktura:client:notify', src, { type = 'error', text = 'Kun selv-oprettede varer kan slettes' })
    end

    MySQL.Async.execute("DELETE FROM mm_faktura_custom_categories WHERE id = @id", { ["@id"] = item.dbId }, function()
        loadCustomCategories()
        Wait(300)
        TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = 'Vare slettet' })
        TriggerEvent('__mm_faktura_refresh', src, job)
    end)
end)

RegisterNetEvent('mm_faktura:server:deleteGroup', function(job, groupName)
    local src = source
    if not CanManageCategory(src, job) then return end

    MySQL.Async.execute("DELETE FROM mm_faktura_custom_categories WHERE job = @job AND group_name = @group",
        { ["@job"] = job, ["@group"] = groupName }, function()
            loadCustomCategories()
            Wait(300)
            TriggerClientEvent('mm_faktura:client:notify', src, { type = 'success', text = 'Gruppe slettet' })
            TriggerEvent('__mm_faktura_refresh', src, job)
        end)
end)

-- Simpelt internt "refresh" hook så editoren i tabletten opdaterer sig selv efter en ændring
AddEventHandler('__mm_faktura_refresh', function(src, job)
    local canManage = CanManageCategory(src, job)
    TriggerClientEvent('mm_faktura:client:categoriesData', src, job, GetMergedCategories(job), canManage)
end)

-- ============================================================
--  EXPORTS – til andre resources (politi-tablet, unicorn-tablet, osv.)
-- ============================================================

--- Send en regning uden at åbne UI'en.
--- data = {
---   targetId = <server id, PÅKRÆVET, spilleren skal være online>,
---   job = "police", -- bruges til kategori-opslag + vises i historik
---   fromId = <server id, valgfri>, fromIdentifier, fromName = <string, valgfri>,
---   amount = <tal, valgfri hvis items er sat>,
---   label = <string, bruges hvis items ikke er sat>,
---   items = { {id="roedt_lys", antal=1}, ... } -- pris slås op server-side ud fra job's kategorier
---   discountPct = <0-100, valgfri>, meta = <table, valgfri>
--- }
--- returns: ok(boolean), amountOrErrorMessage
exports('SendInvoice', function(data)
    return CreateInvoice({
        targetSrc       = data.targetId,
        targetIdentifier = data.targetIdentifier,
        fromSrc         = data.fromId,
        fromIdentifier  = data.fromIdentifier,
        fromName        = data.fromName,
        job             = data.job,
        amount          = data.amount,
        categoryLabel   = data.label,
        items           = data.items,
        discountPct     = data.discountPct,
        meta            = data.meta,
    })
end)

--- Åbn selve Faktura-tabletten for en spiller udefra (fx fra politi-tabletten)
exports('OpenTablet', function(src, initialData)
    TriggerClientEvent('mm_faktura:client:externalOpen', src, initialData or {})
end)

--- Registrér en enkelt vare under en (evt. ny) gruppe for et job – kaldes typisk
--- én gang når dit eget resource starter.
exports('RegisterCategory', function(job, groupName, item)
    runtimeCategories[job] = runtimeCategories[job] or {}
    local target = nil
    for _, g in ipairs(runtimeCategories[job]) do
        if g.group == groupName then target = g break end
    end
    if not target then
        target = { group = groupName, items = {} }
        table.insert(runtimeCategories[job], target)
    end
    table.insert(target.items, item)
    return true
end)

--- Registrér en hel gruppe med flere varer på én gang.
exports('RegisterCategoryGroup', function(job, groupName, items)
    runtimeCategories[job] = runtimeCategories[job] or {}
    table.insert(runtimeCategories[job], { group = groupName, items = items or {} })
    return true
end)

--- Hent de samlede kategorier for et job (config + runtime + DB-custom)
exports('GetCategories', function(job)
    return GetMergedCategories(job)
end)

--- Hent hurtigt overblik over en spillers ubetalte regninger (fx til dispatch)
exports('GetUnpaidSummary', function(identifierOrSrc, cb)
    local identifier = identifierOrSrc
    if type(identifierOrSrc) == "number" then identifier = GetIdentifier(identifierOrSrc) end
    MySQL.Async.fetchAll([[
        SELECT COUNT(*) AS unpaid_count, COALESCE(SUM(amount),0) AS unpaid_total
        FROM mm_faktura_invoices WHERE target_identifier = @id AND paid = 0
    ]], { ["@id"] = identifier }, function(rows)
        local r = rows and rows[1] or { unpaid_count = 0, unpaid_total = 0 }
        if cb then cb(r.unpaid_count, r.unpaid_total) end
    end)
end)
