--[[
    Ren rapportering — selve autoriteten (er spilleren FAKTISK udenfor
    zonen, skal pausen sættes, teleport tilbage) ligger 100% server-side
    i server/antiescape.lua. Denne thread kører kun mens klienten selv
    mener at Service.active er true, men serveren tjekker Players[..].inService
    igen alligevel.
]]

CreateThread(function()
    while true do
        local wait = 1000

        if Service.active and Service.siteKey then
            local site = Config.Samfundstjeneste.Sites[Service.siteKey]

            if site and Config.Samfundstjeneste.AntiEscape.enabled then
                wait = Config.Samfundstjeneste.AntiEscape.checkInterval

                local coords = GetEntityCoords(PlayerPedId())
                local distance = #(coords - site.antiEscape.center)

                if distance > site.antiEscape.radius then
                    TriggerServerEvent('mm_sf:server:escapeDetected')
                end
            end
        end

        Wait(wait)
    end
end)
