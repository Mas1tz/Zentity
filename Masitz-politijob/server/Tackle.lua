-- ============================================================
--  MM-PolitiJob – server/tackle.lua
-- ============================================================

RegisterNetEvent('mm_police:server:tacklePlayer', function(targetId, fx, fy, fz)
    local src = source

    -- Validering
    if not SV.Framework.IsPolice(src) then return end

    targetId = tonumber(targetId)
    if not targetId or not GetPlayerName(targetId) then return end
    if targetId == src then return end

    -- Afstand check
    local srcPed    = GetPlayerPed(src)
    local targetPed = GetPlayerPed(targetId)
    if not DoesEntityExist(srcPed) or not DoesEntityExist(targetPed) then return end

    local c1 = GetEntityCoords(srcPed)
    local c2 = GetEntityCoords(targetPed)
    if #(c1 - c2) > 6.0 then return end

    -- Send ragdoll til target
    TriggerClientEvent('mm_police:client:tacklePlayer', targetId, fx, fy, fz)
end)