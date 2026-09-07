--[[
    Trust factor-tab sker ÉN gang, i det øjeblik opgaver bliver tildelt
    (se Tasks.GiveService). Trust factor-recovery derimod er et løbende
    system der kræver reel, ikke-AFK aktiv tid på serveren — det håndteres
    her via et 1-minuts tick der læser data.lastActivityAt, som klienten
    holder opdateret (client/activity.lua).
]]

TrustFactor = {}

-- ------------------------------------------------------------
-- TAB — kaldes fra Tasks.GiveService lige efter tasks er tilføjet.
-- "amount" er ANTALLET af netop tildelte opgaver, ikke spillerens total.
-- ------------------------------------------------------------
function TrustFactor.OnTasksAssigned(identifier, amount)
    local settings = Settings.TrustFactor()
    if not settings.enabled then return end

    local data = Players[identifier]
    if not data then return end

    local loss = 0

    if settings.mode == 'per_task' then
        loss = amount * settings.perTaskLoss
    else -- per_x_tasks
        local blocks = math.floor(amount / settings.perXTasksTasks)
        loss = blocks * settings.perXTasksLoss
    end

    if loss <= 0 then return end

    data.trust_factor = Utils.Clamp(Utils.Round(data.trust_factor - loss, 2), 0, 100)
    SavePlayer(identifier)
    PushPlayerUpdate(identifier)

    InsertAuditLog('modify_trust', nil, nil, identifier, data.name, {
        delta = -loss, reason = 'task_assignment', tasksGiven = amount,
    })
end

-- Bruges af Owner/Staff når trust factor justeres direkte (ikke via opgaver).
function TrustFactor.SetManually(identifier, newValue, actorSource, actorName)
    local data = Players[identifier]
    if not data then return false, 'Spilleren blev ikke fundet.' end

    newValue = Utils.Clamp(tonumber(newValue) or data.trust_factor, 0, 100)
    local actorIdentifier = actorSource and GetIdentifier(actorSource) or nil

    local before = data.trust_factor
    data.trust_factor = Utils.Round(newValue, 2)
    SavePlayer(identifier)
    PushPlayerUpdate(identifier)

    InsertAuditLog('modify_trust', actorIdentifier, actorName, identifier, data.name, {
        before = before, after = data.trust_factor, reason = 'manual_staff_edit',
    })

    return true
end

-- ------------------------------------------------------------
-- RECOVERY TICK — kører hvert 60. sekund for alle ONLINE spillere.
-- ------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(60000)

        local settings = Settings.TrustFactor()
        if settings.enabled and settings.recoveryEnabled then
            local now = os.time()

            for identifier, data in pairs(Players) do
                if data.source and data.trust_factor < 100 then
                    local secondsSinceActivity = now - (data.lastActivityAt or 0)
                    local isActive = secondsSinceActivity <= settings.afkTimeoutSeconds

                    if isActive then
                        data.active_minutes_since_recovery = (data.active_minutes_since_recovery or 0) + 1

                        if data.active_minutes_since_recovery >= settings.recoveryMinutes then
                            data.active_minutes_since_recovery = 0
                            data.trust_factor = Utils.Clamp(
                                Utils.Round(data.trust_factor + settings.recoveryAmount, 2), 0, 100
                            )

                            SavePlayer(identifier)
                            PushPlayerUpdate(identifier)

                            InsertAuditLog('trust_recovery', nil, nil, identifier, data.name, {
                                amount = settings.recoveryAmount, newValue = data.trust_factor,
                            })

                            TriggerClientEvent('ox_lib:notify', data.source, {
                                title = 'Samfundstjeneste',
                                description = ('Din tillidsfaktor er steget til %d%%.'):format(math.floor(data.trust_factor)),
                                type = 'success',
                                position = 'center-right',
                            })
                        else
                            SavePlayer(identifier)
                        end
                    end
                    -- Hvis ikke aktiv: tælleren fryser simpelthen (gemmes ikke ned igen).
                end
            end
        end
    end
end)

-- ------------------------------------------------------------
-- AKTIVITETS-PING fra klienten (kun sendt når spilleren reelt har
-- bevæget sig / givet input siden sidste ping — se client/activity.lua).
-- ------------------------------------------------------------
RegisterNetEvent('mm_sf:server:activityPing', function()
    local src = source
    local identifier = GetIdentifier(src)
    local data = identifier and Players[identifier]
    if not data then return end

    data.lastActivityAt = os.time()
end)
