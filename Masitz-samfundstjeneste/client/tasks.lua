--[[
    Selve arbejdsmetoden fra V1 (send-punkt, marker, [E], progressbar,
    animation) genimplementeret oven på det server-autoritative
    session-system i server/tasks.lua. Klienten viser og spiller — den
    bestemmer ALDRIG selv om en opgave er "gennemført".

    VIGTIGT (rettet AFK-farming-hul): tidligere blev ALLE et sites
    opgavepunkter vist/interagerbare på samme tid, og serveren tjekkede
    aldrig hvor spilleren rent faktisk stod ved completion - man kunne
    derfor blive stående ét sted og spamme [E]. Nu får klienten ét
    server-udpeget "mål" ad gangen (mm_sf:client:setTaskTarget), og
    serveren verificerer selv afstanden til DET punkt, før en session
    overhovedet startes (se server/tasks.lua). Efter hver gennemført
    opgave udpeger serveren et NYT mål (jf. Config.AntiRepeat), så
    spilleren reelt skal bevæge sig rundt mellem punkterne.
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

-- Det ene, aktuelle mål udpeget af serveren. nil indtil serveren har sendt
-- et via mm_sf:client:setTaskTarget (sker automatisk når tjenesten
-- starter, og igen efter hver gennemført opgave).
local currentTarget = nil

RegisterNetEvent('mm_sf:client:setTaskTarget', function(target)
    currentTarget = target
end)

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

        if Service.active and currentTarget and currentTarget.point then
            local marker = Config.Samfundstjeneste.Marker
            local point = currentTarget.point
            local playerCoords = GetEntityCoords(PlayerPedId())
            local distance = #(playerCoords - point)

            if distance < marker.drawDistance then
                -- Kun her behøver loopet køre hvert frame - markøren skal
                -- tegnes hver tick for at være flimmerfri, og det er også
                -- her E-interaktionen kan blive relevant. Langt fra målet
                -- (den store majoritet af tiden en spiller bevæger sig
                -- rundt mellem opgaver) er der intet at tegne eller tjekke,
                -- så det korte 500ms-interval fra toppen af loopet bruges
                -- i stedet - jf. kravet om dynamiske waits frem for
                -- konstant Wait(0).
                wait = 0

                DrawMarker(marker.type, point.x, point.y, point.z + marker.heightOffset, 0, 0, 0, 0, 0, 0,
                    marker.size.x, marker.size.y, marker.size.z,
                    marker.color.r, marker.color.g, marker.color.b, marker.color.a, false, true, 2, false, nil, nil, false)

                if distance <= INTERACT_DISTANCE then
                    -- Prompten vises kun ved 2+ resterende opgaver (se
                    -- MIN_TASKS_FOR_PROMPT) - men selve interaktionen
                    -- (markør + [E]) virker uændret uanset antal tilbage.
                    if CanShowPrompt() then
                        if not shownPrompt then
                            shownPrompt = true
                            lib.showTextUI('[E] Udfør opgave', { position = 'bottom-center' })
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
    currentTarget = nil
end)
