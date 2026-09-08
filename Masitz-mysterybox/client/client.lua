-- ============================================================
--  Masitz-mysterybox | client/client.lua
--
--  Clienten kender IKKE til noget box-navn/type hardcoded. Alt
--  bygges dynamisk ud fra Config.MysteryBox.Boxes / .Conversion, så
--  en ny box i config.lua automatisk får sin egen "brug item"-export
--  og dukker automatisk op i konverterings-menuen.
-- ============================================================

local M = Config.MysteryBox

local function notify(title, description, notifyType)
    lib.notify({
        title = title,
        description = description,
        type = notifyType,
        position = (M.Notifications and M.Notifications.position) or 'center-right',
    })
end

-- ================================
-- Konverter mysterybox
-- Menuen bygges dynamisk ud fra Config.MysteryBox.Conversion.targets
-- - INGEN box-navne er hardcoded her. Tilføjer du en ny target i
-- config.lua, dukker den automatisk op i denne dialog.
-- ================================
local function buildConversionOptions()
    local options = {}
    local conversion = M.Conversion

    if not conversion or not conversion.enabled or type(conversion.targets) ~= 'table' then
        return options
    end

    for targetKey in pairs(conversion.targets) do
        local box = M.Boxes[targetKey]

        options[#options + 1] = {
            label = box and box.label or targetKey,
            value = targetKey,
        }
    end

    table.sort(options, function(a, b) return a.label < b.label end)

    return options
end

-- ox_inventory kalder et usable items client.export med signaturen
-- (event, item, inventory, slot, data), og kan kalde den for flere
-- events (fx både 'usingItem' og 'usedItem') - vi skal derfor kun
-- reagere på 'usingItem' for ikke at åbne/konvertere to gange pr. brug.
local function convertMysteryBox(event, _item, _inventory, _slot, _data)
    if event ~= nil and event ~= 'usingItem' then return end

    local conversion = M.Conversion

    if not conversion or not conversion.enabled then return end

    local options = buildConversionOptions()

    if #options == 0 then
        notify('Mystery Box', 'Der er ingen konverteringsmuligheder tilgængelige.', 'error')
        return
    end

    local input = lib.inputDialog(conversion.dialogTitle or 'Mystery Box', {
        {
            type = 'select',
            label = 'Vælg type',
            options = options,
            required = true,
        },
        {
            type = 'number',
            label = 'Antal',
            description = 'Hvor mange mysteryboxe vil du konvertere?',
            min = 1,
            required = true,
        },
    })

    if not input or not input[1] then return end

    local targetKey = input[1]
    local amount = math.floor(tonumber(input[2]) or 0)

    if amount < 1 then
        notify('Mystery Box', 'Ugyldigt antal angivet.', 'error')
        return
    end

    TriggerServerEvent('Masitz-MysteryBox:convertBox', targetKey, amount)
end

exports('convertMysteryBox', convertMysteryBox)

-- ================================
-- Åbn mystery box
-- Én generisk export pr. konfigureret box, autogenereret ud fra
-- Config.MysteryBox.Boxes. Tilføjer du "premium" i config.lua, får
-- du automatisk en "use_premium"-export uden at røre denne fil.
-- Peg det tilsvarende items.lua-item i ox_inventory på
-- 'Masitz-mysterybox.use_<boxnøgle>'.
-- ================================
for boxKey, box in pairs(M.Boxes) do
    exports(('use_%s'):format(boxKey), function(event, item, _inventory, slot, _data)
        -- Se kommentaren ved convertMysteryBox ovenfor: samme
        -- (event, item, inventory, slot, data)-signatur fra ox_inventory.
        if event ~= nil and event ~= 'usingItem' then return end

        -- slot er den korrekte kilde til slotnummeret. Falder kun
        -- tilbage til item.slot hvis en anden kaldekonvention bruges
        -- (fx et script der kalder exporten direkte).
        slot = slot or (type(item) == 'table' and item.slot)

        notify(box.label or 'Mystery Box', 'Åbner boxen...', 'inform')
        TriggerServerEvent('Masitz-MysteryBox:openBox', boxKey, slot)
    end)
end
