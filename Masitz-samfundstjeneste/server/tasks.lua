--[[
    server/tasks.lua er den eneste kilde til sandhed for opgave-tal
    (active_tasks/total_assigned/total_completed) og for den automatiske
    tidsreduktion. INGEN andre moduler må selv skrive til disse felter —
    alt går gennem funktionerne herunder, så trust factor, historik,
    audit log og NUI-opdatering altid følger med konsistent.

    ALLE veje der kan bringe en spillers active_tasks til 0 (manuel
    completion, automatisk tidsreduktion, Staff der fjerner/sætter
    opgaver, eller et eksplicit Release) ender i ÉN central funktion,
    CompleteCommunityService, nederst i filen — så teleport/cleanup/
    notifikation aldrig kan glemmes på en enkelt af de veje.
]]

Tasks = {}

local ActiveSessions = {} -- [identifier] = { sessionId, taskKey, siteKey, startedAt, minDuration }

-- ------------------------------------------------------------
-- ANTI-REPEAT
-- Husker de senest brugte arbejdspunkter (og task-typer) pr. spiller, så
-- samme placering ikke kan trækkes igen med det samme (AFK-farming). Rent
-- server-side, in-memory — nulstilles naturligt ved disconnect, og har
-- ingen grund til at overleve en resource-genstart (ActiveSessions gør
-- det heller ikke).
-- ------------------------------------------------------------
local RecentPoints = {}    -- [identifier] = { point, point, ... } ældste først
local RecentTaskTypes = {} -- [identifier] = { taskKey, taskKey, ... } ældste først

local function PickAvoidingRecent(pool, recentList, maxRecent)
    if maxRecent <= 0 or #pool <= 1 then
        return pool[math.random(#pool)]
    end

    local candidates = {}
    for _, item in ipairs(pool) do
        local isRecent = false
        for _, recentItem in ipairs(recentList) do
            if item == recentItem then
                isRecent = true
                break
            end
        end
        if not isRecent then
            candidates[#candidates + 1] = item
        end
    end

    -- For få unikke muligheder til at kunne undgå alle "recent" — brug
    -- hele puljen i stedet for at fejle eller give en tom liste.
    if #candidates == 0 then
        candidates = pool
    end

    return candidates[math.random(#candidates)]
end

local function RememberRecent(recentTable, identifier, chosen, maxRecent)
    local list = recentTable[identifier] or {}
    list[#list + 1] = chosen

    while #list > maxRecent do
        table.remove(list, 1)
    end

    recentTable[identifier] = list
end

-- ------------------------------------------------------------
-- INTERNT: anvend en delta (positiv eller negativ) på active_tasks,
-- clamp til >= 0, og hold total_assigned i sync når det er en tildeling.
-- ------------------------------------------------------------
-- isManualRemoval: sat af Staff-initierede fjernelser (RemoveTasks,
-- SetTasks nedad, Release) så vi kan skelne dem fra opgaver der forsvinder
-- via gennemførelse eller automatisk tidsreduktion (som IKKE går gennem
-- ApplyDelta) — det er kun de manuelle vi tæller i total_removed_manual.
local function ApplyDelta(identifier, delta, reason, actorName, isAssignment, isManualRemoval)
    local data = Players[identifier]
    if not data then return false end

    local before = data.active_tasks
    data.active_tasks = math.max(0, data.active_tasks + delta)

    if isAssignment and delta > 0 then
        data.total_assigned = data.total_assigned + delta
    end

    if isManualRemoval and delta < 0 then
        data.total_removed_manual = (data.total_removed_manual or 0) + math.abs(delta)
    end

    InsertHistory(identifier, delta, reason, actorName)
    SavePlayer(identifier)
    PushPlayerUpdate(identifier)

    return true, before, data.active_tasks
end

-- ------------------------------------------------------------
-- CENTRAL COMPLETION — se filens toptekst. Kaldes ALTID (og KUN) når en
-- spillers active_tasks reelt er nået til 0, uanset hvilken vej der
-- bragte den derhen. Idempotent: har spilleren allerede ingen aktiv
-- session/service, er der intet at gøre (forhindrer dobbelt teleport/
-- notifikation hvis flere kald skulle ramme samme spiller).
-- ------------------------------------------------------------
local function CompleteCommunityService(identifier, options)
    options = options or {}

    local data = Players[identifier]
    if not data then return end

    if not data.inService and not ActiveSessions[identifier] then
        return
    end

    data.inService = false
    ActiveSessions[identifier] = nil
    RecentPoints[identifier] = nil
    RecentTaskTypes[identifier] = nil

    SavePlayer(identifier)
    PushPlayerUpdate(identifier)

    if options.auditAction then
        InsertAuditLog(options.auditAction, options.actorIdentifier, options.actorName, identifier, data.name,
            options.auditDetails or { finished = true })
    end

    if data.source then
        TriggerClientEvent('mm_sf:client:stopService', data.source)
        TriggerClientEvent('mm_sf:client:teleportBack', data.source, Config.Samfundstjeneste.General.releaseCoords)
        TriggerClientEvent('ox_lib:notify', data.source, {
            title = 'Samfundstjeneste',
            description = options.notifyMessage or 'Din samfundstjeneste er afsluttet.',
            type = 'success',
            position = 'center-right',
        })
    end
end

-- ------------------------------------------------------------
-- GIV / TILFØJ OPGAVER (Staff/Owner/console-handling, eller /kommando)
-- Udløser trust factor-tab baseret på det tildelte ANTAL, jf. config.
-- ------------------------------------------------------------
function Tasks.GiveService(identifier, amount, reason, actorSource, actorName)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Antal skal være positivt.' end
    if amount > 5000 then return false, 'Antal er urealistisk højt.' end

    local data = Players[identifier]
    if not data then return false, 'Spilleren blev ikke fundet.' end

    local actorIdentifier = actorSource and GetIdentifier(actorSource) or nil
    ApplyDelta(identifier, amount, reason or 'Tildelt af Staff', actorName, true)

    TrustFactor.OnTasksAssigned(identifier, amount)

    InsertAuditLog('give_service', actorIdentifier, actorName, identifier, data.name, {
        amount = amount, reason = reason,
    })

    if data.source then
        TriggerClientEvent('ox_lib:notify', data.source, {
            title = 'Samfundstjeneste',
            description = ('Du har fået %d nye opgaver.'):format(amount),
            type = 'inform',
            position = 'center-right',
        })
    end

    Tasks.TryAutoStart(identifier)

    return true
end

function Tasks.RemoveTasks(identifier, amount, actorSource, actorName)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false, 'Antal skal være positivt.' end

    local data = Players[identifier]
    if not data then return false, 'Spilleren blev ikke fundet.' end

    local actorIdentifier = actorSource and GetIdentifier(actorSource) or nil
    ApplyDelta(identifier, -amount, 'Staff justering', actorName, false, true)

    InsertAuditLog('remove_tasks', actorIdentifier, actorName, identifier, data.name, { amount = amount })

    -- Bragte denne fjernelse spilleren i bund, skal de færdiggøres og
    -- teleporteres tilbage præcis som ved enhver anden vej til 0 - uanset
    -- om de var fysisk i tjeneste eller ej.
    if data.active_tasks <= 0 then
        CompleteCommunityService(identifier, {
            auditAction = 'remove_tasks_complete',
            actorIdentifier = actorIdentifier,
            actorName = actorName,
            notifyMessage = 'Din samfundstjeneste er afsluttet.',
        })
    end

    return true
end

function Tasks.SetTasks(identifier, newAmount, actorSource, actorName)
    newAmount = math.floor(tonumber(newAmount) or -1)
    if newAmount < 0 then return false, 'Antal kan ikke være negativt.' end

    local data = Players[identifier]
    if not data then return false, 'Spilleren blev ikke fundet.' end

    local delta = newAmount - data.active_tasks
    local actorIdentifier = actorSource and GetIdentifier(actorSource) or nil

    ApplyDelta(identifier, delta, 'Staff justering (sæt direkte)', actorName, delta > 0, delta < 0)

    InsertAuditLog('set_tasks', actorIdentifier, actorName, identifier, data.name, {
        newAmount = newAmount,
    })

    if data.active_tasks <= 0 then
        CompleteCommunityService(identifier, {
            auditAction = 'set_tasks_complete',
            actorIdentifier = actorIdentifier,
            actorName = actorName,
            notifyMessage = 'Din samfundstjeneste er afsluttet.',
        })
    else
        Tasks.TryAutoStart(identifier)
    end

    return true
end

function Tasks.Release(identifier, actorSource, actorName)
    local data = Players[identifier]
    if not data then return false, 'Spilleren blev ikke fundet.' end

    local removed = data.active_tasks
    if removed > 0 then
        ApplyDelta(identifier, -removed, 'Løsladt af Staff', actorName, false, true)
    end

    local actorIdentifier = actorSource and GetIdentifier(actorSource) or nil
    InsertAuditLog('release', actorIdentifier, actorName, identifier, data.name, { removed = removed })

    -- Release skal altid færdiggøre spilleren, uanset om de allerede var
    -- i tjeneste eller ej (CompleteCommunityService er selv idempotent,
    -- så et kald her uden noget at afslutte er en billig no-op).
    CompleteCommunityService(identifier, {
        notifyMessage = 'Du er blevet løsladt. Din tjeneste er afsluttet.',
    })

    return true
end

-- ------------------------------------------------------------
-- AUTOMATISK AFSENDELSE
-- Spilleren kan IKKE selv bede om at komme i tjeneste — det sker
-- automatisk, i det øjeblik Staff/Owner giver dem opgaver (eller sætter
-- antallet op), eller når de logger ind og allerede har opgaver fra en
-- tidligere session. Kaldes altid EFTER active_tasks er opdateret.
-- ------------------------------------------------------------
function Tasks.TryAutoStart(identifier)
    local data = Players[identifier]
    if not data or not data.source then return end -- offline, sendes ved næste login
    if data.inService then return end
    if data.active_tasks <= 0 then return end

    Tasks.StartService(data.source)
end

-- ------------------------------------------------------------
-- SERVICE START/STOP (spilleren fysisk på et site)
-- Spilleren kan ALDRIG selv vælge site — den vælges tilfældigt her,
-- server-side, blandt de konfigurerede sites, og spilleren sendes
-- automatisk derud.
-- ------------------------------------------------------------
function Tasks.StartService(source)
    local identifier = GetIdentifier(source)
    local data = identifier and Players[identifier]
    if not data then return false, 'Data ikke klar.' end

    if data.active_tasks <= 0 then
        return false, 'Du har ingen aktive opgaver.'
    end

    local siteKeys = {}
    for key in pairs(Config.Samfundstjeneste.Sites) do
        siteKeys[#siteKeys + 1] = key
    end
    if #siteKeys == 0 then return false, 'Ingen arbejdssteder er konfigureret.' end

    local siteKey = siteKeys[math.random(#siteKeys)]
    local site = Config.Samfundstjeneste.Sites[siteKey]

    data.inService = siteKey
    -- active_tasks sendes med, så klienten (client/service.lua) kender sit
    -- eget tal fra det øjeblik tjenesten starter, uafhængigt af om
    -- dashboardet nogensinde har været åbnet - se client/tasks.lua's
    -- TextUI-regel ved 1 opgave tilbage.
    TriggerClientEvent('mm_sf:client:startService', source, siteKey, site.sendCoords, data.active_tasks)

    return true
end

function Tasks.StopService(identifier)
    local data = Players[identifier]
    if not data then return end

    data.inService = false
    ActiveSessions[identifier] = nil

    if data.source then
        TriggerClientEvent('mm_sf:client:stopService', data.source)
    end
end

-- ------------------------------------------------------------
-- TASK SESSIONS
-- Klienten kan ALDRIG selv bestemme hvilken task/varighed/placering der
-- gælder — den trækkes server-side blandt sitets aktiverede tasks (og
-- undgår, jf. Config.AntiRepeat, de senest brugte task-typer/punkter), og
-- et sessionId + server-timestamp gemmes så completion kan valideres.
-- ------------------------------------------------------------
lib.callback.register('mm_sf:server:startTaskSession', function(source)
    local identifier = GetIdentifier(source)
    local data = identifier and Players[identifier]
    if not data or not data.inService then return false end
    if data.active_tasks <= 0 then return false end
    if ActiveSessions[identifier] then return false end -- allerede i gang med én

    local site = Config.Samfundstjeneste.Sites[data.inService]
    if not site then return false end

    local enabledTasks = {}
    for _, taskKey in ipairs(site.tasks) do
        local taskDef = Config.Samfundstjeneste.Tasks[taskKey]
        if taskDef and taskDef.enabled then
            enabledTasks[#enabledTasks + 1] = taskKey
        end
    end
    if #enabledTasks == 0 then return false end

    local avoidCount = (Config.Samfundstjeneste.AntiRepeat and Config.Samfundstjeneste.AntiRepeat.avoidLastPoints) or 0

    local taskKey = PickAvoidingRecent(enabledTasks, RecentTaskTypes[identifier] or {}, avoidCount)
    local taskDef = Config.Samfundstjeneste.Tasks[taskKey]
    local point = PickAvoidingRecent(taskDef.points, RecentPoints[identifier] or {}, avoidCount)
    local duration = math.random(taskDef.duration.min, taskDef.duration.max)

    RememberRecent(RecentTaskTypes, identifier, taskKey, avoidCount)
    RememberRecent(RecentPoints, identifier, point, avoidCount)

    ActiveSessions[identifier] = {
        sessionId = ('%s-%d-%d'):format(identifier, GetGameTimer(), math.random(100000, 999999)),
        taskKey = taskKey,
        siteKey = data.inService,
        startedAt = GetGameTimer(),
        minDuration = duration,
    }

    return {
        sessionId = ActiveSessions[identifier].sessionId,
        taskKey = taskKey,
        label = taskDef.label,
        description = taskDef.description,
        animation = taskDef.animation,
        duration = duration,
        point = point,
    }
end)

-- Lille buffer (ms) så normal netværks-jitter mellem client/server ikke
-- fejlagtigt afviser en helt legitim completion.
local COMPLETION_GRACE_MS = 800

lib.callback.register('mm_sf:server:completeTaskSession', function(source)
    local identifier = GetIdentifier(source)
    local data = identifier and Players[identifier]
    local session = identifier and ActiveSessions[identifier]

    if not data or not session then return false end
    if not data.inService or data.inService ~= session.siteKey then
        ActiveSessions[identifier] = nil
        return false
    end
    if data.active_tasks <= 0 then
        ActiveSessions[identifier] = nil
        return false
    end

    local elapsed = GetGameTimer() - session.startedAt
    if elapsed + COMPLETION_GRACE_MS < session.minDuration then
        -- For hurtigt til at være ægte — dropper sessionen uden reward.
        ActiveSessions[identifier] = nil
        return false
    end

    ActiveSessions[identifier] = nil

    data.active_tasks = math.max(0, data.active_tasks - 1)
    data.total_completed = data.total_completed + 1
    InsertHistory(identifier, -1, 'Gennemført arbejdsopgave')
    SavePlayer(identifier)
    PushPlayerUpdate(identifier)

    if data.active_tasks > 0 then
        -- Kun relevant at vise "X opgaver tilbage" når der faktisk ER en
        -- resterende opgave — er dette den sidste, viser
        -- CompleteCommunityService en samlet, mere præcis besked i stedet
        -- for to notifikationer lige efter hinanden.
        TriggerClientEvent('ox_lib:notify', source, {
            title = 'Samfundstjeneste',
            description = ('Du har gennemført en opgave.\n%d opgaver tilbage.'):format(data.active_tasks),
            type = 'success',
            position = 'center-right',
        })
    else
        CompleteCommunityService(identifier, {
            auditAction = 'auto_complete',
            notifyMessage = 'Du har gennemført din sidste opgave.\nDin samfundstjeneste er afsluttet.',
        })
    end

    return true
end)

-- ------------------------------------------------------------
-- AUTOMATISK TIDSREDUKTION
-- Kører ét centralt loop (i stedet for ét loop pr. spiller) for at holde
-- performance-belastningen minimal uanset hvor mange der er i tjeneste.
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(1000)

        local reduction = Settings.TimeReduction()
        if reduction.enabled then
            for identifier, data in pairs(Players) do
                if data.inService and data.active_tasks > 0 then
                    data._reductionAccumMs = (data._reductionAccumMs or 0) + 1000

                    -- escape_pause_until gemmes som unix-millisekunder (os.time-baseret),
                    -- så vi sammenligner mod reelt clock-tid, ikke GetGameTimer().
                    local pausedUntil = data.escape_pause_until or 0
                    local isPaused = pausedUntil > (os.time() * 1000)

                    if not isPaused and data._reductionAccumMs >= (reduction.interval * 1000) then
                        data._reductionAccumMs = 0
                        data.active_tasks = math.max(0, data.active_tasks - reduction.amount)
                        InsertHistory(identifier, -reduction.amount, 'Automatisk tidsreduktion')
                        SavePlayer(identifier)
                        PushPlayerUpdate(identifier)

                        if data.active_tasks > 0 then
                            if data.source then
                                TriggerClientEvent('ox_lib:notify', data.source, {
                                    title = 'Samfundstjeneste',
                                    description = ('%d opgaver tilbage.'):format(data.active_tasks),
                                    type = 'inform',
                                    position = 'center-right',
                                })
                            end
                        else
                            CompleteCommunityService(identifier, {
                                auditAction = 'auto_reduction',
                                notifyMessage = 'Din samfundstjeneste er afsluttet (automatisk tidsreduktion).',
                            })
                        end
                    end
                else
                    data._reductionAccumMs = 0
                end
            end
        end
    end
end)

-- ------------------------------------------------------------
-- CLEANUP ved disconnect/død — undgår hængende sessions/timers.
-- ------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local identifier = GetIdentifier(source)
    if identifier then
        ActiveSessions[identifier] = nil
        RecentPoints[identifier] = nil
        RecentTaskTypes[identifier] = nil
    end
end)
