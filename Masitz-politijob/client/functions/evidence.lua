-- ============================================================
-- MM-PolitiJob – client/functions/evidence.lua  (NY)
-- Evidence stash på Config.EvidenceStash.coords, tilgået via
-- ox_target. Reel adgangskontrol sker i ox_inventory selv
-- (RegisterStash-groups i server/evidence.lua) — canInteract her
-- er kun for hurtig client-side UX-feedback.
-- ============================================================

CreateThread(function()
    if not Config.EvidenceStash or not Config.EvidenceStash.enabled then return end

    exports.ox_target:addSphereZone({
        coords = Config.EvidenceStash.coords,
        radius = 1.5,
        debug  = Config.Debug or false,
        options = {
            {
                name  = 'mm_evidence_stash',
                label = 'Åbn Evidence',
                icon  = 'fa-solid fa-boxes-stacked',
                distance = 2.0,
                canInteract = function()
                    return MM.Framework.IsPolice()
                end,
                onSelect = function()
                    exports.ox_inventory:openInventory('stash', 'police_evidence')
                end,
            }
        }
    })

    if Config.Debug then
        print('[MM-PolitiJob] Evidence target-zone oprettet.')
    end
end)
