# Masitz-mehandler

Automatiske `/me`-handlinger til ESX Legacy + ox_inventory. Sender selv en
`/me`-besked, når spilleren udfører relevante handlinger (åbner bagagerum,
handskerum, ind-/udstiger et køretøj, m.m.) - uden at spilleren selv skal
skrive noget.

---

## Hvordan det virker (kort forklaring)

Scriptet lytter IKKE efter en bestemt fysisk tast. I stedet reagerer det på
**resultatet** af en handling, uanset hvilken tast/kommando/ressource der
udløste den:

- **Bagagerum/handskerum:** ox_inventory sætter altid en player *state bag*
  (`invOpen`) til `true`/`false` lige inden dens UI åbnes/lukkes - uanset om
  det skete via ox_inventory's eget keybind, et ox_target-valg, eller et
  helt tredje script der kalder `exports.ox_inventory:openInventory(...)`.
  Masitz-mehandler lytter på præcis dette state bag-flag. Se afsnittet
  "ox_inventory-integration" herunder for den fulde tekniske forklaring.
- **`/me`-afsendelse:** Sker via `ExecuteCommand('me <besked>')` - PRÆCIS
  som hvis spilleren selv havde skrevet det i chatten. FiveM videresender
  automatisk en ukendt client-kommando til serveren med spillerens rigtige
  identitet bevaret, så dette rammer jeres eksisterende `/me`-system
  korrekt, uanset om det er registreret client- eller server-side.

---

## Resource-struktur

```
Masitz-mehandler/
├── fxmanifest.lua
├── config.lua
├── client/
│   └── client.lua
├── server/
│   └── server.lua
└── README.md
```

---

## 1. Installation

1. Kopiér `Masitz-mehandler/`-mappen til din `resources/`-mappe.
2. Tilføj `ensure Masitz-mehandler` til `server.cfg` **efter** `ox_lib` og
   `ox_inventory`.
3. Tilret `config.lua` efter behov (se afsnit 4).
4. Genstart serveren, eller kør `refresh` + `ensure Masitz-mehandler`.

## 2. Dependencies

- **ox_lib** (påkrævet) - bruges til `cache.vehicle`/`cache.seat`/`cache.ped`
  og til at registrere handlingernes cooldown-frie, event-drevne logik.
- **ox_inventory** (påkrævet) - kilden til bagagerum/handskerum-detektionen.
  Scriptet starter og fungerer stadig selvom ox_inventory af en eller anden
  grund ikke skulle være startet, men bagagerum/handskerum-delen er
  naturligvis afhængig af den.
- **ESX Legacy** er IKKE en hård dependency i `fxmanifest.lua` - scriptet
  bruger ingen ESX-specifikke funktioner direkte (kun natives + ox_lib +
  det eksisterende `/me`-system), så det holder afhængighederne minimale
  som ønsket.

## 3. Sådan startes resourcen

`ensure Masitz-mehandler` i `server.cfg`, efter `ox_lib` og `ox_inventory`.
Ingen database, ingen yderligere opsætning.

## 4. Sådan fungerer config'en

Alt styres fra `config.lua` via `Config.MeHandler`:

- `M.Enabled` - global til/fra-knap.
- `M.Debug` - se afsnit 9.
- `M.Cooldown` - standard cooldown (ms) pr. handling, kan overskrives pr.
  handling.
- `M.MeIntegration` - hvordan `/me` faktisk afsendes (se afsnit "VIGTIGT
  OM /ME" i den oprindelige specifikation - opsummeret: `Mode = 'command'`
  er standard og anbefalet).
- `M.Actions` - selve `/me`-beskederne og om de er aktive. Dette er den
  ENESTE tabel der indeholder tekst - alt andet konfig refererer blot til
  et action-id herfra.
- `M.Inventory` - detektions-specifikke indstillinger (afstand til nærmeste
  køretøj for bagagerums-klassificering), adskilt fra selve beskederne.

## 5. Sådan tilføjer du nye `/me`-handlinger

**Fra config (permanent):**
```lua
M.Actions.phone_out = { enabled = true, message = 'Tager telefonen frem' }
```
Kald den herefter fra jeres eget script (telefon, våben, restraint, osv.):
```lua
exports['Masitz-mehandler']:TriggerAction('phone_out')
```

**Fra et andet script, helt uden at røre config.lua (dynamisk):**
```lua
exports['Masitz-mehandler']:RegisterAction('cuffs_out', {
    message = 'Tager håndjern frem',
    enabled = true,
    cooldown = 1000, -- valgfri, overskriver M.Cooldown for lige denne handling
})

exports['Masitz-mehandler']:TriggerAction('cuffs_out')
```

Andre nyttige exports:
```lua
exports['Masitz-mehandler']:IsActionEnabled('trunk_open')      -- bool
exports['Masitz-mehandler']:SetActionEnabled('trunk_open', false) -- slå til/fra i runtime
```

Alle exports kører gennem samme cooldown-/enabled-tjek som auto-detektionen,
så der er ingen forskel i beskyttelse mod spam uanset hvordan en handling
udløses.

## 6. Hvordan ox_inventory-integrationen fungerer

Dette er den vigtigste - og mest snørklede - del, så her er den fulde
forklaring, baseret på en gennemgang af jeres faktiske ox_inventory
`client/main.lua` og `modules/inventory/client.lua`:

**Hvad vi ved med sikkerhed (bekræftet i jeres kildekode):**
- ALLE måder at åbne et inventar på (ox_inventory's egne `inv`/`inv2`
  keybinds, ox_target's trunk-mulighed, eller et hvilket som helst andet
  script der kalder `exports.ox_inventory:openInventory(...)`) ender alle i
  den samme funktion, `client.openInventory`, som altid sætter
  `client.player:set('invOpen', true)` (en player state bag) FØR selve
  UI'et vises, og `false` når det lukkes igen.
- Player state bags adresseres offentligt via `'player:<serverId>'`, og
  `AddStateBagChangeHandler` fyrer KUN ved en reel værdiændring - ikke ved
  hver netværks-tick. Det er derfor vi ikke oplever dobbelt-/spam-fyring
  fra selve denne mekanisme.
- Mens spilleren sidder i et køretøj, er der (jf. `inv`/`inv2`-keybindenes
  egen kode) INGEN anden mulighed end at åbne handskerummet - der findes
  ingen vej til at åbne sit eget inventar eller andet mens man sidder ned.
  Derfor: `cache.vehicle` sandt ved `invOpen = true` = **altid** handskerum.
- Uden for et køretøj bruger ox_inventory's egen `Inventory.CanAccessTrunk`
  en ~1.5m-afstandstjek til nærmeste køretøj før trunk-adgang tillades. Vi
  genbruger den samme radius (konfigurerbar via `M.Inventory.TrunkProximity`)
  til at afgøre om et inventar der åbnes udenfor et køretøj sandsynligvis er
  et bagagerum.

**Det ærlige forbehold:** ox_inventory eksponerer INGEN officiel event/export
der fortæller "dette var specifikt et bagagerum" til andre ressourcer - kun
at "et eller andet inventar" blev åbnet/lukket. Trunk-detektionen er derfor
en velbegrundet, kildekode-bekræftet heuristik (afstand til nærmeste
køretøj), ikke en 100% garanteret klassificering. I den sjældne situation
hvor en spiller åbner sit EGET inventar (eller en stash) mens de tilfældigvis
står lige ved siden af en bil, vil scriptet fejlagtigt tro det er et
bagagerum. Vi vurderer denne afvejning som den bedst mulige uden at ændre i
selve ox_inventory (hvilket eksplicit var forbudt) - og uden for et
køretøj/nær et køretøj er langt den mest sandsynlige situation reelt en
bagagerumsåbning. Hvis I opdager falske positiver på jeres server, kan
`M.Inventory.TrunkProximity` strammes op (fx til 1.0-1.2m).

Åbnes et inventar der IKKE kan klassificeres som handskerum eller bagagerum
(spillerens eget inventar, en stash, en shop osv.), sendes bevidst INGEN
`/me` - vi gætter ikke på noget vi ikke kan underbygge.

## 7. Sådan håndteres keybinds

Der hookes IKKE noget fysisk keybind nogen steder i dette script. Det er en
bevidst arkitekturbeslutning: siden alle indgange til at åbne et
sekundært inventar i sidste ende rammer det samme state bag-flag (se
afsnit 6), er detektionen fuldstændig ligeglad med om spilleren har
rebindet ox_inventory's `inv2`, bruger ox_target, eller åbner det fra et
helt tredje script. Ændrer spilleren sit keybind i FiveM Settings, virker
Masitz-mehandler stadig uændret - der er intet at opdatere.

## 8. Fejlfinding (troubleshooting)

| Problem | Løsning |
|---|---|
| Ingen `/me` ved bagagerum/handskerum | Slå `M.Debug = true` til og tjek konsollen for "State bag-lytter... er nu aktiv". Mangler den linje, er ox_inventory muligvis ikke startet endnu, eller startet FØR Masitz-mehandler (tjek load-rækkefølgen i `server.cfg`). |
| `/me` sendes, men intet vises i chatten | Jeres eksisterende `/me`-system reagerer muligvis ikke på `ExecuteCommand`. Tjek at `M.MeIntegration.Command` matcher det faktiske kommandonavn (`me` som standard). |
| To `/me`-beskeder for samme handling | Tjek `M.Cooldown` / handlingens egen `cooldown`-værdi - hvis I selv kalder `TriggerAction` fra et andet script OG auto-detektionen rammer samme handling, er det forventet at kun én går igennem pga. cooldown, men debug-loggen vil vise hvilken der blev blokeret. |
| Forkert klassificering (fx "Åbner bagagerum" ved almindeligt inventar) | Se det ærlige forbehold i afsnit 6 - juster `M.Inventory.TrunkProximity` ned. |
| Fallback-`/me` matcher ikke jeres eksisterende chat-farve/format | Sæt `M.MeIntegration.RegisterFallback = false` hvis I allerede har et `/me`-system - scriptet registrerer aldrig sin egen fallback oven i et eksisterende system (den tjekker `GetRegisteredCommands()` ved opstart), men indstillingen findes for at kunne slå det fuldstændigt fra eksplicit. |

## 9. Debug mode

Sæt `Config.MeHandler.Debug = true` for at få konsol-output (prefixet
`[Masitz-mehandler]`) for:

- Hvilken inventory-type der blev detekteret (bagagerum/handskerum/ukendt),
  og afstanden til det køretøj der blev brugt til at afgøre det.
- Hvornår state bag-lytteren for ox_inventory bliver aktiveret.
- Hvert `/me` der bliver sendt, og for hvilken handling.
- Hver gang en handling bliver blokeret (deaktiveret eller cooldown), og
  hvor lang cooldown der er tilbage.

Er slået fra som standard for at holde konsollen ren i produktion.

---

## Kendte begrænsninger

- Trunk-klassificeringen er en afstandsbaseret heuristik (se afsnit 6), ikke
  en 100% garanteret type-identifikation, da ox_inventory ikke eksponerer
  dette offentligt.
- `/me`-afsendelsen er klient-initieret (ligesom når en spiller selv
  skriver `/me`) - selve sikkerheden/anti-spam på beskedindholdet er jeres
  eksisterende `/me`-systems ansvar. Masitz-mehandler tilføjer udelukkende
  cooldown for at forhindre at DENNE ressource spammer, men opfinder ikke
  en ny tillidsgrænse ud over hvad en spiller allerede kunne gøre manuelt.
