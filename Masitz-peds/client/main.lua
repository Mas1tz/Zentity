-- ============================================================
--  Masitz-peds | client/main.lua
--  Bootstrap + DET ENESTE loop i hele resourcen: distance-baseret
--  spawn/despawn + TextUI-nærhed. Wait-intervallet er adaptivt —
--  langt fra alt = langt Wait, tæt på en TextUI-ped = Wait(0) KUN
--  så længe det varer.
-- ============================================================

PEDS = PEDS or {}

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[Masitz-peds] ' .. fmt):format(...))
    end
end

-- ─── GENBRUGTE BUFFERE (undgår tabel-allokering hvert tick) ───────
-- Vokser højst til det største antal samtidige TextUI-kandidater der
-- nogensinde er set — allokeres aldrig på ny efter det.
local textUiCandidates = {}
local textUiCandidateCount = 0

local WAIT_IDLE = 1000  -- ingen ped inden for spawnDistance
local WAIT_NEAR = 250   -- mindst én ped inden for spawnDistance, ingen TextUI-nærhed
local WAIT_ACTIVE = 0   -- inden for en TextUI-peds interaktions-afstand

local function MainLoop()
    while true do
        local playerCoords = GetEntityCoords(PlayerPedId())
        local px, py, pz = playerCoords.x, playerCoords.y, playerCoords.z

        local anyNear = false
        textUiCandidateCount = 0

        for id, state in pairs(PEDS.Runtime) do
            local cfg = state.config
            local c = cfg.coords
            local dx, dy, dz = c.x - px, c.y - py, c.z - pz
            local distSq = dx * dx + dy * dy + dz * dz

            if not state.spawned and not state.pending then
                if distSq <= cfg.spawnDistanceSq then
                    PEDS.CreateConfiguredPed(id)
                end
            elseif state.spawned and distSq > cfg.despawnDistanceSq then
                PEDS.DeleteConfiguredPed(id)
            end

            if distSq <= cfg.spawnDistanceSq then
                anyNear = true
            end

            if state.spawned and cfg.textui and cfg.textui.enabled and distSq <= cfg.textui.distanceSq then
                if PEDS.EvaluateCanInteract(cfg.textui, state.entity, nil, cfg.coords, nil, nil) then
                    textUiCandidateCount = textUiCandidateCount + 1
                    local slot = textUiCandidates[textUiCandidateCount]
                    if not slot then
                        slot = {}
                        textUiCandidates[textUiCandidateCount] = slot
                    end
                    slot.id = id
                    slot.distSq = distSq
                end
            end
        end

        -- Find nærmeste TextUI-kandidat uden at allokere en ny tabel.
        local nearestId = nil
        if textUiCandidateCount > 0 then
            local nearestDistSq = math.huge
            for i = 1, textUiCandidateCount do
                local c = textUiCandidates[i]
                if c.distSq < nearestDistSq then
                    nearestDistSq = c.distSq
                    nearestId = c.id
                end
            end
        end

        if nearestId ~= PEDS.CurrentTextUiPedId then
            if PEDS.CurrentTextUiPedId then PEDS.HideTextUi() end
            if nearestId then PEDS.ShowTextUi(nearestId) end
        end

        if nearestId then
            local cfg = PEDS.Runtime[nearestId].config
            if IsControlJustReleased(0, PEDS.GetTextUiControl(cfg)) then
                PEDS.TriggerAction(cfg.textui, nearestId, nil)
            end
            Wait(WAIT_ACTIVE)
        elseif anyNear then
            Wait(WAIT_NEAR)
        else
            Wait(WAIT_IDLE)
        end
    end
end

-- ─── RESOURCE LIFECYCLE ────────────────────────────────────────────
CreateThread(function()
    PEDS.InitRuntime()
    DebugPrint('%d gyldig(e) ped-konfiguration(er) indlæst.', #Config.Peds)
    MainLoop()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end

    PEDS.HideTextUi()
    for id in pairs(PEDS.Runtime) do
        PEDS.CleanupPed(id)
    end

    DebugPrint('Resource stoppet — alle peds/targets/TextUI ryddet op.')
end)
