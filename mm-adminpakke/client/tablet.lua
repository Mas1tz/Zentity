-- ============================================================
--  mm-adminpakke V2 | client/tablet.lua
--
--  Ét centralt system til tablet-prop + animation. Åbnes/lukkes
--  udelukkende via Tablet.Open()/Tablet.Close(), kaldt fra
--  client/main.lua i takt med NUI åbner/lukker - aldrig to
--  konkurrerende systemer, og aldrig mere end én aktiv prop.
-- ============================================================

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

local Tablet = {}

local tabletProp = nil
local tabletActive = false

--- Opretter prop + spiller animation. Er der allerede en aktiv prop
--- (fx dobbelt-kald), gøres intet - der må kun eksistere én ad gangen.
function Tablet.Open()
    if not Config.Tablet.Enabled then return end
    if tabletActive then return end

    local ped = PlayerPedId()
    local cfg = Config.Tablet

    if not lib.requestAnimDict(cfg.Dict, 2000) then
        DebugPrint('Kunne ikke loade animation dict %s - springer tablet-prop over.', cfg.Dict)
        return
    end

    tabletProp = CreateObject(cfg.Prop, 0.0, 0.0, 0.0, true, true, true)
    local bone = GetPedBoneIndex(ped, cfg.Bone)
    local off, rot = cfg.Offset, cfg.Rotation

    AttachEntityToEntity(tabletProp, ped, bone, off.x, off.y, off.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    TaskPlayAnim(ped, cfg.Dict, cfg.Anim, 8.0, -8.0, -1, cfg.Flag, 0, false, false, false)

    tabletActive = true
    DebugPrint('Tablet-prop og animation startet.')
end

--- Rydder prop + animation fuldstændigt op. Sikker at kalde flere
--- gange i træk (fx både fra NUI-luk og fra en death-handler).
function Tablet.Close()
    if tabletProp and DoesEntityExist(tabletProp) then
        DeleteEntity(tabletProp)
    end
    tabletProp = nil

    if tabletActive then
        ClearPedTasks(PlayerPedId())
    end
    tabletActive = false
    DebugPrint('Tablet-prop og animation ryddet op.')
end

function Tablet.IsActive()
    return tabletActive
end

-- ------------------------------------------------------------------
--  AUTOMATISK LUKNING VED SITUATIONER HVOR EN TABLET IKKE GIVER MENING
--  main.lua lytter selv på det faktiske NUI-luk og kalder Close() -
--  disse er UAFHÆNGIGE sikkerhedsnet for situationer hvor UI'et ikke
--  nødvendigvis får en pæn "close"-besked ud (død, køretøj, disconnect).
-- ------------------------------------------------------------------

local function ForceCloseEverything()
    if not Tablet.IsActive() then return end
    Tablet.Close()
    SendNUIMessage({ action = 'forceClose' })
    SetNuiFocus(false, false)
end

AddEventHandler('esx:onPlayerDeath', ForceCloseEverything)
AddEventHandler('baseevents:onPlayerDied', ForceCloseEverything)
AddEventHandler('esx:onPlayerLogout', ForceCloseEverything)

lib.onCache('vehicle', function(vehicle)
    if vehicle then ForceCloseEverything() end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    Tablet.Close()
end)

_G.Tablet = Tablet
