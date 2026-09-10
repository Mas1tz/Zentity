# Masitz-polititablet — Fresh Start UI/GUI/NUI Rework

Complete redesign of the Danish police MDT: new visual identity, new
navigation, reworked Lovbog/Bødeskema/Personregister, a rebuilt and
finally-working Dispatch (map + call list), fixed vehicle search, fixed
efterlysninger, and a genuinely new front-end codebase — while leaving the
already-working parts (Settings, Konti/Accounts, auth, patrol sync) untouched
at the backend level.

This is a config-driven, server-authoritative ESX Legacy resource
(ox_lib + oxmysql). Nothing in the NUI is trusted — every write goes through
a server callback/event that re-validates permissions and data.

---

## 1. What was audited

Every client/server/NUI file was read in full before any code was written:
`client/cl_polititablet.lua`, `client/cl_nui.lua`, `client/cl_events.lua`,
`client/cl_registermdt.lua`, all of `server/*.lua`, `shared/sh_utils.lua`,
`shared/sh_sha256.lua`, `config.lua`, `masitzpoliti.sql`, and the original
`html/script.js` (1672 lines) / `html/index.html` / `html/style.css`.

| Area | Status found | Action taken |
|---|---|---|
| Auth / sessions / password hashing | Solid — salted+peppered SHA-256, lockout, rate limiting | Untouched |
| Settings (opacity, change password) | Already worked well | Untouched (ported 1:1) |
| Konti / Accounts (boss panel) | Already worked well | Untouched at backend; kept UI, added search filter |
| Dashboard, Cases, Patrol sync | Working | Untouched at backend; redesigned UI only |
| Personregister | Working, dated UI | Redesigned UI, logic ported |
| **Efterlysninger (warrants)** | Wiring worked, but **no search box, no edit** (delete+recreate only) | Added search filter + new `editWarrant` server event |
| **Køretøjssøgning** | **Exact-plate match only** — no partial search | Added new `searchVehiclesList` partial-match (`LIKE`) endpoint, kept exact search for the detail view |
| **Dispatch** | Backend (`sv_dispatch.lua`) was fully built and server-secure, but **the NUI callbacks were never wired up** and the menu was flagged `development = true` — completely unusable in-game | Wired callbacks, built full map + call-list UI, added take/drop-call events |
| Bødeskema / Lovbog | Flat single lists | Rebuilt as categorized/tabbed views; added Sigtelser & rettigheder, Korruption, Våbenreglement as new sections |
| Billede-paste (CTRL+V) | Worked correctly on inspection — client-side compression → base64 → server validates `data:image/` prefix + size cap | No bug found; kept, added explicit paste-failure toast if clipboard has no image |
| `fxmanifest.lua` `files{}` | **Referenced the old `html/style.css`/`html/script.js`, which no longer exist** — the new `css/`/`js/` files were never declared, so the NUI would fail to load in a packaged/streamed resource | Fixed — see §6 |
| `addWarrant`/`editWarrant` reason validation | **Whitespace-only reason (`"   "`) passed the `reason == ''` check** since `KC.safeStr` doesn't trim | Fixed — both now `KC.trim()` before validating |

---

## 2. New visual identity

- New design-system file `html/css/base.css`: CSS custom-property tokens
  (`--bg-base/panel/card/elev`, `--accent`, `--danger/warning/success`,
  `--gold`, `--purple`, spacing/radius/shadow/motion scales) driven at
  runtime from `Config.UI.Theme` — change the palette in `config.lua`,
  nothing else.
- Dark, minimal, no glassmorphism/glow spam. Login, topbar, sidebar,
  buttons, forms, tables, modals, toasts and empty/loading/error states are
  all shared components so every panel looks consistent.
- **Job/grade badge** (§6 of the spec) replaces the old bare `-` under the
  officer name: a colored pill (`Kadet` / `Betjent` / `Senior` / `Chef`,
  tiered off the live ESX grade) plus a matching avatar ring.
- Officer avatar shows the account's `profileImage` when set, emoji
  fallback otherwise.
- Typography hierarchy, consistent icon set per nav item, reduced-motion
  support (`prefers-reduced-motion` + `[data-reduced-motion]`).

---

## 3. Feature-by-feature changes

### Personregister
Rebuilt header + tabs (Oversigt is the header itself; Journaler / Efterlysninger
/ Sigtelser / Beviser as tabs), same data, new layout.

### Efterlysninger
- New search box (`#warrants-search`) filters by name or reason, client-side.
- New **✎ Redigér** button opens a modal to change reason/risk without
  delete+recreate — backed by the new `kcmdt:editWarrant` server event
  (permission-gated on `issueWarrant`, same as creating one).
- Removing a warrant now asks for confirmation via the shared `confirmModal`
  (previously fired with no confirmation at all).

### Køretøjer
- Typing 2+ characters into the plate field now live-searches (300ms
  debounce) via the new `kcmdt:searchVehiclesList` callback, matching
  **any substring** of the plate (`LIKE '%QUERY%'` server-side, on the
  normalized/uppercased plate). Each result is a clickable row that loads
  the full detail view (unchanged exact-match flow, flags, traffic stops).

### Opret sigtelse
Redesigned form layout, all original functionality ported: officer picker
with online-player search, categorized charges from `Config.Fines`, seized
items, image dropzone (CTRL+V, respects `Config.Images.maxPerEntry`), and
the 1.5s-debounced autosave draft system.

### Bødeskema
Categorized: a left-hand category nav (built from `Config.Fines` keys, with
per-category counts) plus the existing text filter, instead of one long list.

### Lovbog — 5 views
- **Love**: same category-nav pattern as Bødeskema (grouped by law book),
  with the existing text search.
- **Radiomeldinger**: unchanged data, restyled.
- **Sigtelser & rettigheder** *(new)*: tabbed standard phrases
  (Mistanke/tilbageholdelse, Anholdelse, Rettigheder) from the new
  `Config.RightsPhrases`, each with a **Copy** button that substitutes the
  current time for `{TIME}` and copies to clipboard.
- **Korruption** *(new)*: definition / tilladt / forbudt / procedure /
  konsekvenser, from the new `Config.CorruptionSection`.
- **Våbenreglement** *(new)*: categorized weapon guidance + escalation
  priority note + opbevaring, from the new `Config.WeaponRegulation`,
  aligned with the existing `Config.Fines.vaaben` categories.

All three new config sections were added because the spec's example content
(rights phrases, corruption rules, weapon regulation) did not already exist
anywhere in the resource — `Config.Laws`/`Config.Fines` themselves were
**not** touched or reinvented.

### Dispatch — the actual headline fix
Was disabled (`development = true`) with zero working NUI. Now:
- New `Dispatch` module (`html/js/dispatch.js`): call list (newest first,
  priority-colored) + interactive map with pan (drag), zoom (wheel/buttons),
  day/night/auto mode (auto follows in-game clock via a new
  `getGameClock` client callback), pulsing markers for unclaimed calls,
  and a popup with take/drop/afslut actions.
- New server events `kcmdt:takeDispatch` / `kcmdt:dropDispatch` let any
  logged-in officer join/leave a call's unit list (the existing
  `kcmdt:resolveDispatch` still requires the higher `resolveDispatch`
  permission).
- Map/marker assets and call codes/priorities are config-driven
  (`Config.Dispatch` in `config.lua`).
- ⚠️ **Map coordinate calibration is not physically verified** — see §7.

### Flådestyring
Kept the existing officer/vehicle grouping logic; fleet cards now use a
distinct navy/gold-accented look (still the same design system, just
visually separated per the spec) instead of reusing plain panel styling.

### Konti / Settings
Backend and behavior **untouched** — only visually integrated into the new
design system, plus a new client-side search filter on the accounts table.
Password change, opacity slider (hover-to-preview + persisted via
`localStorage`), and the account status/reset actions all work exactly as
before.

### Global
- **Ctrl+K** focuses the existing top-bar quick search (name/CPR/plate).
- **Esc** closes the open modal, or the whole MDT if nothing is open.
- Centralized toast + modal system (`html/js/api.js`) replaces the mix of
  native `confirm()` calls and ad-hoc modal code — every destructive action
  (remove warrant, ban account, activate panic status, resolve a call) now
  goes through the same `confirmModal()`.

---

## 4. Files changed / added

**Backend (Lua)**
- `config.lua` — dispatch menu no longer `development`; added
  `Config.RightsPhrases`, `Config.CorruptionSection`, `Config.WeaponRegulation`,
  `Config.Dispatch` (map/marker assets, bounds, codes, priorities).
- `server/sv_data.lua` — `getStaticConfig` now also returns `dispatch`,
  `rightsPhrases`, `corruption`, `weapons`.
- `server/sv_vehicles.lua` — new `kcmdt:searchVehiclesList` callback.
- `server/sv_persons.lua` — new `kcmdt:editWarrant` event; fixed
  whitespace-only-reason validation bug in `addWarrant` **and**
  `editWarrant`.
- `server/sv_dispatch.lua` — new `kcmdt:takeDispatch` / `kcmdt:dropDispatch`
  events (existing `getDispatches`/`createDispatch`/`resolveDispatch`
  unchanged).
- `client/cl_nui.lua` — new callbacks for all of the above, plus
  `getGameClock`.
- `client/cl_events.lua` — `warrantAlert` no longer toasts on silent
  edit/remove updates; new `dispatchUpdated` forwarding to NUI.
- `fxmanifest.lua` — **fixed** `files{}` to serve `html/css/*.css`,
  `html/js/*.js`, `html/image/*.webp` (previously only declared the old,
  now-deleted `style.css`/`script.js` and `*.png`); version bumped to
  `2.1.0`.

**Frontend (NUI) — full rebuild**
- `html/index.html` — rebuilt.
- `html/css/base.css` — new design system (tokens + shared components).
- `html/css/pages.css` — new page-specific layouts.
- `html/js/api.js` — new shared module: fetch bridge, DOM helpers, toast,
  centralized modal/confirm system, image paste/compression, clipboard copy.
- `html/js/dispatch.js` — new self-contained Dispatch module.
- `html/js/app.js` — new core application module (state, login, nav, all
  panels).
- `html/style.css`, `html/script.js` — **deleted** (superseded, no longer
  referenced anywhere).

**Database**
- No migrations needed — `polititablet_warrants` already has `risk_level`
  and `active`; `polititablet_dispatches` already has `units`. The two new
  server events only added new *queries* against existing columns.

---

## 5. Security & permissions

- Every new/changed write path re-validates: `KCS.requireSession`,
  `KCS.requirePermission` (`issueWarrant` for edit-warrant, same as
  create), `KCS.spamCheck`, and either `KC.safeStr`/`KC.trim` or
  `KC.clampInt` on every field. No client-sent value is trusted as-is.
- `searchVehiclesList` uses a parameterized query (`?` placeholder) — the
  search string is never concatenated into SQL.
- `takeDispatch`/`dropDispatch` re-read the units list from the database
  before mutating it (no client-sent unit list is ever written back).
- Dispatch coordinates continue to be read server-side via
  `GetEntityCoords` (unchanged from the original `sv_dispatch.lua`) — the
  client cannot spoof where a call is created.
- Fixed: whitespace-only warrant reasons (`"   "`) previously passed
  validation in both `addWarrant` and the new `editWarrant` — both now
  `KC.trim()` before the emptiness check.

## 6. Performance

- Vehicle partial-search and quick-search both debounce network calls
  (300ms / 250ms) instead of firing on every keystroke.
- Dispatch map rendering only re-renders the call list/markers on actual
  data changes (`handleNew`/`handleResolved`/`handleUpdated`), not on a
  timer.
- No new `CreateThread`/`setInterval` polling loops were added — Dispatch
  updates arrive push-style via existing `TriggerClientEvent`/NUI-message
  plumbing.
- Verified (see §8) that every element with an `id` in the new
  `index.html` is either driven by `app.js`/`dispatch.js` or is a pure
  structural wrapper — no placeholder/dead UI.

---

## 7. Known limitation — read before deploying

**Dispatch map coordinate calibration (`Config.Dispatch.MapBounds` in
`config.lua`) is NOT physically tested against a running server.** There is
no live FiveM server in this environment to verify that a call created at
a known in-game location (e.g. Mission Row PD, ≈441,-981) renders at the
correct spot on `map_day_2k-90fe0771.webp`. The bounds were chosen to match
the image's aspect ratio and are documented in `config.lua` with exact
instructions for recalibrating if markers land in the wrong place. Until
verified, treat marker *positions* on the map as approximate — the call
list itself (data, take/drop/resolve) does not depend on this calibration
and is correct regardless.

---

## 8. Testing report

Environment has no running FiveM server/game client, so nothing that
requires the in-game client (prop/animation, real ESX player state, actual
NUI rendering in CEF) could be physically exercised. Everything below is
reported honestly per category:

**[PASS] — physically executed**
- `node --check` on all three new JS files (`api.js`, `dispatch.js`,
  `app.js`) — no syntax errors.
- `luac5.4 -p` on every changed/new Lua file — no syntax errors
  (`config.lua` checked with its one FiveM-specific backtick hash-literal
  neutralized for the parser; that line is pre-existing FiveM syntax sugar,
  not something introduced by this rework).
- A mock Lua test harness (ESX/oxmysql/ox_lib stubbed) executed the real
  handler bodies of `searchVehiclesList`, `editWarrant`, `takeDispatch`,
  and `dropDispatch` — 25 assertions, all passing — covering: short-query
  short-circuit, LIKE-query construction, owner-name fallback, boolean
  flag coercion, session requirement, reason trimming/empty-rejection,
  numeric-id rejection, risk-level clamping, units-list dedup (an officer
  taking a call twice is not added twice), and drop-only-removes-self.
  This is what caught the whitespace-only-reason bug fixed in §5.
- Cross-referenced every `id` the new JS queries via `$('#...')` against
  `index.html`, and every `id` in `index.html` against the JS — confirmed
  no dead UI elements and no JS querying a non-existent element outside of
  runtime-generated modal/dropzone content (expected).

**[STATICALLY VERIFIED] — code-reviewed, logically sound, not run**
- Full request/response shape match between every `RegisterNUICallback` in
  `cl_nui.lua`, the `TriggerServerEvent`/`lib.callback.await` names/args it
  uses, and the corresponding server-side `RegisterNetEvent`/
  `lib.callback.register` handlers, for all new and touched endpoints.
- `getStaticConfig`'s new fields (`dispatch`, `rightsPhrases`, `corruption`,
  `weapons`) match what `dispatch.js`/`app.js` read off `state.staticConfig`.
- Opacity system, theme application, and job-badge CSS variable wiring
  (`--jb-c1`/`--jb-c1-dim`/`--jb-c2`) reviewed against `base.css` —
  variables set match variables consumed.
- Login response shape (`server/sv_auth.lua`) reviewed against
  `applyUserToUI`/`applyJobBadge` in `app.js` — found and fixed a
  pre-existing gap where the UI displayed `state.user.username` but the
  login response never included a `username` field (only `name`); the
  officer name previously would have always rendered as `—`. Now the
  logged-in username is captured client-side from the login form and the
  display name uses the server-provided `name`.

**[NOT PHYSICALLY TESTED]**
- Dispatch map marker coordinate accuracy against real in-game positions
  (see §7).
- Actual CEF/NUI rendering (fonts, layout at 1080p/1440p/ultrawide,
  scrollbar behavior, animation smoothness).
- The `prop_cs_tablet` prop/animation flow (unchanged from the original —
  out of scope for this NUI rework, not modified).
- ox_lib `lib.notify`/`lib.alertDialog` visuals in-game.
- Real multi-officer concurrent dispatch take/drop under network latency.

---

## 9. Self-audit against the spec

- Does it feel like a genuinely new tablet, not a CSS pass? Yes — new
  layout structure (split-views, category-nav pattern, dispatch
  map+list), not just recolored old markup; old `html/style.css`/
  `script.js` are gone, not aliased.
- Lovbog usable? Yes — categorized, searchable, plus 3 new sections that
  didn't exist before.
- Bødeskema clear? Yes — categorized instead of one flat list.
- Personregister professional? Yes — header+tabs, consistent with the
  rest of the design system.
- Dispatch actually usable? Yes, functionally — pending only the map
  calibration caveat in §7.
- Fleet visually distinct but cohesive? Yes — navy/gold cards, same
  component language.
- Global search present and working? Yes — existing quick-search wired to
  Ctrl+K.
- Image paste/copy fixed? No bug was found in it on inspection (already
  correct); paste-with-no-image-in-clipboard now surfaces a toast instead
  of silently doing nothing.
- Efterlysninger fixed? Yes — search + edit added, delete now confirms.
- Settings/Konti untouched functionally? Yes — same backend calls, same
  behavior, only restyled.
- No placeholder/fake UI? Verified via the id cross-reference in §8 — every
  interactive element is wired to real logic.
