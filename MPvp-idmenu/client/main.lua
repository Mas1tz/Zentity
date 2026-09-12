-- ============================================================
--  MPvp-idmenu | client/main.lua
--  Rent ID+navn-peek: PAGE DOWN toggler visning af server-ID +
--  display-navn over andre spillere. INGEN menu, INGEN NUI,
--  INGEN server-events.
--
--  PERFORMANCE-DESIGN:
--  - Når ID-peek er OFF: intet loop, ingen native-kald, 0.00ms.
--  - Når ID-peek er ON: ét render-loop (skal køre hvert frame, da
--    GTA's text/rect-natives kun holder i ét frame ad gangen), men
--    den TUNGE del (GetActivePlayers/GetPlayerServerId/GetPlayerName)
--    sker kun hvert Config.IDPeek.cacheInterval ms via en lille cache
--    — ikke hvert frame.
--  - Ingen permanent input-polling-loop: tasten bruger
--    RegisterKeyMapping + RegisterCommand, som FiveM selv håndterer
--    uden nogen konstant Wait(0)-loop.
-- ============================================================

if not Config.IDPeek.enabled then return end

local idModeActive = false
local renderThreadRunning = false

-- { { playerIndex, serverId, ped, displayName }, ... } — genopbygges
-- kun periodisk mens ID-peek er aktivt, ikke hvert frame.
local cachedPlayers = {}
local cachedPlayerCount = 0

local sqDistance = Config.IDPeek.distance * Config.IDPeek.distance

-- ─── STEAM/DISPLAY-NAVN — modulær, isoleret opslags-funktion ─────
-- FiveM eksponerer INTET separat "Steam-navn" til klienten for andre
-- spillere end en selv — GetPlayerIdentifiers (som indeholder
-- steam:-identifieren) findes kun SERVER-side. GetPlayerName(...) er
-- derfor den bedste og eneste pålidelige client-native til formålet;
-- den er i praksis det navn serveren har sat for spilleren (typisk
-- Steam-navnet ved connect). Hele opslaget er samlet i ÉN funktion,
-- så metoden nemt kan udskiftes senere (fx til et custom RP-navn
-- synkroniseret via et eget system) uden at røre resten af koden.
local function GetPlayerDisplayName(playerIndex)
    local ok, name = pcall(GetPlayerName, playerIndex)
    if not ok or not name or name == '' then
        return 'Ukendt'
    end
    return name
end

-- ─── SPILLER-CACHE ───────────────────────────────────────────────
-- Bygger listen af andre spillere (aldrig dig selv) på ny. Håndterer
-- join/leave/reconnect helt naturligt: en disconnected spiller findes
-- bare ikke længere i GetActivePlayers() ved næste genopbygning, og en
-- ny spiller dukker op af sig selv — ingen separate event-handlers
-- nødvendige. Spillere i en anden routing bucket/dimension streamer
-- aldrig ind for os (ped findes ikke), så de filtreres fra gratis.
local function RebuildPlayerCache()
    local list = {}
    local count = 0
    local myIndex = PlayerId()

    for _, playerIndex in ipairs(GetActivePlayers()) do
        if playerIndex ~= myIndex then
            local ped = GetPlayerPed(playerIndex)
            if ped ~= 0 and DoesEntityExist(ped) then
                count = count + 1
                list[count] = {
                    playerIndex = playerIndex,
                    serverId = GetPlayerServerId(playerIndex),
                    ped = ped,
                    displayName = GetPlayerDisplayName(playerIndex),
                }
            end
        end
    end

    cachedPlayers = list
    cachedPlayerCount = count
end

-- ─── VALIDERING PR. SPILLER (uafhængigt af render-koden) ─────────
local function IsPlayerValidForPeek(ped)
    local cfg = Config.IDPeek
    if not DoesEntityExist(ped) then return false end
    if not cfg.showDeadPlayers and IsEntityDead(ped) then return false end
    if not cfg.showPlayersInVehicles and IsPedInAnyVehicle(ped, false) then return false end
    return true
end

local function IsPlayerVisible(myPed, ped)
    if not Config.IDPeek.lineOfSight then return true end
    return HasEntityClearLosToEntity(myPed, ped, 17)
end

-- ─── TEKST-BREDDE (til badge-baggrunden) ─────────────────────────
local function GetRenderedTextWidth(text, font, scale)
    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    return GetTextScreenWidth(true)
end

local function ResolveColors(distance)
    local txt = Config.IDPeek.text
    local dc = Config.IDPeek.distanceColors
    if not dc.enabled then return txt.idColor, txt.nameColor end

    if distance <= dc.close.distance then return dc.close.idColor, dc.close.nameColor end
    if distance <= dc.medium.distance then return dc.medium.idColor, dc.medium.nameColor end
    return dc.far.idColor, dc.far.nameColor
end

-- ─── TEGNING ───────────────────────────────────────────────────────
local function DrawPlayerID(screenX, screenY, text, color)
    local txt = Config.IDPeek.text
    SetTextFont(txt.font)
    SetTextScale(txt.idScale, txt.idScale)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(color[1], color[2], color[3], color[4])
    if txt.outline then SetTextOutline() end
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(screenX, screenY)
end

local function DrawPlayerName(screenX, screenY, text, color)
    local txt = Config.IDPeek.text
    SetTextFont(txt.font)
    SetTextScale(txt.nameScale, txt.nameScale)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(color[1], color[2], color[3], color[4])
    if txt.outline then SetTextOutline() end
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(screenX, screenY)
end

-- Tegner ID + navn som ÉT samlet badge (ikke to separate bokse), med
-- ID'et visuelt mere fremtrædende (større skala) end navnet derunder.
local function DrawPlayerInfo(screenX, screenY, idText, nameText, distance)
    local cfg = Config.IDPeek
    local txt = cfg.text
    local bg = cfg.background
    local border = cfg.border

    local showId = cfg.showId and idText ~= nil
    local showName = cfg.showName and nameText ~= nil
    if not showId and not showName then return end

    local idColor, nameColor = ResolveColors(distance)

    local idY = screenY + txt.idOffset
    local nameY = screenY + txt.nameOffset

    if bg.enabled then
        local idWidth = showId and (GetRenderedTextWidth(idText, txt.font, txt.idScale) + bg.paddingX * 2) or 0
        local nameWidth = showName and (GetRenderedTextWidth(nameText, txt.font, txt.nameScale) + bg.paddingX * 2) or 0
        local rectWidth = math.max(idWidth, nameWidth)

        local idHalfHeight = (txt.idScale * 0.9) * 0.0275
        local nameHalfHeight = (txt.nameScale * 0.9) * 0.0275

        local top, bottom
        if showId and showName then
            top, bottom = idY - idHalfHeight, nameY + nameHalfHeight
        elseif showId then
            top, bottom = idY - idHalfHeight, idY + idHalfHeight
        else
            top, bottom = nameY - nameHalfHeight, nameY + nameHalfHeight
        end

        local rectHeight = (bottom - top) + bg.paddingY * 2
        local rectY = (top + bottom) / 2

        DrawRect(screenX, rectY, rectWidth, rectHeight, bg.color[1], bg.color[2], bg.color[3], bg.color[4])

        if border.enabled then
            local bc, t = border.color, border.thickness
            DrawRect(screenX, rectY - rectHeight / 2, rectWidth, t, bc[1], bc[2], bc[3], bc[4]) -- top
            DrawRect(screenX, rectY + rectHeight / 2, rectWidth, t, bc[1], bc[2], bc[3], bc[4]) -- bund
            DrawRect(screenX - rectWidth / 2, rectY, t, rectHeight, bc[1], bc[2], bc[3], bc[4]) -- venstre
            DrawRect(screenX + rectWidth / 2, rectY, t, rectHeight, bc[1], bc[2], bc[3], bc[4]) -- højre
        end
    end

    if showId then DrawPlayerID(screenX, idY, idText, idColor) end
    if showName then DrawPlayerName(screenX, nameY, nameText, nameColor) end
end

-- ─── RENDER: ÉT PAS OVER DEN CACHEDE SPILLERLISTE ────────────────
local function RenderPlayerInfos()
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then return end

    local myCoords = GetEntityCoords(playerPed)

    for i = 1, cachedPlayerCount do
        local data = cachedPlayers[i]
        local ped = data.ped

        if IsPlayerValidForPeek(ped) then
            local pedCoords = GetEntityCoords(ped)
            local dx = pedCoords.x - myCoords.x
            local dy = pedCoords.y - myCoords.y
            local dz = pedCoords.z - myCoords.z
            local distSq = dx * dx + dy * dy + dz * dz

            -- Billig kvadreret afstand FØRST — undgår sqrt og undgår
            -- helt at bruge tid på LOS-raytrace/tegning for alt der er
            -- for langt væk til overhovedet at komme i betragtning.
            if distSq <= sqDistance then
                if IsPlayerVisible(playerPed, ped) then
                    local inVehicle = IsPedInAnyVehicle(ped, false)
                    local offset = inVehicle and Config.IDPeek.vehicleHeight or Config.IDPeek.height
                    local onScreen, screenX, screenY = World3dToScreen2d(pedCoords.x, pedCoords.y, pedCoords.z + offset)

                    if onScreen then
                        local distance = Config.IDPeek.distanceColors.enabled and math.sqrt(distSq) or 0
                        DrawPlayerInfo(screenX, screenY, tostring(data.serverId), data.displayName, distance)
                    end
                end
            end
        end
    end
end

-- ─── RENDER-LOOP (findes KUN mens ID-peek er tændt) ──────────────
local function StartRenderThread()
    if renderThreadRunning then return end
    renderThreadRunning = true

    CreateThread(function()
        RebuildPlayerCache()
        local lastCacheUpdate = GetGameTimer()

        while idModeActive do
            local now = GetGameTimer()
            if now - lastCacheUpdate >= Config.IDPeek.cacheInterval then
                RebuildPlayerCache()
                lastCacheUpdate = now
            end

            RenderPlayerInfos()
            Wait(0)
        end

        renderThreadRunning = false
    end)
end

-- ─── TOGGLE ──────────────────────────────────────────────────────
local function ToggleIdMode()
    idModeActive = not idModeActive

    if idModeActive then
        StartRenderThread()
    else
        -- Ingen grund til at holde på ped-referencer mens systemet er slukket.
        cachedPlayers = {}
        cachedPlayerCount = 0
    end
end

-- RegisterKeyMapping + RegisterCommand: INGEN permanent
-- input-polling-loop. FiveM kalder kun kommandoen når tasten rent
-- faktisk trykkes.
RegisterCommand('mpvp_toggleid', function()
    ToggleIdMode()
end, false)

RegisterKeyMapping('mpvp_toggleid', 'Vis spiller-ID + navn (MPvp)', 'keyboard', Config.IDPeek.key)

-- ─── CLEANUP ─────────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    idModeActive = false
    cachedPlayers = {}
    cachedPlayerCount = 0
end)
