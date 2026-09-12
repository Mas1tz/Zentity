-- ============================================================
--  Masitz-garage | server/sv_helpers.lua
--  Delte hjælpefunktioner brugt af alle andre server-filer.
--  Loades FØRST (se fxmanifest.lua) så MG.* findes for alle andre.
-- ============================================================

MG = MG or {}

local ESX = exports['es_extended']:getSharedObject()
MG.ESX = ESX

-- ─── DEBUG ───────────────────────────────────────────────────
function MG.Log(msg)
    if Config.Debug then
        print(('[Masitz-garage] %s'):format(tostring(msg)))
    end
end

-- ─── PLATE NORMALISER ────────────────────────────────────────
function MG.NormPlate(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('%s+', ''):upper()
    if #plate == 0 then return nil end
    return plate
end

-- ─── SAFE xPlayer HENT ───────────────────────────────────────
function MG.GetXPlayer(src)
    local xp = ESX.GetPlayerFromId(src)
    if not xp then MG.Log('WARN: xPlayer nil for source ' .. tostring(src)) end
    return xp
end

-- ─── PENGEFORMATERING (§9) — dansk tusind-separator ───────────
-- Eksempel: 2500000 -> "2.500.000 kr."
function MG.FormatMoney(amount)
    amount = math.floor(tonumber(amount) or 0)
    local sign = amount < 0 and '-' or ''
    amount = math.abs(amount)
    local formatted = tostring(amount):reverse():gsub('(%d%d%d)', '%1.'):reverse():gsub('^%.', '')
    return sign .. formatted .. ' kr.'
end

-- ─── MONEY / BANK (§27) — ren ESX Legacy, intet nyt economy-system ──
function MG.GetBalance(xp, method)
    if method == 'bank' then
        local acc = xp.getAccount('bank')
        return acc and acc.money or 0
    end
    return xp.getMoney() or 0
end

-- Returnerer true/false. Trækker ALDRIG penge hvis saldoen er utilstrækkelig.
function MG.TryCharge(xp, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if MG.GetBalance(xp, method) < amount then return false end
    if method == 'bank' then
        xp.removeAccountMoney('bank', amount)
    else
        xp.removeMoney(amount)
    end
    return true
end

function MG.Pay(xp, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    if method == 'bank' then
        xp.addAccountMoney('bank', amount)
    else
        xp.addMoney(amount)
    end
end

-- ─── BEREGN IMPOUND GEBYR ────────────────────────────────────
function MG.CalcImpoundFee(impoundAt)
    if not impoundAt then return Config.ImpoundBaseFee end
    local diff  = os.time() - impoundAt
    local hours = math.ceil(diff / 3600)
    local fee   = Config.ImpoundBaseFee + (hours * Config.ImpoundPerHour)
    return math.min(fee, Config.ImpoundMaxFee)
end

-- ─── PARSE MYSQL DATETIME → unix timestamp ────────────────────
function MG.ParseSqlDatetime(s)
    if not s then return nil end
    s = tostring(s)
    return os.time({
        year = tonumber(s:sub(1, 4)),  month = tonumber(s:sub(6, 7)),
        day  = tonumber(s:sub(9, 10)), hour  = tonumber(s:sub(12, 13)),
        min  = tonumber(s:sub(15, 16)), sec  = tonumber(s:sub(18, 19)),
    })
end

-- ─── SIKKERT BILNAVN (§5) ──────────────────────────────────────
-- Reel SQL-injection-beskyttelse kommer fra parameteriserede queries
-- (bruges konsekvent i hele resourcen) — denne funktion beskytter i
-- stedet mod visnings-/chat-exploit (farvekoder, styretegn, spam) ved
-- kun at tillade et sikkert tegnsæt, og håndhæver en maks-længde.
function MG.SafeVehicleName(raw)
    if type(raw) ~= 'string' then return nil end
    local s = raw:gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    s = s:gsub(Config.VehicleName.allowedPattern, '')
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    if s == '' then return nil end
    if #s > Config.VehicleName.maxLength then
        s = s:sub(1, Config.VehicleName.maxLength)
    end
    return s
end

-- ─── DISTANCE MELLEM TO GARAGER (bruges af sv_transfer.lua) ───
function MG.GarageDistance(garageA, garageB)
    if not garageA or not garageB then return 0.0 end
    return #(garageA.access - garageB.access)
end
