# Masitz-Restraint

Server-autoritativt restraint / carry / drag-system til ESX Legacy.
Fuldt rework af det oprindelige `mm_system`-baserede ziptie/carry/drag-script.

---

## 1. Analyse af det oprindelige script

### Features i det gamle script (bevaret eller forbedret her)
| Feature | Gammel implementation | Ny implementation |
|---|---|---|
| Ziptie/restrain af spiller | `mm_system:restrainMe` (client-triggeret) | Server-valideret `Do*`-kerne, config-styrede typer |
| Fjern restraint | `mm_system:unrestrainMe` | Server-valideret, permission-styret via config |
| Carry (bær) | Client-side attach, ingen server-validering | Server-valideret afstand/state, bidirektionel cleanup |
| Drag (træk) | Client-side attach + `isDragged`-toggle | Server-valideret, kræver restraint (config) |
| Animation ved restrain | Busy-wait `while not HasAnimDictLoaded do Wait(0) end` | `lib.requestAnimDict(dict, timeout)` |
| Chat/besked-integration | Hardcoded `TriggerServerEvent('3dme:executeMe', msg)` | Valgfri, config-styret |

### Bugs fundet i det oprindelige script
| # | Bug | Konsekvens |
|---|---|---|
| 1 | `unrestrainMe` har ingen server-validering af afstand, item eller permission | Enhver spiller kan sende eventet med et vilkårligt target-id og frigøre sig selv eller andre uden nogen tjek |
| 2 | Ingen server-side afstandstjek ved restrain/carry/drag | Klienten kan restrain/bære/trække spillere langt uden for reel rækkevidde |
| 3 | `ensureAnim` bruger en uendelig `while not HasAnimDictLoaded(dict) do Wait(0) end`-loop uden timeout | Hænger permanent hvis dict'en aldrig loader (fx forkert navn, streaming-fejl) |
| 4 | `isDragged = not isDragged`-toggle uden at følge med i hvem der trækker | Kan komme ud af sync hvis to handlinger overlapper, og giver ingen sikker "stop"-vej |
| 5 | Ingen oprydning ved disconnect for den ANDEN part i en carry/drag-relation | Bliver man draget af en spiller der disconnecter, sidder man fast i drag-state permanent |
| 6 | Ingen beskyttelse mod at spamme restrain/unrestrain | Kan bruges til at spamme animationer/events og skabe unødig serverbelastning |
| 7 | Ingen håndtering af død mens restrained/carried/dragged | Kan efterlade ped'en i en fastlåst animation efter død |
| 8 | Ingen resource-restart-håndtering | Klienter beholder en forældet lokal state efter en `restart` af scriptet |

---

## 2. Ny arkitektur

**Princip:** Serveren er den eneste sikkerhedsautoritet. Al state ligger i én central tabel (`states[source]`) på serveren. Klienten har kun en *spejling* af sin egen del af denne state (`localState`), som udelukkende opdateres via ét `syncState`-event fra serveren.

```
              ┌─────────────────────────────┐
              │   server/sv_restraint.lua    │
              │                              │
   events -->  │  Do* kernefunktioner         │ <-- exports (autoritative)
  callbacks --> │  (validerer ALT server-side) │ --> TriggerClientEvent(syncState)
              │  states[source] (autoritet)  │ --> offentlige notify-events
              └─────────────────────────────┘
                              |
                              v  (kun via syncState)
              ┌─────────────────────────────┐
              │   client/cl_restraint.lua    │
              │  localState (spejl, read-UX) │
              │  animation / control-lock     │
              │  attach til carrier/dragger    │
              └─────────────────────────────┘
```

Alle sikkerhedskritiske handlinger (restrain, unrestrain, carry, drag) går gennem en fælles `Do*`-funktion på serveren, uanset om de udløses af et net-event fra en klient ELLER af et export-kald fra en anden ressource. Det betyder der kun er ét sted valideringslogikken skal vedligeholdes.

**Hvorfor ikke State Bags?** FiveM's `Player(source).state` kan sættes af den ejende klient selv (`LocalPlayer.state:set(...)` med `replicated = true` er stadig klient-initieret og kan ikke stoles på som sikkerhedsgrundlag — en modificeret klient kan sætte sin egen state bag til hvad som helst). Derfor bruges state bags IKKE til `restrained`/sikkerhedsflag. Den eneste state bag i dette system er `invBusy`, som udelukkende er en UX-convenience (låser inventar-UI visuelt) og aldrig bruges til en sikkerhedsbeslutning noget sted i koden.

---

## 3. Filer

```
Masitz-Restraint/
├── fxmanifest.lua
├── config.lua
├── server/
│   └── sv_restraint.lua
├── client/
│   └── cl_restraint.lua
└── README.md
```

---

## 4. Installation

1. Kopiér `Masitz-Restraint/`-mappen til din `resources/`-mappe.
2. Tilføj `ensure Masitz-Restraint` til `server.cfg` **efter** `es_extended`, `ox_lib` og `ox_inventory`.
3. Sørg for at OneSync er aktiveret (krævet for server-side læsning af ped-koordinater via `GetPlayerPed`/`GetEntityCoords`).
4. Tilret `config.lua` til jeres items/jobs (se afsnit 6).
5. Fjern/deaktiver det gamle `mm_system`-restraint-script for at undgå event-navnekollision (dette script bruger et helt nyt namespace, `masitz_restraint:*`, så det kan sagtens køre side om side, men det gamle scripts usikre `unrestrainMe` bør fjernes).

---

## 5. Dødt / levende / genoplivning / (re)connect / resource-restart

- **Død:** Klienten rapporterer best-effort via almindelige ESX/baseevents-hooks (`esx:onPlayerDeath`, `baseevents:onPlayerDied`, `baseevents:onPlayerKilled`) samt en fallback-poll der KUN kører mens spilleren er restrained (ingen evig baggrundsloop). `isDead` bruges udelukkende til at stoppe tvungne animationer/carry/drag ved død — det er aldrig en del af en sikkerhedsbeslutning.
- **Genoplivning:** Tilsvarende best-effort via `esx:onPlayerSpawn`, `playerSpawned`, `baseevents:onPlayerRevived`.
- **Custom/eget dødssystem:** Kald i stedet det autoritative server-export `exports['Masitz-Restraint']:SetPlayerDeathState(target, isDead)` direkte fra jeres eget medic-/dødsscript. Dette er den anbefalede integration, da den ikke er afhængig af at gætte de rigtige event-navne.
- **Disconnect:** `playerDropped` rydder op i BEGGE retninger af enhver aktiv relation (er man selv bærer/trækker, ELLER bliver man båret/trukket af nogen, får modparten besked og state nulstilles korrekt for dem).
- **Reconnect:** Får en frisk, tom state (ingen persistering — se afsnit 12), og en `syncState` sendes ved næste handling/resource-start.
- **Resource-restart:** 1 sekund efter start force-resync'er serveren ALLE tilsluttede spillere til en ren state, så ingen klient sidder fast med en forældet lokal kopi fra før genstarten.

---

## 6. Config

Se `config.lua` — alle indstillinger er dokumenteret med danske kommentarer direkte i filen. Kort opsummeret:

- `Config.Restraint` — globale regler: afstande, permissions, cooldown, død-adfærd, chat-integration.
- `Config.Restraints` — tabel af restraint-typer (fx `ziptie`), fuldt udvidelig uden kodeændringer.
- `Config.CarryAnim` / `Config.DragAttachBone` / `Config.DragOffset` — animation/attach-opsætning for carry/drag.
- `Config.Text` — alle danske UI-tekster ét sted.

---

## 7. Events

**Klient → server (sikkerhedsvaliderede):**
- `masitz_restraint:server:requestRestrain(target, restraintType)`
- `masitz_restraint:server:requestUnrestrain(target)`
- `masitz_restraint:server:requestCarry(target)`
- `masitz_restraint:server:stopCarry()`
- `masitz_restraint:server:requestDrag(target)`
- `masitz_restraint:server:stopDrag()`
- `masitz_restraint:server:reportDeath(isDead)` — kun til `isDead`-tracking, ikke sikkerhed

**Server → klient (kun til afsendte spillere, aldrig tillid fra klient):**
- `masitz_restraint:client:syncState(publicState)` — eneste sted `localState` må ændres
- `masitz_restraint:client:notify(text, type)`
- `masitz_restraint:client:carryTarget/carryStarted`
- `masitz_restraint:client:dragTarget/dragStarted`
- `masitz_restraint:client:stopCarryDrag`
- `masitz_restraint:client:openRestraintMenu(restraintType)`

**Offentlige notifikations-events (IKKE en sikkerhedsautoritet — kun til UX-reaktion fra andre ressourcer):**
- `masitz-restraint:server:stateChanged(target, restrained, restraintType, byPlayer)`
- `masitz-restraint:client:stateChanged(target, restrained, restraintType)` (broadcast, `-1`)
- `masitz-restraint:server:deathStateChanged(target, isDead)`
- `masitz-restraint:client:deathStateChanged(target, isDead)` (broadcast, `-1`)

---

## 8. API-dokumentation (exports)

### Server-exports
```lua
exports['Masitz-Restraint']:IsRestrained(target)              -- bool
exports['Masitz-Restraint']:GetRestraintType(target)          -- string|nil
exports['Masitz-Restraint']:GetRestraintState(target)         -- table (public state snapshot)
exports['Masitz-Restraint']:IsPlayerDead(target)               -- bool
exports['Masitz-Restraint']:RestrainPlayer(target, restraintType) -- bool ok, string? reason
exports['Masitz-Restraint']:UnrestrainPlayer(target)            -- bool ok, string? reason
exports['Masitz-Restraint']:SetPlayerDeathState(target, isDead) -- bool
```

`RestrainPlayer`/`UnrestrainPlayer` er autoritative (ingen afstand/item/cooldown-tjek, da det kaldende system SELV er autoriteten — fx et admin-script eller jeres eget arrestations-system).

### Klient-exports
```lua
exports['Masitz-Restraint']:IsRestrained()                    -- bool
exports['Masitz-Restraint']:GetRestraintType()                 -- string|nil
exports['Masitz-Restraint']:GetRestraintState()                 -- table
exports['Masitz-Restraint']:GetKnownRestraintState(serverId)     -- table|nil (UX-cache af andre spillere)
exports['Masitz-Restraint']:RequestRestrain(targetServerId, restraintType)
exports['Masitz-Restraint']:RequestUnrestrain(targetServerId)
exports['Masitz-Restraint']:RequestCarry(targetServerId)
exports['Masitz-Restraint']:RequestDrag(targetServerId)

-- Legacy-kompatible (bevarer oprindelige navne/signaturer):
exports['Masitz-Restraint']:ToggleZiptie()
exports['Masitz-Restraint']:ToggleCarry()
exports['Masitz-Restraint']:ToggleEscort()
```

---

## 9. Radial-menu eksempel (ox_lib)

```lua
lib.registerRadial({
    {
        id = 'masitz_restraint_ziptie',
        label = 'Strips',
        icon = 'handcuffs',
        onSelect = function()
            exports['Masitz-Restraint']:ToggleZiptie()
        end,
    },
    {
        id = 'masitz_restraint_carry',
        label = 'Bær/Slip',
        icon = 'person-carry-box',
        onSelect = function()
            exports['Masitz-Restraint']:ToggleCarry()
        end,
    },
    {
        id = 'masitz_restraint_drag',
        label = 'Eskortér',
        icon = 'person-walking',
        onSelect = function()
            exports['Masitz-Restraint']:ToggleEscort()
        end,
    },
})

-- Eksempel: skjul "Eskortér" i radial-menuen hvis den nærmeste spiller
-- ikke er restrained (kun UX - selve handlingen valideres stadig server-side):
-- lib.hideRadialItem('masitz_restraint_drag')
```

---

## 10. Testplan

1. Restrain en spiller inden for afstand med item på sig → succes, item forbruges.
2. Restrain uden item på sig → fejler med korrekt besked, ingen state-ændring.
3. Restrain en spiller der allerede er restrained → fejler (`already_restrained`).
4. Forsøg `TriggerServerEvent('masitz_restraint:server:requestUnrestrain', ownId)` fra en klient uden at være i nærheden af nogen → fejler (`self_target` hvis `AllowSelfRemove=false`, ellers `too_far`).
5. Unrestrain med `UnrestrainPermission='restrainer_only'` fra en ANDEN spiller end den der restrained → fejler (`no_permission`).
6. Carry en restrained spiller, tryk E → carry stopper korrekt for begge parter.
7. Drag en restrained spiller, unrestrain undervejs → drag stopper automatisk.
8. To spillere forsøger at restraine samme target samtidig → kun én lykkes, den anden får `already_restrained`/`busy`.
9. Restrain en spiller der i forvejen bærer en tredje spiller → den tredjes carry stoppes automatisk, ingen fastlåst animation.
10. Disconnect mens man bliver draget af en anden spiller → draggeren får korrekt `stopCarryDrag`, ingen fastlåst state.
11. Disconnect som draggeren selv → den trukne spiller får korrekt `stopCarryDrag`.
12. Dræb en restrained spiller (`StopCarryDragOnDeath=true`) → carry/drag stopper, restraint forbliver på (medmindre `ClearRestraintOnDeath=true`).
13. Genoplivning efter død mens restrained → `isDead` ryddes korrekt, animation/control-lock genoptages.
14. Genstart resourcen mens spillere er restrained → alle klienter modtager frisk `syncState` inden for 1 sekund.
15. Spam `requestRestrain`/`requestUnrestrain` hurtigt efter hinanden → blokeres af cooldown efter første forsøg.
16. Brug ziptie-item → `openRestraintMenu` toggler korrekt mellem restrain/unrestrain afhængig af target's nuværende state.
17. Test med `ox_inventory` returnerende fejl (simuleret) → handling fejler sikkert (fail-closed), ingen state-ændring.
18. Test uden `es_extended` startet → ingen unhandled error ved resource-start (kun ved faktisk brug af ESX-afhængige dele som job-permission).
19. Verificér at `masitz-restraint:client:stateChanged` broadcastes til ALLE klienter (ikke kun de involverede parter) til UX-brug.
20. Verificér via export at `RestrainPlayer`/`UnrestrainPlayer` virker uden om enhver spiller-initiator (rent system/admin-kald).

---

## 11. Security-audit

| # | Angrebsvektor | Beskyttelse |
|---|---|---|
| 1 | Klient sender `requestUnrestrain` med sit eget id for at frigøre sig selv | `AllowSelfApply/AllowSelfRemove=false` som standard, valideres server-side, ikke klient-styret |
| 2 | Klient sender et vilkårligt target-id langt væk | Server beregner afstand ud fra native `GetEntityCoords` — aldrig klient-input |
| 3 | Klient sender et target-id der ikke findes/er disconnected | `IsValidPlayer` tjekker `GetPlayerName(src) ~= nil` |
| 4 | Klient påstår at have item uden at have det | `GetItemCount` læses server-side via `exports.ox_inventory`, aldrig fra klienten |
| 5 | To spillere spammer restrain på samme target samtidig (race) | `Pending[target]`-guard omkring den yieldende del af `DoRestrain`/`DoUnrestrain` |
| 6 | Klient spammer restrain/unrestrain for at DoS'e serveren | `CheckCooldown` pr. spiller (`ActionCooldownMs`) |
| 7 | Klient forsøger at trigger'e interne server-events direkte (`masitz-restraint:server:stateChanged`) | Dette er et notifikations-event, ikke en handling — ingen kode reagerer sikkerhedsmæssigt på at modtage det, kun `Do*`-funktionerne ændrer state |
| 8 | Klient sender ugyldig `restraintType`-streng | `Config.Restraints[restraintType]` tjekkes, fejler med `invalid_type` hvis ikke fundet |
| 9 | Spiller A disconnecter mens spiller B trækker/bærer dem | `playerDropped` rydder op i begge retninger af relationen |
| 10 | Spiller forsøger at bære/trække mens de selv er restrained | Tjekket eksplicit i `DoStartCarry`/`DoStartDrag` (`iState.restrained`) |
| 11 | Spiller forsøger at bære/trække et target der allerede er i en anden relation | Tjekket via `carriedBy`/`draggedBy`/`carrying`/`dragging`-felterne før start |
| 12 | Klient forsøger at omgå `UnrestrainPermission='job'` ved at sende falsk jobdata | Job hentes server-side fra `ESX.GetPlayerFromId(initiator):getJob()`, aldrig fra klienten |
| 13 | Resource genstartes med spillere i en aktiv relation | Force-resync-thread ved start nulstiller alle klienter til en ren, matchende state |
| 14 | Klient forsøger at kalde et internt event direkte for at sætte `isDead=true` og omgå en sikkerhedstjek | `isDead` bruges ALDRIG i nogen `Do*`-sikkerhedsvalidering, kun til animations-/carry-cleanup |
| 15 | Ondsindet ressource kalder `RestrainPlayer`-exportet i loop for at spamme | Exports er tiltænkt trusted server-side kode; samme `already_restrained`/`Pending`-tjek gælder stadig og forhindrer korrupt state, om end ikke cooldown (bevidst, da systemkald ikke er bruger-input) |
| 16 | Klient forsøger at forfalske `syncState` til sig selv for at "føle" sig ikke-restrained visuelt | Muligt kosmetisk (se §12 Known limitations), men giver INGEN reel fordel da alle handlinger stadig valideres server-side ud fra den ægte `states[source]` |
| 17 | To spillere forsøger samtidig at unrestraine og carry samme target | Begge går gennem samme `Pending`/state-tjek-mønster; carry/drag er atomisk (ingen yield-points) og læser altid den friskeste `tState.restrained`/`carriedBy` |
| 18 | Klient sender non-numeriske eller manipulerede argumenter til events | Alle handlers tjekker `type(target) ~= 'number'` osv. og returnerer tidligt uden effekt |

### Fejl fundet under egen (§1) selv-audit
- Vildledende kommentar om "beskyttelse mod race condition" i `DoRestrain`, hvor `Pending[target]` allerede gjorde det umuligt på det tidspunkt — omformuleret til ærligt at beskrive det som en billig fremtidssikrings-invariant, ikke en reel nutidig race.
- `DoStartDrag` bekræftede kun draget til target, aldrig til dragger selv — gjorde `ToggleEscort`'s stop-logik umulig at ramme korrekt. Løst med et nyt `dragStarted`-event og `currentDragTarget`-variabel (spejler `carryStarted`-mønsteret).
- Ubrugt `local ESX = ...` i klientfilen — fjernet (død kode).
- Tomt no-op `if not ok then end`-block i `onResourceStop` — simplificeret til en bar `pcall`.
- `openRestraintMenu` forsøgte altid at APPLY en restraint uden at tjekke om target allerede var restrained — en regression ift. det oprindelige scripts toggle-adfærd. Rettet med et `isRestrained`-callback-tjek før valg af apply/unrestrain.

### Fejl fundet under uafhængig (§2) selv-audit ("som om jeg ikke skrev det")
- Restrain af en spiller der SELV aktivt bar/trak en tredje part efterlod dem i en modstridende animations-tilstand (tvungen "restrained idle" + carrier/dragger-animation samtidig). Løst ved at `DoRestrain`'s succes-sti nu automatisk stopper target's EGEN aktive carry/drag som handlende part (ikke selve det at blive båret/trukket AF andre — det er stadig fint).
- Klientens restraint-loop udelukkede kun tvungen animation mens `carriedBy` var sat, men manglede den tilsvarende udelukkelse for `draggedBy` — samme problemklasse for den anden kombination. Rettet ved at udvide betingelsen til også at tjekke `draggedBy`.

---

## 12. Known limitations

- **Kræver OneSync** — server-side læsning af ped-koordinater via natives forudsætter OneSync er aktiveret.
- **State persisteres bevidst ikke** — restraint-state overlever ikke et serverrestart (kun en scriptgenstart via force-resync). Dette er et bevidst designvalg for enkelhed/lav kompleksitet; kan tilføjes senere via en simpel tabel hvis ønsket, men var ikke en del af det oprindelige scripts funktionalitet heller.
- **Dødsdetektion er best-effort ved event-hooks** — hvis jeres eget dødssystem ikke matcher de lyttede events, brug det autoritative `SetPlayerDeathState`-export direkte i stedet.
- **Klientens `localState` kan i teorien manipuleres kosmetisk** af en modificeret klient (fx for selv at se ud som om restrainten er væk visuelt for spilleren selv) — dette giver INGEN reel spilmæssig fordel, da alle handlinger (kan man skyde, bruge items, osv.) stadig styres af serverens ægte state og de faktiske `blockedControls`/animation er kun til at forhindre den ÆRLIGE klient, ikke en sikkerhedsgrænse i sig selv (samme begrænsning gjaldt det oprindelige script og er iboende for enhver client-side control-disable).
- **Item-navne skal være unikke på tværs af restraint-typer** i `Config.Restraints`, ellers vil `ESX.RegisterUsableItem` blot bruge den sidst registrerede handler for det pågældende item.
