-- ══════════════════════════════════════════════════════════
--  RATE LIMITING — mm-christmas
--
--  Generisk pr.-spiller / pr.-event cooldown. Bruges foran ALLE
--  server events der kan udløse en reward eller mutere state, for at
--  beskytte mod spam/dobbeltklik/event-replay uden at genere normal
--  spilleradfærd (grænserne i Config.RateLimits er sat rummeligt).
-- ══════════════════════════════════════════════════════════

RateLimit = {}

local lastUsed = {} -- [src] = { [key] = gameTimerMs }

-- Returnerer true hvis handlingen er tilladt (og registrerer den med
-- det samme), ellers false + hvor mange ms der er tilbage af cooldown.
function RateLimit.Check(src, key, cooldownMs)
    cooldownMs = cooldownMs or 1000
    local now  = GetGameTimer()

    lastUsed[src] = lastUsed[src] or {}
    local last = lastUsed[src][key]

    if last and (now - last) < cooldownMs then
        return false, cooldownMs - (now - last)
    end

    lastUsed[src][key] = now
    return true
end

function RateLimit.Clear(src)
    lastUsed[src] = nil
end

AddEventHandler('playerDropped', function()
    RateLimit.Clear(source)
end)
