-- ============================================================
--  kc_mdt | shared/sh_utils.lua
--  Shared helpers used by client and server.
-- ============================================================

KC = KC or {}

-- ─── DEBUG LOGGING ───────────────────────────────────────────
function KC.log(scope, msg, ...)
    if not Config.Debug then return end
    if select('#', ...) > 0 then
        msg = msg:format(...)
    end
    print(('^5[kc_mdt:%s]^7 %s'):format(scope, msg))
end

function KC.warn(scope, msg, ...)
    if select('#', ...) > 0 then msg = msg:format(...) end
    print(('^3[kc_mdt:%s WARN]^7 %s'):format(scope, msg))
end

function KC.err(scope, msg, ...)
    if select('#', ...) > 0 then msg = msg:format(...) end
    print(('^1[kc_mdt:%s ERROR]^7 %s'):format(scope, msg))
end

-- ─── STRING / VALIDATION HELPERS ─────────────────────────────
function KC.trim(s)
    if not s then return '' end
    return (tostring(s):gsub('^%s+',''):gsub('%s+$',''))
end

function KC.normPlate(plate)
    if not plate then return nil end
    local p = tostring(plate):gsub('%s+',''):upper()
    if p == '' then return nil end
    return p
end

function KC.normUsername(name)
    if not name then return nil end
    return tostring(name):lower():gsub('%s+','')
end

function KC.isValidUsername(name)
    if type(name) ~= 'string' then return false end
    local len = #name
    if len < Config.Security.minUsernameLen or len > Config.Security.maxUsernameLen then
        return false
    end
    if not name:match(Config.Security.usernamePattern) then return false end
    return true
end

function KC.isValidPassword(pw)
    if type(pw) ~= 'string' then return false end
    local len = #pw
    return len >= Config.Security.minPasswordLen and len <= Config.Security.maxPasswordLen
end

function KC.clampInt(v, lo, hi)
    v = tonumber(v) or lo
    if v < lo then return lo end
    if v > hi then return hi end
    return math.floor(v)
end

function KC.safeStr(v, maxLen)
    if v == nil then return '' end
    local s = tostring(v)
    if maxLen and #s > maxLen then s = s:sub(1, maxLen) end
    return s
end