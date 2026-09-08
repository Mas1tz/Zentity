# Faktura Tablet V2

## Installation
1. Læg mappen i `resources/` (behold navnet `mm-faktura`, da NUI'en kalder tilbage til `https://mm-faktura/...`).
2. Kør `install.sql` i din database.
3. Læg dit eget logo som `html/image/Mmasitz.png` (findes den ikke, falder tabletten automatisk tilbage til teksten "FT").
4. `ensure mm-faktura` i `server.cfg` – **efter** `oxmysql` og `ox_lib`.
5. Sæt en ACE-gruppe op til kategori-administratorer, fx i `server.cfg`:
   ```
   add_ace group.faktura_admin faktura.admin allow
   add_principal identifier.discord:123456789 group.faktura_admin
   ```
   Bruger du en discord-rolle-bot der allerede tildeler ACE-grupper (de fleste gør), skal du blot pege den på gruppenavnet du sætter i `Config.CategoryManagement.aceGroup`.

## Hvad er nyt i V2
- Regninger ("Faktura" hedder nu **Regning** i UI'en) gemmes i databasen og er koblet til spillerens `license`-identifier, så de ikke forsvinder ved genstart eller når nogen får nyt session-ID.
- Betalte regninger forsvinder ikke længere automatisk – de får en "Betalt"-badge og en **Slet regning**-knap. Alt (betalt eller ej) autoslettes efter `Config.InvoiceRetentionDays` dage (default 7).
- Ny **"Nærved dig"**-liste ved siden af søgefeltet, opdateres automatisk hvert 3. sekund mens tabletten er åben.
- Klik på en spiller viser antal ubetalte regninger + samlet skyldigt beløb.
- Kategorier er nu grupperet (fx politiets bøder er delt op i Færdselsloven, Våbenloven osv.) og kan søges igennem.
- Ny **Administrer**-fane hvor spillere med rettigheder kan tilføje/redigere/slette varer og oprette helt nye grupper, uden at røre `config.lua`.

## Kategori-editor: hvordan de to lag hænger sammen
- `config.lua` er dit **faste grundkatalog** – det kan kun ændres af dig i koden.
- Alt der oprettes via **Administrer**-fanen i tabletten gemmes i en separat databasetabel (`mm_faktura_custom_categories`) og lægges oveni grundkataloget, når spillerne ser listen.
- Det betyder: spillere med rettigheder kan tilføje nye grupper/varer og redigere/slette **deres egne oprettelser**, men kan ikke redigere eller slette noget fra `config.lua` gennem UI'en. Det er bevidst, så en fastsat prisliste ikke kan ændres ved et uheld af en spiller med adgang.

## Hvem må administrere kategorier?
Styres i `config.lua`:
```lua
Config.CategoryManagement = {
    aceGroup = "faktura.admin", -- fuld adgang til ALLE jobs
    jobGradeOverride = {
        police = 3, -- politi-spillere med grade >= 3 må redigere POLITIETS egne kategorier
        ...
    },
}
```
En spiller med ACE-gruppen kan redigere alle jobs. En spiller uden ACE men med højt nok rang i sit eget job kan kun redigere det jobs kategorier.

## Export-API (til politi-tablet, unicorn-tablet, læge-tablet osv.)

### Send en regning uden at åbne UI'en
```lua
local ok, amountOrError = exports['mm-faktura']:SendInvoice({
    targetId = targetServerId,      -- spilleren der skal betale (skal være online)
    job = "police",                 -- bruges til kategori-opslag + vises i historik
    fromId = source,                -- valgfri, den der udsteder regningen
    items = {                       -- pris/label slås op server-side, kan ikke snydes af klienten
        { id = "roedt_lys", antal = 1 },
        { id = "hastighed_2", antal = 1 },
    },
    discountPct = 0,                -- valgfri
})
-- ok == true/false, amountOrError == totalbeløb eller en fejlbesked
```

Du kan også sende et simpelt flad beløb uden at bruge det grupperede katalog:
```lua
exports['mm-faktura']:SendInvoice({
    targetId = targetServerId,
    job = "ambulance",
    fromId = source,
    amount = 2500,
    label = "Akut udrykning",
})
```

### Registrér dine egne kategorier ved resource-start
```lua
-- Én vare ad gangen (opretter gruppen "Ekstra Bøder" hvis den ikke findes for "police")
exports['mm-faktura']:RegisterCategory("police", "Ekstra Bøder", {
    id = "unicorn_ballade", label = "Ballade på Vanilla Unicorn", price = 3000
})

-- Eller en hel gruppe på én gang
exports['mm-faktura']:RegisterCategoryGroup("unicorn", "VIP Menu", {
    { id = "vip_bottle", label = "VIP Flaske Service", price = 5000 },
})
```
**Bemærk:** disse registreres i hukommelsen og skal kaldes igen hver gang dit resource starter (det er med vilje – så du altid har fuld kontrol over dem i din egen kode, ligesom `config.lua`).

### Åbn selve Faktura-UI'en for en spiller
```lua
exports['mm-faktura']:OpenTablet(targetServerId, { canSend = false })
```

### Andre nyttige exports
```lua
local groups = exports['mm-faktura']:GetCategories("police") -- hele det samlede katalog for et job

exports['mm-faktura']:GetUnpaidSummary(playerServerIdEllerIdentifier, function(count, total)
    print(count, total) -- fx til en dispatch-widget
end)
```
