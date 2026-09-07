--[[
    ============================================================================
    Masitz-Anticheat — anti-nummerplade — client.lua
    ============================================================================

    VIGTIGT: Dette script er IKKE en del af sikkerhedsgrænsen. Alt herfra er
    per definition potentielt kompromitteret (stoppet resource, hooket native,
    manipuleret Lua/memory) og bliver ALDRIG brugt af serveren som grundlag
    for en sikkerhedsbeslutning.

    Klientens eneste opgave er at gøre server-side detektion HURTIGERE ved at
    sende et let, rate-limited "hint" når den lokale spillers eget køretøj ser
    ud til at have skiftet plade - serveren læser altid selv den faktiske
    plade via en native og træffer selv beslutningen. Mister klienten dette
    script helt (stoppet resource, crashet), taber serveren intet: den
    event-drevne (driver-enter) og periodiske sweep-baserede detektion på
    serveren fungerer uafhængigt af klienten.

    Der er bevidst IKKE implementeret noget heartbeat-system ("client svarer
    ikke = cheater") - den slags naive systemer skaber massive false positives
    ved bl.a. lag, loading screens og resource-genstarter (se spec punkt 27).
]]

if not Config or not Config.AntiNummerplade or not Config.AntiNummerplade.Enabled then
    return
end

local C = Config.AntiNummerplade

local function DebugPrint(fmt, ...)
    if C.Debug then
        print(("^5[Masitz-Anticheat] [Anti-Nummerplade] [DEBUG]^0 " .. fmt):format(...))
    end
end

local lastKnownPlate = nil
local lastVehicle = nil

-- Only polls while the local player is actually driving a vehicle, and at a
-- low frequency - this is a UX/latency optimization, not a security control,
-- so there is no reason to poll aggressively or while on foot.
CreateThread(function()
    while true do
        local sleep = 2000

        local ped = PlayerPedId()
        if ped and ped ~= 0 and IsPedInAnyVehicle(ped, false) then
            local vehicle = GetVehiclePedIsIn(ped, false)
            if vehicle ~= 0 and GetPedInVehicleSeat(vehicle, -1) == ped then
                if vehicle ~= lastVehicle then
                    lastVehicle = vehicle
                    local ok, plate = pcall(GetVehicleNumberPlateText, vehicle)
                    lastKnownPlate = ok and plate or nil
                else
                    local ok, plate = pcall(GetVehicleNumberPlateText, vehicle)
                    if ok and plate and lastKnownPlate and plate ~= lastKnownPlate then
                        local netId = NetworkGetNetworkIdFromEntity(vehicle)
                        if netId and netId ~= 0 then
                            DebugPrint("Local plate drift observed on driven vehicle (netId=%s) - sending hint to server.", netId)
                            TriggerServerEvent("masitz_anticheat:anp:hintCheck", netId)
                        end
                        lastKnownPlate = plate
                    end
                end
            else
                lastVehicle = nil
                lastKnownPlate = nil
            end
        else
            if lastVehicle ~= nil then
                lastVehicle = nil
                lastKnownPlate = nil
            end
            sleep = 3000
        end

        Wait(sleep)
    end
end)
