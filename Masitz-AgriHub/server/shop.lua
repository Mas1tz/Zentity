-- ============================================================
--  Masitz-AgriHub | server/shop.lua
--  Indkøb via AgriHub-computeren (§15-§16). Server-autoritativ:
--  prisen kommer ALTID fra Config.Agri.Shop, aldrig fra klienten.
-- ============================================================

lib.callback.register('masitz_agrihub:shop:purchase', function(src, cart, paymentMethod)
    local session = AH.RequireSession(src)
    if not session then return { success = false, msg = 'Du er ikke logget ind på AgriHub.' } end

    if type(cart) ~= 'table' or #cart == 0 then
        return { success = false, msg = 'Indkøbskurven er tom.' }
    end
    if paymentMethod ~= 'cash' and paymentMethod ~= 'bank' then paymentMethod = 'bank' end

    local xp = AH.GetXPlayer(src)
    if not xp then return { success = false, msg = 'Spillerdata ikke fundet.' } end

    local shopById = {}
    for _, item in ipairs(Config.Agri.Shop) do shopById[item.id] = item end

    -- Byg en SERVER-AUTORITATIV linje-liste. Alt clienten sendte af
    -- pris/label/etc. ignoreres fuldstændigt — kun `id` og `qty` bruges,
    -- og kun til at slå op i config.
    local lines, total = {}, 0
    for _, entry in ipairs(cart) do
        local def = type(entry) == 'table' and shopById[entry.id] or nil
        if not def then
            AH.LogSecurity(src, 'invalid_shop_item', 'Forsøgte at købe en ukendt vare-ID.', { requestedId = entry and entry.id })
            return { success = false, msg = 'Ukendt vare i kurven.' }
        end

        local qty = math.floor(tonumber(entry.qty) or 0)
        if qty <= 0 or qty > def.maxCart then
            return { success = false, msg = ('Ugyldigt antal for %s.'):format(def.label) }
        end

        local subtotal = def.price * qty
        total = total + subtotal
        lines[#lines + 1] = { id = def.id, item = def.item, label = def.label, qty = qty, price = def.price, subtotal = subtotal }
    end

    if total <= 0 then return { success = false, msg = 'Ugyldig ordre.' } end

    -- Tjek plads i inventory FØR nogen penge rører sig.
    for _, line in ipairs(lines) do
        local ok, canCarry = pcall(function()
            return exports.ox_inventory:CanCarryItem(src, line.item, line.qty)
        end)
        if not ok or not canCarry then
            return { success = false, msg = ('Din inventory har ikke plads til %d× %s.'):format(line.qty, line.label) }
        end
    end

    if not AH.TryCharge(xp, paymentMethod, total) then
        return { success = false, msg = 'Du har ikke råd til denne ordre.' }
    end

    local allGiven = true
    for _, line in ipairs(lines) do
        local ok, given = pcall(function()
            return exports.ox_inventory:AddItem(src, line.item, line.qty)
        end)
        if not ok or given == false then
            allGiven = false
        end
    end

    if not allGiven then
        -- Vi kan ikke vide præcis hvor mange linjer der reelt nåede at
        -- blive givet før fejlen — refunder derfor det FULDE beløb frem
        -- for at risikere at spilleren betalte for noget de ikke fik.
        AH.Pay(xp, paymentMethod, total)
        AH.LogSecurity(src, 'purchase_item_grant_failed', 'Vare-udlevering fejlede efter betaling — beløbet er refunderet.', { total = total })
        return { success = false, msg = 'Der opstod en fejl under leveringen — dine penge er refunderet.' }
    end

    AH.LogAction('purchases', 'PURCHASE', src, {
        total = total, paymentMethod = paymentMethod, itemCount = #lines,
    })

    return { success = true, total = total }
end)

-- ─── EJEDE ANTAL (vises i NUI'en, så man kan se hvad man allerede
--     har af fx Kunstgødning FØR man køber mere ovenpå) ───────────
lib.callback.register('masitz_agrihub:shop:counts', function(src)
    if not AH.RequireSession(src) then return {} end

    local counts = {}
    for _, item in ipairs(Config.Agri.Shop) do
        local ok, count = pcall(function() return exports.ox_inventory:GetItemCount(src, item.item) end)
        counts[item.id] = (ok and tonumber(count)) or 0
    end
    return counts
end)

AH.Log('server/shop.lua indlæst.')
