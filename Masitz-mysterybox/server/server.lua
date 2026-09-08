-- ============================================================
--  Masitz-mysterybox | server/server.lua
--
--  Serveren stoler ALDRIG på clienten. Box-type, item, slot, amount
--  og reward slås altid op/valideres server-side mod Config.MysteryBox.
--  Der er INGEN hardcodede box-typer ("legal"/"illegal" osv.) i denne
--  fil - alt afgøres af hvad der faktisk findes i config.lua, så nye
--  boxes kan tilføjes uden at ændre noget herinde.
-- ============================================================

local ox_inventory = exports.ox_inventory
local M = Config.MysteryBox

local function debugPrint(fmt, ...)
    if not M.Debug then return end
    print(('^3[Masitz-MysteryBox]^0 ' .. fmt):format(...))
end

local function warnPrint(fmt, ...)
    print(('^1[Masitz-MysteryBox]^0 ' .. fmt):format(...))
end

local function notify(src, title, description, notifyType)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title,
        description = description,
        type = notifyType,
        position = (M.Notifications and M.Notifications.position) or 'center-right',
    })
end

-- ================================
-- Reward amount: fast tal ELLER { min = x, max = y } (variable amounts).
-- Altid et heltal >= 1.
-- ================================
local function resolveAmount(amount)
    if type(amount) == 'table' then
        local min = math.floor(tonumber(amount.min) or 1)
        local max = math.floor(tonumber(amount.max) or min)

        if min < 1 then min = 1 end
        if max < min then max = min end

        return math.random(min, max)
    end

    amount = math.floor(tonumber(amount) or 1)
    if amount < 1 then amount = 1 end

    return amount
end

-- ============================================================
--  GENERISK REWARD ENGINE
--  Ny reward-type tilføjes ved blot at tilføje en handler herunder -
--  intet andet i scriptet skal ændres.
-- ============================================================
local RewardHandlers = {}

RewardHandlers['item'] = function(src, reward)
    if type(reward.name) ~= 'string' or reward.name == '' then
        warnPrint('Reward af type "item" mangler et gyldigt "name" felt.')
        return false
    end

    local amount = resolveAmount(reward.amount)
    local metadata = reward.metadata

    if type(metadata) == 'function' then
        metadata = metadata(src)
    end

    return ox_inventory:AddItem(src, reward.name, amount, metadata) and true or false
end

RewardHandlers['money'] = function(src, reward)
    local itemName = reward.name or M.MoneyItem or 'money'
    local amount = resolveAmount(reward.amount)

    return ox_inventory:AddItem(src, itemName, amount) and true or false
end

RewardHandlers['vehicle_ticket'] = function(src, reward)
    local ticketCfg = M.VehicleTicket or {}
    local pool = reward.vehicles or ticketCfg.vehicles

    if type(pool) ~= 'table' or #pool == 0 then
        warnPrint('Reward af type "vehicle_ticket" har ingen vehicle pool konfigureret.')
        return false
    end

    local item = reward.item or ticketCfg.item

    if type(item) ~= 'string' or item == '' then
        warnPrint('Reward af type "vehicle_ticket" mangler et gyldigt ticket item.')
        return false
    end

    local model = pool[math.random(#pool)]
    local prefix = reward.prefix or ticketCfg.prefix or ''
    local ticketId = ('%s%d'):format(prefix, math.random(100000, 999999))

    return ox_inventory:AddItem(src, item, 1, {
        model = model,
        ticketId = ticketId,
    }) and true or false
end

local function giveReward(src, reward)
    if type(reward) ~= 'table' or type(reward.type) ~= 'string' then
        return false
    end

    local handler = RewardHandlers[reward.type]

    if not handler then
        warnPrint('Ukendt reward type "%s".', tostring(reward.type))
        return false
    end

    local ok, result = pcall(handler, src, reward)

    if not ok then
        warnPrint('Fejl i reward handler ("%s"): %s', reward.type, tostring(result))
        return false
    end

    return result == true
end

-- ============================================================
--  CHANCE SYSTEM
--  rewards       -> weighted: der vælges altid præcis 1 fra listen,
--                   chance = relativ vægt (behøver ikke summere til 100).
--  bonusRewards  -> independent chance: hver reward rangeres for sig,
--                   0-100 (decimaler tilladt), 0+ kan udløses samtidig.
--  Se config.lua for den fulde forklaring.
-- ============================================================
local function selectWeightedReward(pool, contextLabel)
    if type(pool) ~= 'table' or #pool == 0 then
        warnPrint('Ingen rewards konfigureret for "%s".', contextLabel or '?')
        return nil
    end

    local total = 0

    for _, reward in ipairs(pool) do
        total = total + (tonumber(reward.chance) or 0)
    end

    if total <= 0 then
        warnPrint('Alle chance-værdier er 0 for "%s" - falder tilbage til tilfældigt valg.', contextLabel or '?')
        return pool[math.random(#pool)]
    end

    local roll = math.random() * total
    local cumulative = 0

    for _, reward in ipairs(pool) do
        cumulative = cumulative + (tonumber(reward.chance) or 0)

        if roll <= cumulative then
            return reward
        end
    end

    return pool[#pool]
end

local function rollBonusRewards(pool)
    local won = {}

    if type(pool) ~= 'table' then return won end

    for _, reward in ipairs(pool) do
        local chance = tonumber(reward.chance) or 0

        if chance > 0 and (math.random() * 100) <= chance then
            won[#won + 1] = reward
        end
    end

    return won
end

-- ============================================================
--  ANTI-SPAM / DUPLICATION PROTECTION
--  Én mystery box-handling ad gangen pr. spiller. Forhindrer at
--  samme event spammes/replayes og at flere åbninger/konverteringer
--  kører samtidigt på samme spiller (race conditions / duplication).
-- ============================================================
local processing = {}

AddEventHandler('playerDropped', function()
    processing[source] = nil
end)

-- ============================================================
--  ÅBN MYSTERY BOX
--  Fuldstændig config-drevet: boxKey slås op i Config.MysteryBox.Boxes.
--  Ukendte box-typer afvises. Rewarden vælges og valideres server-side
--  - clienten kan aldrig vælge sin egen reward.
--
--  Flow: verify box -> verify slot -> remove box -> select reward ->
--  give reward. Hvis item-removal fejler, gives INGEN reward. Hvis
--  reward-udbetalingen fejler EFTER boxen er fjernet, refunderes
--  boxen til spilleren i stedet for at de mister den uden modydelse.
-- ============================================================
local function openMysteryBox(src, boxKey, slot)
    if processing[src] then return end
    if type(boxKey) ~= 'string' then return end

    local box = M.Boxes[boxKey]

    if not box then
        warnPrint('Spiller %s prøvede at åbne en ukendt box type "%s".', src, tostring(boxKey))
        return
    end

    slot = tonumber(slot)

    if not slot then
        notify(src, 'Mystery Box', 'Ugyldig slot.', 'error')
        return
    end

    processing[src] = true

    local ok, err = pcall(function()
        local slotData = ox_inventory:GetSlot(src, slot)

        if not slotData or slotData.name ~= box.item then
            notify(src, 'Mystery Box', 'Du har ikke denne mystery box i den valgte slot.', 'error')
            return
        end

        local removed = ox_inventory:RemoveItem(src, box.item, 1, slot)

        if not removed then
            notify(src, 'Mystery Box', 'Kunne ikke fjerne mystery boxen fra din inventory.', 'error')
            return
        end

        local reward = selectWeightedReward(box.rewards, boxKey)

        if not reward then
            ox_inventory:AddItem(src, box.item, 1)
            notify(src, 'Mystery Box', 'Der opstod en fejl. Din box er blevet refunderet.', 'error')
            return
        end

        local success = giveReward(src, reward)

        if not success then
            ox_inventory:AddItem(src, box.item, 1)
            warnPrint('Kunne ikke give reward til spiller %s ("%s") - box refunderet.', src, boxKey)
            notify(src, 'Mystery Box', 'Der opstod en fejl med din belønning. Din box er blevet refunderet.', 'error')
            return
        end

        debugPrint('Spiller %s åbnede "%s" og fik reward type "%s" (%s).', src, boxKey, reward.type, reward.name or 'n/a')

        notify(src, box.label or 'Mystery Box', 'Du modtog din belønning!', 'success')

        local bonuses = rollBonusRewards(box.bonusRewards)

        for _, bonus in ipairs(bonuses) do
            if giveReward(src, bonus) then
                debugPrint('Spiller %s fik bonus reward type "%s" fra "%s".', src, bonus.type, boxKey)
                notify(src, box.label or 'Mystery Box', 'Du fik også en bonus belønning!', 'success')
            else
                warnPrint('Bonus reward af type "%s" fejlede for spiller %s ("%s").', bonus.type, src, boxKey)
            end
        end
    end)

    if not ok then
        warnPrint('Uventet fejl ved åbning af mystery box for spiller %s: %s', src, tostring(err))
    end

    processing[src] = nil
end

RegisterNetEvent('Masitz-MysteryBox:openBox', function(boxKey, slot)
    openMysteryBox(source, boxKey, slot)
end)

-- ============================================================
--  KONVERTER MYSTERYBOX
--  targetKey slås op i Config.MysteryBox.Conversion.targets - ingen
--  hardcodede box-typer. Amount valideres 100% server-side: heltal,
--  minimum 1, og spilleren kan aldrig konvertere flere end de rent
--  faktisk ejer (serveren stoler ALDRIG på clientens amount).
-- ============================================================
local function convertMysteryBox(src, targetKey, amount)
    local conversion = M.Conversion

    if not conversion or not conversion.enabled then return end
    if processing[src] then return end
    if type(targetKey) ~= 'string' then return end

    local targetItem = conversion.targets and conversion.targets[targetKey]

    if not targetItem then
        warnPrint('Spiller %s prøvede at konvertere til en ukendt type "%s".', src, tostring(targetKey))
        return
    end

    amount = tonumber(amount)

    if not amount or amount ~= math.floor(amount) or amount < 1 then
        notify(src, 'Mystery Box', 'Ugyldigt antal.', 'error')
        return
    end

    amount = math.floor(amount)
    processing[src] = true

    local ok, err = pcall(function()
        local sourceItem = conversion.sourceItem
        local owned = ox_inventory:GetItemCount(src, sourceItem)

        if not owned or owned < amount then
            notify(src, 'Mystery Box', 'Du har ikke nok mysteryboxe.', 'error')
            return
        end

        local removed = ox_inventory:RemoveItem(src, sourceItem, amount)

        if not removed then
            notify(src, 'Mystery Box', 'Kunne ikke fjerne mysteryboxe.', 'error')
            return
        end

        local given = ox_inventory:AddItem(src, targetItem, amount)

        if not given then
            ox_inventory:AddItem(src, sourceItem, amount)
            warnPrint('Kunne ikke give konverteret item til spiller %s - refunderet.', src)
            notify(src, 'Mystery Box', 'Der opstod en fejl. Dine mysteryboxe er blevet refunderet.', 'error')
            return
        end

        debugPrint('Spiller %s konverterede %dx "%s" til "%s".', src, amount, sourceItem, targetItem)

        notify(src, 'Mystery Box', ('Konverterede %dx mystery box.'):format(amount), 'success')
    end)

    if not ok then
        warnPrint('Uventet fejl ved konvertering for spiller %s: %s', src, tostring(err))
    end

    processing[src] = nil
end

RegisterNetEvent('Masitz-MysteryBox:convertBox', function(targetKey, amount)
    convertMysteryBox(source, targetKey, amount)
end)

-- ============================================================
--  CONFIG VALIDATION VED RESOURCE START
--  Fejl/advarsler printes ALTID (så en fejlkonfigureret box aldrig
--  fejler stille/tilfældigt) - info-linjer ("Loaded X boxes...") vises
--  kun når Config.MysteryBox.Debug = true.
-- ============================================================
local function validateConfig()
    local boxCount, rewardCount, errorCount = 0, 0, 0

    if type(M) ~= 'table' then
        warnPrint('Config.MysteryBox mangler eller er ugyldig - resourcen kan ikke fungere korrekt.')
        return
    end

    if type(M.Boxes) ~= 'table' or not next(M.Boxes) then
        warnPrint('Ingen mystery boxes konfigureret (Config.MysteryBox.Boxes er tom).')
        errorCount = errorCount + 1
    else
        for key, box in pairs(M.Boxes) do
            boxCount = boxCount + 1

            if type(box.item) ~= 'string' or box.item == '' then
                warnPrint('Box "%s" mangler et gyldigt item navn.', key)
                errorCount = errorCount + 1
            end

            if type(box.rewards) ~= 'table' or #box.rewards == 0 then
                warnPrint('Box "%s" har ingen rewards konfigureret.', key)
                errorCount = errorCount + 1
            else
                for i, reward in ipairs(box.rewards) do
                    rewardCount = rewardCount + 1

                    if not RewardHandlers[reward.type] then
                        warnPrint('Box "%s" reward #%d har ukendt type "%s".', key, i, tostring(reward.type))
                        errorCount = errorCount + 1
                    end
                end
            end

            if type(box.bonusRewards) == 'table' then
                for i, reward in ipairs(box.bonusRewards) do
                    rewardCount = rewardCount + 1

                    if not RewardHandlers[reward.type] then
                        warnPrint('Box "%s" bonusReward #%d har ukendt type "%s".', key, i, tostring(reward.type))
                        errorCount = errorCount + 1
                    elseif reward.type == 'vehicle_ticket' then
                        local pool = reward.vehicles or (M.VehicleTicket and M.VehicleTicket.vehicles)

                        if type(pool) ~= 'table' or #pool == 0 then
                            warnPrint('Box "%s" bonusReward #%d (vehicle_ticket) har ingen vehicle pool.', key, i)
                            errorCount = errorCount + 1
                        end
                    end
                end
            end
        end
    end

    if M.Conversion and M.Conversion.enabled then
        if type(M.Conversion.sourceItem) ~= 'string' or M.Conversion.sourceItem == '' then
            warnPrint('Config.MysteryBox.Conversion.sourceItem er ugyldig.')
            errorCount = errorCount + 1
        end

        if type(M.Conversion.targets) ~= 'table' or not next(M.Conversion.targets) then
            warnPrint('Config.MysteryBox.Conversion.targets er tom.')
            errorCount = errorCount + 1
        else
            for targetKey, targetItem in pairs(M.Conversion.targets) do
                if not M.Boxes or not M.Boxes[targetKey] then
                    warnPrint('Conversion target "%s" matcher ingen konfigureret box.', targetKey)
                end

                if type(targetItem) ~= 'string' or targetItem == '' then
                    warnPrint('Conversion target "%s" har et ugyldigt item navn.', targetKey)
                    errorCount = errorCount + 1
                end
            end
        end
    end

    if M.Debug then
        print(('^2[Masitz-MysteryBox]^0 Loaded %d mystery boxes.'):format(boxCount))
        print(('^2[Masitz-MysteryBox]^0 Loaded %d rewards.'):format(rewardCount))

        if errorCount > 0 then
            print(('^1[Masitz-MysteryBox]^0 Validation fandt %d fejl - se ovenstående.'):format(errorCount))
        end
    end
end

CreateThread(function()
    math.randomseed(GetGameTimer() + os.time())
    validateConfig()
end)
