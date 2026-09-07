-- ============================================================
--  mm-adminpakke V2 | server/players.lua
--
--  Alt der handler om at læse spiller-information fra ESX. Steam-data
--  hentes bevidst IKKE for hele spillerlisten på én gang (se
--  GetPlayerProfile) - kun for den spiller en admin rent faktisk
--  kigger på, for at undgå unødvendige Steam API-kald.
-- ============================================================

local ESX = exports['es_extended']:getSharedObject()

local Players = {}

local function DebugPrint(fmt, ...)
    if not Config.Debug then return end
    print(('[mm-adminpakke] ' .. fmt):format(...))
end

--- Kort spillerliste til venstre-kolonnen (navn, id, job, ping).
function Players.GetList()
    local result = {}

    for _, src in ipairs(GetPlayers()) do
        local id = tonumber(src)
        if id then
            local xPlayer = ESX.GetPlayerFromId(id)
            local job = xPlayer and xPlayer.getJob and xPlayer.getJob() or nil

            result[#result + 1] = {
                id      = id,
                name    = (xPlayer and xPlayer.getName and xPlayer.getName()) or GetPlayerName(id) or ('Ukendt (%s)'):format(id),
                job     = job and job.label or nil,
                ping    = GetPlayerPing(id) or 0,
            }
        end
    end

    table.sort(result, function(a, b) return a.id < b.id end)
    return result
end

--- Fuld profil til spillerkortet, inkl. Steam-opslag (lazy, cached).
--- Kaldes kun for ÉN spiller ad gangen, når en admin faktisk vælger
--- eller åbner detaljer for den pågældende spiller.
function Players.GetProfile(targetId)
    local xPlayer = ESX.GetPlayerFromId(targetId)
    if not xPlayer then return nil end

    local job = xPlayer.getJob and xPlayer.getJob() or nil
    local identifier = xPlayer.identifier or (xPlayer.getIdentifier and xPlayer.getIdentifier())

    local profile = {
        id         = targetId,
        name       = (xPlayer.getName and xPlayer.getName()) or GetPlayerName(targetId),
        identifier = identifier,
        job        = job and job.label or nil,
        jobGrade   = job and job.grade_label or nil,
        ping       = GetPlayerPing(targetId) or 0,
        steamName  = nil,
        steamAvatar = nil,
    }

    if Config.Steam.Enabled and AdminSteam then
        local steamProfile = AdminSteam.GetProfile(targetId)
        if steamProfile then
            profile.steamName   = steamProfile.personaname
            profile.steamAvatar = steamProfile.avatarfull
        end
    end

    return profile
end

_G.AdminPlayers = Players
