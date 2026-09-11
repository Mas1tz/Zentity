-- ============================================================
--  Masitz-Tweaks | config.lua
--  Samlet erstatning for: disableDispatch, noemergencycars,
--  removeAIcops, disable_radio.
-- ============================================================

Config = {}

-- Konsol-logs prefixet [Masitz-Tweaks]. Ingen spam når false.
Config.Debug = false

-- ─── FEATURE TOGGLES ─────────────────────────────────────────
Config.DisableDispatch            = true   -- erstatter disableDispatch
Config.DisableAICops              = true   -- erstatter removeAIcops
Config.DisableEmergencyTraffic    = true   -- ambient emergency-køretøjer i trafikken (§7)
Config.RestrictEmergencyVehicles  = true   -- kun police/ambulance-job må FØRE emergency-køretøjer (den fikserede "noemergencycars"-adfærd)
Config.DisableRadio               = true   -- erstatter disable_radio

-- ─── DISPATCH ────────────────────────────────────────────────
-- EnableDispatchService er IKKE en "ThisFrame"-native — den er
-- persistent og skal kun sættes én gang pr. service-index (se README).
-- Kun wanted-level skal reapplyes periodisk, da andre
-- scripts/events kan hæve den igen.
Config.DispatchServiceCount   = 12     -- service-index 1-12 (matcher det oprindelige script)
Config.WantedLevelInterval    = 1000   -- ms — hvor tit wanted level tvinges til 0

-- ─── AI COPS ─────────────────────────────────────────────────
-- SetCreateRandomCops-familien er persistent (ikke "ThisFrame") og
-- sættes derfor kun én gang ved start/spawn. AICopsSafetyInterval er
-- en billig sikkerhedsnet-reapplicering + én ClearAreaOfCops-sweep,
-- til at fange edge-cases (andre resources der nulstiller
-- population-flags, eller scriptede cop-peds spawnet direkte uden om
-- population-systemet). Sæt til 0 for at slå sikkerhedsnettet helt fra.
Config.AICopsSafetyInterval   = 30000  -- ms
Config.AICopsClearRadius      = 150.0  -- meter — kun brugt til den periodiske sweep, IKKE hver frame

-- ─── EMERGENCY-TRAFIK (ambient, ikke spiller-kørte) ───────────
-- GTA har ingen native til permanent at undertrykke én bestemt
-- køretøjsklasse fra ambient population — dette KRÆVER derfor en
-- periodisk (men billig og sjælden) scan. Se README §"Hvorfor dette
-- ikke kan være 0.00 ms".
Config.EmergencyTrafficSweepInterval = 5000  -- ms
Config.EmergencyVehicleClass         = 18    -- GTA vehicle class 18 = "Emergency" (politi/ambulance/brand)

-- ─── FØRSTE-RESPONDENT KØRSELS-SPÆRRE ──────────────────────────
-- Hvilke ESX-jobs må sidde på FØRERSÆDET af et emergency-køretøj
-- uden det bliver gjort udrivable. Kræver ESX (eneste feature i
-- denne resource der gør).
Config.AllowedEmergencyJobs = {
    police    = true,
    ambulance = true,
}

-- ─── RADIO ───────────────────────────────────────────────────
Config.RadioCheckInterval = 1000  -- ms — uændret fra det oprindelige (allerede ~0.00 ms)
