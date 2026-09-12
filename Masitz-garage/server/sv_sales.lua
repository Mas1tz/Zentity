-- ============================================================
--  Masitz-garage | server/sv_sales.lua
--  Spiller-til-spiller bilsalg (§7-§11). 100% server-autoritativ:
--  klienten sender kun ID/plade/pris-FORSLAG — serveren genvalidér
--  alt (ejerskab, pris, saldo, target online) igen ved selve
--  gennemførelsen, aldrig kun ved oprettelsen af tilbuddet.
-- ============================================================

local ActiveSales   = {}   -- [saleId]  = { ... }
local PlateSaleLock = {}   -- [plate]   = saleId

local function NewSaleId(plate)
    return ('%s-%d-%d'):format(plate, math.floor(GetGameTimer()), math.random(100000, 999999))
end

local function ReleaseSale(saleId)
    local sale = ActiveSales[saleId]
    if not sale then return end
    if PlateSaleLock[sale.plate] == saleId then
        PlateSaleLock[sale.plate] = nil
    end
    ActiveSales[saleId] = nil
end

-- ─── TRIN 1: sælger vælger køber + pris, ser navnet, bekræfter ────
-- (Navne-opslaget selv sker via masitz_garage:resolveTargetPlayer,
-- delt med sv_keys.lua — samme sikre mønster.)
lib.callback.register('masitz_garage:initiateSale', function(src, plate, targetIdRaw, priceRaw)
    local xp = MG.GetXPlayer(src)
    if not xp then return { ok = false, msg = 'Ikke logget ind.' } end

    plate = MG.NormPlate(plate)
    if not plate then return { ok = false, msg = 'Ugyldig nummerplade.' } end

    local price = math.floor(tonumber(priceRaw) or -1)
    if price < Config.Sale.minPrice or price > Config.Sale.maxPrice then
        return { ok = false, msg = 'Ugyldig pris.' }
    end

    local targetId = tonumber(targetIdRaw)
    if not targetId then return { ok = false, msg = 'Ugyldigt spiller-ID.' } end
    targetId = math.floor(targetId)
    if targetId == src then return { ok = false, msg = 'Du kan ikke sælge til dig selv.' } end

    local buyerXp = MG.GetXPlayer(targetId)
    if not buyerXp then return { ok = false, msg = 'Køberen findes ikke.' } end

    if PlateSaleLock[plate] then
        return { ok = false, msg = 'Der er allerede en aktiv handel for denne bil.' }
    end

    local row = MySQL.single.await(
        'SELECT vehicle, vehicle_name FROM owned_vehicles WHERE owner = ? AND REPLACE(plate," ","") = ? AND impound = 0',
        { xp.identifier, plate }
    )
    if not row then
        return { ok = false, msg = 'Du ejer ikke dette køretøj.' }
    end

    local ok, data = pcall(json.decode, row.vehicle or '{}')
    if not ok or type(data) ~= 'table' then data = {} end

    local saleId = NewSaleId(plate)
    PlateSaleLock[plate] = saleId
    ActiveSales[saleId] = {
        id               = saleId,
        plate            = plate,
        sellerSrc        = src,
        sellerIdentifier = xp.identifier,
        buyerSrc         = targetId,
        buyerIdentifier  = buyerXp.identifier,
        price            = price,
        vehicleModel     = data.model,
        vehicleName      = row.vehicle_name,
        status           = 'awaiting_buyer',
        createdAt        = os.time(),
        expiresAt        = os.time() + Config.Sale.timeoutSec,
    }

    TriggerClientEvent('masitz_garage:incomingSaleOffer', targetId, {
        saleId       = saleId,
        sellerName   = xp.getName(),
        plate        = plate,
        model        = data.model,
        vehicleName  = row.vehicle_name,
        price        = price,
        timeoutSec   = Config.Sale.timeoutSec,
    })

    MG.Log(('SALE: %s tilbød %s til %s for %d kr. (saleId=%s)'):format(xp.identifier, plate, buyerXp.identifier, price, saleId))
    return { ok = true, saleId = saleId, buyerName = buyerXp.getName() }
end)

-- ─── TRIN 2: køber godkender/afviser (med valgt betalingsmetode) ──
lib.callback.register('masitz_garage:confirmSale', function(src, saleId, paymentMethod)
    local sale = ActiveSales[saleId]
    if not sale then return { success = false, msg = 'Handlen findes ikke længere.' } end

    -- Alt herunder, indtil første MySQL-kald, kører SYNKRONT (ingen yield
    -- endnu) — det garanterer at et duplikeret/dobbelt-sendt event #2
    -- altid ser status == 'processing' og bliver afvist, uanset hvor
    -- tæt de to kald sendes efter hinanden (samme mønster som
    -- Masitz-Anticheat's PendingChange-mutex).
    if sale.status ~= 'awaiting_buyer' then
        return { success = false, msg = 'Handlen er allerede under behandling eller afsluttet.' }
    end
    if sale.buyerSrc ~= src then
        return { success = false, msg = 'Denne handel er ikke til dig.' }
    end
    if os.time() > sale.expiresAt then
        ReleaseSale(saleId)
        TriggerClientEvent('ox_lib:notify', sale.sellerSrc, { type = 'error', description = 'Handlen udløb.' })
        return { success = false, msg = 'Tilbuddet er udløbet.' }
    end
    if paymentMethod ~= 'cash' and paymentMethod ~= 'bank' then
        return { success = false, msg = 'Ugyldig betalingsmetode.' }
    end

    sale.status = 'processing'

    local buyerXp = MG.GetXPlayer(src)
    if not buyerXp then
        sale.status = 'awaiting_buyer'
        return { success = false, msg = 'Fejl: kunne ikke finde dig som spiller.' }
    end

    local sellerXp = MG.GetXPlayer(sale.sellerSrc)
    if not sellerXp then
        ReleaseSale(saleId)
        return { success = false, msg = 'Sælgeren er ikke længere online.' }
    end

    -- Genbekræft at sælgeren STADIG ejer bilen, og at den ikke er
    -- impounded i mellemtiden — prisen/pladen kommer aldrig fra klienten
    -- her, kun fra den serverlagrede `sale`.
    local currentOwner = MySQL.scalar.await(
        'SELECT owner FROM owned_vehicles WHERE REPLACE(plate," ","") = ? AND impound = 0',
        { sale.plate }
    )
    if currentOwner ~= sale.sellerIdentifier then
        ReleaseSale(saleId)
        TriggerClientEvent('ox_lib:notify', sale.sellerSrc, { type = 'error', description = 'Handlen kunne ikke gennemføres (bilen er ikke længere din/er impounded).' })
        return { success = false, msg = 'Bilen kan ikke længere sælges (ejerskab/impound ændret).' }
    end

    if MG.GetBalance(buyerXp, paymentMethod) < sale.price then
        sale.status = 'awaiting_buyer'
        return { success = false, msg = ('Du har ikke råd (%s).'):format(MG.FormatMoney(sale.price)) }
    end

    if not MG.TryCharge(buyerXp, paymentMethod, sale.price) then
        sale.status = 'awaiting_buyer'
        return { success = false, msg = 'Betaling fejlede.' }
    end

    local changed = MySQL.update.await(
        'UPDATE owned_vehicles SET owner = ? WHERE REPLACE(plate," ","") = ? AND owner = ? AND impound = 0',
        { sale.buyerIdentifier, sale.plate, sale.sellerIdentifier }
    )

    if not changed or changed < 1 then
        -- Rul betalingen tilbage — ejerskabet blev IKKE overdraget.
        MG.Pay(buyerXp, paymentMethod, sale.price)
        ReleaseSale(saleId)
        return { success = false, msg = 'Database-fejl — handlen blev IKKE gennemført, dine penge er refunderet.' }
    end

    -- Ejerskab er overdraget. Nu nøgler + betaling til sælger.
    MySQL.query.await('DELETE FROM vehicle_keys WHERE identifier = ? AND plate = ?', { sale.sellerIdentifier, sale.plate })
    pcall(function() exports[Config.KeyExport]:Masitz_removeKey(sale.sellerSrc, sale.plate) end)

    local okGive, errGive = pcall(function() exports[Config.KeyExport]:Masitz_giveKey(src, sale.plate) end)
    if not okGive then MG.Log('confirmSale: Masitz_giveKey fejl: ' .. tostring(errGive)) end
    MySQL.query.await('INSERT IGNORE INTO vehicle_keys (identifier, plate) VALUES (?, ?)', { sale.buyerIdentifier, sale.plate })

    MG.Pay(sellerXp, paymentMethod, sale.price)

    MG.LogSale({
        sellerName = sellerXp.getName(), sellerIdentifier = sale.sellerIdentifier, sellerSrc = sale.sellerSrc,
        buyerName  = buyerXp.getName(),  buyerIdentifier  = sale.buyerIdentifier,  buyerSrc  = src,
        vehicleName = sale.vehicleName, model = sale.vehicleModel, plate = sale.plate,
        price = sale.price, paymentMethod = paymentMethod, saleId = saleId,
    })
    MG.Log(('SALE COMPLETE: %s -> %s, %s, %d kr. (%s)'):format(sale.sellerIdentifier, sale.buyerIdentifier, sale.plate, sale.price, paymentMethod))

    TriggerClientEvent('ox_lib:notify', sale.sellerSrc, {
        type = 'success',
        description = ('%s har købt %s af dig for %s.'):format(buyerXp.getName(), sale.plate, MG.FormatMoney(sale.price)),
    })

    sale.status = 'done'
    ReleaseSale(saleId)

    return { success = true, price = sale.price }
end)

-- ─── AFBRYD (fra enten sælger eller køber) ────────────────────────
RegisterNetEvent('masitz_garage:cancelSale', function(saleId)
    local src = source
    local sale = ActiveSales[saleId]
    if not sale then return end
    if sale.status ~= 'awaiting_buyer' then return end
    if src ~= sale.sellerSrc and src ~= sale.buyerSrc then return end

    ReleaseSale(saleId)

    local otherSrc = (src == sale.sellerSrc) and sale.buyerSrc or sale.sellerSrc
    TriggerClientEvent('ox_lib:notify', otherSrc, { type = 'inform', description = 'Handlen blev annulleret.' })
end)

-- ─── DISCONNECT-HÅNDTERING (§28) ──────────────────────────────────
AddEventHandler('playerDropped', function()
    local src = source
    for saleId, sale in pairs(ActiveSales) do
        if sale.status == 'awaiting_buyer' and (sale.sellerSrc == src or sale.buyerSrc == src) then
            local otherSrc = (sale.sellerSrc == src) and sale.buyerSrc or sale.sellerSrc
            ReleaseSale(saleId)
            TriggerClientEvent('ox_lib:notify', otherSrc, { type = 'error', description = 'Handlen blev annulleret (modparten forlod serveren).' })
        end
    end
end)

-- ─── TIMEOUT-OPRYDNING ─────────────────────────────────────────────
CreateThread(function()
    while true do
        Wait(Config.Sale.sweepInterval)
        local now = os.time()
        for saleId, sale in pairs(ActiveSales) do
            if sale.status == 'awaiting_buyer' and now > sale.expiresAt then
                ReleaseSale(saleId)
                TriggerClientEvent('ox_lib:notify', sale.sellerSrc, { type = 'error', description = 'Handlen udløb — køberen svarede ikke i tide.' })
            end
        end
    end
end)
