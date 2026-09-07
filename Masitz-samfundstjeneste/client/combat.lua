--[[
    client/combat.lua — blokerer vold (skydevåben + melee) for DENNE
    spiller, udelukkende mens de selv er i aktiv samfundstjeneste
    (Service.active). Ingen globale control-disables, ingen indgreb i
    våben-udstyr/inventory-state — kun de rene angrebs-kontroller
    disables, og kun lokalt for spilleren selv, hvert frame mens loopet
    kører. Ingen effekt på ox_inventory (våben skiftes/åbnes/lukkes helt
    normalt, kun selve angrebet blokeres), ox_target, pma-voice eller
    andre resources.
]]

-- INPUT_ATTACK (dækker også ubevæbnet slag), INPUT_ATTACK2, samt de tre
-- dedikerede melee-kontroller. Bevidst IKKE bredere end det - fx sigte
-- (25), våbenhjul (37) og inventory-kontroller rører vi slet ikke, da
-- selve skuddet allerede forhindres af DisablePlayerFiring uden at skulle
-- blokere andet.
local COMBAT_CONTROLS = { 24, 257, 140, 141, 142 }

local restricting = false

local function StartCombatRestriction()
    if restricting then return end
    restricting = true

    CreateThread(function()
        while Service.active and restricting do
            local playerId = PlayerId()

            DisablePlayerFiring(playerId, true)
            SetPlayerCanDoDriveBy(playerId, false)

            for _, control in ipairs(COMBAT_CONTROLS) do
                DisableControlAction(0, control, true)
            end

            Wait(0)
        end
        restricting = false
    end)
end

local function StopCombatRestriction()
    restricting = false

    -- Eksplicit gendannelse - DisablePlayerFiring/DriveBy er ikke rent
    -- per-frame-tilstande på samme måde som DisableControlAction, så vi
    -- sætter dem eksplicit tilbage i stedet for blot at stoppe loopet.
    local playerId = PlayerId()
    DisablePlayerFiring(playerId, false)
    SetPlayerCanDoDriveBy(playerId, true)
end

AddEventHandler('mm_sf:client:startService', function()
    StartCombatRestriction()
end)

AddEventHandler('mm_sf:client:stopService', function()
    StopCombatRestriction()
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    StopCombatRestriction()
end)
