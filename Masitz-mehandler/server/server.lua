-- ============================================================
--  Masitz-mehandler | server/server.lua
--
--  Denne fil gør kun ÉN ting: registrerer en simpel fallback
--  "/me"-kommando, HVIS OG KUN HVIS serveren ikke allerede har et
--  /me-system fra en anden ressource. Selve /me-afsendelsen fra
--  client.lua sker via ExecuteCommand, som allerede rammer et
--  eksisterende /me-system korrekt uden hjælp herfra.
-- ============================================================

local M = Config.MeHandler

local function DebugPrint(fmt, ...)
    if not M.Debug then return end
    print(('[Masitz-mehandler] ' .. fmt):format(...))
end

CreateThread(function()
    if not M.MeIntegration.RegisterFallback then
        DebugPrint('RegisterFallback er slået fra - registrerer ikke en fallback /me-kommando.')
        return
    end

    if M.MeIntegration.Mode ~= 'command' then
        DebugPrint('MeIntegration.Mode er ikke "command" - fallback /me-kommando er ikke relevant.')
        return
    end

    -- Lad andre ressourcer nå at registrere deres eget /me først.
    Wait(2000)

    local commandName = M.MeIntegration.Command
    local commands = GetRegisteredCommands()

    for i = 1, #commands do
        if commands[i].name == commandName then
            DebugPrint('Fandt allerede en registreret "/%s"-kommando - registrerer IKKE en fallback (undgår at overskrive jeres eksisterende /me-system).', commandName)
            return
        end
    end

    RegisterCommand(commandName, function(source, args)
        if source == 0 then return end -- kun spillere, ikke konsollen

        local message = table.concat(args, ' ')
        if message == '' then return end
        if #message > 200 then message = message:sub(1, 200) end

        local ped = GetPlayerPed(source)
        if ped == 0 then return end

        local coords = GetEntityCoords(ped)
        local playerName = GetPlayerName(source) or ('Ukendt (%s)'):format(source)
        local formatted = ('* %s %s'):format(playerName, message)

        for _, playerId in ipairs(GetPlayers()) do
            local targetPed = GetPlayerPed(playerId)
            if targetPed ~= 0 and #(coords - GetEntityCoords(targetPed)) <= 20.0 then
                TriggerClientEvent('chat:addMessage', tonumber(playerId), {
                    color = { 200, 200, 200 },
                    multiline = true,
                    args = { formatted },
                })
            end
        end
    end, false)

    DebugPrint('Ingen eksisterende "/%s"-kommando fundet - Masitz-mehandler har registreret en simpel fallback.', commandName)
end)
