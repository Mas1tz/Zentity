-- ============================================================
-- MM-PolitiJob - client/main.lua
-- Core: framework init, markers, zone system
--
-- INGEN duty-system. police-job = automatisk aktiv.
-- ============================================================

-- ── INIT ─────────────────────────────────────────────────────
CreateThread(function()
    MM.Framework.Init(function(fw)
        -- Hent job ved login
        local job, grade = MM.Framework.GetJob()
        if job then MM.State.UpdateJob(job, grade) end
        if Config.Debug then
            print(('[MM-PolitiJob] Framework: ^3%s^7'):format(fw))
        end
    end)
end)

-- ── LOKALE HJÆLPERE ──────────────────────────────────────────
-- Central notify-wrapper — al client-side notify i resource'en bør
-- gå igennem denne (eller sætte position selv), så vi konsekvent kun
-- bruger 'center-right' eller 'bottom', aldrig ox_lib's default.
local function Notify(title, desc, ntype, duration, position)
    lib.notify({
        title       = title,
        description = desc,
        type        = ntype or 'inform',
        duration    = duration or 4000,
        position    = position or 'center-right',
    })
end

-- Eksponér til andre filer
MM.Notify = Notify

-- ── MARKER HJÆLPER ───────────────────────────────────────────
local function DrawM(cfg, offsetZ)
    DrawMarker(
        cfg.type,
        cfg.coords.x, cfg.coords.y, cfg.coords.z + (offsetZ or -0.2),
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        cfg.size.x, cfg.size.y, cfg.size.z,
        cfg.color.r, cfg.color.g, cfg.color.b, cfg.color.a,
        false, true, 2
    )
end

-- ── MARKER STATES ────────────────────────────────────────────
local markers = {
    garage = false,
    park   = false,
    heli   = false,
}

local function SetMarkerText(key, show, text)
    if show and not markers[key] then
        markers[key] = true
        lib.showTextUI(text, { position = 'top-center' })
    elseif not show and markers[key] then
        markers[key] = false
        lib.hideTextUI()
    end
end

-- ── MARKER LOOP ──────────────────────────────────────────────
CreateThread(function()
    while true do
        local sleep = 500
        local ped   = cache.ped
        local pos   = GetEntityCoords(ped)

        local gPos = Config.GarageMarker.coords
        local pPos = Config.ParkMarker.coords
        local hPos = Config.HeliMarker.coords

        local dGarage = #(pos - gPos)
        local dPark   = #(pos - pPos)
        local dHeli   = #(pos - hPos)

        -- ── GARAGE ──
        if dGarage < Config.GarageMarker.drawDist then
            sleep = 0
            DrawM(Config.GarageMarker)
            if dGarage < Config.GarageMarker.interactDist then
                SetMarkerText('garage', true, '[E] Åbn Politi Garage')
                if IsControlJustReleased(0, 38) then
                    if MM.Framework.IsPolice() then
                        exports['MM-politijob']:OpenGarageMenu()
                    else
                        Notify('Adgang nægtet', 'Du er ikke ansat i politiet.', 'error')
                    end
                end
            else
                SetMarkerText('garage', false)
            end
        else
            SetMarkerText('garage', false)
        end

        -- ── PARK ──
        if dPark < Config.ParkMarker.drawDist then
            sleep = 0
            DrawM(Config.ParkMarker, -0.8)
            if dPark < Config.ParkMarker.interactDist then
                SetMarkerText('park', true, '[E] Parkér politibil')
                if IsControlJustReleased(0, 38) then
                    exports['MM-politijob']:ParkVehicle()
                end
            else
                SetMarkerText('park', false)
            end
        else
            SetMarkerText('park', false)
        end

        -- ── HELI ──
        if dHeli < Config.HeliMarker.drawDist then
            sleep = 0
            DrawM(Config.HeliMarker)
            if dHeli < Config.HeliMarker.interactDist then
                SetMarkerText('heli', true, '[E] Åbn Helikopter Garage')
                if IsControlJustReleased(0, 38) then
                    if MM.Framework.IsPolice() then
                        exports['MM-politijob']:OpenHeliMenu()
                    else
                        Notify('Adgang nægtet', 'Du er ikke ansat i politiet.', 'error')
                    end
                end
            else
                SetMarkerText('heli', false)
            end
        else
            SetMarkerText('heli', false)
        end

        Wait(sleep)
    end
end)

-- ── BOSS MARKER ──────────────────────────────────────────────
local bossMarkerActive = false

CreateThread(function()
    while true do
        local sleep = 500
        local pos   = GetEntityCoords(cache.ped)
        local bPos  = Config.BossTargetCoords
        local dist  = #(pos - bPos)

        if dist < 20.0 then
            sleep = 0
            DrawMarker(1, bPos.x, bPos.y, bPos.z - 0.9,
                0, 0, 0, 0, 0, 0, 0.5, 0.5, 0.5,
                0, 132, 255, 100, false, true, 2)

            if dist < 2.0 then
                if not bossMarkerActive then
                    bossMarkerActive = true
                    lib.showTextUI('[E] Politi Ledelse', { position = 'top-center' })
                end
                if IsControlJustReleased(0, 38) then
                    if MM.Framework.IsPolice() and MM.Framework.HasMinGrade(Config.BossMinGrade) then
                        exports['MM-politijob']:OpenBossMenu()
                    else
                        Notify('Adgang nægtet', 'Du har ikke tilladelse til boss-menuen.', 'error')
                    end
                end
            elseif bossMarkerActive then
                bossMarkerActive = false
                lib.hideTextUI()
            end
        elseif bossMarkerActive then
            bossMarkerActive = false
            lib.hideTextUI()
        end

        Wait(sleep)
    end
end)

-- ── TARGET REGISTRERING NÅR KLAR ─────────────────────────────
CreateThread(function()
    while not MM.State do Wait(100) end
    Wait(500)
    if MM.RegisterPoliceTargets then
        MM.RegisterPoliceTargets()
    end
end)
