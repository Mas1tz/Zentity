-- ============================================================
--  Masitz-garage | server/sv_logging.lua
--  Discord webhook-logging (§12). Webhook-URLs ligger UDELUKKENDE
--  i Config.Logging (server-side) — sendes aldrig til klienten.
-- ============================================================

MG = MG or {}

local function ResolveWebhook(kind)
    if not Config.Logging or not Config.Logging.enabled then return nil end
    local url = Config.Logging.webhooks and Config.Logging.webhooks[kind]
    if not url or url == '' then return nil end
    return url
end

local function SendWebhook(kind, title, color, fields)
    local url = ResolveWebhook(kind)
    if not url then return end

    local embedFields = {}
    for _, f in ipairs(fields) do
        embedFields[#embedFields + 1] = {
            name   = f[1],
            value  = tostring(f[2] ~= nil and f[2] ~= '' and f[2] or 'n/a'),
            inline = f[3] ~= false,
        }
    end

    local payload = {
        username = Config.Logging.username or 'Masitz-garage',
        embeds   = {
            {
                title     = title,
                color     = color,
                fields    = embedFields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
                footer    = { text = 'Masitz-garage' },
            },
        },
    }

    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

-- ─── BILSALG ──────────────────────────────────────────────────
function MG.LogSale(data)
    SendWebhook('sales', '🚗 Bilsalg gennemført', 0x2ecc71, {
        { 'Sælger',        ('%s (%s / ID %s)'):format(data.sellerName, data.sellerIdentifier, data.sellerSrc) },
        { 'Køber',         ('%s (%s / ID %s)'):format(data.buyerName,  data.buyerIdentifier,  data.buyerSrc) },
        { 'Bil',           data.vehicleName or data.vehicleLabel },
        { 'Model',         data.model },
        { 'Nummerplade',   data.plate },
        { 'Pris',          MG.FormatMoney(data.price) },
        { 'Betaling',      data.paymentMethod == 'bank' and 'Bank' or 'Kontant' },
        { 'Sale ID',       data.saleId },
        { 'Tidspunkt',     os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── NØGLER ───────────────────────────────────────────────────
function MG.LogKeyGiven(data)
    SendWebhook('keys', '🔑 Nøgler givet', 0x3498db, {
        { 'Givet af',      ('%s (%s)'):format(data.giverName, data.giverIdentifier) },
        { 'Modtaget af',   ('%s (%s)'):format(data.receiverName, data.receiverIdentifier) },
        { 'Nummerplade',   data.plate },
        { 'Tidspunkt',     os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── SKIFT BILNAVN ────────────────────────────────────────────
function MG.LogRename(data)
    SendWebhook('garage', '✏️ Bilnavn ændret', 0x9b59b6, {
        { 'Spiller',       ('%s (%s)'):format(data.playerName, data.identifier) },
        { 'Gammelt navn',  data.oldName },
        { 'Nyt navn',      data.newName },
        { 'Nummerplade',   data.plate },
        { 'Tidspunkt',     os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── NUMMERPLADE-ÆNDRING (API — se sv_exports.lua) ────────────
function MG.LogPlateChange(data)
    SendWebhook('plates', '🔖 Nummerplade ændret', 0xf39c12, {
        { 'Spiller',        ('%s'):format(data.identifier) },
        { 'Gammel plade',   data.oldPlate },
        { 'Ny plade',       data.newPlate },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── GARAGE-FLYTNING ────────────────────────────────────────────
function MG.LogGarageTransfer(data)
    SendWebhook('garage', '🏢 Bil flyttet mellem garager', 0x3498db, {
        { 'Spiller',        ('%s (%s)'):format(data.playerName, data.identifier) },
        { 'Bil',            data.vehicleName or data.vehicleLabel },
        { 'Nummerplade',    data.plate },
        { 'Fra',            data.fromLabel },
        { 'Til',            data.toLabel },
        { 'Pris',           MG.FormatMoney(data.price) },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── BIL HENTET ─────────────────────────────────────────────────
function MG.LogVehicleRetrieved(data)
    SendWebhook('garage', '🔑 Bil hentet ud', 0x2ecc71, {
        { 'Spiller',        ('%s (%s)'):format(data.playerName, data.identifier) },
        { 'Bil',            data.vehicleName or data.vehicleLabel },
        { 'Nummerplade',    data.plate },
        { 'Garage',         data.garageLabel },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── BIL PARKERET ───────────────────────────────────────────────
function MG.LogVehicleStored(data)
    SendWebhook('garage', '🅿️ Bil parkeret', 0x2ecc71, {
        { 'Spiller',        ('%s (%s)'):format(data.playerName, data.identifier) },
        { 'Bil',            data.vehicleName or data.vehicleLabel },
        { 'Nummerplade',    data.plate },
        { 'Garage',         data.garageLabel },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── IMPOUND ────────────────────────────────────────────────────
function MG.LogImpound(data)
    SendWebhook('impound', '⚠️ Bil sat på impound', 0xe74c3c, {
        { 'Nummerplade',    data.plate },
        { 'Ejer',           data.owner },
        { 'Lokation',       data.location },
        { 'Årsag',          data.reason },
        { 'Gebyr',          MG.FormatMoney(data.fee) },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

function MG.LogImpoundRelease(data)
    SendWebhook('impound', '✅ Bil hentet fra impound', 0x2ecc71, {
        { 'Spiller',        ('%s (%s)'):format(data.playerName, data.identifier) },
        { 'Nummerplade',    data.plate },
        { 'Betalt gebyr',   MG.FormatMoney(data.fee) },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end

-- ─── BILKØB (fra fx en bilforhandler-resource, via export) ───
function MG.LogPurchase(data)
    SendWebhook('purchases', '🛒 Bil købt', 0x2ecc71, {
        { 'Spiller',        data.identifier },
        { 'Model',          data.model },
        { 'Nummerplade',    data.plate },
        { 'Pris',           MG.FormatMoney(data.price) },
        { 'Betaling',       data.paymentMethod == 'bank' and 'Bank' or 'Kontant' },
        { 'Tidspunkt',      os.date('%Y-%m-%d %H:%M:%S') },
    })
end
