-- ============================================================
--  MPvp-idmenu | client/main.lua
--  Rent ID-peek: PAGE DOWN toggler visning af server-ID over andre
--  spillere. INGEN menu, INGEN NUI, INGEN server-events.
--
--  PERFORMANCE-DESIGN:
--  - Når ID-peek er OFF: intet loop, ingen native-kald, 0.00ms.
--  - Når ID-peek er ON: ét render-loop (skal køre hvert frame, da
--    GTA's text/rect-natives kun holder i ét frame ad gangen), men
--    den TUNGE del (GetActivePlayers/GetPlayerServerId/GetPlayerPed)
--    sker kun hvert Config.CacheInterval ms via en lille cache — ikke
--    hvert frame.
--  - Ingen permanent input-polling-loop: tasten bruger
--    RegisterKeyMapping + RegisterCommand, som FiveM selv håndterer
--    uden nogen konstant Wait(0)-loop.
-- ============================================================

local idModeActive = false
local renderThreadRunning = false

-- { { playerIndex = , serverId = , ped = }, ... } — genopbygges kun
-- periodisk mens ID-peek er aktivt, ikke hvert frame.
local cachedPlayers = {}

local sqDistance = Config.Distance * Config.Distance

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
                }
            end
        end
    end

    cachedPlayers = list
end

-- ─── TEKST-BREDDE (til badge-baggrunden) ─────────────────────────
local function GetRenderedTextWidth(text, font, scale)
    SetTextFont(font)
    SetTextScale(scale, scale)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    return GetTextScreenWidth(true)
end

local function ResolveTextColor(distance)
    local dc = Config.DistanceColors
    if not dc.enabled then return Config.Text.color end
    if distance <= dc.close.distance then return dc.close.color end
    if distance <= dc.medium.distance then return dc.medium.color end
    return dc.far.color
end

-- ─── TEGNING AF ÉT ID-BADGE ───────────────────────────────────────
local function DrawIdBadge(screenX, screenY, text, color)
    local txt = Config.Text
    local bg = Config.Background
    local border = Config.Border

    if bg.enabled then
        local textWidth = GetRenderedTextWidth(text, txt.font, txt.scale)
        local rectWidth = textWidth + bg.paddingX * 2
        local rectHeight = (txt.scale * 0.9) * 0.055 + bg.paddingY * 2
        -- GTA's DrawText tegner fra en baseline lidt over det angivne
        -- Y — dette lille løft centrerer boksen visuelt om teksten.
        local rectY = screenY + rectHeight * 0.18

        DrawRect(screenX, rectY, rectWidth, rectHeight, bg.color[1], bg.color[2], bg.color[3], bg.color[4])

        if border.enabled then
            local bc, t = border.color, border.thickness
            DrawRect(screenX, rectY - rectHeight / 2, rectWidth, t, bc[1], bc[2], bc[3], bc[4]) -- top
            DrawRect(screenX, rectY + rectHeight / 2, rectWidth, t, bc[1], bc[2], bc[3], bc[4]) -- bund
            DrawRect(screenX - rectWidth / 2, rectY, t, rectHeight, bc[1], bc[2], bc[3], bc[4]) -- venstre
            DrawRect(screenX + rectWidth / 2, rectY, t, rectHeight, bc[1], bc[2], bc[3], bc[4]) -- højre
        end
    end

    SetTextFont(txt.font)
    SetTextScale(txt.scale, txt.scale)
    SetTextProportional(true)
    SetTextCentre(true)
    SetTextColour(color[1], color[2], color[3], color[4])
    if txt.outline then SetTextOutline() end
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(screenX, screenY)
end

-- ─── RENDER: ÉT PAS OVER DEN CACHEDE SPILLERLISTE ────────────────
local function RenderPlayerIds()
    local playerPed = PlayerPedId()
    if not DoesEntityExist(playerPed) then return end

    local myCoords = GetEntityCoords(playerPed)
    local showDead = Config.ShowDeadPlayers
    local requireLos = Config.RequireLineOfSight

    for i = 1, #cachedPlayers do
        local data = cachedPlayers[i]
        local ped = data.ped

        if DoesEntityExist(ped) and (showDead or not IsEntityDead(ped)) then
            local pedCoords = GetEntityCoords(ped)
            local dx = pedCoords.x - myCoords.x
            local dy = pedCoords.y - myCoords.y
            local dz = pedCoords.z - myCoords.z
            local distSq = dx * dx + dy * dy + dz * dz

            -- Billig kvadreret afstand FØRST — undgår sqrt og undgår
            -- helt at bruge tid på LOS-raytrace/tegning for alt der er
            -- for langt væk til overhovedet at komme i betragtning.
            if distSq <= sqDistance then
                if not requireLos or HasEntityClearLosToEntity(playerPed, ped, 17) then
                    local offset = IsPedInAnyVehicle(ped, false) and Config.VehicleIdOffset or Config.PlayerIdOffset
                    local onScreen, screenX, screenY = World3dToScreen2d(pedCoords.x, pedCoords.y, pedCoords.z + offset)

                    if onScreen then
                        local color = Config.Text.color
                        if Config.DistanceColors.enabled then
                            color = ResolveTextColor(math.sqrt(distSq))
                        end
                        DrawIdBadge(screenX, screenY, tostring(data.serverId), color)
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
            if now - lastCacheUpdate >= Config.CacheInterval then
                RebuildPlayerCache()
                lastCacheUpdate = now
            end

            RenderPlayerIds()
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
    end
end

-- RegisterKeyMapping + RegisterCommand: INGEN permanent
-- input-polling-loop. FiveM kalder kun kommandoen når tasten rent
-- faktisk trykkes.
RegisterCommand('mpvp_toggleid', function()
    ToggleIdMode()
end, false)

RegisterKeyMapping('mpvp_toggleid', 'Vis spiller-ID (MPvp)', 'keyboard', Config.Key)

-- ─── CLEANUP ─────────────────────────────────────────────────────
AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    idModeActive = false
    cachedPlayers = {}
end)
