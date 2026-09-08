-- ============================================================
-- MM-PolitiJob - client/state.lua
-- Central state machine. Al state læses/skrives her.
-- Bruger LocalPlayer.state (statebag) til synkronisering.
--
-- Der er INGEN duty-state. Reglen er:
--   player.job.name == "police" (eller andet job i Config.PoliceJobs)
--   => spilleren er automatisk aktiv i politi-systemet.
-- ============================================================

MM       = MM or {}
MM.State = {}

-- ── LOKAL STATE ──────────────────────────────────────────────
MM.State.jobName      = nil
MM.State.jobGrade     = 0
MM.State.hasPoliceJob = false
MM.State.isHandcuffed = false
MM.State.handcuffMode = nil     -- 'soft' | 'hard'
MM.State.isEscorted   = false
MM.State.isDead       = false
MM.State.inVehicle    = false
MM.State.currentZone  = nil

-- ── UPDATE JOB ───────────────────────────────────────────────
function MM.State.UpdateJob(jobName, grade)
    MM.State.jobName  = jobName
    MM.State.jobGrade = grade or 0

    local wasPolice = MM.State.hasPoliceJob
    local isPolice  = false
    for _, j in ipairs(Config.PoliceJobs) do
        if j == jobName then
            isPolice = true
            break
        end
    end
    MM.State.hasPoliceJob = isPolice

    -- Statebag til sync (andre klienter/serveren kan læse dette)
    LocalPlayer.state:set('jobName',      jobName,  false)
    LocalPlayer.state:set('hasPoliceJob', isPolice, false)

    -- Notificér resten af resource'en lokalt, i stedet for at hver
    -- fil skal registrere sine egne esx:setJob / QBCore job handlers.
    if wasPolice ~= isPolice then
        TriggerEvent('mm:policeStatusChanged', isPolice)
    end
end

-- ── HANDCUFFS ────────────────────────────────────────────────
function MM.State.SetHandcuffed(state, mode)
    MM.State.isHandcuffed = state
    MM.State.handcuffMode = state and mode or nil
    LocalPlayer.state:set('isHandcuffed', state, true)
    LocalPlayer.state:set('handcuffMode', MM.State.handcuffMode, true)
end

-- ── ESCORT ───────────────────────────────────────────────────
function MM.State.SetEscorted(state)
    MM.State.isEscorted = state
    LocalPlayer.state:set('isEscorted', state, true)
end

-- ── DEAD ─────────────────────────────────────────────────────
function MM.State.SetDead(state)
    MM.State.isDead = state
    LocalPlayer.state:set('isDead', state, true)
end

-- ── VEHICLE ──────────────────────────────────────────────────
function MM.State.SetInVehicle(state)
    MM.State.inVehicle = state
end

-- ── ZONE ─────────────────────────────────────────────────────
function MM.State.SetZone(zoneName)
    MM.State.currentZone = zoneName
end

-- ── DEATH MONITOR ────────────────────────────────────────────
-- Opdaterer isDead løbende - billig loop, gælder alle spillere
CreateThread(function()
    while true do
        Wait(1000)
        local ped  = cache.ped
        local dead = IsEntityDead(ped) or IsPedDeadOrDying(ped, true)
        if dead ~= MM.State.isDead then
            MM.State.SetDead(dead)
        end
    end
end)

-- ── VEHICLE MONITOR ──────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(500)
        local inVeh = GetVehiclePedIsIn(cache.ped, false) ~= 0
        if inVeh ~= MM.State.inVehicle then
            MM.State.SetInVehicle(inVeh)
        end
    end
end)
