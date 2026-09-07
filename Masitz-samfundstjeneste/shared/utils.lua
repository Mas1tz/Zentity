Utils = Utils or {}

-- ------------------------------------------------------------
-- MATH
-- ------------------------------------------------------------
function Utils.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utils.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

-- ------------------------------------------------------------
-- TRUST FACTOR — FARVEGRADIENT
-- Returnerer en hex-farve ud fra tillidsfaktor-procenten, efter reglerne:
--   90-100%  Grøn
--   80-89%   Grøn/gul overgang
--   70-79%   Orange
--   60-69%   Orange/rød overgang
--   0-59%    Rød
-- Selve overgangene er lineært interpolerede, så farven skifter jævnt i
-- stedet for i hårde spring hver gang man krydser en tærskel.
-- ------------------------------------------------------------
local COLOR_GREEN  = { r = 0,   g = 255, b = 136 } -- #00ff88
local COLOR_YELLOW = { r = 255, g = 214, b = 0   } -- #ffd600
local COLOR_ORANGE = { r = 255, g = 145, b = 0   } -- #ff9100
local COLOR_RED    = { r = 255, g = 82,  b = 82  } -- #ff5252

local function LerpColor(a, b, t)
    return {
        r = math.floor(a.r + (b.r - a.r) * t),
        g = math.floor(a.g + (b.g - a.g) * t),
        b = math.floor(a.b + (b.b - a.b) * t),
    }
end

local function ColorToHex(c)
    return ('#%02x%02x%02x'):format(c.r, c.g, c.b)
end

function Utils.GetTrustColor(percent)
    percent = Utils.Clamp(tonumber(percent) or 0, 0, 100)

    local color

    if percent >= 90 then
        color = COLOR_GREEN
    elseif percent >= 80 then
        -- 80-89: grøn -> gul
        local t = (90 - percent) / 10
        color = LerpColor(COLOR_GREEN, COLOR_YELLOW, t)
    elseif percent >= 70 then
        color = COLOR_ORANGE
    elseif percent >= 60 then
        -- 60-69: orange -> rød
        local t = (70 - percent) / 10
        color = LerpColor(COLOR_ORANGE, COLOR_RED, t)
    else
        color = COLOR_RED
    end

    return ColorToHex(color)
end

-- ------------------------------------------------------------
-- JSON-safe encode/decode wrappers (defensive, crasher aldrig scriptet)
-- ------------------------------------------------------------
function Utils.SafeJsonEncode(value)
    local ok, result = pcall(json.encode, value)
    if ok then return result end
    return '{}'
end

function Utils.SafeJsonDecode(str)
    if not str or str == '' then return nil end
    local ok, result = pcall(json.decode, str)
    if ok then return result end
    return nil
end
