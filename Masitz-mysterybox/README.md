# Masitz-mysterybox

Config-drevet mystery box-system til **ox_inventory** + **ox_lib**. Reworket
fra den tidligere `MM-mysterybox`, med bevaret funktionalitet (konvertering,
lovlig/ulovlig box, rewards, bonus rewards, vehicle tickets), men nu
fuldstændig styret fra `config.lua` - ingen hardcoded box-typer i client
eller server.

---

## Resource-struktur

```
Masitz-mysterybox/
├── fxmanifest.lua
├── config.lua
├── client/
│   └── client.lua
├── server/
│   └── server.lua
└── README.md
```

## 1. Installation

1. Kopiér `Masitz-mysterybox/`-mappen til din `resources/`-mappe.
2. **Vigtigt:** Ressourcen hed tidligere `MM-mysterybox`. Alle steder i jeres
   `ox_inventory` items-config (`data/items.lua` el. lign.) der peger på
   `MM-mysterybox.<export>` (fx `MM-mysterybox.useLegalMystery`) skal
   opdateres til de nye exports (se afsnit 5 herunder) under det nye
   resource-navn `Masitz-mysterybox`.
3. Tilføj `ensure Masitz-mysterybox` til `server.cfg` **efter** `ox_lib` og
   `ox_inventory`.
4. Tilret `config.lua` efter behov (se afsnit 3-6).
5. Genstart serveren, eller kør `refresh` + `ensure Masitz-mysterybox`.

## 2. Dependencies

- **ox_lib** (påkrævet) - `lib.inputDialog` til konverterings-menuen og
  `lib.notify`/`ox_lib:notify` til alle notifikationer.
- **ox_inventory** (påkrævet) - `AddItem`/`RemoveItem`/`GetSlot`/
  `GetItemCount` bruges til al item-håndtering.

## 3. Sådan fungerer config'en

Alt styres fra `config.lua` via `Config.MysteryBox`:

- `M.Debug` - se afsnit 8. Falsk som standard, ingen konsol-spam i produktion.
- `M.MoneyItem` - standard item-navn for rewards af typen `'money'`.
- `M.Notifications.position` - position for alle `ox_lib` notifikationer.
- `M.Conversion` - kilde-item, om konvertering er aktiveret, og
  `targets`-tabellen der styrer den dynamiske konverterings-menu.
- `M.VehicleTicket` - standard item/præfiks/bilpulje for enhver reward af
  typen `'vehicle_ticket'` (kan overskrives pr. reward).
- `M.Boxes` - selve mystery boxene. **Dette er den eneste tabel du skal røre
  for at tilføje, fjerne eller ændre en box, dens rewards, dens bonus
  rewards, dens amounts eller dens chances.**

Hverken `client/client.lua` eller `server/server.lua` indeholder noget
hardcodet box-navn ("legal"/"illegal" osv.) - alt afgøres af hvad der findes
i `Config.MysteryBox.Boxes` og `Config.MysteryBox.Conversion.targets` ved
resource-start.

## 4. Chance-system (læs dette før du ændrer tal)

- **`rewards`** (hoved-belønningen): **weighted**. Der vælges ALTID præcis 1
  reward fra listen. `chance` er en relativ **vægt** i forhold til de andre
  rewards i samme liste - de skal ikke summere til 100. Eksempel: chance =
  60, 50, 25 giver hhv. ~44 %, ~37 %, ~19 % af selve trækningen. Vil du have
  "rene" procenter, så sørg selv for at chance-værdierne i listen summerer
  til 100.
- **`bonusRewards`** (ekstra rewards oveni hoved-rewarden): **independent
  chance**. Hver reward rangeres helt for sig selv som en selvstændig
  procent-chance (0-100, decimaler tilladt, fx `chance = 2.5`). Der kan
  udløses 0, 1 eller flere bonusRewards samtidig - de påvirker ikke
  hinanden.

Det gamle system i `MM-mysterybox` rullede hver reward uafhængigt og valgte
derefter tilfældigt blandt de reward, der "vandt" - og faldt tilbage til et
**helt tilfældigt** valg (ignorerede chance fuldstændigt) hvis ingen vandt.
Det gav en skæv/uforudsigelig fordeling, især for lav-chance items. Det nye
weighted-system garanterer altid en reward, og fordelingen matcher direkte
de relative chance-værdier i config.

## 5. Sådan tilføjer/fjerner du en mystery box

Tilføj en ny nøgle i `Config.MysteryBox.Boxes`, fx:

```lua
premium = {
    item = 'premium_mysterybox',
    label = 'Premium Mystery Box',
    description = 'En mystery box med premium belønninger.',
    rewards = {
        { type = 'item', name = 'goldbar', amount = { min = 1, max = 3 }, chance = 40 },
        { type = 'money', amount = 100000, chance = 30 },
    },
    bonusRewards = {
        { type = 'vehicle_ticket', chance = 1 },
    },
},
```

Client genererer automatisk en export `use_premium` for denne box (mønster:
`use_<boxnøgle>`). Peg jeres `ox_inventory` item på:

```lua
client = {
    export = 'Masitz-mysterybox.use_premium',
},
```

Vil boxen også kunne konverteres til fra `mysterybox`, tilføj den i
`Config.MysteryBox.Conversion.targets`:

```lua
targets = {
    legal = 'lovlig_mysterybox',
    illegal = 'ulovlig_mysterybox',
    premium = 'premium_mysterybox',
},
```

Den dukker automatisk op i `lib.inputDialog`-menuen - intet andet skal
ændres. Fjern en box ved blot at slette dens nøgle fra `M.Boxes` (og evt.
`M.Conversion.targets`).

Konverterings-exporten hedder `convertMysteryBox`:

```lua
client = {
    export = 'Masitz-mysterybox.convertMysteryBox',
},
```

## 6. Reward-typer

Understøttede `type`-værdier i både `rewards` og `bonusRewards`:

| type             | felter                                                        |
|------------------|----------------------------------------------------------------|
| `item`           | `name` (påkrævet), `amount` (tal eller `{min, max}`), valgfri `metadata` (tabel eller funktion `function(src)`) |
| `money`          | `name` (valgfri, default `M.MoneyItem`), `amount` (tal eller `{min, max}`) |
| `vehicle_ticket` | valgfri `item`/`prefix`/`vehicles` (falder ellers tilbage til `M.VehicleTicket`) |

Nye reward-typer tilføjes i `server/server.lua` ved blot at tilføje én ny
handler i `RewardHandlers`-tabellen - resten af flowet (validation, weighted
selection, bonus rolls, refund-on-failure) håndterer automatisk enhver ny
type.

## 7. Server-side sikkerhed

- Box-type, reward og amount slås **altid** op i `Config.MysteryBox`
  server-side - clienten sender kun en box-nøgle og en slot, aldrig en
  reward.
- Slotens indhold verificeres (`GetSlot`) mod boxens item, før noget fjernes.
- Amount ved konvertering valideres server-side: heltal, minimum 1, og aldrig
  mere end spilleren faktisk ejer (`GetItemCount`).
- Fejler item-removal, gives INGEN reward.
- Fejler reward-udbetalingen (`AddItem`) EFTER boxen er fjernet, refunderes
  boxen til spilleren automatisk, så de aldrig kan miste en box uden at få
  noget for den.
- Én mystery box-handling ad gangen pr. spiller (`processing`-lock) forhindrer
  spam/replay af samme event og race conditions ved samtidige åbninger.

## 8. Debug mode

Sæt `Config.MysteryBox.Debug = true` for konsol-output prefixet
`[Masitz-MysteryBox]`:

- `Loaded X mystery boxes.` / `Loaded X rewards.` ved resource-start.
- Hvilken reward (og evt. bonus reward) en spiller fik, og fra hvilken box.
- Config-valideringsfejl (disse printes dog altid, uanset Debug, så en
  fejlkonfigureret box aldrig fejler stille/tilfældigt).

Er slået fra som standard for at holde konsollen ren i produktion.

## 9. Migration fra `MM-mysterybox`

| Gammelt                                   | Nyt                                                   |
|--------------------------------------------|--------------------------------------------------------|
| `Config.LegalRewards`                     | `Config.MysteryBox.Boxes.legal.rewards`               |
| `Config.IllegalRewards`                   | `Config.MysteryBox.Boxes.illegal.rewards`             |
| `Config.LegalVehicleChance` / `Pool`      | `Config.MysteryBox.Boxes.legal.bonusRewards` (type `vehicle_ticket`) |
| `Config.IllegalGasMaskChance`             | `Config.MysteryBox.Boxes.illegal.bonusRewards` (type `item`) |
| `Config.CarTicketItem` / `TicketPrefix`   | `Config.MysteryBox.VehicleTicket.item` / `.prefix`    |
| `MM:convertMysteryBox`                    | `Masitz-MysteryBox:convertBox`                        |
| `MM:openLegal` / `MM:openIllegal`         | `Masitz-MysteryBox:openBox` (generisk, boxKey som param) |
| export `mysterybox`                       | export `convertMysteryBox`                            |
| export `useLegalMystery` / `useIllegalMystery` | export `use_legal` / `use_illegal`               |

Alle tal (amounts, chances, item-navne) fra den gamle config er bevaret
1:1 i den nye `Config.MysteryBox.Boxes` - kun strukturen er ændret.
