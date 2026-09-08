-- ============================================================
--  Masitz-InventoryLogs | server/main.lua
--  Bootstrap: sanity checks + a one-line ready banner. Loaded last
--  so every other module (Utils, Framework, Discord, Database,
--  Logger, hooks) already exists by the time this runs.
-- ============================================================

CreateThread(function()
    if Config.Storage ~= 'discord' and Config.Storage ~= 'database' and Config.Storage ~= 'both' then
        Utils.Warn(('Config.Storage is set to an invalid value ("%s"). Falling back to "discord".'):format(tostring(Config.Storage)))
        Config.Storage = 'discord'
    end

    if (Config.Storage == 'discord' or Config.Storage == 'both') and not Config.Discord.enabled then
        Utils.Warn('Config.Storage includes Discord but Config.Discord.enabled is false - no Discord logs will be sent.')
    end

    while GetResourceState('ox_inventory') ~= 'started' do
        Wait(250)
    end

    print(('^2[Masitz-InventoryLogs]^7 Ready. Storage mode: ^3%s^7. Debug: ^3%s^7.'):format(
        Config.Storage, tostring(Config.Debug)
    ))
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    -- ox_inventory automatically removes every hook registered by this
    -- resource on 'onResourceStop' (verified in modules/hooks/server.lua -
    -- registerHook ties each hook to GetInvokingResource() and cleans up
    -- via its own AddEventHandler('onResourceStop', ...)), so no manual
    -- exports.ox_inventory:removeHooks() call is required here. We still
    -- call it defensively in case a future ox_inventory version changes
    -- that behaviour.
    if GetResourceState('ox_inventory') == 'started' then
        pcall(function()
            exports.ox_inventory:removeHooks()
        end)
    end
end)
