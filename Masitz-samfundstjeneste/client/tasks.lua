--[[
    Selve arbejdsmetoden fra V1 (send-punkt, marker, [E], progressbar,
    animation) genimplementeret oven på det server-autoritative
    session-system i server/tasks.lua. Klienten viser og spiller — den
    bestemmer ALDRIG selv om en opgave er "gennemført".
]]

local INTERACT_DISTANCE = 1.5
local busy = false

-- Minimum antal resterende opgaver før [E]-prompten (lib.showTextUI) må
-- vises. Ved præcis 1 opgave tilbage undertrykkes prompten bevidst - det
-- er her det tidligere buggede/flakkende TextUI-forløb opstod, i det korte
-- vindue mellem serverens completion og stopService-eventets ankomst.
-- Selve interaktionen (verdens-markøren og [E]-tasten) virker stadig helt
-- normalt, kun tekst-prompten skjules. Se client/main.lua/service.lua for
-- hvordan PlayerTaskState.activeTasks holdes opdateret.
local MIN_TASKS_FOR_PROMPT = 2

local function CanShowPrompt()
    return (PlayerTaskState and PlayerTaskState.activeTasks or 0) >= MIN_TASKS_FOR_PROMPT
end

-- Alle punkter for de aktiverede tasks på det site spilleren er sendt til.
-- Bruges BÅDE til at tegne markører ved ALLE opgavepunkter (ikke kun det
-- nærmeste) og til selve interaktionstjekket.
local function GetSiteTaskPoints()
    if not Service.active or not Service.siteKey then return nil end

    local site = Config.Samfundstjeneste.Sites[Service.siteKey]
    if not site then return nil end

    local points = {}
    for _, taskKey in ipairs(site.tasks) do
        local taskDef = Config.Samfundstjeneste.Tasks[taskKey]
        if taskDef and taskDef.enabled then
            for _, point in ipairs(taskDef.points) do
                points[#points + 1] = point
            end
        end
    end

    return points
end

local function GetNearestPoint(points, playerCoords, maxDist)
    local nearest, nearestDist = nil, maxDist

    for _, point in ipairs(points) do
        local dist = #(playerCoords - point)
        if dist < nearestDist then
            nearest = point
            nearestDist = dist
        end
    end

    return nearest
end

local function PickAnimationCommand(animation)
    if animation.type ~= 'emote' then return nil end
    if animation.command then return animation.command end
    if animation.random then return animation.random[math.random(#animation.random)] end
    return nil
end

local function PlayTaskAnimation(animation)
    local command = PickAnimationCommand(animation)
    if not command then return end

    -- Genbruger serverens etablerede emote-system (samme som V1's 'e broom'
    -- osv.) i stedet for at implementere en parallel animations-loader.
    ExecuteCommand(command)
end

local function StopTaskAnimation()
    ClearPedTasks(PlayerPedId())
end

local function RunTask()
    if busy then return end
    busy = true

    local session = lib.callback.await('mm_sf:server:startTaskSession', false)
    if not session then
        busy = false
        return
    end

    local ped = PlayerPedId()
    PlayTaskAnimation(session.animation)

    local completed = lib.progressBar({
        duration = session.duration,
        label = session.label,
        useWhileDead = false,
        canCancel = true,
        disable = { move = true, car = true, combat = true },
    })

    StopTaskAnimation()

    if not completed then
        busy = false
        return
    end

    local ok = lib.callback.await('mm_sf:server:completeTaskSession', false)
    if not ok then
        lib.notify({
            title = 'Samfundstjeneste',
            description = 'Opgaven kunne ikke godkendes. Prøv igen.',
            type = 'error',
            position = 'center-right',
        })
    end

    busy = false
end

CreateThread(function()
    local shownPrompt = false

    while true do
        local wait = 500

        if Service.active then
            wait = 0
            local points = GetSiteTaskPoints()

            if points and #points > 0 then
                local marker = Config.Samfundstjeneste.Marker
                local playerCoords = GetEntityCoords(PlayerPedId())

                -- Tegn en markør ved ALLE aktiverede opgavepunkter på sitet
                -- (inden for drawDistance), ikke kun det spilleren står ved.
                for _, point in ipairs(points) do
                    if #(playerCoords - point) < marker.drawDistance then
                        DrawMarker(marker.type, point.x, point.y, point.z + marker.heightOffset, 0, 0, 0, 0, 0, 0,
                            marker.size.x, marker.size.y, marker.size.z,
                            marker.color.r, marker.color.g, marker.color.b, marker.color.a, false, true, 2, false, nil, nil, false)
                    end
                end

                local nearest = GetNearestPoint(points, playerCoords, INTERACT_DISTANCE)

                if nearest then
                    -- Prompten vises kun ved 2+ resterende opgaver (se
                    -- MIN_TASKS_FOR_PROMPT) - men selve interaktionen
                    -- (markør + [E]) virker uændret uanset antal tilbage.
                    if CanShowPrompt() then
                        if not shownPrompt then
                            shownPrompt = true
                            lib.showTextUI('[E] Udfør opgave', { position = 'top-center' })
                        end
                    elseif shownPrompt then
                        shownPrompt = false
                        lib.hideTextUI()
                    end

                    if not busy and IsControlJustPressed(0, 38) then -- E
                        if shownPrompt then
                            lib.hideTextUI()
                            shownPrompt = false
                        end
                        RunTask()
                    end
                elseif shownPrompt then
                    shownPrompt = false
                    lib.hideTextUI()
                end
            elseif shownPrompt then
                shownPrompt = false
                lib.hideTextUI()
            end
        elseif shownPrompt then
            shownPrompt = false
            lib.hideTextUI()
        end

        Wait(wait)
    end
end)

-- ------------------------------------------------------------
-- CLEANUP
-- ------------------------------------------------------------
AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    lib.hideTextUI()
    StopTaskAnimation()
end)

AddEventHandler('mm_sf:client:stopService', function()
    lib.hideTextUI()
    StopTaskAnimation()
    busy = false
end)
