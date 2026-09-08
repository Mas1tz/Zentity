-- ============================================================
-- MM-PolitiJob - server/database.lua
-- Database setup + hjælpere
-- ============================================================

MySQL.ready(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `police_activity` (
            `identifier`   VARCHAR(64)  NOT NULL,
            `char_name`    VARCHAR(100) DEFAULT 'Ukendt',
            `weekly_time`  INT          DEFAULT 0,
            `monthly_time` INT          DEFAULT 0,
            `total_time`   INT          DEFAULT 0,
            `last_clockin` TIMESTAMP    DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
            `last_update`  DATE         DEFAULT (CURRENT_DATE),
            PRIMARY KEY (`identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    -- Elevfeedback (v3.1 rework) — se masitzpolitijob.sql
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `police_feedback` (
            `id`                 INT          NOT NULL AUTO_INCREMENT,
            `target_identifier`  VARCHAR(64)  NOT NULL,
            `target_name`        VARCHAR(100) DEFAULT 'Ukendt',
            `author_identifier`  VARCHAR(64)  NOT NULL,
            `author_name`        VARCHAR(100) DEFAULT 'Ukendt',
            `feedback`           TEXT         NOT NULL,
            `ratings`            TEXT         DEFAULT NULL,
            `created_at`         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `target_identifier` (`target_identifier`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    if Config.Debug then print('[MM-PolitiJob] Database tabeller klar.') end
end)

-- ── GEM ELEVFEEDBACK ─────────────────────────────────────────
function DB_SaveFeedback(targetIdentifier, targetName, authorIdentifier, authorName, feedbackText, ratingsJson)
    if not targetIdentifier or not authorIdentifier or not feedbackText then return end
    MySQL.insert([[
        INSERT INTO police_feedback
            (target_identifier, target_name, author_identifier, author_name, feedback, ratings)
        VALUES (?, ?, ?, ?, ?, ?)
    ]], { targetIdentifier, targetName or 'Ukendt', authorIdentifier, authorName or 'Ukendt', feedbackText, ratingsJson })
end

-- ── HENT ELEVFEEDBACK-HISTORIK FOR ÉN SPILLER ────────────────
function DB_GetFeedback(targetIdentifier)
    if not targetIdentifier then return {} end
    local results = MySQL.query.await([[
        SELECT target_name, author_name, feedback, ratings, created_at
        FROM police_feedback
        WHERE target_identifier = ?
        ORDER BY created_at DESC
        LIMIT 25
    ]], { targetIdentifier })
    return results or {}
end

-- ── UPSERT AKTIV-TID ─────────────────────────────────────────
-- Kaldes fra server/main.lua når en spiller holder op med at have
-- politi-jobbet (jobskifte eller disconnect), med hvor mange
-- minutter de har haft jobbet siden sidste opdatering.
function DB_SaveTime(identifier, charName, minutes)
    if not identifier or not minutes or minutes <= 0 then return end
    MySQL.query([[
        INSERT INTO police_activity (identifier, char_name, weekly_time, monthly_time, total_time, last_update)
        VALUES (?, ?, ?, ?, ?, CURDATE())
        ON DUPLICATE KEY UPDATE
            char_name    = VALUES(char_name),
            weekly_time  = weekly_time  + VALUES(weekly_time),
            monthly_time = monthly_time + VALUES(monthly_time),
            total_time   = total_time   + VALUES(total_time),
            last_clockin = CURRENT_TIMESTAMP,
            last_update  = CURDATE()
    ]], { identifier, charName or 'Ukendt', minutes, minutes, minutes })
end

-- ── HENT MEDARBEJDERE (boss menu) ────────────────────────────
-- FIX: denne query var hardcoded til ESX' `users` tabel og ville
-- returnere 0 rækker (stille, uden fejl) på en QBCore-server, selv
-- om Config.Framework = "auto"/"qb". Nu framework-aware.
-- FIX: denne funktion blev tidligere defineret men ALDRIG kaldt -
-- server/bossmenu.lua havde sin egen duplikerede kopi af samme
-- query i stedet for at genbruge denne. Nu er dette den ENESTE
-- implementation, og bossmenu.lua kalder ind i den.
-- Synkron (await-baseret) variant, ment til brug inde i en
-- lib.callback.register handler, som allerede kører i en coroutine
-- der kan yield'e.
function DB_GetEmployees()
    local fw = SV.Framework.GetType()

    -- Byg en dynamisk IN(...) placeholder-liste ud fra Config.PoliceJobs
    -- i stedet for at hardcode 'police' - config.lua er den centrale
    -- kilde til hvilke jobs der tæller som politi.
    local placeholders = {}
    for i = 1, #Config.PoliceJobs do placeholders[i] = '?' end
    local inClause = table.concat(placeholders, ', ')

    local results
    if fw == 'qb' then
        results = MySQL.query.await(([[
            SELECT
                citizenid,
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) AS firstname,
                JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname'))  AS lastname,
                JSON_EXTRACT(job, '$.grade.level')                  AS job_grade,
                COALESCE(pa.weekly_time,  0) AS weekly,
                COALESCE(pa.monthly_time, 0) AS monthly
            FROM players p
            LEFT JOIN police_activity pa ON p.citizenid = pa.identifier
            WHERE JSON_UNQUOTE(JSON_EXTRACT(p.job, '$.name')) IN (%s)
            ORDER BY job_grade DESC, firstname ASC
        ]]):format(inClause), Config.PoliceJobs)

        if not results then return {} end
        local out = {}
        for _, r in ipairs(results) do
            out[#out + 1] = {
                identifier = r.citizenid,
                name       = (r.firstname or 'Ukendt') .. ' ' .. (r.lastname or ''),
                grade      = tonumber(r.job_grade) or 0,
                weekly     = r.weekly,
                monthly    = r.monthly,
            }
        end
        return out
    end

    -- ESX (default)
    results = MySQL.query.await(([[
        SELECT
            u.identifier,
            u.firstname,
            u.lastname,
            u.job_grade,
            COALESCE(pa.weekly_time,  0) AS weekly,
            COALESCE(pa.monthly_time, 0) AS monthly
        FROM users u
        LEFT JOIN police_activity pa ON u.identifier = pa.identifier
        WHERE u.job IN (%s)
        ORDER BY u.job_grade DESC, u.firstname ASC
    ]]):format(inClause), Config.PoliceJobs)

    if not results then return {} end
    local out = {}
    for _, r in ipairs(results) do
        out[#out + 1] = {
            identifier = r.identifier,
            name       = (r.firstname or 'Ukendt') .. ' ' .. (r.lastname or ''),
            grade      = r.job_grade or 0,
            weekly     = r.weekly,
            monthly    = r.monthly,
        }
    end
    return out
end
