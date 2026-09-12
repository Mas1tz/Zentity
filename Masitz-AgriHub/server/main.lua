-- ============================================================
--  Masitz-AgriHub | server/main.lua
--  Kerne: session-håndtering, discord/identifier-helpers,
--  penge-helpers, ID-generator, cleanup-registry.
--  Loades FØRST (se fxmanifest.lua) så AH.* findes for alle andre.
-- ============================================================

AH = AH or {}

AH.ESX = exports['es_extended']:getSharedObject()

-- Aktive AgriHub-sessioner. [source] = { identifier, discordId, name, role }
-- Dette er den ENESTE kilde til "er denne spiller logget ind på AgriHub" —
-- NUI'en kan aldrig selv sætte dette.
AH.Sessions = {}

-- Cleanup-hooks andre filer kan registrere sig i (playerDropped).
-- Undgår at main.lua skal kende til tasks/rental/vehicles internt.
AH.CleanupHooks = {}
function AH.RegisterCleanupHook(fn)
    AH.CleanupHooks[#AH.CleanupHooks + 1] = fn
end

-- ─── DEBUG ───────────────────────────────────────────────────
function AH.Log(fmt, ...)
    if Config.Agri.Debug then
        print(('[Masitz-AgriHub] ' .. fmt):format(...))
    end
end

-- ─── PLATE / STRING HELPERS ────────────────────────────────────
function AH.NormPlate(plate)
    if not plate then return nil end
    plate = tostring(plate):gsub('%s+', ''):upper()
    if #plate == 0 or #plate > 8 then return nil end
    return plate
end

-- Genererer et ID i stil med "AGR-000184". Kollision er ekstremt
-- usandsynligt (1 million kombinationer), men kaldere (tasks.lua/
-- rental.lua) retryer ved en UNIQUE-constraint-fejl fra databasen.
function AH.GenerateId(prefix)
    local num = math.random(0, 999999)
    return ('%s-%06d'):format(prefix, num)
end

-- ─── SPILLER-OPSLAG ─────────────────────────────────────────────
function AH.GetXPlayer(src)
    local ok, xp = pcall(AH.ESX.GetPlayerFromId, src)
    if not ok or not xp then return nil end
    return xp
end

-- Robust Discord-identifier-helper (§114). Returnerer nil hvis
-- spilleren ikke har en Discord-identifier tilknyttet (fx offline
-- Discord-integration) — kaldere skal selv håndtere nil korrekt.
function AH.GetDiscordId(src)
    local ok, ids = pcall(GetPlayerIdentifiers, src)
    if not ok or not ids then return nil end
    for _, id in ipairs(ids) do
        if type(id) == 'string' and id:sub(1, 8) == 'discord:' then
            return id:sub(9)
        end
    end
    return nil
end

-- ─── SESSION / ADGANGS-GATES ────────────────────────────────────
-- Bruges af ALLE NUI-vendte callbacks/events der kræver login.
function AH.RequireSession(src)
    local session = AH.Sessions[src]
    if not session then
        AH.LogSecurity(src, 'no_session', 'Handling forsøgt uden aktiv AgriHub-session.', {})
        return false
    end
    return session
end

-- Bruges af ALLE admin-callbacks. Genvalidér Discord ID LIVE ved hvert
-- kald (§113) — stoler ALDRIG kun på en cachet session.role.
function AH.RequireAdmin(src)
    local session = AH.RequireSession(src)
    if not session then return false end

    local discordId = AH.GetDiscordId(src)
    if not discordId or discordId ~= Config.Agri.Admin.discordId then
        AH.LogSecurity(src, 'unauthorized_admin_attempt', 'Ikke-SUPER_ADMIN forsøgte en admin-handling.', {
            discordId = discordId or 'ukendt',
        })
        return false
    end
    return session
end

-- ─── NOTIFY ──────────────────────────────────────────────────
function AH.Notify(src, description, ntype, title)
    TriggerClientEvent('ox_lib:notify', src, {
        title = title or 'AgriHub',
        description = description,
        type = ntype or 'inform',
    })
end

-- ─── PENGE (§36, §66) — ren ESX Legacy, intet nyt economy-system ──
function AH.GetBalance(xp, method)
    if method == 'bank' then
        local acc = xp.getAccount('bank')
        return acc and acc.money or 0
    end
    return xp.getMoney() or 0
end

function AH.TryCharge(xp, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end
    if AH.GetBalance(xp, method) < amount then return false end
    if method == 'bank' then
        xp.removeAccountMoney('bank', amount)
    else
        xp.removeMoney(amount)
    end
    return true
end

function AH.Pay(xp, method, amount)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return end
    if method == 'bank' then
        xp.addAccountMoney('bank', amount)
    else
        xp.addMoney(amount)
    end
end

-- ─── PLAYER LIFECYCLE ────────────────────────────────────────
AddEventHandler('playerDropped', function(_reason)
    local src = source
    for i = 1, #AH.CleanupHooks do
        local ok, err = pcall(AH.CleanupHooks[i], src)
        if not ok then
            AH.Log('CleanupHook fejlede: %s', tostring(err))
        end
    end
    AH.Sessions[src] = nil
end)

AH.Log('server/main.lua indlæst.')
