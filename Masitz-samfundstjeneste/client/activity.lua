--[[
    Aktivitetstjek til trust factor-recovery. Kører HELE tiden (ikke kun
    i tjeneste), fordi recovery skal kunne ske mens spilleren bare spiller
    normalt på serveren — ikke kun mens de udfører samfundstjeneste.

    Et "aktivt" tick kræver ÉT af:
      - spillerens koordinater har flyttet sig mere end en lille tærskel
      - kameraets retning (heading) har ændret sig
      - der er registreret et faktisk gameplay-kontrol-tryk

    Det gør det markant sværere at snyde med fx en anti-AFK-makro der kun
    holder én enkelt tast nede eller vender kameraet ubetydeligt — den skal
    reelt bevæge SPILLEREN eller ramme en rigtig kontrol for at tælle.
]]

local PING_INTERVAL_MS = 15000
local MOVE_THRESHOLD = 0.15

-- Et lille udvalg af "rigtige" gameplay-kontroller (bevægelse, hop, angreb,
-- interaktion, køretøj) — bevidst IKKE alle kontroller, så det ikke er nok
-- bare at spamme en helt vilkårlig, ubrugt tast.
local WATCHED_CONTROLS = {
    [30] = true, [31] = true, -- move left/right
    [32] = true, [33] = true, -- move fwd/back
    [22] = true,              -- jump
    [24] = true, [25] = true, -- attack / aim
    [38] = true,              -- interact (E)
    [71] = true, [72] = true, -- vehicle accel/brake
}

local lastCoords = nil
local lastHeading = nil

local function HasRealInput()
    for control in pairs(WATCHED_CONTROLS) do
        if IsControlPressed(0, control) or IsDisabledControlPressed(0, control) then
            return true
        end
    end
    return false
end

CreateThread(function()
    while true do
        Wait(PING_INTERVAL_MS)

        local ped = PlayerPedId()
        local coords = GetEntityCoords(ped)
        local heading = GetEntityHeading(ped)

        local moved = lastCoords and #(coords - lastCoords) > MOVE_THRESHOLD
        local turned = lastHeading and math.abs(heading - lastHeading) > 2.0
        local input = HasRealInput()

        lastCoords = coords
        lastHeading = heading

        if moved or turned or input then
            TriggerServerEvent('mm_sf:server:activityPing')
        end
    end
end)
