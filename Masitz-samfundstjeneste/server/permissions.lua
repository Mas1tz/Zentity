--[[
    Permissions-modulet er BEVIDST det eneste sted i hele resourcen der
    afgør om en spiller er Staff eller Owner. Alt andet (kommandoer, NUI-
    callbacks, events) skal spørge HER — aldrig lave sit eget gruppetjek.
    Det gør det trivielt at bytte owner-tjekket til rigtig Discord OAuth
    senere: kun IsOwner() skal ændres, resten af systemet er upåvirket.
]]

local ESX = exports['es_extended']:getSharedObject()

Permissions = {}

local function GetDiscordId(source)
    if not source or source == 0 then return nil end

    for _, id in ipairs(GetPlayerIdentifiers(source) or {}) do
        if id:find('discord:') then
            return id:gsub('discord:', '')
        end
    end

    return nil
end

-- Konsol / eksterne systemer (Discord-bot osv.) er fuldt betroet, ligesom i V1.
local function IsTrustedExternal(source)
    return source == 0 or source == nil or source == ''
end

function Permissions.IsOwner(source)
    if IsTrustedExternal(source) then
        return true
    end

    return GetDiscordId(source) == Config.Samfundstjeneste.Permissions.OwnerDiscordId
end

function Permissions.IsStaff(source)
    if IsTrustedExternal(source) then
        return true
    end

    if Permissions.IsOwner(source) then
        return true
    end

    local xPlayer = ESX.GetPlayerFromId(source)
    return xPlayer ~= nil and Config.Samfundstjeneste.Permissions.StaffGroups[xPlayer.getGroup()] == true
end

-- Eksporteres så html/NUI-callbacks og evt. andre resources kan spørge
-- uden at skulle kende til den interne implementation.
exports('IsOwner', Permissions.IsOwner)
exports('IsStaff', Permissions.IsStaff)
