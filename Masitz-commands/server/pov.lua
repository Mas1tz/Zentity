-- ============================================================
--  Masitz-commands | server/pov.lua
--
--  /pov [ID], /povdone [ID], og hele POV-tidsfrist-maskinen.
--  100% server-autoritativt: klienten sender kun et mål-ID, og modtager
--  udelukkende notifikationer den ikke selv kan udløse eller fortolke om.
--
--  Ingen "while true do Wait(0) end" - hver frist er ét enkelt,
--  event-drevet SetTimeout, ganget med et generations-tal pr. request så
--  en forældet timer (fordi requesten allerede blev completed/annulleret)
--  bliver et sikkert no-op i stedet for at handle på forældet state.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

Pov = {}

-- [identifier] = requestTable  (se NewRequestState())
local ActiveByIdentifier = {}
-- [discordId]  = requestTable  (samme reference som ovenfor - kun til hurtigt opslag)
local ActiveByDiscordId = {}

local function NowIso()
    return os.date('%Y-%m-%d %H:%M:%S')
end

local function DateTimeToEpoch(mysqlDateTime)
    if not mysqlDateTime then return nil end
    local y, mo, d, h, mi, s = mysqlDateTime:match('(%d+)-(%d+)-(%d+) (%d+):(%d+):(%d+)')
    if not y then return nil end
    return os.time({
        year = tonumber(y), month = tonumber(mo), day = tonumber(d),
        hour = tonumber(h), min = tonumber(mi), sec = tonumber(s),
    })
end

local function EpochToDateTime(epoch)
    return os.date('%Y-%m-%d %H:%M:%S', epoch)
end

-- ------------------------------------------------------------------
--  NOTIFY / ALERT (thin client triggers - al beslutningstagen er her)
-- ------------------------------------------------------------------
local function NotifyPovRequested(target, minutesTotal, isRepeat)
    local description
    if isRepeat then
        description = ('Du er blevet bedt om at indsende POV igen. Da du tidligere ikke har overholdt en ' ..
            'POV-frist, har du denne gang kun %d minutter i alt til at indsende dit klip i #%s. ' ..
            'Overholder du ikke fristen denne gang, bliver du permanent udelukket fra serveren.')
            :format(minutesTotal, Config.Command.Pov.DiscordChannelName)
    else
        description = ('Du er blevet bedt om at indsende POV. Du har %d minutter til at indsende dit klip i ' ..
            'Discord-kanalen #%s (kanal-ID: %s).')
            :format(minutesTotal, Config.Command.Pov.DiscordChannelName, Config.Command.Pov.DiscordChannelId)
    end

    TriggerClientEvent('ox_lib:notify', target, {
        title = 'POV påkrævet',
        description = description,
        type = 'warning',
        position = 'center-right',
        duration = 12000,
    })
end

local function NotifyPovStage2(target)
    TriggerClientEvent('Masitz-commands:client:povAlert', target, {
        header = 'POV mangler stadig',
        content = ('Du mangler stadig at sende dit POV. Du har nu yderligere %d minutter til at indsende klippet. ' ..
            'Hvis du ikke gør det, bliver du kicked.'):format(Config.Command.Pov.SecondTimeout),
    })
end

local function NotifyPovCompleted(target)
    TriggerClientEvent('ox_lib:notify', target, {
        title = 'POV registreret',
        description = 'Dit POV er blevet registreret. Tak for din indsendelse.',
        type = 'success',
        position = 'center-right',
        duration = 6000,
    })
end

local function NotifyPovAlreadyActive(requesterSource)
    TriggerClientEvent('ox_lib:notify', requesterSource, {
        title = 'POV-anmodning',
        description = 'Denne spiller har allerede en aktiv POV-anmodning. Der oprettes ikke en ny.',
        type = 'error',
    })
end

-- ------------------------------------------------------------------
--  DATABASE-LAG
-- ------------------------------------------------------------------
local function DbInsertRequest(req)
    MySQL.query.await([[
        INSERT INTO masitz_commands_pov_requests
            (request_id, target_identifier, target_name, target_discord_id,
             requester_identifier, requester_name, status, is_repeat, stage,
             stage_deadline_at, final_deadline_at)
        VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?, ?)
    ]], {
        req.requestId, req.targetIdentifier, req.targetName, req.targetDiscordId,
        req.requesterIdentifier, req.requesterName, req.isRepeat and 1 or 0, req.stage,
        EpochToDateTime(req.stageDeadlineAt), EpochToDateTime(req.finalDeadlineAt),
    })
end

local function DbUpdateStage(req)
    MySQL.query.await(
        'UPDATE masitz_commands_pov_requests SET stage = ?, stage_deadline_at = ? WHERE request_id = ?',
        { req.stage, EpochToDateTime(req.stageDeadlineAt), req.requestId }
    )
end

local function DbMarkStatus(requestId, status, method, staffIdentifier)
    MySQL.query.await(
        'UPDATE masitz_commands_pov_requests SET status = ?, completed_at = CURRENT_TIMESTAMP, completed_method = ?, completed_by_identifier = ? WHERE request_id = ?',
        { status, method, staffIdentifier, requestId }
    )
end

local function DbGetHistory(identifier)
    local ok, row = pcall(MySQL.single.await,
        'SELECT fail_count FROM masitz_commands_pov_history WHERE identifier = ?', { identifier })
    if ok and row then return row.fail_count end
    return 0
end

local function DbRegisterFailure(identifier)
    MySQL.query.await([[
        INSERT INTO masitz_commands_pov_history (identifier, fail_count, last_fail_at)
        VALUES (?, 1, CURRENT_TIMESTAMP)
        ON DUPLICATE KEY UPDATE fail_count = fail_count + 1, last_fail_at = CURRENT_TIMESTAMP
    ]], { identifier })
end

local function DbMarkBanned(identifier)
    MySQL.query.await(
        'UPDATE masitz_commands_pov_history SET banned = 1, banned_at = CURRENT_TIMESTAMP WHERE identifier = ?',
        { identifier })
end

-- ------------------------------------------------------------------
--  STATE-OPRETTELSE / -FJERNELSE
-- ------------------------------------------------------------------
local function RemoveActive(req)
    req.generation = req.generation + 1 -- gør alle udestående timere for denne request til no-ops
    if ActiveByIdentifier[req.targetIdentifier] == req then
        ActiveByIdentifier[req.targetIdentifier] = nil
    end
    if req.targetDiscordId and ActiveByDiscordId[req.targetDiscordId] == req then
        ActiveByDiscordId[req.targetDiscordId] = nil
    end
end

local function RegisterActive(req)
    ActiveByIdentifier[req.targetIdentifier] = req
    if req.targetDiscordId then
        ActiveByDiscordId[req.targetDiscordId] = req
    end
end

-- Forward-deklareret så ScheduleTimeout og HandleTimeout kan referere
-- hinanden uden globale opslag.
local ScheduleTimeout

local function HandleTimeout(req, generation)
    -- Forældet timer (requesten er allerede completed/annulleret siden). No-op.
    if req.generation ~= generation then return end
    if ActiveByIdentifier[req.targetIdentifier] ~= req then return end

    local xPlayer = ESX.GetPlayerFromIdentifier(req.targetIdentifier)
    local currentSource = xPlayer and xPlayer.source or nil

    if req.isRepeat then
        -- Eneste frist for en gentagelses-anmodning: permanent ban.
        DbMarkStatus(req.requestId, 'banned', nil, nil)
        DbMarkBanned(req.targetIdentifier)
        Helpers.BanIdentifier(req.targetIdentifier, Config.Command.Pov.BanReason, 'Masitz-commands (auto)')

        Discord.LogPov('banned', {
            requestId = req.requestId,
            targetName = req.targetName,
            targetServerId = currentSource,
            targetIdentifier = req.targetIdentifier,
            targetDiscordId = req.targetDiscordId,
        })

        if currentSource then
            DropPlayer(currentSource, Config.Command.Pov.BanReason)
        end

        RemoveActive(req)
        return
    end

    if req.stage == 1 then
        req.stage = 2
        req.stageDeadlineAt = os.time() + (Config.Command.Pov.SecondTimeout * 60)
        DbUpdateStage(req)

        if currentSource then
            NotifyPovStage2(currentSource)
        end

        Discord.LogPov('stage2_warning', {
            requestId = req.requestId,
            targetName = req.targetName,
            targetServerId = currentSource,
        })

        ScheduleTimeout(req, req.stageDeadlineAt)
        return
    end

    -- stage == 2 og stadig ikke completed -> kick + registrér fejl.
    DbMarkStatus(req.requestId, 'kicked', nil, nil)
    DbRegisterFailure(req.targetIdentifier)

    Discord.LogPov('kicked', {
        requestId = req.requestId,
        targetName = req.targetName,
        targetServerId = currentSource,
        targetDiscordId = req.targetDiscordId,
        createdAt = EpochToDateTime(req.createdAt),
    })

    if currentSource then
        DropPlayer(currentSource, Config.Command.Pov.KickReason)
    end

    RemoveActive(req)
end

--- Planlægger næste timeout for en request. `deadlineEpoch` er det
--- absolutte tidspunkt (unix-epoch) hvor denne fase udløber - beregnet
--- ud fra timestamps, så restart-genberegning og førstegangs-planlægning
--- bruger nøjagtig samme kode.
ScheduleTimeout = function(req, deadlineEpoch)
    local generation = req.generation
    local msRemaining = math.max(0, (deadlineEpoch - os.time()) * 1000)
    SetTimeout(msRemaining, function()
        HandleTimeout(req, generation)
    end)
end

-- ------------------------------------------------------------------
--  OPRETTELSE AF NY REQUEST
-- ------------------------------------------------------------------
function Pov.CreateRequest(requesterSource, targetSource)
    local requesterIdentifier = Helpers.GetIdentifier(requesterSource)
    local targetIdentifier = Helpers.GetIdentifier(targetSource)

    if not requesterIdentifier or not targetIdentifier then
        return false, 'Kunne ikke bekræfte din identitet. Prøv igen om et øjeblik.'
    end

    if ActiveByIdentifier[targetIdentifier] then
        NotifyPovAlreadyActive(requesterSource)
        return false, nil -- notify allerede sendt, ingen yderligere fejlbesked nødvendig
    end

    local failCount = DbGetHistory(targetIdentifier)
    local isRepeat = failCount >= 1

    local totalMinutes = isRepeat and Config.Command.Pov.RepeatTimeout or
        (Config.Command.Pov.FirstTimeout + Config.Command.Pov.SecondTimeout)
    local firstStageMinutes = isRepeat and Config.Command.Pov.RepeatTimeout or Config.Command.Pov.FirstTimeout

    local now = os.time()
    local req = {
        requestId = Helpers.GeneratePovRequestId(targetSource),
        targetIdentifier = targetIdentifier,
        targetName = GetPlayerName(targetSource) or ('Player ' .. targetSource),
        targetDiscordId = Helpers.GetDiscordId(targetSource),
        requesterIdentifier = requesterIdentifier,
        requesterName = GetPlayerName(requesterSource) or ('Player ' .. requesterSource),
        isRepeat = isRepeat,
        stage = 1,
        generation = 0,
        createdAt = now,
        stageDeadlineAt = now + (firstStageMinutes * 60),
        finalDeadlineAt = now + (totalMinutes * 60),
    }

    DbInsertRequest(req)
    RegisterActive(req)
    ScheduleTimeout(req, req.stageDeadlineAt)

    NotifyPovRequested(targetSource, totalMinutes, isRepeat)

    Discord.LogPov('created', {
        requestId = req.requestId,
        requesterName = req.requesterName,
        requesterServerId = requesterSource,
        targetName = req.targetName,
        targetServerId = targetSource,
        targetDiscordId = req.targetDiscordId,
        isRepeat = isRepeat,
    })

    return true, nil
end

-- ------------------------------------------------------------------
--  COMPLETION (delt af /povdone og den automatiske Discord-integration)
-- ------------------------------------------------------------------
local function CompleteRequest(req, method, staffIdentifier, staffName)
    DbMarkStatus(req.requestId, 'completed', method, staffIdentifier)

    local xPlayer = ESX.GetPlayerFromIdentifier(req.targetIdentifier)
    local currentSource = xPlayer and xPlayer.source or nil
    if currentSource then
        NotifyPovCompleted(currentSource)
    end

    Discord.LogPov('completed', {
        requestId = req.requestId,
        targetName = req.targetName,
        targetServerId = currentSource,
        method = method,
        staffName = staffName,
    })

    RemoveActive(req)
end

--- /povdone [ID] - target angives ved CURRENT server-ID (spilleren skal
--- være online for at en admin manuelt kan bekræfte deres POV).
function Pov.ManualComplete(staffSource, targetServerId)
    local targetIdentifier = Helpers.GetIdentifier(targetServerId)
    local req = targetIdentifier and ActiveByIdentifier[targetIdentifier]

    if not req then
        Discord.LogPov('povdone_noop', {
            staffName = GetPlayerName(staffSource) or tostring(staffSource),
            staffServerId = staffSource,
            targetServerId = targetServerId,
        })
        return false, 'Denne spiller har ingen aktiv POV-anmodning.'
    end

    CompleteRequest(req, 'manual', Helpers.GetIdentifier(staffSource), GetPlayerName(staffSource))
    return true, nil
end

--- Kaldes af server/discord.lua's HTTP-handler. discordId er den ENESTE
--- ting boten sender - resten (hvilken spiller, om anmodningen rent
--- faktisk er aktiv) verificeres udelukkende ud fra vores egen,
--- tidligere server-side indsamlede state (target_discord_id blev
--- registreret dengang requesten blev oprettet, ud fra spillerens egne
--- identifiers på det tidspunkt - IKKE ud fra noget boten selv påstår).
function Pov.CompleteByDiscordId(discordId)
    local req = ActiveByDiscordId[discordId]
    if not req then
        return false, 'not_found'
    end

    CompleteRequest(req, 'auto', nil, nil)
    return true, nil
end

-- ------------------------------------------------------------------
--  GENSTART-GENOPRETTELSE
--  Aktive requests fra før en resource-restart må ikke bare glemmes -
--  resterende tid genberegnes ud fra de gemte timestamps.
-- ------------------------------------------------------------------
AddEventHandler('Masitz-commands:database:ready', function()
    local rows = MySQL.query.await('SELECT * FROM masitz_commands_pov_requests WHERE status = ?', { 'pending' })
    if not rows then return end

    local now = os.time()

    for _, row in ipairs(rows) do
        local req = {
            requestId = row.request_id,
            targetIdentifier = row.target_identifier,
            targetName = row.target_name,
            targetDiscordId = row.target_discord_id,
            requesterIdentifier = row.requester_identifier,
            requesterName = row.requester_name,
            isRepeat = row.is_repeat == 1,
            stage = row.stage,
            generation = 0,
            createdAt = DateTimeToEpoch(row.created_at) or now,
            stageDeadlineAt = DateTimeToEpoch(row.stage_deadline_at) or now,
            finalDeadlineAt = DateTimeToEpoch(row.final_deadline_at) or now,
        }

        RegisterActive(req)

        if now >= req.finalDeadlineAt then
            -- Fristen udløb mens serveren var nede - håndhæv konsekvensen
            -- med det samme i stedet for at planlægge en fortidig timer.
            HandleTimeout(req, req.generation)
        elseif not req.isRepeat and req.stage == 1 and now >= req.stageDeadlineAt then
            -- Stage 1 nåede at udløbe mens serveren var nede, men den
            -- samlede frist er endnu ikke overskredet - spring direkte
            -- til stage 2 med den korrekt genberegnede resterende tid.
            HandleTimeout(req, req.generation)
        else
            ScheduleTimeout(req, req.isRepeat and req.finalDeadlineAt or req.stageDeadlineAt)
        end
    end

    Helpers.DebugPrint('Genoprettede %d aktiv(e) POV-anmodning(er) efter restart.', #rows)
end)

-- ------------------------------------------------------------------
--  GENJOIN-PÅMINDELSE
--  Ingen automatisk straf ved rejoin efter et kick (jf. kravspec) - kun
--  en venlig påmindelse hvis spilleren stadig har en åben anmodning.
-- ------------------------------------------------------------------
AddEventHandler('esx:playerLoaded', function(playerId, xPlayer)
    local identifier = xPlayer and xPlayer.identifier
    if not identifier then return end

    local req = ActiveByIdentifier[identifier]
    if not req then return end

    CreateThread(function()
        Wait(3000) -- lad klienten nå at loade ind før en NUI-notifikation vises
        if req.stage == 2 and not req.isRepeat then
            NotifyPovStage2(playerId)
        else
            local minutesLeft = math.max(1, math.ceil((req.finalDeadlineAt - os.time()) / 60))
            NotifyPovRequested(playerId, minutesLeft, req.isRepeat)
        end
    end)
end)

-- ------------------------------------------------------------------
--  COMMANDS
-- ------------------------------------------------------------------
RegisterCommand('pov', function(source, args)
    if source == 0 then return end -- kun spillere, ikke konsol
    if not Config.Command.Pov.Enabled then return end

    if Config.Command.Pov.CooldownEnabled then
        local onCooldown, remaining = Helpers.IsOnCooldown(source, 'pov', Config.Command.Pov.Cooldown)
        if onCooldown then
            TriggerClientEvent('ox_lib:notify', source, {
                title = 'POV',
                description = ('Du skal vente %d sekunder mere før du kan bruge /pov igen.'):format(remaining),
                type = 'error',
            })
            return
        end
    end

    local ok, targetId, err = Helpers.ValidateTarget(args[1])
    if not ok then
        if Helpers.RegisterInvalidAttempt(source, 'pov') then
            Discord.LogPov('abuse', { serverId = source, reason = 'Gentagne ugyldige /pov-forsøg' })
        end
        TriggerClientEvent('ox_lib:notify', source, { title = 'POV', description = err, type = 'error' })
        return
    end

    if targetId == source then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'POV',
            description = 'Du kan ikke bede dig selv om POV.',
            type = 'error',
        })
        return
    end

    Pov.CreateRequest(source, targetId)
end, false)

RegisterCommand('povdone', function(source, args)
    if source == 0 then return end
    if not Config.Command.Pov.Enabled then return end

    if not Helpers.IsStaff(source, Config.Command.Pov.Povdone) then
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Adgang nægtet',
            description = 'Du har ikke tilladelse til at bruge denne kommando.',
            type = 'error',
        })
        return
    end

    local ok, targetId, err = Helpers.ValidateTarget(args[1])
    if not ok then
        TriggerClientEvent('ox_lib:notify', source, { title = 'POV', description = err, type = 'error' })
        return
    end

    local success, message = Pov.ManualComplete(source, targetId)
    TriggerClientEvent('ox_lib:notify', source, {
        title = 'POV',
        description = success and 'POV registreret som modtaget.' or message,
        type = success and 'success' or 'error',
    })
end, false)
