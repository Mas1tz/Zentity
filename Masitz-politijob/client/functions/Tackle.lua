-- ============================================================
--  MM-PolitiJob - client/functions/Tackle.lua
-- ============================================================

local isTackling = false

-- Shift + E for at tackle
-- Shift = control 21 (LEFT SHIFT)
-- E     = control 38
--
-- PERFORMANCE FIX: løkken sov tidligere Wait(0) permanent, uanset
-- job. Nu sover den langt langsommere når spilleren ikke er politi,
-- og kun i tight-loop mens spilleren rent faktisk er politi.
CreateThread(function()
    while true do
        if MM.State and MM.State.hasPoliceJob then
            Wait(0)
            if IsControlPressed(0, 21) and IsControlJustPressed(0, 38) then
                local ped = cache.ped
                if IsPedJumping(ped) then
                    MM.TacklePlayer()
                end
            end
        else
            Wait(1000)
        end
    end
end)

function MM.TacklePlayer()
    local ped = cache.ped
    if IsPedInAnyVehicle(ped, false) then return end
    if isTackling then return end

    local tackled       = {}
    local forwardVector  = GetEntityForwardVector(ped)

    SetPedToRagdollWithFall(ped, 1000, 1500, 1,
        forwardVector, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

    isTackling = true

    CreateThread(function()
        while IsPedRagdoll(ped) do
            Wait(0)
            for _, playerId in ipairs(MM.GetTouchedPlayers(ped)) do
                if not tackled[playerId] then
                    tackled[playerId] = true
                    TriggerServerEvent('mm_police:server:tacklePlayer',
                        GetPlayerServerId(playerId),
                        forwardVector.x, forwardVector.y, forwardVector.z)
                end
            end
        end
        isTackling = false
    end)
end

-- Modtag tackle fra en anden spiller
RegisterNetEvent('mm_police:client:tacklePlayer', function(fx, fy, fz)
    SetPedToRagdollWithFall(cache.ped, 3000, 4000, 1,
        fx, fy, fz, 10.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
end)

function MM.GetTouchedPlayers(ped)
    local pedCoords = GetEntityCoords(ped)
    local touched    = {}

    for _, playerId in ipairs(GetActivePlayers()) do
        if playerId ~= PlayerId() then
            local otherPed = GetPlayerPed(playerId)
            if DoesEntityExist(otherPed) then
                local dist = #(pedCoords - GetEntityCoords(otherPed))
                if dist <= 5.0 and IsEntityTouchingEntity(ped, otherPed) then
                    touched[#touched + 1] = playerId
                end
            end
        end
    end

    return touched
end
