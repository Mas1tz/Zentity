# Masitz-commands

Standalone FiveM resource (ESX Legacy · ox_lib · oxmysql) med to
uafhængige commands: `/pov` + `/povdone` (POV-anmodninger med
tidsfrister, historik og eskalerende straf) og `/check` (server-side
spiller-opslag sendt til Discord). Rører intet i jeres eksisterende
moderation-, PVP- eller anti-cheat-resources.

## 1. Analyse af den eksisterende server foretaget før implementation

Før noget blev skrevet blev følgende gennemgået i den eksisterende
resource-mappe:

- **Ban-system**: intet server-bredt ban-system fundet nogen steder
  (kun et duel-scopet exclusion-system i `bach_duels`, som ikke er en
  generel spiller-ban). Denne resource implementerer derfor sin egen
  minimale, persistente løsning (`masitz_commands_bans`), håndhævet i
  `playerConnecting` - præcis efter kravet om at integrere med et
  eksisterende system, hvis et findes, og ellers bygge et minimalt selv.
- **Discord-integration**: ingen eksisterende Discord-bot (ingen
  `SetHttpHandler`, ingen bot-token, ingen inbound API) fundet noget
  sted. `discord_name`/`discord_avatar`-felterne i
  `Masitz-samfundstjeneste`'s database er ubrugte placeholder-kolonner,
  ikke en fungerende integration. Se §5 for den nye, dokumenterede
  API-kontrakt til jeres eksterne bot.
- **Discord-ID-opslag**: samme mønster som
  `Masitz-samfundstjeneste/server/permissions.lua` (`GetPlayerIdentifiers`
  + find `discord:`-præfiks) genbruges for konsistens.
- **Permission-gating**: samme arkitektur som
  `mm-adminpakke/server/security.lua` (`Security.IsAdmin`) - ESX-gruppeliste
  med mulighed for i stedet at bruge en ren ACE-permission. Genimplementeret
  selvstændigt (ikke exporteret af mm-adminpakke), så resourcen forbliver
  standalone.
- **Database**: `MySQL.query/single/scalar/insert/update.await`
  (`@oxmysql/lib/MySQL.lua`) er den dominerende konvention på tværs af
  serveren (`Masitz-garage`, `Masitz-politijob`, `MM-polititablet`,
  `Masitz-Anticheat`, `bach_duels`) og er derfor brugt her, frem for
  `Masitz-samfundstjeneste`'s afvigende `exports.oxmysql:...`-stil.

## 2. Struktur

```
Masitz-commands/
├── fxmanifest.lua
├── config.lua
├── client/
│   └── main.lua        -- kun lib.alertDialog-visning (se §6)
└── server/
    ├── main.lua         -- database, identifiers, permissions, cooldown, ban-håndhævelse
    ├── discord.lua       -- central webhook-logger + indgående HTTP-API (§5)
    ├── pov.lua           -- /pov, /povdone, hele POV-tidsfrist-maskinen
    └── check.lua         -- /check
```

## 3. Config

Alt styres fra `config.lua` under `Config.Command.<Navn>`, jf. den
ønskede filosofi. Se de kommenterede felter i filen selv for den fulde
reference. Vigtigst ved opsætning:

- `Config.Command.Pov.Webhook` / `Config.Command.Check.Webhook` - sæt
  jeres rigtige Discord-webhook-URL'er.
- `Config.Command.Pov.DiscordApi.SharedSecret` - **skift denne** før I
  aktiverer den automatiske Discord-integration (se §5).
- `Config.Command.Pov.Povdone.AllowedGroups` /
  `Config.Command.Check.AllowedGroups` - jeres faktiske staff-grupper.
  `/pov` selv har bevidst INGEN permission, jf. kravet.
- `Config.Command.Check.SteamApiKey` - valgfri. Uden den vises stadig
  SteamID64 og et korrekt profil-link (kræver ingen API-nøgle), kun det
  faktiske Steam-visningsnavn kræver nøglen.

## 4. `/pov` [ID] og `/povdone` [ID]

- `/pov [ID]` - alle spillere må bruge den, ingen permission. Server-side
  cooldown (`Config.Command.Pov.Cooldown`, standard 30s) - da kommandoen
  er registreret via `RegisterCommand` i server-koden (ikke et
  client→server event), er der intet at sende direkte og omgå cooldownen
  med.
- Målet får en `lib.notify` (center-right) med tydelig frist og
  Discord-kanal-reference.
- **Første anmodning nogensinde**: 15 min (`FirstTimeout`), derefter ved
  udløb en `lib.alertDialog`-advarsel og yderligere 15 min
  (`SecondTimeout`) = 30 min total. Overskrides det → **kick**
  (server-side `DropPlayer`), og fejlet forsøg registreres persistent.
- **Anmodning nummer to** (spilleren har tidligere en kick for manglende
  POV i historikken): ét samlet vindue på 20 min
  (`RepeatTimeout`), ingen advarsel undervejs. Overskrides det →
  **permanent ban** (egen `masitz_commands_bans`-tabel, håndhævet ved
  connect).
- Rejoin efter et kick giver **ikke** automatisk ban - kun selve fejlet
  forsøgt tælles i historikken (`masitz_commands_pov_history`).
- Kun én aktiv anmodning ad gangen pr. spiller - en ny `/pov` mod en
  spiller med en allerede aktiv anmodning opretter ikke endnu en timer.
- `/povdone [ID]` (staff, jf. `Config.Command.Pov.Povdone`) markerer den
  aktive anmodning som gennemført med det samme, stopper timeren, og
  logges til Discord. Ingen aktiv anmodning for målet → pænt no-op +
  Discord-log, ingen fejl.
- Alt overlever et resource-restart: aktive anmodninger gemmes i
  `masitz_commands_pov_requests` med absolutte deadline-timestamps.
  Ved genstart genberegnes resterende tid ud fra disse timestamps -
  en frist der allerede er overskredet mens serveren var nede
  håndhæves med det samme i stedet for at blive glemt.

## 5. Automatisk POV-registrering fra en ekstern Discord-bot

Der findes **ingen** eksisterende Discord-bot-integration på serveren i
forvejen (bekræftet ved gennemgang - se §1), så FiveM Lua kan ikke i sig
selv "læse" en besked i jeres POV-kanal. Denne resource eksponerer i
stedet et lille, sikret HTTP-endpoint, som jeres EGEN, eksterne
Discord-bot (fx en discord.py/discord.js-bot der lytter på
kanal-ID `1548295920079081472`) skal kalde, når en POV-video er
indsendt.

**Vigtigt om verifikation**: boten sender KUN spillerens Discord-ID.
Hvilken FiveM-spiller det Discord-ID hører til, og om der overhovedet er
en aktiv POV-anmodning for dem, slås udelukkende op i serverens egen,
tidligere indsamlede state (Discord-ID'et blev gemt server-side, ud fra
spillerens egne identifiers, allerede da `/pov` blev brugt) - boten kan
altså ikke selv påstå/forfalske hvem der har sendt POV.

```
POST http://<jeres-fivem-server-ip>:<port><Config.Command.Pov.DiscordApi.HttpPath>
Header:  X-Masitz-Secret: <Config.Command.Pov.DiscordApi.SharedSecret>
Content-Type: application/json

Body:
{
    "discordId": "123456789012345678"
}
```

Svar:

| Status | Betydning |
|---|---|
| `200 {"ok":true}` | POV registreret, anmodning completed |
| `400 {"ok":false,"error":"invalid_body"}` | Body mangler/ugyldig `discordId` |
| `401 {"ok":false,"error":"unauthorized"}` | Forkert/manglende `X-Masitz-Secret` |
| `404 {"ok":false,"error":"no_active_request_for_discord_id"}` | Ingen aktiv POV-anmodning for det Discord-ID |
| `503 {"ok":false,"error":"not_configured"}` | `SharedSecret` er stadig standardværdien - skift den først |

**Bemærk**: FXServer tillader kun ét globalt `SetHttpHandler` pr. server.
Kører I allerede et andet resource der selv kalder `SetHttpHandler`, vil
de kollidere (kun det senest startede resources handler er aktiv) - I
skal i så fald slå `Config.Command.Pov.DiscordApi.Enabled` fra her og i
stedet lade jeres andet resource videresende til
`exports['Masitz-commands']` - se `server/pov.lua`'s `Pov.CompleteByDiscordId(discordId)`
for den funktion der reelt udfører completion, hvis I foretrækker at
kalde den direkte fra et andet, samkørende Lua-resource i stedet for via
HTTP.

## 6. `/check` [ID]

Kun staff (`Config.Command.Check.AllowedGroups`/`UseAcePermission`).
Henter server-side og sender UDELUKKENDE til Discord
(`Config.Command.Check.Webhook`) - aldrig som chat-besked, hverken til
target-spilleren eller til den der bruger kommandoen (kun en generisk
"sendt til Discord"-bekræftelse).

Indhold: server-ID, FiveM-navn, ping, Discord-ID + profil-link
(`https://discord.com/users/<id>` - kræver ingen bot for at være
gyldigt), Steam-ID64 + profil-link (udledt af `steam:HEX`-identifieren,
kræver ingen API-nøgle) + Steam-visningsnavn (kun med
`Config.Command.Check.SteamApiKey` sat), IP (server-side
`GetPlayerEndpoint`), license/license2/øvrige identifiers. Manglende
felter vises som "Ikke fundet" i stedet for at fejle.

## 7. Sikkerhed

- Alt er server-autoritativt. Klienten sender kun et mål-ID til `/pov`,
  `/povdone`, `/check` - resten (navn, identifiers, IP, historik,
  timere) slås udelukkende op server-side.
- `/pov`/`/povdone`/`/check` er registreret som **server-side**
  commands (`RegisterCommand` i `server/*.lua`) - der findes intet
  client→server event for dem, så der er intet at spoofe cooldown,
  completion eller data igennem.
- Hvert POV-timer-forløb er bundet til et generations-tal pr. anmodning:
  bliver en anmodning completed (manuelt eller automatisk), bliver alle
  udestående planlagte timere for den et sikkert no-op i stedet for at
  kunne straffe en spiller efter deres POV allerede er godkendt.
- Discord-ID/Steam-ID/IP kan aldrig spoofes af klienten - de læses
  udelukkende via native FiveM-funktioner (`GetPlayerIdentifiers`,
  `GetPlayerEndpoint`) server-side.
- Den automatiske Discord-completion stoler ALDRIG på et Discord-ID
  boten selv kunne finde på at sende for en spiller uden aktiv
  anmodning - kun et Discord-ID der matcher en anmodning oprettet
  tidligere ud fra en reelt tilsluttet spillers egne identifiers,
  godkendes.
- Simpel misbrugsbeskyttelse (`Config.AbuseProtection`) logger til
  Discord ved gentagne ugyldige `/pov`-forsøg.

## 8. Performance

Ingen permanente `while true do Wait(0) end`-loops for selve
POV-systemet. Hver frist er ét enkelt `SetTimeout`, event-drevet.
Databasen forespørges kun ved oprettelse/completion/restart - ikke i
noget polling-loop. Discord-webhooks sendes kun ved faktiske
hændelser, aldrig periodisk.

## 9. Verifikation udført

- `luac5.4 -p` kørt på samtlige Lua-filer - alle består.
- Et mock Lua-testmiljø (stubber FiveM/ESX/oxmysql/ox_lib-nativerne, kører
  de RIGTIGE, medfølgende filer under `lua5.4`) - 34 assertions dækker:
  grundlæggende oprettelse/notifikation, dubletbeskyttelse, selv-target
  og ugyldige ID'er, server-side cooldown (og at den rent faktisk
  udløber igen), det fulde to-trins tidsfrist-forløb frem til kick,
  persistent historik, at rejoin efter et kick ikke giver automatisk
  ban, en gentagelses-anmodnings skærpede 20-minutters frist frem til
  permanent ban, at banned-håndhævelsen faktisk afviser en genforbindelse,
  at `/povdone` completer korrekt (og korrekt er et no-op uden en aktiv
  anmodning), at en completed anmodnings gamle timere bliver no-ops, samt
  fuld permission-gating og databehandling for `/check` (inkl. en spiller
  helt uden Discord/Steam-identifiers).
- Et separat, isoleret restart-genoprettelses-testmiljø - 6 assertions
  bekræfter at en allerede overskredet frist fra før genstarten
  håndhæves med det samme ved opstart, og at en frist der stadig har tid
  tilbage genberegnes præcist ud fra de gemte timestamps i stedet for at
  blive glemt eller nulstillet.
