# EllesmereUI core framework: architecture study

Study notes on the `EllesmereUI` parent addon (v9.7, Interface 120000-120105 + 16001), read from
`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\EllesmereUI\`.

> **Licence reminder.** EllesmereUI is "all rights reserved". Everything below describes their
> design in our own words so that SoulUI can make informed decisions. Do not paste their code.
> The few snippets here are short illustrations of *Blizzard API usage* (under 10 lines each)
> and are written fresh, not copied.

File references use `File.lua:line` against the v9.7 files. Line numbers drift between releases,
so treat them as "roughly here".

---

## 1. Overview

EllesmereUI ("EUI") is a suite: one parent addon (`EllesmereUI`, ~90k lines, 83 Lua files)
plus about 20 child addons (`EllesmereUINameplates`, `EllesmereUIUnitFrames`,
`EllesmereUIActionBars`, `EllesmereUICooldownManager`, `EllesmereUIRaidFrames`, ...), a
LoadOnDemand options addon (`EllesmereUIOptions`) and a LoadOnDemand translation addon
(`EllesmereUILocales`).

The parent is not "just a library". It owns:

- the addon/event/DB framework (their Ace3 replacement, `EllesmereUI_Lite.lua`);
- the single SavedVariables store `EllesmereUIDB` for the whole suite (profiles, positions,
  anchors, colours, fonts, account settings);
- the options panel shell (sidebar, pages, search, plugin API) - the widgets and pages live in
  the LOD options addon;
- Unlock Mode (the mover/anchor/snap editor) - about 14k lines across 9 files;
- profile import/export, profile sync groups, spec overrides, conditional overrides;
- shared rendering services: pixel-perfect math and borders, glows, rounded corners,
  absorb glow, aura container kit (12.1 engine aura containers), range engine, text tags,
  number abbreviation, fonts, colours;
- shared runtime services: ticker/driver, combat queue, cursor service, visibility dispatcher;
- a pile of feature code that "belongs to everyone" (kick lookup, secure menu proxies, warrior
  charges, gold ledger, party mode, macro factory, first-install popup, uninstall/CVar restore).

### 1.1 TOC and load order (`EllesmereUI.toc`)

```
## Interface: 120000, 120001, 120005, 120007, 120100, 120105, 16001
## SavedVariables: EllesmereUIDB
```

Load order (abbreviated, with purpose):

| # | File | Role |
|---|------|------|
| 1 | `EllesmereUI_ClientGate.lua` | Pre-12.1 failsafe. MUST be first. |
| 2 | Libs: LibStub, CallbackHandler, LibDataBroker, LibSharedMedia, LibDeflate, LibKeystone, LibSpecialization | Only libs; no Ace. LibKeystone/LibSpecialization carry `[AllowLoadGameType standard]` |
| 3 | `EllesmereUI_Lite.lua` | Addon objects, events, DB, lifecycle |
| 4 | `EllesmereUI_Uninstall.lua` | CVar/EditMode change recorder (before anything changes a setting) |
| 5 | `EllesmereUI_Locale.lua` | `L()`, LOD locale loading |
| 6 | `EllesmereUI_NumberFormat.lua` | K/M/B and CJK abbreviation configs |
| 7 | `EllesmereUI_Migration.lua` | One-time migrations at parent ADDON_LOADED |
| 8 | `EllesmereUI_Startup.lua` | UI scale applied at ADDON_LOADED, engine-cached fonts |
| 9 | `EllesmereUI_GoldLedger.lua` | Account gold record |
| 10 | `EllesmereUI_PixelPerfect.lua` | PP math, border system (EllesmereUI.lua reads PP at load) |
| 11 | `EllesmereUI.lua` | Constants, theme, panel scaffolding, deferred-init slots, slash commands, escape proxy |
| 12+ | AbsorbGlow, Panel, VisibilityRules, SharedHelpers, Popups, TextTags, Colors, Fonts, ProfileSync, RetailAtlas, BuffPresets, UICore, Ticker, Mouse, BlizzardParty, KickData, Kick, MenuFallbacks, SignupHelpers, GlobalSearch, Visibility, Presets, Profiles, PartyMode, MacroFactory | Services |
| .. | `EUI_UnlockMode_PointAnchors.lua`, `EUI_UnlockMode.lua`, `_Anchors`, `_Positions`, `_Tools`, `_PointVisuals`, `_PointPicker`, `_Movers`, `_Session`, `_Filter` | Unlock Mode (body deferred, see 6.1) |
| .. | Glows, RoundedCorners, ClassicArt, Range, AuraKit, WarriorCharges, ManaRegenSpark, SpellCostPrediction, FriendsKit, popups (FirstInstall, RaidFrames, PatchNotes, WindowSkins, SpecOverrides, StyleCards/Choice/Launch, GroupFinder, KickTracker), VideoGuides | Rendering kits and one-shot UI |
| last | `EllesmereUI_SpecOverrides.lua` + 8 `EUI_SpecOverrides_*.lua`, then `EllesmereUI_Conditions.lua` | Per-spec / conditional override engine |

Two load-order notes they call out repeatedly:

- Some files are read by others **at load time** (PixelPerfect before EllesmereUI.lua; Lite
  first so `EllesmereUI.Lite` exists). Others are only read at call time, and later files
  install **"early stubs"** that a deferred body replaces (Unlock Mode does this heavily).
- Several big files are "at Lua 5.1's 200-local cap" or "60-upvalue cap". Their workaround is
  to park state on the `EllesmereUI` table or a private `ns` table instead of file locals. We
  should design to avoid this (smaller files, one module table per file).

### 1.2 Client gate

`EllesmereUI_ClientGate.lua` reads `select(4, GetBuildInfo())`:

- `16000 <= iface < 20000` -> sets `EUI_CLIENT_FOREVER` ("WoW Forever", the 12.1 engine with
  vanilla content) and continues.
- `iface >= 120100` -> continue.
- otherwise sets global `EUI_CLIENT_BLOCKED = true` and shows a plain popup at
  PLAYER_ENTERING_WORLD.

**Every** suite file's line 1 is `if EUI_CLIENT_BLOCKED then return end`. The point is data
safety: on an older client nothing touches SavedVariables, so WoW round-trips the WTF file
untouched. It is fail-open (non-numeric iface runs normally). This is a cheap, good idea.

### 1.3 How child addons hook in

Child TOC pattern:

```
## Dependencies: EllesmereUI
## SavedVariables: EllesmereUINameplatesDB     (vestigial - see 2.3)
## Group: EllesmereUI          (addon-list grouping)
## Category: ...
```

Child main chunk:

1. `local addon = EllesmereUI.Lite.NewAddon("EllesmereUINameplates")` at file scope.
2. In `OnInitialize`: `addon.db = EllesmereUI.Lite.NewDB("EllesmereUINameplatesDB", { profile = defaults })`.
3. Publishes its private `ns` into `EllesmereUI._ModuleNS[folder]` so the LOD options files can
   find it.
4. Registers unlock elements with `EllesmereUI:RegisterUnlockElements({ EllesmereUI.MakeUnlockElement{...} }, folder)`.
5. Exposes global apply hooks like `_G._ERB_Apply`, `_G._EUF_ReloadFrames`, `_G._ECME_Apply`
   which the parent calls by name on profile change / scale change (see 7.4). This is a hard
   coupling we should not copy - use a callback registry instead.

All SV-bearing children are hard dependencies (never LoadOnDemand). Only `EllesmereUIOptions`
and `EllesmereUILocales` are LOD, and both declare **no** SavedVariables on purpose (see the
stale-DB guard in 2.4).

---

## 2. `EllesmereUI_Lite.lua` - the Ace3 replacement

~560 lines replacing AceAddon + AceEvent + AceDB. Worth mirroring closely in spirit.

### 2.1 Addon objects

- `NewAddon(name)` returns a plain table `{ name, enabledState = true }`, stores it in a private
  registry, queues it for init, and mixes in `RegisterEvent`/`UnregisterEvent`.
- `GetAddon(name, silent)` for cross-addon access.
- No module/sub-module hierarchy, no mixin library, no embeds.

### 2.2 Event dispatch

- One hidden event frame **per addon**, holding a `_handlers[event] = fn` map and a single
  `OnEvent` that looks up and calls `handler(addon, event, ...)`.
- `RegisterEvent(event, fnOrMethodNameOrNil)`: a function is stored directly (no wrapper
  closure, to save a call per event); a string or nil gets a closure that resolves
  `addon[method]` at dispatch time.
- No CallbackHandler, no `securecallfunction` loop.

**CPU attribution insight (important).** Their comments (`Lite.lua:58-79`, `Ticker.lua:9-28`)
state, probe-verified: the client bills a script handler's entire call tree to the addon whose
*execution context created the frame* - not where the closure was defined or who called
`SetScript`. `OnInitialize`/`OnEnable` run inside the parent's ADDON_LOADED/PLAYER_LOGIN
dispatch, so frames created there are billed to the parent forever. Therefore:

- `NewAddon` creates the per-addon event frame **eagerly** in the child's main chunk.
- Ticker drivers, combat queues and aura build workers all accept a frame "created in your own
  main chunk" so the work bills the right addon.

This matters for anyone reading `/framestack`-style CPU profiling or the addon CPU panel.

### 2.3 DB model

There is exactly one SavedVariables table for the suite: `EllesmereUIDB`.

```
EllesmereUIDB = {
  activeProfile = "Default",
  profileOrder  = { "Default", ... },
  specProfiles  = { [specID] = "ProfileName" },
  lastSpecByChar = { ["Name - Realm"] = specID },
  profiles = {
    [name] = {
      addons = { [childFolder] = <that child's profile table> },
      fonts = {...}, customColors = {...}, darkMode = {...},
      unlockLayout = { anchors, widthMatch, heightMatch, widthMatchExtra,
                       heightMatchExtra, phantomBounds },
      specOverrides = {...}, specOverrideGroups = {...}, condOverrideGroups = {...},
      _migrations = { [id] = true },
      ...
    },
  },
  -- live (active-profile) unlock link tables, restored from profiles[x].unlockLayout:
  unlockAnchors, unlockWidthMatch, unlockHeightMatch, unlockWidthMatchExtra,
  unlockHeightMatchExtra, phantomBounds,
  -- account-wide settings and one-shot flags:
  ppUIScale, panelScale, activeTheme, accentColor, syncedModules, goldLedger,
  firstInstallPopupShown, videoGuidesSeen, unlockGridMode, unlockSnapEnabled, ...,
  _migrations = { [id] = true },
}
```

`NewDB(svName, defaults)` (`Lite.lua:250`):

1. Derives the child folder from the SV name by stripping a trailing `DB`.
2. Ensures `EllesmereUIDB.profiles[active].addons[folder]` exists and points `db.profile` at it.
3. **Wipes the child's own SV global in place** (`wipe(_G[svName])`) - child SVs are vestigial;
   wiping (not replacing) means WoW's serializer, which still holds the original table
   reference, writes an empty table.
4. `DeepMergeDefaults(profile, defaults.profile)` fills only missing keys (recursive).
5. Corruption check: if any top-level default sub-table is not a table after the merge, wipe the
   profile, re-merge, and print a one-time warning after 5 s.
6. Returns `db = { sv, svName, folder, profile, _profileName, _defaults, _profileDefaults,
   ResetProfile() }` and pushes it into `_dbRegistry` (exposed so the profile system can
   repoint every db in place).

There is no AceDB-style metatable default lookup. Defaults are physically merged in on load and
**stripped on logout**: at `PLAYER_LOGOUT` they run pre-logout callbacks first (profile snapshot
etc.), then for each registered db they deep-copy the live profile, strip values equal to
defaults, and write the stripped copy back into the store. The live `db.profile` reference is
left untouched (a pre-logout callback may still read it).

Pitfall they hit: `StripDefaults` drops empty sub-tables only for non-numeric keys, so array
slots stay aligned.

### 2.4 Lifecycle and the two safety guards

- `OnInitialize` runs on every ADDON_LOADED (drains the init queue, exactly like AceAddon).
- `OnEnable` runs at PLAYER_LOGIN. Before draining it calls `PP.UpdateMult()` and
  `EllesmereUI.PreSeedSpecProfile()` (spec API is ready here but not at ADDON_LOADED).
- **Synchronous at PLAYER_LOGIN, deferred one tick for post-login demand loads**
  (`Lite.lua:525-559`). Rationale: secure setup (RegisterStateDriver, WrapScript, protected
  SetCVar, EditMode Hide) is only allowed in combat during the login/reload loading screen, and
  `C_Timer` callbacks do not fire during the loading screen; but a post-login ADDON_LOADED can
  be dispatched from inside a Blizzard secure execution, and running OnEnable there stamps taint
  onto values that Edit Mode later reads (errors on 12.x secret values). A `C_Timer.After(0)`
  gives a clean addon-owned execution.
- **Stale central-DB guard** (`Lite.lua:384-513`): WoW executes a child's entire WTF file when the
  child loads, including variables its TOC no longer declares. A child that once declared
  `EllesmereUIDB` can therefore overwrite the real store with a frozen copy. Lite captures the
  table at its own ADDON_LOADED and, until PLAYER_LOGIN, re-points the global back if any later
  load swapped it.
- **Standalone builds**: they package single modules as standalone addons by textually renaming
  "EllesmereUI". A file-scope NewDB there would run before the SV loads; they queue such dbs and
  re-root them in place at ADDON_LOADED. `IsDBReady()` tells consumers when cached profile data
  can be trusted. `OnSavedVariablesLoaded(fn)` runs account passes that must see raw loaded data.

---

## 3. Startup, migration and client-cached settings

### 3.1 `EllesmereUI_Startup.lua`

- **UI scale.** `ppUIScale` is applied at ADDON_LOADED (earliest moment the SV exists) and again
  at PLAYER_LOGIN, then re-applied on `UI_SCALE_CHANGED`. First install snapshots the user's
  current Blizzard scale at PLAYER_ENTERING_WORLD (clamped 0.4-1.15) and re-applies at +2 s and
  +5 s for slow machines. All applies go through the core combat queue when in combat.
  Old near-values are migrated to exact pixel-perfect (`768/1440`, `768/1080`).
- **Panel scale seed**: options panel scale defaults to `physH/1440` (floored at 1), snapped to
  5% steps, so 4K users get a readable panel.
- **Undocked chat drift fix**: Blizzard restores undocked chat windows as a screen-height ratio
  while the CVar scale is active, then EUI changes UIParent scale, so the window creeps every
  login. Fix: one deferred pass after login re-runs Blizzard's own formula using
  `GetChatWindowSavedPosition(i)` against the settled screen size. They explicitly *removed*
  hooks on FCF functions and `SetUserPlaced` writes as taint risks.
- **Engine-cached font globals**: `UNIT_NAME_FONT` and `DAMAGE_TEXT_FONT` are plain path strings
  the client caches at login. They set them at file scope / ADDON_LOADED. A font path is probed
  with `pcall(fs.SetFont, fs, path, 12, "")` - **only a raised error means "missing"**; the
  boolean return was observed to be unreliable.

### 3.2 `EllesmereUI_Migration.lua`

A one-time migration runner (`RegisterMigration{ id, scope, description, body }`):

- scopes: `global` (flag on the root), `profile` (runner iterates every profile),
  `specProfile` (every spec-profile bucket);
- flags stored as `host._migrations[id] = true`, stamped only after `pcall(body)` succeeds, so a
  failed migration retries next session; errors buffered for a `/eui migrations` command;
- runs at the parent's ADDON_LOADED, before any child initialises.

Their stated rules: ids are permanent; bodies must still be idempotent; never iterate profiles
inside a body; never call live game APIs (UnitClass, GetSpecialization) at that phase; edit raw
profile tables, never `child.db.profile`. Good rules - adopt them.

---

## 4. Rendering foundations

### 4.1 Pixel perfect (`EllesmereUI_PixelPerfect.lua`)

Core values:

- `perfect = 768 / physicalScreenHeight` (one physical pixel in UIParent units at scale 1).
  `RefreshPhysical` keeps the last good height if `GetPhysicalScreenSize()` returns 0/nil during
  a display-mode change (division by zero would NaN every size).
- `mult = perfect / uiScale` - one physical pixel at the current UI scale.
- `PixelBestSize() = clamp(perfect, 0.4, 1.15)` - the auto pixel-perfect UI scale.

Snapping helpers (all with ~0.001 epsilon guards so values sitting exactly on a pixel boundary
do not flip between reloads):

| Helper | Use |
|---|---|
| `Scale(x)` | truncate toward zero to whole `mult` units (sizes, offsets) |
| `Snap(x)` | round to nearest `mult` (save paths) |
| `ToPixels` / `FromPixels` | display in physical px / store as coords |
| `SnapForES(x, es)` | snap to whole physical px at an arbitrary effective scale |
| `SnapCenterForDim(v, dim, es)` | **centre snapping**: odd pixel dimension -> centre on a half pixel, even -> whole pixel, so both edges land on pixels. They store positions as CENTER and this is how they avoid 1 px drift per save/reload |
| `CenterToPixels` | inverse, for live readouts |
| `IsNum(n)` | finite-number check (WoW Forever's Lua errors on NaN/inf arithmetic) |

`SetUIScale(newScale)` (`PixelPerfect.lua:73`) defers via combat queue, sets UIParent scale,
updates mult, then re-snaps every stored profile position and pokes each child's global
re-apply hook. Note: `UIParent:SetScale()` does **not** fire `UI_SCALE_CHANGED` (CVar-tied), so
they debounce a width/height-match re-sync with a 0.3 s timer.

**Pixel-snap prevention**: textures default to `SetSnapToPixelGrid(true)`, which blurs/vanishes
sub-pixel-thin elements. They hook (via `hooksecurefunc` on the widget *metatable*) the image
setters `SetTexture`, `SetColorTexture`, `SetAtlas`, `SetStatusBarTexture` to call
`DisablePixelSnap` once per object (`SetSnapToPixelGrid(false)` + `SetTexelSnappingBias(0)`),
and hook `SetSnapToPixelGrid` itself to notice when Blizzard turns it back on. They deliberately
do not hook `SetVertexColor`/`SetTexCoord` (too hot). The "already done" cache is an external
weak-keyed table - never a field on the widget. They also capture the raw original
`SetTexture`/`SetColorTexture` before hooking, for pooled hot-path textures.

Removed anti-pattern worth noting: an `EnumerateFrames()` walk at load to hook every widget type
cost 248 ms of a 419 ms load and found nothing new.

**Border system** (`PP.CreateBorder` at `:728`): four `WHITE8X8` strip textures on a child
container frame (no BackdropTemplate - NineSlice corner sub-frames render as black boxes on
nameplates). Strip thickness is computed from the container's *effective scale* each snap, so
borders stay exactly N physical pixels. Details worth copying conceptually:

- per-frame border state lives in a weak-keyed side table, never on the frame (taint);
- geometry is idempotent and skipped when the post-transform values are unchanged
  (~30 API calls saved per call; this runs per aura per refresh);
- colour writes mutate a cached table in place (allocation was their #1 garbage source,
  1.2 MB/min) and skip unchanged colours - but **secret colour components are written through
  without comparing or caching** and mark the cache dirty (`:824-861`);
- a 2-frame OnUpdate re-snap after creation to catch the final effective scale;
- nameplate borders opt into a "scale guard": the container ignores parent scale, and when the
  plate is collapsed (`SetScale(0.001)` during recycle) the snap is skipped and a one-shot
  `OnShow` re-snap is armed instead;
- edge suppression flags (`_hideTop` etc.) for fused stacked bars.

`PanelPP` is a second instance of the same math for the options panel, which runs at
`baseScale * userScale` (pinned to physical pixels, not to UI scale).

### 4.2 Colours (`EllesmereUI_Colors.lua`)

- Default tables for power types, class resources (keyed by resource, not class), plus Blizzard
  class colours. User overrides in `customColors`, with a "darken %" baked into a cached palette
  rebuilt lazily when a dirty flag is set.
- Colour sections can be per-profile or shared ("Apply to All Profiles") and can "pull from"
  another profile.
- Dark Mode palette is always per-profile; consumers register refresh callbacks.
- `GetClassColorForRestrictedUnit` (`:531`) - see Section 11.

### 4.3 Fonts (`EllesmereUI_Fonts.lua`)

- Bundled font table, LSM registration, per-module font overrides with a global fallback.
- Resolution cache invalidated on profile change.
- Locale glyph fallback: a whitelist of faces whose cmap fully covers Cyrillic; CJK swaps to the
  system glyph font.
- **`SLUG` outline flag**: their outline flags are `"OUTLINE, SLUG"` / `"THICKOUTLINE, SLUG"`
  (12.x font renderer flag). A per-profile "Never Show Slug" strips it centrally via one gate
  function used at every place a flag is produced. Worth investigating what SLUG does on 12.1.5.
- `ApplyModuleFontFailsafe` swaps the shared Blizzard font *objects* behind chat, quest tracker
  and tooltips so sub-elements their per-frame styling misses still match.

### 4.4 Number format (`EllesmereUI_NumberFormat.lua`)

Delegates to the client's `AbbreviateNumbers(n, config)` with a `CreateAbbreviateConfig(rows)`
built once per session (English K/M/B; zhCN/zhTW/koKR use thousand/wan/yi tiers). Because the
work happens in C, **the client function is secret-safe**; their WoW Forever wrappers pass the
value straight through for that reason. (Their retail `AbbreviateNumber` does
`tonumber(n) or 0` first - avoid that pattern for secrets.)

### 4.5 Text tags (`EllesmereUI_TextTags.lua`)

Pure string logic, no frames/events:

- A **schema** lists tags (`hp`, `pp`, `absorb`, `healabsorb`, `name`, `target`, `level`,
  `group`) and modifiers (`max`, `abr`, `pct`, `first`, `last`, `abbr`), each key with a
  "reads" class (`hp`, `pp`, `abs`, `id`, `tgt`, `roster`) that tells the module which events
  matter, an estimated pixel width and a preview sample.
- `Bind(schema, map)` narrows the schema to keys a module can actually draw.
- `Parse(catalog, template)` turns `"[hp:abr] | [hp:pct]%"` into
  `{ fmt = "%s | %s%%", keys = {...}, reads = {...}, unknown = {...} }`, normalising modifier
  order, escaping `%` and doubling `|` (so users cannot inject colour/texture escapes). Results
  are cached (64-entry cap, transient parses for live preview do not fill the cache).
- **Secret-safety design**: the module evaluates each key to a value (possibly secret) and calls
  `fontString:SetFormattedText(parsed.fmt, v1, v2, ...)`. Secrets only ever reach the format
  setter, never Lua concatenation. The `reads` set lets the module register only needed events.

### 4.6 Glows (`EllesmereUI_Glows.lua`)

One engine for Pixel Glow (procedural ants), Action Button Glow, Auto-Cast Shine, Shape Glow,
FlipBook glows (atlas-based, C-driven AnimationGroups), and a solid "Blackout". One central
OnUpdate driver gated at ~60 fps animates every procedural glow; FlipBook glows never touch Lua
per frame. The driver hides itself when nothing is registered. Size reads guard secrets
(`:228`, `:251`, `:543`) and visibility probes are `pcall`ed and treat a secret result as
hidden (`:164`). `BindEngineHost` lets a glow be registered as an engine "shown animation" on an
aura button (Section 9). Their `tonumber(tostring(w))` on plain sizes is a "taint strip" for
tainted (not secret) numbers.

### 4.7 Rounded corners and AbsorbGlow

- `RoundCorners(owner, radius, opts)`: one nine-sliced rounded-rect **mask texture** per body
  texture (a texture takes at most 3 masks), hosted on a common ancestor; the border becomes a
  rounded fill with the body's inverse cut out. Masks are pre-generated TGAs per radius and per
  corner bitmask. Uses `SetTextureSliceMargins` + `SetTextureSliceMode`.
- `AbsorbGlow` - secret-safe overshield line. See Section 11.

---

## 5. Runtime services (performance backbone)

### 5.1 Ticker (`EllesmereUI_Ticker.lua`)

- `Tick.NewDriver(frame)` - a self-disarming OnUpdate dispatcher: dense arrays of keys and
  functions, `Add(key, fn)` idempotent (re-arming always safe), `Remove` swap-removes O(1),
  frame hides itself at zero subscribers so idle costs nothing. Safe to remove yourself inside
  your own tick (index re-check after swap).
- `Tick.Add/Remove` - the shared parent driver.
- `Tick.NewAnimTicker(frame, fn, interval)` - a looping `AnimationGroup` whose `OnLoop` fires at a
  fixed interval; the C engine sleeps between fires, so there is **zero Lua per frame**. Use for
  time-based work (drains, recharge timers, polling) rather than `C_Timer.NewTicker` or OnUpdate
  accumulators.
- `NewCombatQueue(frame)` - "run once after combat": keyed, idempotent `Defer(key, fn)`;
  registers `PLAYER_REGEN_ENABLED` only while something is pending; swaps the queue before
  draining so fns may re-defer; each fn error-isolated. Callers keep their own
  `InCombatLockdown()` check. Separate queues per addon (attribution again).

### 5.2 Mouse service (`EllesmereUI_Mouse.lua`)

One shared cursor sampler for the suite:

- Tier A `SubscribeFrame(key, fn, motionOnly)` - per-render-frame callbacks (cursor-glued
  visuals). Motion-only subscribers park after 1 s of stillness; a watch ticker re-arms them.
- Tier B `SubscribeTick(key, interval, fn)` - low-rate checks on an anim ticker (20 Hz while Tier
  A exists, 0.15 s otherwise, slows to 0.15 s after 30 s AFK, stops at zero subscribers).

### 5.3 `RunBudgeted(steps, msBudget, onDone)` (`EllesmereUI.lua:1058`)

Their defence against 12.1's "script ran too long" watchdog: runs an array of step functions in
order, at most N ms (default 8) of `debugprofilestop()` per execution, continuing via
`C_Timer.After(0)`. Nothing runs in the caller's execution (even the first slice is deferred).
Each step is `pcall`ed and the chain continues after an error. Used for manual profile swaps.

Related: the aura build worker (9.3) and the async import decoder (7.3) use the same
time-slice idea with coroutines/OnUpdate.

### 5.4 Visibility (`EllesmereUI_Visibility.lua`, `_VisibilityRules.lua`, `_Conditions.lua`)

- Rules file: dropdown values (`never/always/mouseover/in_combat/out_of_combat/in_raid/
  in_party/solo`, plus dragonriding variants for action bars), a checklist of option lanes
  (`visOnlyInstances`, `visHideMounted`, `visHideDragonriding`, `visHideNoTarget`, housing,
  vehicle, resting...), and evaluators (`CheckVisibilityOptions`, `EvalVisibilityExtended` with
  "all"/"any" matching). Secure action bars express the same rules as macro conditionals in
  state drivers (e.g. `[advflyable,flying]`, class paging `[bonusbar:N]`).
- Dispatcher: one event frame (`PLAYER_REGEN_*`, `PLAYER_DEAD` as a safety net for a missed regen,
  target, mount, zone, roster, shapeshift, resting, vehicle, glide events) that calls every
  registered updater **one tick later** (`C_Timer.After(0)`) and `pcall`s each. `IsInCombat()`
  is a cached boolean, resynced from `InCombatLockdown()` on PEW. `PLAYER_IS_GLIDING_CHANGED` is
  probed with `C_EventUtils.IsEventValid` and dependent options lock if missing.
- Mouseover: frames register `{ frame, isActive, getAlpha }`; one 0.15 s scan on the Mouse
  service uses `frame:GetRect()` vs. cursor (works on hidden frames). `isActive` results are
  cached per "generation" bumped on every dispatcher event.
- Conditions (`EllesmereUI_Conditions.lua`): a priority ladder for "conditional override groups"
  (keybind > darkmode > instance type > party > solo). Flips never happen in combat; they are
  recomputed fresh at PLAYER_REGEN_ENABLED.

### 5.5 Range (`EllesmereUI_Range.lua`)

Lazy engine (events registered only while a consumer is active) that infers distance from a
ladder of the player's own harmful spells (`C_Spell.IsSpellInRange` on the live override via
`C_SpellBook.FindSpellOverrideByID`) and a table of fixed-range items (`C_Item.IsItemInRange`).
Secret answers are skipped (fail-open to nil). **`C_Item.IsItemInRange` on a unit you cannot
attack is a protected call in combat / protected instances** (ADDON_ACTION_BLOCKED, not a secret
result), so it is gated by `UnitCanAttack` with a secret check (`Range.lua:273-292`).

### 5.6 Shared helpers (`EllesmereUI_SharedHelpers.lua`) - taint hygiene

- `NewFrameData()` - weak-keyed side table + getter; every file gets its own so fields never
  collide. **Rule: never write custom keys onto Blizzard frames.**
- `ClearFramePoints` / `SetFramePoint` / `SetFrameScale` / `HideFrame` call
  `frame.ClearAllPointsBase / SetPointBase / SetScaleBase / HideBase` when present. Edit Mode
  replaces those methods on its system frames with Lua overrides that, called from addon code,
  taint Edit Mode's anchor sweep/snap state. The `*Base` saved C methods avoid that.
  **Adopt this for any Blizzard Edit Mode system frame we move.**
- `SetElementVisibility(frame, visible)` - alpha 0 + mouse off instead of `Hide()` for frames that
  participate in anchor chains (keeps valid bounds for dependents).
- `SetEditModeChildInert` - make an Edit Mode Selection/resize child inert by alpha+mouse only.
- **Frame placers** (`SetFramePlacer`): keep an *unprotected* Blizzard frame that Blizzard keeps
  re-anchoring (e.g. GroupLootContainer) at our spot by post-hooking SetPoint and re-placing
  from one OnUpdate; refuse protected/forbidden/anchoring-restricted frames (a secret answer
  counts as "yes, refuse").
- `EllesmereUI.IsSecret(v)` and `EllesmereUI.PlainString(v)` (`:920-927`) - the suite-wide secret
  helpers (test secrecy before any comparison: comparing a secret string raises).

### 5.7 Escape handling and printing

- One `UISpecialFrames` entry (`EllesmereUI_EscapeProxy`) fronts every EUI window; frames opt in
  with `RegisterEscapeClose(frame, { onEscape, modal, padOnly, notOwned, cursor })`. Avoids
  dozens of UISpecialFrames entries and supports controller Back.
- `EllesmereUI.Print` uses `DEFAULT_CHAT_FRAME:AddMessage`, never global `print` (which taints the
  chat frame), and drops messages entirely in raid combat, active M+ and PvP combat to avoid
  tainting the whisper/temporary-window chain.

---

## 6. Unlock Mode (movers, anchors, snapping)

~14k lines. The single most important subsystem for us to match.

### 6.1 Structure and load strategy

- `EUI_UnlockMode.lua` has a small **non-deferred header**: the registration API, listener API,
  early stubs (`ReapplyOwnAnchor`, `NotifyElementResized`, `IsUnlockAnchored`), screen-edge
  anchor targets, and two login handlers. Everything else is wrapped in
  `EllesmereUI._unlockCoreInit = function() ... end`, which runs on first
  `EllesmereUI:EnsureUnlockCore()` (at PLAYER_LOGIN, synchronously, so protected children can be
  anchored before combat lockdown re-engages after an in-combat reload).
- The deferred body builds a shared `UM` state table and runs the split parts in order:
  `Anchors(UM)`, `Positions(UM)`, `Tools(UM)`, `PointPicker(UM)`, `Movers(UM)`, `Session(UM)`,
  `Filter(UM)`. Parts are registered on the private `ns` table, not a public one, so another
  addon cannot wrap them.
- A fallback PEW handler runs the full position pass at +1.5 s if the Cooldown Manager module
  (which normally drives the final pass after its async icon population) is absent.

### 6.2 Element registration contract

Modules call `EllesmereUI:RegisterUnlockElements(list, folder)`; `MakeUnlockElement(opts)` is a
**whitelist** constructor (unknown fields are dropped silently). Fields:

| Field | Meaning |
|---|---|
| `key`, `label`, `group`, `order` | identity and menu sorting |
| `getFrame(key)` | the real frame to move |
| `getSize(key)` -> w, h[, centerYOff] | authoritative size (may differ from frame rect) |
| `savePos(key, point, relPoint, x, y, origPoint, origRel)` | persist + apply |
| `loadPos(key)` -> `{point, relPoint, x, y}` | read stored position |
| `clearPos(key)`, `applyPos(key)` | reset / re-apply |
| `setWidth`, `setHeight` | resize from the mover cog (module rebuilds) |
| `isHidden`, `isAnchored`, `keepMoverWhenAnchored` | mover availability |
| `onLiveMove(key)` | called after every live placement (drag frame, nudge) |
| `ownsPosition` | module alone places it (e.g. main chat); links never move it |
| `isPositionHeld` | something else places it right now (quest tracker in Blizzard's managed container) |
| `noSpecLayout` | per-spec layouts never bank this element |
| `linkedKeys`, `linkedDimensions` | elements that move/size together |
| `noResize`, `allowMatchSource`, `noSizeMatchTarget`, `matchUnavailable` | width/height match rules |
| `noAnchorTarget`, `noAnchorTo` | anchor rules |
| `sizeFixedByLook`, `getSettingSize`, `getInsets`, `getBottomExtra`, `getMatchPad` | visual vs. logical rect corrections |
| `detachedMover` | frame refuses dependents (forbidden layout aspect) - mover positioned absolutely instead of anchored to it |
| `loadRawPos` / `saveRawPos` | raw stored form for spec layers |
| `moverBg`, `moverTooltip`, `subtitle` | mover cosmetics |
| `folder` | owning module for per-module layout export |

Re-registering marks the order dirty; the wrapper in `_Anchors` also installs `OnSizeChanged`
and `SetPoint` post-hooks on each element's frame 0.1 s later (skipped for chat and quest
tracker - taint risk).

Cross-addon listeners: `RegisterUnlockModeListener(owner, fn(active, closeAction))` with
`closeAction` in `"exit" | "save" | "discard"`. Combat suspension does not count as close.

### 6.3 Position storage convention

**Every element's position is stored as CENTER/CENTER offsets from UIParent's centre, in
UIParent units** (`Positions.lua:2209-2285`). `ConvertToCenterPos` converts any point by reading
the live frame's edges (scaled by `frame:GetEffectiveScale()/UIParent:GetEffectiveScale()`), or
arithmetically from size when the frame is not laid out.

On apply (`ApplyCenterPosition`, `:2289`):

1. If the element is anchored (via unlock link or module option), skip - the anchor owns it.
2. Otherwise choose the SetPoint anchor from the **grow direction**: grow RIGHT -> anchor LEFT edge
   at `cx - w/2`, grow DOWN -> TOP edge, etc.; CENTER otherwise. A stored `growEdge` (absolute
   edge offset) wins when present so width changes do not move the fixed edge.
3. Add any registered "extra offset" (render-only displacement).
4. Snap with `SnapCenterForDim` (CENTER) or `SnapForES` (edge), against UIParent's grid.
5. Convert into the frame's own scale if it has one (`fRatio`), then
   `ClearFramePoints`/`SetFramePoint(frame, anchor, UIParent, "CENTER", x, y)`.
6. In combat with a protected frame: defer through the unlock combat queue keyed by frame.

Note the half-pixel subtlety: odd-pixel-height frames have centres at `n + 0.5`; they keep raw
`w/2` in edge math (never `floor`) so the edge lands exactly on a pixel. Saving snaps nothing
extra.

Action bars without a registered element fall back to `EAB.db.profile.barPositions`.

### 6.4 Anchoring (links between elements)

`EllesmereUIDB.unlockAnchors[childKey]` (live; snapshotted per profile in `unlockLayout`):

```
{ target = "player", side = "LEFT"|"RIGHT"|"TOP"|"BOTTOM"|nil,
  offsetX, offsetY,             -- relative to stable edges of the target
  mode = "POINT", sourcePoint, targetPoint,   -- explicit 9-point links
  fallback = {...},             -- alternate target when the primary is hidden
  edge = { key = "SCREEN_LEFT", offset },     -- cross-axis screen-edge pin
  edgeOffX, edgeOffY, savedEdge, tgt*        -- growth-edge pins / follow baselines
}
```

Key design decision: **anchors are resolved by computing an absolute position and calling
SetPoint against UIParent**, not by `SetPoint(child, target)`. Benefits: no anchor-dependency
chains between frames of different addons/protection states, no "anchor family connected"
errors, works when the target is protected or has a forbidden layout aspect. Costs: they must
propagate manually.

Propagation:

- `PropagateAnchorChain(parentKey, visited, axis)` walks children recursively (with cycle guard).
- `SetPoint` post-hooks + `OnSizeChanged` hooks on every registered frame feed
  `NotifyElementMoved` / `NotifyElementResized`, which coalesce into one
  `C_Timer.After(0)` batch (`ScheduleAnchorBatch`) and skip when the position changed by less
  than 0.5 px (convergence guard; `ApplyAnchorPosition` itself also skips no-op SetPoints).
- `ReapplyAllUnlockAnchors(Forced)` applies everything in dependency-depth order.
- Screen edges are registered as hidden 1-unit elements (`SCREEN_LEFT/RIGHT/TOP/BOTTOM`) so an
  element can anchor to a screen edge; a UIParent-sized watcher re-runs those chains on resize.
- Width/height **matching** (`unlockWidthMatch[child] = target`, with `...MatchExtra` px) writes
  the matched size into the element's own settings and propagates in dependency order with
  cycle detection (`WouldCreateCycle`, `BreakMatchCycles`).
- "Override anchors" (per spec/condition group) and "fallback anchors" are shown as draggable
  ghost movers at 75% opacity.
- Combat: any apply skipped by lockdown is **parked** (`_AnchorPark.Park(key)`) and the whole
  dependency-sorted pass runs once on PLAYER_REGEN_ENABLED. A target whose edges read secret
  (riding an engine aura container under restriction) also parks (`Positions.lua:1106-1117`).

### 6.5 Point anchors and the point picker

Newer "explicit point" links (`mode = "POINT"`, `PointAnchors.lua`): the user picks one of 9
points on the source and on the target (TOPLEFT ... BOTTOMRIGHT as `{x,y}` fractions). `Capture`
reads both points' live positions and stores the offset; `Place` computes the source point's
target position and writes a single SetPoint (UIParent CENTER-relative, or relative to a
"follow" frame for bottom-edge targets that grow). Insets are honoured. Cycle walk is capped at
100 links. The picker (`PointPicker.lua`) draws 9 dots on the mover only - "gameplay frames
receive no mouse hooks". A dependency walk (`FrameDependsOn`, depth 30) refuses links that would
create anchor loops, treating secret/pcall-failing `GetPoint` reads as "depends".

### 6.6 Movers (`EUI_UnlockMode_Movers.lua`)

One mover frame per registered element:

- Overlay frame sized to the element, `SetMovable(true)`, `RegisterForDrag("LeftButton")`,
  dark overlay at alpha 0.55 / hover 0.85 / drag 0.95, label, coordinate text, hover-expanded
  toolbar (width match, height match, anchor-to, grow direction, cog, element options link).
- **Drag is manual, not `StartMoving`**: OnDragStart records cursor-to-centre offset (cursor via
  `GetCursorPosition()/UIParent:GetEffectiveScale()`), then an OnUpdate each frame computes the
  raw centre, applies Shift-axis lock (axis chosen after 3 px movement), runs `SnapPosition`,
  clamps to screen, **moves the real frame live** (TOPLEFT to UIParent, `SnapForES` unless an
  edge snap locked that axis), then anchors the mover to the real frame's TOPLEFT for pixel
  alignment, calls `onLiveMove`, propagates the anchor chain and redraws alignment guides. A
  safety check stops the drag if the button is no longer down.
- OnDragStop: re-anchors the mover CENTER, detects real movement (>0.5 px), and writes a
  **pending** position (not saved) from the bar's actual `GetPoint(1)`; anchored children get
  their offsets recaptured from real edges.
- Link buttons forward drags via OnMouseDown/Up with a 3 px threshold (WoW's drag system fires
  OnDragStop immediately when started from a child button).
- Mouse-wheel overlap cycling (configurable modifier) for stacked movers.
- Every drag/nudge path is gated with `InCombatLockdown()`.

### 6.7 Snapping, grid, nudge (`EUI_UnlockMode_Tools.lua`)

- Grid: BACKGROUND-strata frame, 1-physical-pixel lines (`mult` wide) every 32 px*mult, centre
  lines brighter, modes `disabled/dimmed/bright`, tinted with the accent colour. Lines are pooled
  textures with pixel snapping disabled.
- `SnapPosition(dragKey, cx, cy, halfW, halfH)`: find the closest visible mover by 2D
  edge-to-edge distance (excluding the dragged element's descendants and siblings in the anchor
  tree; a per-mover snap target or `"_disable_"` overrides), then test 3x3 X pairs
  (left/centre/right) and 3x3 Y pairs within 6 px (`SNAP_THRESH`), snap, and record guide line
  positions and "axis locked" flags so pixel snapping does not undo an edge match.
- Selection + arrow keys: an invisible keyboard-enabled frame captures arrows to nudge the
  selected mover by one pixel (anchored elements adjust their link offsets instead).
- Overlays for Blizzard-owned elements that EUI cannot move show an info hover instead.
- Filter box on the banner hides movers whose label lacks the typed words.

### 6.8 Session lifecycle (`EUI_UnlockMode_Session.lua`)

- Open (`ns.OpenUnlockMode`): refused in combat. Remembers the open options page to return to,
  closes spec-override edit sessions first (so the snapshot is canonical), snapshots positions,
  anchors, sizes, matches and grow directions, validates/prunes stale links, notifies modules via
  global hooks (`_EAB_UnlockModeOpen`, ...), hides unit frame auras and the objective tracker
  (**alpha 0 + mouse off, never `Hide()`**, with a `SetAlpha` hook to keep it hidden; state in the
  side table), shows a full-screen FULLSCREEN_DIALOG overlay (mouse disabled so clicks pass
  through), grid, HUD banner, animated lock graphic, one-time tip.
- All edits live in `pendingPositions`; nothing touches the DB until **Save & Exit**
  (`CommitPositions`): saves every pending entry through `SaveBarPosition` (which converts to
  CENTER and calls the element's `savePos`), suppresses per-save rebuilds then runs one rebuild,
  force-reapplies all anchors.
- Exit without saving -> `RevertPositions` restores every snapshot. Unsaved changes -> confirm
  popup (Save & Exit / Exit Without Saving / dismiss = stay).
- **Combat**: PLAYER_REGEN_DISABLED -> `SuspendForCombat` hides all unlock UI, restores action bar
  mouseover alpha, but keeps the session (snapshots, pending edits). PLAYER_REGEN_ENABLED + 0.5 s
  -> `ResumeAfterCombat` re-shows everything, resyncs movers and re-centres anchors; a pull
  during the 0.5 s stays suspended.
- Spec switch while unlocked -> `ForceCloseUnlockDiscard` (edits belong to the outgoing spec's
  layout).

### 6.9 Blizzard Edit Mode coexistence

- Moves Edit Mode system frames through `SetPointBase`/`ClearAllPointsBase` (5.6).
- For action bars that Blizzard re-anchors via `ApplySystemAnchor`, a `hooksecurefunc` post-hook
  re-applies the saved EUI position **on the next tick** (deferred to avoid tainting the secure
  context), parking it if in combat (`Positions.lua:2765`).
- Applying a Blizzard Edit Mode layout from a preset string uses
  `C_EditMode.ConvertStringToLayoutInfo` then writes the layout and calls `SetActiveLayout`,
  deliberately not `EditModeManagerFrame:ImportLayout` (`Profiles.lua:4774-4786`).

---

## 7. Profiles, import/export, sync

### 7.1 Profile switching (`EllesmereUI_Profiles.lua`)

- `ADDON_DB_MAP` lists every module `{ folder, display, svName, suffix }`; `suffix` gives a
  rename-immune canonical key so strings work across suite and standalone builds.
- `SwitchProfile(name)` -> sets `activeProfile` -> `RepointAllDBs(name)`: for every db in the
  Lite registry, `db.profile = profiles[name].addons[folder]` (create + merge defaults), then
  restores the profile's `unlockLayout` into the live `unlockAnchors/...` tables, fonts, colours,
  dark mode, accent. Modules keep their `db` object; only `db.profile` changes, so a module must
  always read `self.db.profile` fresh (never cache the profile table).
- `RefreshAllAddons(budgeted)`: applies spec override values first, sets suppression flags,
  re-resolves accent, then runs a fixed list of step functions each calling a child's global
  apply hook (`_ERB_Apply`, `_ECME_Apply`, `_EUF_ReloadFrames`, ...), optionally through
  `RunBudgeted`; then a double `C_Timer.After(0)` tail re-applies saved positions and anchor
  offsets once rebuilds settle.
- Font, window-skin or "style" changes need a reload; they detect that up front and prompt.
- Unlock layout snapshots must hold **baseline** links (not a live spec layer) - a lot of their
  spec-override complexity is about not corrupting this.

### 7.2 Spec-based profiles

- `EllesmereUIDB.specProfiles[specID] = profileName`; `lastSpecByChar` caches the spec per
  character because the live spec API can be nil early for new characters.
- `PreSeedSpecProfile` runs just before OnEnable (Lite calls it) so modules build with the right
  profile on first paint.
- Runtime handler on `PLAYER_SPECIALIZATION_CHANGED` (unit `"player"` only) and PEW; **in combat
  the whole switch is deferred** to PLAYER_REGEN_ENABLED and re-resolved then.
- Profile keybinds: hidden buttons + `SetOverrideBindingClick`.

### 7.3 Export / import format

- Payload `{ version = 3|4, type = "full", data = profileData, client = "forever"|nil }`.
  Version 4 marks strings containing point-anchor links so old builds refuse them.
- Custom serializer (no AceSerializer): type-tagged, length-prefixed strings
  (`s<len>:<bytes>`), `n<num>;`, `T`/`F`/`N`, tables as `{ ...array... K key value ... }`.
  Deserializer flags malformed input instead of erroring (because the async path yields inside it).
- Pipeline: `Serialize -> LibDeflate:CompressDeflate -> LibDeflate:EncodeForPrint`, prefixed
  `!EUI_`. Decode reverses it and validates version range.
- **Async decode** (`DecodeImportStringAsync`, `Profiles.lua:2979`): a coroutine on a shared
  OnUpdate, 8 ms budget per frame; printable decode in 64 KB slices; decompression prefers the
  client's native `C_EncodingUtil.DecompressString(data, Enum.CompressionMethod.Deflate)`
  (pcall, falls back to LibDeflate); deserializer yields every 2048 values via a hook.
- Export options: subset of modules, include layout, include CDM spells per spec, include
  account globals, include overrides, include Blizzard skin globals. Private per-character data
  (gold ledger etc.) is always stripped on export and again on decode.
- A separate "full account" export copies the whole store minus per-character data.
- Import reconciles unknown SharedMedia names, fixes class colours, merges unlock layouts per
  module, and finishes with a reload prompt.
- Wago UI Packs integration: `DecodeProfileString`, `SetProfile`, `GetProfileKeys`,
  `GetCurrentProfileKey`, `OpenConfig`, `CloseConfig`; plus an interactive import API for partner
  addons.

### 7.4 Profile sync (`EllesmereUI_ProfileSync.lua`)

"Mirror groups": `EllesmereUIDB.syncedModules[folder] = { [profileName] = true }`. When the
active profile is a member, its module data is copied to the other members on sync click, logout
and profile switch (two-way only among members). Modules register exclusion keys
(`RegisterSyncExclusions(folder, { "bars.*.growDirection", ... })` - dot paths with `*`
wildcard), and any key that has a spec/conditional override entry is excluded automatically.

### 7.5 Spec overrides and conditional overrides

Instead of one profile per spec, a profile can hold per-spec-group values for individual
settings:

- Storage on the profile root: `specOverrides = { { label, module, page, section, group,
  values = { default = {[fkey]=v}, [specID] = {[fkey]=v} } } }`, `specOverrideGroups`,
  `condOverrideGroups`. `fkey = folder .. "\31" .. path` with path segments joined by `"\30"`
  (control characters so keys containing dots are safe), and a sentinel string for "key absent".
- "Editing as <group>": the group's values are swapped into the live profile; the user edits with
  the normal widgets; a 0.4 s `C_Timer.NewTicker` watcher diffs addon profiles and attributes
  each change to the options row under the mouse (or the open dropdown/colour picker).
  Unattributed writes are ignored. On exit, captured paths are harvested back into every member
  spec and the real spec's values restored.
- Save-on-leave / apply-on-enter on spec change, unlock layout layers per group, gold borders on
  overridden option rows, a management list page.
- Some modules are blacklisted (bags, meters, chat, QoL...).

Honest assessment: extremely powerful but enormous (~10k lines) and the source of many of their
corruption bugs (comments are full of "the default-layout corruption class"). See
recommendations.

---

## 8. Options panel, plugins, LoadOnDemand

- The panel shell (`EllesmereUI_Panel.lua`, 6k lines) is resident; **all widgets and every
  module's options pages live in the LOD `EllesmereUIOptions` addon**, loaded on first panel
  open via `C_AddOns.LoadAddOn`. Nothing of it is parsed at login.
- Deferred-init slots: options files append `EllesmereUI._deferredInits[...]`; `EnsureLoaded()`
  drains them after loading the options addon. Unlock core has its own slot because it must run
  at login without the options addon.
- Child modules' slash commands moved into the LOD addon, so the parent registers bootstrap
  handlers for each that refuse in combat, defer one tick (slash dispatch runs inside the chat
  edit box execution, which has its own watchdog budget), load the options addon, then
  re-dispatch to the real handler.
- Panel closes itself on PLAYER_REGEN_DISABLED; opening is refused in combat.
- Page cache keyed `module::page`; widgets register refresh callbacks so revisits update values
  in place; a frame pool in the options addon re-dresses page frames instead of creating new ones
  (frames are never freed in WoW).
- Global search indexes every widget row (label, tooltip, section); un-opened pages are indexed
  by a hidden "pre-build pass" that runs page builders with a stub widget factory.
- **Plugin API** (`PLUGINS_API.md`, `RegisterPlugin(id, spec)`): third-party addons get their own
  sidebar section with modules and pages built by `buildPage(pageName, parent, yOffset)` using
  `EllesmereUI.Widgets`. Strict validation (id format, label length, reserved names), snapshot at
  registration, all callbacks `pcall`ed, `IsSearchPrebuild()` so builders can skip side effects.
- Anti-hijack: core module registration only accepted from the options addon during a
  "registration window"; the caller folder comes from `debugstack(2,1,0)`, and
  `issecurevariable(t, key)` identifies which addon last wrote a field (taint names the writer).
  If someone replaced `EllesmereUI.RegisterModule`, the core puts its own back and records the
  offender, then shows a once-per-session "this addon needs an update" popup.
- **Skinning API** (`SKINNING_API.md`, `RegisterSkin(name, fn(S))`): third parties hand frames to
  primitives (`S.Shell`, `S.Button`, `S.EditBox`, `S.ScrollBar`, `S.Tab`, ...). Primitives are
  idempotent, taint-safe (side-table state, alpha-only art removal, no Hide/SetParent on others'
  frames), registration queues until the skin module drains it at PLAYER_LOGIN.
- Version mismatch check: each addon writes its version into a global table at load; 2 s after
  login, a popup lists modules whose version differs from the newest.

---

## 9. AuraKit: 12.1 engine aura containers (`EllesmereUI_AuraKit.lua`)

The biggest Midnight-specific discovery in the core. 12.1 ships **engine-driven aura
containers**: an `AuraContainer` frame type from the `Blizzard_AuraContainer` addon (template
`CustomAuraContainerTemplate`) that does aura parsing, filtering, sorting, layout and button
updates in C, identically in and out of restricted (secret) content. EUI routes *every* aura
display in the suite through AuraKit.

APIs observed (method names on the container / button):

- container: `SetUnit(unit)`, `UpdateAllAuras()`, `AddAuraGroup(key, filter, opts)`,
  `AddAuraSlot(key, filter, opts)`, `SetAuraGroupMaxFrameCount`, `SetAuraGroupEnabled`,
  `SetAuraSlotEnabled`, `SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, opts)`,
  flow layout setters `SetFlowLayoutAnchorPoint/GrowthDirection/...` (older builds:
  `SetAuraLayout*`), item enchantment sources (`SetItemEnchantmentLayout/SortMethod`).
- group opts: `maxFrameCount, sortMethod, sortDirection, candidateFilters, initializeFrame,
  layout = { elementWidth, elementHeight, elementSpacing, lineSpacing, ... }`.
- button: `SetIcon(tex)`, `SetDurationCooldown(cooldownFrame)`, `SetApplicationCount(fs, {formatter})`,
  `SetApplicationBar(statusBar, { maxApplications, interpolation })`,
  `SetDurationText(fs, opts)`, `SetCancelAuraButtons(...)`, dispel-type texture styles
  (`Enum.CustomAuraButtonDispelTypeTextureStyle.Icon`), `AddAuraShownAnimation(animGroup)` /
  `RemoveAuraShownAnimation` (12.1.5).

Rules they learned the hard way:

- **Filter strings must be byte-identical to share a parse.** `AK.Filter(...)` canonicalises:
  HELPFUL/HARMFUL first, then remaining tokens sorted (negations after their bare token), cached.
- Groups are **add-only**; "disable" = cap 0 (on 12.1.5 `SetAuraGroupEnabled(false)` also stops
  parsing; a container with everything off stops listening to UNIT_AURA).
- Buttons are pre-created in engine batches of 10 when a group is declared; `initializeFrame(button)`
  runs once per button. **The initializer is the only window where touching the button is always
  legal.** Right after it returns, the engine applies `DenyTaintedAccessWhenAurasAreSecret` to the
  button: while auras are secret, addon reads/writes on the button object are refused. Therefore:
  create every child region (icon texture, cooldown, border host, dispel holder, text carrier) in
  the initializer; cache `button:GetFrameLevel()` there; keep per-button state in a weak side
  table; style regions first and only then register them (each `Set*` registration immediately
  runs an update that calls `SetText` on your font strings - an unstyled font string errors).
- Child holders over aura buttons must `EnableMouse(false)` or they eat nameplate clicks.
- Any error inside a registration aborts the engine's whole `CreateFrameBatch`, killing the
  group. So every novel engine call is `pcall`ed with stepwise degradation
  (`SetDurationTextSafe`: full opts -> without colour curve -> bare).
- Restyles that hit a refused call are deferred per style key and re-run at the **restriction
  lift**: a watcher on `PLAYER_REGEN_ENABLED`, `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`,
  `ENCOUNTER_END`, and `CVAR_UPDATE` for `*RestrictionsForced*` dev CVars.
- `AK.AurasRestricted()` prefers `C_Secrets.ShouldAurasBeSecret()`, falls back to
  `pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")` (throws while restricted).
  Only the "restricted" answer is cached per frame (error construction is the cost).
- Container creation **is combat-legal since build 68914** (their earlier "queue until regen"
  gate left bars blank after an in-combat reload).
- Containers are never destroyed (frames are permanent); `ReleaseContainer` hides it, switches its
  groups/slots off and untracks buttons so restyle passes stop touching zombies.
- Frames anchored inside a container's button tree report **secret geometry** (`GetLeft`,
  `GetWidth`...) under restriction; unlock mode checks for this everywhere (Section 11).

Duration text: `SetDurationText` takes a formatter evaluated engine-side against the (possibly
secret) remaining time. They build a banded `C_StringUtil.CreateNumericRuleFormatter()` with
`SetBreakpoints{ {threshold, format, step, rounding, components={{div=..},{mod=..}}} }` mimicking
Blizzard's buff text (seconds, `m` from 90 s, `h`, `d`, optional `m:ss` precise band), with a
`C_StringUtil.CreateSecondsFormatter()` + `C_CurveUtil.CreateCurve()` fallback. Update interval and
colour-by-remaining go through a `C_DurationUtil.CreateDurationTextBinding()` passed as
`opts.binding`, colour as `opts.textColor = { curve = colorCurve, property =
Enum.DurationTextBindingProperty.RemainingDuration }` (enum value 0 - never `and/or` it).

Build scheduler: `AK.NewBuildWorker()` (one per module, frame created in the module's main chunk
for attribution) with FIFO jobs and **one shared per-frame budget** (8 ms; 250 ms "turbo" for 15 s
after login outside raids and out of combat). Jobs may return `"again"` to requeue; jobs killed by
the "script ran too long" watchdog are requeued up to 3 times. No work in the PEW handler itself.

Also in AuraKit: offensive dispel capability (purge/soothe/spellsteal known?) computed from the
spellbook, which "asks what the player knows, never what an aura is", so it works in restricted
content.

---

## 10. Small but notable subsystems

- **Kick** (`EllesmereUI_Kick.lua`, `_KickData.lua`): KickData is a curated 12.1.5 table of every
  interrupt (class, base cd, specs, talent, pet) with a season-update note. `RefreshKickAbility`
  resolves the player's kick, pet spellbook first (`C_SpellBook.IsSpellKnownOrInSpellBook(id,
  Enum.SpellBookSpellBank.Pet)`), on `SPELLS_CHANGED` and `UNIT_PET` (player). Cast-bar
  "kick ready" tint is secret-safe (Section 11).
- **Secure unit menu proxies** (also in Kick.lua): 12.0.7 gates `SecureUnitButton_OnClick` menu
  actions behind ClickBindings; opening from insecure Lua taints the menu. Fix: a hidden
  `SecureActionButtonTemplate` child per unit button with `type*="togglemenu"`,
  `useparent-unit=true`, `useOnKeyDown=false`, globally named so the unit button can drive it with
  `*type2="macro"`, `*macrotext2="/click <proxy>"` (12.1's "click" secure action is broken by a
  Blizzard typo). Same for non-left-click "target" bindings. A `UnitPopup_OpenMenu` post-hook
  repairs a classifier misfire (raid player shown a pet menu).
- **WarriorCharges**: Whirlwind/Sweeping Strikes buffs are not whitelisted (aura reads return nil
  even while up), so they use one-slot aura containers with `includeSpellIDs` and
  `SetApplicationBar` - the engine writes the true stack count into a StatusBar.
- **ManaRegenSpark / SpellCostPrediction** (WoW Forever only): mana is secret, so the spark sweep is
  a StatusBar driven by `SetTimerDuration(durationObj, Enum.StatusBarInterpolation.Immediate,
  Enum.StatusBarTimerDirection.ElapsedTime)` and the cost segment only ever receives secret
  values through `SetMinMaxValues`/`SetValue`.
- **GoldLedger**: account-level, kept out of profile exports.
- **Uninstall**: every CVar / Edit Mode / chat-font change goes through setters that record the
  original value and EUI's value; a value is only restored while it still equals EUI's (player
  changes are respected); CVars of a disabled module are restored at login.
- **BlizzardParty**: hides `CompactRaidFrameManager` by reparenting to a hidden frame (SetParent is
  combat-blocked, so it waits on the combat queue).
- **Locale**: `L(s)` is identity for English; translation data is in the LOD locales addon loaded
  only for non-English clients; guards skip non-strings, secrets, numbers and letterless strings.

---

## 11. Secret values / Midnight API usage (exhaustive for the core)

Counts across the parent: `issecretvalue` appears ~198 times. They polyfill once per file:
`local issecretvalue = issecretvalue or function() return false end` (or test
`issecretvalue and issecretvalue(x)` inline).

### 11.1 Restricted API calls and how each is used

| API | Where | Pattern |
|---|---|---|
| `C_CurveUtil.EvaluateColorValueFromBoolean(bool, valueIfFalse?, valueIfTrue?)` | `Kick.lua:115-125`, `Colors.lua:534-562`, `UICore.lua:1372-1381` | Pick a colour component from a **secret boolean** in C. Called once per r/g/b; the three results (possibly secret) go straight into `SetStatusBarColor`/`SetTextColor`. Note arg order as used: `(bool, base, ready)` returns `ready` when true. |
| `C_Spell.GetSpellCooldownDuration(spellID)` -> duration object; `:IsZero()` | `Kick.lua:118-122` | Kick-ready tint without reading the cooldown: `IsZero()` returns a (secret) boolean fed to the curve util. |
| `UnitIsUnit(a, b)` | `Colors.lua:550`, `EllesmereUI.lua:2068` | Returns a **secret boolean** for restricted identities, or **nil** (not an error) when the comparison is refused. Always `type(x) == "boolean"` check (type works on secrets) and `issecretvalue` before branching. |
| `C_Secrets.CanCompareUnitTokens(a, b)` | `Colors.lua:545-550` | Pre-check before `UnitIsUnit`. Measured in a 12.1 dungeon: only "is this unit the player?" is answerable (as a secret) under identity restriction; all other pairings are refused. |
| `C_ClassColor.GetClassColor(secretToken)` | `Colors.lua:542` | Accepts a secret class token (UnitClass returns secret tokens for restricted units like targettarget). A secret cannot be a table key, so user palette lookup is impossible; they fold player identity via curve util to recover the custom colour. |
| `C_Secrets.ShouldAurasBeSecret()` | `AuraKit.lua:2352` | Primary restriction probe. |
| `pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")` | `AuraKit.lua:2357` | Fallback probe: throws while restricted. |
| `C_UnitAuras.GetPlayerAuraBySpellID(id)` | `EllesmereUI.lua:2121-2186` | Only for **Blizzard-whitelisted** auras (Maelstrom Weapon 344179, Tip of the Spear 260286, Devourer 1225789/1227702/1217607) whose data stays readable. Non-whitelisted auras return nil while up (WarriorCharges header). |
| `C_Spell.GetSpellCastCount(228477)` | `EllesmereUI.lua:2151` | Vengeance soul fragments: returns a secret; caller must feed it to a StatusBar. |
| `CreateUnitHealPredictionCalculator()` + `UnitGetDetailedHealPrediction(unit, nil, calc)` + `calc:GetDamageAbsorbs()` | `AbsorbGlow.lua:43-54, 101-102` | Calculator configured once: `SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)`, `SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)`. Second return of `GetDamageAbsorbs()` is then the **overshield boolean** (secret). |
| `frame:SetAlphaFromBoolean(bool, alphaTrue, alphaFalse)` | `AbsorbGlow.lua:95-107` | Show/hide from a secret boolean. Comment: works on **frames**; on a texture it rendered nothing on this client - so each line sits on its own frame. |
| Hidden "gate" StatusBar | `AbsorbGlow.lua:29-38, 122` | Trick: a 0..1 StatusBar fed the raw (secret) absorb amount is full for any shield and empty without one; a texture anchored to its fill texture appears only when a shield exists - **no Lua comparison of the secret needed**. |
| `C_StringUtil.CreateNumericRuleFormatter()` / `:SetBreakpoints` | `AuraKit.lua:88-142`, `WarriorCharges.lua:270-277` | Engine-side formatting of secret numbers (durations, stack counts; also gives "0" display which the engine otherwise hides). |
| `C_StringUtil.CreateSecondsFormatter()` + `C_CurveUtil.CreateCurve()` | `AuraKit.lua:146-160` | Fallback duration formatter (`SetMaxIntervalCurve`). |
| `C_DurationUtil.CreateDurationTextBinding()` | `AuraKit.lua:1179-1193` | Binding with `SetFormatter`, `SetUpdateInterval`; passed as `opts.binding` to `button:SetDurationText`. |
| `C_DurationUtil.CreateDuration()` + `dur:SetTimeFromStart(start, len)` + `StatusBar:SetTimerDuration(dur, Enum.StatusBarInterpolation.Immediate, Enum.StatusBarTimerDirection.ElapsedTime)` | `ManaRegenSpark.lua:46-57, 115, 133` | Engine-animated timer fill: no Lua per frame. |
| `Enum.StatusBarInterpolation.Immediate` in `SetApplicationBar` opts | `WarriorCharges.lua:212-213, 608-609` | Engine writes aura stacks into a StatusBar. |
| `issecrettable(obj)` | `PixelPerfect.lua:307, 351` | Skip widget objects that are themselves secret tables before touching them. |
| `canaccesstable(t)` | `SignupHelpers.lua:52` | `C_LFGList.GetSearchResultInfo` result may be secret/inaccessible during chat messaging lockdown; guard `type(info)=="table" and not issecretvalue(info) and canaccesstable(info)`. |
| `C_Spell.GetSpellPowerCost(id)` | `ManaRegenSpark.lua:62-75`, `SpellCostPrediction.lua:71-79` | `c.type` and `c.cost` may be secret; a secret cost counts as "costs mana". |
| `C_Spell.IsSpellInRange` / `C_Item.IsItemInRange` | `Range.lua:249, 264-273, 411` | Secret results skipped (fail-open nil). |
| `UnitCanAttack` | `Range.lua:288`, `SharedHelpers.lua:795` | Secret -> treat as "no / unknown". |
| `UnitGroupRolesAssigned` | `EllesmereUI.lua:2075-2103` | Secret for identity-restricted units -> return `nil, true` ("unsure"). |
| `UnitAffectingCombat("player")` | `AuraKit.lua:2270-2271` | Can be secret; treated as false. |
| `GetSpellCritChance` / `GetRangedCritChance` / `GetCritChance` / `UnitSpellHaste` / `GetMeleeHaste` / `GetRangedHaste` | `EllesmereUI.lua:1999-2050` | Stats may be secret in combat: they remember the last plain "which stat is highest" pick and reuse it. |
| `UnitEffectiveLevel`, unit level, `UnitHonorLevel` | `SharedHelpers.lua:770, 791-795, 834` | Secret -> no colour / no badge. |
| `UnitName` / names, `UnitGUID` | `UICore.lua:1175, 1234`, `EllesmereUI.lua:1254-1261`, `Kick.lua:190`, `MenuFallbacks.lua:364` | Secret names pass through untouched (no `==`, `:sub`, concatenation). |
| `UnitClass` token | `Colors.lua:512` | Secret token -> skip candidate. |
| FontString `GetStringWidth` / `GetStringHeight` | `UICore.lua:328-337` | Tooltip auto-size: secret metrics fall back to fixed size. |
| Frame geometry `GetLeft/GetTop/GetWidth/GetHeight/GetEffectiveScale/GetPoint/GetNumPoints/IsVisible/GetAlpha/IsForbidden/IsProtected/IsAnchoringRestricted` | Unlock files (`Anchors.lua:1198, 1550, 1944`; `Positions.lua:567, 810, 1106-1165, 1660-1838`; `Movers.lua:117, 2017`; `Tools.lua:810`; `PointAnchors.lua:27, 94, 193`; `PointPicker.lua:43-46`), `Glows.lua:164, 228, 251, 543`, `RoundedCorners.lua:189`, `SharedHelpers.lua:94, 116, 157-162, 232-291` | Frames inside an engine aura container (or anchored to one) have **secret rects** under aura restriction; Edit Mode / layout frames can read secret alpha. Every geometry read that feeds arithmetic or comparison is checked; on secret: park until regen, skip the compare, or use a fallback size. |
| `GetGoldLedger` money values | `GoldLedger.lua:37-40` | `IsUsable(v)` = number and not secret. |
| `L(s)` translator | `Locale.lua:64` | Secret strings returned untranslated. |

### 11.2 Child-addon usage seen while cross-checking (for context)

Counts across all EllesmereUI addons (not just the core): `SetAlphaFromBoolean` 75,
`C_Spell.GetSpellCooldownDuration` 54, `SetTimerDuration` 44,
`C_CurveUtil.EvaluateColorValueFromBoolean` 40, `SetCooldownFromDurationObject` 38,
`UnitPowerPercent` 37, `UnitHealthPercent` 36, `CurveConstants.ScaleTo(100)` 21,
`C_CurveUtil.CreateColorCurve` 20, `C_Spell.GetSpellChargeDuration` 18, `C_CurveUtil.CreateCurve`
18, `C_StringUtil.TruncateWhenZero` 11+3, `GetRemainingDuration` 16, `canaccesstable` 15,
`C_ActionBar.GetActionCooldownDuration` 6, `C_Secrets.ShouldSpellAuraBeSecret` /
`ShouldCooldownsBeSecret` / `ShouldUnitIdentityBeSecret` / `ShouldUnitThreatValuesBeSecret`,
`C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)`,
`SetVertexColorFromBoolean`, `SetToTargetValue`.

Typical unit-frame patterns (described, not copied):

- Health percent text: `fs:SetFormattedText("%d%%", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100))`.
- Health-gradient colour: build once a `C_CurveUtil.CreateColorCurve()` with
  `SetType(Enum.LuaCurveType.Linear)` and `AddPoint(0, red) / (0.5, yellow) / (1, green)`; then
  `local c = UnitHealthPercent(unit, true, curve)` returns a colour object whose `GetRGB()` goes
  straight into `SetStatusBarColor`. Rebuild the curve only when the user's colours change.
- Alpha-by-health: `UnitHealthPercent(unit, false, alphaCurve)` -> `SetAlpha`.
- Secret resource text "hide at zero": `C_StringUtil.TruncateWhenZero(value)`.

### 11.3 Recurring rules they follow

1. Test with `issecretvalue` **before** `==`, `<`, `..`, `#`, `tostring`, table indexing or
   `string` methods. `type(secret)` is allowed and reports the underlying type.
2. Secrets go only into widget setters that accept them (`SetValue`, `SetMinMaxValues`,
   `SetFormattedText`, `SetText`, `SetStatusBarColor`, `SetVertexColor`, `SetAlphaFromBoolean`,
   curve/duration/formatter objects).
3. Never cache a secret (a cached secret breaks the next "unchanged?" compare) - mark dirty.
4. Branch on secret booleans in C (`EvaluateColorValueFromBoolean`, `SetAlphaFromBoolean`,
   gate StatusBars), not in Lua.
5. Restriction is instance/combat gated and cannot flip mid-frame: defer refused work and re-run
   on a lift edge (regen, PEW, zone change, encounter end).
6. Never write fields on Blizzard frames; side tables only (taint turns later Blizzard reads
   into secret-value errors).
7. Edit Mode frames: use the `*Base` C methods.

---

## 12. Performance patterns (summary)

- Upvalue globals in hot files; split files to stay under the 200-local / 60-upvalue limits.
- Events: `RegisterUnitEvent` for unit events (`UNIT_PET` for "player"); register expensive
  events only while a consumer is active (range, cost prediction, mana spark, gold ledger,
  roster watcher for restricted colours, AuraKit's offensive dispel watcher, combat queue).
- No idle OnUpdate anywhere: self-disarming drivers, anim-group tickers, demand-gated Mouse
  service, glow driver hides when empty, FlipBook animations in C.
- Coalescing: dispatcher events -> one `C_Timer.After(0)` per batch; anchor propagation batched
  per frame with 0.5 px convergence guards; per-frame caching of restriction probes.
- Allocation: mutate colour tables in place; cache parsed templates (capped); cache joined names;
  reuse Color objects (`CreateColor` once); dense arrays with swap-remove; weak-keyed side tables.
- Work slicing under the 12.1 watchdog: `RunBudgeted`, AuraKit build workers with shared
  per-frame budget and watchdog-retry, async import decode coroutine.
- Lazy loading: options + locales LOD; heavy unlock body deferred to first use (but still at
  PLAYER_LOGIN for positioning); frames built on first show.
- Frame pooling: options page frame pool with "dress generation" counters; glow/guide/grid line
  pools; containers released rather than destroyed.
- Measure: they repeatedly cite measured costs (EnumerateFrames 248 ms, border colour garbage
  1.2 MB/min, spec ID strings 1.9 KB per call) - keep a perf log too.

---

## 13. Pitfalls they guard against (checklist)

- Older client loading new code -> SV corruption (client gate).
- Child WTF file containing an old copy of the central store (stale-DB guard).
- OnEnable taint when run inside a secure post-login ADDON_LOADED (defer one tick).
- Secure setup must happen inside the login loading-screen window on an in-combat reload
  (run synchronously at PLAYER_LOGIN; timers don't fire during loading screens).
- UI scale applied after Blizzard restores positions -> frames drift each login.
- `UIParent:SetScale` not firing `UI_SCALE_CHANGED`.
- 1 px drift from rounding odd-dimension centres; float dust at pixel boundaries.
- Pixel-snap re-enabled by Blizzard or by `SetStatusBarTexture` creating a new fill texture.
- `GetPhysicalScreenSize()` returning 0 mid mode switch.
- Writing fields onto Blizzard frames (taint -> secret errors in Blizzard code later).
- Edit Mode `SetPoint`/`Hide`/`SetScale` overrides tainting layouts.
- `print()` tainting chat; `Hide()` on Blizzard frames during unlock (use alpha).
- Protected item-range calls in combat; secure menus opened from Lua.
- Watchdog "script ran too long" on login/profile swap/import.
- Profile switches with cached `db.profile` references (always read through `db`).
- Anchor cycles and contradictory imported chains (cycle checks, 100-step caps).
- Imports from newer/older versions or the other client flavour (version gates, `client` stamp).

---

## 14. Recommendations for SoulUI

Concrete design decisions, in priority order. "Adopt" = same idea, our own code. "Simplify" =
we want the capability with less machinery.

### 14.1 Framework and data

1. **Adopt a single central SavedVariables** (`SoulUIDB`) owned by the core, with child modules
   getting `db.profile = SoulUIDB.profiles[active].modules[moduleKey]`. Do **not** declare child
   SavedVariables at all (avoids EUI's vestigial-SV and stale-WTF problems from day one); if a
   module ever needs character data use `SoulUIDB.chars[charKey]`.
2. **Our own tiny addon framework** (`SoulUI.NewModule(key)`), mirroring Lite's good parts:
   eager per-module event frame created in the module's main chunk (CPU attribution),
   direct-function event handlers, `RegisterUnitEvent` helper, OnInitialize at ADDON_LOADED,
   OnEnable synchronous at PLAYER_LOGIN and deferred one tick for post-login loads.
3. **Defaults merge + strip-on-logout** like Lite, plus a schema version per module. Keep a
   per-module `Defaults.lua` (already our rule). Add Lite's corruption self-heal.
4. **Callback registry instead of global apply hooks.** Modules register
   `SoulUI:RegisterCallback("ProfileChanged", fn)`, `"UIScaleChanged"`, `"UnlockModeChanged"`,
   `"SpecChanged"`. The core never calls `_G._XXX_Apply`.
5. **Migration runner** with permanent ids, global/profile scopes, pcall + stamp-on-success,
   no live game APIs. Adopt as specified in 3.2.
6. **Client gate** first file + `if SOULUI_BLOCKED then return end` on line 1 of every file.
   Cheap and protects user data across patch days.
7. **Module discovery**: each child addon `## Dependencies: SoulUI`, registers itself, and
   declares its options builder name; options live in `SoulUI_Options` (LOD, no SVs). Register
   bootstrap slash commands in the core that load options on demand (combat-refused, deferred one
   tick).

### 14.2 Rendering

8. **Pixel-perfect module** with `perfect`, `mult`, `Scale`, `Snap`, `SnapForES`,
   `SnapCenterForDim`, `ToPixels`/`FromPixels`, finite-number guard, and the epsilon rule. Store
   positions as **CENTER offsets in UIParent units** and snap odd dimensions to half pixels.
9. **Border = 4 strip textures** on a child container, thickness from effective scale, state in a
   weak side table, idempotent geometry, in-place colour updates, secret colours written but
   never compared/cached. Hook image setters on widget metatables to disable pixel snap once per
   object (skip VertexColor/TexCoord hooks).
10. **UI scale handling**: apply our saved scale at ADDON_LOADED and PLAYER_LOGIN, re-apply on
    `UI_SCALE_CHANGED`, defer in combat, and fire our own `UIScaleChanged` callback since
    `SetScale` won't. Offer "auto pixel perfect" = `clamp(768/physH, 0.4, 1.15)`.
11. **Text tags**: implement a schema + parser that compiles templates to a format string with
    `%s` slots and a "reads" set; modules paint with `SetFormattedText`. Escape `|` and `%`.
    Use `AbbreviateNumbers` + `CreateAbbreviateConfig` (secret-safe, C-side) for K/M/B; never
    `tonumber()` a possible secret first.
12. **Glows**: one driver, FlipBook (AnimationGroup) styles preferred because they cost no Lua;
    procedural ants only when chosen; driver hides when idle. (LibCustomGlow is an allowed
    alternative if its licence fits; check before embedding.)

### 14.3 Runtime services

13. **Ticker**: `NewDriver(frame)` self-disarming OnUpdate dispatcher + `NewAnimTicker` for fixed
    intervals (AnimationGroup OnLoop, zero Lua between fires). Make `SoulUI.Ticker` the only way
    to get per-frame or periodic work (CLAUDE.md already says this).
14. **`SoulUI:RunAfterCombat(key, fn)`** = keyed, idempotent combat queue that registers
    PLAYER_REGEN_ENABLED only while non-empty, swaps before drain, pcall per fn.
15. **`RunBudgeted(steps, ms)`** for any pass that scales with data (profile apply, import, full
    rebuild). Default 8 ms, first slice deferred.
16. **Visibility dispatcher**: one event frame, cached combat flag (with PLAYER_DEAD safety net),
    deferred one-tick updater fan-out, generation-cached mouseover predicates on a 0.15 s ticker.
    Secure frames use state drivers with macro conditionals for the same options.
17. **Shared cursor service** if we add cursor-following features; otherwise skip.
18. **Taint hygiene helpers**: `SoulUI.FrameData(frame)` weak side tables; `SetFramePoint` that
    prefers `SetPointBase`/`ClearAllPointsBase` on Edit Mode systems; `Print` via `AddMessage`
    and muted in protected combat; never `Hide()` Blizzard managed frames (alpha + mouse).

### 14.4 Unlock mode (our `/soul move`)

19. **Element registration contract**: a whitelist constructor with at least `key, label, group,
    order, getFrame, getSize, savePos, loadPos, clearPos, applyPos, setWidth/setHeight, isHidden,
    onLiveMove, ownsPosition, noResize`. Start small; add insets/match-pad style fields only when a
    module needs them.
20. **Movers drag manually** (cursor offset + OnUpdate) and move the real frame live, so snapping,
    guides and anchored children update in real time. Refuse drag/nudge in combat.
21. **Snap** to the nearest element: 3x3 edge/centre pairs per axis with a ~6 px threshold, plus
    screen centre/edges; draw guide lines; Shift locks axis; arrow keys nudge 1 physical pixel.
    1-physical-pixel grid lines at a configurable spacing.
22. **Pending-then-commit sessions**: snapshot on open, keep edits pending, Save & Exit commits,
    Exit reverts, confirm on unsaved changes. **Suspend (not close) on combat** and resume 0.5 s
    after regen.
23. **Anchor links**: store `{ target, point, targetPoint, x, y }` (9-point model from the start -
    skip EUI's legacy side model) and resolve to an absolute UIParent-relative SetPoint, propagating
    via batched `OnSizeChanged`/`SetPoint` post-hooks with a 0.5 px convergence guard and cycle
    checks. Park lockdown-blocked applies and run a dependency-sorted pass at regen. Screen edges as
    pseudo-elements. Width/height match as a later phase.
24. **Grow direction** stored per element; when unanchored, pick the SetPoint edge from it so
    resizing keeps the fixed edge.
25. **Run the position pass synchronously at PLAYER_LOGIN** so protected frames are placed before
    lockdown resumes on an in-combat reload.
26. Keep unlock-mode code in its own files with the body built on first use, but the position
    engine loaded at login (separate from the options UI).

### 14.5 Profiles

27. **Profiles + per-spec assignment** (`specProfiles[specID]`, cached `lastSpecByChar`, pre-seed
    before OnEnable, combat-deferred switching). This covers most "per spec" needs.
28. **Do not build EUI-scale spec overrides initially.** If needed later, design a narrower
    feature (per-spec layout layer for positions only, or explicit "per-spec" toggles on chosen
    settings) instead of a diffing watcher that attributes writes by mouse position.
29. **Export strings**: `!SOUL1!` prefix + version + client stamp; a type-tagged serializer of our
    own (or AceSerializer under its licence) -> `LibDeflate:CompressDeflate` ->
    `EncodeForPrint`. Decode via a coroutine with an 8 ms budget and native
    `C_EncodingUtil.DecompressString(data, Enum.CompressionMethod.Deflate)` when present. Strip
    private/character data on export and on decode. Validate version range. Partial (per-module)
    export from day one. Consider Wago UI Packs' interface later.
30. **Profile switch** = repoint every `db.profile` in place, merge defaults, fire
    `ProfileChanged`, then a budgeted refresh and a deferred position pass. Detect "needs reload"
    settings (fonts cached by the engine) and prompt.
31. Optional later: mirror-group sync with exclusion paths (simple and useful).

### 14.6 Midnight / secret values

32. Write a `SoulUI.Secret` helper module: `IsSecret(v)`, `PlainNumber(v)`, `PlainString(v)`,
    `CanTouchAuras()` (via `C_Secrets.ShouldAurasBeSecret`), a per-frame restriction cache, and an
    `OnRestrictionLift(fn)` hub (regen, PEW, zone, encounter end).
33. Unit frames: `UnitHealthPercent(unit, usePredicted, curve)` with prebuilt colour curves
    (`C_CurveUtil.CreateColorCurve`, `Enum.LuaCurveType.Linear/Step`) and
    `CurveConstants.ScaleTo100` for text; `SetAlphaFromBoolean` / `EvaluateColorValueFromBoolean`
    for any secret boolean; heal prediction via `CreateUnitHealPredictionCalculator`; hidden
    "gate bar" trick for "has any absorb". Verify each API on 12.1.5 before relying on it and
    record findings in `docs/research/midnight-api.md`.
34. Cooldowns: duration objects (`C_Spell.GetSpellCooldownDuration`,
    `Cooldown:SetCooldownFromDurationObject`, `StatusBar:SetTimerDuration`) - never read start/
    duration numbers in restricted content.
35. **Auras: build on the 12.1 engine aura containers** for player/target/party/nameplate auras.
    Mirror AuraKit's lessons: canonical filter strings, add-only groups (cap 0 to disable), all
    child regions created inside `initializeFrame`, side-table state, `pcall` around every engine
    registration with graceful degradation, restyle deferral to restriction lift, a shared
    time-budgeted build queue, `EnableMouse(false)` on overlays, release-not-destroy.
36. Unlock mode must treat geometry of anything inside an aura container as possibly secret
    (check before arithmetic; park until regen).
37. Engine formatters for numbers we cannot read: `C_StringUtil.CreateNumericRuleFormatter`,
    `CreateDurationTextBinding`, `TruncateWhenZero`.

### 14.7 Things to deliberately not copy

- Global `_G._XXX_Apply` coupling between core and modules (use callbacks).
- Feature code living in the core (party mode, macro factory, gold ledger, warrior charges, mana
  spark): keep SoulUI core to framework + shared services; features go in modules.
- 5000-line files that hit the local/upvalue caps.
- Spec-override auto-capture watcher (complexity and corruption risk).
- Standalone-build renaming tricks (we have no standalone builds).
- The anti-hijack `debugstack`/`issecurevariable` plugin enforcement - only needed if we publish a
  plugin API; if we do, copy the *idea* (validated, snapshotted, pcall-guarded registration).
