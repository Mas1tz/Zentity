# MPvp-idmenu

Rent ID + display-navn "peek" system til MPvp. **PAGE DOWN** toggler
det til/fra. Ingen menu, ingen NUI, ingen server-events, ingen
notifikationer.

## Visning

Over hver anden aktive spiller (aldrig dig selv):

```
      42
    Masitz
```

Server-ID øverst (mest fremtrædende), display-navn direkte under.
Begge kan slås fra hver for sig (`Config.IDPeek.showId` /
`showName`).

## Config

Alt styres fra `config.lua`'s `Config.IDPeek`-tabel: `enabled`, `key`,
`distance`, `height`/`vehicleHeight`, `showId`/`showName`,
`lineOfSight`, `showDeadPlayers`, `showPlayersInVehicles`,
`cacheInterval`, samt `text`/`background`/`border`/`distanceColors`
for udseendet. Sæt `Config.IDPeek.enabled = false` for at slå hele
systemet fra — så registreres end ikke tasten.

**Om `key`:** konfigureret som `'PAGEDOWN'` (FiveM's keybind-navn) i
stedet for den rå control-id `207`, fordi det bindes via
`RegisterKeyMapping` — det giver ægte 0.00ms idle for selve
tast-aktiveringen (intet polling-loop overhovedet) og lader spilleren
selv rebinde tasten under F8 → Settings → Key Bindings → FiveM.
`'PAGEDOWN'` er præcis den samme fysiske tast som control-id `207`.

## Steam/display-navn

`GetPlayerDisplayName()` i `client/main.lua` er en isoleret, ét-sted
opslags-funktion. FiveM eksponerer intet separat "Steam-navn" til
klienten for ANDRE spilleres vedkommende — `GetPlayerIdentifiers`
(som indeholder `steam:`-identifieren) findes kun server-side.
`GetPlayerName(...)` er derfor den bedste og eneste pålidelige
client-native til formålet, og er i praksis det navn serveren har sat
for spilleren (typisk Steam-navnet ved connect). Kaldet er
`pcall`-beskyttet og falder tilbage til `"Ukendt"` i stedet for at
fejle, hvis et navn af en eller anden grund ikke kan hentes (fx en
spiller midt i en reconnect). Skal I senere bruge et andet/custom
display-navn (fx et RP-karakternavn), er det den ENESTE funktion der
skal ændres.

## Performance

- **Ingen loop kører før PAGE DOWN trykkes.** Tasten er bundet via
  `RegisterKeyMapping`/`RegisterCommand` — intet polling.
- Mens ID-peek er tændt kører ét render-loop (nødvendigt — GTA's
  text/rect-natives holder kun ét frame ad gangen), men den tunge del
  (`GetActivePlayers`/`GetPlayerServerId`/`GetPlayerName`) sker kun
  hvert `Config.IDPeek.cacheInterval` (500 ms som standard) via en
  lille cache — **ikke** hvert frame. Bekræftet i test-suiten: navnet
  hentes ved cache-genopbygning og genbruges uændret på alle
  efterfølgende frames, indtil næste genopbygning.
- Afstand tjekkes som **kvadreret afstand** (ingen `sqrt`) før noget
  som helst andet — LOS-raytrace og tegning sker kun for spillere der
  allerede har bestået distance-tjekket.
- Sluk ID-peek igen (eller stop resourcen): loopet afsluttes selv,
  cachen ryddes, ingen efterladte referencer.

## Fjernet fra den oprindelige resource

Hele `lib.registerMenu`/`lib.showMenu`/`lib.hideMenu`-flowet, den
tilhørende spillerliste (`getPlayers`, `menuOptions`,
`openPlayerMenu`), og notifikationen der advarede nærliggende
spillere om at "nogen peaker i området". `ox_lib` er ikke længere en
dependency — intet i den nye resource bruger det.

## Test

Verificeret med en smoke-test der kører det RIGTIGE `client/main.lua`
gennem flere frames med mockede natives: intet loop starter før
tasten trykkes, selv-ID/-navn vises aldrig, distance/dead/LOS-filtrering
virker hver for sig, en spiller i køretøj vises korrekt med
`vehicleHeight` når `showPlayersInVehicles = true` og ignoreres
fuldstændigt når det er `false`, `GetPlayerName` kaldes kun ved
cache-rebuild (ikke pr. frame), en spiller uden gyldigt navn falder
roligt tilbage til "Ukendt", og loopet/resource-stop rydder korrekt
op. 31/31 assertions bestået.
