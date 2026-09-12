-- ============================================================
--  Masitz-garage | client/cl_menus.lua
--  Nye menu-flows: Skift bilnavn, Giv nøgler, Sælg bil (+ købers
--  side), Flyt bil / Hent bil hertil (tom garage). Alt her sender
--  kun "forslag" til serveren — serveren er den eneste sandhed
--  for ejerskab/pris/target/betaling (se server/*.lua).
-- ============================================================

MGC = MGC or {}

-- ═══════════════════════════════════════════════════════════
--  SKIFT BILNAVN (§5)
-- ═══════════════════════════════════════════════════════════

function MGC.OpenRenameDialog(plate, currentName, onDone)
    local input = lib.inputDialog('Skift bilnavn', {
        {
            type = 'input', label = 'Nyt navn',
            description = ('Maks %d tegn'):format(Config.VehicleName.maxLength),
            default = currentName or '', required = true,
        }
    })
    if not input or not input[1] then return end

    local result = lib.callback.await('masitz_garage:renameVehicle', false, plate, input[1])
    if result and result.success then
        lib.notify({ type = 'success', description = ('Bilen hedder nu "%s".'):format(result.newName) })
    else
        lib.notify({ type = 'error', description = (result and result.msg) or 'Kunne ikke omdøbe bilen.' })
    end
    if onDone then onDone() end
end

-- ═══════════════════════════════════════════════════════════
--  GIV NØGLER (§6)
-- ═══════════════════════════════════════════════════════════

function MGC.OpenGiveKeysDialog(plate)
    local input = lib.inputDialog('Giv nøgler', {
        { type = 'number', label = 'Spiller ID', required = true, min = 0 }
    })
    if not input or input[1] == nil then return end

    local target = lib.callback.await('masitz_garage:resolveTargetPlayer', false, input[1])
    if not target then
        lib.notify({ type = 'error', description = 'Spilleren blev ikke fundet (tjek ID\'et).' })
        return
    end

    local confirmed = lib.alertDialog({
        header   = 'Giv nøgler til:',
        content  = ('**ID:** %d\n**Navn:** %s'):format(target.id, target.name),
        centered = true,
        cancel   = true,
        labels   = { confirm = 'Godkend', cancel = 'Annuller' },
    })
    if confirmed ~= 'confirm' then return end

    local result = lib.callback.await('masitz_garage:giveKeyToPlayer', false, plate, target.id)
    if result and result.success then
        lib.notify({ type = 'success', description = ('Nøgler givet til %s.'):format(result.targetName) })
    else
        lib.notify({ type = 'error', description = (result and result.msg) or 'Kunne ikke give nøgler.' })
    end
end

-- ═══════════════════════════════════════════════════════════
--  SÆLG BIL (§7-§9) — sælgers side
-- ═══════════════════════════════════════════════════════════

function MGC.OpenSellDialog(plate, v, label)
    local input = lib.inputDialog('Sælg bil', {
        { type = 'number', label = 'Køber Spiller-ID', required = true, min = 0 },
        { type = 'number', label = 'Pris (kr.)', required = true, min = Config.Sale.minPrice, max = Config.Sale.maxPrice },
    })
    if not input or input[1] == nil or input[2] == nil then return end

    local targetId, price = input[1], math.floor(input[2])

    local target = lib.callback.await('masitz_garage:resolveTargetPlayer', false, targetId)
    if not target then
        lib.notify({ type = 'error', description = 'Køberen blev ikke fundet (tjek ID\'et).' })
        return
    end

    local displayName = MGC.GetDisplayName(v.vehicleName, v.model)
    local confirmed = lib.alertDialog({
        header   = 'Bekræft salg',
        content  = ('Sælg **%s** (%s) til:\n\n**ID:** %d\n**Navn:** %s\n\n**Pris:** %s'):format(
            displayName, plate, target.id, target.name, MGC.FormatMoney(price)),
        centered = true,
        cancel   = true,
        labels   = { confirm = 'Godkend', cancel = 'Annuller' },
    })
    if confirmed ~= 'confirm' then return end

    local result = lib.callback.await('masitz_garage:initiateSale', false, plate, target.id, price)
    if result and result.ok then
        lib.notify({ type = 'inform', description = ('Tilbud sendt til %s — venter på svar...'):format(result.buyerName) })
    else
        lib.notify({ type = 'error', description = (result and result.msg) or 'Kunne ikke starte handlen.' })
    end
end

-- ─── SÆLG BIL — købers side (modtager tilbuddet) ──────────────
RegisterNetEvent('masitz_garage:incomingSaleOffer', function(offer)
    local vehicleLabel = MGC.GetDisplayName(offer.vehicleName, offer.model)

    local confirmed = lib.alertDialog({
        header   = 'BILHANDEL',
        content  = ('%s vil sælge dig:\n\n**%s**\n\nNummerplade: **%s**\nPris: **%s**'):format(
            offer.sellerName, vehicleLabel, offer.plate, MGC.FormatMoney(offer.price)),
        centered = true,
        cancel   = true,
        labels   = { confirm = 'Godkend handel', cancel = 'Annuller' },
    })

    if confirmed ~= 'confirm' then
        TriggerServerEvent('masitz_garage:cancelSale', offer.saleId)
        return
    end

    local payInput = lib.inputDialog('Betalingsmetode', {
        {
            type = 'select', label = 'Betaling', required = true, default = 'bank',
            options = {
                { value = 'cash', label = 'Kontanter' },
                { value = 'bank', label = 'Bank' },
            },
        }
    })
    if not payInput or not payInput[1] then
        TriggerServerEvent('masitz_garage:cancelSale', offer.saleId)
        return
    end

    local result = lib.callback.await('masitz_garage:confirmSale', false, offer.saleId, payInput[1])
    if result and result.success then
        lib.notify({ type = 'success', description = ('Du har købt %s for %s.'):format(vehicleLabel, MGC.FormatMoney(result.price)) })
    else
        lib.notify({ type = 'error', description = (result and result.msg) or 'Handlen kunne ikke gennemføres.' })
    end
end)

-- ═══════════════════════════════════════════════════════════
--  FLYT BIL (§14) — fra en bil man allerede har valgt i en garage
-- ═══════════════════════════════════════════════════════════

function MGC.OpenTransferOutMenu(plate, currentGarageKey, onDone)
    local options = lib.callback.await('masitz_garage:getTransferOptions', false, plate)
    if not options or #options == 0 then
        lib.notify({ type = 'error', description = 'Ingen andre garager af denne type er tilgængelige.' })
        return
    end

    local menuOptions = {}
    for _, opt in ipairs(options) do
        menuOptions[#menuOptions + 1] = {
            title       = opt.label,
            description = ('Pris: %s'):format(MGC.FormatMoney(opt.price)),
            icon        = 'warehouse',
            onSelect    = function()
                local confirmed = lib.alertDialog({
                    header   = 'Flyt bil',
                    content  = ('Flyt bilen til **%s** for **%s**?'):format(opt.label, MGC.FormatMoney(opt.price)),
                    centered = true,
                    cancel   = true,
                    labels   = { confirm = 'Bekræft', cancel = 'Annuller' },
                })
                if confirmed ~= 'confirm' then return end

                local result = lib.callback.await('masitz_garage:executeTransfer', false, plate, opt.key)
                if result and result.success then
                    lib.notify({ type = 'success', description = ('Bilen er flyttet til %s (%s).'):format(result.toLabel, MGC.FormatMoney(result.price)) })
                else
                    lib.notify({ type = 'error', description = (result and result.msg) or 'Kunne ikke flytte bilen.' })
                end
                if onDone then onDone() end
            end
        }
    end

    lib.registerContext({
        id      = 'garage_transfer_' .. plate,
        title   = '🏢 Flyt bil',
        menu    = 'garage_actions_' .. plate,
        options = menuOptions,
    })
    lib.showContext('garage_transfer_' .. plate)
end

-- ═══════════════════════════════════════════════════════════
--  TOM GARAGE (§25) — "Hent bil hertil" i stedet for dead-end notify
-- ═══════════════════════════════════════════════════════════

function MGC.OpenEmptyGarageMenu(garageKey)
    local garage = Config.Garages[garageKey]

    lib.registerContext({
        id      = 'garage_empty_' .. garageKey,
        title   = '🏢 ' .. (garage and garage.label or garageKey),
        options = {
            {
                title       = 'Ingen biler er parkeret her.',
                description = 'Du kan hente en af dine biler hertil.',
                icon        = 'circle-info',
                readOnly    = true,
            },
            {
                title       = '🚚 Hent bil hertil',
                description = 'Vælg en af dine andre biler og betal for transport',
                icon        = 'truck-fast',
                onSelect    = function() MGC.OpenTransferInMenu(garageKey) end
            }
        }
    })
    lib.showContext('garage_empty_' .. garageKey)
end

function MGC.OpenTransferInMenu(garageKey)
    local vehicles = lib.callback.await('masitz_garage:getOtherStoredVehicles', false, garageKey)
    if not vehicles or #vehicles == 0 then
        lib.notify({ type = 'error', description = 'Du har ingen andre biler at hente hertil.' })
        return
    end

    local options = {}
    for _, v in ipairs(vehicles) do
        local fromLabel = (Config.Garages[v.parking] and Config.Garages[v.parking].label) or v.parking
        local displayName = MGC.GetDisplayName(v.vehicleName, v.model)

        options[#options + 1] = {
            title       = displayName:upper(),
            description = ('Fra: %s\nPris: %s'):format(fromLabel, MGC.FormatMoney(v.price)),
            icon        = 'car',
            onSelect    = function()
                local confirmed = lib.alertDialog({
                    header   = 'Hent bil hertil',
                    content  = ('Hent **%s** hertil fra %s for **%s**?'):format(displayName, fromLabel, MGC.FormatMoney(v.price)),
                    centered = true,
                    cancel   = true,
                    labels   = { confirm = 'Bekræft', cancel = 'Annuller' },
                })
                if confirmed ~= 'confirm' then return end

                local result = lib.callback.await('masitz_garage:executeTransfer', false, v.plate, garageKey)
                if result and result.success then
                    lib.notify({ type = 'success', description = ('Bilen er på vej! Betalte %s.'):format(MGC.FormatMoney(result.price)) })
                    if OpenGarageMenu then OpenGarageMenu(garageKey) end
                else
                    lib.notify({ type = 'error', description = (result and result.msg) or 'Kunne ikke hente bilen.' })
                end
            end
        }
    end

    lib.registerContext({
        id      = 'garage_transferin_' .. garageKey,
        title   = '🚚 Hent bil hertil',
        menu    = 'garage_empty_' .. garageKey,
        options = options,
    })
    lib.showContext('garage_transferin_' .. garageKey)
end
