-- ══════════════════════════════════════════════════════════
--  SERVER — mm-christmas
--
--  Alt herunder behandler clienten som fjendtlig input. Intet event
--  stoler på en værdi fra clienten uden at validere den mod
--  Config/databasen/spillerens faktiske server-side position/state
--  først. Se README.md "Security" for den fulde liste over hvad der
--  ændrede sig og hvorfor.
-- ══════════════════════════════════════════════════════════

Shared.LoadLocale(Config.Locale)

-- ── PLAYER CACHE ─────────────────────────────────────────
local Players    = {}   -- [src] = db row (mutable in-memory copy)
local Processing = {}   -- [src] = true while an atomic op (shop/box) is running

-- ── WORLD STATE (delt mellem alle spillere) ──────────────
local ActiveSnowmen = {}  -- [locIndex] = GetGameTimer() expiry
local ActiveGifts   = {}  -- [giftId] = { target = src, expires = GetGameTimer() }
local giftCounter   = 0

-- ── NOTIFY HELPER (ensartet ox_lib notify) ───────────────
local function notify(src, title, ntype, duration, icon, description)
    TriggerClientEvent('ox_lib:notify', src, {
        title       = title,
        description = description,
        type        = ntype or 'inform',
        duration    = duration or 3000,
        icon        = icon,
    })
end

local function playerPos(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    return GetEntityCoords(ped)
end

-- ── TASK RESET HELPERS ───────────────────────────────────
local function GetTodayStr() return os.date('%Y-%m-%d') end

local function GetWeekStr()
    -- %V understøttes ikke konsistent i FiveM's Lua — manuel ISO uge-beregning.
    local t          = os.time()
    local d          = os.date('*t', t)
    local year       = d.year
    local jan1       = os.time({ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    local dayOfYear  = math.floor((t - jan1) / 86400) + 1
    local jan1Wday   = os.date('*t', jan1).wday
    local iso1       = (jan1Wday == 1) and 7 or (jan1Wday - 1)
    local weekNum    = math.floor((dayOfYear + iso1 - 2) / 7) + 1
    if weekNum < 1 then weekNum = 52 end
    if weekNum > 52 then weekNum = 1 end
    return year .. '-W' .. string.format('%02d', weekNum)
end

local function EnsureTasksReset(data)
    local changed = false
    local today   = GetTodayStr()
    local week    = GetWeekStr()

    if data.daily_reset ~= today then
        local picked = Shared.PickRandomTasks(Config.DailyTasks, Config.DailyTaskCount)
        local tasks  = {}
        for _, t in ipairs(picked) do
            tasks[t.id] = { progress = 0, done = false }
        end
        data.daily_tasks = json.encode(tasks)
        data.daily_reset = today
        changed = true
    end

    if data.weekly_reset ~= week then
        local picked = Shared.PickRandomTasks(Config.WeeklyTasks, Config.WeeklyTaskCount)
        local tasks  = {}
        for _, t in ipairs(picked) do
            tasks[t.id] = { progress = 0, done = false }
        end
        data.weekly_tasks = json.encode(tasks)
        data.weekly_reset = week
        changed = true
    end

    return changed
end

-- ── XP / LEVEL ────────────────────────────────────────────
-- INTERNT ONLY: amount kommer altid fra Config, ALDRIG fra klienten.
-- Der findes bevidst intet client-triggerbart "giveXP(amount)" event -
-- den gamle version havde et, helt uvalideret, som lod enhver spiller
-- give sig selv ubegrænset XP/coins/task-fremgang. Det er fjernet.
local function GiveXP(src, data, amount)
    if data.level >= Config.MaxLevel then return end
    if amount <= 0 then return end

    data.xp = data.xp + amount
    notify(src, T('xp_gained', Shared.FormatNumber(amount)), 'success', 3000, 'star')

    while data.level < Config.MaxLevel do
        local req = Shared.XPRequired(data.level)
        if data.xp < req then break end
        data.xp    = data.xp - req
        data.level = data.level + 1

        notify(src, T('level_up', data.level), 'success', 5000, 'tree')
        -- Level-belønninger gives IKKE automatisk her — de skal hentes
        -- via claimLevelReward (Locked/Available/Claimed-flowet i UI'et).
        -- Den gamle version gav dem BÅDE automatisk her OG lod spilleren
        -- claime dem igen via UI'et, hvilket var en duplication-exploit.
    end
end

-- INTERNT ONLY: amount kommer altid fra Config.
local function GiveCoins(src, data, amount)
    if amount <= 0 then return end
    local given = Currency.Add(src, amount)
    if given <= 0 then
        notify(src, T('coins_max', Shared.FormatNumber(Config.MaxCoins)), 'warning', 3000)
        return
    end
    notify(src, T('coins_gained', Shared.FormatNumber(given)), 'success', 3000, 'coins')
end

-- ── TASK PROGRESS ─────────────────────────────────────────
local function UpdateTask(src, data, taskType, amount)
    local function processPool(tasksJson, pool)
        local tasks   = json.decode(tasksJson) or {}
        local changed = false
        for id, state in pairs(tasks) do
            if not state.done then
                local cfg = nil
                for _, t in ipairs(pool) do
                    if t.id == id and t.type == taskType then cfg = t; break end
                end
                if cfg then
                    state.progress = state.progress + amount
                    changed = true
                    notify(src, T('task_progress', Shared.FormatNumber(state.progress), Shared.FormatNumber(cfg.target)), 'inform', 2000)
                    if state.progress >= cfg.target then
                        state.done = true
                        GiveXP(src, data, cfg.xp)
                        GiveCoins(src, data, cfg.coins)
                        notify(src, T('task_completed', cfg.label), 'success', 5000, 'check')
                    end
                end
            end
        end
        return changed, json.encode(tasks)
    end

    local dc, newDaily  = processPool(data.daily_tasks,  Config.DailyTasks)
    local wc, newWeekly = processPool(data.weekly_tasks, Config.WeeklyTasks)
    if dc then data.daily_tasks  = newDaily  end
    if wc then data.weekly_tasks = newWeekly end
end

-- ── PLAYER JOIN / DROP ────────────────────────────────────
RegisterNetEvent('mm-christmas:server:playerJoin', function()
    local src = source

    local allowed = RateLimit.Check(src, 'playerJoin', Config.RateLimits.playerJoin)
    if not allowed then return end

    local id = Framework.GetIdentifier(src)
    if not id then
        Shared.Warn(('Kunne ikke finde identifier for spiller %s (framework: %s)'):format(src, Framework.type))
        return
    end

    local data = Database.LoadPlayer(id)
    data.identifier = id
    data.name       = Framework.GetName(src)

    if EnsureTasksReset(data) then
        Database.SavePlayer(src, data)
    end

    Players[src] = data

    -- Send nuværende delte world-state (aktive snemænd) så en spiller
    -- der joiner midt i et event ser de samme snemænd som alle andre.
    local now    = GetGameTimer()
    local active = {}
    for locIndex, expires in pairs(ActiveSnowmen) do
        if expires > now then
            active[#active + 1] = { index = locIndex, expiresIn = expires - now }
        end
    end
    TriggerClientEvent('mm-christmas:client:activeSnowmen', src, active)

    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    Shared.Debug('Player loaded:', id)
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Players[src] then
        Database.SavePlayer(src, Players[src])
        Players[src] = nil
    end
    Processing[src] = nil

    -- Ryd op i personlige gaver sendt til denne spiller, så et
    -- disconnect ikke efterlader en evigt-aktiv gave/prop.
    for giftId, gift in pairs(ActiveGifts) do
        if gift.target == src then
            ActiveGifts[giftId] = nil
            TriggerClientEvent('mm-christmas:client:removeGift', -1, giftId)
        end
    end
end)

-- ── OPEN UI ───────────────────────────────────────────────
RegisterNetEvent('mm-christmas:server:openUI', function()
    local src  = source
    local data = Players[src]
    if not data then return end

    local allowed = RateLimit.Check(src, 'openUI', Config.RateLimits.openUI)
    if not allowed then return end

    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
end)

-- ── PROFILE AVATAR ────────────────────────────────────────
RegisterNetEvent('mm-christmas:server:getProfileImage', function()
    local src = source
    if not Players[src] then return end

    local allowed = RateLimit.Check(src, 'getProfileImage', Config.RateLimits.getProfileImage)
    if not allowed then return end

    local url = Avatar.Get(src)
    TriggerClientEvent('mm-christmas:client:profileImage', src, url)
end)

-- ── DECORATE TREE ─────────────────────────────────────────
RegisterNetEvent('mm-christmas:server:decorateTree', function(treeIndex)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end

    local allowed = RateLimit.Check(src, 'decorateTree', Config.RateLimits.decorateTree)
    if not allowed then return end

    treeIndex = Shared.ToPositiveInt(treeIndex, nil)
    if not treeIndex or treeIndex < 1 or treeIndex > #Config.Trees then
        Shared.Warn(('Spiller %s sendte ugyldigt treeIndex: %s'):format(src, tostring(treeIndex)))
        return
    end

    local pos = playerPos(src)
    if not pos or Shared.Distance(pos, Config.Trees[treeIndex].coords) > Config.InteractionRadius then
        notify(src, T('too_far_away'), 'error')
        return
    end

    local done = json.decode(data.trees_done) or {}
    for _, v in ipairs(done) do
        if v == treeIndex then
            notify(src, T('tree_already_done'), 'error')
            return
        end
    end

    done[#done + 1]       = treeIndex
    data.trees_done       = json.encode(done)
    data.trees_decorated  = data.trees_decorated + 1

    GiveXP(src, data, Config.TreeRewards.xp)
    GiveCoins(src, data, Config.TreeRewards.coins)
    UpdateTask(src, data, 'trees', 1)

    notify(src, T('tree_decorated'), 'success', 4000, 'tree')

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    TriggerClientEvent('mm-christmas:client:treeDecorated', src, treeIndex)
end)

-- ── BUILD SNOWMAN ─────────────────────────────────────────
-- Server-autoritativ: en lokation er "optaget" for ALLE spillere indtil
-- den udløber, uanset hvad en enkelt clients egen lokale prop-tjek tror.
RegisterNetEvent('mm-christmas:server:buildSnowman', function(locIndex)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end

    local allowed = RateLimit.Check(src, 'buildSnowman', Config.RateLimits.buildSnowman)
    if not allowed then return end

    locIndex = Shared.ToPositiveInt(locIndex, nil)
    if not locIndex or locIndex < 1 or locIndex > #Config.SnowmanLocations then
        Shared.Warn(('Spiller %s sendte ugyldigt locIndex: %s'):format(src, tostring(locIndex)))
        return
    end

    local now = GetGameTimer()
    if ActiveSnowmen[locIndex] and ActiveSnowmen[locIndex] > now then
        notify(src, T('snowman_loc_taken'), 'error')
        return
    end

    local entry = Config.SnowmanLocations[locIndex]
    local loc   = type(entry) == 'table' and entry.coords or entry
    local pos   = playerPos(src)
    if not pos or Shared.Distance(pos, loc) > Config.InteractionRadius then
        notify(src, T('too_far_away'), 'error')
        return
    end

    ActiveSnowmen[locIndex] = now + Config.SnowmanDespawnTime

    data.snowmen_built = data.snowmen_built + 1
    GiveXP(src, data, Config.SnowmanRewards.xp)
    GiveCoins(src, data, Config.SnowmanRewards.coins)
    UpdateTask(src, data, 'snowmen', 1)

    notify(src, T('snowman_built'), 'success', 4000, 'snowflake')

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    -- Broadcast til ALLE spillere så alle ser snemanden, ikke kun bygherren.
    TriggerClientEvent('mm-christmas:client:snowmanBuilt', -1, locIndex, Config.SnowmanDespawnTime)
end)

-- ── WORLD GIFTS (findes frit, én gang pr. spiller pr. lokation) ──
RegisterNetEvent('mm-christmas:server:worldGiftFound', function(locIndex)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end
    if not Config.WorldGiftsEnabled then return end

    local allowed = RateLimit.Check(src, 'worldGift', Config.RateLimits.worldGift)
    if not allowed then return end

    locIndex = Shared.ToPositiveInt(locIndex, nil)
    if not locIndex or locIndex < 1 or locIndex > #Config.GiftLocations then
        Shared.Warn(('Spiller %s sendte ugyldigt world gift locIndex: %s'):format(src, tostring(locIndex)))
        return
    end

    local pos = playerPos(src)
    if not pos or Shared.Distance(pos, Config.GiftLocations[locIndex]) > Config.InteractionRadius then
        notify(src, T('too_far_away'), 'error')
        return
    end

    local found = json.decode(data.world_gifts_found or '[]') or {}
    for _, v in ipairs(found) do
        if v == locIndex then
            notify(src, T('gift_already_taken'), 'error')
            return
        end
    end

    found[#found + 1]        = locIndex
    data.world_gifts_found   = json.encode(found)
    data.gifts_found         = data.gifts_found + 1

    GiveXP(src, data, Config.WorldGiftRewards.xp)
    GiveCoins(src, data, Config.WorldGiftRewards.coins)
    UpdateTask(src, data, 'gifts', 1)

    notify(src, T('gift_found'), 'success', 4000, 'gift')

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
end)

-- ── PERSONLIG GAVE FUNDET ─────────────────────────────────
RegisterNetEvent('mm-christmas:server:giftFound', function(giftId)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end

    local allowed = RateLimit.Check(src, 'giftFound', Config.RateLimits.giftFound)
    if not allowed then return end

    if type(giftId) ~= 'string' then return end

    local gift = ActiveGifts[giftId]
    if not gift or gift.target ~= src then
        notify(src, T('gift_already_taken'), 'error')
        return
    end

    ActiveGifts[giftId]  = nil
    data.personal_gifts  = data.personal_gifts + 1
    data.gifts_found      = data.gifts_found + 1

    GiveXP(src, data, Config.PersonalGiftRewards.xp)
    GiveCoins(src, data, Config.PersonalGiftRewards.coins)
    if Config.PersonalGiftRewards.items then
        for _, itm in ipairs(Config.PersonalGiftRewards.items) do
            Inventory.GiveItem(src, itm.item, itm.amount)
        end
    end

    UpdateTask(src, data, 'gifts', 1)

    notify(src, T('gift_found'), 'success', 4000, 'gift')

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    TriggerClientEvent('mm-christmas:client:removeGift', -1, giftId)
end)

-- ── DISTANCE TRACKING ─────────────────────────────────────
-- Klienten rapporterer akkumulerede deltaer hvert Config.Distance.ReportInterval
-- ms. Alt over den fysisk plausible grænse pr. rapport klippes ned i
-- stedet for at blive godtaget råt.
RegisterNetEvent('mm-christmas:server:trackDistance', function(driven, run)
    local src  = source
    local data = Players[src]
    if not data then return end

    local allowed = RateLimit.Check(src, 'trackDistance', Config.RateLimits.trackDistance)
    if not allowed then return end

    driven = Shared.Clamp(driven, 0, Config.Distance.MaxDrivenPerReport)
    run    = Shared.Clamp(run,    0, Config.Distance.MaxRunPerReport)

    if driven <= 0 and run <= 0 then return end

    data.distance_driven = data.distance_driven + driven
    data.distance_run    = data.distance_run    + run

    if driven > 0 then UpdateTask(src, data, 'drive', driven) end
    if run    > 0 then UpdateTask(src, data, 'run',   run)    end

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
end)

-- ── SHOP PURCHASE (atomisk, server-authoritative) ─────────
RegisterNetEvent('mm-christmas:server:shopBuy', function(shopItemId)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end
    if Processing[src] then return end

    local allowed = RateLimit.Check(src, 'shopBuy', Config.RateLimits.shopBuy)
    if not allowed then return end

    if type(shopItemId) ~= 'string' then return end

    local item = nil
    for _, s in ipairs(Config.ShopItems) do
        if s.id == shopItemId then item = s; break end
    end
    if not item then
        Shared.Warn(('Spiller %s prøvede at købe en ukendt shop-vare "%s".'):format(src, tostring(shopItemId)))
        return
    end

    Processing[src] = true

    local ok, err = pcall(function()
        local purchases = json.decode(data.shop_purchases) or {}
        local count      = purchases[item.id] or 0

        if count >= item.limit then
            notify(src, T('shop_limit'), 'error', 3000)
            return
        end

        if not Currency.Has(src, item.price) then
            notify(src, T('not_enough_coins'), 'error', 3000)
            return
        end

        local removed = Currency.Remove(src, item.price)
        if not removed then
            notify(src, T('not_enough_coins'), 'error', 3000)
            return
        end

        local given = Inventory.GiveItem(src, item.item, item.amount or 1)
        if not given then
            -- Rul betalingen tilbage — spilleren må ALDRIG betale uden varen.
            Currency.Add(src, item.price)
            Shared.Warn(('Kunne ikke give shop-vare "%s" til spiller %s - coins refunderet.'):format(item.item, src))
            notify(src, T('shop_give_failed'), 'error', 4000)
            return
        end

        purchases[item.id]  = count + 1
        data.shop_purchases = json.encode(purchases)

        notify(src, T('shop_bought', item.label), 'success', 4000, 'shopping-cart')

        Database.SavePlayer(src, data)
        TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    end)

    if not ok then
        Shared.Warn(('Uventet fejl i shopBuy for spiller %s: %s'):format(src, tostring(err)))
    end

    Processing[src] = nil
end)

-- ── CHRISTMAS BOX (server-authoritative) ──────────────────
RegisterNetEvent('mm-christmas:server:openBox', function()
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end
    if Processing[src] then return end

    local allowed = RateLimit.Check(src, 'openBox', Config.RateLimits.openBox)
    if not allowed then return end

    Processing[src] = true

    local ok, err = pcall(function()
        local removed = Inventory.RemoveItem(src, Config.ChristmasBoxItem, 1)
        if not removed then
            notify(src, T('no_box'), 'error', 3000)
            return
        end

        local reward = Shared.RollChristmasBox()
        local success = true

        if reward.type == 'coins' then
            GiveCoins(src, data, reward.amount)
            notify(src, T('box_reward_coins', Shared.FormatNumber(reward.amount)), 'success', 5000, 'coins')
        elseif reward.type == 'xp' then
            GiveXP(src, data, reward.amount)
            notify(src, T('box_reward_xp', Shared.FormatNumber(reward.amount)), 'success', 5000, 'star')
        elseif reward.type == 'item' then
            success = Inventory.GiveItem(src, reward.item, reward.amount or 1)
            if success then
                notify(src, T('box_reward_item', reward.item, reward.amount or 1), 'success', 5000, 'gift')
            end
        end

        if not success then
            -- Item-reward kunne ikke gives — refunder boxen i stedet for
            -- at spilleren mister den uden at få noget som helst.
            Inventory.GiveItem(src, Config.ChristmasBoxItem, 1)
            Shared.Warn(('Kunne ikke give box-reward item "%s" til spiller %s - box refunderet.'):format(tostring(reward.item), src))
            notify(src, T('box_reward_failed'), 'error', 4000)
            return
        end

        notify(src, T('box_opened'), 'inform', 3000)

        Database.SavePlayer(src, data)
        TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
    end)

    if not ok then
        Shared.Warn(('Uventet fejl i openBox for spiller %s: %s'):format(src, tostring(err)))
    end

    Processing[src] = nil
end)

-- ── CLAIM LEVEL REWARD ─────────────────────────────────────
RegisterNetEvent('mm-christmas:server:claimLevelReward', function(level)
    local src  = source
    local data = Players[src]
    if not data then return end
    if not Shared.IsEventActive() then return end

    local allowed = RateLimit.Check(src, 'claimLevelReward', Config.RateLimits.claimLevelReward)
    if not allowed then return end

    level = Shared.ToPositiveInt(level, nil)
    if not level then return end

    if data.level < level then
        notify(src, T('level_not_reached', level), 'error', 3000)
        return
    end

    local claimed = json.decode(data.claimed_rewards or '[]') or {}
    for _, v in ipairs(claimed) do
        if v == level then
            notify(src, T('level_already_claimed', level), 'error', 3000)
            return
        end
    end

    local reward = Config.LevelRewards[level]
    if not reward then
        notify(src, T('no_level_reward'), 'error', 3000)
        return
    end

    if reward.coins and reward.coins > 0 then
        GiveCoins(src, data, reward.coins)
    end
    if reward.item then
        Inventory.GiveItem(src, reward.item, reward.amount or 1)
    end

    claimed[#claimed + 1] = level
    data.claimed_rewards  = json.encode(claimed)

    local rewardMsg = ''
    if reward.coins then rewardMsg = rewardMsg .. '🪙 ' .. Shared.FormatNumber(reward.coins) .. ' ' .. T('ui_coins') end
    if reward.item  then rewardMsg = rewardMsg .. (rewardMsg ~= '' and ' + ' or '') .. '🎁 ' .. reward.item .. ' x' .. (reward.amount or 1) end

    notify(src, T('level_reward_claimed', level), 'success', 6000, 'gift', rewardMsg)

    Database.SavePlayer(src, data)
    TriggerClientEvent('mm-christmas:client:syncData', src, Database.BuildClientData(src, data))
end)

-- ── LEADERBOARD ────────────────────────────────────────────
local LeaderboardCache        = {}
local LastLeaderboardRefresh  = 0

local function RefreshLeaderboard()
    local now = GetGameTimer()
    if now - LastLeaderboardRefresh < Config.LeaderboardRefresh then
        return LeaderboardCache
    end
    LastLeaderboardRefresh = now

    local ok, rows = pcall(function()
        return MySQL.query.await(
            'SELECT name, level, xp, trees_decorated, snowmen_built, gifts_found, coins FROM mm_christmas_players ORDER BY level DESC, xp DESC LIMIT ?',
            { Config.LeaderboardSize * 2 }
        )
    end)
    if not ok or not rows then return LeaderboardCache end

    local function sortedTop(field)
        local copy = {}
        for _, r in ipairs(rows) do copy[#copy + 1] = r end
        table.sort(copy, function(a, b) return (a[field] or 0) > (b[field] or 0) end)
        local out = {}
        for i = 1, math.min(Config.LeaderboardSize, #copy) do
            out[#out + 1] = { name = copy[i].name, value = copy[i][field] or 0 }
        end
        return out
    end

    LeaderboardCache = {
        level   = sortedTop('level'),
        xp      = sortedTop('xp'),
        trees   = sortedTop('trees_decorated'),
        snowmen = sortedTop('snowmen_built'),
        gifts   = sortedTop('gifts_found'),
        coins   = sortedTop('coins'),
    }

    return LeaderboardCache
end

RegisterNetEvent('mm-christmas:server:getLeaderboard', function()
    local src = source
    if not Players[src] then return end

    local allowed = RateLimit.Check(src, 'getLeaderboard', Config.RateLimits.getLeaderboard)
    if not allowed then return end

    TriggerClientEvent('mm-christmas:client:leaderboardData', src, RefreshLeaderboard())
end)

-- ── ADMIN GIFT COMMAND ─────────────────────────────────────
RegisterCommand(Config.PersonalGiftCommand, function(src, args)
    if src == 0 then return end -- kun spillere, ikke konsollen

    if not Framework.IsAdmin(src) then
        notify(src, T('not_admin'), 'error', 3000)
        return
    end

    local targetId = Shared.ToPositiveInt(args[1], nil)
    if not targetId or GetPlayerName(targetId) == nil then
        notify(src, ('Usage: /%s [id]'):format(Config.PersonalGiftCommand), 'error', 3000)
        return
    end

    local targetData = Players[targetId]
    if not targetData then
        notify(src, T('player_not_found'), 'error', 3000)
        return
    end

    local locIndex = math.random(1, #Config.GiftLocations)
    local loc       = Config.GiftLocations[locIndex]

    giftCounter = giftCounter + 1
    local giftId = 'gift_' .. giftCounter

    ActiveGifts[giftId] = { target = targetId, expires = GetGameTimer() + Config.PersonalGiftExpiry }

    TriggerClientEvent('mm-christmas:client:spawnPersonalGift', targetId, {
        id     = giftId,
        coords = { x = loc.x, y = loc.y, z = loc.z },
    })

    notify(src, T('admin_gift_sent', Framework.GetName(targetId)), 'success', 4000)
end, false)

-- ── PERIODIC CLEANUP / SAVE ────────────────────────────────
-- Bevidst langt interval (ikke en busy loop) - kun til periodisk
-- persistens og udløb af midlertidig world-state.
CreateThread(function()
    while true do
        Wait(300000) -- 5 minutter
        for src, data in pairs(Players) do
            Database.SavePlayer(src, data)
        end
        Shared.Debug('Auto-saved all players')
    end
end)

CreateThread(function()
    while true do
        Wait(60000) -- 1 minut
        local now = GetGameTimer()
        for giftId, gift in pairs(ActiveGifts) do
            if gift.expires <= now then
                ActiveGifts[giftId] = nil
                TriggerClientEvent('mm-christmas:client:removeGift', -1, giftId)
            end
        end
    end
end)

-- ── DATABASE MIGRATION VED OPSTART ────────────────────────
CreateThread(function()
    Database.RunMigrations()
end)
