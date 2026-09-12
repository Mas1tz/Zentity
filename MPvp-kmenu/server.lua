-- ============================================================
--  MPvp-kmenu | server.lua
--  100% server-autoritativ udlevering. Klienten/NUI'en sender KUN et
--  ønsket nøgle-navn (+ evt. antal) — server slår ALTID op i sin egen
--  whitelist (bygget fra config.lua) og bestemmer selv label, kategori,
--  og det faktiske antal der gives. Intet fra klienten bruges direkte.
-- ============================================================

local function DebugPrint(fmt, ...)
    if Config.Debug then
        print(('[MPvp-kmenu] ' .. fmt):format(...))
    end
end

-- ─── WHITELIST — bygget ÉN gang ved opstart ud fra Config.Weapons ─
local WeaponWhitelist = {}
local ItemWhitelist = {}

for category, entries in pairs(Config.Weapons) do
    for _, entry in ipairs(entries) do
        if entry.weapon then
            WeaponWhitelist[entry.weapon] = { label = entry.label, category = category }
        elseif entry.item then
            ItemWhitelist[entry.item] = {
                label = entry.label,
                category = category,
                maxAmount = entry.maxAmount or Config.MaxItemAmount,
            }
        end
    end
end

DebugPrint('Whitelist klar — %d våben, %d items.', (function() local n = 0 for _ in pairs(WeaponWhitelist) do n = n + 1 end return n end)(), (function() local n = 0 for _ in pairs(ItemWhitelist) do n = n + 1 end return n end)())

-- ─── DISCORD-LOGGING (kun server-side URL, aldrig sendt til klient) ─
local KIND_COLOR = {
    weapon_given   = 0x3F9142,
    item_given     = 0x3F9142,
    security       = 0xE03131,
    inventory_full = 0xF08C00,
    errors         = 0x666666,
}

local function SendWebhook(kind, title, fields)
    if not Config.Logging.enabled then return end
    local webhook = Config.Logging.webhook
    if not webhook or webhook == '' then return end

    local embedFields = {}
    for _, f in ipairs(fields) do
        embedFields[#embedFields + 1] = {
            name = f[1],
            value = tostring(f[2] ~= nil and f[2] ~= '' and f[2] or 'n/a'),
            inline = f[3] ~= false,
        }
    end

    local payload = {
        username = Config.Logging.username or 'MPvp Security',
        embeds = {
            {
                title = title,
                color = KIND_COLOR[kind] or KIND_COLOR.errors,
                fields = embedFields,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            },
        },
    }

    PerformHttpRequest(webhook, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function GetDiscordId(src)
    local ok, ids = pcall(GetPlayerIdentifiers, src)
    if not ok or not ids then return nil end
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
            return id:sub(9)
        end
    end
    return nil
end

local function Log(kind, title, src, data)
    data = data or {}
    local name = GetPlayerName(src) or 'Ukendt'

    local fields = {
        { 'Spiller', name, true },
        { 'Server ID', tostring(src), true },
        { 'Discord', GetDiscordId(src) or 'n/a', true },
    }
    for k, v in pairs(data) do
        fields[#fields + 1] = { k, tostring(v), true }
    end

    if Config.Debug then
        print(('[MPvp-kmenu] %s (src=%s): %s'):format(kind, tostring(src), title))
    end

    SendWebhook(kind, title, fields)
end

-- ─── ANTI-SPAM (server-side, pr. spiller) ─────────────────────────
local lastGiveAt = {}

local function CheckAndStampCooldown(src)
    local now = GetGameTimer()
    local last = lastGiveAt[src]
    if last and (now - last) < Config.GiveCooldown then
        return false
    end
    lastGiveAt[src] = now
    return true
end

AddEventHandler('playerDropped', function()
    lastGiveAt[source] = nil
end)

-- ─── SVAR TIL KLIENTEN (NUI-toast) ─────────────────────────────────
local function Respond(src, success, title, message)
    TriggerClientEvent('mpvp_kmenu:result', src, { success = success, title = title, message = message })
end

-- ─── HOVED-HANDLER: klienten beder om at få noget, server afgør ALT ─
RegisterNetEvent('mpvp_kmenu:give', function(kind, key, amount)
    local src = source

    if kind ~= 'weapon' and kind ~= 'item' then
        Log('security', 'Ugyldig give-type forsøgt', src, { kind = tostring(kind) })
        return
    end

    if not CheckAndStampCooldown(src) then
        Respond(src, false, 'Vent lidt', 'Du gør det for hurtigt — prøv igen om et øjeblik.')
        Log('security', 'Give-cooldown ramt (muligt spam-forsøg)', src, { kind = kind, key = tostring(key) })
        return
    end

    key = tostring(key or '')
    local entry, amountToGive

    if kind == 'weapon' then
        entry = WeaponWhitelist[key]
        if not entry then
            Respond(src, false, 'Fejl', 'Ukendt våben.')
            Log('security', 'Forsøgte at give et ukendt/ikke-whitelisted våben', src, { weapon = key })
            return
        end
        -- Våben er ALTID præcis 1, uanset hvad klienten måtte sende.
        amountToGive = 1
    else
        entry = ItemWhitelist[key]
        if not entry then
            Respond(src, false, 'Fejl', 'Ukendt item.')
            Log('security', 'Forsøgte at give et ukendt/ikke-whitelisted item', src, { item = key })
            return
        end

        local requested = tonumber(amount)
        if not requested or requested ~= math.floor(requested) or requested < 1 or requested > entry.maxAmount then
            Respond(src, false, 'Ugyldigt antal', ('Antal skal være mellem 1 og %d.'):format(entry.maxAmount))
            Log('security', 'Ugyldigt/mistænkeligt antal forsøgt', src, { item = key, amount = tostring(amount), maxAllowed = entry.maxAmount })
            return
        end
        amountToGive = requested
    end

    local ok, added = pcall(function()
        return exports.ox_inventory:AddItem(src, key, amountToGive)
    end)

    if not ok then
        Respond(src, false, 'Noget gik galt', 'Der opstod en serverfejl.')
        Log('errors', 'ox_inventory:AddItem fejlede', src, { key = key, amount = amountToGive, error = tostring(added) })
        return
    end

    if not added then
        Respond(src, false, 'Inventory fuldt', 'Du har ikke plads i din inventory.')
        Log('inventory_full', 'Inventory var fuldt ved udlevering', src, { key = key, amount = amountToGive })
        return
    end

    Respond(src, true, kind == 'weapon' and 'Våben givet' or 'Item givet', ('%s blev tilføjet til din inventory.'):format(entry.label))
    Log(kind == 'weapon' and 'weapon_given' or 'item_given', 'Vare udleveret', src, { key = key, amount = amountToGive, category = entry.category })
end)
