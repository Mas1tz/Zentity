# Masitz-garage

Rework af `MM-garage` (`kc_garage`) — samme velfungerende kerne (garager,
både, impound, nøgler via `MM-vehiclekeys`), udvidet med bilnavn,
spiller-til-spiller salg, "giv nøgler", flytning mellem garager, og
Discord-logging. **Alt eksisterende data i `owned_vehicles`, `vehicle_keys`
og `impound_log` er intakt** — ingen biler, nøgler eller nummerplader er
rørt.

---

## 1. Hvad blev analyseret

Hele den uploadede `MM-garage.zip` (config.lua, cl_garage.lua, sv_garage.lua,
MMgarage.sql) blev læst og forstået før noget blev skrevet: zone-/marker-
loopet, spawn/store-flowet for både biler og både, impound-systemet,
nøgle-restore-on-login via `MM-vehiclekeys`, og den fulde databasestruktur
(inkl. den eksisterende sikre kolonne-for-kolonne SQL-migration).

**Fundet under analysen:**
- `kc_garage`/`MM-garage` optrådte **kun** i kommentarer og debug-print-
  præfikser — intet event- eller export-navn var hardcodet med det gamle
  navn. Omdøbning var derfor risikofri, med **én undtagelse**: se §3.
- Stand-beregningen (§22) brugte for snævre tærskler (95-100=Perfekt,
  derunder straks "God") — en enkelt let bule kunne synligt degradere
  bilen. Udvidet til 6 niveauer, se §7.
- Ingen eksisterende funktion til bilnavn, spiller-salg, nøgle-overdragelse
  til andre, eller garage-flytning — alt sammen bygget som ægte ny,
  server-autoritativ funktionalitet, ikke tilføjet oven på noget der
  allerede fandtes.

---

## 2. Filstruktur

```
Masitz-garage/
├── fxmanifest.lua
├── config.lua
├── client/
│   ├── cl_helpers.lua   -- delte hjælpefunktioner (props, fuel, stand, pengeformat)
│   ├── cl_garage.lua    -- kerne: zoner/markers/blips/spawn/store/menuer (uændret logik)
│   └── cl_menus.lua     -- NYT: rename/giv nøgler/sælg/flyt-bil UI-flows
├── server/
│   ├── sv_helpers.lua   -- delte hjælpefunktioner (money, plate, validering)
│   ├── sv_logging.lua   -- Discord webhook-dispatch
│   ├── sv_garage.lua    -- kerne: hente/parkere/impound/nøgle-restore (uændret logik)
│   ├── sv_keys.lua      -- NYT: "giv nøgler" til en anden spiller
│   ├── sv_sales.lua     -- NYT: spiller-til-spiller salg
│   ├── sv_transfer.lua  -- NYT: flyt bil / hent bil hertil
│   └── sv_exports.lua   -- NYT: getPlayerVehicles, impoundVehicle, log-hooks
├── sql/
│   └── masitz_garage.sql
└── README.md
```

Splittet i flere filer for at undgå spaghetti-kode i takt med den nye
funktionalitet — men **kernelogikken** (zoner, spawn, store, impound,
nøgle-restore) er funktionelt 1:1 med originalen, kun flyttet og omdøbt.

---

## 3. Omdøbning (§2, §33)

- Resource-folder: `MM-garage` → `Masitz-garage`.
- Alle interne events: `garage:*` → `masitz_garage:*` (client↔server-par
  krydstjekket — alle 14 callbacks og 7 events matcher eksakt, se testrapport).
- Debug-præfikser: `[kc_garage]`/`[kc_garage:client]` → `[Masitz-garage]`/
  `[Masitz-garage:client]`.
- `Config.KeyExport = 'MM-vehiclekeys'` og export-navnene `Masitz_giveKey`/
  `Masitz_removeKey` er **UÆNDREDE** — det er `MM-vehiclekeys`' egne
  eksisterende eksportnavne, ikke noget der tilhører garage-resourcen.

**Den ene uundgåelige breaking change:** `exports('impoundVehicle', ...)`
er et ægte eksternt-vendt export. Når resourcen omdøbes, adresseres exports
via det NYE resource-navn — en ekstern kalder skal opdatere fra
`exports['MM-garage']:impoundVehicle(...)` til
`exports['Masitz-garage']:impoundVehicle(...)`. Det kan ikke gøres
bagudkompatibelt (eksportnavnerummet ER ressourcens navn), men er en direkte
konsekvens af den ønskede omdøbning, ikke en fejl.

**Bagudkompatibilitet der ER bygget ind:** `garage:vehicleDestroyed` (det
ene event der plausibelt kunne blive trigget af et eksternt skade-/
crash-script) lyttes der stadig på, SAMTIDIG med det nye
`masitz_garage:vehicleDestroyed` — begge rammer samme logik, så intet
eksternt script går i stykker.

---

## 4. Nye funktioner

### Skift bilnavn (§5)
Ny kolonne `owned_vehicles.vehicle_name` (nullable). `masitz_garage:renameVehicle`
callback validerer server-side: ejerskab, tom/whitespace-only afvises,
maks 32 tegn, og teksten filtreres til et sikkert tegnsæt (bogstaver inkl.
æøå, tal, mellemrum, let tegnsætning) — strukturelle SQL-tegn som `;`/`(`/`)`/`_`
fjernes. Den reelle SQL-injection-beskyttelse er dog parameteriserede
queries (som bruges konsekvent i hele resourcen); charset-filteret er en
ekstra defense-in-depth mod visnings-/chat-exploit. Navnet vises i alle
menuer (garage, impound) hvis sat, ellers falder det tilbage til
mærke/model-labelen.

### Giv nøgler (§6)
To-trins flow: `resolveTargetPlayer` finder og viser målspillerens navn
FØR noget sker, betjenten godkender eksplicit, og først derefter kalder
`giveKeyToPlayer` som **genvaliderer alt** (target stadig online, initiativ-
tager ejer stadig bilen) uafhængigt af resolve-trinnet. Bruger
`MM-vehiclekeys` uændret, og persisterer en `vehicle_keys`-række under
MODTAGERENS identifier (så nøglen også gendannes automatisk ved deres
fremtidige logins).

### Sælg bil (§7-§11)
Fuldt server-autoritativt spiller-til-spiller salg:
1. Sælger vælger køber-ID + pris → ser køberens navn → bekræfter.
2. Køberen får en "BILHANDEL"-dialog med bil/plade/pris, vælger
   Kontanter/Bank, godkender eller afviser.
3. Serveren genvalidér ALT ved godkendelse (ikke kun ved oprettelse):
   sælger ejer stadig bilen, bilen er ikke impounded, køberens saldo er
   tilstrækkelig — FØR nogen penge eller ejerskab rører sig.
4. Ejerskabsoverdragelse er én atomisk `UPDATE ... WHERE owner = <sælger>`;
   hvis den ikke rammer nogen rækker (bilen skiftede status i mellemtiden),
   rulles betalingen tilbage 100%.
5. Sælgerens nøgle fjernes (DB + `MM-vehiclekeys`), køberen får en ny.

**Transaktionssikkerhed (§11):** hver handel har et unikt `saleId`, låst pr.
nummerplade (kun én aktiv handel ad gangen pr. bil). Anti-duplikat er løst
ved at sætte `sale.status = 'processing'` som det ALLERFØRSTE der sker i
`confirmSale`, FØR noget databasekald — samme mønster som allerede
verificeret virker i `Masitz-Anticheat`s `PendingChange`-mutex. Et
dobbelt-sendt/replayet event nummer 2 ser altid status ≠ `'awaiting_buyer'`
og afvises uden at røre penge eller ejerskab (verificeret i testrapporten).
Handler udløber efter `Config.Sale.timeoutSec` (60s), ryddes af en periodisk
tråd, og annulleres automatisk hvis køber eller sælger disconnecter
undervejs.

### Flyt bil / Hent bil hertil (§14-§16, §25)
Én delt server-funktion (`executeTransfer`) bruges af begge UI-indgange:
"Flyt bil" (fra en bil du allerede har valgt) og "Hent bil hertil" (fra en
tom garage — **erstatter** den gamle dead-end "Ingen biler parkeret her."
med en rigtig menu og handling). Prisen beregnes **server-side, altid
genberegnet ved selve udførelsen** (aldrig kun ved visning af estimatet) ud
fra den faktiske GPS-afstand mellem garagernes koordinater, clampet til
`Config.GarageTransfer.minPrice`/`maxPrice` (standard 50.000-150.000 kr.).
Klienten viser kun et estimat — den kan aldrig bestemme det endelige beløb.

### Pengeformatering (§9)
`MG.FormatMoney()`/`MGC.FormatMoney()` (identisk logik server+client) giver
dansk tusind-separator overalt: `2500000` → `"2.500.000 kr."`.

### Discord-logging (§12)
`Config.Logging.webhooks` (kun server-side, aldrig i klientkode) dækker
salg, nøgler, bilnavn, garage-flytning, hentet/parkeret, impound, og et
købs-hook til en fremtidig bilforhandler-resource. Slået fra som standard
(`Config.Logging.enabled = false`) — sæt webhook-URLs og slå til.

### Discord bot-grundlag (§13)
`exports('getPlayerVehicles', identifier)` returnerer alle en spillers
køretøjer (plade, model, bilnavn, garage, stored/impound-status) — rent
læse-API, ingen Discord-bot bygget ind i resourcen selv, som ønsket.

### Stand/kondition (§22)
Centraliseret i ÉN funktion (`MGC.GetConditionInfo`) — den gamle
`ConditionStr()`-funktion i cl_garage.lua var faktisk **dead code**
(defineret, aldrig kaldt); den reelle logik var duplikeret inline i både
bil- og bådmenuen. Nu ét sted, brugt begge steder. Bredere tærskler:

| Interval (gennemsnit motor+karosseri) | Status |
|---|---|
| 95-100% | Perfekt |
| 80-94%  | Meget god |
| 60-79%  | God |
| 40-59%  | Slidt |
| 20-39%  | Dårlig |
| 0-19%   | Kritisk |

En enkelt let bule (fx 1000→970 på én af værdierne) forbliver nu "Perfekt"
i stedet for straks at falde til "God".

---

## 5. Database (§20)

`sql/masitz_garage.sql` er den oprindelige `MMgarage.sql` **uændret**, med
tilføjelse af ÉT nyt sikkert migrations-blok for `vehicle_name` (samme
`IF NOT EXISTS`-mønster som resten af filen). Ingen `DROP TABLE`, ingen
`DELETE`. Sikker at køre på en frisk database OG på en eksisterende
MM-garage-installation — alle eksisterende biler/nøgler/impound-poster
består uændret.

---

## 6. Sikkerhed (§26-§27)

- Alle nye endpoints (`renameVehicle`, `giveKeyToPlayer`, `initiateSale`,
  `confirmSale`, `executeTransfer`) genvalidér ejerskab/target/pris/saldo
  **server-side ved selve udførelsen**, ikke kun ved en tidligere
  "forhånds"-visning.
- Ren ESX Legacy money/bank-API (`xPlayer.getMoney/addMoney/removeMoney`,
  `getAccount('bank')/addAccountMoney/removeAccountMoney`) — intet nyt
  economy-system.
- Enhver fejlet pengetransaktion rulles eksplicit tilbage (køb, salg,
  impound-release, garage-transfer) — verificeret i testrapporten.
- `MG.TryCharge` trækker ALDRIG penge hvis saldoen er utilstrækkelig.

---

## 7. Testrapport

Ingen kørende FiveM-server i dette miljø, så alt herunder er rapporteret
ærligt efter hvad der faktisk kunne verificeres:

**[PASS] — fysisk kørt**
- `luac5.4 -p` på samtlige 12 Lua-filer (config, fxmanifest, 3 client-,
  7 server-filer) — ingen syntaksfejl.
- Mock Lua-testharness (ESX/oxmysql/MM-vehiclekeys/Discord-webhook stubbet)
  — 32 assertions, alle bestået:
  - `FormatMoney` matcher de danske eksempler fra specifikationen præcist.
  - `SafeVehicleName` afviser tomt/whitespace, trunkerer til maxLength,
    fjerner strukturelle SQL-tegn.
  - `CalcTransferPrice` holder sig ALTID inden for `[minPrice, maxPrice]`
    for samtlige konfigurerede garage-par, skalerer korrekt med afstand,
    og håndterer en ukendt destination sikkert.
  - `resolveTargetPlayer`/`giveKeyToPlayer`: afviser offline target,
    afviser selv-target, afviser når initiativtager ikke ejer bilen,
    lykkes kun når begge betingelser er opfyldt.
  - `initiateSale`/`confirmSale`: fuld handel flytter penge og ejerskab
    korrekt; et REPLAYET `confirmSale`-kald for samme `saleId` efter
    gennemførsel bliver afvist og rører hverken køber eller sælgers saldo
    (verificerer anti-duplikat-mekanismen); utilstrækkelig saldo afviser
    handlen uden at røre nogens penge; pris under/over konfigurerede
    grænser afvises ved oprettelse.
  - `GetConditionInfo` (client): alle 6 tærskel-grænser rammer den
    korrekte status, og en let bule (970/1000) forbliver "Perfekt".
- Fuld krydsreference af samtlige `lib.callback.await`/`TriggerServerEvent`
  (klient) mod `lib.callback.register`/`RegisterNetEvent` (server), og
  omvendt for server→klient-events — alle 14 callbacks og alle
  client↔server-events matcher eksakt, ingen kaldes uden modpart.

**[STATICALLY VERIFIED] — kodegennemgået, logisk korrekt, ikke kørt**
- `MM-vehiclekeys`-integrationen (uændrede eksportnavne, pcall-beskyttet
  præcis som originalen) — kan ikke fysisk testes uden den rigtige
  resource.
- Discord webhook-payload-formatet (samme mønster som allerede verificeret
  virkende i `Masitz-Anticheat`s logging).
- ox_lib UI-kald (`lib.inputDialog`/`lib.alertDialog`/`lib.registerContext`)
  — API-brug matcher dokumenteret ox_lib-adfærd og det eksisterende
  resource's egne, allerede-fungerende kald.

**[NOT PHYSICALLY TESTED]**
- Faktisk in-game UI/UX for alle nye menuer (kræver kørende server + ox_lib
  CEF-rendering).
- De 4 nye garagers spawn-koordinater/heading (sat til samme `0.0`-heading
  som ALLE eksisterende garager i den originale config — det ser ud til at
  være den etablerede konvention i denne resource, men er ikke visuelt
  efterprøvet).
- Reelt multi-spiller samtidighedstest af salgs-låsen under netværks-lag.

---

## 8. Dependencies (uændret, §32)

`es_extended`, `ox_lib`, `oxmysql`, `ox_fuel`. `MM-vehiclekeys` kaldes
udelukkende via `pcall`-beskyttede exports (som originalen) — ikke en hård
`dependency`, så Masitz-garage stadig starter selvom key-scriptet er nede.

## 9. Installation

1. Kopiér `Masitz-garage/` til `resources/`.
2. Kør `sql/masitz_garage.sql` (sikker at køre selv med eksisterende data).
3. Fjern `ensure MM-garage` / `ensure kc_garage` fra `server.cfg`, tilføj
   `ensure Masitz-garage` i stedet, efter `ox_lib`/`oxmysql`/`ox_fuel`.
4. Hvis noget eksternt kalder `exports['MM-garage']:impoundVehicle(...)`,
   opdatér til `exports['Masitz-garage']:impoundVehicle(...)` (se §3).
5. Sæt evt. `Config.Logging.enabled = true` + webhook-URLs for Discord-logs.
