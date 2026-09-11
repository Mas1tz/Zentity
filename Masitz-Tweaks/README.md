# Masitz-Tweaks

Samlet, performance-optimeret erstatning for fire separate scripts:
`disableDispatch`, `noemergencycars`, `removeAIcops`, `disable_radio`.
Navnet er bevidst generelt ("Tweaks", ikke "Disabled") — resourcen er
tænkt som samlingspunkt for flere kommende client-side GTA-tweaks
(fx et mask-fix), ikke kun disable-funktioner.

---

## 1. Root-cause-analyse — hvorfor de gamle scripts brugte så meget CPU

Al kode blev læst og forstået før noget blev skrevet. Her er den præcise
årsag til hvert tal, ikke en antagelse:

| Script | Målt CPU | Loop | Faktisk årsag |
|---|---|---|---|
| `disableDispatch` | ~3.20 ms | `while true do Wait(0) ... end` | 12× `EnableDispatchService` + 3 wanted-level-natives, **hver eneste frame** (60+ gange/sek. = 900+ native-kald/sek.). `EnableDispatchService` er **ikke** en "ThisFrame"-native — den er persistent og virker til den ændres igen. At kalde den 60x/sekund er ren spildt CPU. |
| `removeAIcops` | ~1.60 ms | `while true do Wait(0) ... end` | `ClearAreaOfCops(x,y,z, 400.0)` **hver frame** — en af GTA's tungeste population-natives (400m radius-scan/fjernelse), brugt som permanent brute-force-løsning i stedet for at forhindre spawn i første omgang med de lette, persistente `SetCreateRandomCops`-natives. |
| `noemergencycars` | ~1.20 ms | `while true do Wait(0) ... end` | To reelle bugs: (1) `PlayerData` blev **aldrig udfyldt** noget sted i scriptet (intet `esx:setJob`-handler), så `PlayerData.job` var altid `nil`, og hele blokken kørte reelt **aldrig** — de 1.20 ms gik til at polle `IsPedInAnyPoliceVehicle`/`GetVehiclePedIsUsing` hver frame for ingenting. (2) Selv hvis den havde virket: betingelsen `job.name ~= 'police' or job.name ~= 'ambulance'` er en De Morgan-logikfejl — den er **altid sand** uanset job (selv en rigtig betjent ville få sin egen patruljevogn deaktiveret). Se §3 for hvordan dette er rettet. |
| `disable_radio` | ~0.00 ms | `while true do Wait(1000) ... end` | Allerede optimalt. `Wait(1000)`, ingen tunge natives. **Uændret** her udover at fjerne en ubrugt ESX-reference (samme døde `PlayerData`-mønster som i noemergencycars, bare uden konsekvens fordi den aldrig blev læst). |

**Overlap fundet:** Ingen reel funktionsoverlap mellem de 4 — hver løser
noget forskelligt. Det eneste "overlap" var arkitektonisk: alle fire brugte
en uafhængig `while true do Wait(low) end`-tråd, ofte for indstillinger der
reelt kun skulle sættes én gang.

---

## 2. Ny arkitektur

```
Masitz-Tweaks/
├── fxmanifest.lua
├── config.lua
├── client/
│   └── main.lua
└── README.md
```

Én fil, som du bad om ("en client"), organiseret i tydeligt afgrænsede
sektioner (dispatch / AI cops / emergency-trafik / emergency-kørsel /
radio) i stedet for fem separate filer.

**Princippet gennemgående:** alt der er en *persistent* GTA-indstilling
sættes **én gang** (ved resource-load + defensivt ved hvert spawn). Kun
det der reelt kræver periodisk reapplicering (fordi andre systemer kan
ændre det, eller fordi GTA ikke har en permanent-undertrykkelses-native)
kører i en tråd — og altid med det længst forsvarlige interval, aldrig
`Wait(0)`.

| Funktion | Gammel tilgang | Ny tilgang | Hvorfor |
|---|---|---|---|
| Dispatch services | 12 kald hver frame | 12 kald ÉN gang (load + spawn) | Persistent native |
| Wanted level | 3 kald hver frame | 3 kald hvert `Config.WantedLevelInterval` (1000 ms) | Skal reapplyes (andre systemer kan hæve den), men ikke 60x/sek |
| AI cop-flags | N/A (brugte slet ikke disse) | Sat ÉN gang (load + spawn) | Persistent native |
| AI cops sikkerhedsnet | `ClearAreaOfCops` hver frame | Reapply-flags + ÉN `ClearAreaOfCops` hvert `Config.AICopsSafetyInterval` (30s) | Fanger scriptede cop-peds spawnet direkte (uden om population-systemet) — se §"hvorfor ikke 0.00 ms" |
| Ambient emergency-trafik | Fandtes ikke i det oprindelige script | Scan hvert `Config.EmergencyTrafficSweepInterval` (5s) | GTA har ingen native til permanent at undertrykke én køretøjsklasse fra ambient spawn — se nedenfor |
| Emergency-køretøj kørsels-spærre | Hver frame, men reelt død kode | 100% event-drevet (`CEventNetworkPlayerEnteredVehicle`) | Nul polling — kun et kald når nogen rent faktisk sætter sig i førersædet |
| Radio | `Wait(1000)`, allerede godt | Uændret | "Ødelæg ikke det der virker" |

---

## 3. Detaljer pr. funktion

### Dispatch (`Config.DisableDispatch`)
`EnableDispatchService(i, false)` for service 1-12 sat én gang ved load
og igen ved `playerSpawned` (defensivt, i tilfælde af at noget nulstiller
det ved respawn — billigt, da det kun sker ved selve spawn-eventet, ikke
i en loop). En let tråd (`Config.WantedLevelInterval`, standard 1000 ms)
tvinger fortsat wanted level til 0, da wanted level (i modsætning til
dispatch-service-flagene) kan hæves af andre events/scripts og derfor
reelt kræver periodisk håndhævelse.

### AI cops (`Config.DisableAICops`)
`SetCreateRandomCops(false)` + `SetCreateRandomCopsNotOnScenarios(false)`
+ `SetCreateRandomCopsOnScenarios(false)` sat én gang ved load + spawn.
Disse forhindrer GTA's population-system i at spawne nye ambient cop-peds
overhovedet — den rigtige fix, i stedet for at fjerne dem efter de allerede
er spawnet. Et sikkerhedsnet (`Config.AICopsSafetyInterval`, standard
30 sekunder) reapplicerer flagene og laver ÉN `ClearAreaOfCops`-sweep, som
ekstra beskyttelse mod cop-peds spawnet direkte af et andet resource/en
mission (population-flags har ingen magt over den slags). Sæt
`Config.AICopsSafetyInterval = 0` for at slå sikkerhedsnettet helt fra,
hvis du er sikker på at ingen andre resources spawner cop-peds direkte.

### Ambient emergency-trafik (`Config.DisableEmergencyTraffic`) — NY funktion
Det oprindelige `noemergencycars`-script gjorde IKKE dette (se §1) — men
navnet og din beskrivelse antydede det, så det er bygget fra bunden.
Scanner `GetGamePool('CVehicle')` hvert `Config.EmergencyTrafficSweepInterval`
(standard 5 sekunder — ikke hver frame), og markerer emergency-klasse
køretøjer (`GetVehicleClass == 18`) som `SetEntityAsNoLongerNeeded`,
**men kun hvis ingen spiller sidder i dem** (tjekker samtlige sæder, ikke
kun føreren — beskytter enhver spillers legitime ambulance/politibil).
Ingen force-delete: vi har ikke nødvendigvis network-ownership over et
ambient køretøj, og et forceret `DeleteEntity` på noget en anden klient
ejer kan desynce. `SetEntityAsNoLongerNeeded` er den sikre, ikke-
destruktive metode.

**Hvorfor dette ikke kan være 0.00 ms:** GTA V har ingen native der
permanent undertrykker én bestemt køretøjsklasse fra ambient population-
spawn (i modsætning til fx `SetRandomBoats`/`SetRandomTrains`, som styrer
hele kategorier, ikke en enkelt klasse). At foregive 0.00 ms her ville
betyde funktionen reelt ikke virker. 5-sekunders-intervallet er den
billigste løsning der stadig faktisk fjerner ambient emergency-trafik
inden for få sekunder efter spawn.

### Emergency-køretøj kørsels-spærre (`Config.RestrictEmergencyVehicles`)
Den oprindelige, tiltænkte funktion bag `noemergencycars` — kun jobs i
`Config.AllowedEmergencyJobs` (standard: `police`, `ambulance`) må sidde
på FØRERSÆDET af et emergency-klasse-køretøj. Genopbygget fra bunden:
- **Bug rettet:** `PlayerData.job` udfyldes nu faktisk, via `esx:setJob` +
  `esx:playerLoaded`.
- **Bug rettet:** logikken er nu et opslag i `Config.AllowedEmergencyJobs`
  (svarer til korrekt `and`-logik), ikke den tautologiske `or`-fejl.
- **Performance rettet:** 100% event-drevet via `gameEventTriggered` /
  `CEventNetworkPlayerEnteredVehicle` i stedet for et `Wait(0)`-loop — der
  bruges nul CPU, indtil nogen faktisk sætter sig ind i et emergency-
  køretøj.

Denne ene delfunktion kræver ESX (ligesom det oprindelige script gjorde)
— resten af resourcen kræver intet framework.

### Radio (`Config.DisableRadio`)
Uændret logik og interval (`Wait(1000)`) — allerede ~0.00 ms, intet at
optimere. Kun den ubrugte ESX/`PlayerData`-reference er fjernet, så denne
ene sektion ikke længere har nogen framework-afhængighed overhovedet.

---

## 4. Framework (§15)

Kun **én** delfunktion — emergency-køretøj kørsels-spærren — bruger ESX,
fordi den grundlæggende handler om spillerens *job*, som er et
framework-koncept. Den er skrevet til at vente pænt på at `es_extended`
starter (`GetResourceState`-tjek, ikke en fejl hvis ESX mangler) og fejler
blot ikke-destruktivt hvis ESX ikke findes på din server. De øvrige fire
funktioner (dispatch, AI cops, ambient emergency-trafik, radio) har
**ingen** framework-afhængighed overhovedet.

`es_extended` er derfor bevidst IKKE en hård `dependency` i
`fxmanifest.lua` — resourcen starter og fungerer fint uden den, du
mister blot kørsels-spærre-funktionen.

---

## 5. Config

```lua
Config.DisableDispatch            = true
Config.DisableAICops              = true
Config.DisableEmergencyTraffic    = true
Config.RestrictEmergencyVehicles  = true
Config.DisableRadio               = true
```

Slå enhver funktion fra individuelt uden at røre koden. Se `config.lua`
for alle intervaller/radius/job-liste.

---

## 6. Events & exports — bagudkompatibilitet (§16, §23)

Ingen af de 4 oprindelige scripts eksponerede nogen `exports`, og ingen af
dem registrerede noget event et andet script kunne trigge ind i (alt var
interne `while true` loops uden `RegisterNetEvent`/`exports`). Der er
derfor **intet at lave compatibility-wrappers for** — ingen andre
resources kan have været afhængige af noget her.

---

## 7. Testrapport

**[PASS] — fysisk kørt**
- `luac5.4 -p` på alle 3 filer — ingen syntaksfejl.
- Mock Lua-testharness: bekræfter at `EnableDispatchService` og
  `SetCreateRandomCops` nu kaldes **præcis én gang** ved load (ikke pr.
  frame), og at intet kaldes overhovedet når deres respektive
  `Config.Disable*`-flag er `false`.

**[STATICALLY VERIFIED] — kodegennemgået, ikke kørt**
- `EnableDispatchService`/`SetCreateRandomCops`-familiens persistente
  (ikke "ThisFrame") opførsel — bekræftet ud fra native-navnekonvention
  og etableret FiveM-community-praksis (langt de fleste "no dispatch"/
  "no cops"-resources sætter disse én gang, ikke i en loop).
- `gameEventTriggered`/`CEventNetworkPlayerEnteredVehicle`-baseret
  detektion af køretøjs-indstigning — standard FiveM-mønster, samme type
  event allerede brugt korrekt i `Masitz-Anticheat` i dette repo.

**[NOT PHYSICALLY TESTED]**
- Faktisk in-game CPU-måling (kræver `resmon`/`txAdmin` på en kørende
  server) — jeg kan ikke selv måle ms-forbrug uden en live FiveM-klient.
  De arkitektoniske ændringer (fra 60 kald/sek. til 1 kald ved load, og
  fra polling til events) er dog af en størrelsesorden der gør et fald
  til under 0.05 ms overordentligt sandsynligt for dispatch/AI cops/
  kørsels-spærre — men jeg vil ikke påstå et præcist ms-tal jeg ikke har
  målt.
- Ambient emergency-trafik-sweepen (ny funktion) er ikke testet mod en
  reel, befolket GTA-verden.

---

## 8. Server.cfg — korrekt rækkefølge

```cfg
# Fjern/udkommentér de 4 gamle:
# stop disableDispatch
# stop noemergencycars
# stop removeAIcops
# stop disable_radio

ensure Masitz-Tweaks
```

Konkret: fjern (eller udkommentér) `ensure`/`start`-linjerne for
`disableDispatch`, `noemergencycars`, `removeAIcops` og `disable_radio`
fra `server.cfg`, og tilføj `ensure Masitz-Tweaks` i stedet. Ingen
database, ingen andre resources skal genstartes.
