# 🎄 MM Christmas Event System (v2.0.0 — full rework)

Premium Christmas Event System for FiveM with ESX, QBCore, vRP and Standalone
support, built on **ox_lib**, **ox_target** and **ox_inventory**.

This version is a complete architectural rework of the original resource:
every layer (client → NUI → server → database → inventory → framework) was
audited and rebuilt where it was broken, insecure, or unfinished. Every
existing feature is preserved — several were actually fixed for the first
time, since they had never worked correctly (see "Problems found" below).

---

## 1. Analysis — what the original resource did

The original `MM-christmasevent` (`mm-christmas`) was a single-file
client/server FiveM event script: players earned XP and "Christmas Coins"
by decorating static Christmas trees, building snowmen, finding gifts,
completing daily/weekly tasks, and driving/running around the map. Coins
could be spent in an in-NUI shop, and progress unlocked per-level rewards
and a leaderboard. A `christmas_box` item could be opened for a random
reward, and admins could send a specific player a personal gift with a GPS
route to it. All of it was exposed through a single NUI menu opened with
`/christmas` or `F5`.

## 2. Problems found

A full line-by-line audit of `client/main.lua`, `server/main.lua`,
`shared/functions.lua`, `config.lua`, `html/*` and the SQL install script
turned up the following. Every one of these is fixed in this rework
(details in "Security fixes" and the file-by-file changelog below).

**Critical / directly exploitable:**
- `mm-christmas:server:giveXP` accepted a raw `amount` straight from the
  client with **zero validation**, and was never actually called by any
  legitimate client code — a pure, dead attack surface. Any player could
  trigger it manually (`TriggerServerEvent('mm-christmas:server:giveXP',
  999999999)`) for unlimited XP, coins, and task progress. **Removed.**
- `buildSnowman` had **no server-side validation whatsoever** — no bounds
  check, no distance check, no "is this location already taken" check
  (that only existed as a client-local prop check other players never saw).
  Spamming the event with any argument farmed unlimited XP/coins.
- `decorateTree` only checked "have I already used this exact index" —
  it never validated the index was a real tree, and never checked the
  player's distance to it. Sending incrementing fake indices
  (`1, 2, 3, 4, ...`) farmed unlimited rewards with no proximity needed.
- `openBox` never checked or removed a `christmas_box` item from the
  player's inventory at all. Spamming the event granted unlimited box
  rewards for free.
- `giftFound` accepted a client-chosen `isPersonal` flag and an arbitrary
  `giftId` string for the "regular" (non-personal) path, with **no
  validation of any kind** — trivially farmable for unlimited "gifts
  found" credit and task progress.
- `trackDistance` accepted raw `driven`/`run` deltas with no upper bound —
  a client could report `500000` (km) per call and have it accepted as-is.
- The NUI's "Hent" (claim) button on the Level tab called
  `nuiFetch('claimLevelReward', ...)`, but **no matching
  `RegisterNUICallback('claimLevelReward', ...)` existed in the client** —
  the feature was completely dead; level rewards could never be claimed
  from the UI at all, even though the server-side logic for it existed.
- Level rewards were **also** auto-granted the moment a player leveled up
  (inside the XP/level-up loop) — meaning if the claim button had worked,
  a player could have received the same level's reward twice (once
  automatically, once via claiming). A genuine duplicate-reward bug.
- `data.claimed_rewards` was read and written by `server/main.lua`, but
  the shipped `install.sql` **never defined that column** — every single
  `SavePlayer()` call would have failed against a real database with an
  "unknown column" error.
- Shop purchases deducted coins and incremented the purchase counter
  **before** confirming the item was actually given — if the item didn't
  exist in `ox_inventory`'s `items.lua`, the player paid and got nothing,
  with no refund.
- Currency existed in **two places that could drift**: a `data.coins`
  integer column in the database, incremented independently of the
  `christmas_coin` item that was *also* given directly via
  `ox_inventory:AddItem`. Any ordinary trade/drop/sale of that item through
  normal inventory UI would desync the two permanently.
- `Config.Framework = 'vrp'` was accepted by config but the framework
  detection thread never actually checked for vRP — it silently fell back
  to `standalone`, even though `FW.GetIdentifier` had vRP-specific code
  that could never be reached.

**Design / robustness issues:**
- Framework detection ran inside an un-awaited `CreateThread`, with no
  guarantee it had finished before the first `playerJoin` event could fire.
- No rate limiting anywhere — every event could be spammed/double-clicked.
- `ActiveGifts` was a global (non-`local`) table.
- Personal admin gifts never expired, and their `AddBlipForCoord` blips
  were never explicitly cleaned up on resource stop (FiveM does **not**
  auto-remove blips when a resource stops, unlike some other entity types).
- The "regular gift" feature implied by the daily/weekly "find gifts" tasks
  and the "Gaver" tab was **never actually implemented** on the client —
  there was no code anywhere that spawned a findable, non-personal gift.
- `client/main.lua` defined an unused `NuiFetch` Lua function that made no
  sense in FiveM's NUI model (Lua→NUI communication goes through
  `SendNUIMessage`, not `fetch`) — dead code.
- The UI had zero settings (no theme, transparency, resize, sound,
  animation, or reduced-motion controls), no loading screen, and no
  profile-avatar support.

---

## 3. New file structure

```
MM-christmasevent/
├── fxmanifest.lua
├── config.lua
├── install.sql
├── README.md
├── shared/
│   └── functions.lua
├── client/
│   └── main.lua
├── server/
│   ├── framework.lua     -- ESX/QBCore/vRP/Standalone abstraction
│   ├── inventory.lua     -- ox_inventory wrapper (existence/failure aware)
│   ├── currency.lua      -- single source-of-truth coin abstraction
│   ├── database.lua      -- load/save/build-client-data + auto-migration
│   ├── ratelimit.lua     -- generic per-player/per-event cooldown
│   ├── avatar.lua        -- Steam/Discord avatar resolution (server-only)
│   └── main.lua          -- all secured game event handlers
├── locales/
│   ├── da.lua
│   └── en.lua
└── html/
    ├── index.html
    ├── css/
    │   ├── base.css      -- layout/components (theme-agnostic)
    │   └── themes.css    -- the 4 themes, as CSS custom properties
    ├── js/
    │   ├── settings.js   -- Settings/Toast/Loading/SoundFX (localStorage)
    │   ├── api.js         -- central NUI fetch + error handling
    │   └── app.js          -- rendering / state / event wiring
    └── assets/
        └── default-avatar.svg
```

---

## 4. Installation

1. **New installation:** run `install.sql`.
   **Existing installation:** do nothing — `server/database.lua` detects
   and adds the two missing columns (`claimed_rewards`,
   `world_gifts_found`) automatically the first time the resource starts,
   without touching any existing rows. You'll see a console line like:
   `[mm-christmas] Database migreret - tilføjede kolonne(r): claimed_rewards, world_gifts_found`.
2. Place the `MM-christmasevent` folder in your `resources/` directory.
3. Add to `server.cfg`, **after** `ox_lib`, `ox_target` and `oxmysql`:
   ```
   ensure ox_lib
   ensure ox_target
   ensure oxmysql
   ensure MM-christmasevent
   ```
4. Make sure the following items exist in your `ox_inventory` `items.lua`:
   `christmas_coin`, `christmas_box`, `santahat`, `snowglobe`, `candy_cane`,
   `xmas_socks`, `reindeer_mask`, `elf_suit`, `wood_box`, `goldbar`, `glass`,
   `weapon_candycane` (weapon items are registered differently — check your
   inventory's weapon-item docs if you keep this shop entry).
5. Review `config.lua` (see below) — in particular `Config.ProfileImage`
   if you want real Steam/Discord avatars.

## 5. Configuration

Everything lives in `config.lua`. New sections added in this rework:

- `Config.Distance` — server-side sanity limits for `trackDistance`
  (`MaxDrivenPerReport`, `MaxRunPerReport`, `ReportInterval`).
- `Config.InteractionRadius` — how close (meters) a player must be to a
  tree/snowman/gift location for the server to accept the action.
- `Config.RateLimits` — per-event cooldown (ms) per player.
- `Config.ProfileImage` — `provider` (`'auto'|'discord'|'steam'|'none'`),
  `cacheTime` (seconds), and `steamApiKey`/`discordBotToken`. **These keys
  are read only by `server/avatar.lua` and are never sent to the
  client/NUI** — only the resolved public avatar URL is.
- `Config.UI` — `MinWidth`/`MinHeight`/`MaxWidth`/`MaxHeight` (resize
  bounds), `LoadingDuration` (ms, `0` disables the loading screen),
  `DefaultTheme` (`'snow'|'santa'|'trees'|'reindeer'`), and
  `EnableAnimations`/`EnableSnow`/`EnableSounds` (only applied the *first*
  time a player opens the UI — after that, their own Settings tab choices,
  stored in `localStorage`, always win).
- `Config.WorldGiftsEnabled` / `Config.WorldGiftRewards` — the newly
  completed "find a gift anywhere" feature (see below).
- `Config.SnowmanDespawnTime` / `Config.PersonalGiftExpiry` — previously
  hardcoded magic numbers, now configurable.

Everything else (level rewards, shop items, box rewards, tree/snowman/gift
locations, tasks, animations, admin groups) is unchanged in shape from the
original config, so existing customizations carry over directly.

### The "world gifts" feature (newly completed)

The original UI, locale strings, and daily/weekly tasks all referenced
finding "gifts" as a general activity distinct from admin-sent personal
gifts — but no code ever spawned a findable gift anywhere. This rework
implements it: every location in `Config.GiftLocations` (the same pool
already used for personal gifts) doubles as a discoverable world gift.
Each player can find and open each location once (tracked server-side in
the new `world_gifts_found` column, exactly like `trees_done`). Set
`Config.WorldGiftsEnabled = false` to turn this off if you'd rather keep
gift-finding purely admin-driven.

---

## 6. Security fixes (server is now fully authoritative)

- **Removed** the dead, unvalidated `giveXP` event entirely — there is no
  longer any event that accepts a raw reward amount from the client.
  XP/coins only ever come from fixed `Config` values inside server-only
  functions.
- **`decorateTree`** now validates the index is within
  `Config.Trees` bounds and that the player's server-side position
  (`GetEntityCoords(GetPlayerPed(src))`) is within `Config.InteractionRadius`
  of that tree's real coordinates, in addition to the existing per-player
  "already decorated" check.
- **`buildSnowman`** is now fully server-authoritative: bounds-checked,
  distance-checked, and a location is tracked as "taken" server-side
  (`ActiveSnowmen[locIndex]`) for **every** player, not just the builder's
  own client — a second player can no longer build at the same spot
  seconds later just because their own client never saw the first prop.
  The server also broadcasts the build to all clients so everyone actually
  sees the resulting snowman, not just the builder (previously the prop
  was a local, non-networked object visible only to the builder).
- **`openBox`** now genuinely requires and removes 1 `Config.ChristmasBoxItem`
  from the player's inventory before rolling a reward. If the removal
  fails, no reward is given.
- **`giftFound`** (personal gifts) validates the gift ID actually belongs
  to that player via server-tracked `ActiveGifts`, exactly as before, but
  the dead/unvalidated "regular gift" path (arbitrary `giftId` +
  `isPersonal=false`) was removed and replaced by the properly validated
  `worldGiftFound` event (bounds + distance + per-player dedup).
- **`trackDistance`** clamps every reported delta to
  `Config.Distance.MaxDrivenPerReport` / `MaxRunPerReport` instead of
  accepting it raw.
- **Shop purchases are now atomic with rollback:** currency is deducted,
  then the item is given; if giving the item fails (missing from
  `items.lua`, full inventory, etc.), the coins are refunded, the purchase
  counter is **not** incremented, and the player is notified. Same pattern
  for `openBox`'s item-type rewards (the box itself is refunded on
  failure).
- **Currency has one source of truth**: `Currency.Get/Add/Remove/Has`
  (`server/currency.lua`) always read/write the actual
  `Config.CoinItem` count in `ox_inventory`. The `coins` DB column is now
  purely a read-only cache refreshed from that live count right before
  every save, used only so the leaderboard can show offline players'
  balances — it is never consulted to decide whether a purchase is
  affordable.
- **Level rewards can only be granted once, ever**, exclusively through
  `claimLevelReward` (now correctly wired up from the NUI — see below).
  The automatic double-grant on level-up was removed.
- **Rate limiting** (`server/ratelimit.lua`) is applied to every mutating
  event (shop, box, tree, snowman, gifts, distance, level claim,
  leaderboard, avatar, open UI) — generous enough not to affect normal
  play, tight enough to stop spam/double-click/event-replay.
- **`vRP` framework support** now actually gets selected during detection
  (best-effort — see the note in `server/framework.lua`; vRP forks vary,
  and this could not be tested against a live vRP server).
- **Steam/Discord API credentials never reach the client** — only the
  resolved avatar URL does (`server/avatar.lua`).
- Fixed the missing `claimed_rewards` column (see "Database" above),
  which would otherwise have made every `SavePlayer()` call error out
  against a real MySQL/MariaDB server.

## 7. NUI rework

- **Loading screen** on open (🎄 / progress bar / configurable duration).
- **4 themes** (Christmas Snow, Santa, Christmas Trees, Reindeer),
  implemented as pure CSS custom-property sets in `themes.css` — adding a
  5th theme later (Halloween, Valentine, ...) means adding one
  `[data-theme="..."]` block and one `THEME_LIST` entry, nothing else.
  Motifs are CSS/Unicode-glyph based (no bitmap art assets), so there is
  no dependency on any external image host and nothing that can go
  missing.
- **Settings tab**: theme picker, transparency slider, UI size slider,
  animations/snow/sounds/reduced-motion toggles — all persisted in
  `localStorage` and re-applied instantly (transparency/size are plain CSS
  custom properties, so they never distort layout or aspect ratio).
- **Profile avatar**: sidebar + profile tab request
  `mm-christmas:server:getProfileImage` on open; a failed/absent avatar
  falls back to the local `default-avatar.svg` (never breaks the UI).
- **Central error handling** (`api.js` + the toast banner in `index.html`):
  a failed NUI fetch shows a toast instead of hanging silently.
- **Shop UX states**: afford/not-afford/maxed messaging, live coin/purchase
  updates, and a purchase-success pulse animation on the bought card.
- Reduced-motion is honored both via an explicit Settings toggle and the
  OS-level `prefers-reduced-motion` media query.
- All inline styles/hardcoded colors were replaced with the `--t-*` theme
  variable contract so no component needs theme-specific code.

---

## 8. Testing report

Per the instructions, this section is deliberately explicit about what was
**actually run** versus what could only be reviewed statically — there is
no live FiveM/FXServer, database, or game client available in this
environment.

**Physically executed (automated Lua test harness, mocking
oxmysql/ox_inventory/FiveM natives) — `28/28 passed`:**
- `giveXP` event confirmed removed.
- `decorateTree`: out-of-bounds index rejected, too-far-away rejected,
  valid in-range decoration succeeds and grants coins via the real
  inventory path, spamming 49 fake indices while out of range grants
  nothing.
- `buildSnowman`: a second player attempting the same location right after
  the first build is rejected (server-tracked, not client-local); the
  build broadcasts to all clients; an out-of-bounds index is rejected.
- `openBox`: opening with zero boxes owned grants nothing; a valid box is
  actually consumed from inventory; a forced item-give failure refunds the
  box.
- Shop: a forced item-give failure refunds the coins and does not
  increment the purchase counter; the purchase limit is enforced exactly;
  insufficient coins are rejected.
- `trackDistance`: a fabricated 500,000 km report is clamped to the
  configured per-report maximum.
- `claimLevelReward`: rejected before the level is reached; claiming the
  same level twice only registers once.
- Rate limiting: an immediate second `openBox` call (same tick) is
  blocked.
- Currency: `Currency.Get` reflects the live inventory count directly, and
  correctly follows an externally-changed inventory balance (proving there
  is no separate stale counter).
- Database migration: starting against a schema missing
  `claimed_rewards`/`world_gifts_found` adds them automatically without
  the server erroring, and `LoadPlayer` fills in safe defaults either way.

All Lua files pass `lua5.4 loadfile()` syntax checks; all JS files pass
`node --check`.

**[NOT PHYSICALLY TESTED]** — could not be exercised without a live
FXServer, MySQL/MariaDB instance, ox_inventory/ox_target install, and a
connected game client:
- The NUI itself in an actual game overlay (loading screen timing, theme
  switching, resize/transparency sliders, animations, ESC/close, avatar
  `<img>` loading from real Steam/Discord CDN URLs).
- Steam/Discord avatar resolution against real API keys/bot tokens
  (the HTTP/JSON logic in `server/avatar.lua` was reviewed carefully but
  not run against the live Steam Web API or Discord API).
- ox_target zone/entity interactions in-game (tree/snowman/gift prop
  placement, ground-snapping, `PlaceObjectOnGroundProperly`).
- ESX/QBCore/vRP framework integration against real running instances of
  those frameworks (the ESX/QBCore code paths mirror the original,
  unmodified logic; the vRP path is best-effort and explicitly flagged as
  unverified in `server/framework.lua`, since vRP forks are not
  API-compatible with each other and none was available to test against).
- Resource restart/hot-reload behavior in a live server process.
- Animation/anim-dict loading (`lib.requestAnimDict`, `TaskPlayAnim`) and
  particle effects, which require a running game client.

## 9. Changed / added files

| File | Status |
|---|---|
| `config.lua` | Rewritten — new sections added, all original values preserved |
| `shared/functions.lua` | Extended (added `Clamp`/`IsInteger`/`ToPositiveInt`/`Warn`) |
| `fxmanifest.lua` | Updated file list, version bump |
| `install.sql` | Rewritten — adds the two missing columns + indexes for new installs |
| `client/main.lua` | Rewritten |
| `server/main.lua` | Rewritten |
| `server/framework.lua` | **New** (split out of the old `server/main.lua`) |
| `server/inventory.lua` | **New** |
| `server/currency.lua` | **New** |
| `server/database.lua` | **New** (includes the auto-migration runner) |
| `server/ratelimit.lua` | **New** |
| `server/avatar.lua` | **New** |
| `locales/da.lua`, `locales/en.lua` | Extended with new keys |
| `html/index.html` | Rewritten |
| `html/css/base.css`, `html/css/themes.css` | **New** (replaces the old single `style.css`) |
| `html/js/app.js`, `html/js/api.js`, `html/js/settings.js` | **New** (replaces the old single `script.js`) |
| `html/assets/default-avatar.svg` | **New** |

## 10. Migration from the previous version

- **Database**: nothing to do — see "Installation" above, it migrates
  itself on first start.
- **Old `install.sql`** in your previous copy is superseded by this one;
  you don't need to run it, it's kept only as the fresh-install baseline.
- **Event/callback names**: unchanged (`mm-christmas:server:*` /
  `mm-christmas:client:*`), except:
  - `mm-christmas:server:giveXP` no longer exists (it was dead/exploitable
    and nothing legitimate called it).
  - `mm-christmas:server:giftFound` no longer takes an `isPersonal`
    argument (personal vs. world gifts are now two separate, properly
    validated events: `giftFound` for personal, `worldGiftFound` for
    world gifts).
- **NUI files**: `html/style.css` and `html/script.js` are replaced by
  `html/css/{base,themes}.css` and `html/js/{settings,api,app}.js` — if
  you had custom NUI edits, they'll need to be re-applied to the new
  files.
- **Config**: every original key keeps the same name and default value;
  only new keys were added (see "Configuration" above), so a previous
  `config.lua` with custom values can be diffed against this one and
  merged by hand if you don't want to lose local tweaks.
