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

local function convertMysteryBox(...)
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
-- ox_inventory's egen kaldekonvention for et usable item's client.export
-- varierer på tværs af versioner/forks (nogle sender slot som 2. argument,
-- andre som 4. argument i et (event, item, inventory, slot, data)-kald,
-- og nogle sender item-tabellen med et .slot felt i stedet). I stedet for
-- at gætte på én bestemt rækkefølge, scanner vi alle modtagne argumenter
-- og bruger det første der reelt er et gyldigt slot-tal.
local function findSlotArg(...)
    for i = 1, select('#', ...) do
        local value = select(i, ...)

        if type(value) == 'number' then
            return value
        elseif type(value) == 'table' and type(value.slot) == 'number' then
            return value.slot
        end
    end

    return nil
end

for boxKey, box in pairs(M.Boxes) do
    exports(('use_%s'):format(boxKey), function(...)
        local slot = findSlotArg(...)

        notify(box.label or 'Mystery Box', 'Åbner boxen...', 'inform')
        TriggerServerEvent('Masitz-MysteryBox:openBox', boxKey, slot)
    end)
end
