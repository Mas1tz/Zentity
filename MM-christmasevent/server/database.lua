-- ══════════════════════════════════════════════════════════
--  DATABASE — mm-christmas
--
--  Alt DB-adgang går gennem denne fil. Indeholder også en
--  selv-migrerende opstarts-rutine: hvis en eksisterende installation
--  mangler kolonner koden forventer (fx `claimed_rewards`, som den
--  gamle version læste/skrev til uden at kolonnen nogensinde blev
--  tilføjet til install.sql), tilføjes de automatisk uden datatab.
--  Dette virker på både MySQL 5.7+ og MariaDB (undgår
--  `ADD COLUMN IF NOT EXISTS`, som ikke er universelt understøttet).
-- ══════════════════════════════════════════════════════════

Database = {}

local TABLE_NAME = 'mm_christmas_players'

-- Kolonner koden forventer, men som ikke nødvendigvis findes i en
-- ældre installation. key = kolonnenavn, value = DDL-fragment.
local REQUIRED_COLUMNS = {
    claimed_rewards    = "LONGTEXT NULL",
    world_gifts_found  = "LONGTEXT NULL",
}

local function columnExists(column)
    local row = MySQL.scalar.await(
        [[SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?]],
        { TABLE_NAME, column }
    )
    return (row or 0) > 0
end

function Database.RunMigrations()
    local tableExistsRow = MySQL.scalar.await(
        [[SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES
          WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ?]],
        { TABLE_NAME }
    )

    if (tableExistsRow or 0) == 0 then
        Shared.Warn(('Tabellen "%s" findes ikke endnu. Kør install.sql før du starter resourcen.'):format(TABLE_NAME))
        return
    end

    local migrated = {}
    for column, ddl in pairs(REQUIRED_COLUMNS) do
        local ok, exists = pcall(columnExists, column)
        if ok and not exists then
            local alterOk, err = pcall(function()
                MySQL.query.await(('ALTER TABLE `%s` ADD COLUMN `%s` %s'):format(TABLE_NAME, column, ddl))
            end)
            if alterOk then
                migrated[#migrated + 1] = column
            else
                Shared.Warn(('Migration fejlede for kolonne "%s": %s'):format(column, tostring(err)))
            end
        elseif not ok then
            Shared.Warn(('Kunne ikke tjekke om kolonne "%s" findes: %s'):format(column, tostring(exists)))
        end
    end

    if #migrated > 0 then
        print(('^2[mm-christmas]^0 Database migreret - tilføjede kolonne(r): %s'):format(table.concat(migrated, ', ')))
    end
end

local function defaultRow(identifier)
    return {
        identifier      = identifier,
        name            = '',
        xp              = 0,
        level           = 1,
        coins           = 0,
        trees_decorated = 0,
        snowmen_built   = 0,
        gifts_found     = 0,
        personal_gifts  = 0,
        distance_driven = 0,
        distance_run    = 0,
        daily_tasks     = '{}',
        weekly_tasks    = '{}',
        daily_reset     = nil,
        weekly_reset    = nil,
        trees_done      = '[]',
        shop_purchases  = '{}',
        claimed_rewards = '[]',
        world_gifts_found = '[]',
    }
end

function Database.LoadPlayer(identifier)
    local result = MySQL.single.await(
        ('SELECT * FROM `%s` WHERE identifier = ?'):format(TABLE_NAME),
        { identifier }
    )

    if not result then
        local row = defaultRow(identifier)
        local ok, err = pcall(function()
            MySQL.insert.await(
                ('INSERT INTO `%s` (identifier, name) VALUES (?, ?)'):format(TABLE_NAME),
                { identifier, '' }
            )
        end)
        if not ok then
            Shared.Warn(('Kunne ikke oprette ny spillerrække for %s: %s'):format(identifier, tostring(err)))
        end
        return row
    end

    -- Ældre rækker fra før migrationen kan have NULL i de nye kolonner.
    result.claimed_rewards   = result.claimed_rewards   or '[]'
    result.world_gifts_found = result.world_gifts_found or '[]'
    result.daily_tasks       = result.daily_tasks       or '{}'
    result.weekly_tasks      = result.weekly_tasks      or '{}'
    result.trees_done        = result.trees_done        or '[]'
    result.shop_purchases    = result.shop_purchases    or '{}'

    return result
end

function Database.SavePlayer(src, data)
    -- data.coins er en READ-ONLY leaderboard-cache — opdater den fra
    -- den faktiske inventory-saldo (source of truth) lige før gem,
    -- så leaderboardet aldrig kan vise et forkert/forældet tal.
    if src then
        data.coins = Currency.Get(src)
    end

    local ok, err = pcall(function()
        MySQL.update.await(([[
            UPDATE `%s` SET
                name              = ?,
                xp                = ?,
                level             = ?,
                coins             = ?,
                trees_decorated   = ?,
                snowmen_built     = ?,
                gifts_found       = ?,
                personal_gifts    = ?,
                distance_driven   = ?,
                distance_run      = ?,
                daily_tasks       = ?,
                weekly_tasks      = ?,
                daily_reset       = ?,
                weekly_reset      = ?,
                trees_done        = ?,
                shop_purchases    = ?,
                claimed_rewards   = ?,
                world_gifts_found = ?
            WHERE identifier = ?
        ]]):format(TABLE_NAME), {
            data.name,
            data.xp,
            data.level,
            data.coins,
            data.trees_decorated,
            data.snowmen_built,
            data.gifts_found,
            data.personal_gifts,
            data.distance_driven,
            data.distance_run,
            data.daily_tasks,
            data.weekly_tasks,
            data.daily_reset,
            data.weekly_reset,
            data.trees_done,
            data.shop_purchases,
            data.claimed_rewards or '[]',
            data.world_gifts_found or '[]',
            data.identifier,
        })
    end)

    if not ok then
        Shared.Warn(('SavePlayer fejlede for %s: %s'):format(tostring(data.identifier), tostring(err)))
    end
end

-- Bygger den datastruktur der sendes til NUI. `src` bruges til at hente
-- den LIVE coins-saldo fra inventoryet i stedet for den (potentielt
-- forældede) DB-cache.
function Database.BuildClientData(src, data)
    local xpInto, xpReq = Shared.XPIntoLevel(data.xp)

    local function buildTaskList(tasksJson, pool)
        local list  = {}
        local tasks = json.decode(tasksJson) or {}
        for id, state in pairs(tasks) do
            local cfg = nil
            for _, t in ipairs(pool) do
                if t.id == id then cfg = t; break end
            end
            if cfg then
                list[#list + 1] = {
                    id       = id,
                    label    = cfg.label,
                    type     = cfg.type,
                    target   = cfg.target,
                    progress = state.progress,
                    done     = state.done,
                    xp       = cfg.xp,
                    coins    = cfg.coins,
                }
            end
        end
        return list
    end

    return {
        level             = data.level,
        xp                = xpInto,
        xpRequired        = xpReq,
        totalXP           = data.xp,
        coins             = Currency.Get(src),
        treesDecorated    = data.trees_decorated,
        snowmenBuilt      = data.snowmen_built,
        giftsFound        = data.gifts_found,
        personalGifts     = data.personal_gifts,
        distanceDriven    = data.distance_driven,
        distanceRun       = data.distance_run,
        dailyTasks        = buildTaskList(data.daily_tasks,  Config.DailyTasks),
        weeklyTasks       = buildTaskList(data.weekly_tasks, Config.WeeklyTasks),
        treesDone         = json.decode(data.trees_done) or {},
        worldGiftsFound   = json.decode(data.world_gifts_found or '[]') or {},
        shopPurchases     = json.decode(data.shop_purchases) or {},
        claimedRewards    = json.decode(data.claimed_rewards or '[]') or {},
        name              = data.name,
    }
end
