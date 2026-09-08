# Masitz-InventoryLogs

Enterprise-grade inventory audit logging for **ESX Legacy + ox_inventory + ox_lib**.

A complete rework of the `ox_inventory_logs` concept: instead of a handful of
hardcoded Discord messages for drop/pickup/give/stash, this resource hooks
into every reliably-loggable ox_inventory action, classifies it through one
central dispatcher, and ships it to Discord and/or a database with
duplicate protection, rate limiting, and zero impact on ox_inventory itself
if Discord or MySQL misbehave.

This is a passive, server-only audit layer. It does not modify
`ox_inventory`, `ox_lib`, ESX, or any other resource, does not change how
items move, and exposes no client-side code, events, or callbacks - there is
nothing for a client to spoof.

---

## 1. Analysis summary

The reference project (`itIsMaku/ox_inventory_logs`, archived) hooks
`swapItems` and dispatches purely on `(fromType, toType)` pairs. That
approach predates/ignores the `action` field ox_inventory now attaches to
every `swapItems` payload, so it cannot distinguish a stack split from a
slot move from a genuine swap, only covers 4 flows, and has no dedup, no
database option, no rate limiting, and no restart safety.

This rework is built directly from `overextended/ox_inventory`'s current
source (verified against `fxmanifest.lua` version **2.47.9**):
`modules/hooks/server.lua`, `modules/inventory/server.lua`,
`modules/shops/server.lua`, `modules/crafting/server.lua`,
`modules/bridge/esx/server.lua`, and `server.lua`.

Key findings that shaped the architecture:

- **Only 7 hook points exist** in this version of ox_inventory:
  `openInventory`, `usingItem`, `swapItems`, `buyItem`, `openShop`,
  `craftItem`, `createItem`. No others were invented or assumed.
- **`swapItems` is the single hook behind give / drop / pickup / stash /
  trunk / glovebox / police evidence / dumpster / container / stack-split /
  stack-merge / slot-move.** Every player-driven item movement goes through
  it, discriminated by the payload's `action` field (`move | swap | stack |
  give`) plus `fromType`/`toType` - which ox_inventory resolves for us, so
  inventory-type detection never has to guess.
- **Two real API quirks** that would silently break a naive implementation:
  1. On a ground drop, `payload.toInventory` is the literal placeholder
     string `"newdrop"` - the real drop id is `payload.dropId`.
  2. `payload.toSlot` is a full slot table when the destination slot already
     holds an item, but a bare slot number when it's empty.
  Both are handled explicitly (`server/hooks.lua` `classifySwap` /
  `Utils.NormalizeSlotField`).
- **Vehicle plates aren't included in the payload**, but ox_inventory ids
  trunk/glovebox inventories as `"trunk"..plate` / `"glove"..plate`
  (verified in `loadInventoryData`), so the plate is *derived* from the
  inventory id, never guessed or looked up separately.
- **No hook exists for `AddItem` / `RemoveItem` / `SetItem`**, which means
  the server console's `/additem`, `/removeitem`, `/setitem` commands and
  any other resource calling `exports.ox_inventory:AddItem` directly are
  **not covered**. `createItem` technically fires there too, but it *also*
  fires on every buy/craft/give/drop-split, so hooking it generically would
  duplicate everything already logged elsewhere. This is a genuine gap in
  ox_inventory's current hook API, not an oversight - see [Known
  limitations](#7-known-limitations).
- **Restart safety is already solved by ox_inventory itself**:
  `registerHook` ties every hook to `GetInvokingResource()`, and
  ox_inventory's own `AddEventHandler('onResourceStop', removeResourceHooks)`
  strips a resource's hooks the moment it stops - verified in
  `modules/hooks/server.lua`. No manual bookkeeping is required to avoid
  duplicate hooks after a `restart Masitz-InventoryLogs`; we still call
  `exports.ox_inventory:removeHooks()` defensively on our own stop.
- **Hooks run synchronously inside ox_inventory's own `pcall` and block the
  calling function until they return.** Every handler in this resource
  therefore only does cheap, synchronous work (ESX lookups, natives, table
  lookups) and hands off to a plain table insert (`Logger.Log`); all
  network/database I/O happens later on independent threads.
- **A real, unavoidable edge case**: our hook fires *before* ox_inventory's
  final commit. A few lines later, in rare race conditions (e.g. a party
  inventory disappearing mid-transaction), ox_inventory can still abort the
  action with no callback informing us. There is no post-commit hook for
  `swapItems` in this version of ox_inventory to work around this. It is
  documented, not hidden.

---

## 2. Architecture

```
ox_inventory hook fires (sync, blocking)
        │
        ▼
server/hooks.lua      -- classifies the payload into an action + builds a
                          normalized entry (player, item, from, to, ...)
        │  (cheap table insert, returns immediately)
        ▼
server/logger.lua     -- LogInventoryAction(entry): config gate → dedup
                          fingerprint → forwards to Discord and/or Database
        │
        ├──────────────► server/discord.lua
        │                  builds the embed, resolves the webhook for this
        │                  action's category, enqueues per-webhook
        │                  (own CreateThread, rate-limited, 429-aware,
        │                   retries with backoff, overflow → summary/drop)
        │
        └──────────────► server/database.lua
                           async oxmysql insert (only if Config.Storage
                           includes 'database'); separate thread sweeps
                           old rows per Config.Database.retentionDays
```

Instead of ~20 near-identical `logDrop()` / `logGive()` / `logStash()`
functions, every hook handler ends with one call:

```lua
Logger.Log({
    action = 'stash_deposit',
    player = Framework.GetPlayerInfo(source),
    item = { name = ..., label = ..., amount = ... },
    from = { id = ..., type = ..., slot = ... },
    to = { id = ..., type = ..., slot = ... },
    stash = 'police_evidence',
    metadata = ...,
})
```

`Logger.Log` (aliased globally as `LogInventoryAction`) is the only place
that decides whether an action is enabled, deduplicated, and where it goes.

### Files

```
Masitz-InventoryLogs/
├── fxmanifest.lua
├── config.lua
├── masitz-inventorylogs.sql
├── README.md
└── server/
    ├── utils.lua      -- pure helpers: type labels, plate/slot parsing, metadata sanitizing
    ├── framework.lua  -- defensive ESX Legacy bridge (player/job/identifier lookups)
    ├── discord.lua    -- embeds, webhook routing, rate-limited async queue
    ├── database.lua   -- optional oxmysql storage + retention cleanup
    ├── logger.lua     -- central LogInventoryAction dispatcher + dedup cache
    ├── hooks.lua       -- registers the 6 hooks we use, classifies swapItems
    └── main.lua        -- startup checks, ready banner, defensive cleanup
```

There is deliberately **no client script** and **no shared/ folder** - every
signal this resource needs is available server-side through ox_inventory's
hooks and ESX's server objects.

---

## 3. Action matrix

Every action this resource can produce, whether it's backed by an official
hook, and the config key that gates it.

| Action | Possible? | Method | Default |
|---|---|---|---|
| Give item (player → player) | YES | `swapItems` hook, `action == 'give'` | ON |
| Drop item to ground | YES | `swapItems` hook, `toType == 'drop'` (real id from `payload.dropId`) | ON |
| Pickup item from ground | YES | `swapItems` hook, `fromType == 'drop'` | ON |
| Stash deposit | YES | `swapItems` hook, `toType == 'stash'` | ON |
| Stash withdraw | YES | `swapItems` hook, `fromType == 'stash'` | ON |
| Trunk deposit / withdraw | YES | `swapItems` hook, `type == 'trunk'`; plate derived from inventory id | ON |
| Glovebox deposit / withdraw | YES | `swapItems` hook, `type == 'glovebox'`; plate derived from inventory id | ON |
| Police evidence deposit / withdraw | YES | `swapItems` hook, `type == 'policeevidence'` | ON |
| Dumpster deposit / retrieve | YES | `swapItems` hook, `type == 'dumpster'` | ON |
| Container store / retrieve | YES | `swapItems` hook, `type == 'container'` | ON |
| Item swap (two occupied slots) | YES | `swapItems` hook, `action == 'swap'` | ON |
| Stack merge | YES | `swapItems` hook, `action == 'stack'` | OFF (noisy) |
| Stack split | YES | `swapItems` hook, `action=='move'` + same inventory + `count < fromSlot.count` | OFF (noisy) |
| Move item between slots (same inventory) | YES | `swapItems` hook, `action=='move'` + same inventory + full count | OFF (noisy) |
| Generic player↔player inventory transfer (trade UIs etc.) | YES | `swapItems` hook, `fromType==toType=='player'`, different inventories | ON |
| Shop purchase | YES | `buyItem` hook | ON |
| Shop opened (menu, not a purchase) | YES | `openShop` hook | OFF (noisy) |
| Crafting | YES* | `craftItem` hook (fires at recipe-validation time, see limitations) | ON |
| Item used/consumed | YES | `usingItem` hook | OFF (very noisy) |
| Stash/trunk/glovebox/container/evidence **opened** (access, not movement) | YES | `openInventory` hook | OFF (very noisy) |
| Admin `/additem`, `/removeitem`, `/setitem` console commands | **NO** | No dedicated hook exists in ox_inventory 2.47.9 (see limitations) | n/a |
| Direct `exports.ox_inventory:AddItem/RemoveItem/SetItem` calls by other resources | **NO** | Same as above | n/a |
| Weapon component attach/detach, ammo load | Partial | Goes through `swapItems`/`usingItem` like any other item movement - not specially distinguished, logged as the underlying action | n/a |

Everything marked YES is logged through real, verified ox_inventory hooks.
Nothing in this resource invents data, guesses an inventory type, or
fabricates a hook that doesn't exist.

---

## 4. Installation

1. Copy `Masitz-InventoryLogs/` into your server's resources folder.
2. Ensure load order: `ox_lib`, `oxmysql` (if using database storage),
   `es_extended`, `ox_inventory`, then `Masitz-InventoryLogs`.
   ```cfg
   ensure ox_lib
   ensure oxmysql
   ensure es_extended
   ensure ox_inventory
   ensure Masitz-InventoryLogs
   ```
3. Open `config.lua` and set `Config.Storage` (`'discord'`, `'database'`, or
   `'both'`) and fill in the webhook URLs you want under `Config.Webhooks`.
4. If using database storage, the table is created automatically on first
   start (`CREATE TABLE IF NOT EXISTS`). `masitz-inventorylogs.sql` is
   provided for manual import if you'd rather run it yourself.
5. Restart the resource. With `Config.Debug = true` you'll see a ready
   banner and hook registration confirmation in the console.

### Dependencies

- **Required**: `es_extended` (ESX Legacy), `ox_lib`, `ox_inventory`.
- **Optional**: `oxmysql` - only needed if `Config.Storage` is `'database'`
  or `'both'`. In `'discord'`-only mode (the default), oxmysql does not
  need to be installed at all.

---

## 5. Configuration reference

See `config.lua` - every setting is commented inline. Highlights:

- `Config.Storage` - `'discord' | 'database' | 'both'`.
- `Config.Webhooks` - one URL per category (`player`, `drop`, `stash`,
  `vehicle`, `shop`, `crafting`, `admin`, `default`). Empty falls back to
  `default`; if `default` is also empty, that category is silently skipped.
- `Config.ActionWebhooks` - remaps any action to any webhook category
  without touching code.
- `Config.Logging` - per-action on/off switches. High-volume, low-audit-value
  actions (stack merges, same-inventory moves, item usage, inventory
  opens, shop menu opens) are **off by default**.
- `Config.Discord.RateLimit` / `Config.Discord.Queue` - request spacing,
  retry/backoff behaviour on HTTP 429, and overflow handling
  (`'summary'` collapses excess entries into one "+N more actions" embed,
  `'drop'` silently discards them) when more than `maxSize` messages are
  queued for one webhook.
- `Config.Database.retentionDays` - automatic cleanup; `0` keeps logs
  forever.
- `Config.DedupWindowMs` - short-lived duplicate-action fingerprint window.
- `Config.PlayerInfo` / `Config.Metadata` - control how much detail (job,
  identifier, coordinates, raw item metadata) ends up in each log entry.

---

## 6. Testing checklist

All 20 scenarios below were reasoned through against the actual
ox_inventory source and this implementation. `T` = tested against hook
payload shapes taken directly from ox_inventory's source; run these
manually on a live server to confirm end-to-end behaviour for your setup.

| # | Scenario | Expected result |
|---|---|---|
| 1 | Player → Player (give) | `give` logged with both player and target resolved via ESX; webhook category `player` |
| 2 | Player → Drop | `drop` logged with position (`GetEntityCoords` at hook time, matches ox_inventory's own `z - 0.2` drop offset) |
| 3 | Drop → Player | `pickup` logged, source inventory shown as `Ground Drop - drop-XXXXXX` |
| 4 | Player → Stash | `stash_deposit` logged with `stash` id and, if registered via `RegisterStash`, its friendly label |
| 5 | Stash → Player | `stash_withdraw` logged symmetrically |
| 6 | Player → Trunk | `trunk_deposit` logged, plate derived from `trunk<PLATE>` inventory id |
| 7 | Trunk → Player | `trunk_withdraw` logged symmetrically |
| 8 | Player → Glovebox | `glovebox_deposit` logged, plate derived from `glove<PLATE>` inventory id |
| 9 | Glovebox → Player | `glovebox_withdraw` logged symmetrically |
| 10 | Shop purchase | `shop_purchase` logged via `buyItem` hook with price/currency/shop id |
| 11 | Crafting | `craft` logged via `craftItem` hook with recipe + ingredients note (see limitation on timing) |
| 12 | Container (store/retrieve) | `container_store` / `container_retrieve` logged, same `swapItems` pipeline |
| 13 | Stack split | Classified as `split_stack` (`action=='move'`, same inventory, partial count) - off by default, enable `Config.Logging.splitStack` to verify |
| 14 | Stack merge | Classified as `inventory_stack` (`action=='stack'`) - off by default, enable `Config.Logging.inventoryStack` to verify |
| 15 | Move item between slots | Classified as `move_slot` (`action=='move'`, same inventory, full count) - off by default, enable `Config.Logging.moveSlot` to verify |
| 16 | Resource restart while players online | ox_inventory's own `onResourceStop` handler removes all hooks tied to this resource automatically (verified in source); our own `main.lua` also calls `removeHooks()` defensively. No duplicate hooks, no leaked handlers after `restart Masitz-InventoryLogs` |
| 17 | Discord webhook unavailable/down | `PerformHttpRequest` failures/timeouts retry with backoff (`Config.Discord.RateLimit.maxRetries`), then the entry is dropped with a console warning; ox_inventory item movement is completely unaffected since the HTTP call never blocks the hook |
| 18 | 100+ inventory actions in rapid succession | All hooks return instantly (table insert only); the per-webhook queue absorbs the burst and drains at `Config.Discord.RateLimit.minIntervalMs` intervals; once `Queue.maxSize` is hit, further entries collapse into a summary embed instead of growing memory unbounded |
| 19 | Player disconnects mid-action | `Framework.GetPlayerInfo` and `Utils.GetPlayerCoords` are pcall-wrapped and fall back to `'Unknown'`/`nil` rather than throwing; a hook error is caught by `hooks.lua`'s own `runHook` wrapper and logged as a warning instead of silently vanishing or crashing the resource |
| 20 | Invalid/spoofed client data | Not applicable by design: this resource has no client script, no exposed server event, and no callback that accepts logging data from a client. Every field originates from ox_inventory's own server-side hook payload or a server-authoritative ESX/native lookup keyed by the trusted `source` id |

---

## 7. Known limitations

- **No hook for `AddItem`/`RemoveItem`/`SetItem`.** Server console
  `/additem`, `/removeitem`, `/setitem`, and any resource calling those
  exports directly, are not logged. `createItem` fires there but also on
  every buy/craft/give/drop-split, so using it generically would duplicate
  everything else - deliberately not done. If you need this specific
  coverage, it would require a resource-specific wrapper around those
  exports/commands, which is out of scope for a passive hook-based logger.
- **`craftItem` fires before the crafting animation completes.** If a
  player cancels the client-side crafting animation, ingredients are never
  actually consumed, but the hook (and therefore the log entry) already
  fired. ox_inventory does not expose a post-completion hook for crafting
  in this version.
- **A narrow race window on `swapItems`.** Our hook runs before
  ox_inventory's absolute final commit; in rare concurrent-access races
  (e.g. the destination inventory disappearing between hook approval and
  commit) ox_inventory can still abort the action with no callback telling
  us. Not fixable without a hook API change upstream.
- **Weapon serials/components** are logged as part of an item's metadata
  (truncated per `Config.Metadata.maxLength`), not broken out into
  dedicated fields - ox_inventory doesn't distinguish weapon actions from
  regular item actions at the hook level beyond what's in `metadata`.
- **openShop, usingItem, openInventory access, stack merge/split/move are
  off by default** purely due to volume; enabling them is one boolean each
  in `config.lua`.

---

## 8. Performance

- No polling loops (`while true do Wait(0) end`) anywhere in this resource.
  The only background threads are: the Discord dispatcher (only runs while
  its queue is non-empty, `Wait(RateLimit.minIntervalMs)` between sends),
  the dedup-cache sweep (`Wait(30000)`), and the retention cleanup sweep
  (`Wait(cleanupIntervalMinutes * 60000)`).
- Every hook handler does O(1) table work and a handful of already-cached
  ESX/native lookups before returning - no `Wait()` or blocking I/O ever
  happens inside a hook.
- Discord requests and database inserts are fully asynchronous and queued;
  a Discord outage or a burst of 100+ actions cannot slow down or block
  ox_inventory.

## 9. Compatibility

- Built and verified against `ox_inventory` **2.47.9** (current `main`).
  If a future version renames/restructures a hook payload, only
  `server/hooks.lua`'s classification logic needs updating - the rest of
  the pipeline is unaffected.
- ESX Legacy only (`Config` assumes `xPlayer.job`, `xPlayer.identifier`,
  `xPlayer.getName()`). Not tested against QBCore.
- Makes zero changes to `ox_inventory`, `ox_lib`, `es_extended`, or any
  other resource's files.

## 10. Troubleshooting

- **Nothing shows up in Discord**: check `Config.Discord.enabled`,
  `Config.Storage`, and that the relevant webhook (or `Config.Webhooks.default`)
  is actually filled in. Set `Config.Debug = true` and watch the console.
- **"Failed to acquire the ESX shared object"**: `es_extended` isn't
  started yet or isn't ESX Legacy - check your `server.cfg` load order.
- **"Config.Storage requires oxmysql, but the MySQL global is not
  available"**: install/start `oxmysql`, or set `Config.Storage = 'discord'`.
- **Console is noisy**: set `Config.Debug = false` (default) - only real
  warnings (failed hook handlers, dropped Discord messages after repeated
  retries) print regardless of debug state.
