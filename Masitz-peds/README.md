# Masitz-peds

Et config-drevet PED/NPC-framework til ESX Legacy + ox_lib + ox_target.
Tilføj, ret eller fjern en NPC ved KUN at redigere `config.lua` — ingen
client/server-kode skal nogensinde ændres for at ændre hvad der står på
mappet.

## Struktur

```
Masitz-peds/
├── fxmanifest.lua
├── config.lua              -- ALT indhold + intern validering/indeksering (shared_script)
├── client/
│   ├── peds.lua              -- model/animation-loading, spawn/despawn, native ped-opsætning
│   ├── interactions.lua      -- ox_target, TextUI, job/gruppe-gating, interaktions-afsendelse
│   └── main.lua               -- bootstrap + DET ENESTE loop i resourcen
├── server/
│   └── main.lua                -- interaktions-gatewayen (det eneste server-event)
└── README.md
```

## Config-first

Se `config.lua`'s kommentarer for den fulde feltreference. Kort fortalt:
hver `Config.Peds`-entry styrer model, coords (vec4), scenario ELLER
animation, freeze/invincible/collision/ragdoll/block_events (alle
sammen slås til/fra pr. ped — se `Config.Defaults` for hvad der sker
når et felt er udeladt), spawn/despawn-afstand, og `interaction`
(`'target'`, `'textui'` eller `'both'`).

`target.options[n]` og `textui` deler samme "action"-form:
`event`/`serverEvent`/`groups`/`canInteract` — se afsnittet "Security"
nedenfor for hvornår du skal bruge hvilken.

## Performance

**Ét eneste loop findes i hele resourcen** — distance-loopet i
`client/main.lua`. Waittiden er adaptiv:

| Situation | Wait |
|---|---|
| Ingen ped inden for nogens `spawnDistance` | `1000ms` |
| Mindst én ped inden for `spawnDistance`, men ingen TextUI-nærhed | `250ms` |
| Inden for en TextUI-peds interaktionsafstand | `0ms` — **kun** så længe det varer |

Ingen `GetActivePlayers()`, ingen gentagne dyre kald — modellernes hash
udregnes ÉN gang ved indlæsning (`joaat`), spawn/despawn-afstande
sammenlignes som **kvadreret afstand** (ingen `sqrt`), og
TextUI-kandidat-listen genbruger de samme tabeller hvert tick i stedet
for at allokere nye (`Config.Peds` er typisk et par håndfulde
entries — men vanen er den samme uanset antal).

`ox_target`-baserede peds kræver INGEN ekstra logik fra denne
resource ud over spawn/despawn — ox_target håndterer selv sin egen
hover/select-afstand og rendering, helt event-drevet.

Ped-spawning er **asynkront**: indlæses en models streaming langsomt,
blokerer det kun DEN ene peds egen spawn-coroutine, aldrig
hovedloopet eller andre peds. Et `pending`-flag forhindrer dobbelt-spawn
af samme ped mens dens model stadig loader.

## Security

Masitz-peds har **ét eneste** server-event:
`Masitz-peds:server:interact`. Klienten sender KUN et ped-id og et
option-navn (identifikatorer — aldrig label, pris, event-navn eller
andet der kunne forfalskes) — serveren slår selv den ægte config-entry
op (`Config.PedsById`, samme validerede data som klienten bruger, da
`config.lua` er et shared_script) og genvaliderer:

1. At ped-id og option-navn rent faktisk findes i config.
2. At optionen faktisk HAR en `serverEvent` sat (en ren client-`event`
   kan aldrig bruges til at trigge gatewayen).
3. Spillerens **reelle** ESX-job/grade mod `groups` — aldrig klientens
   påstand.
4. Spillerens **reelle** afstand (`GetEntityCoords(GetPlayerPed(src))`)
   til ped'ens config-coords, med en lille netværks-tolerance.

Kun hvis ALLE fire tjek består, videresendes til det event I selv
konfigurerede (`TriggerEvent(action.serverEvent, src, pedId,
optionName)`) — det er JERES eget resource der herefter rent faktisk
giver penge/items/adgang, med en garanti for at afsenderen allerede er
job- og afstands-godkendt.

**Brug `event` (client-side) til ting uden konsekvens** — dialog,
en animation, en menu der åbner. **Brug `serverEvent` til alt der giver
penge, items eller adgang** — det er den eneste vej der bliver
genvalideret server-side.

Verificeret med to mock-test-suiter der kører de RIGTIGE
`config.lua`/`server/main.lua`-filer under `lua5.4`:

- **Config-validering** (21 assertions): de 3 medfølgende eksempel-peds
  validerer korrekt; en håndfuld bevidst ødelagte entries (manglende
  id/model/coords, forkert coords-type, ugyldig interaction, tom
  target.options, manglende event/serverEvent, duplikeret id) afvises
  alle med en klar logbesked UDEN at crashe eller blokere en gyldig
  entry der kommer efter dem i listen.
- **Interaktions-gatewayen** (25 assertions): et gyldigt kald
  videresender præcis én gang til det korrekte event; en option uden
  `serverEvent` kan ikke bruges til at trigge gatewayen overhovedet;
  forkert job, for stor fysisk afstand, et opdigtet ped-id, et
  opdigtet option-navn, ugyldige argument-typer (tabel/tal/nil/boolean)
  og en spiller uden ESX-data afvises alle uden at crashe serveren.

## Klar til exports (endnu ikke aktiveret)

Al logik ligger allerede i navngivne, genanvendelige funktioner under
`PEDS`-navnerummet — at tilføje de fremtidige exports er en ren
one-liner pr. export, ingen omskrivning:

```lua
-- eksempel på hvordan de SENERE kan tilføjes, ét sted, i client/main.lua:
exports('CreatePed', PEDS.CreateConfiguredPed)
exports('RemovePed', PEDS.DeleteConfiguredPed)
exports('GetPed', PEDS.GetPed)
exports('GetAllPeds', PEDS.GetAllPeds)
```

`PEDS.CreateConfiguredPed(id)`, `PEDS.DeleteConfiguredPed(id)`,
`PEDS.RegisterPedTarget(id)`, `PEDS.UnregisterPedTarget(id)`,
`PEDS.ShowTextUi(id)` / `PEDS.HideTextUi()`, `PEDS.CleanupPed(id)`,
`PEDS.GetPed(id)` og `PEDS.GetAllPeds()` findes allerede og bruges
internt af resourcen selv — de er blot ikke eksponeret som `exports(...)`
endnu, præcis som ønsket.

## Cleanup

`onResourceStop` kalder `PEDS.CleanupPed` for hver ped: fjerner
ox_target-registreringen, skjuler en evt. aktiv TextUI, og sletter
entiteten. Ingen efterladte peds, targets eller TextUI-states ved
resource-restart.

## Debug

`Config.Debug = false` som standard. Sæt til `true` for at se
ped-spawn/despawn, target-(af)registrering, interaktioner, og
model/animation-fejl i konsollen. Sikkerheds-relaterede afvisninger
logges altid (`^1[Masitz-peds SECURITY]^7`), uanset `Config.Debug`.
