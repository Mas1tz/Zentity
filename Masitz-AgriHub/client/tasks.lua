-- ============================================================
--  Masitz-AgriHub | client/tasks.lua
--  GENERISK task-klient — spawner det rigtige køretøj/trailer for
--  hver task-type, viser blip + ox_target-zone pr. stop, og kalder
--  reachStop server-side (som ALENE afgør om stoppet reelt er nået).
--
--  Ingen distance-polling-tråd: stop-fuldførelse sker via en
--  ox_target-zone (event-drevet), ikke et Wait(0)-loop der måler
--  afstand hvert frame.
-- ============================================================

AH = AH or {}
AH.ActiveTask = nil -- { taskId, type, data, reward, vehicle, trailer, zoneId, blip }

local function ClearTaskWorldState()
    if not AH.ActiveTask then return end
    if AH.ActiveTask.zoneId then
        exports.ox_target:removeZone(AH.ActiveTask.zoneId)
    end
    if AH.ActiveTask.blip and DoesBlipExist(AH.ActiveTask.blip) then
        RemoveBlip(AH.ActiveTask.blip)
    end
    AH.ActiveTask.zoneId = nil
    AH.ActiveTask.blip = nil
end

local function SpawnCoordsForGroup(group)
    if group == 'diesel' then return Config.Agri.Diesel.spawnCoords end
    if group == 'equipment' then return Config.Agri.Equipment.spawnCoords end
    if group == 'animals' then return Config.Agri.Animals.spawnCoords end
    return Config.Agri.Diesel.spawnCoords -- fælles gårdsplads, bruges også til 'delivery'
end

-- Beder serveren om en plade + nøgle til opgave-køretøjet, ligesom
-- udlejningsflowet i client/rental.lua.
local function ClaimVehicleForTask(taskId)
    local result = lib.callback.await('masitz_agrihub:tasks:requestVehicle', false, taskId)
    if not result or not result.success then
        lib.notify({ title = 'AgriHub', description = result and result.msg or 'Kunne ikke tildele et køretøj.', type = 'error' })
        return nil
    end
    return result.plate
end

local function SpawnTaskVehicle(taskType, typeCfg, meta, taskId)
    local group = typeCfg.vehicleGroup
    if group == 'rental' or not group then return nil, nil end -- machinery_npc: spilleren bruger sit eget lejede køretøj

    local plate = ClaimVehicleForTask(taskId)
    if not plate then return nil, nil end

    local coords = SpawnCoordsForGroup(group)
    local heading = coords.w or 0.0

    local model
    if group == 'diesel' then
        if Config.Agri.Diesel.autoAssign or #Config.Agri.Diesel.trucks == 1 then
            model = Config.Agri.Diesel.trucks[1]
        else
            local truckOptions = {}
            for _, truck in ipairs(Config.Agri.Diesel.trucks) do
                truckOptions[#truckOptions + 1] = { value = truck, label = truck }
            end
            local input = lib.inputDialog('Vælg lastbil', {
                { type = 'select', label = 'Køretøj', options = truckOptions, required = true },
            })
            model = (input and input[1]) or Config.Agri.Diesel.trucks[1]
        end
    elseif group == 'equipment' then
        model = Config.Agri.Equipment.towVehicle
    elseif group == 'animals' then
        model = Config.Agri.Animals.vehicle
    elseif group == 'delivery' then
        model = Config.Agri.DeliveryVehicles[math.random(1, #Config.Agri.DeliveryVehicles)]
    end
    if not model then return nil, nil end

    local veh = AH.SpawnVehicle(model, coords, heading, plate)
    if not veh and group == 'delivery' and #Config.Agri.DeliveryVehicles > 1 then
        -- Selv-helbredende: er den valgte model ugyldig (fx en fejl i
        -- config.lua), prøv én gang til med en anden tilfældig model i
        -- stedet for at lade opgaven fejle helt.
        model = Config.Agri.DeliveryVehicles[math.random(1, #Config.Agri.DeliveryVehicles)]
        veh = AH.SpawnVehicle(model, coords, heading, plate)
    end
    if not veh then
        lib.notify({ title = 'AgriHub', description = 'Køretøjet kunne ikke spawnes — kontakt en administrator.', type = 'error' })
        return nil, nil
    end

    TriggerServerEvent('masitz_agrihub:tasks:vehicleSpawned', plate)

    local trailer = nil
    if group == 'diesel' and meta.trailerModel then
        trailer = AH.AttachTrailer(veh, meta.trailerModel, coords, heading)
    elseif group == 'equipment' and meta.trailer then
        trailer = AH.AttachTrailer(veh, meta.trailer, coords, heading)
    end

    return veh, trailer
end

local function CreateStopZone(index, stop, typeCfg, meta)
    local coords = vec3(stop.coords.x, stop.coords.y, stop.coords.z)
    local label = 'Aflever her'
    if meta.stage == 'pickup' or (stop.meta and stop.meta.stage == 'pickup') then
        label = 'Hent her'
    elseif meta.stage == 'dropoff' or (stop.meta and stop.meta.stage == 'dropoff') then
        label = 'Afsæt her'
    end

    AH.ActiveTask.blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(AH.ActiveTask.blip, 478)
    SetBlipColour(AH.ActiveTask.blip, 5)
    SetBlipScale(AH.ActiveTask.blip, 0.9)
    SetBlipRoute(AH.ActiveTask.blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(typeCfg.label or 'AgriHub')
    EndTextCommandSetBlipName(AH.ActiveTask.blip)

    AH.ActiveTask.zoneId = exports.ox_target:addSphereZone({
        coords = coords,
        radius = 6.0,
        debug = Config.Agri.Debug,
        options = {
            {
                name = 'masitz_agrihub_task_stop',
                icon = typeCfg.icon and 'fa-solid fa-truck-ramp-box' or 'fa-solid fa-check',
                label = label,
                onSelect = function()
                    AH.CompleteStop(index)
                end,
            },
        },
    })
end

-- Kaldes fra client/nui.lua efter et vellykket 'claim'-svar fra serveren.
function AH.StartTask(task)
    if AH.ActiveTask then
        lib.notify({ title = 'AgriHub', description = 'Du har allerede en aktiv opgave.', type = 'error' })
        return
    end

    local ok, data = pcall(json.decode, task.data)
    if not ok or type(data) ~= 'table' then
        lib.notify({ title = 'AgriHub', description = 'Opgavedata kunne ikke læses.', type = 'error' })
        return
    end

    local typeCfg = Config.Agri.TaskTypes[task.type]
    if not typeCfg then return end

    AH.ActiveTask = {
        taskId = task.task_id, type = task.type, data = data, reward = task.reward,
        vehicle = nil, trailer = nil, zoneId = nil, blip = nil,
    }

    local veh, trailer = SpawnTaskVehicle(task.type, typeCfg, data.meta or {}, task.task_id)
    AH.ActiveTask.vehicle = veh
    AH.ActiveTask.trailer = trailer

    local firstIndex = nil
    for i, stop in ipairs(data.stops) do
        if not stop.done then firstIndex = i; break end
    end
    if firstIndex then
        CreateStopZone(firstIndex, data.stops[firstIndex], typeCfg, data.meta or {})
    end

    lib.notify({ title = typeCfg.label or 'AgriHub', description = 'Opgave startet — følg blip\'en til første stop.', type = 'inform' })
end

function AH.CompleteStop(index)
    if not AH.ActiveTask then return end

    local result = lib.callback.await('masitz_agrihub:tasks:reachStop', false, AH.ActiveTask.taskId, index)
    if not result or not result.success then
        lib.notify({ title = 'AgriHub', description = result and result.msg or 'Kunne ikke fuldføre stoppet.', type = 'error' })
        return
    end

    ClearTaskWorldState()

    if result.completed then
        lib.notify({ title = 'AgriHub', description = ('Opgave fuldført! Du modtog %d kr.'):format(result.reward), type = 'success' })

        -- Redskabs-levering: KUN traileren fjernes, tractor2 må gerne
        -- køres tilbage af spilleren (§ persisterer bevidst).
        AH.DeleteVehicleSafe(AH.ActiveTask.trailer)
        if AH.ActiveTask.type ~= 'equipment_delivery' then
            AH.DeleteVehicleSafe(AH.ActiveTask.vehicle)
        end

        AH.ActiveTask = nil
        return
    end

    local typeCfg = Config.Agri.TaskTypes[AH.ActiveTask.type]
    local nextStop = AH.ActiveTask.data.stops[result.nextIndex]
    if nextStop then
        CreateStopZone(result.nextIndex, nextStop, typeCfg, AH.ActiveTask.data.meta or {})
        lib.notify({ title = typeCfg.label or 'AgriHub', description = 'Næste stop markeret på kortet.', type = 'inform' })
    end
end

function AH.CancelActiveTask()
    if not AH.ActiveTask then return end
    local taskId = AH.ActiveTask.taskId
    local result = lib.callback.await('masitz_agrihub:tasks:cancel', false, taskId)
    if result and result.success then
        AH.DeleteVehicleSafe(AH.ActiveTask.trailer)
        AH.DeleteVehicleSafe(AH.ActiveTask.vehicle)
        ClearTaskWorldState()
        AH.ActiveTask = nil
        lib.notify({ title = 'AgriHub', description = 'Opgave annulleret.', type = 'inform' })
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    ClearTaskWorldState()
end)
