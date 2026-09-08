-- ============================================================
-- MM-PolitiJob – server/evidence.lua  (NY)
-- Politiets evidence-stash. Registreret som ox_inventory stash,
-- låst til Config.EvidenceStash.job via ox_inventory's egne
-- groups (samme mønster som PoliceArmoury-shoppen i loadout.lua).
-- ============================================================

if Config.EvidenceStash and Config.EvidenceStash.enabled then
    exports.ox_inventory:RegisterStash(
        'police_evidence',
        Config.EvidenceStash.label or 'Politi Evidence',
        Config.EvidenceStash.slots or 100,
        Config.EvidenceStash.weight or 4000000,
        false,
        { [Config.EvidenceStash.job or 'police'] = 0 }
    )

    if Config.Debug then
        print('[MM-PolitiJob] Evidence stash registreret.')
    end
end
