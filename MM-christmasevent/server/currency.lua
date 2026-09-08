-- ══════════════════════════════════════════════════════════
--  CURRENCY ABSTRACTION — mm-christmas
--
--  ÉN source of truth: den faktiske mængde Config.CoinItem i
--  spillerens ox_inventory. Der findes IKKE en separat tæller der
--  kan komme ud af sync (den gamle version havde både en DB-kolonne
--  OG et rigtigt inventory-item som blev opdateret uafhængigt af
--  hinanden - hvis en spiller solgte/smed/trak et christmas_coin item
--  via almindelig inventory-handling, ville DB-tallet stadig vise det
--  gamle (forkerte) beløb).
--
--  data.coins i databasen er udelukkende en READ-ONLY cache til
--  leaderboardet (for at kunne vise offline spilleres sidst kendte
--  saldo uden at kræve de er online) - den bruges ALDRIG til at
--  træffe en beslutning om hvorvidt en spiller har råd til noget.
-- ══════════════════════════════════════════════════════════

Currency = {}

function Currency.Get(src)
    return Inventory.GetCount(src, Config.CoinItem)
end

function Currency.Has(src, amount)
    amount = Shared.ToPositiveInt(amount, 0)
    return Currency.Get(src) >= amount
end

-- Giver op til `amount` coins, klippet så spilleren aldrig overstiger
-- Config.MaxCoins. Returnerer det faktisk tildelte beløb (kan være 0).
function Currency.Add(src, amount)
    amount = Shared.ToPositiveInt(amount, 0)
    if amount <= 0 then return 0 end

    local current = Currency.Get(src)
    local capped  = math.min(amount, math.max(0, Config.MaxCoins - current))
    if capped <= 0 then return 0 end

    local ok = Inventory.GiveItem(src, Config.CoinItem, capped)
    if not ok then
        Shared.Warn(('Kunne ikke give %d x %s til spiller %s - "%s" findes muligvis ikke i ox_inventory items.lua.'):format(capped, Config.CoinItem, src, Config.CoinItem))
        return 0
    end

    return capped
end

-- Fjerner `amount` coins. Returnerer true/false - kaldere skal ALTID
-- tjekke Currency.Has() eller dette returflag før de giver en vare/reward.
function Currency.Remove(src, amount)
    amount = Shared.ToPositiveInt(amount, 0)
    if amount <= 0 then return true end

    if not Currency.Has(src, amount) then
        return false
    end

    return Inventory.RemoveItem(src, Config.CoinItem, amount)
end
