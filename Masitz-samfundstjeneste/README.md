# MM Samfundstjeneste V2

Modulær ESX/ox_lib/oxmysql-baseret samfundstjeneste-resource med NUI-dashboard
for spillere, staff og owner.

## Installation

1. Sørg for at `es_extended`, `ox_lib` og `oxmysql` er startet før denne resource.
2. Kør `sql/install.sql` mod din database (eller lad resourcen oprette
   tabellerne automatisk ved første start — begge dele fører til samme resultat).
3. Tilføj til `server.cfg`, **før** `ensure Masitz-samfundstjeneste`:

   ```cfg
   set steam_webApiKey "din-steam-web-api-nøgle"
   ```

   Steam-nøglen bruges udelukkende server-side (`server/identity.lua`) til at
   hente spillerens Steam-navn/avatar til staff/owner-profiler. Uden nøglen
   fungerer resten af systemet fint — Steam-felterne er bare tomme.
4. `ensure Masitz-samfundstjeneste`

## Kommandoer

Åbner dashboardet (spiller/staff/owner-visning afgøres altid server-side):

```
/sf
/samfundstjeneste
```

Rediger listen i `Config.Samfundstjeneste.Commands`.

## Permissions

- **Owner**: bestemt af Discord-ID i `Config.Samfundstjeneste.Permissions.OwnerDiscordId`.
- **Staff**: ESX-grupper listet i `Config.Samfundstjeneste.Permissions.StaffGroups`.

`server/permissions.lua` er det ENESTE sted disse tjekkes — alt andet (NUI-
callbacks, events, kommandoer) spørger dette modul. Når I senere kobler jeres
eget Discord-auth-system på, er `Permissions.IsOwner` det eneste der skal ændres.

## Tilføj et nyt arbejdssted eller en ny opgavetype

Alt sker i `config.lua` — ingen andre filer skal røres:

```lua
Config.Samfundstjeneste.Sites.carwash = {
    label = 'Vaskehallen',
    sendCoords = vec3(...),
    antiEscape = { center = vec3(...), radius = 50.0 },
    tasks = { 'sweeping', 'washing' },
}

Config.Samfundstjeneste.Tasks.washing = {
    label = 'Vask bilen',
    description = 'Skyl bilen ren for sæbe.',
    enabled = true,
    duration = { min = 5000, max = 12000 },
    animation = { type = 'emote', command = 'e mechanic3' },
    points = { vec3(...), vec3(...) },
}
```

Owner kan aktivere/deaktivere eksisterende opgavetyper live fra dashboardets
"Opgavetyper"-fane. Helt nye tasks/sites (nye koordinater, animationer) kræver
bevidst en filredigering + genstart — det er placeringer og animationer der
bør gennemtjekkes af en udvikler, ikke ændres i farten fra en UI-knap.

## Runtime-indstillinger (Owner-dashboard)

Følgende kan ændres live uden genstart, fra Owner-fanen "Indstillinger":
trust factor-metode og -beløb, recovery-parametre, AFK-timeout, automatisk
tidsreduktion (interval/mængde), og anti-escape (til/fra + pause-varighed).
Værdierne persisteres i `sf_settings` og overlever en resource-genstart.

## Arkitektur

```
config.lua              — Sites, Tasks, TrustFactor, TimeReduction, AntiEscape, Identity, Permissions
shared/utils.lua         — clamp/round, trust-farvegradient, safe json

server/database.lua      — tabel-opsætning, audit/history insert-helpers
server/permissions.lua   — eneste kilde til IsStaff/IsOwner
server/players.lua       — cache <-> database, identifier-opslag, søgning
server/settings.lua      — runtime-redigerbare config-værdier (sf_settings)
server/trustfactor.lua   — tab ved tildeling, AFK-aware recovery-tick
server/tasks.lua         — give/tilføj/fjern/sæt/løslad, task-sessions, automatisk tidsreduktion,
                           anti-repeat opgavevalg, CENTRAL CompleteCommunityService (se nedenfor)
server/antiescape.lua    — server-verificeret zone-tjek, pause af tidsreduktion
server/identity.lua      — Steam Web API-opslag (server-side only)
server/staff.lua         — staff NUI-callbacks
server/owner.lua         — owner NUI-callbacks (settings, statistik, audit log)
server/main.lua          — kommandoer, dashboard-åbning, egen historik

client/main.lua           — NUI open/close, videreformidler alle staff/owner-callbacks,
                             holder PlayerTaskState.activeTasks opdateret (se TextUI nedenfor)
client/activity.lua        — AFK-/aktivitetsdetektion til trust recovery
client/service.lua         — send til site, service-state
client/combat.lua          — blokerer skydning/melee KUN for spilleren selv, KUN mens i tjeneste
client/tasks.lua           — marker, [E], progressbar, animation, session-completion
client/antiescape.lua       — afstandstjek til sitets zone

html/                      — NUI-dashboard (spiller/staff/owner)
sql/install.sql             — databaseskema
```

## Central completion (`CompleteCommunityService`)

Alle veje der kan bringe en spillers `active_tasks` til 0 — manuel
gennemførelse af sidste opgave, automatisk tidsreduktion, Staff der
fjerner/sætter opgaver ned til 0, eller et eksplicit Release — kalder
samme centrale funktion i `server/tasks.lua`. Den håndterer teleport til
`Config.Samfundstjeneste.General.releaseCoords`, notifikation, audit-log,
og rydder service-/session-/anti-repeat-state. Der findes bevidst ingen
anden vej til at afslutte en tjeneste end denne ene funktion.

## Anti-repeat (undgå AFK-farming)

`Config.Samfundstjeneste.AntiRepeat.avoidLastPoints` (standard: 2) styrer
hvor mange af de senest brugte arbejdspunkter der udelukkes, når serveren
vælger næste opgaves placering (`server/tasks.lua`). Er der for få unikke
punkter til at kunne undgå dem alle, bruges hele puljen i stedet for at
fejle. Ren server-side, in-memory pr. spiller — kan ikke omgås fra
klienten, og nulstilles naturligt ved disconnect.

## TextUI og "1 opgave tilbage"

`[E] Udfør opgave`-prompten (`lib.showTextUI`) vises kun når spilleren har
2 eller flere aktive opgaver tilbage (`client/tasks.lua`,
`MIN_TASKS_FOR_PROMPT`). Ved præcis 1 tilbage undertrykkes selve
tekstprompten bevidst — markøren i verden og selve `[E]`-interaktionen
virker uændret, kun tekst-overlayet skjules, for at undgå det tidligere
flakkende forløb i overgangen til `CompleteCommunityService`. Klienten
kender sit eget opgavetal via `PlayerTaskState.activeTasks`
(`client/main.lua`/`client/service.lua`) — udelukkende til UI-visning,
aldrig som grundlag for om en opgave rent faktisk godkendes.

## Combat-restriktion under aktiv tjeneste

`client/combat.lua` er et helt isoleret modul: mens `Service.active` er
sand, disabler det hvert frame kun `DisablePlayerFiring` +
`SetPlayerCanDoDriveBy(false)` + de fem specifikke angrebs-kontroller
(Attack/Attack2/melee light/heavy/alternate) — intet andet. Ingen globale
control-disables, ingen indgreb i våben-udstyr eller inventory-state.
Loopet starter/stopper med selve tjenesten og har derfor nul CPU-omkostning
resten af tiden. Ved tjenestens afslutning gendannes begge natives eksplicit
med det samme, ikke kun ved at stoppe loopet.

## Kendte afgrænsninger

- Nye sites/tasks (koordinater, animationer) tilføjes i `config.lua`, ikke fra
  UI'en — se begrundelse ovenfor.
- Discord-brugernavn/avatar udfyldes ikke automatisk (kræver en bot-token og
  jeres eget Discord-system) — felterne i databasen står klar til det.
