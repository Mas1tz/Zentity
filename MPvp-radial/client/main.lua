-- ============================================================
--  MPvp-radial | client/main.lua
--  Ét fladt ox_lib-radial-hjul: Noclip, Revive, Lobby, Report.
--  Ingen nedlagt "Funktioner"-undermenu, ingen andre punkter.
-- ============================================================

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[MPvp-radial] ' .. fmt):format(...))
    end
end

-- ============================================================
--  NOCLIP
--  Eneste loop i hele resourcen — findes KUN mens noclip er aktivt.
--  Bevægelse er framerate-uafhængig (GetFrameTime()) og kamera-relativ,
--  som almindelig FiveM noclip. Sidder spilleren i et køretøj, noclippes
--  køretøjet i stedet for pedet.
-- ============================================================

local noclipActive = false

-- Reference-hastighed i m/s ved Config.Noclip.speed = 1.0. De tre
-- config-værdier er multiplikatorer af denne, ikke rå m/s.
local NOCLIP_BASE_SPEED = 15.0

local function GetNoclipEntity()
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        return GetVehiclePedIsIn(ped, false)
    end
    return ped
end

-- Kamera-forward-vektor — standard-udledning fra kamerarotation.
local function GetCamDirection()
    local rot = GetGameplayCamRot(2)
    local rotZ = math.rad(rot.z)
    local rotX = math.rad(rot.x)
    local cosX = math.abs(math.cos(rotX))
    return vector3(-math.sin(rotZ) * cosX, math.cos(rotZ) * cosX, math.sin(rotX))
end

local function GetNoclipSpeed()
    if IsControlPressed(0, 21) then return Config.Noclip.fastSpeed end -- VENSTRE SHIFT
    if IsControlPressed(0, 25) then return Config.Noclip.slowSpeed end -- HØJRE MUSEKNAP
    return Config.Noclip.speed
end

local function DrawNoclipIndicator()
    local bg, txt = Config.UI.background, Config.UI.text
    local label = 'NOCLIP'
    local x, y = 0.5, 0.955

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextEntry('STRING')
    AddTextComponentString(label)
    local width = GetTextScreenWidth(true) + 0.014

    DrawRect(x, y, width, 0.028, bg[1], bg[2], bg[3], bg[4])

    SetTextFont(4)
    SetTextScale(0.32, 0.32)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(txt[1], txt[2], txt[3], txt[4])
    SetTextOutline()
    SetTextEntry('STRING')
    AddTextComponentString(label)
    DrawText(x, y - 0.011)
end

local function SetNoclipEntityState(entity, enabled)
    SetEntityCollision(entity, not enabled, not enabled)
    SetEntityInvincible(entity, enabled)
    FreezeEntityPosition(entity, enabled)
end

local function EnableNoclip()
    if noclipActive then return end
    noclipActive = true

    CreateThread(function()
        local entity = GetNoclipEntity()
        SetNoclipEntityState(entity, true)

        while noclipActive do
            local currentEntity = GetNoclipEntity()
            if currentEntity ~= entity then
                -- Spilleren steg ind i/ud af et køretøj mens noclip var aktivt.
                SetNoclipEntityState(entity, false)
                entity = currentEntity
                SetNoclipEntityState(entity, true)
            end

            if DoesEntityExist(entity) then
                local forwardInput, rightInput, upInput = 0.0, 0.0, 0.0

                if IsControlPressed(0, 32) then forwardInput = forwardInput + 1.0 end -- W
                if IsControlPressed(0, 33) then forwardInput = forwardInput - 1.0 end -- S
                if IsControlPressed(0, 35) then rightInput = rightInput + 1.0 end     -- D
                if IsControlPressed(0, 34) then rightInput = rightInput - 1.0 end     -- A
                if IsControlPressed(0, 22) then upInput = upInput + 1.0 end           -- SPACE
                if IsControlPressed(0, 36) then upInput = upInput - 1.0 end           -- VENSTRE CTRL

                -- Undertryk spillets egen håndtering af disse taster, så der
                -- ikke opstår løbe-/hop-animationer mens pedet er frosset.
                DisableControlAction(0, 32, true)
                DisableControlAction(0, 33, true)
                DisableControlAction(0, 34, true)
                DisableControlAction(0, 35, true)
                DisableControlAction(0, 22, true)
                DisableControlAction(0, 36, true)

                if forwardInput ~= 0.0 or rightInput ~= 0.0 or upInput ~= 0.0 then
                    local dir = GetCamDirection()
                    local right = vector3(dir.y, -dir.x, 0.0)
                    local move = (dir * forwardInput) + (right * rightInput) + (vector3(0.0, 0.0, 1.0) * upInput)

                    local len = #move
                    if len > 0.0 then
                        move = move / len
                    end

                    local displacement = move * (NOCLIP_BASE_SPEED * GetNoclipSpeed() * GetFrameTime())
                    local coords = GetEntityCoords(entity) + displacement
                    SetEntityCoordsNoOffset(entity, coords.x, coords.y, coords.z, true, true, true)
                end
            end

            DrawNoclipIndicator()
            Wait(0)
        end

        if DoesEntityExist(entity) then
            SetNoclipEntityState(entity, false)
            local coords = GetEntityCoords(entity)
            SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, true)
        end
    end)
end

local function DisableNoclip()
    -- Selve oprydningen sker i loopet ovenfor, når det ser
    -- `noclipActive == false` og afslutter sig selv.
    noclipActive = false
end

local function ToggleNoclip()
    if noclipActive then
        DisableNoclip()
        lib.notify({ title = 'Noclip', description = 'Noclip deaktiveret.', type = 'inform' })
    else
        EnableNoclip()
        lib.notify({ title = 'Noclip', description = 'Noclip aktiveret.', type = 'inform' })
    end
end

-- ============================================================
--  REVIVE
--  Bevarer den eksisterende esx_ambulancejob-integration. Rent
--  client-side og selv-kun, som før — men nu med et dødstjek og en
--  cooldown, så det ikke kan bruges som et ubegrænset selv-heal.
-- ============================================================

local lastReviveAt = 0

local function TryRevive()
    if not Config.Revive.enabled then return end

    if not IsEntityDead(PlayerPedId()) then
        lib.notify({ title = 'Revive', description = 'Du er ikke død.', type = 'error' })
        return
    end

    local now = GetGameTimer()
    if now - lastReviveAt < Config.Revive.cooldown then
        lib.notify({ title = 'Revive', description = 'Vent lidt før du prøver igen.', type = 'error' })
        return
    end
    lastReviveAt = now

    TriggerEvent(Config.Revive.event)
    lib.notify({ title = 'Revive', description = 'Du er blevet genoplivet.', type = 'success' })
end

-- ============================================================
--  LOBBY
-- ============================================================

local function GoToLobby()
    if not Config.Lobby.enabled then return end

    if Config.Lobby.exportResource and Config.Lobby.exportName then
        local ok, err = pcall(function()
            exports[Config.Lobby.exportResource][Config.Lobby.exportName]()
        end)
        if not ok then
            DebugPrint('Lobby-export fejlede: %s', tostring(err))
            lib.notify({ title = 'Lobby', description = 'Kunne ikke åbne lobbyen.', type = 'error' })
        end
        return
    end

    local ped = PlayerPedId()
    local c = Config.Lobby.coords

    DoScreenFadeOut(300)
    Wait(300)
    SetEntityCoords(ped, c.x, c.y, c.z, false, false, false, true)
    SetEntityHeading(ped, c.w or 0.0)
    Wait(150)
    DoScreenFadeIn(300)

    lib.notify({ title = 'Lobby', description = 'Du er nu i lobbyen.', type = 'inform' })
end

-- ============================================================
--  REPORT
--  Client-side er kun UX — serveren gennemtjekker alt selv (se
--  server/main.lua). Bruger ox_lib's inputDialog, ikke en ny NUI.
-- ============================================================

local function OpenReport()
    if not Config.Report.enabled then return end

    local input = lib.inputDialog('Report spiller', {
        { type = 'number', label = 'Spiller-ID', description = 'Server-ID på den du vil rapportere', min = 0, required = true },
        { type = 'textarea', label = 'Årsag', description = 'Beskriv kort hvad der skete', required = true, min = Config.Report.minReasonLength, max = Config.Report.maxReasonLength },
    })
    if not input then return end

    local targetId = tonumber(input[1])
    local reason = tostring(input[2] or '')

    if not targetId then
        lib.notify({ title = 'Report', description = 'Ugyldigt spiller-ID.', type = 'error' })
        return
    end
    if #reason < Config.Report.minReasonLength then
        lib.notify({ title = 'Report', description = 'Skriv en mere uddybende årsag.', type = 'error' })
        return
    end

    TriggerServerEvent('mpvp_radial:report', targetId, reason)
end

RegisterNetEvent('mpvp_radial:reportResult', function(success, message)
    lib.notify({
        title = success and 'Report sendt' or 'Report fejl',
        description = message,
        type = success and 'success' or 'error',
    })
end)

-- ============================================================
--  RADIAL-REGISTRERING — ét fladt hjul, 4 punkter, ingen undermenu.
--  Selve åbne-mekanismen er uændret ox_lib-radial (samme som før).
-- ============================================================

lib.addRadialItem({
    { id = 'mpvp_noclip', label = 'Noclip', icon = 'jet-fighter-up',    onSelect = ToggleNoclip },
    { id = 'mpvp_revive',  label = 'Revive', icon = 'heartbeat',        onSelect = TryRevive },
    { id = 'mpvp_lobby',   label = 'Lobby',  icon = 'door-open',        onSelect = GoToLobby },
    { id = 'mpvp_report',  label = 'Report', icon = 'clipboard-question', onSelect = OpenReport },
})

-- ============================================================
--  CLEANUP — ingen stuck noclip, ingen efterladte states.
-- ============================================================

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if noclipActive then
        noclipActive = false
        local ped = PlayerPedId()
        local entity = GetNoclipEntity()
        if DoesEntityExist(entity) then
            SetNoclipEntityState(entity, false)
        end
        if DoesEntityExist(ped) then
            SetNoclipEntityState(ped, false)
        end
    end
end)
