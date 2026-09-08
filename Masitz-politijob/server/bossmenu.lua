-- ============================================================
-- MM-PolitiJob - server/bossmenu.lua
-- Boss menu callbacks: medarbejderliste, grade, fyr
-- ============================================================

-- ── HENT MEDARBEJDERE ────────────────────────────────────────
-- FIX: kaldte tidligere ikke DB_GetEmployees (server/database.lua)
-- men havde sin egen duplikerede kopi af den samme query, hardcoded
-- til ESX' schema. Nu genbruges den ene, framework-aware version.
lib.callback.register('mm_police:cb:getEmployees', function(src)
    if not SV.Framework.IsPolice(src) then return {} end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return {} end

    local p = promise.new()
    DB_GetEmployees(function(employees)
        p:resolve(employees or {})
    end)
    return Citizen.Await(p)
end)

-- ── SET GRADE ────────────────────────────────────────────────
RegisterNetEvent('mm_police:server:setGrade', function(identifier, grade)
    local src = source
    if not SV.Framework.IsPolice(src) then return end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return end

    grade = tonumber(grade)
    if not grade or grade < 0 or grade > 12 then return end
    if not identifier or type(identifier) ~= 'string' then return end

    -- FIX: kørte tidligere rå ESX-SQL direkte mod `users`-tabellen
    -- uden nogen framework-check, hvilket ikke virkede på QBCore.
    -- Opdater online spiller via framework-abstraktionen hvis muligt,
    -- ellers offline via den framework-aware helper.
    local targetSrc = nil
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if SV.Framework.GetIdentifier(id) == identifier then
            targetSrc = id
            break
        end
    end

    if targetSrc then
        local job = SV.Framework.GetJob(targetSrc)
        SV.Framework.SetJob(targetSrc, job or Config.PoliceJobs[1], grade)
        SV_Notify(targetSrc, 'Rank ændret', ('Din rank er ændret til grade %d.'):format(grade), 'inform')
    else
        SV.Framework.SetGradeOffline(identifier, grade)
    end

    SV_Notify(src, 'Grade', ('Grade opdateret til %d.'):format(grade), 'success')
end)

-- ── ELEVFEEDBACK ─────────────────────────────────────────────
-- REWORK: Config.FeedbackChoices/Config.FeedbackCategories fandtes
-- allerede i config, men blev aldrig brugt nogen steder, og
-- klientens "Politielev Feedback"-knap sendte et event
-- (mm_police:server:getFeedback) som ikke havde nogen handler
-- overhovedet — dead code der ikke gjorde noget. Nu et rigtigt,
-- SQL-baseret system: gemning, historik, server-valideret.

local function ValidateRatings(ratings)
    if type(ratings) ~= 'table' then return {} end

    local validChoice = {}
    for _, choice in ipairs(Config.FeedbackChoices or {}) do
        validChoice[choice] = true
    end

    local validField = {}
    for _, cat in ipairs(Config.FeedbackCategories or {}) do
        validField[cat.field] = true
    end

    local out = {}
    for field, value in pairs(ratings) do
        if validField[field] and validChoice[value] then
            out[field] = value
        end
    end
    return out
end

RegisterNetEvent('mm_police:server:submitFeedback', function(targetIdentifier, targetName, feedbackText, ratings)
    local src = source
    if not SV.Framework.IsPolice(src) then return end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return end

    if type(targetIdentifier) ~= 'string' or targetIdentifier == '' then return end
    if type(feedbackText) ~= 'string' or feedbackText == '' then
        SV_Notify(src, 'Feedback', 'Skriv en feedback-tekst.', 'error')
        return
    end
    if #feedbackText > 1000 then
        feedbackText = feedbackText:sub(1, 1000)
    end

    local cleanRatings = ValidateRatings(ratings)
    local ratingsJson = next(cleanRatings) and json.encode(cleanRatings) or nil

    local authorIdentifier = SV.Framework.GetIdentifier(src)
    local authorName       = SV.Framework.GetName(src)

    DB_SaveFeedback(targetIdentifier, targetName, authorIdentifier, authorName, feedbackText, ratingsJson)

    SV_Notify(src, 'Feedback', 'Feedback gemt.', 'success')
end)

lib.callback.register('mm_police:cb:getFeedback', function(src, targetIdentifier)
    if not SV.Framework.IsPolice(src) then return {} end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return {} end
    if type(targetIdentifier) ~= 'string' then return {} end

    local rows = DB_GetFeedback(targetIdentifier)
    for _, row in ipairs(rows) do
        row.ratings = row.ratings and json.decode(row.ratings) or nil
    end
    return rows
end)

-- ── FYR BETJENT ──────────────────────────────────────────────
RegisterNetEvent('mm_police:server:fireEmployee', function(identifier)
    local src = source
    if not SV.Framework.IsPolice(src) then return end
    if not SV.Framework.HasMinGrade(src, Config.BossMinGrade) then return end
    if not identifier or type(identifier) ~= 'string' then return end

    -- FIX: kørte tidligere rå ESX-SQL direkte mod `users`-tabellen,
    -- uafhængigt af hvilket framework der rent faktisk kører.
    local targetSrc = nil
    for _, pid in ipairs(GetPlayers()) do
        local id = tonumber(pid)
        if SV.Framework.GetIdentifier(id) == identifier then
            targetSrc = id
            break
        end
    end

    if targetSrc then
        SV.Framework.SetJob(targetSrc, 'unemployed', 0)
        SV_Notify(targetSrc, 'Fyret', 'Du er blevet fjernet fra politiet.', 'error')
    else
        SV.Framework.SetJobOffline(identifier, 'unemployed', 0)
    end

    SV_Notify(src, 'Fyret', 'Betjenten er fjernet fra politiet.', 'success')
end)
