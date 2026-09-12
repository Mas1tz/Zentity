# MPvp-kmenu

Weapon Hub til MPvp (Masitz PVP). Ren NUI — ingen `ox_lib` context-menu,
ingen `lib.inputDialog`, ingen `lib.notify`. Tryk **K** for at åbne/lukke,
**ESC** lukker den også.

## Afhængigheder

Kun `ox_inventory` (til billeder + `AddItem`). Ingen `ox_lib`-afhængighed —
intet i den nye version bruger den længere.

## Struktur

```
MPvp-kmenu/
├── fxmanifest.lua
├── config.lua      -- ALT indhold (våben/items/UI-farver/security) — én kilde til sandhed
├── client.lua       -- åbn/luk, NUI-callbacks, ingen loops
├── server.lua        -- whitelist, validering, cooldown, ox_inventory, Discord-log
└── web/
    ├── index.html
    ├── style.css      -- #141517 / #2e2e2e tema
    └── app.js          -- NUI state machine
```

## Sikkerhed (det vigtigste ved reworket)

Den gamle resource gav våben **direkte client-side** (`GiveWeaponToPed`)
uden nogen server involveret, og items via en server-event der blindt
kaldte `exports.ox_inventory:AddItem(src, item, amount)` med **hvad som
helst** klienten sendte — reelt muligt at bede om `item = "money"` med
`amount = 999999999`.

Den nye version er 100% server-autoritativ:

- **Whitelist bygget ét sted:** `server.lua` flader `Config.Weapons` ud i
  to opslagstabeller (`WeaponWhitelist`/`ItemWhitelist`) ved opstart. Et
  våben/item der ikke findes i `config.lua` kan **aldrig** gives, uanset
  hvad NUI'en sender.
- **Våben er altid præcis 1** — klientens `amount` bruges aldrig for våben.
- **Items valideres mod `maxAmount`** (pr. item, ellers `Config.MaxItemAmount`)
  — et ikke-heltal, negativt, nul eller urealistisk stort antal afvises
  fuldstændigt, det klemmes ikke bare ned.
- **Server-side cooldown** (`Config.GiveCooldown`) pr. spiller, uafhængig af
  andre spilleres cooldown.
- **Alt gives via `exports.ox_inventory:AddItem`** — også våben, så
  ox_inventory forbliver source of truth (komponenter/durability/serials,
  fuld inventory-plads-check). `pcall`-beskyttet, så et internt
  ox_inventory-problem aldrig crasher serveren.
- **Discord-logging** (kun server-side URL, `Config.Logging.webhook`) for
  hvert forsøg: gyldig udlevering, ukendt våben/item, ugyldigt antal,
  cooldown ramt, inventory fuldt, interne fejl.

Verificeret med en mock-test-harness der kører de **rigtige**
`config.lua`/`server.lua`-filer under `lua5.4` (ingen ægte
database/server nødvendig) — 41 assertions, bl.a.: ukendte
våben/items blokeres, `amount = 999999999` blokeres, våben tvinges altid
til antal 1, cooldown er pr.-spiller, og et simuleret ox_inventory-crash
fanges uden at vælte serveren.

## Billeder

`Config.InventoryImagePath = 'nui://ox_inventory/web/images/'` — genbruger
ox_inventory's egne billeder direkte (ingen dubletter, ingen base64).
Billednavnet udledes automatisk af våben-/item-navnet
(`weapon_pistol` → `weapon_pistol.png`). Mangler filen, viser NUI'en et
diskret indbygget SVG-fallback-ikon i stedet for et ødelagt billede.

## Performance

- **Ingen loops nogen steder.** Åbn/luk sker udelukkende via
  `RegisterKeyMapping`/`RegisterCommand` + NUI-callbacks. 0.00ms idle,
  også mens menuen er åben (NUI'en tegner alt, Lua sender kun data én
  gang ved åbning og videresender server-svar).
- Al kategori-/vare-data er statisk config og sendes samlet i ét
  `SendNUIMessage`-kald når K trykkes — ingen løbende/polling-beskeder.

## Udvidelse

Ny kategori (Melee, Snipers, Armor, osv.): tilføj én linje i
`Config.Categories` + én ny tabel i `Config.Weapons`. Whitelist, NUI-nav,
dashboard-cards og søgning opdaterer sig selv.

## Dansk UI

Hele NUI'en er på dansk: Oversigt, Pistoler, SMG'er, Rifler, Shotguns,
Attachments, Tilbehør, Søg, Giv våben, Giv item, Antal, Luk, Tilbage,
Ingen items er tilgængelige i denne kategori, Inventory fuldt, Noget gik
galt.
