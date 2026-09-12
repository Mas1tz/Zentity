# MPvp-radial

Ét ox_lib-radial-hjul til MPvp med præcis 4 funktioner: **Noclip**,
**Revive**, **Lobby**, **Report**. Intet andet.

## Struktur

```
MPvp-radial/
├── fxmanifest.lua
├── config.lua
├── client/main.lua   -- radial-registrering, noclip, revive, lobby, report-UI
└── server/main.lua   -- KUN report-validering (det eneste der har server-tillid)
```

## Hvad blev fjernet

- Den nedlagte "Funktioner"-undermenu — de 4 punkter ligger nu direkte
  på hjulet.
- Noclip via `ExecuteCommand('txAdmin:menu:noClip')` — erstattet af en
  rigtig, selvstændig noclip-implementation.
- `ExecuteCommand('report')` mod en ekstern, ikke-vedhæftet resource —
  erstattet af et selvstændigt, server-valideret report-flow.
- `ox_target` og `es_extended` som dependencies — ingen af dem blev
  reelt brugt nogen steder i den oprindelige kode.

## Hvad blev bevaret

- Selve ox_lib-radial-mekanismen (`lib.addRadialItem`) — uændret måde
  at åbne menuen på.
- Revive-integrationen mod `esx_ambulancejob:revive` — samme event som
  før, nu bare bag et dødstjek + cooldown.
- De tre eksisterende ikoner (`jet-fighter-up`, `heartbeat`,
  `clipboard-question`) genbruges for Noclip/Revive/Report; kun Lobby
  fik et nyt (`door-open`), da funktionen ikke fandtes før.

## Lobby — ingen eksisterende integration fundet

Den vedhæftede resource indeholdt intet lobby-event, -export eller
-command overhovedet. `Config.Lobby` implementerer derfor en simpel,
konfigurerbar teleport som standard, plus et export-hook
(`exportResource`/`exportName`) I kan pege på jeres eget lobby-system,
hvis I har ét jeg ikke havde adgang til at analysere.

## Security-gennemgang (§48)

Kun ét server-event findes: `mpvp_radial:report`. Alt andet (noclip,
revive, lobby) er bevidst rent client-side og selv-kun — ingen af dem
kan bruges til at påvirke andre spillere eller give en uretmæssig
fordel serveren behøver at validere.

- **Kan en exploiter få revive uden grund?** Nej — der er nu et
  `IsEntityDead`-tjek; er man ikke død, sker der intet. Cooldown
  forhindrer spam. (Bevidst client-side: revive rører aldrig andre
  spillere eller server-state, kun ens eget ESX-karakter-flow.)
- **Kan lobby misbruges?** Nej — den flytter kun ens egen ped til et
  fast, config-defineret punkt (eller kalder et export I selv
  kontrollerer). Ingen server-tillid nødvendig.
- **Kan report spammes?** Nej — server-side cooldown
  (`Config.Report.cooldown`), pr. spiller, uafhængig af andre.
- **Kan report sende falske/injicerede data?** Nej — `targetId`
  gen-valideres som et ikke-negativt heltal og skal matche en reelt
  online spiller (`GetPlayerName`); `reason` gen-tjekkes som en streng,
  kontroltegn fjernes, og den klippes HÅRDT til `maxReasonLength`
  server-side — klientens egen min/max i `inputDialog` er ren UX og
  betyder intet for hvad serveren rent faktisk accepterer.
- **Kan man kalde funktioner der ikke burde eksistere?** Nej — der er
  ingen andre client-triggerbare server-events end `mpvp_radial:report`.

Verificeret med en mock-test-harness der kører de **rigtige**
`config.lua`/`server/main.lua`-filer under `lua5.4`: 21 assertions,
bl.a. selv-report blokeret, offline-ID afvist, ugyldige ID-typer
(streng/negativ/decimal/tabel/nil) afvist uden crash, en 10.000-tegns
årsag klippet ned i stedet for at fejle, et ikke-string "reason"
(tabel) håndteret roligt, og cooldown der er uafhængig pr. spiller.

## Performance-gennemgang (§49)

Kun ét loop findes i hele resourcen: noclip-bevægelsesloopet, og det
**findes kun mens noclip rent faktisk er aktivt** — `while true do
Wait(0) end` findes ingen steder.

| Loop | Hvornår | Wait | Hvorfor ikke event-baseret |
|---|---|---|---|
| Noclip-bevægelse | Kun mens `noclipActive == true` | `Wait(0)` | Kræver frame-for-frame input-læsning (WASD/SPACE/CTRL/SHIFT/RMB) og position-opdatering for at føles jævnt — kan pr. definition ikke være event-drevet. Afsluttes selv når `noclipActive` sættes til `false`. |

Alt andet — radial-registrering, revive, lobby, report — er 100%
event-drevet (`onSelect`-callbacks, `RegisterNetEvent`,
`onResourceStop`, `playerDropped`). Når radial-hjulet er lukket og
noclip er slukket, kører intet i denne resource overhovedet: 0.00ms
idle.

## Noclip-detaljer

- Bevægelse er kamera-relativ og framerate-uafhængig
  (`GetFrameTime()`), ikke hardcoded pr.-frame-forskydning.
- **W/A/S/D** flytter, **SPACE** op, **VENSTRE CTRL** ned, **VENSTRE
  SHIFT** = `fastSpeed`, **HØJRE MUSEKNAP** = `slowSpeed` (præcision).
- Sidder man i et køretøj, noclippes køretøjet i stedet for pedet —
  skifter man ind/ud af et køretøj midt i noclip, håndteres det uden
  fejl.
- Et lille, diskret badge ("NOCLIP") tegnes nederst på skærmen mens det
  er aktivt — native `DrawRect`/`DrawText`, ingen NUI, farverne kommer
  fra `Config.UI`.
- Ved `onResourceStop` og ved almindelig deaktivering gendannes
  collision/invincibility/freeze altid — ingen fastlåst spiller,
  uanset hvordan resourcen stoppes.

**Vigtigt om `Config.UI`:** Radial-hjulet, `lib.notify` og
`lib.inputDialog` er alle ox_lib's egne, server-fælles UI-komponenter
— deres farver styres af ox_lib's eget tema, ikke af denne resources
config. `Config.UI` bruges udelukkende til det lille native
noclip-status-badge, hvor det faktisk har effekt.
