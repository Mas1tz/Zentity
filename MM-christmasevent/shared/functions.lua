-- ══════════════════════════════════════════════════════════
--  SHARED FUNCTIONS — mm-christmas
-- ══════════════════════════════════════════════════════════

Shared = {}

-- ── LOCALE ──────────────────────────────────────────────
local _locale = {}

function Shared.LoadLocale(lang)
    _locale = Locales[lang] or Locales['en'] or {}
end

function T(key, ...)
    local str = _locale[key] or key
    if select('#', ...) > 0 then
        return string.format(str, ...)
    end
    return str
end

-- ── XP FORMLER ──────────────────────────────────────────
function Shared.XPRequired(level)
    if level >= Config.MaxLevel then return math.huge end
    return math.floor(1000 * (level ^ 1.5))
end

function Shared.LevelFromXP(xp)
    local level = 1
    while level < Config.MaxLevel do
        if xp < Shared.XPRequired(level) then break end
        xp  = xp - Shared.XPRequired(level)
        level = level + 1
    end
    return level
end

function Shared.XPIntoLevel(xp)
    local level = 1
    while level < Config.MaxLevel do
        local req = Shared.XPRequired(level)
        if xp < req then return xp, req end
        xp    = xp - req
        level = level + 1
    end
    return 0, Shared.XPRequired(Config.MaxLevel)
end

-- ── FORMATTERING ────────────────────────────────────────
function Shared.FormatNumber(n)
    local s = tostring(math.floor(n))
    local result = ''
    local len    = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. '.'
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-- ── DATO TJEK ───────────────────────────────────────────
function Shared.IsEventActive()
    if not Config.EnableDateCheck then return true end
    local now   = os.date('*t')
    local month = now.month
    local day   = now.day

    local startOk = (month > Config.StartMonth) or (month == Config.StartMonth and day >= Config.StartDay)
    local endOk   = (month < Config.EndMonth)   or (month == Config.EndMonth   and day <= Config.EndDay)
    return startOk and endOk
end

-- ── CHRISTMAS BOX ROLLER ────────────────────────────────
-- Weighted roll (1-100). Config.ChristmasBoxRewards' chance-værdier
-- summerer til 100, så dette er en ren, forudsigelig fordeling - ikke
-- den slags "independent roll + tilfældig fallback" der findes i nogle
-- andre scripts og skævvrider den reelle sandsynlighed.
function Shared.RollChristmasBox()
    local roll = math.random(1, 100)
    local cum  = 0
    for _, reward in ipairs(Config.ChristmasBoxRewards) do
        cum = cum + reward.chance
        if roll <= cum then
            return reward
        end
    end
    return Config.ChristmasBoxRewards[#Config.ChristmasBoxRewards]
end

-- ── OPGAVE HELPERS ──────────────────────────────────────
function Shared.GetTaskConfig(id)
    for _, t in ipairs(Config.DailyTasks) do
        if t.id == id then return t, 'daily' end
    end
    for _, t in ipairs(Config.WeeklyTasks) do
        if t.id == id then return t, 'weekly' end
    end
    return nil, nil
end

function Shared.PickRandomTasks(pool, count)
    local copy    = {}
    for _, v in ipairs(pool) do copy[#copy + 1] = v end

    local picked = {}
    local max    = math.min(count, #copy)
    for i = 1, max do
        local idx    = math.random(1, #copy)
        picked[#picked + 1] = copy[idx]
        table.remove(copy, idx)
    end
    return picked
end

-- ── DEBUG ────────────────────────────────────────────────
function Shared.Debug(...)
    if Config.Debug then
        print('[mm-christmas]', ...)
    end
end

function Shared.Warn(...)
    print('^1[mm-christmas]^0', ...)
end

-- ── DISTANCE HJÆLPER ────────────────────────────────────
function Shared.Distance(v1, v2)
    local dx = v1.x - v2.x
    local dy = v1.y - v2.y
    local dz = v1.z - v2.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ── VALIDERINGS-HJÆLPERE ─────────────────────────────────
-- Bruges konsekvent server-side til at validere alt input fra clienten,
-- så vi aldrig stoler blindt på typen/formen af det clienten sender.
function Shared.Clamp(n, min, max)
    n = tonumber(n)
    if not n then return min end
    if n < min then return min end
    if n > max then return max end
    return n
end

function Shared.IsInteger(n)
    return type(n) == 'number' and n == math.floor(n) and n == n -- n==n udelukker NaN
end

function Shared.ToPositiveInt(n, default)
    n = tonumber(n)
    if not n then return default end
    n = math.floor(n)
    if n < 0 or n ~= n then return default end
    return n
end
