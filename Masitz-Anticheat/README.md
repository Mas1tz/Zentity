# Masitz-Anticheat — anti-nummerplade

Server-authoritative anti-cheat module protecting vehicle plate ownership
against manipulation via mod menus, injected scripts, spoofed events, and
other client-side exploits. Built for ESX Legacy + ox_inventory + oxmysql,
integrating with the existing `owned_vehicles` table from the MM-garage
system (`MMgarage.sql`) — no separate/parallel vehicle-ownership schema.

---

## 1. Security design (read this first)

**Threat model.** The client is assumed compromised at all times: mod menus,
hooked natives, memory edits, stopped resources, forged/replayed events. The
only things ever trusted are: (1) values the server itself reads via a
native call against a networked entity (requires OneSync), (2) rows read
from the database, and (3) the `source` (server ID) FiveM itself assigns to
an event — never any *argument* a client attaches to an event.

**Trusted / untrusted split.**

| Trusted (server-side only) | Untrusted (never trusted as-is) |
|---|---|
| `owned_vehicles` rows (owner/plate) | Any plate string sent by a client |
| Native reads of entity state (`GetVehicleNumberPlateText`, `NetworkGetEntityOwner`, ...) | A client's claim "I own this vehicle" |
| `xPlayer.identifier` resolved server-side from `source` | A client's claim "I have `vehicle_plate`" |
| ox_inventory's own server-side item count | Any client-supplied `netId`/`vehicle`/`owner` value (used only as a lookup key, re-verified every time) |

**Ownership verification.** Every operation re-derives ownership from
`owned_vehicles` by the vehicle's *actual current plate* (read via native,
server-side) and compares `row.owner` against `xPlayer.identifier` resolved
from the real connection (`source`), never from anything the client sent.

**`vehicle_plate` verification.** `GetPlateItemCount()` calls
`ox_inventory` server-side for the given `source`. If ox_inventory itself
errors for any reason, the count is treated as `0` (**fail-closed** — an
inventory-layer failure denies the operation instead of silently allowing
it).

**How a legitimate plate change is authorized.** See §2 below — the short
version is that authorization and the actual change happen inside the same
uninterruptible function call, so there's no separate "authorized" event a
client could replay or spoof.

**How unauthorized changes are detected.** Every tracked vehicle has one
server-owned baseline plate (`TrackedVehicles[netId].plate`). It changes
*only* when the server itself writes it (inside `AuthorizePlateChange`).
Whenever a native read of the entity's actual plate disagrees with that
baseline — checked on driver-enter, on a rate-limited client hint, and on a
45s sweep as a safety net — the server:
1. **Reverts** the entity's plate to the baseline immediately (native
   server-side write) — this is the actual "block", not just detection.
2. **Classifies** the drift (LEVEL 2–5) based on whether the new plate
   collides with someone else's registered vehicle and whether the
   responsible player (resolved via `NetworkGetEntityOwner`, a server-side
   native — never client-claimed) is the vehicle's registered owner.
3. **Logs** to console/DB/Discord, and **bans** automatically only at
   `LEVEL >= BanConfidenceLevel` (default 4 — collision with someone else's
   plate, or manipulation of a vehicle by someone who isn't its owner).

**Bans.** Stored in `masitz_anticheat_bans` (survives every kind of
restart). Enforced on `playerConnecting` using a confidence model: a strong
identifier (license/license2) alone blocks the connection; weaker signals
(Discord/Steam/IP) only block when **two or more** correlate to the *same*
ban row — a single IP/Discord match alone never blocks, only flags for
admin review (§15/§17 of the spec).

**Identifiers.** Collected via `GetPlayerIdentifiers`/`GetPlayerEndpoint`
into a plain table; any identifier that doesn't exist for a given platform
is simply absent — nothing assumes Steam/Discord/Xbox/etc. are present.

**Discord logging.** Four categories (🟢/🟡/🔴/🚨), each with its own
optional webhook override, falling back to a single general webhook.

**Performance.** No native is ever polled for every vehicle on the map. See
§5 (Performance considerations).

**False-positive minimization.** Bans require `LEVEL >= 4`, which only
happens when a plate collides with someone else's *registered* vehicle, or
when the vehicle's registered owner isn't the one who changed it. A plate
that merely changed through an unknown path but stays consistent with its
own owner (e.g. a bug in another resource) is logged at LEVEL 3
("suspicious"/"strong evidence") but never auto-banned; repeated low-level
offences can escalate to a ban (`EscalateRepeatOffences`), which is the only
place a string of "weak" signals turns into an automatic ban, and it is
opt-out and threshold-configurable.

---

## 2. Installation

1. Copy the `Masitz-Anticheat` folder into your resources directory.
2. Import `Masitz-Anticheat.sql` once (adds `masitz_anticheat_bans` and
   `masitz_anticheat_security_events` — it does **not** touch
   `owned_vehicles` or any other MM-garage table).
3. Set `Config.AntiNummerplade.Webhook` (and/or the per-category webhook
   overrides) in `config/anti-nummerplade/config.lua`.
4. Ensure **OneSync** (Infinity or Legacy) is enabled on the server — this
   module reads vehicle/entity state server-side, which requires it. See
   Known Limitations.
5. Add to `server.cfg`, after `es_extended`, `oxmysql`, and `ox_inventory`:
   ```
   ensure Masitz-Anticheat
   ```
6. Review `config/anti-nummerplade/config.lua` — in particular
   `BanEnabled`, `BanConfidenceLevel`, and `AdminGroups`.

No changes to the MM-garage resource are required for the anti-cheat to
start protecting registered vehicles: it discovers them itself, either the
moment they spawn (via `entityCreated`) or the moment a player gets into
them (via the vehicle-enter event), by reading their live plate and looking
it up in `owned_vehicles`.

---

## 3. Integrating the (future) reworked `nummerplade` script

Do **not** write directly to `owned_vehicles.plate` from the plate-change
script, and do **not** invent a client → server "this is authorized" event.
Instead, call the export below from the plate-change resource's own
**server** script, after it has received a request from its own client:

```lua
local ok, reason = exports['Masitz-Anticheat']:AuthorizePlateChange(
    source,       -- the requesting player's server ID (from your own event's `source`, never client-supplied)
    vehicleNetId, -- the target vehicle's network ID
    "NEW PLATE"   -- the requested new plate text
)

if not ok then
    -- reason is one of: invalid_arguments, invalid_player, invalid_vehicle,
    -- not_a_vehicle, could_not_read_plate, invalid_current_plate,
    -- vehicle_not_registered, not_owner, operation_in_progress, missing_item,
    -- invalid_new_plate_length, invalid_new_plate_charset, no_change,
    -- plate_already_registered, database_update_failed, item_removal_failed,
    -- internal_error
    -- Tell the player it failed; do not attempt to change the plate yourself.
    return
end

-- Success: the plate has already been changed in owned_vehicles, the
-- vehicle_plate item has already been removed (if ConsumeItemOnAuthorize),
-- and the entity's native plate has already been updated and Discord-logged.
-- Your script only needs to handle its own UI/UX feedback from here.
```

**Why this is safe even though your own event that triggers this is still
client-facing:** `AuthorizePlateChange` re-derives *everything* itself from
`source` and `vehicleNetId` — it re-reads the vehicle's actual current
plate, re-checks `owned_vehicles` for real ownership, re-checks
`vehicle_plate` via `ox_inventory` for that exact `source`, and re-validates
the requested new plate. It never trusts anything your resource "already
checked". This is also why there is no separate authorization *token*
system: ownership/item/duplicate verification and the actual DB write and
native update all happen inside one non-yielding tail of this single
function call, so there's no window between "authorized" and "applied" for
a client to exploit — a stronger property than a short-lived nonce would
give you, with less moving state to secure.

**Do not** call `SetVehicleNumberPlateText` yourself for a "legitimate"
change — always go through the export, or the anti-cheat will detect and
revert it as unauthorized on its next check.

---

## 4. Security audit

### The 10 required attack scenarios

| # | Attack | Bypassed? | Detection | Defense |
|---|---|---|---|---|
| 1 | Owner of `ABC123` changes own car's plate to victim's `XYZ789` | No | Native plate ≠ baseline; new plate found in `owned_vehicles` under another owner | LEVEL 5, revert + ban (`BanConfidenceLevel` default 4) |
| 2 | Stranger changes a stolen/random car's plate to victim's `XYZ789` | No | Vehicle bound on driver-enter (even if unregistered); same collision check as #1 | LEVEL 5, revert + ban |
| 3 | Only client-side vehicle state changed, client claims it's legit | No | There is no "client says it's legit" path at all — every check re-reads native/DB state itself | N/A — nothing to bypass |
| 4 | Direct `TriggerServerEvent(...)` with forged args | No | The only client→server event (`hintCheck`) carries just a `netId` used purely to pick *what* to re-verify; the actual verification always re-reads the entity natively | Forged args can at most make the server re-check a real vehicle sooner — never change anything |
| 5 | Client sends `plate/vehicle/owner` triplet as "truth" | No | No code path accepts an owner value from a client; ownership always comes from `owned_vehicles` keyed by the *actual* plate | N/A |
| 6 | Manipulate a vehicle that isn't the attacker's | No | `NetworkGetEntityOwner`-resolved responsible identifier ≠ `tracked.owner` | LEVEL 4, revert + ban |
| 7 | Reuse a plate that already exists in `owned_vehicles` | No | `DbGetVehicleByPlate(newPlate)` check, both in `AuthorizePlateChange` and in drift classification | Denied (legit path) / LEVEL 5 ban (exploit path) |
| 8 | Change plate on a car not currently owned by the attacker | No | Same as #6 | LEVEL 4, revert + ban |
| 9 | Change a plate without going through the legit system | No | Any native plate change not preceded by `AuthorizePlateChange` updating the baseline is drift by definition | LEVEL 2–3, revert + log (ban only if it also collides with someone else's plate, or repeats) |
| 10 | Spoof/replay a legitimate server event | No | There is no discrete "this change is authorized" event to replay — see §3 | N/A |

### Second review — logic/race/leak-focused

- **Race: two changes on the same plate at once.** In-process mutex
  (`PendingChange[plate]`) rejects the second request outright, *and* the
  DB-level `PRIMARY KEY` on `owned_vehicles.plate` rejects a duplicate-key
  UPDATE even if two different old-plates race for the same new-plate
  (a scenario the in-process mutex alone doesn't cover, since it's keyed by
  *old* plate).
- **Memory leak: growing `TrackedVehicles`.** Unregistered vehicles are
  auto-evicted after `UnregisteredWatchWindowSec` of no driver; registered
  vehicles are removed on `entityRemoved` and, as a backstop, the periodic
  sweep also prunes any entry whose entity no longer exists.
- **Memory leak: growing `OffenceLog`.** Pruned to entries within
  `RepeatOffenceWindowMs` every time a new offence is registered for that
  identifier — cannot grow past a few entries per offending identifier.
- **Mutex leak on error.** `AuthorizePlateChange`'s DB/inventory-touching
  section runs inside `pcall`, so an unexpected error (e.g. the vehicle
  being deleted mid-flight) still always releases `PendingChange` instead of
  permanently locking that plate.
- **Thread death.** The periodic sweep runs each vehicle's check inside
  `pcall` — one bad entry logs an `[ERROR]` line instead of silently killing
  the sweep thread for the rest of the server's uptime.
- **Passenger misattribution.** `CEventNetworkPlayerEnteredVehicle` fires
  for *any* seat, not just the driver's. Responsibility (`lastDriverSource`)
  is only attributed after confirming, server-side, that the entering
  player is actually in the driver seat — a passenger entering never gets
  blamed for a later violation.
- **Positional SQL params with `nil` holes.** Ban/security-event inserts use
  named (`:key`) parameters instead of a positional `?` array, because most
  of these fields (Discord, Steam, license2, ...) are routinely absent —
  and a `nil` in the middle of a Lua array is unsafe to iterate positionally
  (`ipairs` stops at the first hole; `#` over a table with holes is
  undefined by the Lua spec).
- **SQL injection.** Every single query in this module is parameterized;
  none use string concatenation.
- **Vehicle deleted / player disconnects mid-validation.** Every native call
  is preceded by `DoesEntityExist`; `AuthorizePlateChange` explicitly checks
  again *after* its awaits, before writing to the entity, and simply
  finishes without a native write if the vehicle vanished — the DB/inventory
  side of the change (already committed) is left consistent either way.
- **Resource/server restart.** All authority lives in
  `owned_vehicles`/`masitz_anticheat_bans`; `TrackedVehicles` is pure
  runtime cache that is naturally rebuilt as vehicles spawn/are entered
  again after a restart. No state is assumed to survive in memory.

### Final self-test — 10 bypass attempts an experienced exploiter might try

1. **Attack:** Trigger `hintCheck` with a forged `netId` for someone else's
   vehicle at high frequency. **Detection:** rate-limited per source (one
   per `ClientHintRateLimitMs`). **Defense:** the event only *schedules* a
   real re-verification, never trusts the payload for anything else.
   **Possible bypass:** none — worst case is a slightly early, harmless
   re-check of an unrelated vehicle. **Fix:** n/a.
2. **Attack:** Stop the `Masitz-Anticheat` client resource entirely before
   cheating. **Detection:** unaffected — detection is server-native-read
   driven, not client-reported. **Defense:** none needed. **Possible
   bypass:** none. **Fix:** n/a.
3. **Attack:** Call `AuthorizePlateChange`'s underlying logic by getting
   another resource to expose it. **Detection:** exports are Lua-to-Lua,
   server-to-server only; no client can invoke a server export directly.
   **Possible bypass:** only if the *calling* resource itself blindly trusts
   client input for `source`/`vehicleNetId`/plate and never re-validates —
   which is fine, because `AuthorizePlateChange` re-validates all of it
   itself regardless of what the caller believed. **Fix:** n/a (design
   already assumes the caller might be careless).
4. **Attack:** Change plate while disconnecting, hoping the ban write loses
   the race. **Detection:** `BanPlayer` still gathers identifiers and writes
   the ban row even if `source` is stale/gone by the time `DropPlayer` is
   called (kick failing is irrelevant — the DB ban row is what's enforced on
   the next connection). **Fix:** n/a — already handled.
5. **Attack:** Spam-spawn vehicles to blow up `TrackedVehicles` memory.
   **Detection:** unregistered vehicles are only tracked once a player
   actually enters as driver (bounded by concurrent player count, not spawn
   count), and expire after `UnregisteredWatchWindowSec`. **Fix:** n/a.
6. **Attack:** Enter a vehicle as a passenger to get "cover" so a driver's
   plate change is misattributed to you (deflection). **Detection:** driver
   attribution requires `NetworkGetEntityOwner(driverSeatPed) ==
   enteringSource`, verified server-side. **Fix:** already implemented (see
   "Passenger misattribution" above).
7. **Attack:** Rapidly re-enter/exit the driver seat to desync
   `lastDriverSource` right before changing the plate remotely (e.g. after
   exiting). **Detection:** the actual attribution at detection time comes
   from `NetworkGetEntityOwner(vehicle)` (who currently network-owns the
   *vehicle* entity, i.e. whoever can actually issue the native call that
   changed its plate) — `lastDriverSource` is only a fallback for the rare
   case that lookup fails. **Fix:** n/a — already the primary signal.
8. **Attack:** Hold two different old-plates and race both to the same new
   plate to end up owning a plate that shows as "unclaimed" to both mutexes.
   **Detection:** covered by the `PRIMARY KEY` on `owned_vehicles.plate` —
   only one `UPDATE` can win. **Fix:** n/a — already handled (DB-level
   defense-in-depth, see "Race" above).
9. **Attack:** Use a plate value with control characters / extreme length to
   break the Discord embed or SQL. **Detection:** `ValidatePlateFormat`
   rejects anything outside `PlateCharsetPattern`/length bounds before it
   reaches the DB or a log message; DB access is always parameterized
   regardless. **Fix:** n/a — already handled.
10. **Attack:** Reconnect with a new Discord account after an IP+license
    ban to evade. **Detection:** license/license2 alone already blocks the
    reconnection (strongest, most stable identifier) regardless of Discord.
    **Fix:** n/a — already handled; a genuinely fresh device+account+IP
    combination is the one case no anti-cheat identifier model can close,
    documented under Known Limitations.

---

## 5. Performance considerations

- **No full-map scans, ever.** The periodic sweep (`SweepIntervalMs`,
  default 45s) iterates only `TrackedVehicles` — bounded by the number of
  currently-relevant (registered or player-driven) vehicles, not the total
  vehicle count on the server.
- **Event-driven first, polling second.** Real detection happens on
  `entityCreated` (registered vehicles), vehicle-enter (any vehicle a player
  actually uses), and the rate-limited client hint. The sweep exists purely
  as a safety net for a vehicle nobody has interacted with recently.
- **One native call per check.** Each verification is a single
  `GetVehicleNumberPlateText` read; a DB query only happens when that read
  actually disagrees with the cached baseline (the common case is zero DB
  queries per sweep tick).
- **Client cost is near zero.** The client only polls (2s interval) while
  the local player is actually driving, and only sends a hint on an actual
  observed plate change on their own vehicle, rate-limited server-side
  regardless.

---

## 6. Known limitations

- **Requires OneSync** (Infinity or Legacy). Without it, the server has no
  visibility into vehicle/entity state and this module cannot function —
  most modern ESX servers already run OneSync, but this is a hard
  requirement, not a soft recommendation.
- **`gameEventTriggered` / `CEventNetworkPlayerEnteredVehicle` argument
  shape** is community-documented rather than officially specified by CFX
  and could differ across server builds. The handler is defensive
  (`pcall`-guarded, nil-checked) and degrades gracefully — the periodic
  sweep still catches anything this event misses, just up to
  `SweepIntervalMs` later.
- **`ox_inventory` export names** (`GetItemCount`/`Search`/`RemoveItem`) are
  based on the commonly documented ox_inventory server API and are called
  through `pcall` with a fallback chain; verify against your installed
  ox_inventory version if item checks unexpectedly deny everything (they
  fail *closed*, so a mismatch shows up as false denials, never as a
  bypass).
- **`oxmysql`** (`MySQL.query/single/update/insert` with `.await` and named
  `:key` parameters) is assumed as the MySQL layer, consistent with a
  modern ESX Legacy + ox_lib + ox_inventory stack. If a different DB library
  is used, the `Db*` helper functions are the only place that needs
  adapting.
- **IP-based correlation** cannot distinguish shared/dynamic IPs from a
  genuinely returning banned player with certainty — this is why IP alone
  never blocks a connection in this design (see §1), only contributes to a
  ≥2-signal correlated match.
- **A genuinely fresh identity** (new hardware ID / new license / new
  Discord / new IP simultaneously) cannot be linked to a prior ban by any
  identifier-based system, including this one.
- **`GetGameTimer()` rollover**: used for rate-limiting and repeat-offence
  windows; like any FiveM script relying on it, an extremely long
  continuous uptime could in theory roll the counter over. Impact here is
  limited to a rate-limit or offence-window very occasionally resetting
  early — never a security bypass, since bans/ownership never depend on it.
