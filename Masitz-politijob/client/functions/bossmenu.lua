-- ============================================================
-- MM-PolitiJob - client/functions/bossmenu.lua
-- Boss menu: medarbejder list, aktivitet, grade, fyr
-- ============================================================

function MM.OpenBossMenu()
    -- FIX: funktionen er exported og kunne tidligere kaldes direkte
    -- uden om markør-tjekket i client/main.lua (samme klasse bug som
    -- garagen havde). Tjek permission internt også.
    if not MM.Framework.IsPolice() or not MM.Framework.HasMinGrade(Config.BossMinGrade) then
        lib.notify({
            title       = 'Adgang nægtet',
            description = 'Du har ikke tilladelse til boss-menuen.',
            type        = 'error',
            position    = 'center-right',
        })
        return
    end

    lib.registerContext({
        id      = 'mm_boss_main',
        title   = '🛡️ Politi Ledelse',
        options = {
            {
                title       = '👮 Medarbejdere & Aktivitet',
                description = 'Se tjeneste-timer, rank og administrér personale',
                icon        = 'users',
                arrow       = true,
                onSelect    = function() MM.OpenEmployeeList() end,
            },
            {
                title       = '➕ Ansæt betjent',
                description = 'Ansæt en borger via server-ID',
                icon        = 'fa-user-plus',
                onSelect    = function()
                    local input = lib.inputDialog('Ansæt Betjent', {
                        { type = 'input', label = 'Spiller Server-ID', required = true },
                    })
                    if input and input[1] then
                        TriggerServerEvent('mm_police:server:hire', tonumber(input[1]))
                    end
                end,
            },
        },
    })
    lib.showContext('mm_boss_main')
end

exports('OpenBossMenu', MM.OpenBossMenu)

-- ── EMPLOYEE LIST ─────────────────────────────────────────────
function MM.OpenEmployeeList()
    lib.callback('mm_police:cb:getEmployees', false, function(employees)
        if not employees or #employees == 0 then
            lib.notify({ title = 'Fejl', description = 'Ingen medarbejdere fundet.', type = 'error', position = 'center-right' })
            return
        end

        local options = {}
        for _, emp in ipairs(employees) do
            options[#options + 1] = {
                title       = emp.name,
                description = ('Grade: %d | Uge: %dh | Måned: %dh')
                    :format(emp.grade, math.floor(emp.weekly / 60), math.floor(emp.monthly / 60)),
                icon        = 'user',
                arrow       = true,
                onSelect    = function() MM.OpenEmployeeDetail(emp) end,
            }
        end

        lib.registerContext({
            id      = 'mm_employee_list',
            title   = '👮 Medarbejderliste',
            menu    = 'mm_boss_main',
            options = options,
        })
        lib.showContext('mm_employee_list')
    end)
end

-- ── EMPLOYEE DETAIL ───────────────────────────────────────────
function MM.OpenEmployeeDetail(emp)
    lib.registerContext({
        id    = 'mm_employee_detail',
        title = emp.name,
        menu  = 'mm_employee_list',
        options = {
            {
                title    = '⏱️ Tids-statistik',
                readOnly = true,
                metadata = {
                    { label = 'Uge',   value = math.floor(emp.weekly  / 60) .. ' timer' },
                    { label = 'Måned', value = math.floor(emp.monthly / 60) .. ' timer' },
                },
            },
            {
                title       = '🔼 Ændre Rank',
                description = 'Oprangér eller degradér betjenten',
                icon        = 'arrow-up-9-1',
                onSelect    = function()
                    local input = lib.inputDialog('Ændre Rank: ' .. emp.name, {
                        { type = 'number', label = 'Ny Grade', description = '0–12', min = 0, max = 12, required = true },
                    })
                    if input and input[1] then
                        TriggerServerEvent('mm_police:server:setGrade', emp.identifier, input[1])
                    end
                end,
            },
            {
                title       = '🔽 Fyr Betjent',
                description = 'Fjern betjenten fra politiet',
                icon        = 'user-slash',
                onSelect    = function()
                    local confirm = lib.alertDialog({
                        header  = 'Bekræft Fyring',
                        content = ('Er du sikker på, du vil fyre **%s**?'):format(emp.name),
                        centered = true,
                        cancel  = true,
                    })
                    if confirm == 'confirm' then
                        TriggerServerEvent('mm_police:server:fireEmployee', emp.identifier)
                    end
                end,
            },
            {
                title       = '➕ Giv Elevfeedback',
                description = 'Skriv feedback til/om denne betjent',
                icon        = 'fa-solid fa-comment-medical',
                onSelect    = function() MM.GiveFeedback(emp) end,
            },
            {
                title       = '📋 Se Elevfeedback',
                description = 'Historik over tidligere feedback',
                icon        = 'fa-solid fa-clipboard-list',
                onSelect    = function() MM.ViewFeedback(emp) end,
            },
        },
    })
    lib.showContext('mm_employee_detail')
end

-- ── ELEVFEEDBACK: GIV ─────────────────────────────────────────
-- REWORK: rigtigt system i stedet for den gamle døde
-- "Politielev Feedback"-knap (sendte et event uden handler).
-- Genbruger Config.FeedbackCategories/Config.FeedbackChoices, som
-- allerede fandtes i config men aldrig blev brugt nogen steder.
function MM.GiveFeedback(emp)
    local rows = {}

    for _, cat in ipairs(Config.FeedbackCategories or {}) do
        local options = {}
        for _, choice in ipairs(Config.FeedbackChoices or {}) do
            options[#options + 1] = { value = choice, label = choice }
        end
        rows[#rows + 1] = {
            type    = 'select',
            label   = cat.label,
            options = options,
            default = Config.FeedbackChoices and Config.FeedbackChoices[1],
        }
    end

    rows[#rows + 1] = {
        type     = 'textarea',
        label    = 'Feedback',
        required = true,
    }

    local input = lib.inputDialog('Elevfeedback: ' .. emp.name, rows)
    if not input then return end

    local ratings = {}
    for i, cat in ipairs(Config.FeedbackCategories or {}) do
        if input[i] then ratings[cat.field] = input[i] end
    end

    local feedbackText = input[#rows]
    if not feedbackText or feedbackText == '' then
        lib.notify({ title = 'Feedback', description = 'Du skal skrive en feedback-tekst.', type = 'error', position = 'center-right' })
        return
    end

    TriggerServerEvent('mm_police:server:submitFeedback', emp.identifier, emp.name, feedbackText, ratings)
end

-- ── ELEVFEEDBACK: SE HISTORIK ─────────────────────────────────
function MM.ViewFeedback(emp)
    lib.callback('mm_police:cb:getFeedback', false, function(rows)
        if not rows or #rows == 0 then
            lib.notify({ title = 'Feedback', description = 'Ingen feedback fundet for denne betjent.', type = 'inform', position = 'center-right' })
            return
        end

        local options = {}
        for i, row in ipairs(rows) do
            options[#options + 1] = {
                title       = row.created_at,
                description = ('Givet af: %s'):format(row.author_name),
                icon        = 'comment',
                onSelect    = function()
                    local ratingLines = {}
                    if row.ratings then
                        for _, cat in ipairs(Config.FeedbackCategories or {}) do
                            if row.ratings[cat.field] then
                                ratingLines[#ratingLines + 1] = ('**%s:** %s'):format(cat.label, row.ratings[cat.field])
                            end
                        end
                    end

                    lib.alertDialog({
                        header  = ('📋 Feedback – %s'):format(emp.name),
                        content = ('**Spiller:** %s\n**Givet af:** %s\n**Dato:** %s\n\n%s\n\n%s')
                            :format(emp.name, row.author_name, row.created_at,
                                (#ratingLines > 0 and table.concat(ratingLines, '\n') or ''),
                                row.feedback),
                        centered = true,
                        cancel   = false,
                    })
                end,
            }
        end

        lib.registerContext({
            id      = 'mm_feedback_history',
            title   = '📋 Feedback: ' .. emp.name,
            menu    = 'mm_employee_detail',
            options = options,
        })
        lib.showContext('mm_feedback_history')
    end, emp.identifier)
end
