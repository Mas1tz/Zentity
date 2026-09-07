--[[
    Holder den client-side "er jeg i tjeneste" state, som tasks.lua og
    antiescape.lua læser. Selve autoriteten ligger stadig server-side
    (Players[identifier].inService) — dette er kun en spejling så UI/task-
    threads ved hvornår de skal være aktive, uden at spamme serveren.
]]

Service = {
    active = false,
    siteKey = nil,
}

RegisterNetEvent('mm_sf:client:startService', function(siteKey, sendCoords, activeTasks)
    Service.active = true
    Service.siteKey = siteKey
    PlayerTaskState.activeTasks = tonumber(activeTasks) or PlayerTaskState.activeTasks or 0

    local ped = PlayerPedId()
    SetEntityCoords(ped, sendCoords.x, sendCoords.y, sendCoords.z, false, false, false, false)

    lib.notify({
        title = 'Samfundstjeneste',
        description = 'Du er blevet sendt til dit arbejdssted.',
        type = 'inform',
        position = 'center-right',
    })
end)

RegisterNetEvent('mm_sf:client:stopService', function()
    Service.active = false
    Service.siteKey = nil
end)

RegisterNetEvent('mm_sf:client:teleportBack', function(sendCoords)
    local ped = PlayerPedId()
    SetEntityCoords(ped, sendCoords.x, sendCoords.y, sendCoords.z, false, false, false, false)
end)
