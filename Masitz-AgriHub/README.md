# Masitz-AgriHub

Et komplet agri-logistik/udlejnings/leverings-system til FiveM (ESX Legacy).
Spillere interagerer med AgriHub via en computer-NUI og landmand-NPC'er, løser
leverings-opgaver, lejer maskiner (fra AgriHub eller af hinanden via en fuld
digital kontrakt), handler i shoppen, og transporterer dyr og diesel.

## Afhængigheder

Hårde (`fxmanifest.lua`'s `dependencies`):

- `es_extended` (ESX Legacy)
- `ox_lib`
- `ox_target`
- `ox_inventory`
- `oxmysql`

Blød integration (ikke en hård dependency — kaldes udelukkende via
`pcall`-beskyttede dynamiske exports, se `server/vehicles.lua`):

- `MM-vehiclekeys` — hvis den ikke kører, starter AgriHub stadig, men ingen
  nøgler bliver reelt givet/fjernet (`AH.GiveKey`/`AH.RemoveKey` logger en
  fejl og returnerer `false` i stedet for at crashe).

## Installation

1. Kopiér `Masitz-AgriHub` til din `resources`-mappe.
2. Kør `sql/install.sql` mod din database (kun `CREATE TABLE IF NOT EXISTS`
   — ingen `DROP`, ingen datatab, sikkert at køre igen).
3. Tilføj `ensure Masitz-AgriHub` i `server.cfg` **efter** `es_extended`,
   `ox_lib`, `ox_target`, `ox_inventory`, `oxmysql` og `MM-vehiclekeys`.
4. Åbn `config.lua` og udfyld:
   - `Config.Agri.Items` — match dine egne `ox_inventory`-item-navne.
   - `Config.Agri.Logging.enabled` + `Config.Agri.Logging.webhooks.*` hvis I
     vil have Discord-logging (alle URL'er er tomme som standard).
   - Evt. justér `Config.Agri.Farmers`-koordinater/pedModels til jeres kort.
5. `Config.Agri.Admin.discordId` er allerede sat til den aftalte SUPER_ADMIN
   Discord-ID (`1529563765870301217`). Denne værdi bruges **udelukkende**
   server-side — se Sikkerhed nedenfor.

## Struktur

```
Masitz-AgriHub/
├── fxmanifest.lua
├── config.lua
├── sql/install.sql
├── server/
│   ├── main.lua       -- session/discord/penge/ID-helpers, AH-namespace
│   ├── logging.lua     -- Discord webhooks + DB audit-log
│   ├── access.lua      -- login, adgangsstyring, admin-kommandoer
│   ├── vehicles.lua     -- plader, køretøjs-registry, MM-vehiclekeys
│   ├── shop.lua        -- indkøb (server-prissat)
│   ├── tasks.lua        -- generisk opgave-motor (alle 5 typer)
│   ├── rental.lua        -- udlejning + fuld kontrakt-tilstandsmaskine
│   └── exports.lua       -- exports til andre ressourcer
├── client/
│   ├── main.lua         -- computer ox_target, landmand-NPC'er, NUI åbn/luk
│   ├── vehicles.lua      -- spawn/slet/trailer-helpers, burrito-livery
│   ├── tasks.lua          -- opgave-klient (blip/zone/køretøj pr. type)
│   ├── rental.lua          -- udlejnings-spawn, afleveringszone, fremleje-UI-bro
│   └── nui.lua             -- ALLE NUI-callback-bridges
└── web/
    ├── index.html
    ├── css/style.css
    └── js/app.js          -- NUI state machine
```

## Funktioner

### Opgaver (§ generisk motor, én tabel, fem typer)

Alle opgavetyper (diesel, gødning, sprøjtemidler, redskabslevering,
dyretransport, maskine-til-landmand) deler samme tabel (`agrihub_tasks`) og
samme livscyklus: `available -> active -> completed/expired/cancelled`.

- **Ingen baggrunds-loop.** Nye opgaver genereres kun når en spiller reelt
  åbner opgavelisten (`Config.Agri.TaskPool.generateOnNuiOpen`), op til et
  samlet loft (`Config.Agri.TaskPool.maxTotal`, default 4) på tværs af ALLE
  typer — ikke 3-4 af hver. Er puljen helt tom, fyldes den op med det
  samme; ellers trickler nye opgaver kun ind med mindst
  `Config.Agri.TaskPool.regenIntervalSec` (default 15 min) imellem.
- **Ingen notify-spam.** Nye opgaver dukker stille op i listen næste gang
  man åbner Opgaver-fanen — der sendes bevidst ingen `lib.notify` til alle
  online spillere, hverken ved login eller ved generering.
- **Server validerer alt.** `reachStop` tjekker den reelle spiller-position
  (`GetEntityCoords`) og evt. påkrævet køretøj (`GetVehiclePedIsIn` +
  model-hash) — klienten kan aldrig selv erklære et stop fuldført eller
  springe et stop over (rækkefølgen håndhæves server-side).
- **Redskabslevering:** kun traileren fjernes ved levering — `tractor2`
  persisterer bevidst, så spilleren kan køre den tilbage.
- **Dyretransport:** `benson2`, tilfældig kilde/destination (inkl. slagteri/
  auktion), to-stops-flow (hent -> aflever).

### Udlejning (§ maskiner fra AgriHub ELLER fra andre spillere)

- **Fra AgriHub:** øjeblikkelig, auto-godkendt/signeret kontrakt — depositum
  og leje trækkes fra `Config.Agri.Rentals` med det samme.
- **Fremleje spiller-til-spiller:** en spiller med en aktiv AgriHub-kontrakt
  kan tilbyde den videre til en anden spiller (fundet via spiller-opslag +
  navn-bekræftelse i NUI'en). Prisen genberegnes **friskt fra config** ved
  hvert tilbud — udlejeren kan aldrig selv sætte sin egen pris.
- **Godkend -> signér -> aktiv:** lejeren skal godkende tilbuddet, FØR nogen
  af parterne kan signere. Kontrakten aktiveres (og pengene/nøglen flytter
  sig) først når **begge** parter har signeret. Se `AGR-XXXXXX`-ID'er,
  `owner_approved`/`renter_approved`/`owner_signed`/`renter_signed`-felterne
  i `agrihub_contracts`.
- **Dobbelt-signering er beskyttet** af en atomisk `UPDATE ... WHERE status =
  "pending"`-guard, samme mønster som opgave-claims — kun ét samtidigt
  signerings-forsøg kan reelt udløse betaling/aktivering (verificeret i
  test-suiten, se nedenfor).
- **Forlængelse** genberegner altid prisen ud fra konfigurationens
  timepris — aldrig fra klient-input.
- **Aflevering** kræver: spilleren reelt sidder i køretøjet, pladen matcher,
  og de er inden for afleveringszonen — kun da refunderes depositum.

### Indkøb

Server bygger linjelisten ud fra `Config.Agri.Shop` — klientens `cart` bruges
**udelukkende** til at slå id/antal op, aldrig pris/label. Inventory-plads
tjekkes før betaling; slår vare-udlevering fejl efter betaling, refunderes
hele beløbet automatisk og hændelsen logges som en sikkerhedshændelse.

Hvert vare-kort i NUI'en viser "Du har: N stk." (hentet server-side fra
`ox_inventory` ved hvert åbn af Indkøb-fanen), så man kan se hvad man
allerede har af fx Kunstgødning før man køber mere ovenpå.

### Adgangsstyring (§ SUPER_ADMIN — kun server-side)

- `Config.Agri.Admin.discordId` sammenlignes **kun** server-side
  (`AH.RequireAdmin` i `server/main.lua`) mod spillerens **live**
  `GetPlayerIdentifiers`-liste — genvalideret ved **hvert eneste** admin-kald,
  aldrig ud fra en cachet `session.role`.
- Der findes **ingen** tilsvarende check i noget client-script eller i
  `web/js/app.js`. NUI'en viser kun admin-fanen hvis `login`-svaret fra
  serveren sagde `role = 'SUPER_ADMIN'` — men selve handlingerne (søg/giv/
  fjern adgang) genvalideres alligevel 100% server-side, så en manipuleret
  klient kan i bedste fald se en tom fane, aldrig udføre en admin-handling.
- SUPER_ADMIN kan give/fjerne adgang via NUI'en **eller** via
  `/agriaccess [id]` og `/agrirevoke [id]`.
- En fjernet spillers session lukkes øjeblikkeligt (`forceLogout`), uanset om
  de sad inde i NUI'en i det øjeblik.

## MM-vehiclekeys-integration

Da export-navnet (`Masitz_giveKey`/`Masitz_removeKey`) skal kunne
konfigureres, kan Lua's `:`-genvejssyntaks ikke bruges direkte (den kræver et
bogstaveligt metode-navn). I stedet replikeres selv-argument-videregivelsen:

```lua
local exp = exports[Config.Agri.Keys.resource]
exp[Config.Agri.Keys.giveExport](exp, src, plate)
```

Alle kald er `pcall`-beskyttede — fejler MM-vehiclekeys, logges det og
resten af AgriHub fortsætter uden at crashe.

## Performance

- **Ingen distance-polling-loop** noget sted. Alle interaktionspunkter
  (computer, landmænd, opgave-stop, afleveringszone) bruger `ox_target`s
  zone-system, som selv er event-drevet.
- **Ingen baggrunds-tråd for opgave-generering eller udløb** — begge sker
  lazy, udløst af en spillerhandling (åbn liste / claim).
- Det eneste periodiske element er `Config.Agri.Performance.cleanupIntervalMs`
  (10 min, `ox_lib`-fri standard-timer) — en billig sikkerhedsnet-sweep for
  edge cases som en spiller der disconnecter midt i en opgave. Dette **kan
  ikke** fjernes helt uden at miste den garanti, uden at det koster reel
  CPU i praksis (ét MySQL-kald hvert 10. minut).
- Resultat: ~0.00 ms i hvile. Alt reelt arbejde sker udelukkende som svar på
  en spillerhandling (ox_target-valg, NUI-callback, server-callback).

## Test

Kritisk server-logik er verificeret med en mock-test-harness (stub'et
FiveM/ESX/MySQL/exports, kører de **rigtige** `server/*.lua`-filer via
`lua5.4`, ingen ægte database/server nødvendig):

- Plade-generering er kollisionssikker.
- `RequireAdmin` godkender **kun** en live Discord-ID-match, og ignorerer en
  manipuleret cachet `session.role`.
- Udlejningspriser er 100% server-autoritative (opkrævet beløb matcher
  præcis config, vinter-spærrede maskiner afvises udenfor vinter).
- Fremleje-kontraktens tilstandsmaskine: ingen penge/nøgle flytter sig før
  begge parter har godkendt OG signeret.
- Den atomiske "activating"-guard forhindrer dobbelt-opkrævning ved et
  samtidigt dobbelt signerings-forsøg.

Alle Lua-filer er desuden syntax-tjekket med `luac5.4 -p`, og
`web/js/app.js` med `node --check`.

## Exports (til andre ressourcer)

```lua
exports['Masitz-AgriHub']:getActiveContract(src)   -- spillerens aktive lejekontrakt, hvis nogen
exports['Masitz-AgriHub']:getPlayerTasks(src)      -- spillerens seneste opgaver
exports['Masitz-AgriHub']:getPlayerRentals(src)    -- spillerens lejemål
exports['Masitz-AgriHub']:getPlayerAgriStats(src)  -- fuldførte opgaver, indtjening, aktive lejemål
```
