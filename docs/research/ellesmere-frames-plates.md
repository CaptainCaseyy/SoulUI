# EllesmereUI frames, plates, resources and CDM: research notes

Study target: EllesmereUI 9.7 (`## Interface: 120000 ... 120105`) as installed in
`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`.

Scope of this document: the five child addons

| Addon | Lua files | Approx. lines | SavedVariables |
|---|---|---|---|
| EllesmereUINameplates | 19 | 19.0k | `EllesmereUINameplatesDB` |
| EllesmereUIUnitFrames | 31 | 33.0k | `EllesmereUIUnitFramesDB` |
| EllesmereUIRaidFrames | 38 | 43.9k | `EllesmereUIRaidFramesDB` |
| EllesmereUIResourceBars | 23 | 19.2k | `EllesmereUIResourceBarsDB` |
| EllesmereUICooldownManager | 45 | 39.5k | `EllesmereUICooldownManagerDB` |

All five depend on the core `EllesmereUI` addon. Core files are outside this
document's scope, but several are load-bearing and get short notes where the child
addons call into them: `EllesmereUI_AuraKit.lua` (the 12.1 aura container engine wrapper),
`EllesmereUI_ClientGate.lua` (`EUI_CLIENT_BLOCKED`), `EllesmereUI.Lite` (the
AceAddon/AceDB stand-in), `EllesmereUI.PP` (pixel-perfect helpers) and `EllesmereUI.Tick`.

License reminder: EllesmereUI is "all rights reserved". Everything below is a
description in my own words. Code fragments are short illustrations (under 10 lines)
written to explain a technique. They are not copied blocks. SoulUI must implement its
own versions.

File:line references point at the installed 9.7 files and will drift when they update.

---

## 0. TL;DR: architecture at a glance

1. **No oUF anymore.** The unit frames were extracted from oUF into a custom "engine"
   (`EUI_UnitFrames_Engine.lua`). oUF-shaped names remain (`frame.Health`,
   `frame.Castbar`, `PostUpdateColor`, `EnableElement`) as a compatibility surface
   only. The code uses raw `SecureUnitButtonTemplate` + `RegisterUnitWatch`.
2. **Raid/party frames** run on stock `SecureGroupHeaderTemplate` (8 per-group headers or one
   flat header), plus `SecureGroupPetHeaderTemplate` for pets. The 12.1 header attribute
   `auraContainerTemplate = "CustomAuraContainerTemplate"` makes the header create a
   secure-side **AuraContainer** for every child button.
3. **Nameplates reskin by overlay, not by replacing the plate.** EUI keeps its own frame
   pool. On `NAME_PLATE_UNIT_ADDED` (enemy units only) it parents one pooled frame to
   Blizzard's base nameplate, sets the Blizzard `UnitFrame` to alpha 0, reparents its
   children to a hidden holder, and calls `UnregisterAllEvents()` on it. Friendly plates
   mostly stay Blizzard name-only plates with tweaks.
4. **Auras in 12.1 are no longer scanned in Lua** on any unit frame, plate or raid frame.
   Every aura display goes through Blizzard's new `AuraContainer` frame type
   (`CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")`).
   Groups and slots are declared with filter strings and candidate filters, and the
   engine does parsing, sorting, layout, icon, cooldown, stack count, duration text and
   dispel-type tinting in C. Lua only styles the buttons.
5. **Secret values flow only into widget setters.** The values are health, power, absorbs,
   cast flags, range, threat booleans and cooldown durations. The setters are
   `StatusBar:SetValue`, `SetTimerDuration`, `SetAlphaFromBoolean`,
   `SetVertexColorFromBoolean`, `SetStatusBarColor`, `FontString:SetFormattedText`,
   `Cooldown:SetCooldownFromDurationObject`. When Lua needs a decision, it asks the
   engine to evaluate a curve:
   `UnitHealthPercent(unit, usePredicted, curve)`,
   `UnitPowerPercent(unit, type, usePredicted, curve)`,
   `DurationObject:EvaluateRemainingDuration(curve)`,
   `C_CurveUtil.EvaluateColorValueFromBoolean`.
6. **The Cooldown Manager does not rebuild cooldown tracking.** It hooks Blizzard's
   `EssentialCooldownViewer`, `UtilityCooldownViewer` and `BuffIconCooldownViewer` item
   frames. It decorates and re-anchors them into its own bar containers and never
   reparents them. Blizzard's frames keep reading the restricted spell/aura state.
   The secondary `BuffBarCooldownViewer` is parked off-screen and replaced by EUI's own
   "Tracked Buff Bars".
7. **Performance is a first-class design goal.** The code uses per-unit trackers with
   `RegisterUnitEvent` (C-side filtering), same-frame paint dedupe, "lean path" memos, and
   timers that exist only while armed. Per-frame OnUpdate is avoided. It prefers
   10 Hz animation tickers and engine-driven timer bars.

---

## 1. Shared infrastructure the children rely on

### 1.1 Client gate

Every file starts with `if EUI_CLIENT_BLOCKED then return end`. The core sets the flag on
pre-12.1 clients, and each child's main file also sets it when the parent addon is stale.
Example: `EllesmereUIRaidFrames.lua:9` checks that a list of core functions exists and
otherwise goes dormant instead of throwing. This is a cheap, clean "wrong client, do
nothing" switch. SoulUI should copy the idea.

### 1.2 Split-file module pattern

Large modules are cut into many files that share one namespace:

- `ns._internals` / `ns._npInternals` / `ns._hookInternals` tables (named `I`) carry the
  locals that later files need.
- A `I.broken = true` sentinel at the top of each file and `I.broken = false` at the bottom.
  When an earlier file errored mid-load, every later file early-returns instead of
  cascading errors. See `EUI_Nameplates_Plate.lua:11-14`.
- `I.dbSetters` / `I.profileSetters` arrays: each file registers a closure that receives
  the db/profile reference. When the profile swaps, every file's cached upvalue `db` / `p`
  updates without a global lookup on hot paths.
- The code comments mention the Lua 5.1 200-local limit more than once ("this chunk is near
  its 200-local cap"). That is the reason values move to `ns.*` fields.

### 1.3 External per-frame state ("FFD")

`EllesmereUI.NewFrameData()` returns a weak-keyed table plus an accessor (`GetFFD`,
`FD`, `FC`). The rule is enforced everywhere: **do not write custom keys on Blizzard
frames or on secure header children**. That would taint them. Examples:

- Raid buttons: `GetFFD(button)` (`EUI_RaidFrames_Update.lua:1155`).
- CDM: `hookFrameData[frame]` and `_ecmeFC[frame]` (`EllesmereUICdmHooks.lua:32`).
- Unit-frame portrait side: `EllesmereUI._ufPortraitSide` weak table
  (`EllesmereUIUnitFrames.lua:151-152`).

The unit-frame engine is a deliberate exception: its own spawned buttons carry
underscore-prefixed fields (`frame._euiUnit`, `_euiBaseUnit`). They must **never** carry a
`.unit` field, because the ping system reads `self.unit or GetAttribute("unit")` inside a
secure call. An addon-written `.unit` turns a secret GUID "inaccessible" there
(`EUI_UnitFrames_Engine.lua:901-911`).

### 1.4 Shell frames billed to the right addon

`ns.TakeShell()` (`EllesmereUICooldownManager.lua:13-29`, also used in raid frames)
pre-creates N plain frames in the module's main chunk. The client bills a handler's CPU
to the addon whose load context created the frame. A frame created later inside a
callback from the core would bill the core forever. This matters only for profiling
accuracy, but it is a neat trick.

### 1.5 CVar ownership

The code never calls `SetCVar` directly. It calls `EllesmereUI.SetCVar(name, value, ownerAddon)` and
`EllesmereUI.SetCVarBitfield(...)`. The core wrapper records ownership, so it can tell user
changes from addon changes and can restore values on uninstall.

### 1.6 DB / config

`EllesmereUI.Lite.NewDB("EllesmereUIUnitFramesDB", defaults, true)`
(`EUI_UnitFrames_Lifecycle.lua:26`) is an AceDB-like profile store. Per-unit settings live
at `db.profile[unitKey]`, positions at `db.profile.positions[unit] = {point, relPoint, x, y}`.
Live application:

- **Positions:** `ApplyFramePosition` (`EUI_UnitFrames_Layout.lua:445-472`). It reads the
  saved point, converts offsets to the frame's scale (`ns.UF_ScaledOffsets`), and snaps to
  the physical pixel grid (`PP.SnapCenterForDim` for CENTER anchors, `PP.SnapForES`
  otherwise). Then it runs `ClearAllPoints` + `SetPoint(point, UIParent, relPoint, x, y)`.
- **Unlock mode** (core `EUI_UnlockMode*.lua`) calls per-module `loadPos` / `savePos`
  closures (`EUI_UnitFrames_Unlock.lua:177-200`). These write the db and apply directly
  (boss frames chain 2..5 off boss1).
- **Settings changes** call a throttled `ns.ReloadFrames()`
  (`EUI_UnitFrames_OptionsSetup.lua:125-131`). It sets a pending flag, shows a one-shot
  OnUpdate frame, and restyles once on the next frame. The engine's
  `Engine.RepaintAll` / `Engine.ForceAll` then repaint every channel.
- Nameplates use an **appearance generation counter**: `ns._npAppearanceGen`. A recycled
  plate re-runs `ApplyAppearance()` only when its stamped generation is stale
  (`EUI_Nameplates_Plate.lua:951-954`).
- Raid frames read settings through **scaled proxies** (`ns._scaledProfile`,
  `ns._scaledPartyProxy`, `ns._scaledExtraProxy`). These are materialized tables with size
  tiers and indicator scale already applied, so hot paths do plain table reads.
- Combat-blocked work goes through `EllesmereUI.NewCombatQueue(shell)`.
  `Defer(key, fn)` runs once on `PLAYER_REGEN_ENABLED`.

---

## 2. Unit frames (EllesmereUIUnitFrames)

### 2.1 Load order (toc)

`EUI_UnitFrames_Engine.lua` is first, then the main file, Text, Portrait, Castbar, Layout,
Absorb, Power, Builders, ClassPower, Threat, StockStyles, Reload, Visibility, Init,
OptionsSetup, Unlock, Lifecycle, the PlayerAuraBars set, and last
`EUI_UnitFrames_AuraContainers.lua`.

### 2.2 Frame creation: custom engine, not oUF

`Engine.SpawnUnitFrame(unit, name)` (`EUI_UnitFrames_Engine.lua:899-932`):

- `CreateFrame("Button", name, petBattleHider, "SecureUnitButtonTemplate, PingableUnitFrameTemplate")`.
- `petBattleHider` is a `SecureHandlerStateTemplate` frame covering UIParent with
  `RegisterStateDriver(hider, "visibility", "[petbattle] hide; show")` (`:810-812`).
  Every unit frame parents to it.
- Attributes: `unit`, `*type1 = "target"`, `toggleForVehicle = true`.
- Right-click: `EllesmereUI.AttachSecureUnitMenu(frame)`. This is a macro-proxy
  `SecureActionButton` route, because 12.0.7+ gates the raw `togglemenu` type on unit
  buttons (comment at `EUI_UnitFrames_Init.lua:101-108`).
- `OnAttributeChanged("unit"|"toggleForVehicle")` calls `EvalActiveUnit`. It resolves the
  live token with `SecureButton_GetModifiedUnit` and updates `frame._euiUnit`, then runs
  a full repaint. It refuses to adopt a non-existent vehicle token until it exists
  (`:822-845`).
- `RegisterUnitWatch(frame)` owns show/hide.
- Click-casting interop: the frame registers with `RegisterForClicks("AnyUp")` and adds itself to the global
  `ClickCastFrames[frame] = true` (`EUI_UnitFrames_Init.lua:116-117`), so Clique or EUI's own
  engine can bind it.
- No ping mixin override. Comments describe three failed attempts (`:118-128`).
- Visibility conditions per frame: `RegisterAttributeDriver(frame, "state-visibility", cond)`
  replaces `RegisterUnitWatch` when the user sets a custom visibility macro
  (`EUI_UnitFrames_Init.lua:1755-1758`).

`targettarget` / `focustarget` frames are "polled". `Engine.AttachPolled` registers them,
and one shared 0.5 s ticker repaints value channels every tick. Identity channels repaint
only when the GUID changed (`:745-798`). The comparison is secret-safe: a secret GUID
counts as "changed" (fail open). `UNIT_TARGET` for target/focus (`RegisterUnitEvent("UNIT_TARGET", "target", "focus")`)
forces an immediate repaint, so the occupant never waits for the tick.

### 2.3 The engine: channels, trackers and painters

`EUI_UnitFrames_Engine.lua` owns no visuals. It decides *who* gets painted and *when*:

- **Channels** map to unit events (`CHANNEL_EVENTS`, `:63-102`):
  - `health`: `UNIT_HEALTH, UNIT_MAXHEALTH, UNIT_CONNECTION, UNIT_FACTION, UNIT_MAX_HEALTH_MODIFIERS_CHANGED`
  - `power`: `UNIT_POWER_UPDATE, UNIT_MAXPOWER, UNIT_DISPLAYPOWER, UNIT_POWER_BAR_SHOW/HIDE, UNIT_CONNECTION`
  - `text`: health + power + name/level/connection/faction/absorb events, plus `UNIT_TARGET`
  - `absorb`: `UNIT_MAXHEALTH`, both absorb-changed events, and max-health modifiers.
    **Not** `UNIT_HEALTH`, because absorb overlays are clip-anchored to the health fill
    texture edge, which the client moves for free.
  - `portrait`: `UNIT_PORTRAIT_UPDATE, UNIT_MODEL_CHANGED, UNIT_CONNECTION`
  - `castbar`: the 13 `UNIT_SPELLCAST_*` events, routed raw and never deduped.
- **Opt-in channels** (`OPTIN_EVENTS`, `:115-120`). Their events are registered only while a
  setting needs them. `Engine.SetChannelOn(frame, channel, on)` registers or unregisters
  events and frees them when unused:
  - `healpred`: `UNIT_HEAL_PREDICTION` and related events.
  - `absglow`: `UNIT_HEALTH` for the overshield glow flip.
  - `powerval`: `UNIT_POWER_FREQUENT` for the player's smooth power bar.
- **Trackers:** one hidden `Frame` per unit token, using `RegisterUnitEvent(ev, unit[, secondary])`.
  The vehicle trick is that the player tracker registers for both `"player"` and
  `"vehicle"`, and the pet tracker for both `"pet"` and `"player"`. Painters read
  `frame._euiUnit` at paint time, so a vehicle swap needs no re-registration
  (`SECONDARY_TOKEN`, `:441`).
- **Same-frame dedupe:** `Bump()` increments a generation once per `GetTime()` value.
  Each `(frame, channel)` paint is stamped with the generation, and a second trigger in
  the same rendered frame is skipped (`Paint`, `:504-525`). Identity events
  (`UNIT_NAME_UPDATE`, `UNIT_LEVEL`, ...) are never eaten. `healpred` gets one trailing
  next-frame flush for deduped repeats.
- **Power value flush:** `UNIT_POWER_FREQUENT` only marks the frame. One OnUpdate pass on
  the next frame paints the live value. That is at most one value paint per frame however
  bursty the events are (`:484-502`). A per-type filter drops events for a power type the
  bar does not show. A secret token passes unfiltered.
- **Resettle:** after `UNIT_MAXHEALTH` / `UNIT_MAX_HEALTH_MODIFIERS_CHANGED`, a
  `C_Timer.After(0)` repaints once from settled values. Max and current health land in two
  steps, and dedupe could otherwise leave a torn paint (`:551-597`).
- **Boss GUID guard:** boss slots re-sort mid-encounter. Each event compares
  `UnitGUID(unit)` (skipped when secret) and runs a full repaint when it changed
  (`:566-576`). `INSTANCE_ENCOUNTER_ENGAGE_UNIT` repaints all boss frames now and once
  more next frame.
- **Global triggers** (`:968-1050`): `PLAYER_TARGET_CHANGED`, `PLAYER_FOCUS_CHANGED`,
  `PLAYER_ENTERING_WORLD`, `RAID_TARGET_UPDATE`, `INSTANCE_ENCOUNTER_ENGAGE_UNIT`,
  `PORTRAITS_UPDATED`. Vehicle edges come from a separate frame on `UNIT_ENTERED_VEHICLE`,
  `UNIT_EXITED_VEHICLE` and `UNIT_PET` (`:944-962`).
- **OnShow repaint:** hidden frames skip event dispatch, so `HookScript("OnShow")`
  repaints everything (`:617-621`).

This is in effect a tiny oUF without the element abstraction, tuned for event counts.

### 2.4 Health

`PaintHealth` (`EUI_UnitFrames_Text.lua:73-118`):

- `SetMinMaxValues(0, UnitHealthMax(unit))` runs only on non-`UNIT_HEALTH` events or the first
  paint. On `UNIT_HEALTH` only `SetValue(UnitHealth(unit), element.smoothing)` runs, which is
  Blizzard's own contract. Both values may be secret, and the widget accepts them.
- Disconnected: `SetValue(UnitHealthMax)` (full bar). Dead (`UnitIsDead`, a plain boolean
  even in restricted content): `SetValue(0)` without smoothing. A corpse gets no more
  `UNIT_HEALTH` events, and smoothing would otherwise leave a sliver.
- `element.smoothing` is a `Enum.StatusBarInterpolation` value. Native interpolation, no
  Lua tween.
- Color runs only when the mode depends on health/threat, or on identity events.

**Color chain:** `UF_SecretSafeHealthColor` (`EllesmereUIUnitFrames.lua:2105-2170`) mirrors
oUF's `UpdateColor` priorities (disconnected > tapped > threat > class > reaction > smooth >
health). It adds one 12.1-specific fix:

- 12.1 build 68914 made `UnitClass` return a **secret class token for identity-restricted
  units** (focus, focus-target, target-of-target in instances). A secret table key throws.
  The fix: when `issecretvalue(class)`, call core `EllesmereUI.GetClassColorForRestrictedUnit`.
  It compares C-side to recover the user's custom class color and returns secret r,g,b.
  Those values are written into a reusable `ColorMixin` with `SetRGB` and passed to
  `SetStatusBarColor`, never read. Fallback: `C_ClassColor.GetClassColor(secretToken)`
  accepts the secret token and returns Blizzard's color.

**Dynamic health color modes** (`EllesmereUIUnitFrames.lua:1895-2060`):

- `classic`: a linear `C_CurveUtil.CreateColorCurve()` with points at 0 red, 0.5 yellow, 1 green.
- `customDynamic`: the same with user stops. One cached curve, rebuilt only when the stop
  colors change.
- `classReactive`: points at 0 / 0.4 / 0.75 / 1, where the 1.0 point is the class color.
  Cached per class token. It needs a readable class token and declines on a secret one.
- Evaluated by `UnitHealthPercent(unit, true, curve)`, which returns a `ColorMixin`. Its
  `GetRGB()` may return secret numbers. These go to `SetStatusBarColor`, which accepts
  secrets. **`SetGradient` refuses secrets**, so the function returns an `isSecret` flag
  and callers skip gradient paths (`:1990-2003`).
- Plain-number "twin" functions (`ns.UF_ResolveDynamicColor`, ...) compute the same color
  in Lua for the options preview, where the percent is a fake known number.

### 2.5 Absorbs and heal prediction

The core trick, explained at `EUI_UnitFrames_Absorb.lua:140-156`: **you cannot do
`min(absorb, missing)` in Lua on secrets, so let StatusBar clipping do the math.**

- `missClip` is a frame with `SetClipsChildren(true)` anchored from the health fill
  texture's RIGHT edge to the health bar's RIGHT edge. A forward-filling absorb bar inside
  it, anchored at the fill edge with the full bar width and range `(0, maxHealth)`, shows
  exactly `min(absorb, missing)`.
- `curClip` spans from the bar's LEFT edge to the fill texture's RIGHT edge. A
  reverse-filling bar anchored at the bar's right edge shows only the overflow
  `max(0, absorb - missing)` (the "overshield backfill").
- Both bars receive the raw, possibly secret `UnitGetTotalAbsorbs(unit)` through
  `SetValue`. No arithmetic.
- Because the clips are anchored to the fill texture, the client moves them when health
  changes. That is why the absorb channel does not listen to `UNIT_HEALTH`.
- A mask texture (`CreateMaskTexture`, WHITE8X8, `SetAllPoints(hpBar)`) prevents 1 px
  subpixel bleed (`:965-972`).
- **Memo:** skip a repaint when absorb, heal absorb, max and size equal the last plain
  values. Any secret input fails open and clears the memo (`:1265-1278`).
- **Armed belt** (`:921-958`): an aura shield that expires on its timer on an unhit,
  full-health unit fires **no event at all** (field example: VDH Infernal Strike). Instead
  of listening to `UNIT_AURA`, a frame that last painted a non-zero or secret absorb is
  "armed". A shared `C_Timer.NewTicker(0.5)` repaints armed frames whose last paint is
  older than 0.45 s, and cancels itself when no frame is armed. A plain zero read disarms.

Heal prediction (opt-in, `EUI_UnitFrames_Absorb.lua:603-660`):

- `calc = CreateUnitHealPredictionCalculator()` per frame, configured once with these
  modes:
  - `calc:SetIncomingHealClampMode(Enum.UnitIncomingHealClampMode.MaximumHealth)`
  - `calc:SetHealAbsorbClampMode(Enum.UnitHealAbsorbClampMode.MaximumHealth)`
  - `calc:SetHealAbsorbMode(Enum.UnitHealAbsorbMode.ReducedByIncomingHeals)`
- Paint: `UnitGetDetailedHealPrediction(unit, "player", calc)`, then
  `local _, mine, others = calc:GetIncomingHeals()`. Each value goes into its own bar with
  range `(0, UnitHealthMax)`, inside the same missing-health clip (`:603-614`).

### 2.6 Power

`PaintPower` (`EUI_UnitFrames_Text.lua:125+`) resolves the display power type. The player
has spec overrides: Balance/Elemental/Shadow can show Mana (`EllesmereUI.GetPlayerPowerOverride`).
It then stashes the type's token for the engine's `UNIT_POWER_FREQUENT` filter, and calls
`SetMinMaxValues(0, UnitPowerMax)` + `SetValue(UnitPower)`. Power values for other units can
be secret. They pass straight to the widget.

### 2.7 Cast bar (unit frames)

The castbar driver lives in the engine (`EUI_UnitFrames_Engine.lua:145-431`):

- **StartCast:** read `UnitCastingInfo(unit)`. If nothing, read `UnitChannelInfo(unit)` and
  take `isEmpowered` from it. Get the duration object:
  - `UnitCastingDuration(unit)`, direction `ElapsedTime`;
  - `UnitChannelDuration(unit)`, direction `RemainingTime`;
  - `UnitEmpoweredChannelDuration(unit)`, `ElapsedTime`.

  Then `element:SetTimerDuration(duration, element.smoothing, direction)`. **The fill is
  engine-driven, and Lua never reads the clock.**
- `startTime/endTime` from `*Info` are readable **only for the player** (`:249-257`). They
  feed the delay (pushback) text and the latency SafeZone:
  `ratio = select(4, GetNetStats()) / (endTime - startTime)`.
- **Time text:** OnUpdate reads `self:GetTimerDuration():GetRemainingDuration()` and writes
  it with `SetFormattedText("%.1f", rem)`. The remaining time is secret for other units in
  instanced combat. `SetFormattedText` accepts the secret, but Lua cannot compute when the
  next tenth ticks, so a secret value repaints on a fixed 0.05 s grid. A plain value waits
  exactly until the shown tenth changes (`:159-206`).
- **Cast identity:** 12.1 delivers the cast GUID at **event argument 4**, with interrupt
  and empower extras before it. Stop, fail and update events are ignored unless
  `element.castID == castID` (`:300-379`). The comment at `:140-143` documents the
  positional layout.
- **Interrupted / failed:** shows `INTERRUPTED` / `FAILED`, sets the bar to full
  (`SetMinMaxValues(0,1)`, `SetValue(1)`), and holds for `timeToHold`.
- **Empower stage pips:** `element:UpdatePips(UnitEmpoweredStagePercentages(unit))`.
  End time adds `GetUnitEmpowerHoldAtMaxTime(unit)`.
- **Interruptible state:** `notInterruptible` from `*Info` is a **secret boolean** for hostile
  units. It is stored as is. `UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE` events override it with a
  plain boolean. Nil-safety uses `type(v) == "nil"`, not `v == nil`
  (`EUI_UnitFrames_Castbar.lua:615-619`).
- **Shield overlay:** `shieldHost:SetAlphaFromBoolean(uninterruptible, fillOpacity, 0)`
  (`EUI_UnitFrames_Castbar.lua:676-677`). Field note in the code: calling
  `SetAlphaFromBoolean` on a *texture* rendered 0 on Midnight, so it is called on the
  **host frame**. Separate note: 3-argument `SetVertexColor` left vertex alpha at an odd
  value, so they always pass alpha explicitly (`:665-670`).
- **Important-cast glow:** `pcall(C_Spell.IsSpellImportant, spellID)` returns a possibly
  secret boolean, which drives `overlay:SetAlphaFromBoolean(isImportant)`
  (`EUI_UnitFrames_Castbar.lua:1306-1358`).
- **Kick-ready tick** (the cleverest piece, `EUI_UnitFrames_Castbar.lua:687-893`). It shows
  where on the cast bar your interrupt comes off cooldown, all secret-safe:
  1. `kickPositioner`: a StatusBar the size of the cast bar with range
     `(0, castDuration:GetTotalDuration())` and value `castDuration:GetElapsedDuration()`.
     Its fill edge is "now".
  2. `kickMarker`: a second StatusBar anchored at the positioner's fill edge, with the same
     range and value `C_Spell.GetSpellCooldownDuration(kickSpell):GetRemainingDuration()`.
     Its fill edge is "now + kick CD remaining", the moment the kick becomes ready.
  3. `kickTick`: a 1 px texture anchored to the marker's fill edge. `kickReadyFill` spans
     from that edge to the cast end.
  4. Visibility alpha:
     `interruptible = EvaluateColorValueFromBoolean(kickProtected, 0, 1)`, then
     `alpha = EvaluateColorValueFromBoolean(interruptCD:IsZero(), 0, interruptible)`.
     Two nested secret-boolean selects with no Lua branch. Applied with `SetAlpha(alpha)`.
  5. For channels, both bars use `Enum.StatusBarFillStyle.Reverse`.
     `SetSnapToPixelGrid(false)` + `SetTexelSnappingBias(0)` are re-applied after every
     `SetFillStyle` (comment: "LOAD-BEARING", because SetFillStyle re-creates the inner fill
     texture with snapping on).
  6. A `C_Timer.NewTicker(0.1)` refreshes only the alpha. `SPELL_UPDATE_COOLDOWN` /
     `SPELL_UPDATE_USABLE` re-pin both values *together*, so the tick never drifts.
  7. Cast-bar width can be **secret** when the bar is anchored to a stock-style aura
     container (restricted rect). The code checks `issecretvalue(barW)` before any compare
     (`:735-740`, `:1340-1347`).

### 2.8 Text tags and number formatting

`EUI_UnitFrames_Text.lua` (zone formatters / `TagFns`):

- Health values: `AbbreviateNumbers(UnitHealth(u), cfg)` (`:382-386`). `AbbreviateNumbers`
  accepts a secret number and returns a secret string. A custom `breakpointData` config
  (`DecimalAbbrevConfig`, `:280-292`) gives K/M with decimals.
- Percent: `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`, then
  `string.format("%d" | "%.1f" | "%.2f", pct)` (`:431-434`). **`string.format` accepts
  secret numbers** and returns a secret string, which `SetText` accepts.
- **"Hide trailing zeros" percent** (`:313-329`, `:425-430`). Lua cannot strip ".0" from a
  secret string. The solution:
  - Build a linear curve `CreateCurve()` with points (0 → 0.5) and (1 → 1000.5). This
    scales the percent to tenths of a percent, with +0.5 for rounding.
  - Evaluate `UnitHealthPercent(unit, true, curve)`, which returns a secret number in
    tenths.
  - Format with `AbbreviateNumbers(scaled, {breakpointData = {{breakpoint=0, abbreviation="",
    significandDivisor=1, fractionDivisor=10}}})`. AbbreviateNumbers truncates and drops a
    zero fraction, so the result reads "100" or "99.5".
- Power percent: `sf("%d", UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100))`
  (`:894`).
- Absorb text: `sf("%s", C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0))`
  (`:927`, heal absorb `:937`). `TruncateWhenZero` returns `""` for zero and a display
  string otherwise, without Lua ever seeing the number.
- Dead/offline status words come from plain booleans (`UnitIsConnected`, `UnitIsDeadOrGhost`).

### 2.9 Visibility tied to health (secret-safe)

`ns.HealthVisibilityAlpha` (`EUI_UnitFrames_Visibility.lua:100-126`) is a step curve
`CreateCurve()` with points (0 → 1) and (1 → baseAlpha). It is evaluated with
`UnitHealthPercent(unit, false, curve)`, and the result goes straight to `frame:SetAlpha(alpha)`.
The effect: the frame "reveals when damaged" without Lua knowing the health. On each
`UNIT_HEALTH` only the curve is re-evaluated (`:131-143`).

### 2.10 Range

Boss frames: `C_Spell.IsSpellInRange(spell, unit)` may return a secret boolean **or nil**.
`SetAlphaFromBoolean` rejects nil, so the code checks `issecretvalue(x) or x ~= nil` first
(`EUI_UnitFrames_Lifecycle.lua:218-226`), then calls `f:SetAlphaFromBoolean(inRange, 1, oorAlpha)`.

### 2.11 Class power (unit frame variant)

`EUI_UnitFrames_ClassPower.lua:470-495`. A secret `UnitPower` (combo points come back secret
on some clients, Forever for example) uses the **pip-gate** technique. Each pip gets a
child StatusBar with `SetMinMaxValues(i-1, i)` and `SetValue(cur)`. The bar is empty when
cur ≤ i-1 and full when cur ≥ i. That gives a binary pip per index with no comparison.
Stagger uses a plain StatusBar on `UnitStagger` against `UnitHealthMax` (`:340-377`).

### 2.12 Hiding Blizzard unit frames

`HandleFrame` (`EllesmereUIUnitFrames.lua`, just above `ns.UF_HideBlizzard`):
`UnregisterAllEvents()` on the frame and on known children (health, mana, cast, alt power,
auras, ...), then `EllesmereUI.HideFrame`, then reparent to a hidden parent. A
`hooksecurefunc(frame, "SetParent")` re-applies the hidden parent next frame if Edit Mode
moves it back. A protected frame in combat is deferred to the combat queue.

Special case: the Midnight player alt-power bars (`AlternatePowerBar`, `MonkStaggerBar`,
`EvokerEbonMightBar`, `DemonHunterSoulFragmentsBar`) are **only unregistered, never
reparented**. Reparenting `PlayerFrame` made them descendants of an insecure frame. Their
own event handlers then reached `BuffFrame:Update() -> GetAuraSlots` and threw "Auras
cannot be accessed when secret while tainted" (12.1 build 68824).

### 2.13 Threat (unit frames)

`EUI_UnitFrames_Threat.lua`. A player threat border uses
`RegisterUnitEvent("UNIT_THREAT_SITUATION_UPDATE", "player")` and reads
`UnitThreatSituation("player")`. The status is plain. The threat-percent text (Forever only)
uses `UnitDetailedThreatSituation("player", unit)`. The pct may be secret, so only
`type()` and `issecretvalue()` touch it (`:162-171`).

### 2.14 Raid marker

`EUI_UnitFrames_Portrait.lua:448-470`: `GetRaidTargetIndex(unit)` +
`SetRaidTargetIconTexture`, driven by `RAID_TARGET_UPDATE` fan-out from the engine.

### 2.15 Player aura bars and unit-frame auras

`EUI_UnitFrames_AuraContainers.lua` (3.7k lines) replaces the old oUF aura elements with
AuraKit containers (section 5). `EUI_PlayerAuraBars_*` is a separate bar-style player
buff/debuff display.

---

## 3. Nameplates (EllesmereUINameplates)

### 3.1 Strategy: overlay plate parented to the Blizzard base

- **Own pool:** `CreateFramePool("Frame", UIParent, nil, nil, false, initFn)`
  (`EUI_Nameplates_PlatePool.lua:31`). The init function builds the health StatusBar,
  background, hash line, absorb mask and bars, a heal prediction calculator, borders, the
  cast bar and its texts.
- **Prewarm:** after `PLAYER_LOGIN` it acquires and releases one plate every 100 ms for 2 s,
  so an AoE pull does not pay 2 ms+ per plate creation (`:633-640`). Aura container
  bundles are pre-built the same way (16 at login, topped up to 25 on zoning into an
  instance; `EUI_Nameplates_AuraContainers.lua:30-41`).
- **NAME_PLATE_UNIT_ADDED** (`EUI_Nameplates_Events.lua:363-422`):
  - `nameplate = C_NamePlate.GetNamePlateForUnit(unit)`.
  - **Friendly** (`not UnitCanAttack("player", unit)`): leave the Blizzard UnitFrame
    visible as a name-only plate, adjust its Y offset, tint NPC names. A per-unit watcher
    on `UNIT_FLAGS` (`RegisterUnitEvent`) promotes the plate to an enemy plate when the
    unit becomes attackable (duel start). EUI can also show its own friendly-player health
    plates (`EllesmereUINameplatesFriendly.lua`).
  - **Enemy:** `plate = frameCache:Acquire()`, mix in `NameplateFrame` on first use,
    `ns.plates[unit] = plate`, then `plate:SetUnit(unit, nameplate)`.
- **SetUnit** (`EUI_Nameplates_Plate.lua:939-1060`):
  - `self:SetParent(nameplate)`, `SetPoint("CENTER", nameplate, ...)`, frame level +1.
  - `HideBlizzardFrame(nameplate)` (below).
  - `RegisterUnitEvent` for `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_ABSORB_AMOUNT_CHANGED`,
    `UNIT_NAME_UPDATE`, `UNIT_CLASSIFICATION_CHANGED` and `UNIT_THREAT_LIST_UPDATE`.
    `UNIT_TARGET` only when a ToT text is shown, and `UNIT_FLAGS` only when out-of-combat
    alpha is on.
  - Aura bundle attach (`ns.NPC_AttachPlate`), debuff-color attach.
  - Health paints **immediately**. Name, cast, classification, raid icon, target/mouseover
    and stacking bounds are deferred to `C_Timer.After(0)`. The comment claims this cuts
    the add spike by about 40 %.
  - `nameplate:SetStackingBoundsFrame(self._stackBounds)`: a 12.x API. The bounds frame
    needs a real (alpha-0) texture region, because the engine reads the **rendered region
    union**, not `SetSize` (`:985-1006`).
- **NAME_PLATE_UNIT_REMOVED:** `plate:ClearUnit()` (`UnregisterAllEvents`, reset caches,
  `SetParent(UIParent)`), then `frameCache:Release(plate)`.
- **Token swap guard:** `UpdateHealthValues` compares `self.nameplate.namePlateUnitToken`
  against `self.unit`. When they differ, a different mob now owns this base, so the code
  tears down cast state and repaints identity (`EUI_Nameplates_Health.lua:35-87`).

### 3.2 Hiding the Blizzard plate content

`HideBlizzardFrame` (`EUI_Nameplates_Plate.lua:62-200`), also called early from
`hooksecurefunc(NamePlateDriverFrame, "OnNamePlateAdded", ...)` (`EUI_Nameplates_CastState.lua:387-397`)
so Blizzard's first layout never affects bounds:

- `uf:SetAlpha(0)`, plus a `hooksecurefunc(uf, "SetAlpha")` that forces it back to 0 while
  an EUI plate owns the unit. The UnitFrame **itself stays parented to the nameplate**.
  Parenting it to a hidden frame makes `IsVisible()` false and breaks click-target
  selection between overlapping plates.
- Every non-protected, non-forbidden child of the UnitFrame (except `WidgetContainer`,
  `SoftTargetFrame` and `AurasFrame`, which get their own treatment) is reparented to a
  hidden offscreen holder. The pieces are recorded so `ns.NP_ReclaimBlizzardFrame` can
  hand them back when the pooled UnitFrame is later used for a friendly unit.
- `AurasFrame` also goes offscreen. Alpha 0 is not enough, because its item frames are
  mouse-enabled and would trap tooltips.
- `uf:UnregisterAllEvents()`, then re-register only `PLAYER_TARGET_CHANGED` and the soft-target
  events. The comment counts about 27 unit events and 20 globals per plate, including
  `UNIT_AURA`, otherwise running under every plate. The Blizzard castBar also gets
  `UnregisterAllEvents()`. The driver's `CompactUnitFrame_SetUnit` restores unit events on
  re-acquire.
- `WidgetContainer` and `SoftTargetFrame` are reparented live to the nameplate.
- The selection highlight is hooked so it is hidden on attackable plates.
- Also hooked: `NamePlateDriverFrame.SetupClassNameplateBars`, which hides and unregisters
  Blizzard's class-resource bars on plates. `NamePlateDriverFrame` gets
  `UnregisterEvent("DISPLAY_SIZE_CHANGED")` and `UnregisterEvent("CVAR_UPDATE")` to stop
  size jitter.

### 3.3 Click area and CVars

`ApplyNamePlateClickArea` (`EUI_Nameplates_CastState.lua:349-360`):

- `C_NamePlate.SetNamePlateSize(width * hitboxScale, hitboxHeight)`.
- `C_NamePlateManager.SetNamePlateHitTestInsets(Enum.NamePlateType.Enemy, -10000, -10000, -10000, -10000)`
  for Enemy and Friendly. The very large negative insets effectively make the hit-test
  rect the plate size. It is out-of-combat only and re-applied from a hook on
  `NamePlateDriverFrame.UpdateNamePlateOptions`.

CVars written through `EllesmereUI.SetCVar(..., "EllesmereUINameplates")` (`:271-336`):

- Aura display bitfields:
  - `NamePlateConstants.ENEMY_NPC_AURA_DISPLAY_CVAR` with `Enum.NamePlateEnemyNpcAuraDisplay.Debuffs | CrowdControl`.
  - `ENEMY_PLAYER_AURA_DISPLAY_CVAR` with `Debuffs | LossOfControl`.

  These are set with `SetCVarBitfield`, and they matter because they control which auras
  the engine will deliver for plates.
- `nameplateShowOnlyNameForFriendlyPlayerUnits`, `UnitNameFriendlyPlayerName`,
  `nameplateShowFriendlyNPCs` (+ `Npcs` spelling), `nameplateShowEnemyPets`,
  `ShowClassColorInFriendlyNameplate`, `ShowClassColorInNameplate`.
- `nameplateSize=3`, `nameplateShowAll=1`, `nameplateMinScale=1`, `nameplateMaxScale=1`,
  `nameplateSelectedScale=1` (EUI does its own target scale), `nameplateOverlapH=1`.
  `nameplateOverlapV` is left to the user.
- `nameplateMaxAlpha=1`, `nameplateMinAlpha=0.6`, `nameplateMaxAlphaDistance=40`,
  `nameplateMinAlphaDistance=-100000`, `nameplateMaxDistance=60`,
  `nameplateTargetBehindMaxDistance=30`, `clampTargetNameplateToScreen=1`.
- `nameplateShowEnemies` is toggled by visibility rules (`EUI_Nameplates_Init.lua:472-494`).
- Stacking motion uses "the Midnight bitfield CVar" (`ns.RefreshStackingMotion`).
- Friendly visibility CVars are seeded only on first install, so a user's choice to hide
  friendly plates is respected.

### 3.4 Health, absorbs and text on plates

`NameplateFrame:UpdateHealthValues` (`EUI_Nameplates_Health.lua:31-337`):

- **Lean path:** if the last full pass proved there is no absorb (`self._absorbHidden`) and
  no absorb event has fired since (`self._absorbEdge`), the paint is just
  `SetValue(UnitHealth(unit))`. Max health is cached (possibly secret: stored, never
  compared) and pushed only when `_maxHPValid` is false. The gate reads only the addon's
  own plain booleans, so secrecy cannot affect it.
- **Full path:** one heal prediction calculator per plate, created in the pool init with
  `SetMaximumHealthMode(Enum.UnitMaximumHealthMode.Default)` and
  `SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MaximumHealth)`
  (`EUI_Nameplates_PlatePool.lua:63-71`). Then:
  - `UnitGetDetailedHealPrediction(unit, nil, calc)`;
  - `cur = calc:GetCurrentHealth()`, `max = calc:GetMaximumHealth()`,
    `absorb = calc:GetDamageAbsorbs()`.
  - A secret absorb always draws (zero renders nothing). A plain absorb ≤ 0 hides the
    clips and enters the lean path.
  - The same two-clip absorb design as the unit frames.
- **Health text memo:** health ticks constantly land on the same *displayed* values, so
  the memo key is the percent quantized to display granularity. A secret value cannot be
  floored: it writes through and clears the key (`:196-311`). Text uses
  `fs:SetFormattedText("%d%%", pctVal)` directly with the possibly secret percent.
- **Hash line:** a fixed vertical marker at N % of bar width, computed from plain settings
  and the bar width (the bar is EUI's own frame, never secret).
- **Execute glow** (`:317-333` + `EUI_Nameplates_Overlays.lua:150-166`):
  - The execute threshold comes from a per-spec table plus `C_SpellBook.IsSpellKnown`
    talent checks. It is resolved on spec/talent events.
  - Curve: `CreateColorCurve()` with points (0, red), (t, red), (t+0.0001, black) and
    (1, black). This makes a step via an epsilon pair. **Black under ADD blend renders
    nothing**, so alpha interpolation is never relied on.
  - `col = UnitHealthPercent(unit, true, curve)` inside a pcall. `col:GetRGBA()` goes to
    `SetVertexColor` on the glow textures. The glow appears below the execute percentage,
    and Lua never branches on it.
- Tag table (`EUI_Nameplates_Layout.lua:828-838`): `hp:pct` uses `sf("%d", UnitHealthPercent(u,
  true, CurveConstants.ScaleTo100) or 0)`, `absorb` uses
  `C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(u) or 0)`, and abbreviated variants use
  `AbbreviateNumbers`.

### 3.5 Health color, threat, target/focus

`NameplateFrame:UpdateHealthColor` (`EUI_Nameplates_Health.lua:345-621`) with
`GetReactionColor` (`EUI_Nameplates_Colors.lua`). Priority order, roughly:

1. Tapped (`UnitIsTapDenied`).
2. Quest mob (`IsQuestMob`, below).
3. Threat colors (opt-in per content type):
   - `UnitThreatSituation("player", unit)` returns a **plain** status (0-3) for plate
     units. The code compares it with `>=`.
   - Non-tank: has aggro (≥3) or near aggro (≥2), only when threat is "shared" (in a
     group or with a pet out).
   - Tank: losing aggro (2) or no aggro. The target's role is checked with
     `UnitGroupRolesAssigned(unit.."target")`, which can be secret and is then handled as
     "unknown".
4. Mob-type colors (caster/miniboss/boss), reaction colors, and class colors for players.

**Off-tank fold** (`ns.ComputeOffTankFold`, `EUI_Nameplates_Colors.lua:44-82`). This is the
most instructive secret-boolean pattern in the suite:

- The question "is another tank tanking this mob?" cannot be answered in Lua.
  `UnitDetailedThreatSituation(tankToken, plateUnit)` returns a secret `isTanking` for
  plate pairings. The code comment says it is plain only for "target" pairings.
- For each other tank token (up to 3, from the group roster with
  `UnitGroupRolesAssigned == "TANK"`), it folds:
  `r = EvaluateColorValueFromBoolean(isTanking, offTankR, r)`, and the same for g, b and an
  alpha accumulator.
- `type(isTanking) == "boolean"` is used as the guard. **`type()` is legal on secrets and
  reports the underlying type.**
- The resulting r,g,b,a may be secret. They go only to `SetStatusBarColor`, never into a
  cache or a comparison. Any value cache is set to nil so the next plain color re-applies.

**Enemy player class color under PvP redaction:** `UnitClass(unit)` returns a secret token.
`C_ClassColor.GetClassColor(secretToken)` still returns a color whose `GetRGB` values
may be secret. They go to `SetStatusBarColor` (`:351-360`).

**Threat channels:** threat color can also drive the border and name text. Secret
components skip value caches. `RepaintThreatBorder` respects target and hover colors,
which win over threat.

**Target/focus:** `PLAYER_TARGET_CHANGED` updates only the old and new target plate (cached
`ns._cachedTargetPlate`). It runs `ApplyTarget` (scale, border, glow, arrows) and
`UpdateHealthColor`. Target and focus overlays are striped textures inside clip frames on
the fill and background. A focus letter is optional. `UnitIsUnit(plate.unit, "target")`
is plain here.

**Target scale animation:** one shared OnUpdate driver eases all animating plates with an
exponential approach and frame-rate-independent `t = 1 - exp(-11 * elapsed)`. It hides
itself when nothing is animating (`EUI_Nameplates_Cast.lua:263-307`).

### 3.6 Quest mobs

`IsQuestMob` (`EUI_Nameplates_Colors.lua:305-375`):

- `C_TooltipInfo.GetUnit(unit)` structured lines. `LT.QuestTitle` lines give `id`.
  `LT.QuestObjective` lines give `completed`, `numFulfilled`, `numRequired` and `leftText`.
- Each field is `issecretvalue`-checked. Ownership: `C_QuestLog.IsOnQuest(questID)`, so a
  group member's objectives are ignored. When the ID is unreadable it fails open.
- Open world only by default. Results are cached per unit and cleared on `QUEST_LOG_UPDATE`
  and plate removal. Optional objective text (`have/need` or a percent extracted from
  `leftText`).

### 3.7 Raid markers and classification

`NameplateFrame:UpdateRaidIcon` (`EUI_Nameplates_Name.lua:498-524`) uses
`type(GetRaidTargetIndex(unit)) == "nil"` as the empty check. The comment calls this
taint-safe, which suggests the index can be secret. `SetRaidTargetIconTexture(tex, idx)`
accepts it. `RAID_TARGET_UPDATE` updates every plate.

### 3.8 Cast bars on plates

- **Centralized dispatcher** (`EUI_Nameplates_Events.lua:41-60`): one frame registers all 13
  `UNIT_SPELLCAST_*` events *globally* (no unit filter). It looks up `ns.plates[unit]` and
  calls `plate[event](plate, unit, ...)`. This replaces 13 `RegisterUnitEvent` calls per
  plate.
- **UpdateCast** (`EUI_Nameplates_Cast.lua:~150-260`): the same duration-object pattern.
  `UnitEmpoweredChannelDuration(unit, true)` is tried first for channels, because
  `UnitChannelDuration` can return nil during the empower phase. Then
  `cast:SetTimerDuration(durObj, nil, direction)`.
- **Fallback:** if the duration API is missing, mirror Blizzard's own castBar
  (`bc:GetMinMaxValues()` / `bc:GetValue()`) in an OnUpdate (`EUI_Nameplates_Plate.lua:242-280`).
- **Cast timer text:** a 10 Hz *animation ticker* (`EllesmereUI.Tick.NewAnimTicker`) instead
  of per-frame OnUpdate. It writes `castTimer:SetFormattedText("%.1f",
  durObj:GetRemainingDuration())` (`EUI_Nameplates_PlatePool.lua:561-597`). The comment
  measured the old accumulator at 60.8 ms/min in a caster-heavy pull.
- **Cast colors** (`ApplyCastColor`, `EUI_Nameplates_Cast.lua:310-390`):
  - Important cast color: `isImp` from `pcall(C_Spell.IsSpellImportant, spellID)`, blended
    per channel: `r = EvaluateColorValueFromBoolean(isImp, impR, underR)`.
  - Uninterruptible: the same fold with `isUnint`. A nil is replaced by `false` via a `type()`
    check first, because "a nil reaching the fold throws".
  - Final: `cast:GetStatusBarTexture():SetVertexColor(cr, cg, cb)` with possibly secret
    components.
  - Overlay and shield: `castBarOverlay:SetAlphaFromBoolean(uninterruptible)`,
    `castShieldFrame:SetAlphaFromBoolean(uninterruptible)`.
- **Kick tick on plates:** the same positioner/marker technique as the unit frames
  (`EUI_Nameplates_Cast.lua:420-620`). One `SPELL_UPDATE_COOLDOWN` watcher refreshes cached
  cast identity on every casting plate, without re-reading cast info.
- **Cast target name:** `UnitShouldDisplaySpellTargetName(unit)` gates
  `UnitSpellTargetName(unit)`, which can be a secret string and goes straight to `SetText`.
  `UnitSpellTargetClass(unit)` can be a secret token and goes to
  `C_ClassColor.GetClassColor`. Nil checks always use `type()`
  (`EUI_Nameplates_Plate.lua:324-360`).

### 3.9 Auras on plates (AuraContainers)

`EUI_Nameplates_AuraContainers.lua`:

- Each plate gets a **bundle of three containers** (debuffs, enemy buffs, CC) from a
  pre-built pool. Container creation became combat-legal in build 68914, but pre-building
  avoids spikes. Pool exhaustion queues on-demand builds.
- Blizzard's per-plate `debuffList` / `buffList` are taint-locked and unreadable in 12.1.
  EUI reproduces Blizzard's rule: fetch `HARMFUL|INCLUDE_NAME_PLATE_ONLY` and keep auras
  with `nameplateShowPersonal`. The group uses the filter tokens
  `{ "HARMFUL", "PLAYER", "INCLUDE_NAME_PLATE_ONLY", "!CROWD_CONTROL" }` plus the
  candidate filter `{ nameplateShowPersonal = true }`.
- Engine filter tokens used: `HARMFUL`, `HELPFUL`, `PLAYER`, `INCLUDE_NAME_PLATE_ONLY`,
  `CROWD_CONTROL`, `RAID`, `RAID_IN_COMBAT`, `RAID_PLAYER_DISPELLABLE`, and
  `AuraUtil.AuraFilters.Dispellable` / `.Important` (enemy buffs worth showing). A `!`
  prefix negates.
- **Candidate filters** (per group, changeable live with `container:SetAuraGroupCandidateFilters`):
  `includeSpellIDs`, exclude lists, `includeDispelTypes`, boolean aura fields such as
  `nameplateShowPersonal`.
- Group filter **strings are fixed at declaration**. When the user changes a filter, a new
  keyed group variant is declared and the old one is parked at cap 0
  (`AK.SetGroupCap(container, key, 0)`). From 12.1.5 a cap of 0 also disables the group
  with `SetAuraGroupEnabled`.
- Negation chains ("raid" = `RAID` ∪ `RAID_IN_COMBAT`, implemented as group 1 `RAID` and
  group 2 `RAID_IN_COMBAT|!RAID`) give unions without double rendering.
- **Debuff-colored health bars** (`EllesmereUINameplates_DebuffColors.lua`; credited by
  the author to Jeebz/PlateTweaks, used with permission). The plate needs "tint the bar
  orange while my Rip is on it" without reading aura payloads. Declarative aura **slots**
  with `includeSpellIDs` own the *visibility* of a tint texture over the bar. The engine
  shows the slot's registered texture when the aura exists. Lua never reads the aura or
  checks button visibility.

### 3.10 Class power on the target plate

`EUI_Nameplates_ClassPower.lua`: zero cost when disabled. When enabled, one watcher on the
player's `UNIT_POWER_UPDATE` (plus `UNIT_AURA` for some specs) draws pips only on the
current target's plate (`ns._cachedTargetPlate`).

### 3.11 Mouseover

A unified ticker exists only while some plate is hovered (`ns._EnsureMouseoverTicker`).
`UPDATE_MOUSEOVER_UNIT` + `GLOBAL_MOUSE_UP` re-evaluation.

---

## 4. Raid and party frames (EllesmereUIRaidFrames)

### 4.1 Headers

`ns._BuildHeaderSet(merge)` (`EUI_RaidFrames_Layout.lua:38-150`):

- **Separated mode:** 8 `SecureGroupHeaderTemplate` headers (`ERFGroupHeader1..8`), each
  with `groupFilter = tostring(group)`, `unitsPerColumn=5`, `maxColumns=1`,
  `sortMethod="INDEX"`.
- **Merged mode:** one flat header (`ERFFlatHeader`) with `groupFilter="1,...,8"`,
  `maxColumns=8`, `columnSpacing` and `columnAnchorPoint` derived from growth directions.
- Common attributes: `template = "SecureUnitButtonTemplate"`, `templateType = "Button"`,
  `showRaid/showParty/showPlayer = true`, `showSolo` from the setting, and
  **`auraContainerTemplate = "CustomAuraContainerTemplate"`**. The 12.1 header creates an
  AuraContainer per child, secure-side. The code calls this "the only combat-legal
  container source", which covers in-combat `/reload` and roster growth mid-combat.
- `initialConfigFunction` is a restricted snippet that sets width and height from
  pixel-snapped settings.
- **Pre-spawn trick:** `SetAttribute("startingIndex", -4)`, `Show()`, then
  `SetAttribute("startingIndex", 1)`. This makes the header create all 5 buttons per group
  out of combat. A header only creates children while visible, so the container is
  briefly shown if it was hidden.
- Only the active mode's headers are built at login. The other mode is built on first
  flip, and combat defers it.
- **Party:** `ERFPartyHeader` (one header, `showRaid=true` so arenas and "small raid"
  mode work) plus a separate `ERFPartySelfButton` (`EUI_RaidFrames_Party.lua:562-625`).
- **Pets:** `SecureGroupPetHeaderTemplate` (`EUI_RaidFrames_PetFrames.lua:514`).
- **Extra frames / boss frames / party targets:** standalone `SecureUnitButtonTemplate`
  buttons with `RegisterUnitWatch` (`EUI_RaidFrames_ExtraFrames.lua:358`,
  `EUI_RaidFrames_BossFrames.lua:404`, `EUI_RaidFrames_PartyTargets.lua:687`).
  Friendly boss frames use `RegisterAttributeDriver(controller, "state-fb"..i, "[@boss"..i..",help] 1; 0")`.
- Visibility uses `RegisterStateDriver(container, "visibility", rule)`
  (`EUI_RaidFrames_Visibility.lua:377-381`).
- Blizzard compact raid/party frames are suppressed through the core
  (`EllesmereUI_BlizzardParty.lua`, `EUI_RaidFrames_Compact.lua`).
- Button state lives only in FFD. Buttons get `HookScript`, never `SetScript`, so the
  header's own handlers survive.
- `OnAttributeChanged("unit")` hook (`EUI_RaidFrames_Style.lua:1109-1130`) remaps the
  unit→button routing and repaints at once. It also re-anchors private auras, which
  "the engine drops on unit reassignment even when the token string is unchanged".

### 4.2 Events and per-unit trackers

`EUI_RaidFrames_Lifecycle.lua:331-412`:

- Global `eventFrame`: roster, leader, roles, raid targets, target change, ready check,
  summon/rez, combat, PEW, phase, encounter start/end, spec change.
- **One tracker frame per unit token** (`player`, `party1-4`, `raid1-40`), each with
  `RegisterUnitEvent(ev, unit)` for:
  - `UNIT_HEALTH`, `UNIT_MAXHEALTH`;
  - `UNIT_ABSORB_AMOUNT_CHANGED`, `UNIT_HEAL_ABSORB_AMOUNT_CHANGED`;
  - `UNIT_MAX_HEALTH_MODIFIERS_CHANGED`;
  - `UNIT_NAME_UPDATE`;
  - `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`;
  - `PLAYER_FLAGS_CHANGED`, `UNIT_CONNECTION`, `UNIT_IN_RANGE_UPDATE`;
  - `UNIT_POWER_UPDATE`, `UNIT_DISPLAYPOWER`.

  Units that do not exist never fire, so this costs nothing.
- `UNIT_HEAL_PREDICTION` is registered only while some view shows heal prediction
  (`ns._RFSyncPredRegistration`). The comment says it "fires on every healer cast at
  every target".
- `UNIT_AURA` is **deliberately absent** from health and absorb paths. The same armed-belt
  approach as the unit frames covers timer-expired shields.
- `UNIT_LEVEL` and `UNIT_TARGET` are opt-in and synced across trackers.
- `OnEvent` (`EUI_RaidFrames_Events.lua:49+`) handles the hot per-unit branches first
  (`UNIT_HEALTH` → `ns._UpdateButtonHealth(btn, unit)` through a
  `unitToButton[unit] or ns._partyUnitToButton[unit]` map).
- Absorb events "arm" the button and mark it dirty. A coalescer paints once per rendered
  frame.

### 4.3 Health bar: a percent bar

`ns._UpdateButtonHealth` (`EUI_RaidFrames_Update.lua:1147-1238`). This is a **different
approach from the unit frames**:

- The bar range is fixed `(0, 100)`, set once (`d._hb100`).
- Value: `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)`. With inverted fill it
  uses `CurveConstants.ReverseTo100` (`EUI_RaidFrames_Colors.lua:44-47`). This needs no
  `UNIT_MAXHEALTH` bookkeeping. Optional smoothing:
  `SetValue(pct, Enum.StatusBarInterpolation.ExponentialEaseOut)`.
- Class color: the class token is cached per occupant in FFD (`d._clsTok`) and cleared on
  unit assignment, `UNIT_NAME_UPDATE` and `UNIT_CONNECTION`. A secret token is never
  cached. It falls back to grey each tick.
- Curve modes (`classic` / `customDynamic` / `classReactive`):
  `UnitHealthPercent(unit, true, curve)` returns a color that goes to
  `SetStatusBarColor(r,g,b,a)` on every tick (`EUI_RaidFrames_Colors.lua:410-440`).
- Static modes keep a value cache (`d._hcR...`), because "every static-mode component is a
  plain value by construction".
- Status text (DEAD / OFFLINE / AFK), dead/offline background tint and resurrection
  latches ride the same function.

### 4.4 Absorbs, overshield and heal prediction (raid)

`EUI_RaidFrames_Absorb.lua`:

- Per-button calculator: `SetMaximumHealthMode(Default)` and
  **`SetDamageAbsorbClampMode(Enum.UnitDamageAbsorbClampMode.MissingHealth)`**
  (`:556-569`). With the MissingHealth clamp, **the second return of
  `calc:GetDamageAbsorbs()` is a boolean "absorb exceeds missing health"**. That is a
  ready-made overshield flag, possibly secret.
- The bars still get the full `UnitGetTotalAbsorbs(unit)`, so overflow and backfill render.
- Overshield glow and spark: `spark:SetAlphaFromBoolean(isClamped, 1, 0)` or `(isClamped, 0, 1)`
  (`:1159-1182`).
- Incoming heals: `calc:GetIncomingHeals()` after `UnitGetDetailedHealPrediction(unit, nil, calc)`,
  gated on the feature being on.
- Identical-state short-circuit with secret fail-open (`:890-905`).

### 4.5 Power, text, range

- Power: `UnitPowerPercent(unit, pType, true, CurveConstants.ScaleTo100)` into a 0-100 bar.
  Text: `sformat("%.0f", ppct)` (`EUI_RaidFrames_Colors.lua:836`, `EUI_RaidFrames_Update.lua:573`).
- Missing health text: `C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit, true))`
  (`EUI_RaidFrames_Colors.lua:983-984`). `UnitHealthMissing` is a 12.x API.
- Absorb and heal-absorb text: `C_StringUtil.TruncateWhenZero(amount)` (`:849`, `:1007`).
- Range: `UNIT_IN_RANGE_UPDATE`, then `UnitInRange(unit)`, which can be a secret boolean.
  Then `btn:SetAlphaFromBoolean(inRange, bmA * inAlpha, bmA * outAlpha)`
  (`EUI_RaidFrames_Visibility.lua:80-97`). A tighter friendly-spell range refinement uses
  `C_Spell.IsSpellInRange`. Range alpha is multiplied with the Buff Manager's alpha, and
  each system stores its own factor.

### 4.6 Dispel highlighting

- Dispel type → color is **a step `ColorCurve` keyed by the engine's dispel-type enum**: 0
  none, 1 Magic, 2 Curse, 3 Disease, 4 Poison, 9 Enrage, 11 Bleed. Per-type alpha rides
  the curve (alpha 0 = type opted out). Dark variants (×0.5) are built at curve-build time
  from plain colors (`ns._RebuildDispelCurves`, `EUI_RaidFrames_Update.lua:720-770`). The
  comment says `GetAuraDispelTypeColor` evaluates such a curve against the secret dispel
  type internally.
- Inside aura containers the engine tints registered textures itself:
  `button:AddDispelTypeTexture(tex, { style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset | Border | Icon, ... })`
  plus a `customDispelColorMap = { Magic = Color, Curse = Color, ... }`
  (`ns.RFC_DispelBorderColorMap`, `EUI_RaidFrames_AuraContainers.lua:620-635`). Registration
  makes the texture's alpha, vertex color, shown state and texcoords **engine-owned secret
  aspects**. Lua must set its neutral white base once, before registration, and never
  write those again (AuraKit `:515-640`).
- "Dispellable by me": the filter `HARMFUL|RAID_PLAYER_DISPELLABLE`. The comment warns:
  never branch on a possibly secret auraInstanceID, because negating
  `IsAuraFilteredOutByInstanceID` on it was nondeterministic for secret boss debuffs.
  Shaman Poison Cleansing Totem is special-cased, because `RAID_PLAYER_DISPELLABLE` only
  knows class and spec dispels.

### 4.7 Aura containers on raid buttons

`EUI_RaidFrames_AuraContainers.lua` (3.7k), `EUI_RaidFrames_DebuffManager.lua` (3.8k),
`EUI_RaidFrames_BuffManager.lua` / `BuffManager2.lua`:

- Debuff groups (`:43-50`): `cc` = `HARMFUL|CROWD_CONTROL` (declared first so it leads the
  row), `all` = `HARMFUL|!CROWD_CONTROL`, and lazily `raid`, `raidcombat` and
  `dispellable`. Lazy groups are declared on demand (combat-legal), because every
  `AddAuraGroup` eagerly allocates a 10-button engine batch.
- Sated/exhaustion and other always-hidden debuffs are excluded with spell-ID candidate filters.
- Unbound containers must use unit token `"none"`, never `"player"`. Otherwise an unbound
  container streams the player's own auras onto the button (`:16-20`).
- The Buff Manager has indicator types (icons, squares, bars) with duration-threshold
  colors: a step `ColorCurve` with points (0, warn color) and (threshold, normal color),
  passed in the SetDurationText options as `textColor = { curve, property }`
  (`:1325-1370`). The engine colors the countdown text when the remaining time drops below
  N seconds.

### 4.8 Click-casting

`EUI_RaidFrames_ClickCast.lua` (4.9k). Two paths:

1. **Frame-based:** for every registered frame, `header:WrapScript(frame, "OnEnter"/"OnLeave", body)`.
   `header` is a `SecureHandlerStateTemplate` named `EUIClickCastHeader`. The OnEnter body
   records the hovered frame and runs the per-frame keyboard binding setup
   (`SetBindingClick` within the restricted environment). Mouse-button bindings are
   applied directly as attributes (`[mods]type[N]`, `spell[N]`, `macrotext[N]`).
2. **Hovercast:** persistent bindings on a dedicated secure button that targets
   `@mouseover`, with friend/harm filtered through macro conditionals. It is toggled by
   `RegisterStateDriver(header, "eui_cc", "[@mouseover,exists] on; off")`. State values are
   deliberately non-numeric, because the driver runs `tonumber()` on values and "1" would
   become the number 1.

Other details:

- Out-of-combat-only actions (menu, target) use
  `RegisterAttributeDriver(frame, "type1", "[combat] none; target")`. `"none"`, not nil,
  because nil falls back to the `*type2` wildcard.
- **ClickCastFrames interop:** `ClickCastFrames` is replaced with a metatable proxy that
  captures frames registered by any addon (`SetupClickCastFramesHook`, `:2148-2160`). When
  EUI click-casting is off, its frames are handed back to other consumers (Clique), and
  `ClickCastFrames[frame] = nil` tells them to drop it.
- Per-spec bindings. Class dispel and external presets are filtered by
  `C_SpellBook.IsSpellKnown`.

### 4.9 Options preview

The `EUI_RaidFrames_Preview*.lua` files build non-secure fake frames with fake data, so the
options panel can show raid and party layouts without a group. `PLAYER_REGEN_DISABLED`
force-restores real frames (`EUI_RaidFrames_Events.lua:115-128`).

---

## 5. AuraKit: the 12.1 AuraContainer engine (core, required context)

All aura displays above go through `EllesmereUI_AuraKit.lua`. What SoulUI needs to know
about the Blizzard API, as observed from EUI's usage:

- `C_AddOns.LoadAddOn("Blizzard_AuraContainer")` if not loaded, then
  `CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")` (`:1606-1610`).
  The intrinsic is born on unit `"none"`. Call `container:SetUnit(unit)`.
- Layout setters, with two API generations probed:
  - `SetFlowLayoutPadding` / `SetAuraLayoutPadding`;
  - `SetFlowLayoutMaximumLineSize` / `SetAuraLayoutRowWidth`;
  - `SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal|Vertical)` (68914+);
  - anchor point and growth setters.

  The container needs a non-zero provisional size, because the engine's parse and layout
  OnUpdate runs only while it is visible.
- `container:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, ...)`.
- `container:AddAuraGroup(key, filterString, { maxFrameCount, sortMethod, sortDirection,
  candidateFilters, initializeFrame = fn(button), layout = { elementWidth, elementHeight,
  elementSpacing, lineSpacing } })`. Each call eagerly creates a batch of 10 buttons
  (about 4-6 ms), so EUI spreads builds over frames with a "build worker" scheduler.
- `container:AddAuraSlot(key, filterString, { candidateFilters, sortMethod, initializeFrame })`
  creates one fixed frame that shows the best matching aura.
- `container:SetAuraGroupMaxFrameCount(key, n)`,
  `container:SetAuraGroupEnabled(key, bool)` (12.1.5),
  `container:SetAuraGroupCandidateFilters(key, tbl)`.
- **Filter strings must be byte-identical to share one engine scan.** `AK.Filter`
  normalizes them: polarity first, then the rest sorted alphabetically, with `!X` sorted
  right after `X` (`:16-58`).
- **Button registration** (inside `initializeFrame`, the "creation window", where every
  call is legal):
  - `button:SetIcon(texture)`;
  - `button:SetDurationCooldown(cooldownFrame)`;
  - `button:SetApplicationCount(fontString, {})`;
  - `button:SetDurationText(fontString, { textFormatter = NumericRuleFormatter, textColor = { curve, property } })`;
  - `button:SetCancelAuraButtons(...)` (right-click cancel on player buffs);
  - `button:AddDispelTypeTexture(tex, opts)` (older `SetAuraBorder`);
  - `button:AddAuraShownAnimation(animGroup)` (12.1.5, played when the button shows an aura).
- **Restriction:** while `C_Secrets.ShouldAurasBeSecret()` is true (or a probe
  `pcall(C_UnitAuras.GetAuraDataByIndex, "player", 1, "HELPFUL")` fails), **the button
  subtree refuses calls from addon code outside the creation window**.
  `AK.AurasRestricted()` (`:2350-2362`) detects this. Restyles are deferred to the lift
  (`AK.DeferRestyle`). Button rects are restricted too, so decoration anchors to holders
  (`SetAllPoints`) and never reads the button's size.
- **Duration text formatter:** `C_StringUtil.CreateNumericRuleFormatter()` +
  `SetBreakpoints({ {threshold, format, rounding = Enum.NumericRuleFormatRounding.Up|Nearest,
  step, components = {{div=60},{mod=60}}} ... })`. Bands: seconds, then `m` from 90 s, `h`
  from 90 min, `d` from 36 h. `C_StringUtil.CreateSecondsFormatter()` also exists.

---

## 6. Resource bars (EllesmereUIResourceBars)

### 6.1 What it is

Standalone player bars: health, primary power, secondary class resource, cast bar, GCD
bar, swing timer, totem and call-totem bars, and special trackers (Ebon Might, Arcane Soul,
warrior charges, druid mana in forms). Positions go through Unlock mode with pixel
snapping (`SnapXY`, `EllesmereUIResourceBars.lua:18-31`).

### 6.2 Events

`EUI_ResourceBars_Events.lua:750-850`. One event frame:

- `RegisterUnitEvent(..., "player")` for `UNIT_HEALTH`, `UNIT_MAXHEALTH`,
  `UNIT_MAX_HEALTH_MODIFIERS_CHANGED`, **`UNIT_POWER_FREQUENT`**, `UNIT_MAXPOWER`, `UNIT_AURA`,
  `UNIT_ABSORB_AMOUNT_CHANGED`, all `UNIT_SPELLCAST_*`, `UNIT_POWER_POINT_CHARGE` and vehicle
  enter/exit.
- Global events: `RUNE_POWER_UPDATE`, combat, target change, mount/glide/resting, zone,
  roster, spec/talent/shapeshift.
- Talent changes are debounced (`ns.ScheduleTalentApply`).
- A 10 fps safety poll exists for the secondary resource. A value memo (`ns.SecSt`) skips
  redraws when value, max, config generation, active buff and spender winner are unchanged
  (profiled at 12.2 % → 2.9 %). The memo skips secret values.

### 6.3 Primary power and health

- Bar `SetValue(UnitPower(...))` (possibly secret) for display.
- Percent text: `UnitPowerPercent("player", type, true, CurveConstants.ScaleTo100)`.
- **Threshold coloring** (`EUI_ResourceBars_Thresholds.lua:290-335`): a step color curve
  with the threshold color at or below t, an epsilon step, and the base color above. It is
  evaluated with `UnitPowerPercent("player", type, false, curve)` inside a pcall, and the
  result goes to `SetStatusBarColor`. The cache uses direct numeric comparison of 7 inputs,
  not a format() hash, because it runs about 30 times a second.
- **"Show when missing" reveal** (`EUI_ResourceBars_Update.lua:2671-2730`): a step curve
  (0 → 1, 1 → 0) through `UnitPowerPercent`/`UnitHealthPercent`. Note `usePredicted=false`
  here. The result goes to `wrapper:SetAlpha(a)`. The bar shows only while not full,
  decided C-side. `SetAlpha` accepts the secret number.
- Text "hide at zero": `pcall(C_StringUtil.TruncateWhenZero, v)` for secret counts
  (`EllesmereUIResourceBars.lua:63-69`).

### 6.4 Class resources

`UpdateSecondaryResource` (`EUI_ResourceBars_Update.lua` ~1270-2600):

- **Points** (combo, holy power, chi, arcane charges, soul shards, essence):
  - Plain value: the normal pip path with thresholds and bands.
  - Charged combo points: `GetUnitChargedPowerPoints("player")` returns a list of indices.
    `UNIT_POWER_POINT_CHARGE` drops the memo.
  - Destruction soul shards: `UnitPower("player", SOUL_SHARDS, true) / 10` for fractions,
    only when not secret.
  - **Essence:** `UnitPower` has no partial for essence, so the recharge pip is timed in
    Lua from `GetPowerRegenForPowerType(ESSENCE)` (`:531`). A timer starts when the count
    drops below max.
  - **Secret value:** the pip-gate StatusBar per pip with `SetMinMaxValues(i-1, i)` and
    `SetValue(cur)` (`:2147-2178`). **Threshold bands as stacked gates:** one extra
    StatusBar per band per pip with range `(max(i, bandStart) - 1, max(i, bandStart))`.
    Higher bands sit on higher frame levels, so the topmost reached band colors the pip.
    No compare needed.
- **Runes:** `GetRuneCooldown(i)` for i = 1..6 returns plain start, duration, ready. Order
  is ready runes first, then by remaining time. Driven by `RUNE_POWER_UPDATE`.
- **Stagger:** `UnitStagger("player")` against `UnitHealthMax`.
- Bar-type resources (maelstrom, insanity, focus, lunar power, stagger as bar) use
  `UnitPower`.
- Blizzard class art option: `EUI_ResourceBars_BlizzClassArt.lua` re-hosts Blizzard's own
  class power frames.

### 6.5 Cast bar, GCD bar, swing timer: duration objects everywhere

- Player cast bar: `ns.ApplyCastTimer(kind)` (`EUI_ResourceBars_CastBar.lua:994-1020`) calls
  `sb:SetTimerDuration(durObj, nil, dir)` and then `sb:SetToTargetValue()`. Without that
  call, the fill sweeps in from the previous cast's position.
- GCD: `C_Spell.GetSpellCooldownDuration(EllesmereUI.GCD_SPELL)` returns a duration object,
  then `SetTimerDuration`. Field finding (2026-08-08, `EUI_ResourceBars_GCD.lua:35-66`):
  **a completed bar timer keeps painting its final state even after `SetValue(0)`**. The
  idle look is set by *re-arming* a finished duration object in the direction that paints
  the wanted state. RemainingTime on a finished duration paints empty. ElapsedTime paints
  full. After a cancelled cast, a *fresh* duration object is fetched, because the stored
  one is stale (refunded GCD).
- Swing timer (`EUI_ResourceBars_SwingTimer.lua`):
  - `C_DurationUtil.CreateDuration()` gives a reusable duration object. It is filled with
    `obj:SetTimeFromStart(startTime, duration)` from plain swing math and handed to
    `bar:SetTimerDuration(obj, IMMEDIATE, dir)`.
  - Countdown text: `C_DurationUtil.CreateDurationTextBinding()` with
    `:SetFontString(fs)`, `:SetDuration(obj)`, `:SetFormatter(numericRuleFormatter)`,
    `:SetUpdateInterval(0.05)`, `:SetExpiredText("")`, `:SetZeroDurationText("")` and
    `:SetEnabled(bool)` (`:399-409`). **The engine updates the text.** No Lua OnUpdate.
  - Formatter fallback: try a rule table that blanks the last 0.05 s. If `SetBreakpoints`
    rejects it (pcall), use plain `%.1f`.
  - `UNIT_ATTACK_SPEED` resyncs.

---

## 7. Cooldown Manager (EllesmereUICooldownManager)

### 7.1 Why hook Blizzard's viewer instead of tracking cooldowns yourself

In 12.x, spell cooldown start and duration, charge counts and aura data are **secret in
restricted content**. `C_Spell.GetSpellCooldown(id)` still returns a table, but only
`isActive` and `isOnGCD` are plain booleans. The comment calls them "clean bools", and the
code reads them bare (`EUI_CDM_HookDecorate.lua:394, 437, 789`). Timing must go through
`C_Spell.GetSpellCooldownDuration(id)` / `GetSpellChargeDuration(id)` duration objects into
`Cooldown:SetCooldownFromDurationObject`. Stack and charge counts
(`GetSpellDisplayCount`, `GetSpellCastCount`, aura `applications`) are secret.

Blizzard's own **Cooldown Manager** (`CooldownViewer` frames, data from
`C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)` and
`GetCooldownViewerCategorySet(category)`) is privileged. Its item frames bind cooldowns,
auras, charges, "active" glow state and linked spell IDs correctly, including buffs whose
aura data a tainted addon cannot read. EUI's stated principle (`EllesmereUICdmHooks.lua:4-19`):

> Blizzard manages all cooldown/buff state. We only restyle and reposition.

Taint rules: never `SetParent`, `SetScale`, `Hide` or `Show` a Blizzard CDM frame, never
move it offscreen (except parking, below), and never write keys onto its tables. Unclaimed
frames get `SetAlpha(0)` and claimed frames `SetAlpha(1)`.

### 7.2 Mechanics

- **Category mapping:** EUI bar `cooldowns`/`utility` take viewer categories 0+1 (Essential +
  Utility), and `buffs` takes 2+3 (tracked buff + tracked debuff)
  (`EUI_CDM_Blizzard.lua:39-44`). Users can create up to 20 custom bars.
- **First login:** `CaptureCDMPositions` measures Blizzard's viewers: icon size from child
  width × scale, spacing from the smallest left-edge step, row count from distinct Y
  values, orientation from `frame.isHorizontal`. EUI's bars start where the user had
  Blizzard's.
- **HideBlizzardCDM** (`EUI_CDM_Blizzard.lua:647-688`): the primary viewers are **not**
  moved or hidden. Mouse is disabled out of combat, and original points are stored for
  restore. Only `BuffBarCooldownViewer` is alpha-0 and parked offscreen
  (`ns.ParkSecondaryBuffViewer`), because EUI renders its own Tracked Buff Bars.
- **Hooks** (`EUI_CDM_HookViewers.lua:127-260`):
  - `hooksecurefunc(CooldownViewerBuffIconItemMixin|BuffBarItemMixin, "OnCooldownIDSet", ...)`
    clears the per-frame spell cache and queues a reanchor. Buffs are dynamic.
  - `Essential/UtilityItemMixin.OnCooldownIDSet` only clears the cache. Those sets change
    only on spec, talent or equipment changes (full rebuild). The comment says real-time
    reanchors there are "catastrophic" when Blizzard rebuilds pools constantly (example:
    Lightsmith Holy Armaments).
  - Mixin hooks do not reach frames created before install, because mixin functions are
    copied per instance. Per-frame hooks are added lazily where needed.
  - `hooksecurefunc(viewer.itemFramePool, "Acquire", ...)` catches new frames.
    `hooksecurefunc(viewer, "RefreshLayout", RestoreViewerAnchors)` re-applies EUI anchors
    *after* Blizzard's layout measurement.
  - Per-frame `hooksecurefunc(frame, "OnActiveStateChanged")` triggers a deferred
    reanchor (two-frame defer, coalesced).
- **Reanchor queue:** a dirty flag plus an OnUpdate throttled to 0.2 s runs
  `CollectAndReanchor()`. That function walks the viewer pools, resolves each frame's spell
  (base, override and linked IDs, with a variant ledger for dual-ID spells), assigns it to
  an EUI bar, and computes `fd._cdmAnchor`.
- **Anchoring** (`EUI_CDM_HookDecorate.lua:44-70`): `frame:ClearAllPoints()` +
  `SetPoint(anchorOnEUIBar)` for claimed frames. Unclaimed decorated frames are parked at
  `TOPLEFT, UIParent, -10000, 10000`. Anchors are applied only after the viewer's layout
  pass. If an icon moves mid-layout, the viewer measures the gap as its own size and
  shifts Blizzard's bottom stack.
- **Decoration:** EUI-owned textures (background, border, glow overlay, custom shape masks,
  keybind text, charge text) are created *on* the Blizzard item frame. Creating child
  regions is allowed; writing fields is not, so state goes in `hookFrameData`.
- **Cooldown swipe control** (`EUI_CDM_HookDecorate.lua:380-1030`). It hooks the item's
  Cooldown widget (`hooksecurefunc(cd, "SetCooldownFromDurationObject" / "SetCooldown")`):
  - Suppress GCD: `C_Spell.GetSpellCooldown(effectiveID).isOnGCD` gives a plain bool,
    then `cd:SetSwipeColor(0,0,0,0)`.
  - Charge spells: when a recharge is running, do not suppress. Only the last GCD-length
    slice of the recharge is hidden, through `ns.GCDTailAlpha(durObj, alpha)`
    (`EUI_CDM_HookTrinkets.lua:631-656`). That is a step curve (0 → 0, gcdLen → alpha)
    evaluated by `durObj:EvaluateRemainingDuration(curve, default)`. GCD length is
    `1.5 / (1 + UnitSpellHaste/100)`. Haste is secret in instanced combat, which falls
    back to 0.
  - Re-assert the real cooldown after aura display ends:
    `cd:SetUseAuraDisplayTime(false)` + `cd:SetCooldownFromDurationObject(C_Spell.GetSpellCooldownDuration(id))`.
  - Override IDs: `C_SpellBook.FindSpellOverrideByID(sid)`. Queries must use the override
    ID, because a transform's real CD ticks on the override.
  - Desaturation from a duration: a step curve (0 → 0, 0.001 → 1) with
    `tex:SetDesaturation(durObj:EvaluateRemainingDuration(curve, 0))` (`:658-676`). The
    icon is grey while on cooldown, without reading the time.
- **Out of range tint:** `frame.spellOutOfRange` (a Blizzard field, possibly secret
  boolean) feeds `tex:SetVertexColorFromBoolean(oor, redColor, baseColor)`
  (`EUI_CDM_HookIconWatch.lua:1546-1555`).
- **Stack count text:** `C_StringUtil.TruncateWhenZero(C_Spell.GetSpellDisplayCount(sid))`
  inside a pcall (`EUI_CDM_HookPresetCooldowns.lua:401-420`).
- **Glow at stacks** (`EllesmereUICdmHooks.lua:34-80+`). Stack counts are secret, so
  "glow when stacks ≥ N" uses one-unit StatusBar "gates": range `(N-1, N)`, value = stacks.
  The gate's fill edge drives a `CLAMPTOBLACKADDITIVE` mask texture over the glow, so the
  glow is visible only where the gate filled. A lower and an upper bound combine for
  equality. The comment notes masks keep working where `SetClipsChildren` "goes dark on
  secret-derived rects".
- **Cooldown text formatter:** `cd:SetCountdownFormatter(numericRuleFormatter)`
  (`EUI_CDM_Icons.lua:396-500`). The engine formats the countdown (decimals below N
  seconds, color-wrapped text) with no OnUpdate.
- **Aura reads with secret guards:** `frame.auraInstanceID` / `frame.auraDataUnit` (Blizzard
  item fields) are checked with `issecretvalue` first, then read with
  `pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, iid)`. Under secrecy the id-keyed
  APIs hard-error, so the code falls back to `frame.auraDataCached.applications`, which may
  be secret and goes only to sinks (`EllesmereUICdmHooks.lua:94-116`).
- **`C_Secrets` probes:** `C_Secrets.ShouldAurasBeSecret()` and
  `C_Secrets.ShouldSpellAuraBeSecret(spellID)` decide whether a druid form-exception aura
  can be read at all (`EUI_CDM_HookIconWatch.lua:844-848`). Tooltip tables are checked
  with `canaccesstable(t)` (`:729-731`).
- **Tracked Buff Bars** (`EUI_CDM_BuffBar*.lua`) replace `BuffBarCooldownViewer`. They
  mirror Blizzard's bar items (active state, linked spell IDs) into EUI StatusBars driven
  by `SetTimerDuration(durObj, Immediate, ElapsedTime)`. Charge count goes to a second bar
  with `SetValue(currentCharges)`; the comment says "SetValue is a supported secret sink"
  (`EUI_CDM_BuffBarCooldown.lua:300-312`).
- **Trinkets and custom spells** (`EUI_CDM_HookTrinkets.lua`, `HookPresetCooldowns.lua`): EUI
  owns these frames, so they use `GetInventoryItemCooldown` / `C_Item.GetItemCooldown`
  (plain for items) and `C_Spell.GetSpellCooldownDuration` objects for spells.
- **Focus kick** (`EUI_CDM_FocusKick.lua`): interrupt-on-focus helper (macro factory in core).

---

## 8. Events and performance patterns (cross-module)

| Pattern | Where | Notes |
|---|---|---|
| Per-unit tracker frames with `RegisterUnitEvent` | UF engine, RF lifecycle | C-side filter. One or two units per call. Non-existent units cost nothing. |
| Global dispatcher keyed by unit | NP cast events | One `RegisterEvent` instead of 13 per plate. O(1) `ns.plates[unit]` lookup. |
| Same-frame dedupe by generation stamp | UF engine `Paint` | Collapses stacked triggers. Never dedupes cast or identity events. |
| Next-frame value flush | UF `UNIT_POWER_FREQUENT` | At most one paint per frame. |
| Resettle repaint at `C_Timer.After(0)` | UF/RF max-health | Fixes two-step max/value landings. |
| Lean path or memo keyed by display granularity | NP health text, RF/UF absorbs, RB secondary | Any secret fails open (paint) and invalidates the memo. |
| Armed belt ticker | UF/RF absorbs | Exists only while needed. Replaces `UNIT_AURA`. |
| Opt-in event registration | UF `SetChannelOn`, RF heal prediction, NP `UNIT_TARGET`/`UNIT_FLAGS` | Features that are off register no events. |
| Pool prewarm, deferred non-critical setup | NP | Smooths AoE pulls. |
| Engine-driven timers | Casts, GCD, swing, CDM | `SetTimerDuration`, `SetCooldownFromDurationObject`, duration text bindings, countdown formatters. |
| Anim-group tickers instead of OnUpdate | NP cast timer (`EllesmereUI.Tick.NewAnimTicker`) | The engine sleeps between fires. |
| Self-hiding OnUpdate drivers | NP scale anim, CDM reanchor, UF pred flush | OnUpdate runs only while shown. |
| CPU-attribution shells | CDM, RF | Pre-created frames bill the right addon. |

`UNIT_HEALTH` in Midnight fires per change (unthrottled). EUI never throttles health
itself. It makes each paint cheap (one `SetValue`) and moves extras to opt-in channels.

---

## 9. Midnight secret-value cookbook

This section collects every technique observed, as rules SoulUI can adopt. "Secret" means
the value is a secret value as reported by `issecretvalue(v)`.

### 9.1 What you may and may not do with a secret

Observed **allowed**:

- `issecretvalue(v)`, `type(v)` (returns the underlying type), `canaccessvalue(v)`,
  `canaccesstable(t)`.
- Passing it to whitelisted widget setters:
  - `StatusBar:SetValue`, `SetMinMaxValues`, `SetStatusBarColor`;
  - `Texture:SetVertexColor`, `Region:SetAlpha` (number);
  - `FontString:SetText` / `SetFormattedText`;
  - `SetAlphaFromBoolean`, `SetVertexColorFromBoolean`;
  - `SetRaidTargetIconTexture`;
  - `C_ClassColor.GetClassColor(secretToken)`;
  - `Cooldown:SetCooldownFromDurationObject`, `StatusBar:SetTimerDuration`;
  - `ColorMixin:SetRGB` (plain field writes).
- `string.format(fmt, secret)`: returns a secret string. Used for `%d`, `%.1f`, `%s`
  everywhere.
- `AbbreviateNumbers(secret[, config])` and `C_StringUtil.TruncateWhenZero(secret)` (pcall
  recommended).
- Storing it in a variable or table field for later use by setters
  (`self._maxHP = maxHealth`).

Observed **forbidden** (hard errors per EUI comments):

- Arithmetic (`+ - * /`, `math.min`), comparison (`<`, `==`, `~=`), and using it as a
  table key (secret class tokens as `colors.class[token]`).
- Boolean tests on **secret booleans**: `if notInterruptible then`, `x == nil` on a possibly
  secret boolean, and handing nil to `EvaluateColorValueFromBoolean`.
- `StatusBar:SetGradient` with secret colors (`EllesmereUIUnitFrames.lua:1992-1996`).
- Id-keyed aura APIs with a secret auraInstanceID. Touching AuraContainer button subtrees
  from addon code while auras are restricted (outside `initializeFrame`).
- Reading layout from restricted rects (aura container buttons) and comparing the result.

**Ambiguity to verify in-game:** EUI writes `UnitHealth(u) or 0` and
`if not scaled then return "0" end` on secret *numbers* (`EUI_UnitFrames_Text.lua:376,428`,
`EUI_Nameplates_Layout.lua:836`). Yet a comment says "truthiness-testing ... one throw"
for secret r,g,b (`EllesmereUIUnitFrames.lua:1972-1975`). Either `or` / `not` on a secret
number is allowed, or those paths never see a secret there. SoulUI should test this
explicitly and, until then, prefer `type(v) == "nil"` checks.

### 9.2 Defensive idioms

```lua
-- nil check that is legal on secrets (secret booleans included)
if type(v) == "nil" then ... end
-- read-or-skip: probe secrecy BEFORE any comparison
if not issecretvalue(x) and x > 0 then ... end
-- setter that rejects nil but takes secrets
if issecretvalue(b) or b ~= nil then f:SetAlphaFromBoolean(b, 1, 0.4) end
```

- Value caches must be **fail-open**: on secret input, paint and clear the cache key
  (`self._lastHCr = nil`). Do not cache a secret as a comparison key.
- Plain flags you own (`_absorbHidden`, `_maxHPValid`) can gate hot paths safely.
- `pcall` around APIs that may throw under restriction: `C_Spell.IsSpellImportant`,
  `UnitHealthPercent(…, curve)` in exotic modes, `TruncateWhenZero`,
  `NumericRuleFormatter:SetBreakpoints`, `GetAuraDataByAuraInstanceID`.

### 9.3 Health and power as numbers

| Need | Technique | File:line |
|---|---|---|
| Health bar | `SetMinMaxValues(0, UnitHealthMax(u))`, `SetValue(UnitHealth(u), interp)` | UF `EUI_UnitFrames_Text.lua:87-102` |
| Health bar (percent) | Range 0-100, `SetValue(UnitHealthPercent(u, true, CurveConstants.ScaleTo100))` | RF `EUI_RaidFrames_Update.lua:1166-1178`, `Colors.lua:44-47` |
| Inverted fill | `CurveConstants.ReverseTo100` | RF `Colors.lua:45` |
| Percent text | `fs:SetFormattedText("%d%%", UnitHealthPercent(u, true, CurveConstants.ScaleTo100))` | NP `Health.lua:206-207,300`; NP Friendly `:1444` |
| Abbreviated value | `AbbreviateNumbers(UnitHealth(u), breakpointCfg)` | UF `Text.lua:382-386`; NP `Layout.lua:828-833` |
| Trailing-zero-free percent | Scaling curve (×1000 + 0.5), then `AbbreviateNumbers` with `fractionDivisor=10` | UF `Text.lua:313-329,425-430` |
| Missing health | `UnitHealthMissing(unit, true)`, then `TruncateWhenZero` | RF `Colors.lua:983-984` |
| Power percent | `UnitPowerPercent(u, pType, true, CurveConstants.ScaleTo100)` | UF `Text.lua:894`; RF `Update.lua:573`, `Events.lua:463,477`; RB `Update.lua:324,2017,2319` |
| Zero-blank count | `C_StringUtil.TruncateWhenZero(v)` | NP `Layout.lua:838`; UF `Text.lua:927,937`; RF `Colors.lua:849,1007`; RB main `:67-68`; CDM `HookPresetCooldowns.lua:410-411` |

### 9.4 Curves (C-side decisions)

Constructors:

- `C_CurveUtil.CreateColorCurve()`: points are `(x, ColorMixin)`.
- `C_CurveUtil.CreateCurve()`: points are `(x, number)`.
- `:SetType(Enum.LuaCurveType.Linear | .Step)`, `:AddPoint(x, y)`, `:ClearPoints()`.

Evaluators observed:

- `UnitHealthPercent(unit, usePredicted, curve)` returns a ColorMixin for a color curve or
  a number for a numeric curve. The input x is the health fraction in 0..1.
- `UnitPowerPercent(unit, powerType, usePredicted, curve)`: the same for power.
- `DurationObject:EvaluateRemainingDuration(curve[, default])`: x is remaining seconds.
- `C_CurveUtil.EvaluateColorValueFromBoolean(bool, ifTrue, ifFalse)`: a numeric select on
  a possibly secret boolean. The name says "Color", but EUI uses it for any number
  (colors per channel, alphas).
- `CurveConstants.ScaleTo100` / `ReverseTo100`: built-in curves.
- AuraContainer `SetDurationText(..., { textColor = { curve, property } })`: the engine
  evaluates a color curve against remaining aura time.

Recipes:

| Recipe | Curve | Consumer | File:line |
|---|---|---|---|
| Red→yellow→green health | Linear color 0/0.5/1 | `SetStatusBarColor` | UF main `:1913-1922`; RF `Colors.lua:53-63` |
| Class→reactive gradient | Linear color 0/0.4/0.75/1, class at 1 | `SetStatusBarColor` | UF main `:1955-1985`; RF `Colors.lua:140` |
| Execute glow | Color: red at [0,t], black after t+ε (ADD blend) | `SetVertexColor` on glow | NP `Overlays.lua:150-166`, `Health.lua:317-333` |
| Power threshold color | Color step via ε pair | `SetStatusBarColor` | RB `Thresholds.lua:296-335,410-440`; RB `Update.lua:136,159,421,1861,1868` |
| Reveal when not full | Numeric step 0→1, 1→0 | `SetAlpha` | RB `Update.lua:2671-2730`; UF `Visibility.lua:113-126` |
| Hide trailing zero | Numeric linear ×1000 + 0.5 | `AbbreviateNumbers` | UF `Text.lua:319-329` |
| GCD tail suppression | Numeric step on remaining (0→0, gcd→α) | `SetSwipeColor` alpha | CDM `HookTrinkets.lua:631-656` |
| Desaturate while on CD | Numeric step (0→0, 0.001→1) | `SetDesaturation` | CDM `HookTrinkets.lua:658-676` |
| Duration warn color | Color step (0→warn, N→normal) | AuraContainer duration text | RF `AuraContainers.lua:1325-1340` |
| Dispel type colors | Color step indexed by dispel enum | engine / dispel textures | RF `Update.lua:735-770` |
| Arcane / Ebon Might specials | Color curves, numeric rule formatters | RB `ArcaneSoul.lua:382-394`, `EbonMight121.lua:46-48` | |

### 9.5 Secret booleans

| Source of secret bool | Consumer | File:line |
|---|---|---|
| `notInterruptible` (cast info) | `frame:SetAlphaFromBoolean(b, a1, a0)`; color fold | UF `Castbar.lua:676-677`; NP `Cast.lua:370-386` |
| `C_Spell.IsSpellImportant(id)` | `overlay:SetAlphaFromBoolean(b)`; color fold | UF `Castbar.lua:1312,1358`; NP `Cast.lua:79-82,190-194,342-357` |
| `UnitInRange` / `C_Spell.IsSpellInRange` | `btn:SetAlphaFromBoolean(b, inA, outA)` | RF `Visibility.lua:80-97`, `BossFrames.lua:120`, `PetFrames.lua:169`, `Portrait.lua:667`; UF `Lifecycle.lua:218-226` |
| `UnitDetailedThreatSituation(tank, mob)` isTanking | `EvaluateColorValueFromBoolean` per channel | NP `Colors.lua:44-82` |
| Overshield (`calc:GetDamageAbsorbs()` 2nd return, MissingHealth clamp) | `spark:SetAlphaFromBoolean` | RF `Absorb.lua:556-569,859-866,1159-1182` |
| `durObj:IsZero()` (kick ready) | nested `EvaluateColorValueFromBoolean`, then `SetAlpha` | UF `Castbar.lua:813-817,834-838,878-881`; NP `Cast.lua:528-531,562-565,612-614` |
| `frame.spellOutOfRange` (CDM) | `tex:SetVertexColorFromBoolean(b, red, base)` | CDM `HookIconWatch.lua:1551-1552` |
| Blizzard button shown state | `SetAlphaFromBoolean(engBtn:IsShown(), 1, 0)` (pcall) | CDM `BuffBarPresets.lua:253-254` |

Field notes:

- **Use SetAlphaFromBoolean on frames, not textures.** On textures it rendered 0 on Midnight
  in EUI's testing (UF `Castbar.lua:672-675`). NP `Cast.lua:82` uses it on an overlay
  *frame*, and RF uses it on spark textures, so results may vary. Test it.
- To combine two booleans without branching:
  `inner = EvaluateColorValueFromBoolean(b1, 0, 1)`, then
  `alpha = EvaluateColorValueFromBoolean(b2, 0, inner)`. That gives an AND/NOT expression
  as numbers.
- Replace nil with `false` before folding, using `type(x) == "nil"`.

### 9.6 Duration objects

Sources:

- `UnitCastingDuration(unit)`, `UnitChannelDuration(unit)`,
  `UnitEmpoweredChannelDuration(unit, includeHold)`.
- `C_Spell.GetSpellCooldownDuration(spellID)`, `C_Spell.GetSpellChargeDuration(spellID)`.
- `C_DurationUtil.CreateDuration()` for your own durations
  (`:SetTimeFromStart(start, duration)`).

Methods observed:

- `:GetRemainingDuration()`, `:GetElapsedDuration()`, `:GetTotalDuration()` (secret for
  others' casts).
- `:IsZero()` (possibly secret boolean).
- `:EvaluateRemainingDuration(curve[, default])`.

Consumers:

- `StatusBar:SetTimerDuration(durObj, interpolation|nil, Enum.StatusBarTimerDirection.ElapsedTime|RemainingTime)`
  and `StatusBar:GetTimerDuration()`, `StatusBar:SetToTargetValue()`.
- `Cooldown:SetCooldownFromDurationObject(durObj)`, `Cooldown:SetUseAuraDisplayTime(bool)`.
- `C_DurationUtil.CreateDurationTextBinding()` with `:SetFontString`, `:SetDuration`,
  `:SetFormatter`, `:SetUpdateInterval`, `:SetExpiredText`, `:SetZeroDurationText` and
  `:SetEnabled` (RB `SwingTimer.lua:399-409,730-739`; UF `ForeverImbues.lua:134-136`).
- `Cooldown:SetCountdownFormatter(numericRuleFormatter)` (CDM `Icons.lua:490-499`).
- Text by Lua: `fs:SetFormattedText("%.1f", durObj:GetRemainingDuration())` in a 10-20 Hz
  ticker (NP `PlatePool.lua:568-597`; UF `Engine.lua:184-206`).

All `SetTimerDuration` call sites: UF `Engine.lua:268,337`; NP `Cast.lua:225,233`;
RB `CastBar.lua:1015`, `GCD.lua:62,136`, `SwingTimer.lua:689,843,866,892,1666,1680,1688`;
CDM `BuffBarCooldown.lua:310,730`.

Pitfalls recorded by EUI:

- A finished timer keeps painting its terminal state. Re-arm in the right direction to set
  the idle look (RB `GCD.lua:35-66`).
- Call `SetToTargetValue()` after re-arming, or the fill animates in from the previous cast.
- `UnitChannelDuration` can be nil during an empower. Ask
  `UnitEmpoweredChannelDuration(unit, true)` first.
- A transient nil duration mid-cast means skip, not hide. Hiding blinks the bar on every
  cooldown event.
- Two stacked bars (elapsed and remaining) anchored edge to edge give an exact screen
  position of "now + X" (the kick tick). Disable pixel snapping on their fill textures
  after every `SetFillStyle`.

### 9.7 Secret counts → discrete visuals (pip gates)

- One StatusBar per pip with `SetMinMaxValues(i-1, i)` and `SetValue(count)`. It is full
  iff count ≥ i (UF `ClassPower.lua:482-493`; RB `Update.lua:2147-2178`; UF
  `ForeverExtras.lua:271-296`).
- Thresholds or bands: more gates with shifted ranges on higher frame levels (RB
  `Update.lua:2180-2240`).
- "Glow at ≥ N stacks": a gate with range (N-1, N) whose fill edge positions a
  `CLAMPTOBLACKADDITIVE` mask over the glow (CDM `EllesmereUICdmHooks.lua:34-80`).
  Masks keep working where clip-children on secret-derived rects go dark.

### 9.8 Absorb splitting without arithmetic

Two clip frames anchored to the health fill texture edge plus full-range absorb bars
(UF `Absorb.lua:140-156`; NP `PlatePool.lua:59-62` + `Health.lua:113-150`; RF `Absorb.lua`).
The overshield boolean comes from a MissingHealth-clamped calculator (RF). Heal
prediction uses a calculator with MaximumHealth clamps inside the same missing-health clip
(UF `Absorb.lua:603-660`).

### 9.9 Identity restrictions (12.1)

- `UnitClass(unit)` can return a **secret token** for focus, ToT and enemy players in PvP.
  Never index tables with it. Use `C_ClassColor.GetClassColor(token)` or a C-side helper.
  Do not cache it.
- `UnitGUID` can be secret. Compare only after `issecretvalue`, and treat secret as
  "changed" (UF `Engine.lua:566-576,750-758`).
- `UnitGroupRolesAssigned(unit.."target")` can be secret (NP `Colors.lua:870-890`).
- `UnitSpellTargetName` / `UnitSpellTargetClass` can be secret (NP `Plate.lua:324-360`).
- Never add a `.unit` field to secure unit buttons. It breaks pings with secret GUIDs.

### 9.10 Auras: do not scan, declare

- Use AuraContainers (section 5). Filters are strings; candidate filters hold spell IDs and
  booleans.
- Dispel colors come from engine-owned dispel textures plus a `customDispelColorMap`.
- If you must read your own auras (class mechanics), check first:
  `C_Secrets.ShouldAurasBeSecret()` / `ShouldSpellAuraBeSecret(id)`, then
  `pcall(C_UnitAuras.GetPlayerAuraBySpellID, id)`, then `issecretvalue(data)` and
  `canaccesstable(data)`.
- `UNIT_AURA` `updateInfo` can itself be secret (CDM `BuffBarGroups.lua:165`).

### 9.11 Full list of `issecretvalue` hotspots

There are 747 occurrences on roughly 450 lines across the five addons. Highest density:

- `EllesmereUIResourceBars/EUI_ResourceBars_Update.lua` (35 lines)
- `EllesmereUICooldownManager/EUI_CDM_HookIconWatch.lua` (30)
- `EllesmereUINameplates/EUI_Nameplates_Colors.lua` (23)
- `EllesmereUIUnitFrames/EUI_UnitFrames_Text.lua`, `EUI_UnitFrames_Init.lua`,
  `EllesmereUIRaidFrames/EUI_RaidFrames_Colors.lua` (17 each)
- `EllesmereUIResourceBars/EllesmereUIResourceBars.lua`, `EUI_RaidFrames_Update.lua` (14)
- `EUI_RaidFrames_ForeverMissingBuffs.lua` (13), `EUI_UnitFrames_StockStyles.lua` (12),
  `EUI_UnitFrames_Portrait.lua` (11), `EUI_UnitFrames_Reload.lua`, `EllesmereUICdmHooks.lua`,
  `EUI_CDM_Rotation.lua` (10)

Representative checks:

- UF `Engine.lua:197` (remaining cast time), `:570` (boss GUID), `:595` (power token), `:753`
  (poll GUID).
- UF main `:1992` (curve color), `:2120` (class token).
- UF `Castbar.lua:643` (class token), `:738` (bar width).
- NP `Health.lua:131` (absorb), `:209` (pct memo).
- NP `Colors.lua:336-360` (quest tooltip fields), `:751` (role).
- NP `Plate.lua:151` (UnitCanAttack in hook).
- RF `Update.lua:1194` (class token).
- RF `Absorb.lua:880,904`.
- RB `Update.lua:1309` (points memo), `:2443-2446` (shard fraction).
- CDM `HookDecorate.lua:779` (cooldown duration), `EllesmereUICdmHooks.lua:96-111`
  (aura iid/applications).

Get the complete per-line list with
`grep -rn issecretvalue EllesmereUI{Nameplates,UnitFrames,RaidFrames,ResourceBars,CooldownManager}`.

---

## 10. Taint and secure-environment lessons (collected)

1. Do not write fields on Blizzard frames or secure header children. Use weak external
   tables.
2. Do not `SetScript` on header children. Use `HookScript`.
3. Reparenting Blizzard frames: only out of combat, with a `SetParent` hook that undoes
   Edit Mode re-parenting, and never for frames whose descendants run aura code (alt-power
   bars).
4. Nameplate UnitFrames: keep them parented to the base (alpha 0). Sweep their children
   instead.
5. Blizzard CDM frames: re-anchor only, after the viewer's own layout pass.
6. Unit menu: a secure macro-proxy instead of `togglemenu` (12.0.7 gate).
7. Ping: let `PingableUnitFrameTemplate` read the `unit` attribute. Do not override
   `GetIsPingable` / `GetTargetInfo`.
8. Secure header children are created only while the header is visible. Pre-spawn with
   the `startingIndex` trick out of combat.
9. Click-cast state drivers: use non-numeric state values.
10. `"none"` vs nil for type attributes (wildcard fallback).

---

## 11. Recommendations for SoulUI

### 11.1 Architecture

1. **Do not use oUF.** Build a small engine like EUI's. Channel→event tables, one tracker
   per unit token via `RegisterUnitEvent`, painters per channel, same-frame generation
   dedupe, and opt-in channels that register events only when a feature is on. It is
   about 1k lines and gives full control over secret handling. (Write it from scratch from
   the design described here, not from EUI's code.)
2. **Secure layer:** `SecureUnitButtonTemplate, PingableUnitFrameTemplate` +
   `RegisterUnitWatch` + `toggleForVehicle`, parented to a `[petbattle] hide` state-driver
   frame. Keep the live token in a private field (`_soulUnit`), never `.unit`. Ship a
   secure right-click menu proxy from day one.
3. **Raid/party:** `SecureGroupHeaderTemplate` with
   `auraContainerTemplate="CustomAuraContainerTemplate"`. Pre-spawn buttons out of combat,
   and keep all per-button state in a weak table. Use a percent bar
   (`UnitHealthPercent(..., ScaleTo100)`, range 0-100): it is cheaper and avoids max-health
   races.
4. **Nameplates:** use the overlay approach. Pool frames, parent them to the base plate,
   alpha-0 the Blizzard UnitFrame (keep it parented), sweep its children to a hidden
   holder, `UnregisterAllEvents()` on it, and give pieces back on friendly reuse. Use
   `SetStackingBoundsFrame` with a real region. Use a centralized cast-event dispatcher.
   Prewarm the pool. Defer non-critical setup by one frame.
5. **Auras:** go all-in on AuraContainers through a SoulUI wrapper like AuraKit. Normalize
   filter strings, schedule group builds across frames, defer restyles while auras are
   restricted, and handle the "creation window" rule. Plan for fixed group filter strings
   (declare new variants and park old ones at cap 0).
6. **Cooldown Manager:** if SoulUI ships one, hook and re-anchor Blizzard's viewers as EUI
   does, instead of rebuilding cooldown tracking. Blizzard's frames are the only thing
   that reliably knows aura-linked and secret state. Keep strict rules: no reparent, no
   field writes, anchor after `RefreshLayout`. SoulUI-owned extras (trinkets, custom
   spells) should use duration objects.
7. **Resource bars:** use duration-object timers for cast, GCD and swing bars. Use
   pip-gate StatusBars for any possibly secret count. Build threshold colors as step
   curves evaluated by `UnitPowerPercent`.

### 11.2 A SoulUI secret-safety kit (suggested module `SoulUI/Core/Secret.lua`)

Provide tiny helpers with our own names and code:

- `S.IsNil(v)`: wraps `type(v) == "nil"`.
- `S.Plain(v)`: returns v if not secret, else nil (for memo keys).
- `S.AlphaFromBool(frame, b, aTrue, aFalse)`: secret check, nil guard, and fallback to
  `SetAlpha` on old clients.
- `S.Select(b, ifTrue, ifFalse)`: wraps `C_CurveUtil.EvaluateColorValueFromBoolean`,
  replacing nil with false.
- `S.SelectColor(b, colorA, colorB)`: returns three folded channels.
- `S.StepColorCurve(threshold, below, above)`: cached by inputs, using the epsilon-pair
  construction.
- `S.PercentText(fs, unit, decimals)`: `SetFormattedText` with `UnitHealthPercent`.
- `S.ZeroBlank(v)`: `pcall(C_StringUtil.TruncateWhenZero, v)`.
- `S.PipGate(parent, index)`: creates or updates a pip-gate StatusBar.
- `S.AurasRestricted()`: `C_Secrets.ShouldAurasBeSecret()` with a pcall probe fallback.

Also add a debug command that dumps `issecretvalue` for a list of APIs on
target/focus/party1 inside and outside an instance. Several behaviors here (truthiness on
secret numbers, `SetAlphaFromBoolean` on textures, which pairings return secret threat)
were "field-proven" by EUI and are not documented anywhere else. We need our own
verification harness.

### 11.3 Performance budget rules to adopt

- Each `UNIT_HEALTH` paint does one `SetValue` (plus color only in dynamic modes). Anything
  else needs an opt-in channel.
- No `UNIT_AURA` on frames for absorbs or health. Use an armed ticker for timer-expired
  shields.
- No per-frame OnUpdate for text. Use engine bindings (`CreateDurationTextBinding`,
  `SetCountdownFormatter`, AuraContainer duration text) or 10 Hz anim tickers.
- Memos keyed by display granularity, with fail-open on secrets.
- Register `UNIT_HEAL_PREDICTION` only while heal prediction is shown.
- Self-hiding OnUpdate drivers and tickers that cancel themselves when idle.

### 11.4 Config and live-apply

- One DB per module with profiles. Positions as `{point, relPoint, x, y}` relative to
  UIParent, snapped to the physical pixel grid on apply (center anchors need dimension-aware
  snapping to keep whole-pixel edges).
- Settings writes go to a throttled `Reload()` (next frame), which bumps an appearance
  generation. Hot paths compare generations instead of re-reading settings.
- Materialize "effective settings" proxies (scale or size tiers applied) for hot paths.
- A combat queue for anything touching secure frames.
- A client gate and stale-parent guard at the top of every file.

### 11.5 Things to explicitly avoid copying

- EUI's very large single-feature files (4-5k lines) and the 200-local workarounds.
  SoulUI should keep modules smaller from the start.
- Features that exist only for WoW Forever (`IS_FOREVER` branches) unless we target that
  client.
- Any code text. All of the above must be re-implemented from the described behavior.

---

## Appendix A: file map (what lives where)

**Nameplates:**

| File | Contents |
|---|---|
| `EllesmereUINameplates.lua` | Defaults and profile |
| `Styles` / `Layout` | Sizes, text slots, tags |
| `Overlays` | Execute glow, overlays |
| `PlatePool` | Pool, plate build, cast timer ticker, prewarm |
| `CastState` | CVars, click area, driver hooks |
| `ClassPower` | Pips on the target plate |
| `Colors` | Reaction, threat, quest, off-tank fold |
| `Plate` | Hide Blizzard, mixin, SetUnit/ClearUnit |
| `Health` | Values and colors |
| `Name` | Name, raid icon, target |
| `Cast` | Cast bar, kick tick, important glow |
| `Events` | Manager and dispatcher |
| `Init` | Enable, CVar rules |
| `AuraContainers` | Plate aura bundles |
| `DebuffColors` | Aura-slot bar tint |
| `Friendly` | Friendly plates |
| `Faction`, `CastOverlay` | Extras |

**UnitFrames:**

| File | Contents |
|---|---|
| `Engine` | Trackers, painters, castbar driver, spawn, Blizzard hide routing |
| `EllesmereUIUnitFrames.lua` | Defaults, Blizzard hide, dynamic colors, secret-safe color chain |
| `Text` | Painters, tags, number formatting |
| `Portrait` | Portraits and raid icon |
| `Castbar` | Cast bar styling, kick tick, important glow |
| `Layout` | Positions, bar clip |
| `Absorb` | Absorbs, heal prediction, armed belt |
| `Power`, `ClassPower` | Power and class power |
| `Threat` | Threat border and threat text |
| `Builders` | Frame building |
| `StockStyles` | Blizzard/Classic looks |
| `Visibility` | Visibility and health reveal |
| `Init` | Spawn, ClickCastFrames, menus |
| `Unlock` | Movers |
| `AuraContainers`, `PlayerAuraBars_*` | Auras |

**RaidFrames:**

| File | Contents |
|---|---|
| `Layout` | Headers |
| `Party`, `PetFrames`, `ExtraFrames`, `BossFrames`, `PartyTargets` | Other frame sets |
| `Lifecycle` | Trackers, events |
| `Events` | OnEvent |
| `Update` | Health, dispel curves |
| `Colors` | Curves, text helpers |
| `Absorb` | Absorbs |
| `Visibility` | Range |
| `ClickCast` | Click-casting |
| `AuraContainers`, `DebuffManager`, `BuffManager*` | Auras |
| `Sort`, `Reload`, `Style`, `Stock`, `Portrait`, `Preview*` | Sorting, reload, styling, preview |

**ResourceBars:**

| File | Contents |
|---|---|
| `EllesmereUIResourceBars.lua` | Main |
| `Defaults`, `Frames`, `Anchors`, `Build`, `Style`, `Groups` | Setup and layout |
| `Update` | All value painting, pip gates |
| `Thresholds` | Curves |
| `Events` | Events |
| `CastBar`, `GCD`, `SwingTimer`, `Totem`, `CallTotemBar` | Timers |
| `EbonMight121`, `ArcaneSoul`, `WarriorCharges`, `ForeverDruidMana` | Class-specific trackers |
| `HealthIndicators`, `BlizzClassArt` | Extras |

**CooldownManager:**

| File | Contents |
|---|---|
| main | Shells, style latches |
| `Store`, `Spec` | Per-spec data |
| `Blizzard` | Capture, hide, restore |
| `Bars`, `Icons` | EUI containers, formatters |
| `Rebuild`, `Reconcile`, `Lifecycle` | Rebuild and lifecycle |
| `Hooks*` | Decorate, viewers, reanchor, icon watch, trinkets, presets, custom buffs, press mirror |
| `BuffBar*` | Tracked Buff Bars |
| `FakeActive`, `RotationIcon`, `KeybindStyle`, `BarGlows*`, `TalentConditions`, `StanceBar`, `SpellPicker`, `RPTSync`, `FocusKick` | Extras |

## Appendix B: 12.x API inventory observed in these five addons

| Category | APIs |
|---|---|
| Health and power | `UnitHealthPercent`, `UnitPowerPercent`, `UnitHealthMissing`, `CurveConstants.ScaleTo100`, `CurveConstants.ReverseTo100` |
| Heal prediction | `CreateUnitHealPredictionCalculator`, `UnitGetDetailedHealPrediction`; calculator `SetMaximumHealthMode`, `SetDamageAbsorbClampMode`, `SetIncomingHealClampMode`, `SetHealAbsorbClampMode`, `SetHealAbsorbMode`, `GetCurrentHealth`, `GetMaximumHealth`, `GetDamageAbsorbs`, `GetIncomingHeals`; enums `UnitMaximumHealthMode`, `UnitDamageAbsorbClampMode`, `UnitIncomingHealClampMode`, `UnitHealAbsorbClampMode`, `UnitHealAbsorbMode` |
| Curves | `C_CurveUtil.CreateCurve`, `CreateColorCurve`, `EvaluateColorValueFromBoolean`, `Enum.LuaCurveType` |
| Durations and timers | `C_DurationUtil.CreateDuration`, `CreateDurationTextBinding`; `UnitCastingDuration`, `UnitChannelDuration`, `UnitEmpoweredChannelDuration`; `C_Spell.GetSpellCooldownDuration`, `GetSpellChargeDuration`; `StatusBar:SetTimerDuration`, `GetTimerDuration`, `SetToTargetValue`; `Enum.StatusBarTimerDirection`, `Enum.StatusBarInterpolation`; `Cooldown:SetCooldownFromDurationObject`, `SetUseAuraDisplayTime`, `SetCountdownFormatter` |
| Strings | `C_StringUtil.TruncateWhenZero`, `CreateNumericRuleFormatter` (`SetBreakpoints`, `Enum.NumericRuleFormatRounding`), `CreateSecondsFormatter`; `AbbreviateNumbers` with `breakpointData` |
| Boolean setters | `SetAlphaFromBoolean`, `SetVertexColorFromBoolean` |
| Secrets | `issecretvalue`, `canaccessvalue`, `canaccesstable`, `C_Secrets.ShouldAurasBeSecret`, `C_Secrets.ShouldSpellAuraBeSecret` |
| Spells and casts | `C_Spell.IsSpellImportant`, `UnitSpellTargetName`, `UnitSpellTargetClass`, `UnitShouldDisplaySpellTargetName`, `UnitEmpoweredStagePercentages`, `GetUnitEmpowerHoldAtMaxTime` |
| Nameplates | `C_NamePlate.GetNamePlateForUnit`, `SetNamePlateSize`; `C_NamePlateManager.SetNamePlateHitTestInsets`; `nameplate:SetStackingBoundsFrame`; `NamePlateConstants.ENEMY_*_AURA_DISPLAY_CVAR` |
| Aura containers | `CreateFrame("AuraContainer", ..., "CustomAuraContainerTemplate")`, `AddAuraGroup`, `AddAuraSlot`, `SetAuraGroupMaxFrameCount`, `SetAuraGroupEnabled`, `SetAuraGroupCandidateFilters`, `SetAuraProcessingPolicy`, flow-layout setters; button `SetIcon`, `SetDurationCooldown`, `SetApplicationCount`, `SetDurationText`, `AddDispelTypeTexture`, `SetCancelAuraButtons`, `AddAuraShownAnimation`; header attribute `auraContainerTemplate`; `AuraUtil.AuraFilters.Dispellable`, `AuraUtil.AuraFilters.Important` |
| Cooldown viewer | `C_CooldownViewer.GetCooldownViewerCooldownInfo`, `GetCooldownViewerCategorySet`; mixins `CooldownViewer{Essential,Utility,BuffIcon,BuffBar}ItemMixin.OnCooldownIDSet`; `viewer.itemFramePool`, `viewer:RefreshLayout`, `item:OnActiveStateChanged` |
| Tooltip and quest | `C_TooltipInfo.GetUnit` + `Enum.TooltipDataLineType.QuestTitle` / `QuestObjective` |
