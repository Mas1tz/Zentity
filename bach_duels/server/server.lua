-- ============================================================================
-- bach_duels — server.lua
--
-- Denne fil er den ENESTE tilføjede fil. client/*, html/css/js, fxmanifest.lua,
-- shared/*.lua er UÆNDREDE og betragtes som facit. Alle eventnavne, callback-
-- navne og dataformater herunder er valgt for at matche den eksisterende,
-- uændrede client nøjagtigt (verificeret ved at læse alle client-filer).
--
-- Serveren er eneste autoritet over: duel-state, hold, runder, score, vinder,
-- våben, spectate-adgang, stats og bans. Klienten sender kun ønsker/identifi-
-- katorer — serveren validerer alt før noget udføres eller broadcastes.
-- ============================================================================

local CreateConfig = lib.load('shared.create')
local WeaponsConfig = lib.load('shared.weapons')

-- ----------------------------------------------------------------------------
-- Opsætning af database (ingen eksisterende schema fandtes i resourcen — der
-- er derfor INTET eksisterende schema at ændre. Tabellerne oprettes selv,
-- idempotent, med feltnavne der matcher nøjagtigt det klienten allerede læser:
-- banmenu.lua forventer player_name/player_id/reason/banned_by/banned_at,
-- leaderboard.lua forventer wins/losses/headshots/score/name).
-- ----------------------------------------------------------------------------

MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS `bach_duels_stats` (
        `identifier` VARCHAR(64) NOT NULL,
        `name` VARCHAR(100) NOT NULL DEFAULT '',
        `wins` INT UNSIGNED NOT NULL DEFAULT 0,
        `losses` INT UNSIGNED NOT NULL DEFAULT 0,
        `headshots` INT UNSIGNED NOT NULL DEFAULT 0,
        `score` INT NOT NULL DEFAULT 0,
        PRIMARY KEY (`identifier`)
    )
]])

MySQL.query.await([[
    CREATE TABLE IF NOT EXISTS `bach_duels_bans` (
        `player_id` VARCHAR(64) NOT NULL,
        `player_name` VARCHAR(100) NOT NULL DEFAULT '',
        `reason` VARCHAR(255) NOT NULL DEFAULT 'Ingen årsag angivet',
        `banned_by` VARCHAR(100) NOT NULL DEFAULT '',
        `banned_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (`player_id`)
    )
]])

-- ----------------------------------------------------------------------------
-- In-memory state
-- ----------------------------------------------------------------------------

local Duels = {}                -- [id] = duel table (se NewDuel())
local NextDuelId = 1

local Dummies = {}               -- [fakeId] = { name = str, duelId = id, team = "blue"/"red" }
local NextDummyId = -1           -- negative id-space, kan aldrig kollidere med rigtige server-ids

local PendingSpectateRequests = {} -- [targetServerId] = { requesterId, duelId, team, expireAt }
local RecentDuelResults = {}     -- [duelId] = { winningTeam, teamA, teamB, blueScore, redScore, expireAt }
local PlayerLastDuel = {}        -- [source] = { duelId = id, expireAt = ms }
local IssuedItems = {}           -- [source] = { [itemName] = totalCount }
local Cooldowns = {}             -- [source.."|"..key] = gameTimerMs

local BotNames = {
    "Bot_Anders", "Bot_Bent", "Bot_Carl", "Bot_David", "Bot_Erik",
    "Bot_Frank", "Bot_Gert", "Bot_Hans", "Bot_Ivan", "Bot_Jens",
}

-- ----------------------------------------------------------------------------
-- Generelle hjælpefunktioner
-- ----------------------------------------------------------------------------

local function Throttled(source, key, ms)
    local cacheKey = tostring(source) .. "|" .. key
    local now = GetGameTimer()
    local last = Cooldowns[cacheKey]
    if last and (now - last) < ms then
        return true
    end
    Cooldowns[cacheKey] = now
    return false
end

local function GetIdentifier(source)
    local id = GetPlayerIdentifierByType(source, 'license')
    if not id then
        id = GetPlayerIdentifierByType(source, 'license2')
    end
    if not id then
        id = GetPlayerIdentifierByType(source, 'fivem')
    end
    if not id then
        -- Sidste udvej: stabil pseudo-identifikator ud fra alle identifiers.
        local n = GetNumPlayerIdentifiers(source)
        for i = 0, n - 1 do
            local ident = GetPlayerIdentifier(source, i)
            if ident then
                id = ident
                break
            end
        end
    end
    return id or ("unknown:" .. tostring(source))
end

local function IsDummy(id)
    return Dummies[id] ~= nil
end

local function GetPlayerNameSafe(id)
    if IsDummy(id) then
        return Dummies[id].name
    end
    local ok, name = pcall(GetPlayerName, id)
    if ok and name and name ~= "" then
        return name
    end
    return nil
end

local function IsSourceOnline(id)
    if IsDummy(id) then
        return true
    end
    return GetPlayerName(id) ~= nil
end

-- Flad opslagstabel over alle gyldige våben-id'er, bygget ud fra shared/weapons.lua.
local AllWeaponIds = {}
if WeaponsConfig and WeaponsConfig.Weapons then
    for class, list in pairs(WeaponsConfig.Weapons) do
        for _, weapon in ipairs(list) do
            AllWeaponIds[weapon.id] = class
        end
    end
end

local function IsValidWeapon(weaponId, class)
    local actualClass = AllWeaponIds[weaponId]
    if not actualClass then
        return false
    end
    if class and actualClass ~= class then
        return false
    end
    return true
end

local function GetMapById(mapId)
    if not CreateConfig or not CreateConfig.maps or not CreateConfig.maps.defaults then
        return nil
    end
    for _, map in ipairs(CreateConfig.maps.defaults) do
        if map.id == mapId and not map.hiddenFromDuel then
            return map
        end
    end
    return nil
end

local function IsBanned(identifier)
    local row = MySQL.scalar.await("SELECT 1 FROM bach_duels_bans WHERE player_id = ?", { identifier })
    return row ~= nil
end

local function IsAdmin(source)
    return IsPlayerAceAllowed(source, "bach_duels.admin")
end

local function DenyAdmin(source)
    TriggerClientEvent("bach_duels:notifyPlayer", source, "Adgang nægtet",
        "Du har ikke tilladelse til dette.", "error")
end

-- ----------------------------------------------------------------------------
-- Duel data-model
-- ----------------------------------------------------------------------------

-- team A = blue, team B = red (bekræftet ved klientens brug: Hopouts sætter
-- spawn fra teamAStartCoords når team=="blue" og teamBStartCoords når "red").

local function NewDuel(source, duelData, isDebug, dummyCount)
    local map = GetMapById(duelData.map)
    if not map then
        return nil, "Dette map kan ikke bruges i duels"
    end

    local weaponMode = duelData.weaponMode == "multiple" and "multiple" or "single"
    local weaponClass, weapon, selectedWeapons

    if weaponMode == "single" then
        weapon = duelData.weapon
        weaponClass = duelData.weaponClass
        if not weapon or not IsValidWeapon(weapon, weaponClass) then
            return nil, "Ugyldigt våben valgt"
        end
    else
        selectedWeapons = {}
        if type(duelData.selectedWeapons) == "table" then
            for _, w in ipairs(duelData.selectedWeapons) do
                if IsValidWeapon(w) then
                    selectedWeapons[#selectedWeapons + 1] = w
                end
            end
        end
        if #selectedWeapons == 0 then
            return nil, "Ingen gyldige våben valgt"
        end
        weaponClass = duelData.weaponClass
    end

    local rounds = tonumber(duelData.rounds) or CreateConfig.rounds.default
    local validRoundOption = false
    for _, opt in ipairs(CreateConfig.rounds.options) do
        if opt == rounds then
            validRoundOption = true
            break
        end
    end
    if not validRoundOption then
        rounds = CreateConfig.rounds.default
    end

    local vestUses = tonumber(duelData.vestUses) or CreateConfig.vestUses.default
    if vestUses < CreateConfig.vestUses.min or vestUses > CreateConfig.vestUses.max then
        vestUses = CreateConfig.vestUses.default
    end

    local maxSize = CreateConfig.teams.maxSize
    local teamASize = tonumber(duelData.teamASize) or CreateConfig.teams.defaultSize
    local teamBSize = tonumber(duelData.teamBSize) or CreateConfig.teams.defaultSize
    local isAsymmetric = CreateConfig.teams.allowAsymmetric and duelData.isAsymmetric == true or false

    teamASize = math.max(1, math.min(maxSize, math.floor(teamASize)))
    teamBSize = math.max(1, math.min(maxSize, math.floor(teamBSize)))
    if not isAsymmetric then
        teamBSize = teamASize
    end

    local isPrivate = duelData.isPrivate == true and CreateConfig.privacy.allowPrivateGames
    local privateCode = nil
    if isPrivate then
        local code = duelData.privateCode
        if type(code) ~= "string" or #code ~= CreateConfig.privacy.codeLength then
            return nil, "Ugyldig Private Code"
        end
        privateCode = code:upper()
    end

    local id = NextDuelId
    NextDuelId = NextDuelId + 1

    local duel = {
        id = id,
        creator = source,
        host = source,
        hostName = GetPlayerNameSafe(source) or ("Player " .. tostring(source)),
        map = map.id,
        weaponMode = weaponMode,
        weaponClass = weaponClass,
        weapon = weapon,
        selectedWeapons = selectedWeapons,
        vestUses = vestUses,
        isPrivate = isPrivate,
        privateCode = privateCode,
        rounds = rounds,
        teamASize = teamASize,
        teamBSize = teamBSize,
        isAsymmetric = isAsymmetric,
        gameMode = "onfoot",
        debugMode = isDebug == true,
        status = "waiting",
        teamA = { source },
        teamB = {},
        roundStats = { current = 1, blue = 0, red = 0 },
        roundDead = {},
        spectators = {},
        routingBucket = nil,
        vehicles = {},
        pendingVote = nil,
        createdAt = os.time(),
    }

    duel.teamAStartCoords = map.teamAStartCoords
    duel.teamBStartCoords = map.teamBStartCoords

    if isDebug then
        local count = math.max(0, math.min(tonumber(dummyCount) or 0, (teamASize + teamBSize) - 1))
        for i = 1, count do
            local dummyId = NextDummyId
            NextDummyId = NextDummyId - 1
            local name = BotNames[((i - 1) % #BotNames) + 1] .. "_" .. tostring(-dummyId)
            Dummies[dummyId] = { name = name, duelId = id }
            if #duel.teamA < teamASize then
                duel.teamA[#duel.teamA + 1] = dummyId
            elseif #duel.teamB < teamBSize then
                duel.teamB[#duel.teamB + 1] = dummyId
            end
        end
    end

    Duels[id] = duel
    return duel
end

local function FindDuelByParticipant(source)
    for id, duel in pairs(Duels) do
        for _, pid in ipairs(duel.teamA) do
            if pid == source then
                return duel, "blue"
            end
        end
        for _, pid in ipairs(duel.teamB) do
            if pid == source then
                return duel, "red"
            end
        end
    end
    return nil, nil
end

local function RemoveFromTeam(duel, source)
    for i, pid in ipairs(duel.teamA) do
        if pid == source then
            table.remove(duel.teamA, i)
            return "blue"
        end
    end
    for i, pid in ipairs(duel.teamB) do
        if pid == source then
            table.remove(duel.teamB, i)
            return "red"
        end
    end
    return nil
end

local function TeamNames(ids)
    local names = {}
    for i, pid in ipairs(ids) do
        names[i] = GetPlayerNameSafe(pid) or tostring(pid)
    end
    return names
end

local function BuildDuelSnapshot(duel)
    -- Bruges af getDuelData/getRoundData/getDuelById/startGame — indeholder
    -- alt klienten er observeret at læse fra disse payloads.
    return {
        id = duel.id,
        creator = duel.creator,
        host = duel.host,
        map = duel.map,
        weaponMode = duel.weaponMode,
        weaponClass = duel.weaponClass,
        weapon = duel.weapon,
        selectedWeapons = duel.selectedWeapons,
        vestUses = duel.vestUses,
        selectedVestCount = duel.vestUses,
        isPrivate = duel.isPrivate,
        rounds = duel.rounds,
        teamASize = duel.teamASize,
        teamBSize = duel.teamBSize,
        isAsymmetric = duel.isAsymmetric,
        gameMode = duel.gameMode,
        debugMode = duel.debugMode,
        status = duel.status,
        teamA = duel.teamA,
        teamB = duel.teamB,
        teamAStartCoords = duel.teamAStartCoords,
        teamBStartCoords = duel.teamBStartCoords,
        roundStats = duel.roundStats,
    }
end

local function BuildActiveDuelView(duel)
    -- Offentligt view til lobby-listen. privateCode lækkes ALDRIG her.
    return {
        id = duel.id,
        map = duel.map,
        host = duel.host,
        hostName = duel.hostName,
        isPrivate = duel.isPrivate,
        status = duel.status,
        rounds = duel.rounds,
        teamASize = duel.teamASize,
        teamBSize = duel.teamBSize,
        isAsymmetric = duel.isAsymmetric,
        gameMode = duel.gameMode,
        weaponMode = duel.weaponMode,
        weaponClass = duel.weaponClass,
        weapon = duel.weapon,
        selectedWeapons = duel.selectedWeapons,
        vestUses = duel.vestUses,
        debugMode = duel.debugMode,
        players = {
            blueIds = duel.teamA,
            redIds = duel.teamB,
            blueNames = TeamNames(duel.teamA),
            redNames = TeamNames(duel.teamB),
        },
        roundStats = duel.roundStats,
    }
end

local function BuildActiveDuelsArray()
    local list = {}
    for _, duel in pairs(Duels) do
        if duel.status == "waiting" then
            list[#list + 1] = BuildActiveDuelView(duel)
        end
    end
    return list
end

local function BroadcastUpdateDuels()
    TriggerClientEvent("bach_duels:updateDuels", -1, BuildActiveDuelsArray())
end

local function SetBucketForParticipants(duel, bucket)
    for _, pid in ipairs(duel.teamA) do
        if not IsDummy(pid) and IsSourceOnline(pid) then
            SetPlayerRoutingBucket(pid, bucket)
        end
    end
    for _, pid in ipairs(duel.teamB) do
        if not IsDummy(pid) and IsSourceOnline(pid) then
            SetPlayerRoutingBucket(pid, bucket)
        end
    end
end

-- ----------------------------------------------------------------------------
-- Våben / inventory
-- ----------------------------------------------------------------------------

local function GiveItem(source, item, count)
    local ok = pcall(function()
        exports.ox_inventory:AddItem(source, item, count)
    end)
    if ok then
        IssuedItems[source] = IssuedItems[source] or {}
        IssuedItems[source][item] = (IssuedItems[source][item] or 0) + count
    end
end

local function GiveDuelLoadout(source, duel)
    if duel.weaponMode == "single" and duel.weapon then
        GiveItem(source, duel.weapon, 1)
    elseif duel.weaponMode == "multiple" and duel.selectedWeapons then
        for _, w in ipairs(duel.selectedWeapons) do
            GiveItem(source, w, 1)
        end
    end

    if WeaponsConfig and WeaponsConfig.StashItems then
        for _, item in ipairs(WeaponsConfig.StashItems.DefaultItems or {}) do
            GiveItem(source, item.id, item.amount or 1)
        end
        local modeItems = WeaponsConfig.StashItems.GameModeItems and
            WeaponsConfig.StashItems.GameModeItems[duel.gameMode]
        if modeItems then
            for _, item in ipairs(modeItems) do
                GiveItem(source, item.id, item.amount or 1)
            end
        end
    end
end

local function ClearIssuedItems(source)
    local issued = IssuedItems[source]
    if not issued then
        return
    end
    for item, count in pairs(issued) do
        pcall(function()
            exports.ox_inventory:RemoveItem(source, item, count)
        end)
    end
    IssuedItems[source] = nil
end

RegisterNetEvent("bach_duels:giveDuelWeapons", function(clientDuelData)
    local source = source
    if not clientDuelData or not clientDuelData.id then
        return
    end
    local duel = Duels[clientDuelData.id]
    if not duel then
        return
    end
    local team = select(2, FindDuelByParticipant(source))
    if not team then
        return
    end
    -- clientDuelData bruges KUN til at pege på duel-id'et — selve våben-
    -- valget hentes udelukkende fra den server-autoritative duel-post.
    GiveDuelLoadout(source, duel)
end)

RegisterNetEvent("bach_duels:resetWeapons", function()
    local source = source
    ClearIssuedItems(source)
    TriggerClientEvent("bach_duels:resetWeapons", source)
end)

-- ----------------------------------------------------------------------------
-- Runde / kamp-flow
-- ----------------------------------------------------------------------------

local function AliveStatusPayload(duel)
    local blueTeam, redTeam = {}, {}
    for _, pid in ipairs(duel.teamA) do
        blueTeam[#blueTeam + 1] = { id = pid, alive = not duel.roundDead[pid] }
    end
    for _, pid in ipairs(duel.teamB) do
        redTeam[#redTeam + 1] = { id = pid, alive = not duel.roundDead[pid] }
    end
    return { blueTeam = blueTeam, redTeam = redTeam }
end

local function BroadcastAliveStatus(duel)
    local payload = AliveStatusPayload(duel)
    for _, pid in ipairs(duel.teamA) do
        if not IsDummy(pid) then
            TriggerClientEvent("bach_duels:updateAlivePlayersList", pid, payload)
        end
    end
    for _, pid in ipairs(duel.teamB) do
        if not IsDummy(pid) then
            TriggerClientEvent("bach_duels:updateAlivePlayersList", pid, payload)
        end
    end
end

local function ForEachParticipant(duel, fn)
    for _, pid in ipairs(duel.teamA) do
        if not IsDummy(pid) then
            fn(pid, "blue")
        end
    end
    for _, pid in ipairs(duel.teamB) do
        if not IsDummy(pid) then
            fn(pid, "red")
        end
    end
end

local function ResetPlayerAfterDuel(pid)
    if IsDummy(pid) then
        return
    end
    ClearIssuedItems(pid)
    TriggerClientEvent("bach_duels:resetWeapons", pid)
    if IsSourceOnline(pid) then
        SetPlayerRoutingBucket(pid, 0)
    end
end

local function EndDuel(duel, winningTeam)
    duel.status = "finished"

    RecentDuelResults[duel.id] = {
        winningTeam = winningTeam,
        teamA = duel.teamA,
        teamB = duel.teamB,
        blueScore = duel.roundStats.blue,
        redScore = duel.roundStats.red,
        expireAt = GetGameTimer() + 30000,
    }

    local payload = {
        id = duel.id,
        winningTeam = winningTeam,
        teamA = duel.teamA,
        teamB = duel.teamB,
        blueScore = duel.roundStats.blue,
        redScore = duel.roundStats.red,
    }

    ForEachParticipant(duel, function(pid)
        PlayerLastDuel[pid] = { duelId = duel.id, expireAt = GetGameTimer() + 30000 }
        TriggerClientEvent("bach_duels:duelEnded", pid, payload)
        ResetPlayerAfterDuel(pid)
    end)

    for _, spec in ipairs(duel.spectators) do
        TriggerClientEvent("bach_duels:duelEnded", spec.source, payload)
    end
    duel.spectators = {}

    Duels[duel.id] = nil
    BroadcastUpdateDuels()
end

local function StartRound(duel, roundNumber)
    duel.roundDead = {}
    duel.status = "in-progress"
    duel.roundStats.current = roundNumber

    ForEachParticipant(duel, function(pid, team)
        TriggerClientEvent("bach_duels:startNewRound", pid, {
            duelId = duel.id,
            team = team,
            roundNumber = roundNumber,
            blueScore = duel.roundStats.blue,
            redScore = duel.roundStats.red,
        })
    end)

    BroadcastAliveStatus(duel)
end

local function AdvanceAfterRound(duel)
    local winsNeeded = math.floor(duel.rounds / 2) + 1

    if duel.roundStats.blue >= winsNeeded then
        EndDuel(duel, "blue")
    elseif duel.roundStats.red >= winsNeeded then
        EndDuel(duel, "red")
    elseif duel.roundStats.current >= duel.rounds then
        -- Sidste runde spillet uden at nogen nåede flertallet — afgør på score.
        if duel.roundStats.blue > duel.roundStats.red then
            EndDuel(duel, "blue")
        elseif duel.roundStats.red > duel.roundStats.blue then
            EndDuel(duel, "red")
        else
            EndDuel(duel, "none")
        end
    else
        StartRound(duel, duel.roundStats.current + 1)
    end
end

local function FinishRound(duel, winningTeamColor)
    if duel.roundEndedNumber == duel.roundStats.current then
        return -- allerede afsluttet af en anden klients rapport
    end
    duel.roundEndedNumber = duel.roundStats.current

    if winningTeamColor == "blue" then
        duel.roundStats.blue = duel.roundStats.blue + 1
    elseif winningTeamColor == "red" then
        duel.roundStats.red = duel.roundStats.red + 1
    end

    local payload = {
        id = duel.id,
        roundNumber = duel.roundStats.current,
        roundData = duel.rounds,
        redScore = duel.roundStats.red,
        blueScore = duel.roundStats.blue,
    }

    ForEachParticipant(duel, function(pid)
        TriggerClientEvent("bach_duels:roundEnded", pid, payload)
    end)
    for _, spec in ipairs(duel.spectators) do
        TriggerClientEvent("bach_duels:roundEnded", spec.source, payload)
    end

    duel.pendingRoundFinish = duel.roundStats.current
end

local function CountAliveReal(ids, roundDead)
    local alive = 0
    for _, pid in ipairs(ids) do
        if not IsDummy(pid) and not roundDead[pid] then
            alive = alive + 1
        end
    end
    return alive
end

local function CountRealMembers(ids)
    local count = 0
    for _, pid in ipairs(ids) do
        if not IsDummy(pid) then
            count = count + 1
        end
    end
    return count
end

RegisterNetEvent("bach_duels:playerDied", function(duelId, claimedTeam)
    local source = source
    local duel = Duels[duelId]
    if not duel or duel.status ~= "in-progress" then
        return
    end

    local duel2, actualTeam = FindDuelByParticipant(source)
    if duel2 ~= duel or not actualTeam then
        return -- klienten er ikke faktisk deltager i denne duel
    end

    if duel.roundDead[source] then
        return
    end
    duel.roundDead[source] = true

    BroadcastAliveStatus(duel)

    local blueAlive = CountAliveReal(duel.teamA, duel.roundDead)
    local redAlive = CountAliveReal(duel.teamB, duel.roundDead)
    local blueReal = CountRealMembers(duel.teamA)
    local redReal = CountRealMembers(duel.teamB)

    if blueAlive == 0 and redAlive == 0 then
        FinishRound(duel, "none")
    elseif blueAlive == 0 and blueReal > 0 then
        FinishRound(duel, "red")
    elseif redAlive == 0 and redReal > 0 then
        FinishRound(duel, "blue")
    end
end)

RegisterNetEvent("bach_duels:roundFinished", function(duelId)
    local duel = Duels[duelId]
    if not duel then
        return
    end
    local _, team = FindDuelByParticipant(source)
    if not team then
        return
    end
    if duel.pendingRoundFinish ~= duel.roundStats.current then
        return
    end
    duel.pendingRoundFinish = nil
    AdvanceAfterRound(duel)
end)

RegisterNetEvent("bach_duels:roundTimeLimitReached", function(duelId)
    local source = source
    local duel = Duels[duelId]
    if not duel or duel.status ~= "in-progress" then
        return
    end
    local _, team = FindDuelByParticipant(source)
    if not team then
        return
    end
    if duel.roundEndedNumber == duel.roundStats.current then
        return
    end
    FinishRound(duel, "none")
end)

RegisterNetEvent("bach_duels:headshot", function()
    local source = source
    if Throttled(source, "headshot", 250) then
        return
    end
    local duel = select(1, FindDuelByParticipant(source))
    if not duel or duel.status ~= "in-progress" then
        return
    end

    CreateThread(function()
        local identifier = GetIdentifier(source)
        local name = GetPlayerNameSafe(source) or "Unknown Player"
        MySQL.query.await([[
            INSERT INTO bach_duels_stats (identifier, name, headshots, score)
            VALUES (?, ?, 1, 10)
            ON DUPLICATE KEY UPDATE headshots = headshots + 1, score = score + 10, name = ?
        ]], { identifier, name, name })

        local row = MySQL.single.await(
            "SELECT wins, losses, headshots, score, name FROM bach_duels_stats WHERE identifier = ?",
            { identifier })
        if row then
            TriggerClientEvent("bach_duels:statsUpdated", source, row)
        end
    end)
end)

-- ----------------------------------------------------------------------------
-- Forlad-duel / vote-to-continue / kick / luk
-- ----------------------------------------------------------------------------

local function SendLeftDuel(pid, duelId)
    if not IsDummy(pid) then
        TriggerClientEvent("bach_duels:leftDuel", pid, duelId)
        ResetPlayerAfterDuel(pid)
    end
end

local function CloseWaitingDuel(duel, reason)
    ForEachParticipant(duel, function(pid)
        TriggerClientEvent("bach_duels:duelClosed", pid, duel.id)
        ResetPlayerAfterDuel(pid)
    end)
    Duels[duel.id] = nil
    BroadcastUpdateDuels()
end

local function ResolveContinueVote(duel)
    local vote = duel.pendingVote
    if not vote then
        return
    end
    duel.pendingVote = nil

    local yes, no = 0, 0
    for _, v in pairs(vote.votes) do
        if v then
            yes = yes + 1
        else
            no = no + 1
        end
    end

    local willContinue = yes >= no -- default fortsæt ved uafgjort/ingen stemmer

    ForEachParticipant(duel, function(pid)
        TriggerClientEvent("bach_duels:continueVoteResult", pid, willContinue)
    end)

    if willContinue then
        duel.roundDead[vote.leaverId] = nil
        TriggerClientEvent("bach_duels:resetAliveStatus", -1)
        BroadcastAliveStatus(duel)

        local blueReal = CountRealMembers(duel.teamA)
        local redReal = CountRealMembers(duel.teamB)
        if blueReal == 0 or redReal == 0 then
            EndDuel(duel, "none")
        end
    else
        EndDuel(duel, "none")
    end
end

local function HandlePlayerLeave(source, reason)
    local duel, team = FindDuelByParticipant(source)
    if not duel then
        return
    end

    local name = GetPlayerNameSafe(source) or tostring(source)
    RemoveFromTeam(duel, source)
    SendLeftDuel(source, duel.id)

    if duel.status == "waiting" then
        if duel.creator == source then
            CloseWaitingDuel(duel, reason)
            return
        end

        ForEachParticipant(duel, function(pid)
            TriggerClientEvent("bach_duels:playerLeft", pid, name, team)
        end)
        BroadcastUpdateDuels()
        return
    end

    if duel.status == "in-progress" then
        local blueReal = CountRealMembers(duel.teamA)
        local redReal = CountRealMembers(duel.teamB)

        if blueReal == 0 or redReal == 0 then
            EndDuel(duel, "none")
            return
        end

        if duel.pendingVote then
            -- Der er allerede en afstemning i gang; den nye afgang tælles som
            -- endnu et forladt hold hvis den relevante spiller findes.
            return
        end

        duel.pendingVote = { leaverId = source, leaverName = name, votes = {} }

        ForEachParticipant(duel, function(pid)
            TriggerClientEvent("bach_duels:voteOnContinue", pid, duel.id, name)
        end)

        SetTimeout(15000, function()
            if duel.pendingVote and duel.pendingVote.leaverId == source then
                ResolveContinueVote(duel)
            end
        end)
    end
end

RegisterNetEvent("bach_duels:playerWantsToLeave", function(duelId, claimedPlayerId)
    local source = source
    HandlePlayerLeave(source, "left")
end)

RegisterNetEvent("bach_duels:submitContinueVote", function(duelId, vote)
    local source = source
    local duel = Duels[duelId]
    if not duel or not duel.pendingVote then
        return
    end
    local _, team = FindDuelByParticipant(source)
    if not team then
        return
    end
    duel.pendingVote.votes[source] = vote == true

    local remaining = CountRealMembers(duel.teamA) + CountRealMembers(duel.teamB)
    local voted = 0
    for _ in pairs(duel.pendingVote.votes) do
        voted = voted + 1
    end
    if voted >= remaining then
        ResolveContinueVote(duel)
    end
end)

lib.callback.register("bach_duels:closeDuel", function(source, duelId)
    local duel = Duels[duelId]
    if not duel then
        return { success = false, message = "Duel findes ikke" }
    end
    if duel.host ~= source then
        return { success = false, message = "Kun værten kan lukke duellen" }
    end

    if duel.status == "waiting" then
        CloseWaitingDuel(duel, "closed")
    else
        EndDuel(duel, "none")
    end

    return { success = true }
end)

lib.callback.register("bach_duels:kickPlayer", function(source, data)
    local duel = Duels[data and data.duelId]
    if not duel then
        return { success = false, message = "Duel findes ikke" }
    end
    if duel.host ~= source then
        return { success = false, message = "Kun værten kan kicke Playere" }
    end
    local targetId = tonumber(data.playerId) or data.playerId
    if targetId == duel.host then
        return { success = false, message = "Du kan ikke kicke dig selv" }
    end

    local team = RemoveFromTeam(duel, targetId)
    if not team then
        return { success = false, message = "Player er ikke i duellen" }
    end

    if not IsDummy(targetId) then
        TriggerClientEvent("bach_duels:kickedFromDuel", targetId, duel.id)
        ResetPlayerAfterDuel(targetId)
    end

    BroadcastUpdateDuels()
    return { success = true }
end)

lib.callback.register("bach_duels:changeTeam", function(source, duelId)
    local duel = Duels[duelId]
    if not duel or duel.status ~= "waiting" then
        return { success = false, message = "Duel findes ikke eller er allerede startet" }
    end

    local currentTeam = RemoveFromTeam(duel, source)
    if not currentTeam then
        return { success = false, message = "Du er ikke en del af denne duel" }
    end

    local targetIsBlue = currentTeam == "red"
    local targetList = targetIsBlue and duel.teamA or duel.teamB
    local targetSize = targetIsBlue and duel.teamASize or duel.teamBSize

    if #targetList >= targetSize then
        -- Intet plads på det ønskede hold — sæt Player tilbage.
        if currentTeam == "blue" then
            duel.teamA[#duel.teamA + 1] = source
        else
            duel.teamB[#duel.teamB + 1] = source
        end
        return { success = false, message = "Det andet hold er fuldt" }
    end

    targetList[#targetList + 1] = source
    BroadcastUpdateDuels()
    return { success = true }
end)

-- ----------------------------------------------------------------------------
-- Oprettelse / join / start
-- ----------------------------------------------------------------------------

lib.callback.register("bach_duels:createDuel", function(source, duelData)
    if type(duelData) ~= "table" then
        return { success = false, message = "Ugyldig data" }
    end
    if IsBanned(GetIdentifier(source)) then
        return { success = false, message = "Du er udelukket fra dueller" }
    end

    local duel, err = NewDuel(source, duelData, false, 0)
    if not duel then
        return { success = false, message = err }
    end

    BroadcastUpdateDuels()
    return { success = true, duelId = duel.id, message = "Duel oprettet" }
end)

lib.callback.register("bach_duels:createDebugDuel", function(source, duelData, dummyCount)
    if type(duelData) ~= "table" then
        return { success = false, message = "Ugyldig data" }
    end

    local duel, err = NewDuel(source, duelData, true, dummyCount)
    if not duel then
        return { success = false, message = err }
    end

    BroadcastUpdateDuels()
    return { success = true, duelId = duel.id, message = "Debug-duel oprettet" }
end)

lib.callback.register("bach_duels:getActiveDuels", function(source)
    return BuildActiveDuelsArray()
end)

lib.callback.register("bach_duels:getAllDuels", function(source)
    local all = {}
    for id, duel in pairs(Duels) do
        all[id] = BuildDuelSnapshot(duel)
    end
    return all
end)

lib.callback.register("bach_duels:getDuelData", function(source, duelId)
    local duel = Duels[duelId]
    if not duel then
        return nil
    end
    return BuildDuelSnapshot(duel)
end)

lib.callback.register("bach_duels:getRoundData", function(source, duelId)
    local duel = Duels[duelId]
    if not duel then
        return nil
    end
    return BuildDuelSnapshot(duel)
end)

lib.callback.register("bach_duels:getDuelById", function(source, duelId)
    local duel = Duels[duelId]
    if not duel then
        return nil
    end
    return BuildDuelSnapshot(duel)
end)

local function TryJoin(source, duelId, requestedTeam, privateCode)
    local duel = Duels[duelId]
    if not duel then
        return false, "Duelen findes ikke"
    end
    if duel.status ~= "waiting" then
        return false, "Duelen er allerede startet"
    end
    if FindDuelByParticipant(source) then
        return false, "Du er allerede i en duel"
    end
    if IsBanned(GetIdentifier(source)) then
        return false, "Du er udelukket fra dueller"
    end

    if duel.isPrivate then
        if type(privateCode) ~= "string" or privateCode:upper() ~= duel.privateCode then
            return false, "Forkert Private Code"
        end
    end

    local team = requestedTeam
    if team ~= "blue" and team ~= "red" then
        team = (#duel.teamA <= #duel.teamB) and "blue" or "red"
    end

    local list = team == "blue" and duel.teamA or duel.teamB
    local size = team == "blue" and duel.teamASize or duel.teamBSize

    if #list >= size then
        local otherTeam = team == "blue" and "red" or "blue"
        local otherList = otherTeam == "blue" and duel.teamA or duel.teamB
        local otherSize = otherTeam == "blue" and duel.teamASize or duel.teamBSize
        if #otherList < otherSize then
            team = otherTeam
            list = otherList
        else
            return false, "Duelen er fuld"
        end
    end

    list[#list + 1] = source
    return true, "Du har tilsluttet dig duellen"
end

lib.callback.register("bach_duels:joinDuel", function(source, joinData)
    joinData = joinData or {}
    local ok, message = TryJoin(source, joinData.duelId, joinData.team, joinData.privateCode)
    if ok then
        BroadcastUpdateDuels()
    end
    return { success = ok, message = message }
end)

RegisterNetEvent("bach_duels:joinPrivateDuel", function(duelId, code)
    local source = source
    local ok, message = TryJoin(source, duelId, nil, code)
    if ok then
        BroadcastUpdateDuels()
        TriggerClientEvent("bach_duels:notifyPlayer", source, "Succes", message, "success")
    else
        TriggerClientEvent("bach_duels:notifyPlayer", source, "Fejl", message, "error")
    end
end)

lib.callback.register("bach_duels:leaveDuel", function(source, duelId)
    local duel, team = FindDuelByParticipant(source)
    if not duel or duel.id ~= duelId then
        return { success = false, message = "Du er ikke i denne duel" }
    end
    HandlePlayerLeave(source, "left")
    return { success = true }
end)

lib.callback.register("bach_duels:startDuel", function(source, duelId)
    local duel = Duels[duelId]
    if not duel then
        return { success = false, message = "Duelen findes ikke" }
    end
    if duel.host ~= source then
        return { success = false, message = "Kun værten kan starte duellen" }
    end
    if duel.status ~= "waiting" then
        return { success = false, message = "Duellen er allerede startet" }
    end
    if #duel.teamA ~= duel.teamASize or #duel.teamB ~= duel.teamBSize then
        return { success = false, message = "Begge hold skal være fulde før start" }
    end

    duel.status = "in-progress"
    duel.roundStats = { current = 1, blue = 0, red = 0 }
    duel.roundDead = {}
    duel.roundEndedNumber = nil
    duel.pendingRoundFinish = nil

    duel.routingBucket = 10000 + duel.id
    SetBucketForParticipants(duel, duel.routingBucket)

    local snapshot = BuildDuelSnapshot(duel)
    ForEachParticipant(duel, function(pid, team)
        TriggerClientEvent("bach_duels:startGame", pid, snapshot, team)
    end)

    if duel.debugMode then
        local function tick()
            if not Duels[duel.id] or duel.status ~= "in-progress" then
                return
            end
            local dummies = {}
            for _, pid in ipairs(duel.teamA) do
                if IsDummy(pid) then
                    dummies[#dummies + 1] = { id = pid, team = "blue" }
                end
            end
            for _, pid in ipairs(duel.teamB) do
                if IsDummy(pid) then
                    dummies[#dummies + 1] = { id = pid, team = "red" }
                end
            end
            if #dummies > 0 then
                ForEachParticipant(duel, function(pid)
                    TriggerClientEvent("bach_duels:npcActivity", pid, dummies)
                end)
            end
            SetTimeout(8000, tick)
        end
        SetTimeout(8000, tick)
    end

    BroadcastUpdateDuels()
    return { success = true }
end)

-- ----------------------------------------------------------------------------
-- Vehicles / hopouts (defensivt implementeret; ikke nåeligt via nuværende
-- createDuel-flow, men client-koden forventer disse events hvis gameMode
-- nogensinde er "hopouts")
-- ----------------------------------------------------------------------------

RegisterNetEvent("bach_duels:setRoutingBucket", function(clientDuelData)
    local source = source
    local duel = select(1, FindDuelByParticipant(source))
    if not duel then
        return
    end
    if not duel.routingBucket then
        duel.routingBucket = 10000 + duel.id
    end
    SetPlayerRoutingBucket(source, duel.routingBucket)
end)

RegisterNetEvent("bach_duels:checkEntityBucket", function(netId)
    local source = source
    local entity = NetworkGetEntityFromNetworkId(netId)
    local entityBucket = 0
    if entity and entity ~= 0 and DoesEntityExist(entity) then
        entityBucket = GetEntityRoutingBucket(entity)
    end
    local playerBucket = GetPlayerRoutingBucket(source)
    TriggerClientEvent("bach_duels:entityBucketInfo", source, netId, entityBucket, playerBucket)
end)

RegisterNetEvent("bach_duels:requestTeamVehicles", function(duelId, team)
    local source = source
    local duel = Duels[duelId]
    if not duel or (team ~= "blue" and team ~= "red") then
        return
    end
    local actualDuel, actualTeam = FindDuelByParticipant(source)
    if actualDuel ~= duel or actualTeam ~= team then
        return
    end
    if duel.vehicles[team] then
        local target = team == "blue" and duel.teamA or duel.teamB
        for _, pid in ipairs(target) do
            if not IsDummy(pid) then
                TriggerClientEvent("bach_duels:syncTeamVehicles", pid, duelId, team, duel.vehicles[team])
            end
        end
        return
    end

    local coords = team == "blue" and duel.teamAStartCoords or duel.teamBStartCoords
    if not coords then
        return
    end

    local model = joaat("neon")
    local vehicle = CreateVehicleServerSetter(model, "automobile", coords.x, coords.y, coords.z,
        coords.h or coords.w or 0.0)

    local timeout = 0
    while not DoesEntityExist(vehicle) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end

    if not DoesEntityExist(vehicle) then
        return
    end

    if duel.routingBucket then
        SetEntityRoutingBucket(vehicle, duel.routingBucket)
    end

    local netId = NetworkGetNetworkIdFromEntity(vehicle)
    duel.vehicles[team] = { { netId = netId } }

    local target = team == "blue" and duel.teamA or duel.teamB
    for _, pid in ipairs(target) do
        if not IsDummy(pid) then
            TriggerClientEvent("bach_duels:syncTeamVehicles", pid, duelId, team, duel.vehicles[team])
        end
    end
end)

RegisterNetEvent("bach_duels:playerEnteredVehicle", function(netId)
    -- Rent informativt ping fra klienten — ingen server-handling påkrævet
    -- ud over at bekræfte deltagelse, hvilket allerede sker via FindDuelByParticipant.
    local source = source
    FindDuelByParticipant(source)
end)

-- ----------------------------------------------------------------------------
-- Dummy / bot-opslag
-- ----------------------------------------------------------------------------

lib.callback.register("bach_duels:isDummyPlayer", function(source, playerId)
    return IsDummy(playerId)
end)

lib.callback.register("bach_duels:getPlayerInfo", function(source, playerId)
    local name = GetPlayerNameSafe(playerId)
    if name then
        return { name = name, id = playerId }
    end
    return { name = tostring(playerId), id = playerId }
end)

-- ----------------------------------------------------------------------------
-- Spectate
-- ----------------------------------------------------------------------------

lib.callback.register("bach_duels:isPlayerInDuel", function(source)
    local duel = select(1, FindDuelByParticipant(source))
    return duel ~= nil and duel.status == "in-progress"
end)

lib.callback.register("bach_duels:getSpectateTargets", function(source, duelId)
    local duel, team = FindDuelByParticipant(source)
    if not duel or not team then
        return { players = {}, targetTeam = nil }
    end

    local list = team == "blue" and duel.teamA or duel.teamB
    local players = {}
    for _, pid in ipairs(list) do
        if pid ~= source and not IsDummy(pid) and not duel.roundDead[pid] then
            players[#players + 1] = pid
        end
    end

    return { players = players, targetTeam = team }
end)

lib.callback.register("bach_duels:getSpectateableDuels", function(source)
    local list = {}
    for _, duel in pairs(Duels) do
        if duel.status == "in-progress" then
            local map = GetMapById(duel.map)
            list[#list + 1] = {
                id = duel.id,
                map = { name = map and map.name or "Ukendt Map" },
                blueTeam = duel.teamA,
                redTeam = duel.teamB,
                blueNames = TeamNames(duel.teamA),
                redNames = TeamNames(duel.teamB),
                status = "in-progress",
                host = duel.hostName,
                blueScore = duel.roundStats.blue,
                redScore = duel.roundStats.red,
                currentRound = duel.roundStats.current,
                totalRounds = duel.rounds,
            }
        end
    end
    return list
end)

lib.callback.register("bach_duels:joinAsSpectator", function(source, duelId, team)
    local duel = Duels[duelId]
    if not duel or duel.status ~= "in-progress" then
        return false, nil, nil
    end

    local list = team == "blue" and duel.teamA or duel.teamB
    local targetId = nil
    for _, pid in ipairs(list) do
        if not IsDummy(pid) and IsSourceOnline(pid) and not duel.roundDead[pid] then
            targetId = pid
            break
        end
    end
    if not targetId then
        for _, pid in ipairs(list) do
            if not IsDummy(pid) and IsSourceOnline(pid) then
                targetId = pid
                break
            end
        end
    end
    if not targetId then
        return false, nil, nil
    end

    local ped = GetPlayerPed(targetId)
    if not ped or ped == 0 then
        return false, nil, nil
    end
    local coords = GetEntityCoords(ped)

    local alreadySpectating = false
    for _, spec in ipairs(duel.spectators) do
        if spec.source == source then
            alreadySpectating = true
            spec.team = team
            break
        end
    end
    if not alreadySpectating then
        duel.spectators[#duel.spectators + 1] = { source = source, team = team }
    end

    return true, targetId, coords
end)

RegisterNetEvent("bach_duels:leaveSpectator", function(duelId)
    local source = source
    local duel = Duels[duelId]
    if not duel then
        return
    end
    for i, spec in ipairs(duel.spectators) do
        if spec.source == source then
            table.remove(duel.spectators, i)
            break
        end
    end
end)

RegisterNetEvent("bach_duels:requestSpectate", function(duelId, team, targetPlayerId)
    local source = source
    local duel = Duels[duelId]
    if not duel or duel.status ~= "in-progress" then
        return
    end
    local list = team == "blue" and duel.teamA or duel.teamB
    local valid = false
    for _, pid in ipairs(list) do
        if pid == targetPlayerId then
            valid = true
            break
        end
    end
    if not valid or IsDummy(targetPlayerId) or not IsSourceOnline(targetPlayerId) then
        return
    end

    PendingSpectateRequests[targetPlayerId] = {
        requesterId = source,
        duelId = duelId,
        team = team,
        expireAt = GetGameTimer() + 30000,
    }

    TriggerClientEvent("bach_duels:receiveSpectateRequest", targetPlayerId, source, duelId, team)
end)

local function ResolveSpectateRequest(targetSource, approved)
    local pending = PendingSpectateRequests[targetSource]
    if not pending then
        return false
    end
    PendingSpectateRequests[targetSource] = nil

    if GetGameTimer() > pending.expireAt then
        return false
    end

    TriggerClientEvent("bach_duels:spectateRequestResponse", pending.requesterId, pending.duelId, pending.team,
        targetSource, approved)
    return true
end

RegisterNetEvent("bach_duels:respondToSpectateRequest", function(requesterId, duelId, team, approved)
    local source = source
    local pending = PendingSpectateRequests[source]
    if not pending or pending.requesterId ~= requesterId or pending.duelId ~= duelId then
        return
    end
    ResolveSpectateRequest(source, approved == true)
end)

RegisterCommand("accept", function(source)
    if source == 0 then
        return
    end
    local resolved = ResolveSpectateRequest(source, true)
    if not resolved then
        TriggerClientEvent("bach_duels:notifyPlayer", source, "Spectate",
            "Du har ingen ventende spectate-anmodninger.", "error")
    end
end, false)

-- ----------------------------------------------------------------------------
-- Stats / leaderboard
-- ----------------------------------------------------------------------------

lib.callback.register("bach_duels:getPersonalData", function(source)
    local identifier = GetIdentifier(source)
    local row = MySQL.single.await(
        "SELECT wins, losses, headshots, score, name FROM bach_duels_stats WHERE identifier = ?",
        { identifier })
    if row then
        return row
    end
    return {
        wins = 0,
        losses = 0,
        headshots = 0,
        score = 0,
        name = GetPlayerNameSafe(source) or "Unknown Player",
    }
end)

lib.callback.register("bach_duels:getLeaderboardData", function(source)
    local rows = MySQL.query.await(
        "SELECT name, wins, losses, headshots, score FROM bach_duels_stats ORDER BY score DESC LIMIT 100")
    return { data = rows or {} }
end)

local function PeekLastDuelResult(source)
    local ref = PlayerLastDuel[source]
    if not ref or GetGameTimer() > ref.expireAt then
        return nil
    end
    return RecentDuelResults[ref.duelId]
end

local function IsIdInList(list, id)
    for _, pid in ipairs(list) do
        if pid == id then
            return true
        end
    end
    return false
end

RegisterNetEvent("bach_duels:updatePlayerStats", function(clientPayload)
    local source = source
    local result = PeekLastDuelResult(source)
    if not result or result.winningTeam == "none" then
        return
    end

    local winningList = result.winningTeam == "blue" and result.teamA or result.teamB
    if not IsIdInList(winningList, source) then
        return -- klienten hævder en sejr serveren ikke har registreret
    end

    -- Kravet er nu bekræftet gyldigt af serverens egen kamp-fasit — forbrug
    -- kvitteringen først NU, så en fejlagtig (afvist) påstand ikke ødelægger
    -- Playerens mulighed for stadig at indsende det korrekte, gyldige kald.
    PlayerLastDuel[source] = nil

    local identifier = GetIdentifier(source)
    local name = GetPlayerNameSafe(source) or "Unknown Player"

    MySQL.query.await([[
        INSERT INTO bach_duels_stats (identifier, name, wins, score)
        VALUES (?, ?, 1, 100)
        ON DUPLICATE KEY UPDATE wins = wins + 1, score = score + 100, name = ?
    ]], { identifier, name, name })

    local row = MySQL.single.await(
        "SELECT wins, losses, headshots, score, name FROM bach_duels_stats WHERE identifier = ?",
        { identifier })
    if row then
        TriggerClientEvent("bach_duels:statsUpdated", source, row)
    end
end)

RegisterNetEvent("bach_duels:playerLost", function()
    local source = source
    local result = PeekLastDuelResult(source)
    if not result or result.winningTeam == "none" then
        return
    end

    local winningList = result.winningTeam == "blue" and result.teamA or result.teamB
    if IsIdInList(winningList, source) then
        return -- vandt faktisk — ignorer forkert selvrapporteret tab
    end
    local losingList = result.winningTeam == "blue" and result.teamB or result.teamA
    if not IsIdInList(losingList, source) then
        return -- var slet ikke med i denne duel
    end

    PlayerLastDuel[source] = nil

    local identifier = GetIdentifier(source)
    local name = GetPlayerNameSafe(source) or "Unknown Player"

    MySQL.query.await([[
        INSERT INTO bach_duels_stats (identifier, name, losses)
        VALUES (?, ?, 1)
        ON DUPLICATE KEY UPDATE losses = losses + 1, name = ?
    ]], { identifier, name, name })

    local row = MySQL.single.await(
        "SELECT wins, losses, headshots, score, name FROM bach_duels_stats WHERE identifier = ?",
        { identifier })
    if row then
        TriggerClientEvent("bach_duels:statsUpdated", source, row)
    end
end)

-- ----------------------------------------------------------------------------
-- Ban-system (admin) — ACE-tilladelse "bach_duels.admin" kræves.
-- Ingen klient-side adgangskontrol fandtes for banmenu.lua, så serveren
-- håndhæver dette selv og tilføjer den manglende kommando til at åbne menuen.
-- ----------------------------------------------------------------------------

RegisterCommand("duelban", function(source)
    if source == 0 then
        return
    end
    if not IsAdmin(source) then
        DenyAdmin(source)
        return
    end
    TriggerClientEvent("bach_duels:openBanMenu", source)
end, false)

lib.callback.register("bach_duels:searchPlayers", function(source, searchTerm)
    if not IsAdmin(source) then
        return {}
    end

    local results = {}
    searchTerm = searchTerm and tostring(searchTerm):lower() or nil

    for _, playerId in ipairs(GetPlayers()) do
        local pid = tonumber(playerId)
        local name = GetPlayerName(pid)
        if name then
            if not searchTerm or searchTerm == "" or name:lower():find(searchTerm, 1, true) or
                tostring(pid) == searchTerm then
                results[#results + 1] = { name = name, id = pid }
            end
        end
    end

    return results
end)

lib.callback.register("bach_duels:getBanList", function(source)
    if not IsAdmin(source) then
        return {}
    end
    local rows = MySQL.query.await(
        "SELECT player_name, player_id, reason, banned_by, banned_at FROM bach_duels_bans ORDER BY banned_at DESC")
    return rows or {}
end)

RegisterNetEvent("bach_duels:banPlayer", function(targetId, reason)
    local source = source
    if not IsAdmin(source) then
        DenyAdmin(source)
        return
    end

    targetId = tonumber(targetId)
    if not targetId or not GetPlayerName(targetId) then
        TriggerClientEvent("bach_duels:notifyPlayer", source, "Fejl", "Player er ikke online", "error")
        return
    end

    local identifier = GetIdentifier(targetId)
    local targetName = GetPlayerName(targetId)
    local adminName = GetPlayerName(source) or tostring(source)
    reason = (reason and reason ~= "") and reason or "Ingen årsag angivet"

    MySQL.query.await([[
        INSERT INTO bach_duels_bans (player_id, player_name, reason, banned_by)
        VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE reason = ?, banned_by = ?, banned_at = CURRENT_TIMESTAMP
    ]], { identifier, targetName, reason, adminName, reason, adminName })

    HandlePlayerLeave(targetId, "banned")

    TriggerClientEvent("bach_duels:notifyPlayer", source, "Success",
        targetName .. " er blevet udelukket fra dueller", "success")
    TriggerClientEvent("bach_duels:notifyPlayer", targetId, "Duels",
        "Du er blevet udelukket fra dueller: " .. reason, "error")
end)

RegisterNetEvent("bach_duels:unbanPlayer", function(playerId)
    local source = source
    if not IsAdmin(source) then
        DenyAdmin(source)
        return
    end

    MySQL.query.await("DELETE FROM bach_duels_bans WHERE player_id = ?", { playerId })
    TriggerClientEvent("bach_duels:notifyPlayer", source, "Success", "Udelukkelse fjernet", "success")
end)

-- ----------------------------------------------------------------------------
-- Disconnect / resource-cleanup
-- ----------------------------------------------------------------------------

AddEventHandler("playerDropped", function(reason)
    local source = source
    HandlePlayerLeave(source, "dropped")

    for id, duel in pairs(Duels) do
        for i, spec in ipairs(duel.spectators) do
            if spec.source == source then
                table.remove(duel.spectators, i)
                break
            end
        end
    end

    PendingSpectateRequests[source] = nil
    for target, pending in pairs(PendingSpectateRequests) do
        if pending.requesterId == source then
            PendingSpectateRequests[target] = nil
        end
    end

    PlayerLastDuel[source] = nil
    IssuedItems[source] = nil
end)

AddEventHandler("onResourceStop", function(resourceName)
    if resourceName ~= GetCurrentResourceName() then
        return
    end

    for id, duel in pairs(Duels) do
        ForEachParticipant(duel, function(pid)
            TriggerClientEvent("bach_duels:forceDuelEnd", pid)
            if IsSourceOnline(pid) then
                SetPlayerRoutingBucket(pid, 0)
            end
        end)
        for _, spec in ipairs(duel.spectators) do
            TriggerClientEvent("bach_duels:forceDuelEnd", spec.source)
        end
    end

    Duels = {}
    Dummies = {}
    PendingSpectateRequests = {}
    RecentDuelResults = {}
    PlayerLastDuel = {}
    IssuedItems = {}
end)
