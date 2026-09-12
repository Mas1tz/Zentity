-- ============================================================
--  Masitz-garage | client/cl_helpers.lua
--  Delte hjælpefunktioner brugt af cl_garage.lua og cl_menus.lua.
--  Loades FØRST (se fxmanifest.lua) så MGC.* findes for alle andre.
-- ============================================================

MGC = MGC or {}

-- ─── DEBUG ───────────────────────────────────────────────────
function MGC.Log(msg)
    if Config.Debug then
        print(('[Masitz-garage:client] %s'):format(tostring(msg)))
    end
end

-- ─── PLATE NORMALISER ────────────────────────────────────────
function MGC.NormPlate(plate)
    if not plate then return nil end
    return tostring(plate):gsub('%s+', ''):upper()
end

-- ─── PENGEFORMATERING (§9) — samme danske format som server ───
function MGC.FormatMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local sign = amount < 0 and '-' or ''
    amount = math.abs(amount)
    local formatted = tostring(amount):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return sign .. formatted .. ' kr.'
end

-- ─── FUEL INTEGRATION ────────────────────────────────────────
function MGC.GetFuel(veh)
    if Config.FuelSystem == 'ox_fuel' then
        local fuel = Entity(veh).state.fuel
        return (type(fuel) == 'number') and fuel or GetVehicleFuelLevel(veh) or Config.DefaultFuel
    elseif Config.FuelSystem == 'LegacyFuel' then
        local ok, v = pcall(exports['LegacyFuel'].GetFuel, exports['LegacyFuel'], veh)
        return (ok and type(v) == 'number') and v or Config.DefaultFuel
    elseif Config.FuelSystem == 'cdn-fuel' then
        local ok, v = pcall(exports['cdn-fuel'].GetFuel, exports['cdn-fuel'], veh)
        return (ok and type(v) == 'number') and v or Config.DefaultFuel
    end
    return GetVehicleFuelLevel(veh) or Config.DefaultFuel
end

function MGC.SetFuel(veh, level)
    level = math.max(0.0, math.min(100.0, tonumber(level) or Config.DefaultFuel))
    if Config.FuelSystem == 'ox_fuel' then
        Entity(veh).state.fuel = level
    elseif Config.FuelSystem == 'LegacyFuel' then
        pcall(exports['LegacyFuel'].SetFuel, exports['LegacyFuel'], veh, level)
    elseif Config.FuelSystem == 'cdn-fuel' then
        pcall(exports['cdn-fuel'].SetFuel, exports['cdn-fuel'], veh, level)
    else
        SetVehicleFuelLevel(veh, level)
    end
end

-- ─── VEHICLE PROPS ────────────────────────────────────────────
function MGC.GetVehicleProps(veh)
    if not DoesEntityExist(veh) then return nil end
    local props = lib.getVehicleProperties(veh)
    if not props then return nil end
    props.plate        = MGC.NormPlate(GetVehicleNumberPlateText(veh))
    props.engineHealth = Config.SaveEngineHealth and GetVehicleEngineHealth(veh) or Config.DefaultEngine
    props.bodyHealth   = Config.SaveBodyHealth   and GetVehicleBodyHealth(veh)   or Config.DefaultBody
    props.fuelLevel    = Config.SaveFuel and MGC.GetFuel(veh) or Config.DefaultFuel
    return props
end

function MGC.SetVehicleProps(veh, props)
    if not DoesEntityExist(veh) or type(props) ~= 'table' then return end
    lib.setVehicleProperties(veh, props)
    if props.engineHealth then SetVehicleEngineHealth(veh, props.engineHealth + 0.0) end
    if props.bodyHealth   then SetVehicleBodyHealth(veh,   props.bodyHealth   + 0.0) end
    if props.fuelLevel    then MGC.SetFuel(veh, props.fuelLevel) end
end

-- ─── VEHICLE LABEL ───────────────────────────────────────────
function MGC.GetVehicleLabel(model)
    if not model then return 'Køretøj' end
    local hash = type(model) == 'number' and model or GetHashKey(model)
    local disp = GetDisplayNameFromVehicleModel(hash)
    local lbl  = GetLabelText(disp)
    if lbl and lbl ~= 'NULL' and lbl ~= '' then return lbl end
    return disp ~= 'NULL' and disp or tostring(model)
end

-- Vis brugerens eget bilnavn hvis sat (§5), ellers mærke/model-labelen.
function MGC.GetDisplayName(vehicleName, model)
    if vehicleName and vehicleName ~= '' then return vehicleName end
    return MGC.GetVehicleLabel(model)
end

-- ─── KØRETØJETS STAND (§22) — ÉN central beregning, brugt af
--     både bil- og bådmenuen. Bredere, mere realistiske tærskler
--     end tidligere, så let skade ikke straks vælter statussen. ──
function MGC.GetConditionInfo(engineHealth, bodyHealth)
    local engPct = math.floor(((tonumber(engineHealth) or 1000) / 1000) * 100 + 0.5)
    local bodyPct = math.floor(((tonumber(bodyHealth) or 1000) / 1000) * 100 + 0.5)
    engPct = math.max(0, math.min(100, engPct))
    bodyPct = math.max(0, math.min(100, bodyPct))
    local avg = math.floor((engPct + bodyPct) / 2)

    local text, colorScheme
    if avg >= 95 then      text, colorScheme = 'Perfekt',   'green'
    elseif avg >= 80 then  text, colorScheme = 'Meget god',  'lime'
    elseif avg >= 60 then  text, colorScheme = 'God',        'yellow'
    elseif avg >= 40 then  text, colorScheme = 'Slidt',      'orange'
    elseif avg >= 20 then  text, colorScheme = 'Dårlig',     'red'
    else                   text, colorScheme = 'Kritisk',    'red'
    end

    return { text = text, colorScheme = colorScheme, avg = avg, engPct = engPct, bodyPct = bodyPct }
end
