# mm-adminpakke V2

Fuldt rework af den eksisterende `mm-adminpakke` (mass-give admin panel) til
ESX Legacy + ox_inventory. Nyt UI, ny arkitektur, nyt kategorisystem,
korrekt billed-opløsning, og de to rapporterede kernefejl (500-loft trods
5000 i UI'et, og "billede ikke fundet" for eksisterende billeder) rettet
ved roden - ikke plastret over.

---

## 1. V1-analyse: hvad blev fundet

### Root cause #1 - "5000 fejler, jeg får en fejl om ugyldigt antal"

Frontend i V1 tillod allerede op til 5000 (`MAX_AMOUNT = 5000` i JS,
`max="5000"` på selve input-feltet). Den reelle spærre lå udelukkende
server-side i `server/security.lua`:

```lua
function Security.ValidateAmount(amount)
    ...
    if num > Config.MaxItemsPerGive then return false, 0 end -- = 500
end
```

`Config.MaxItemsPerGive = 500` i `shared/config.lua` afviste derfor alt
over 500, uanset hvad UI'et sendte. Der var desuden en KOLLIDERENDE
ekstra grænse: `Config.MaxBasketAmount = 5000` var et **samlet** loft for
hele kurven, sat til samme tal som selve enkelt-item-grænsen burde være -
så selv efter at rette 500 → 5000, ville det stadig være umuligt at give
5000 af ét item OG noget andet i samme afsendelse.

**V2-fix:** `Config.MaxItemAmount = 5000` er nu den ENESTE grænse for et
enkelt item, håndhævet identisk i UI'et (input `max`, alle +/- knapper og
MAX-knappen læser den fra serverens config-payload, ikke en hardcodet
konstant) og autoritativt i `server/security.lua`. Kurvens samlede loft
(`Config.MaxBasketTotalAmount`) er sat til 100.000 som et rent
DoS-sikkerhedsnet - højt nok til aldrig at kollidere med normal brug af
5000 pr. item.

### Root cause #2 - "billede ikke fundet" for billeder der rent faktisk findes

V1's `shared/items.lua` forsøgte at regex-parse ox_inventory's kildefiler
direkte fra disk (gættede stier som `data/items.lua`,
`data/items/food.lua` osv.) for at finde `client.image`-felter, fordi
`exports.ox_inventory:Items()` ikke altid indeholder det. NUI-siden
forstærkede usikkerheden ved selv at gætte på 3 forskellige base-mapper
(`web/images`, `images`, `web/images/items`) pr. billede - præcis det
mønster du så fejle for `wine.png`.

**Hvad jeg fandt med sikkerhed:** dette er en gætte-baseret arkitektur,
præcis den slags opgaven bad mig undgå. **Hvad jeg IKKE kunne verificere**
uden dine faktiske ox_inventory item-datafiler: hvorfor et konkret,
almindeligt billede som `wine.png` fejler selv mod den korrekte
standard-sti. Jeg spurgte dig om dette undervejs - du bekræftede at gå
videre med den mest korrekte, ikke-gættende arkitektur og at inkludere en
"Manglende billeder"-oversigt, så resterende uoverensstemmelser bliver
synlige for dig i stedet for skjult i F8.

**V2-fix (`server/items.lua`):** billed-opløsning følger nu udelukkende
ox_inventory's egen, dokumenterede konvention - i prioriteret rækkefølge:
1. `Config.ImageOverrides[itemnavn]` (manuel rettelse, dit ansvar for de
   få items hvor filnavnet reelt afviger fra item-navnet)
2. `item.client.image` hvis exporten faktisk indeholder det
3. `<item-navn>.png` (ox_inventory's standard-konvention)

Ingen disk-scanning, ingen gættede alternative mapper. NUI'en forsøger nu
kun ÉT korrekt sammensat billede pr. item; fejler det, vises en neutral
placeholder - console logges kun hvis `Config.Debug = true`. Den nye
**"Manglende billeder"**-fane (klik ikonet i headeren) viser alle items
med status OK/MANGLER, den faktiske billedsti der blev forsøgt, og et
samlet antal - så resterende afvigelser (custom items med et andet
filnavn end deres item-navn) kan rettes præcist via
`Config.ImageOverrides` i stedet for at blive gættet på.

En separat, uafhængig bug blev også fundet og rettet: V1's kurv-visning
brugte billedets rå filnavn direkte som `<img src>` uden at sætte
base-stien foran overhovedet - kurv-thumbnails var derfor altid ødelagte,
uanset resten af billed-systemet. Rettet i V2 (`ImageResolver.urlFor`
bruges konsekvent alle steder, inklusiv kurven).

### Andre reelle fejl fundet og rettet

| # | Fejl | Konsekvens | V2-fix |
|---|---|---|---|
| 1 | `theme.js` indlæses af `index.html` men var ALDRIG listet i `fxmanifest.lua`'s `files{}` | 404 hver gang - hele temavælger/indstillings-panelet har aldrig virket i produktion | Ny arkitektur uden bruger-valgbart tema (fast `#2e2e2e`/`#4c6ef5` per opgavens krav); alle filer der reelt bruges er nu korrekt listet - verificeret automatisk (se §9) |
| 2 | `client/main.lua` kørte en uendelig `while true do Wait(0) end` for altid, kun for at fange ESC | Konstant CPU-forbrug selv når panelet var lukket | ESC-lytteren kører nu KUN mens UI'et faktisk er åbent (starter/stopper med `isOpen`) |
| 3 | `search.js`'s `filter()`-funktion blev aldrig kaldt af noget (død kode), og indeholdt selv en fejl (blandede "missing"- og "recent"-filtrering sammen) | Forvirrende, ubrugt, fejlbehæftet kode i produktionen | Fjernet; al filtrering samlet ét sted i `items.js` |
| 4 | Kategorier var hardcoded prefix-gæt i JS (`drug_`, `pd_`, `nitro_` osv.) uden config-kontrol | Ramte ikke custom item-navne, kunne ikke justeres uden kodeændring | `Config.Categories` i `config.lua` - substring-baseret, prioriteret liste, "Ukategoriseret" fallback der aldrig lader et item forsvinde |
| 5 | `nui/sounds/*.ogg` bundlet og deklareret, men aldrig afspillet (lyd genereres i stedet via WebAudio-toner) | Døde assets | Lyd-systemet var ikke en del af den nuværende opgave og er ikke genimplementeret - se §7 |
| 6 | Pagination-størrelse hardcoded til 40 i JS, aldrig faktisk forbundet til `Config.ItemsPerPage` | Config-værdi der ikke gjorde noget | `itemsPerPage` sendes nu med i åbningsdata og bruges reelt af `Pagination`-modulet |
| 7 | Dobbelt framework-lag (ESX + QBCore auto-detect) på en server der udelukkende kører ESX Legacy | Unødvendig kompleksitet/dead code | Fjernet - V2 er ESX Legacy-only (bekræftet med dig) |

---

## 2. V1 → V2: behold / rework / replace / remove

| Feature | Beslutning | Note |
|---|---|---|
| Kurv-baseret item-give (vælg flere items, sæt antal, giv samlet) | **Behold** | Kernemekanikken var god - kun bagvedliggende validering og billeder er reworket |
| Rate limiting | **Behold** | Fungerede korrekt i V1 |
| Discord/console logging | **Behold** | Fungerede korrekt, kun feltnavne renset op |
| Blacklist af items | **Behold** | Server-autoritativ, som i V1 |
| Favoritter / Seneste | **Behold** | localStorage-baseret som i V1, nu koblet til det nye, korrekte billed-system |
| Item-kategorier | **Rework** | Fra hardcoded JS-prefixes til `Config.Categories` (se §1) |
| Billed-opløsning | **Rework** | Fra disk-scanning/gætte-kæde til ox_inventory's egen konvention + Missing Images manager |
| Personvalg (spillerliste) | **Rework** | Fra ren liste til søg + liste + tydelig "valgt spiller"-bjælke med Steam-avatar (se §5 i din besked) |
| Quantity-system | **Rework** | Enkelt, korrekt håndhævet loft (se §1) |
| UI/design | **Replace** | Helt nyt layout, samme cirka-footprint (1360×820 mod V1's 1380×860) |
| ESX/QBCore dual-framework | **Remove** | ESX Legacy-only efter aftale |
| Tema-vælger (theme.js) | **Remove** | Var reelt aldrig funktionel (se fejl #1); erstattet af fast `#2e2e2e`/`#4c6ef5`-tema jf. opgavens krav |
| Lyd-effekter | **Remove** (for nu) | Ikke en del af denne opgave - nem at tilføje igen hvis ønsket |
| Steam-profil/avatar | **Ny feature** | Tilføjet efter aftale - server-side API-kald, aldrig eksponeret til NUI |
| Tablet-prop + animation | **Ny feature** | Tilføjet efter aftale - ét centralt system, se §6 |
| Missing Images manager | **Ny feature** | Tilføjet efter aftale - direkte relevant for billede-bugsen |

---

## 3. Resource-struktur

```
mm-adminpakke/
├── fxmanifest.lua
├── config.lua
├── client/
│   ├── main.lua        -- NUI-bro, åbn/luk, ESC (kun mens åben), keybind
│   └── tablet.lua       -- ét centralt tablet-prop + animation system
├── server/
│   ├── security.lua      -- permissions, rate-limit, al validering (autoritativ)
│   ├── players.lua       -- spillerliste + fuld profil (inkl. Steam)
│   ├── items.lua         -- item-liste + billede/kategori-opløsning
│   ├── steam.lua         -- Steam Web API, cachet, API-nøgle aldrig til klient
│   ├── logs.lua          -- console + Discord logging
│   ├── actions.lua       -- selve item-udleveringen via ox_inventory
│   └── main.lua          -- orkestrerer events, kalder ind i modulerne ovenfor
└── nui/
    ├── index.html
    ├── css/
    │   ├── main.css        -- design tokens, layout, base
    │   └── components.css  -- cards, modaler, knapper, tabs osv.
    └── js/
        ├── components.js   -- delt state, billed-opløsning, kurv, modal, pagination
        ├── players.js      -- spillerliste, valg, profil-modal
        ├── items.js        -- grid, kategorier, søgning, favoritter/seneste, missing-manager
        └── app.js           -- NUI-besked-orkestrering, tema-anvendelse
```

---

## 4. Installation

1. Kopiér `mm-adminpakke/`-mappen til din `resources/`-mappe.
2. Tilføj `ensure mm-adminpakke` til `server.cfg`, **efter** `es_extended`,
   `ox_lib` og `ox_inventory`.
3. Åbn `config.lua` og tilret mindst:
   - `Config.AllowedGroups` til jeres faktiske admin-grupper
   - `Config.DiscordWebhook` hvis I vil bruge Discord-logging
   - `Config.Steam.ApiKey` (allerede udfyldt med den nøgle du tidligere
     har opgivet - flyt den til en anden værdi hvis den skal roteres)
4. Genstart serveren, eller `refresh` + `ensure mm-adminpakke`.

---

## 5. Config-oversigt (`config.lua`)

- `Config.Debug` - se §9.
- `Config.OpenCommand` / `Config.OpenKey` - kommando/keybind til at åbne panelet.
- `Config.UseAcePermission` / `Config.AcePermission` / `Config.AllowedGroups` - rettigheder.
- `Config.RateLimit` - anti-spam pr. spiller.
- `Config.MaxItemAmount` - **den** grænse for antal pr. item (standard 5000).
- `Config.MaxBasketItems` / `Config.MaxBasketTotalAmount` - kurv-grænser (se §1).
- `Config.BlacklistedItems` - items der aldrig kan gives.
- `Config.Logging` / `Config.DiscordWebhook` / `Config.DiscordEmbed` - logging.
- `Config.ItemsPerPage` - faktisk forbundet til NUI'ens pagination.
- `Config.Theme` - `Background`/`Accent`, sendes til NUI og sættes som CSS custom properties ved åbning.
- `Config.ImageBasePath` / `Config.ImageOverrides` - billed-opløsning (se §1).
- `Config.Categories` / `Config.UncategorizedLabel` / `Config.WeaponsLabel` - kategorisystem (se §1).
- `Config.MissingImageManager.Enabled` - slår "Manglende billeder"-knappen til/fra.
- `Config.Steam` - `Enabled`, `ApiKey`, `CacheSeconds`.
- `Config.Tablet` - prop/animation-opsætning.

---

## 6. Tablet prop + animation-system

Ét centralt system i `client/tablet.lua`: `Tablet.Open()` / `Tablet.Close()`.

- `Tablet.Open()` er en no-op hvis der allerede er en aktiv prop - der kan
  aldrig eksistere mere end én ad gangen.
- `Tablet.Close()` er sikker at kalde flere gange i træk (fx både fra et
  normalt NUI-luk og fra en death-handler).
- Automatisk lukning (`ForceCloseEverything`) er koblet på: `esx:onPlayerDeath`,
  `baseevents:onPlayerDied`, `esx:onPlayerLogout`, at sætte sig ind i et
  køretøj (`lib.onCache('vehicle', ...)`), og `onResourceStop`.
- Når tablet-systemet lukker af en af disse eksterne årsager, sendes en
  `forceClose`-besked til NUI'en, som selv kalder den almindelige
  `close`-callback - så Lua-siden og NUI-siden aldrig kommer ud af sync,
  uden at det kræver nogen ekstra polling-tråd.

---

## 7. Steam-integration

`server/steam.lua` slår **kun** Steam-profilen op for én spiller ad
gangen, når en admin faktisk vælger/åbner den spillers kort i NUI'en -
ikke for hele spillerlisten på én gang. Resultatet cachet
(`Config.Steam.CacheSeconds`, standard 1 time) pr. SteamID64. API-nøglen
bruges udelukkende i denne fil, server-side - den sendes aldrig til
klienten/NUI'en, kun det færdige navn og avatar-URL.

---

## 8. Sikkerhed

- **Permissions**: valideres server-side (`Security.IsAdmin`) på ALLE tre
  net-events og callbacken - klienten kan ikke selv bestemme om den er admin.
- **Item + antal**: `Security.ValidateBasket` genvalideres fuldstændigt
  server-side for hver eneste afsendelse, uanset hvad UI'et allerede
  forhindrede - client-side validering er kun bekvemmelighed.
- **Target**: valideres via `GetPlayerName(id)` - en klient kan ikke ramme
  et ikke-eksisterende server-id.
- **Blacklist**: tjekkes server-side inde i selve item-valideringen, ikke
  kun visuelt i UI'et.
- **Rate limiting**: pr. spiller, forhindrer spam af åbne/opdater/giv-events.
- **Steam API-nøgle**: udelukkende server-side, aldrig i NUI/JS.

---

## 9. Debug mode

`Config.Debug = false` som standard. Sæt til `true` for konsol-output
(prefixet `[mm-adminpakke]`) af: item-cache-opbygning, permission-afvisninger,
Steam-opslagsfejl, tablet-prop-events, og (i NUI-konsollen, F8) hvilke
konkrete billed-URL'er der blev forsøgt og fejlede. Er `false` som
standard, er NUI-konsollen fri for billede-relaterede advarsler -
"Manglende billeder"-fanen viser stadig status uden at kræve debug-mode.

---

## 10. Verifikation udført

- `luac -p` kørt på samtlige Lua-filer (server + client + config) - alle
  består.
- `node --check` kørt på samtlige NUI JS-filer - alle består.
- Automatisk krydstjek: hvert `document.getElementById(...)`-kald i JS'en
  matcher et faktisk element i `index.html` (nul mismatches - den præcise
  fejlklasse der ramte V1's `theme.js`).
- Automatisk krydstjek: hver fil `index.html` linker til (`<script>`/`<link>`)
  findes både på disk OG i `fxmanifest.lua`'s `files{}`-blok (V1's
  `theme.js` 404-bug kan ikke gentage sig).

## Kendte begrænsninger

- Billed-opløsningen er nu korrekt efter ox_inventory's egen konvention,
  men kan stadig vise "MANGLER" for enkelte custom items hvis deres
  filnavn afviger fra item-navnet OG de ikke har et eksplicit
  `client.image` sat i ox_inventory - brug "Manglende billeder"-fanen til
  at finde dem, og ret via `Config.ImageOverrides`.
- Lyd-effekter fra V1 er ikke genimplementeret (var ikke en del af denne
  opgave) - kan tilføjes separat hvis ønsket.
- Steam-integrationen kræver at spilleren har et `steam:`-identifier og at
  serveren har udgående internetadgang til Steam's API.
