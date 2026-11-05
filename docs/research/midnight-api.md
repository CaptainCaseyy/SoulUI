# Midnight (12.x) Addon API Cookbook for SoulUI

Target: WoW retail **12.1.5** (Interface `120105`). Locally installed build seen on 2026-11-04: `12.1.5.70783`.
Compiled: 2026-11-04 from warcraft.wiki.gg, the Gethe/wow-ui-source mirror of Blizzard's generated API
documentation, the oUF master branch, and addon changelogs. Every section lists its sources.

> **How to read this file.** Signatures marked **[doc]** come straight from Blizzard's generated API
> documentation (`Blizzard_APIDocumentationGenerated/*.lua`, mirrored at Gethe/wow-ui-source `live`)
> or the wiki page built from it. Items marked **[inferred]** are reasoned from those docs or from addon
> source and have not been confirmed in game. The section **Uncertain points to verify in game** at the
> end collects everything still open.

Primary sources used throughout:

- Secret values overview: https://warcraft.wiki.gg/wiki/Secret_values
- 12.0.0 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- 12.0.1 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.1/API_changes
- 12.0.5 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes
- 12.0.7 API changes: https://warcraft.wiki.gg/wiki/Patch_12.0.7/API_changes
- 12.1.0 API changes and notes: https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes , https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes/notes
- 12.1.5 API changes and notes: https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes , https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes/notes
- Blizzard generated docs: https://github.com/Gethe/wow-ui-source/tree/live/Interface/AddOns/Blizzard_APIDocumentationGenerated
- oUF (reference implementation of 12.x unit frames): https://github.com/oUF-wow/oUF

---

## 0. TL;DR: the twelve rules

1. In combat, in instances, and on restricted units, many numbers, strings and booleans come back as
   **secret values**. Your (tainted) addon code may **store, pass, concatenate and format** them. It may
   **not** do arithmetic, compare them, test a secret boolean, take `#`, use them as table keys, or index them.
   A disallowed operation raises an **immediate Lua error**.
2. Feed secrets straight into widget APIs that accept them: `StatusBar:SetValue/SetMinMaxValues`,
   `FontString:SetText/SetFormattedText`, `Region:SetAlphaFromBoolean`, `Region:SetVertexColorFromBoolean`,
   `Cooldown:SetCooldownFromDurationObject`, `StatusBar:SetTimerDuration`, and others.
3. Do math through **native helpers**: `UnitHealthPercent`/`UnitPowerPercent` plus **Curves**
   (`C_CurveUtil`), **Duration objects** (`C_DurationUtil`, `UnitCastingDuration`, `C_Spell.GetSpellCooldownDuration`),
   the **heal prediction calculator** (`CreateUnitHealPredictionCalculator`), and **formatters**
   (`AbbreviateNumbers`, `C_StringUtil.Create*Formatter`, `DurationTextBinding`).
4. Branch with `issecretvalue(v)` (or `canaccessvalue(v)`) **before** any comparison or arithmetic.
5. `COMBAT_LOG_EVENT_UNFILTERED` and `COMBAT_LOG_EVENT` **error when registered**. Damage meters read
   `C_DamageMeter` instead.
6. **Auras (12.1.0+):** while auras are restricted, the `C_UnitAuras` lookups by index, slot or instance ID
   **Lua-error** for addons, and `UNIT_AURA` delivers a fully secret payload. To show auras in combat,
   use the new **AuraContainer / CustomAuraButton** frame types (`CustomAuraContainerTemplate`).
   `SecureAuraHeaderTemplate` was removed from Mainline.
7. Cast bars: use `UnitCastingDuration` / `UnitChannelDuration` / `UnitEmpoweredChannelDuration` with
   `StatusBar:SetTimerDuration`. Start and end times are only readable for the player.
8. Cooldowns: `C_Spell.GetSpellCooldown` is `SecretWhenCooldownsRestricted`. Use
   `C_Spell.GetSpellCooldownDuration` with `Cooldown:SetCooldownFromDurationObject`. The fields `isActive`,
   `isEnabled` and `isOnGCD` are never secret.
9. Nameplates: you can still restyle enemy plates. Size is set via `C_NamePlate.SetNamePlateSize`, the hit
   area via `C_NamePlateManager.SetNamePlateHitTestInsets` and `NamePlate:SetHitTestPoints` (12.0.5+). Friendly
   plates in instances are **forbidden** frames (`FORBIDDEN_NAME_PLATE_*` events).
10. Combat lockdown rules are unchanged: no protected-frame show/hide/move/attribute changes in combat.
11. 12.1.5 adds native `math.*`, `string.*` and `table.*` helpers, `Region:SetRoundLayoutToNearestPixel`,
    `CreateFrameWithOptions`, `TimedSignalMap`, and aura pandemic animations.
12. Test restricted paths **out of combat** with the `addon*RestrictionsForced` CVars (section 10).

---

## 1. Secret values

Source: https://warcraft.wiki.gg/wiki/Secret_values , https://warcraft.wiki.gg/wiki/API_issecretvalue ,
https://warcraft.wiki.gg/wiki/Secret_aspects , https://warcraft.wiki.gg/wiki/Forbidden_aspect

### 1.1 What they are

Patch 12.0.0 (2026-01-20) added *secret values*: ordinary Lua values (numbers, strings, booleans, tables)
carrying a flag that restricts what **tainted** code can do with them. Every addon is tainted, so treat the
restrictions as always in force for SoulUI. On untainted (Blizzard) execution paths secrets behave like normal
values.

The underlying data is not hidden from rendering. Blizzard's design principle, as summarized by a
third-party guide: addons may change *how* combat information looks, but may not *decide* things based
on it (https://wow-midnight-addon-template.vercel.app/midnight/).

### 1.2 Allowed versus disallowed operations (tainted code)

| Allowed | Disallowed (immediate Lua error) |
|---|---|
| store in locals, upvalues, table **values** | arithmetic (`+ - * / % ^`, unary minus) |
| pass to Lua functions | comparison (`== ~= < > <= >=`) |
| pass to C APIs **marked as accepting secrets** | boolean test of a **secret boolean** (`if secretBool then`) |
| concatenate (`..`), `string.concat`, `string.format`, `string.join` | length `#secret` |
| truth-test a non-boolean secret (only `nil`/non-nil is revealed, because the type is not secret) | use as a table **key** (`t[secret] = x`) |
| `type(secret)` returns the real type | index or assign into a secret (`secret.foo`, `secret[1] = x`) |
| | call a secret as a function |

Consequences:

- `string.format("%s / %s", cur, max)` is **legal** and yields a secret string. You can `SetText` it.
  `string.format("%d%%", pct)` should also work, because formatting happens natively.
  **[inferred]** Format specifiers that need Lua-side math (none in stock Lua) are not an issue.
- `tostring(secret)` was crash-fixed for secret *objects* in 12.1.5 PTR 2, but avoid it. Use `string.format`
  or a native formatter instead.
- `if UnitHealth(u) > 0 then` errors in combat. Use `UnitIsDeadOrGhost(u)` (not secret) or a curve.
- `math.max(secretA, secretB)` errors, because comparison happens inside Lua.
- `pcall` around a disallowed op catches the error, but don't use that as a strategy. It is slow and hides bugs.

### 1.3 Test functions [doc]

```lua
isSecret   = issecretvalue(value)      -- true if value is secret
canAccess  = canaccessvalue(value)     -- true if the calling context may operate on it
isSecretT  = issecrettable(tbl)        -- table flagged so that indexing yields secrets
canAccessT = canaccesstable(tbl)       -- false if indexing would raise "attempted to index a forbidden table"
-- also exported in 12.0.0 (names from the API-changes page; behaviour not documented in detail):
canaccesssecrets()          canaccessallvalues(...)    hasanysecretvalues(...)
scrubsecretvalues(...)      dropsecretaccess()         secretwrap(...)
securecallmethod(...)       mapvalues(...)
```

`settablesecurity`, `securecopy` and `SetTableSecurityOption` were **removed in 12.1.0**.

`C_Secrets` evaluates predicates directly, for example `C_Secrets.HasSecretRestrictions()`,
`C_Secrets.GetSpellAuraSecrecy(spellID)`, `C_Secrets.GetSpellCastSecrecy(spellID)`,
`C_Secrets.GetSpellCooldownSecrecy(spellID)`, `C_Secrets.ShouldUnitStatsBeSecret()` (12.0.5), plus a family
of `Should*BeSecret` functions. `C_RestrictedActions` tests which restriction state is active.

Widget-side checks:

```lua
obj:HasSecretValues()          -- object was fed a secret with no aspect (e.g. StatusBar:SetValue(secret))
obj:HasSecretAspect(aspect)    -- Enum.SecretAspect.*
obj:HasAnySecretAspect()
obj:SetPreventSecretValues(b) / obj:IsPreventingSecretValues()
region:IsAnchoringSecret()     -- anchoring/positions became secret (propagates to anchored children)
obj:SetToDefaults()            -- the ONLY way to clear secret aspects
```

### 1.4 How API docs tag secrecy

- `SecretReturns = true` means the function **always** returns secrets to tainted callers.
- `SecretWhen<Predicate>` means the return is secret only while that restriction is active.
- `ConditionalSecret` on a field means that one field can be secret.
- `NeverSecret` on a field or argument means it is safe to branch on.
- `SecretArguments`: `AllowedWhenTainted` (always accepts secrets), `AllowedWhenUntainted` (accepts secrets
  only from untainted callers, so **addons must not pass secrets**), `NotAllowed`.
- `SecretArgumentsAddAspect = <Aspect>` means passing a secret applies that **secret aspect** to the object,
  so the matching getters then return secrets too.

### 1.5 Predicates you will hit (with the patch that introduced them)

| Predicate | Ver | When active |
|---|---|---|
| `SecretWhenInCombat` | 12.0.0 | player in combat (damage meter sessions etc.) |
| `SecretWhenUnitHealthMaxRestricted` | 12.0.0 | unit is not player-controlled |
| `SecretWhenUnitPowerRestricted` | 12.0.0 | power types not flagged never-secret |
| `SecretWhenUnitPowerMaxRestricted` | 12.0.0 | non-player-controlled units, with per-power overrides |
| `SecretWhenUnitSpellCastRestricted` | 12.0.0 | cast info for units other than player/pet |
| `SecretWhenUnitIdentityRestricted` | 12.0.0 | unit not player-controlled and not in party/raid |
| `SecretWhenUnitComparisonRestricted` | 12.0.0 | `UnitIsUnit` etc. on restricted maps |
| `SecretWhenUnitAuraRestricted` | 12.0.0 | combat/encounter/M+/PvP, with per-spell overrides |
| `SecretWhenCurveSecret` | 12.0.0 | the curve you passed holds secrets |
| `SecretWhenTotemSlotSecret` | 12.0.0 | totem restrictions |
| `SecretInChatMessagingLockdown` | 12.0.0 | encounter / M+ / PvP / comm-restricted maps |
| `SecretWhenUnitThreatStateRestricted` / `...ThreatValuesRestricted` | 12.0.1 | threat queries |
| `SecretWhenLossOfControlInfoRestricted` | 12.0.1 | LoC for anyone but the active player |
| `SecretInActivePvPMatch` | 12.0.1 | rated/arena match |
| `SecretWhenCooldownsRestricted` | 12.0.5 | spell/action/spellbook cooldowns, charges, counts |
| `SecretOnRestrictedMaps` | 12.0.5 | dungeons and raids |
| `SecretWhenEncounterEvent` | 12.0.5 | encounter timeline event data |
| `SecretWhenUnitStatsRestricted` | 12.0.5 | `GetCritChance`, `GetHaste`, `UnitStat`, `UnitArmor`, ... |
| `SecretWhenNumericFormatterSecret` | 12.0.5 | formatter holds secrets |
| `SecretWhenAurasRestricted` | 12.1.0 | aura system restricted (`UNIT_AURA` payload) |
| `SecretWhenUnitNameIdentityRestricted` | 12.1.0 | like identity, but player units are exempt in PvP |
| `SecretWhenUnitPossessionRestricted` | 12.1.0 | `UnitIsCharmed`/`UnitIsPossessed`; player/pet/vehicle exempt |
| `SecretWhenLuaTableHasSecretKeys` | 12.1.5 | Lua table has secret keys |

### 1.6 Unit API secrecy reference (12.1.5 generated docs) [doc]

Source: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua

| Function | Signature | Secrecy |
|---|---|---|
| `UnitHealth` | `(unit [, usePredicted=true]) -> number` | **SecretReturns** (always) |
| `UnitHealthMax` | `(unit) -> number` | SecretWhenUnitHealthMaxRestricted (players: readable) |
| `UnitHealthMissing` | `(unit [, usePredicted=true]) -> number` | SecretReturns |
| `UnitHealthPercent` | `(unit [, usePredicted=true [, curve]]) -> number or color` | SecretReturns, SecretWhenCurveSecret |
| `UnitPower` | `(unit [, powerType [, unmodified=false]]) -> number` | SecretWhenUnitPowerRestricted |
| `UnitPowerMax` | `(unit [, powerType [, unmodified]]) -> number` | SecretWhenUnitPowerMaxRestricted |
| `UnitPowerPercent` | `(unit [, powerType [, unmodified [, curve]]])` | SecretWhenUnitPowerRestricted, SecretWhenCurveSecret |
| `UnitPowerMissing` | `(unit [, powerType [, unmodified]])` | SecretWhenUnitPowerRestricted |
| `UnitGetIncomingHeals` | `(unit [, healerUnit]) -> number?` | SecretReturns |
| `UnitGetTotalAbsorbs` / `UnitGetTotalHealAbsorbs` | `(unit) -> number` | SecretReturns |
| `UnitCastingInfo` | `(unit) -> name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill*, castID, notInterruptible, spellID, castBarID*, delayTimeMs*` | SecretWhenUnitSpellCastRestricted (* = NeverSecret) |
| `UnitChannelInfo` | `(unit) -> name, displayName, textureID, startTimeMs, endTimeMs, isTradeskill*, notInterruptible, spellID, isEmpowered*, numEmpowerStages*, castBarID*` | SecretWhenUnitSpellCastRestricted |
| `UnitCastingDuration` | `(unit) -> DurationObject` | MayReturnNothing, SecretReturns |
| `UnitChannelDuration` | `(unit) -> DurationObject` | MayReturnNothing |
| `UnitEmpoweredChannelDuration` | `(unit [, includeHoldAtMaxTime=true]) -> DurationObject` | MayReturnNothing |
| `UnitThreatSituation` | `(unit [, mobUnit]) -> number?` | SecretWhenUnitThreatStateRestricted |
| `UnitDetailedThreatSituation` | `(unit, mobUnit) -> isTanking, status, scaledPct, rawPct, rawThreat` | SecretWhenUnitThreatValuesRestricted |
| `UnitName` | `(unit) -> name, realm` | SecretWhenUnitNameIdentityRestricted |
| `UnitClass` | `(unit) -> className(cond.), classFile, classID` | SecretWhenUnitIdentityRestricted |
| `UnitGUID` | `(unit) -> guid?` | SecretWhenUnitIdentityRestricted |
| `UnitIsUnit` | `(u1, u2) -> bool` | SecretWhenUnitComparisonRestricted |
| `UnitInRange` | `(unit) -> inRange, checked` | **SecretReturns** |
| `UnitExists`, `UnitIsDead`, `UnitAffectingCombat`, `UnitIsConnected`, `UnitReaction`, `UnitIsFriend`, `UnitLevel` | | not secret |

Since 12.1.0 these also return secrets when the unit's identity is secret: `UnitClassBase`, `UnitSex`,
`UnitRace`, `UnitGroupRolesAssigned(Enum)`, `UnitIsGroupLeader`, `UnitIsGroupAssistant`, `UnitInRaid`,
`UnitIsPVP`, `UnitPhaseReason`, `UnitIsRaidOfficer`, `UnitGetAvailableRoles`, `GetInspectSpecialization`,
and `UnitIsOwnerOrControllerOfUnit` (12.1.0 notes). `GetArenaOpponentSpec` returns secrets as of 12.1.5.

**Practical implications for SoulUI**

- Health is **always** secret to us, even out of combat. Never assume "out of combat means readable" for health.
- **Party/raid members are player-controlled**, so `UnitHealthMax`, `UnitName` and `UnitClass` are normally
  readable for group members. NPCs and enemies are restricted.
- `UnitInRange` is always secret. Drive range fading with `frame:SetAlphaFromBoolean(inRange, 1, 0.4)`.
  Note the alpha arguments are on a 0-1 scale in oUF usage, while the wiki lists a default of 255. See the
  uncertain points.
- `UnitClass` can be secret for enemy players. oUF handles it with:
  `if issecretvalue(class) then color = C_ClassColor.GetClassColor(class) end`.
  `C_ClassColor.GetClassColor` accepts the secret string and returns a color usable with
  `SetStatusBarColor`. 12.1.5 adds an optional tint argument.

### 1.7 Widget APIs that accept secrets (and the aspect they apply)

Passing a secret to these applies the listed **aspect**. The corresponding getters then return secrets.
Source: https://warcraft.wiki.gg/wiki/Secret_aspects

| Aspect | Setter APIs that accept secrets |
|---|---|
| Text | `FontString:SetText`, `SetFormattedText`, `SetTextToFit`, EditBox text |
| Shown | `SetShown` (secret bool) |
| Alpha | `SetAlpha`, `SetAlphaFromBoolean`, also `SetVertexColor`/`SetStatusBarColor`/`SetTextColor` alpha |
| VertexColor | `SetVertexColor`, `SetVertexColorFromBoolean`, `SetStatusBarColor` |
| BarValue | `StatusBar:SetValue`, `SetMinMaxValues` |
| Cooldown | `Cooldown:SetCooldown`, `SetCooldownFromExpirationTime`, `SetCooldownDuration`, `SetCooldownUNIX` |
| CooldownStyle (12.0.1) | `SetDrawBling`, `SetDrawEdge`, `SetDrawSwipe`, `SetEdgeColor`, `SetSwipeColor` |
| Desaturation | `SetDesaturated`, `SetDesaturation`, `SetStatusBarDesaturation` |
| TexCoords | `SetTexCoord`, `SetSpriteSheetCell` |
| Rotation | `TextureBase:SetRotation` |
| Scale | `SetScale` |
| FrameLevel | `SetFrameLevel` |
| RadialProgress (12.1.0) | `TextureBase:SetRadialProgressBarPercent` |
| ButtonState (12.0.7) | `Button:SetButtonState`, `SetEnabled` |
| ScrollOffset (12.0.7) | `SetHorizontalScroll`, `SetVerticalScroll` |
| Attributes (12.0.1) | `SetAttribute` family |

**Secret anchors.** If an API accepts a secret but has no aspect, the object is marked `HasSecretValues()`.
All its anchoring and position data then becomes secret, and that propagates to anything anchored to it.
Example: a texture anchored to a StatusBar's fill texture. **Do not anchor layout-critical frames to regions
whose size derives from secret values** if you need `GetWidth`/`GetLeft` on them. Heal-prediction overlays
anchored to the health fill are fine as long as you never read their geometry.

### 1.8 Errors you will see

- `attempt to compare ... (a secret value)` / `attempt to perform arithmetic on a secret value`. Exact wording
  is unverified. Check BugSack.
- `attempted to index a forbidden table` when touching a table flagged inaccessible.
- Preconditions behave in three ways. `Error` raises an error. `ReturnNothing` makes the call silently return
  nothing (e.g. `RequiresNonSecretAura`, `RequiresFontStringTextAccess`). `ReturnWithError` returns and logs
  (e.g. `RequiresUnitIdentityAccess`).
- Calling methods on a **forbidden** frame (friendly plate in an instance, AuraButton while auras are secret)
  raises a Lua error. Check `frame:IsForbidden()` first.

### 1.9 Pattern: safe number formatting

```lua
-- Works whether or not cur/max are secret: formatting happens natively.
local function SetHealthText(fs, unit)
    local cur = UnitHealth(unit)
    local pct = UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) -- 0..100, maybe secret
    fs:SetFormattedText("%s | %.0f%%", AbbreviateNumbers(cur), pct)
end
```

`AbbreviateNumbers(number [, options])` became a native API in 12.0.0 and is `AllowedWhenTainted`, so it
accepts secrets and returns a (secret) string. `options` = `{ breakpointData = {...}, locale = "...",
config = AbbreviateConfig }`. Create a config once with `CreateAbbreviateConfig(...)` and reuse it in hot
paths. Breakpoints must be ordered largest to smallest.
Source: https://warcraft.wiki.gg/wiki/API_AbbreviateNumbers

Since 12.0.5 there are reusable formatter objects in `C_StringUtil`:
`CreateAbbreviatedNumberFormatter()`, `CreateNumericRuleFormatter()`, `CreateSecondsFormatter()`,
`GetDefaultAbbreviationBreakpoints()`. The `SecondsFormatter` enum was renamed to
`SecondsFormatterAbbreviation` in 12.0.7, and `SecondsFormatter:SetRounding` arrived in 12.1.0.
`Cooldown:SetCountdownFormatter(formatter)` (12.0.5) styles the built-in countdown numbers.

---

## 2. Helper APIs for working with secrets

### 2.1 UnitHealthPercent / UnitPowerPercent [doc]

```lua
result = UnitHealthPercent(unit [, usePredicted = true [, curve]])
result = UnitPowerPercent(unit [, powerType [, unmodified = false [, curve]]])
```

Without a curve, these return a 0-1 float (secret where restricted). With a `CurveObject`, they return the
curve evaluated at that percentage (a number). With a `ColorCurveObject`, they return a `ColorMixin`.
Source: https://warcraft.wiki.gg/wiki/API_UnitHealthPercent

Built-in curves: `CurveConstants.ZeroToOne`, `CurveConstants.ScaleTo100`, `CurveConstants.Reverse`,
`CurveConstants.ReverseTo100`. Source: https://warcraft.wiki.gg/wiki/ScriptObject_CurveObject

### 2.2 C_CurveUtil and curve objects [doc]

```lua
curve      = C_CurveUtil.CreateCurve()          -- CurveObject (numeric y)
colorCurve = C_CurveUtil.CreateColorCurve()     -- ColorCurveObject (ColorMixin y)
color      = C_CurveUtil.EvaluateColorFromBoolean(bool, colorIfTrue, colorIfFalse)       -- AllowedWhenTainted
value      = C_CurveUtil.EvaluateColorValueFromBoolean(bool, numIfTrue, numIfFalse)      -- AllowedWhenTainted
y          = C_CurveUtil.EvaluateGameCurve(curveID, x)
```

CurveObject methods: `AddPoint(x, y)`, `ClearPoints()`, `Copy()`, `Evaluate(x) -> y`, `GetPoint(i)`,
`GetPointCount()`, `GetPoints()`, `RemovePoint(i)`, `SetPoints(points)`, `SetToDefaults()`, and inherited
`SetType(Enum.LuaCurveType.*)`, `GetType()`, `HasSecretValues()`.
ColorCurveObject has the same methods plus `EvaluateUnpacked(x) -> r, g, b, a`. Curves hold at most **256 points**.
Sources: https://warcraft.wiki.gg/wiki/ScriptObject_CurveObject , https://warcraft.wiki.gg/wiki/ScriptObject_ColorCurveObject

`Enum.LuaCurveType` includes `Linear` and `Step` (both appear in wiki examples). Check the full list in game
with `/dump Enum.LuaCurveType`.

```lua
-- Build once at load. Never per update.
local HealthGradient = C_CurveUtil.CreateColorCurve()
HealthGradient:SetType(Enum.LuaCurveType.Linear)
HealthGradient:AddPoint(0.0, CreateColor(0.85, 0.10, 0.10))
HealthGradient:AddPoint(0.5, CreateColor(0.95, 0.80, 0.10))
HealthGradient:AddPoint(1.0, CreateColor(0.15, 0.80, 0.25))

local function UpdateHealthColor(bar, unit)
    local c = UnitHealthPercent(unit, true, HealthGradient)  -- ColorMixin, possibly secret components
    bar:SetStatusBarColor(c:GetRGB())                        -- SetStatusBarColor accepts secrets (VertexColor aspect)
end
```

Threshold behavior without comparisons uses a **step curve**. For example, "show the execute indicator
below 20%":

```lua
local Execute = C_CurveUtil.CreateCurve()
Execute:SetType(Enum.LuaCurveType.Step)
Execute:AddPoint(0.0, 1)   -- alpha 1 below 20%
Execute:AddPoint(0.2, 0)   -- alpha 0 from 20% up
indicator:SetAlpha(UnitHealthPercent(unit, true, Execute))   -- SetAlpha accepts a secret
```

**[inferred]** Check step semantics (whether the point at x uses the left or right value) in game.

### 2.3 Duration objects (C_DurationUtil) [doc]

```lua
d = C_DurationUtil.CreateDuration()           -- empty DurationObject
-- 12.0.7: C_DurationUtil.CreateManualClock(), C_DurationUtil.CreateDurationTextBinding()
-- removed in 12.0.7: C_DurationUtil.GetCurrentTime
```

DurationObject methods (source: https://warcraft.wiki.gg/wiki/ScriptObject_DurationObject):

- Setup: `SetTimeFromStart(startTime, duration [, modRate])`, `SetTimeFromEnd(endTime, duration [, modRate])`,
  `SetTimeSpan(startTime, endTime)`, `SetClock([clock])`, `Assign(other)`, `Copy()`, `Reset()`, `SetToDefaults()`
- Read: `GetStartTime`, `GetEndTime`, `GetTotalDuration`, `GetElapsedDuration`, `GetRemainingDuration`,
  `GetElapsedPercent`, `GetRemainingPercent`, `GetModRate`, `GetClock`, `GetClockTime` (all take an optional `modifier`)
- Curves: `EvaluateTotalDuration(curve)`, `EvaluateElapsedDuration(curve)`, `EvaluateRemainingDuration(curve)`,
  `EvaluateElapsedPercent(curve)`, `EvaluateRemainingPercent(curve)`
- Format: `FormatTotalDuration(formatter)`, `FormatElapsedDuration(formatter)`, `FormatRemainingDuration(formatter)`
- State: `HasStarted()`, `HasExpired()`, `IsActive()`, `IsZero()`, `HasSecretValues()`

Sources of DurationObjects: `UnitCastingDuration`, `UnitChannelDuration`, `UnitEmpoweredChannelDuration`,
`C_UnitAuras.GetAuraDuration(unit, auraInstanceID)`, `C_Spell.GetSpellCooldownDuration(spell [, ignoreGCD])`,
`C_Spell.GetSpellChargeDuration(spell)`, `C_Spell.GetSpellLossOfControlCooldownDuration(spell)`,
`C_ActionBar.GetActionCooldownDuration(...)`, `C_SpellBook.GetSpellBookItemCooldownDuration(...)`,
`C_EncounterTimeline.GetEventTimer(eventID)`.

Consumers:

```lua
StatusBar:SetTimerDuration(duration [, interpolation = Immediate [, direction = ElapsedTime]])
--   Enum.StatusBarInterpolation: Immediate (0), ExponentialEaseOut (1)
--   Enum.StatusBarTimerDirection: ElapsedTime (0), RemainingTime (1)
Cooldown:SetCooldownFromDurationObject(duration [, clearIfZero = true])
```

Sources: https://warcraft.wiki.gg/wiki/API_StatusBar_SetTimerDuration ,
https://warcraft.wiki.gg/wiki/API_Cooldown_SetCooldownFromDurationObject

Both consumers are documented as `AllowedWhenUntainted` for secret *arguments*, yet oUF (tainted) calls them
every cast. The DurationObject itself is an opaque object, not a secret value, so passing it is fine. Only
raw secret numbers would be refused. `SetCooldownFromDurationObject` is also tagged `IsProtectedFunction`, and
12.1.5 forbids `Cooldown:SetCooldown`/`Clear` from tainted code **on protected cooldown frames**. Use your own
(unprotected) Cooldown frames.

### 2.4 DurationTextBinding (12.0.7+) for countdown text without OnUpdate

```lua
local binding = C_DurationUtil.CreateDurationTextBinding()
binding:SetFontString(timeFS)
binding:SetFormatter(C_StringUtil.CreateSecondsFormatter())
binding:SetUpdateInterval(0.1)          -- native ticking, no Lua OnUpdate
binding:SetZeroDurationText("")
binding:SetExpiredText("")
-- 12.1.0: binding:SetTextColorCurve(colorCurve, property)  e.g. turn red as remaining time runs out
binding:SetDuration(UnitCastingDuration("target"))
binding:Enable()
```

Methods (30): `Assign`, `CanFormatText`, `CanUpdateFontString`, `ClearTextColorCurve`, `Copy`, `Disable`, `Enable`,
`GetDuration`, `GetExpiredText`, `GetFontString`, `GetFormattedText`, `GetFormattedTextColor`, `GetTextColorCurve`,
`GetTimeModifier`, `GetUpdateInterval`, `GetZeroDurationText`, `HasSecretValues`, `IsEnabled`, `SetDuration`,
`SetEnabled`, `SetExpiredText`, `SetFontString`, `SetFormatter`, `SetTextColorCurve`, `SetTextFormat(fmt, components)`,
`SetTimeModifier`, `SetToDefaults`, `SetUpdateInterval`, `SetZeroDurationText`, `UpdateFontString`.
Source: https://warcraft.wiki.gg/wiki/ScriptObject_DurationTextBinding

### 2.5 Heal prediction calculator [doc]

```lua
local calc = CreateUnitHealPredictionCalculator()
UnitGetDetailedHealPrediction(unit, healerUnit_or_nil, calc)   -- fills calc; healer nil => healer values 0
```

Calculator methods (source: https://warcraft.wiki.gg/wiki/ScriptObject_UnitHealPredictionCalculator):

- Health: `GetCurrentHealth()`, `GetMaximumHealth()`, `GetMissingHealth()`, `GetCurrentHealthPercent()`,
  `GetMissingHealthPercent()`, `EvaluateCurrentHealthPercent(curve)`, `EvaluateMissingHealthPercent(curve)`,
  `Set/GetMaximumHealthMode(mode)`
- Absorbs: `GetDamageAbsorbs() -> amount, clamped`, `GetTotalDamageAbsorbs()`, `GetMaximumDamageAbsorbs()`,
  `Set/GetDamageAbsorbClampMode`
- Heal absorbs: `GetHealAbsorbs() -> amount, clamped`, `GetTotalHealAbsorbs()`, `GetMaximumHealAbsorbs()`,
  `Set/GetHealAbsorbClampMode`, `Set/GetHealAbsorbMode`
- Incoming: `GetIncomingHeals() -> amount, fromHealer, fromOthers, clamped`, `GetTotalIncomingHeals()`,
  `GetTotalIncomingHealsFromHealer()`, `GetMaximumIncomingHeals()`, `Set/GetIncomingHealClampMode`,
  `Set/GetIncomingHealOverflowPercent`
- State: `Get/Set/ResetPredictedValues`, `Reset()`, `SetToDefaults()`, `HasSecretValues()`

oUF's health element (the cleanest public 12.x reference), paraphrased in our own words:

```lua
-- once per frame
element.values = CreateUnitHealPredictionCalculator()
-- configure clamp modes here (enum names: see /dump Enum.UnitHealPrediction* in game)

-- on UNIT_HEALTH / UNIT_MAXHEALTH / UNIT_HEAL_PREDICTION / UNIT_ABSORB_AMOUNT_CHANGED /
--    UNIT_HEAL_ABSORB_AMOUNT_CHANGED / UNIT_MAX_HEALTH_MODIFIERS_CHANGED / UNIT_CONNECTION
UnitGetDetailedHealPrediction(unit, "player", calc)
local max = calc:GetMaximumHealth()
bar:SetMinMaxValues(0, max)
bar:SetValue(calc:GetCurrentHealth(), Enum.StatusBarInterpolation.ExponentialEaseOut)
absorbBar:SetMinMaxValues(0, max);   absorbBar:SetValue((calc:GetDamageAbsorbs()))
healBar:SetMinMaxValues(0, max);     healBar:SetValue((calc:GetIncomingHeals()))
local _, overAbsorb = calc:GetDamageAbsorbs()
overAbsorbGlow:SetAlphaFromBoolean(overAbsorb, 1, 0)       -- clamped flag drives a glow, no comparison
local color = calc:EvaluateCurrentHealthPercent(HealthGradient)
```

`GetUnitTotalModifiedMaxHealthPercent(unit)` drives a "temporary max-health loss" bar.
Source: https://github.com/oUF-wow/oUF/blob/master/elements/health.lua

### 2.6 Boolean helpers

```lua
Region:SetAlphaFromBoolean(bool [, alphaIfTrue [, alphaIfFalse]])        -- AllowedWhenTainted, adds Alpha aspect
Region:SetVertexColorFromBoolean(bool, colorIfTrue, colorIfFalse)       -- adds VertexColor aspect [args inferred]
Frame:SetAlphaFromBoolean(...)                                          -- also on Frame
C_CurveUtil.EvaluateColorFromBoolean(bool, colorIfTrue, colorIfFalse)   -- -> ColorMixin
C_CurveUtil.EvaluateColorValueFromBoolean(bool, numIfTrue, numIfFalse)  -- -> number
```

Use these anywhere you would write `if secretBool then A else B end`:

```lua
shield:SetAlphaFromBoolean(notInterruptible, 1, 0)                         -- cast-bar shield
local c = C_CurveUtil.EvaluateColorFromBoolean(notInterruptible, GREY, YELLOW)
castbar:SetStatusBarColor(c:GetRGB())
rangeFader:SetAlphaFromBoolean(UnitInRange(unit), 1, 0.45)
```

There is **no** generic `SetShownFromBoolean`. `SetShown(secretBool)` is accepted and applies the Shown
aspect, but then `IsShown()` returns a secret for that frame. Prefer alpha for visual toggles, and never use
`SetShown(secret)` on a frame whose visibility you later need to read.

### 2.7 StatusBar interpolation and render additions

- `StatusBar:SetValue(value [, interpolation])` and `SetMinMaxValues(min, max [, interpolation])` (12.0.0).
  Native smoothing replaces Lua smoothing libraries (no OnUpdate needed).
- `StatusBar:SetToTargetValue()`, `GetInterpolatedValue()`, `IsInterpolating()` (12.0.0). The getters return
  secrets if the bar holds secrets.
- `StatusBar:SetRenderMode/GetRenderMode` (12.1.0) and radial progress on textures and status bars:
  `SetRadialProgressBarPercent`, `...StartOffset`, `...EndOffset`, `...Reverse`, `...Feather` (12.1.0). Radial
  percent accepts secrets (RadialProgress aspect), which makes ring-shaped health, cooldown or cast indicators
  possible without math.

---

## 3. Auras (biggest change in 12.1.0)

Sources: https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes/notes ,
https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitAuraDocumentation.lua ,
https://github.com/oUF-wow/oUF/blob/master/elements/auras.lua ,
https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes/notes

### 3.1 What changed

- **12.0.x:** aura *fields* were secret (`SecretWhenUnitAuraRestricted`), but addons could still iterate and
  display them via `C_UnitAuras.GetAuraDataByAuraInstanceID`, `GetUnitAuraInstanceIDs`, `GetAuraDuration`, and so on.
- **12.1.0 (PTR 3 onward):** while auras are restricted (combat, encounters, M+, PvP), the `C_UnitAuras` and
  `C_TooltipInfo` functions that access aura data **by index, slot or instance ID raise a Lua error** when
  called by addons (precondition `RequiresUnitAuraAccess`). `UNIT_AURA` delivers a **fully secret payload**,
  and AuraData structs are fully secret. Lookups **by spell ID or name** (`GetPlayerAuraBySpellID`,
  `GetUnitAuraBySpellID`, `GetAuraDataBySpellName`) still work, and return real values for spells on the
  **never-secret** list (precondition `RequiresNonSecretAura`: secret auras return nothing).
- Healer HoTs and buffs were **removed** from the never-secret list in 12.1.0 PTR 6, because containers can now
  filter them on raid members. Raid-frame HoT tracking must use containers and `includeSpellIDs`.
- `SecureAuraHeaderTemplate` was **removed from Mainline**. Classic keeps it.
- `UnitIsCharmed` and `UnitIsPossessed` return secrets while auras are secret, except for player, pet and vehicle.

### 3.2 C_UnitAuras reference (12.1.5) [doc]

RUA = RequiresUnitAuraAccess (errors while restricted), SWURA = SecretWhenUnitAuraRestricted, RNSA = RequiresNonSecretAura.

| Function | Notes |
|---|---|
| `GetAuraDataByAuraInstanceID(unit, auraInstanceID) -> AuraData?` | RUA, SWURA |
| `GetAuraDataByIndex(unit, index [, filter])`, `GetBuffDataByIndex`, `GetDebuffDataByIndex` | RUA, SWURA |
| `GetAuraDataBySlot(unit, slot)`, `GetAuraSlots(unit [, filter [, maxSlots [, contToken]]])` | RUA |
| `GetUnitAuraInstanceIDs(unit, filter [, maxCount [, sortRule [, sortDirection]]]) -> {ids}` | RUA |
| `GetUnitAuras(unit, filter [, maxCount [, sortRule [, sortDirection]]]) -> {AuraData}` | RUA |
| `GetAuraDuration(unit, auraInstanceID) -> DurationObject` | RUA |
| `GetAuraApplicationDisplayCount(unit, id [, min=2 [, max]]) -> string` | RUA, SWURA |
| `GetAuraDispelTypeColor(unit, id, colorCurve) -> ColorMixin` | RUA, SWURA |
| `DoesAuraHaveExpirationTime(unit, id) -> bool` | RUA, SWURA |
| `GetAuraBaseDuration`, `GetRefreshExtendedDuration`, `GetRefreshCarryOverDuration` (12.1.5) | RUA, SWURA |
| `GetAuraCasterGUID(unit, id)` | RUA, SWURA |
| `IsAuraFilteredOutByInstanceID(unit, id, filter) -> bool` | RUA |
| `GetPlayerAuraBySpellID(spellID)`, `GetUnitAuraBySpellID(unit, spellID)`, `GetAuraDataBySpellName(unit, name [, filter])` | SWURA, RNSA (work for never-secret spells) |
| `AuraIsPrivate(spellID)`, `AuraIsBigDefensive(spellID)`, `GetCooldownAuraBySpellID(spellID)` | safe |
| `AddAuraSound(trigger, soundInfo) -> id` / `RemoveAuraSound(id)` | 12.1.5: optional `throttleSeconds` (max 5), playback capped at 5 s |
| `AddPrivateAuraAnchor(args)` / `RemovePrivateAuraAnchor(id)` | private auras (section 6) |
| `CancelAuraByInstanceID(unit, id)` | RUA, HasRestrictions |

`UNIT_AURA(unitTarget, updateInfo)` is SecretWhenAurasRestricted. Do not read `updateInfo` fields in combat.
Treat the event as "something changed" only, and let a container handle it.

**Filters.** These are the standard `"HELPFUL"`, `"HARMFUL"`, `"PLAYER"`, `"RAID"`, `"CANCELABLE"`, ... strings.
12.1.0 added `!` negation (`"HELPFUL|!PLAYER"`), `"DISPELLABLE"`, `"RAID_PLAYER_DISPELLABLE"` (includes enemy
buffs stealable or purgeable by the raid), and restored `"IMPORTANT"`, which 12.0.7 had removed.

### 3.3 Aura containers: the 12.1 way to display auras

Frame types: `AuraContainer` (managed), with `CustomAuraContainerTemplate`, and `CustomAuraButton` children
that the container creates itself. The addon **never** sees aura data. It styles buttons and the container
fills them. Buttons get **forbidden aspects** at creation and become fully forbidden (tainted calls error)
whenever auras are secret, from just after `initializeFrame` runs until restrictions lift.

```lua
-- Our own code, modelled on the documented API (12.1.0 notes + oUF usage)
local c = CreateFrame("AuraContainer", nil, unitFrame, "CustomAuraContainerTemplate")
c:SetPoint("BOTTOMLEFT", unitFrame, "TOPLEFT", 0, 4)
c:SetUnit("target")

-- Layout (AnchorUtil-style flow layout)
c:SetFlowLayoutAnchorPoint("BOTTOMLEFT")
c:SetFlowLayoutAxis(...)                      -- horizontal or vertical; check enum with /dump
c:SetFlowLayoutMaximumLineSize(unitFrame:GetWidth())
c:SetFlowLayoutGrowthDirection(...)           -- growthX, growthY
c:SetFlowLayoutPadding(2)

-- Groups: dynamic lists, each with its own filter
c:AddAuraGroup("debuffs", "HARMFUL|PLAYER", {
    maxFrameCount = 8,
    sortMethod    = AuraContainerSortMethod.ExpirationOnly,
    sortDirection = AuraContainerSortDirection.Normal,
    initializeFrame = function(button)        -- runs ONCE per button; style it here
        button:SetSize(24, 24)
        -- create regions and hand them to the button:
        -- button:SetIcon(tex), button:SetDurationCooldown(cd), button:SetDurationText(fs),
        -- button:SetApplicationCount(fs), button:AddDispelTypeTexture(tex), button:SetAuraBorder(tex, opts),
        -- button:SetTooltipAnchorPoint(...), button:SetHideTooltipInCombat(true),
        -- button:SetCancelAuraButtons("RightButtonUp"), button:SetCasterName(fs) -- 12.1.5
    end,
    candidateFilters = {
        includeSpellIDs = { [774] = true },     -- example only; check the exact table shape
        isFromPlayerOrPlayerPet = true,         -- set to false to negate (PTR 6)
        -- also: excludeSpellIDs, include/exclude dispel types, maxDuration, isRoleAura,
        --       isPriorityAura, isStealable
    },
})

-- Slots: one fixed button you can anchor yourself (e.g. a HoT indicator at a raid-frame corner)
c:AddAuraSlot("rejuv", "HELPFUL|PLAYER", { candidateFilters = { includeSpellIDs = { [774] = true } } })

-- Temporary weapon enchants
c:AddItemEnchantment(itemEnchantmentSlot, options)
c:SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura, policy)
c:UpdateAllAuras();  c:SetEnabled(true)
```

12.1.0 additions: `SetAuraGroupLayout`, `GetAuraGroupFrame(index)`, `SetAuraGroupFilterString`, `layoutIndex`,
column layouts, and an instance-ID-only sort. Groups anchor in the order they are added, and buttons are created
in batches of 10. `SetApplicationBar` shows a stack-count bar (12.1.5 adds `minApplications`).
12.1.5 additions: `SetAuraGroupEnabled`, `SetAuraSlotEnabled`, `SetItemEnchantmentEnabled`,
`SetEditModePreviewEnabled` (preview auras in Edit Mode), and button pandemic animations
`Add/RemovePandemic{Enter,Active,Leave}Animation(animGroup)`, `AddAuraShownAnimation`, `AddAuraAssignedAnimation`.
`AddDispelTypeTexture`/`AddPandemicRegion` no longer return an index. Remove by region reference.
`AuraContainerUtil.GetPandemicWindow` uses `C_UnitAuras.GetRefreshCarryOverDuration`.

**Restrictions to design around**

- Containers **cannot be created in combat**: a Lua error, as intended. Create all of them at load.
- Containers have the `EventRegistrations` forbidden aspect, and containers with groups get **no `OnSizeChanged`**.
  The same applies to frames anchored to them. Don't size neighbours from the container's size.
- Aura buttons cannot be reparented, and configured child components cannot be reparented either.
  `SetPoint`/`SetSize` on them is allowed during reload until `PLAYER_LOGIN`.
- Tooltips are on by default. Turn them off with `SetMouseMotionEnabled(false)`. They update every 200 ms.
- A raid frame should get its container once at creation. `SecureGroupHeaderTemplate`'s `initialConfigFunction`
  is Blizzard's suggested place.

### 3.4 Out-of-combat / never-secret paths

When `C_Secrets.HasSecretRestrictions()` is false or auras are not restricted (open world, out of combat), the
classic `C_UnitAuras` calls still work. Don't maintain two rendering paths. Use containers everywhere and use
`GetPlayerAuraBySpellID` only for never-secret player buffs (e.g. Sated, Bloodlust-style debuffs, class
resources on the whitelist).

---

## 4. Cast bars

Source: https://github.com/oUF-wow/oUF/blob/master/elements/castbar.lua , UnitDocumentation.lua.

```lua
local function CastStart(bar, unit, isChannel)
    local duration, direction
    if isChannel then
        duration  = UnitChannelDuration(unit)
        direction = Enum.StatusBarTimerDirection.RemainingTime
    else
        duration  = UnitCastingDuration(unit)
        direction = Enum.StatusBarTimerDirection.ElapsedTime
    end
    if not duration then return bar:Hide() end
    local name, _, texture, _, _, _, castID, notInterruptible = UnitCastingInfo(unit) -- may be secret
    bar.castID = castID                         -- store and pass, never compare when secret
    bar.Text:SetText(name)                      -- secret string is fine
    bar.Icon:SetTexture(texture)                -- check in game that SetTexture accepts a secret fileID
    bar:SetTimerDuration(duration, Enum.StatusBarInterpolation.Immediate, direction)
    bar.Shield:SetAlphaFromBoolean(notInterruptible, 1, 0)
    bar.TimeBinding:SetDuration(duration)       -- DurationTextBinding for the "1.4" text
    bar:Show()
end
```

- Events still fire: `UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED/DELAYED/CHANNEL_START/CHANNEL_UPDATE/
  CHANNEL_STOP/EMPOWER_START/EMPOWER_UPDATE/EMPOWER_STOP/INTERRUPTIBLE/NOT_INTERRUPTIBLE`.
- `castBarID` (NeverSecret, new 12.0.0) identifies the cast bar. In 12.1.5 it is unique per unit-token string,
  so `"PLAYER"` and `"player"` give different IDs. Events always use lowercase tokens.
- oUF only reads `startTimeMs`/`endTimeMs` for the player ("we can only read these variables for players").
- Empowered casts: `UnitEmpoweredStageDurations`, `UnitEmpoweredStagePercentages`, and the stage count are unrestricted.
- 12.1.0 fixed nameplate cast-bar taint involving `CastingBarTypeInfo`. Don't write into Blizzard's tables.

---

## 5. Damage meters (C_DamageMeter)

Sources: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/DamageMeterDocumentation.lua ,
https://warcraft.wiki.gg/wiki/API_C_DamageMeter.GetCombatSessionFromType , https://warcraft.wiki.gg/wiki/Damage_Meter ,
https://www.wowhead.com/news/blizzards-damage-meter-shortcomings-in-midnight-pre-patch-addon-alternatives-379992 ,
Recount Revived changelog https://www.curseforge.com/wow/addons/recount-revived/files/8225229

### 5.1 API [doc]

```lua
isAvailable, failureReason = C_DamageMeter.IsDamageMeterAvailable()
sessions = C_DamageMeter.GetAvailableCombatSessions()          -- { {sessionID, name, durationSeconds?}, ... }
session  = C_DamageMeter.GetCombatSessionFromType(sessionType, meterType)   -- SecretWhenInCombat
session  = C_DamageMeter.GetCombatSessionFromID(sessionID, meterType)       -- SecretWhenInCombat
src      = C_DamageMeter.GetCombatSessionSourceFromType(sessionType, meterType [, sourceGUID [, sourceCreatureID]])
src      = C_DamageMeter.GetCombatSessionSourceFromID(sessionID, meterType [, sourceGUID [, sourceCreatureID]])
secs     = C_DamageMeter.GetSessionDurationSeconds(sessionType)
C_DamageMeter.ResetAllCombatSessions()
```

Enums:
- `Enum.DamageMeterSessionType`: `Overall = 0`, `Current = 1`, `Expired = 2`
- `Enum.DamageMeterType`: `DamageDone = 0`, `Dps = 1`, `HealingDone = 2`, `Hps = 3`, `Absorbs = 4`,
  `Interrupts = 5`, `Dispels = 6`, `DamageTaken = 7`, `AvoidableDamageTaken = 8`, `Deaths = 9` (12.0.1),
  `EnemyDamageTaken = 10` (12.0.1)
- `Enum.DamageMeterSourceDisplayType` (12.0.5) and `Enum.DamageMeterVisibility` (adds `InGroup` in 12.0.7)

Structures:
- `DamageMeterCombatSession { combatSources = {DamageMeterCombatSource}, maxAmount, totalAmount, durationSeconds? }`
- `DamageMeterCombatSource { sourceGUID? (cond. secret; secret when identity is secret, 12.1.5), sourceCreatureID?,
  name (cond. secret), classFilename*, specIconID*, totalAmount, amountPerSecond, isLocalPlayer*, deathRecapID*,
  deathTimeSeconds, classification*, sourceDisplayType, factionGroup? }` (* = NeverSecret)
- `DamageMeterCombatSessionSource { combatSpells = {DamageMeterCombatSpell}, maxAmount, totalAmount }`
- `DamageMeterCombatSpell { spellID, totalAmount, amountPerSecond, creatureName, overkillAmount, isAvoidable,
  isDeadly, combatSpellDetails = { unitName, unitClassFilename*, classification*, isPet, isMob, amount, specIconID* } }`

Events: `DAMAGE_METER_COMBAT_SESSION_UPDATED(meterType, sessionID)`, `DAMAGE_METER_CURRENT_SESSION_UPDATED`,
`DAMAGE_METER_RESET`.

### 5.2 How meters work now

- `COMBAT_LOG_EVENT_UNFILTERED` is gone for addons. Registering it **errors**. All third-party meters (Details!,
  Recount Revived, Skada forks) now **re-skin `C_DamageMeter` data**. Modes without a C_DamageMeter source
  (friendly fire, healing taken, overhealing, DoT uptime, activity, threat) render blank in those addons.
- During combat the amounts are secret. You **cannot sort, sum, diff or compute percentages** in Lua. Recount's
  maintainers report their delta approach (`total - snapshot`, `delta > 0`) could never work, so they display
  the values directly. Assume `combatSources` arrives **already ordered** by the server (check in game) and
  render rows in the order given.
- Bar width: `row:SetMinMaxValues(0, session.maxAmount); row:SetValue(source.totalAmount)`. Both may be secret,
  which is fine.
- Text: `row.value:SetFormattedText("%s (%s)", AbbreviateNumbers(src.totalAmount), AbbreviateNumbers(src.amountPerSecond))`.
- Percent of total: no division on secrets in Lua. Either skip it during combat or use a second StatusBar trick
  (SetMinMaxValues(0, total), SetValue(amount)) for a visual share. Text percentages only once
  `issecretvalue(total)` is false (out of combat).
- Class colors and spec icons are NeverSecret (`classFilename`, `specIconID`), so row coloring is always possible.
- Names can be secret for non-group units. Pass them to `SetText` only.
- Out of combat everything is readable, so full breakdowns, history and saving to SavedVariables are fine after
  `PLAYER_REGEN_ENABLED`.
- Addon messaging is throttled or blocked during encounters
  (`C_ChatInfo.AreOutgoingAddonChatMessagesRestricted()`, 12.0.5), so don't plan meter sync in combat.

---

## 6. Encounter timeline, warnings, private auras

Sources: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterTimelineDocumentation.lua ,
12.0.7 API changes.

### 6.1 C_EncounterTimeline (Blizzard's built-in boss timers)

Blizzard ships boss timers (the timeline) and warnings natively. Addons can **render** the timeline but cannot
read secret event details (`SecretWhenEncounterEvent`) to make decisions.

```lua
C_EncounterTimeline.IsFeatureAvailable() / IsFeatureEnabled()
ids  = C_EncounterTimeline.GetEventList()                                   -- unsorted IDs
ids  = C_EncounterTimeline.GetSortedEventList([maxCount [, maxDuration [, excludeTerminal=true [, excludeHidden=true]]]])
info = C_EncounterTimeline.GetEventInfo(eventID)    -- {id*, source*, spellName, spellID, iconFileID, duration*, maxQueueDuration*, icons, severity, isApproximate}
d    = C_EncounterTimeline.GetEventTimer(eventID)   -- DurationObject => StatusBar:SetTimerDuration / DurationTextBinding
t    = C_EncounterTimeline.GetEventTimeRemaining(eventID)
st   = C_EncounterTimeline.GetEventState(eventID)
track, sortIndex = C_EncounterTimeline.GetEventTrack(eventID)
color = C_EncounterTimeline.GetEventColor(eventID [, overrideTrigger])     -- 12.0.7: returns colorRGBA
C_EncounterTimeline.SetEventIconTextures(eventID, iconMask, {textures})    -- paints role/effect icons onto your textures
-- Script events: addons may ADD their own timers to the timeline
id = C_EncounterTimeline.AddScriptEvent({ spellID=, iconFileID=, duration=, maxQueueDuration=0,
                                          overrideName="", icons=nil, severity="Medium", paused=false })
C_EncounterTimeline.PauseScriptEvent(id) / ResumeScriptEvent(id) / FinishScriptEvent(id) / CancelScriptEvent(id) / CancelAllScriptEvents()
C_EncounterTimeline.AddEditModeEvents() / CancelEditModeEvents()           -- fake events for previews
C_EncounterTimeline.GetTrackList() / GetTrackInfo(track) / GetViewType() / SetViewType(viewType)
```

Most getters are `SecretArguments = NotAllowed`, but event IDs are not secret, so that is fine.
Events: `ENCOUNTER_TIMELINE_EVENT_ADDED(eventInfo)`, `..._REMOVED(eventID)`, `..._STATE_CHANGED`,
`..._TRACK_CHANGED`, `..._HIGHLIGHT`, `..._BLOCK_STATE_CHANGED`, `..._COLOR_CHANGED` (12.0.7),
`ENCOUNTER_TIMELINE_LAYOUT_UPDATED`, `ENCOUNTER_TIMELINE_STATE_UPDATED`, `ENCOUNTER_TIMELINE_VIEW_ACTIVATED/DEACTIVATED`.
`ENCOUNTER_END` gained `encounterUnitStatus` (12.0.7).

### 6.2 C_EncounterWarnings

`IsFeatureAvailable()`, `IsFeatureEnabled()`, `GetEditModeWarningInfo()`, `GetSoundKitForSeverity(sev)`,
`GetColorForSeverity(sev) -> colorRGBA` (12.0.7), `PlaySound(...)`. These are Blizzard's on-screen boss warnings.
SoulUI should **restyle or reposition** Blizzard's warning frame rather than reimplement it.

### 6.3 Private auras

Private auras are invisible to addons. You can only provide an anchor and Blizzard renders the icon there:
`C_UnitAuras.AddPrivateAuraAnchor(args) -> anchorID`, `RemovePrivateAuraAnchor(anchorID)`,
`SetPrivateWarningTextAnchor(parent [, anchorBinding])`. Since 12.1.0, containers treat private auras like
regular auras for showing and sorting, so a raid-frame container shows them automatically.

---

## 7. Nameplates

Sources: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/NamePlateDocumentation.lua ,
.../NamePlateManagerDocumentation.lua , https://warcraft.wiki.gg/wiki/API_NamePlate_SetHitTestPoints ,
12.0.5 and 12.1.5 notes, https://wow-midnight-addon-template.vercel.app/tutorials/nameplate-restyler/ ,
https://www.curseforge.com/wow/addons/platynator , https://www.curseforge.com/wow/addons/df-friendly-nameplates

### 7.1 API [doc]

```lua
plate = C_NamePlate.GetNamePlateForUnit(unit [, includeForbidden = false])
plates = C_NamePlate.GetNamePlates()
w, h = C_NamePlate.GetNamePlateSize();  C_NamePlate.SetNamePlateSize(w, h)   -- HasRestrictions: out of combat
C_NamePlateManager.SetNamePlateHitTestInsets(type, left, right, top, bottom) -- positive shrinks; HasRestrictions; secrets NotAllowed
l, r, t, b = C_NamePlateManager.GetNamePlateHitTestInsets(type)              -- type = Enum.NamePlateType (friendly/enemy/...)
C_NamePlateManager.SetNamePlateSimplified(unit, isSimplified)
behind = C_NamePlateManager.IsNamePlateUnitBehindCamera(unit)
-- 12.0.5 per-plate hit area (untainted-only per docs, see uncertain points):
plate:SetHitTestPoints({ {point=, relativeTo=, relativePoint=, offsetX=, offsetY=}, ... })
plate:SetAllHitTestPoints(region)   plate:GetHitTestPoints()   plate:ClearAllHitTestPoints()   plate:CanChangeHitTestPoints()
```

Removed along the way: `C_NamePlateManager.SetNamePlateHitTestFrame` (12.0.5). The 12.0.0 friendly/enemy/self
size and click-through variants listed on the 12.0.0 changes page are **not present in the 12.1.5 docs**. Treat
them as gone.

Events: `NAME_PLATE_CREATED(frame)`, `NAME_PLATE_UNIT_ADDED(unit)`, `NAME_PLATE_UNIT_REMOVED(unit)`,
`FORBIDDEN_NAME_PLATE_CREATED`, `FORBIDDEN_NAME_PLATE_UNIT_ADDED/REMOVED`,
`NAME_PLATE_UNIT_BEHIND_CAMERA_CHANGED(unit, isBehind)`.

### 7.2 What custom nameplate addons can still do

- **Enemy plates:** fully restylable. Either hide Blizzard's `UnitFrame` and parent your own frame to the
  nameplate on `NAME_PLATE_UNIT_ADDED` (Plater, ElvUI, oUF style), or skin the Blizzard frame (Platynator,
  "designed to work within the Midnight constraints"). All values follow section 1: health via
  calculator/percent, color via curves, cast bar via duration, auras via an `AuraContainer` with
  `SetUnit("nameplateN")`.
- **Threat coloring:** `UnitThreatSituation("player", unit)` is secret on restricted maps, so you can't branch on
  it in Lua. Use a step curve or `EvaluateColorFromBoolean` only where a secret boolean exists. Otherwise lean on
  Blizzard's native threat color option. Blizzard restored enemy color-coding to its own plates for Midnight
  (https://www.wowhead.com/news/color-coding-enemy-nameplates-is-returning-in-midnight-379467).
- **Friendly plates inside dungeons and raids are forbidden frames** (`FORBIDDEN_NAME_PLATE_*`, a rule dating
  back to 7.2). You can only influence them via CVars and Blizzard's options. Addons like DF Friendly Nameplates
  claim to hook Blizzard's driver to apply settings. Always check `if plate:IsForbidden() then return end`.
- **Hitbox:** set the clickable area with `SetNamePlateHitTestInsets` (global, per type, out of combat). 12.1.5
  gives addons "one extra frame" to adjust the **enemy** hitbox when `UNIT_CLASSIFICATION_CHANGED` arrives late.
- **Unit identity on plates:** `UnitName`/`UnitGUID` on enemy NPC plates are secret in restricted content. Use
  them for display only. Never key tables on GUID while it might be secret. Use the plate frame or unit token as the key.
- `UnitIsUnit("target", plateUnit)` may be secret (`SecretWhenUnitComparisonRestricted`). For the "is my
  target" highlight, prefer `PLAYER_TARGET_CHANGED` with `C_NamePlate.GetNamePlateForUnit("target")`. That lookup
  takes the token, not a comparison.

### 7.3 CVars (12.x)

Restored in 12.1.5: `nameplateMotionSpeed` (default 0.025), `nameplateBottomInset` (0.10), `nameplateTopInset` (0.08).
Present per 12.0.5: `NamePlateHorizontalScale`, `NamePlateVerticalScale`, `nameplateShowFriends`,
`ShowClassColorInNameplate`. The usual `nameplateShowEnemies`, `nameplateMaxDistance`, `nameplateMotion`,
`nameplateOverlapV/H`, `nameplateOccludedAlphaMult`, and `nameplateSelectedScale` should still exist
(check with `/dump C_CVar.GetCVar("...")`). Set CVars **out of combat** only.

---

## 8. Cooldowns and the Blizzard Cooldown Manager

Sources: https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/SpellDocumentation.lua ,
SpellSharedDocumentation.lua , CooldownViewerDocumentation.lua , 12.0.5 changes.

### 8.1 Spell cooldown APIs [doc]

```lua
info = C_Spell.GetSpellCooldown(spell)        -- SecretWhenCooldownsRestricted
-- info = { startTime, duration, isEnabled*, isActive*, modRate, activeCategory?, timeUntilEndOfStartRecovery?, isOnGCD*? }
d    = C_Spell.GetSpellCooldownDuration(spell [, ignoreGCD = false])   -- DurationObject (ignoreGCD: 12.0.5)
ch   = C_Spell.GetSpellCharges(spell)         -- { currentCharges, maxCharges*, cooldownStartTime, cooldownDuration, chargeModRate, isActive* }
d    = C_Spell.GetSpellChargeDuration(spell)
loc  = C_Spell.GetSpellLossOfControlCooldownInfo(spell) / GetSpellLossOfControlCooldownDuration(spell)
n    = C_Spell.GetSpellCastCount(spell)       -- SecretWhenCooldownsRestricted
s    = C_Spell.GetSpellDisplayCount(spell, maxDisplayCount, replacementString)
-- same pattern on C_ActionBar.GetActionCooldown/GetActionCooldownDuration and C_SpellBook.*
```

(* = NeverSecret). `SPELL_UPDATE_COOLDOWN` gained an `itemID` payload in 12.1.0.

Pattern for a cooldown icon:

```lua
local function UpdateCD(btn)
    local d = C_Spell.GetSpellCooldownDuration(btn.spellID, true)  -- ignore GCD
    if d then btn.cd:SetCooldownFromDurationObject(d) else btn.cd:Clear() end
    local info = C_Spell.GetSpellCooldown(btn.spellID)
    if info then btn.icon:SetDesaturated(info.isActive and not info.isOnGCD) end  -- NeverSecret fields
    local charges = C_Spell.GetSpellCharges(btn.spellID)
    if charges then btn.count:SetText(charges.currentCharges) end  -- secret is OK for SetText
end
```

Whitelisted (never-secret) spells: Blizzard keeps class resources and some major cooldowns readable. Request
more on the UI & Macro forum. Check per spell with `C_Secrets.GetSpellCooldownSecrecy(spellID)`.

### 8.2 C_CooldownViewer (Blizzard Cooldown Manager) [doc]

```lua
ok, reason = C_CooldownViewer.IsCooldownViewerAvailable()
ids  = C_CooldownViewer.GetCooldownViewerCategorySet(category [, allowUnlearned=false])  -- Enum.CooldownViewerCategory
info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
-- { cooldownID, spellID?, spellCategoryID?, overrideSpellID?, overrideTooltipSpellID?, equipSlot?, buffSlot?,
--   linkedSpellIDs, selfAura, hasAura, charges, isKnown, isInvisible, flags, category }
alerts = C_CooldownViewer.GetValidAlertTypes(cooldownID)
data = C_CooldownViewer.GetLayoutData();  C_CooldownViewer.SetLayoutData(data)  -- serialized user layout string
```

Events: `COOLDOWN_VIEWER_DATA_LOADED`, `COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED(baseSpellID, overrideSpellID?)`,
`COOLDOWN_VIEWER_TABLE_HOTFIXED`. `GetGroupBuffItems` was removed in 12.1.0.

The Cooldown Manager's own frames (Essential, Utility, Tracked Buffs, Tracked Bars viewers) are Blizzard
frames that track buffs internally, without addon aura access. The most robust approach for SoulUI is to
**skin and position Blizzard's viewers** (hook item frame creation, restyle icons, borders and fonts) and use
`GetCooldownViewerCategorySet` for configuration UIs. Building our own tracked-buff bars would need aura access
we no longer have in combat.

---

## 9. Secure frames, combat lockdown, Edit Mode, Settings

### 9.1 Still applies (unchanged since before 12.0)

- `InCombatLockdown()`: while true, you cannot `Show`/`Hide`/`SetPoint`/`SetSize`/`SetAttribute`/`SetParent`
  protected frames, `RegisterStateDriver`, or create secure frames. Queue the change and run it on
  `PLAYER_REGEN_ENABLED`. SoulUI does this with `SoulUI:RunAfterCombat(fn)`.
- Unit frames: `CreateFrame("Button", name, parent, "SecureUnitButtonTemplate")`, then
  `SetAttribute("unit", "target")`, `SetAttribute("*type1", "target")`, `SetAttribute("*type2", "togglemenu")`,
  and `RegisterUnitWatch(frame)` for automatic show and hide.
- Group frames: `SecureGroupHeaderTemplate` (and `SecureGroupPetHeaderTemplate`) with attributes `showParty`,
  `showRaid`, `showPlayer`, `groupBy`, `groupingOrder`, `maxColumns`, `unitsPerColumn`, `point`,
  `columnAnchorPoint`, and `initialConfigFunction`/`oUF-initialConfigFunction`. Since 12.1.0 this is also
  Blizzard's suggested place to create one aura container per unit button.
- Visibility: `RegisterStateDriver(frame, "visibility", "[combat] show; hide")`, and `RegisterAttributeDriver`.
- **Removed:** `SecureAuraHeaderTemplate` (Mainline 12.1.0) and `SecureAuraHeader_*` FrameXML helpers.
- 12.0.1: `SetAttribute`/`GetAttribute` gained an **Attributes** secret aspect. Don't feed secrets into attributes.
- 12.1.0: `SetScript`/`HookScript` now refuse secret arguments, and objects with `UntrustedScriptExecution`
  ignore addon scripts.
- 12.1.0: `CreateFrame` can no longer create `WorldFrame` instances. `CreateSecureDelegate` gained `options`.

### 9.2 Edit Mode integration

- Blizzard's Edit Mode has no public API for registering addon frames. Use **LibEditMode** (p3lim), which
  avoids taint by limiting method reuse. v15 was released 2026-02-10.
  Repo: https://github.com/p3lim-wow/LibEditMode/wiki

```lua
local LEM = LibStub("LibEditMode")
LEM:AddFrame(frame, function(frame, layoutName, point, x, y) --[[save per layout]] end,
             { point = "CENTER", x = 0, y = 0 })
LEM:AddFrameSettings(frame, {
    { name = "Scale", kind = LEM.SettingType.Slider, default = 1, minValue = 0.5, maxValue = 2, valueStep = 0.05,
      get = function(layout) return db[layout].scale end,
      set = function(layout, v) db[layout].scale = v; frame:SetScale(v) end },
})
LEM:RegisterCallback("enter",  function() --[[show movers]] end)
LEM:RegisterCallback("exit",   function() --[[hide movers]] end)
LEM:RegisterCallback("layout", function(layoutName) --[[apply saved positions]] end)
```

- SoulUI has its own `/soul move` unlock mode. Recommendation: keep ours as the primary mover, and optionally
  also register the frames with LibEditMode so they appear in Blizzard's Edit Mode. Store positions **per Edit
  Mode layout** if we do that.
- 12.1.5 `CustomAuraContainer:SetEditModePreviewEnabled(bool)` shows sample auras while Blizzard Edit Mode is active.
- `C_EncounterTimeline.AddEditModeEvents()` gives fake timers for preview.

### 9.3 Settings API (Interface Options)

Unchanged since 10.0. Register a canvas category that opens our own editor:

```lua
local panel = CreateFrame("Frame")
local category = Settings.RegisterCanvasLayoutCategory(panel, "SoulUI")
Settings.RegisterAddOnCategory(category)
-- open:  Settings.OpenToCategory(category:GetID())
```

Or use vertical layouts (`Settings.RegisterVerticalLayoutCategory`, `Settings.RegisterAddOnSetting`,
`Settings.CreateCheckbox`, `Settings.CreateSlider`). The Addon Compartment (`AddonCompartmentFunc` in the TOC)
is still supported.

### 9.4 Other framework-level changes worth knowing

- **12.1.0 `Frame:SetOnUpdateMode(mode)`**: `Disabled`, `RunWhenVisible` (default), `RunWhenVisibleOnce`,
  `RunOnce`, `RunAlways`.
- **12.1.0** `[Bootstrap]` per-file TOC directive, `<Mixins>` XML element, `KeyValue type="local"`, SVG textures
  (`VectorGraphics`), and `Frame:ResizeToBoundsRect()`. `UIParentLoadAddOn`, `MouseIsOver`, `getglobal`,
  `setglobal` and `CanAccessObject` were removed. Use `C_AddOns.LoadAddOn` and `InputUtil.IsMouseOver`.
- **12.0.7**: TOC files skip **all** directives if the first line starts with `#` followed by a comment. Start
  `.toc` files with `## Interface: 120105`. Font setters now require a valid font file and height, otherwise
  they fail.
- **12.0.0**: functions deprecated during 11.x were removed (`GetSpellInfo`, `GetSpellCooldown`,
  `GetAddOnMetadata`, ...). Use the `C_Spell`, `C_AddOns` and similar namespaces.

---

## 10. Testing restricted paths

CVars (not saved across restarts) that force restrictions so you can test out of combat:

```
/console addonCombatRestrictionsForced 1
/console addonEncounterRestrictionsForced 1
/console addonChallengeModeRestrictionsForced 1
/console addonPvPMatchRestrictionsForced 1
/console addonMapRestrictionsForced 1
/console addonChatRestrictionsForced 1
```

12.0.5 also lists `secret*RestrictionsForced` variants with different descriptions. Try both. Use
`/dump issecretvalue(UnitHealth("player"))` and `/dump C_Secrets.HasSecretRestrictions()` to confirm.
Source: https://warcraft.wiki.gg/wiki/Secret_values

---

## 11. 12.1 and 12.1.5 specific changes versus 12.0

### 12.1.0 (2026-08)

- Aura lockdown plus `AuraContainer`/`CustomAuraButton`/`ManagedAuraContainer` (section 3). The never-secret
  list was trimmed of healer HoTs.
- Forbidden aspects and private script objects (forbidden partition).
- More unit identity APIs return secrets. `UnitName` is **not** secret during an active PvP match.
- Radial progress, `StatusBar:SetRenderMode`, `Frame:SetOnUpdateMode`, VectorGraphics/SVG, `[Bootstrap]`,
  `<Mixins>`, and the Roleset system (`C_Roleset.*`, `Frame:IsRolesetFiltered`).
- `DurationTextBinding` gained color curves. `SecondsFormatter:SetRounding`.
- Removed: `SecureAuraHeaderTemplate` (Mainline), `settablesecurity`, `securecopy`, `SetTableSecurityOption`,
  `GetInspectSpecialization` (as a global), `GetWeaponEnchantInfo`, `CancelItemTempEnchantment`,
  `C_CooldownViewer.GetGroupBuffItems`, and `UIParentLoadAddOn`/`MouseIsOver`/`getglobal`/`setglobal`.
- `SPELL_UPDATE_COOLDOWN` gained `itemID`. `C_Spell.GetSpellTexture` gained `conditionalIconID`.
- `tooltipShowAuraSpellIDs` CVar.

### 12.1.5 (current, build 70783 locally)

Source: https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes/notes

- **Native Lua helpers** (old names kept as aliases): `math.clamp`, `math.saturate`, `math.round`, `math.lerp`,
  `math.normalize`, `math.sign`, `math.remap`, `math.wrap`, `math.isfinite`, `math.isnan`, `math.isinf`;
  `string.contains`, `string.ltrim`, `string.rtrim`, `string.startswith`, `string.endswith`;
  `table.isempty`, `table.contains`, `table.indexof`, `table.removeunordered`, `table.removevalue`,
  `table.keys`, `table.values`. These are faster than our own Lua versions, so prefer them. **None of them make
  secret math legal**: `math.clamp(secret, ...)` still compares.
- `Region:SetRoundLayoutToNearestPixel(bool)` and the XML attribute `roundLayoutToNearestPixel` are a native
  pixel-perfect replacement for `PixelUtil`. Use them on all SoulUI regions for crisp 1px borders.
- `CreateFrameWithOptions{ frameType=, name=, parent=, inherits={...}, id=, hidden=true }`.
- `TimedSignalMap` script object and `TimerUtil.CreateTimedSignalCallbackMap`: one callback fired with
  user-defined keys at scheduled times, and keys can be rescheduled. Ideal for many expiring timers without
  `C_Timer` churn.
- Aura buttons: pandemic animations, `SetCasterName`, shown/assigned animations. Containers: enable toggles and
  Edit Mode preview. The `tooltipShowAuraCasterNames` CVar.
- Security: `Cooldown:SetCooldown`/`Clear` blocked from tainted code on **protected** cooldown frames. Cast-bar
  IDs are unique per token string. Damage meter `sourceGUID` is secret when identity is secret.
  `GetArenaOpponentSpec` returns secrets.
- New `UnitFrameUtil` library: `UpdateUnitPvPIndicator`, `GetUnitRoleIconDisplayInfo`,
  `UpdateUnitFrameRoleIcon` (handles vehicle and main tank/assist), and arena spec display helpers. All take an
  optional `textureMap` so you can use your own icons. **Use these for role and PvP icons**, because they work
  with secret roles.
- `C_ClassColor.GetClassColor(class [, tint])`. `GetPlayerInfoByGUID` returns the level when known.
- New namespaces: `C_Intl` (Unicode: `Transliterate`, `FindStringMatches`, `FindBreaks`, `GetSortKey`, which
  accept secret strings) and `C_Weather`.
- Nameplate CVars `nameplateMotionSpeed`, `nameplateBottomInset` and `nameplateTopInset` restored. Extra frame
  for the enemy hitbox after a late classification change.
- New forbidden aspects: `SetTexture`, `QueryRotation`, `QueryAnimationProgress`, `AddAnimations`.
- Removed ten `Blizzard_Deprecated*` addons (CurrencyScript, Glue, ItemScript, ItemSocketInfo, LFG, PetInfo,
  PvpScript, SoundScript, TradeInfo, WorldElapsedTimerTypes). Any old global alias they supplied is gone.
- Fixed: `EnumerateFrames` performance, duration objects for long auras, and `tostring`/`dumpobject` crashing
  on secret objects.

---

## 12. Performance best practices for high-frequency UI updates

1. **Let the engine animate.** `SetValue(v, ExponentialEaseOut)` for smoothing, `SetTimerDuration` for cast and
   timer bars, `SetCooldownFromDurationObject` for swipes, and `DurationTextBinding:SetUpdateInterval()` for
   countdown text. These replace almost every Lua `OnUpdate` in a 12.x UI.
2. **`RegisterUnitEvent`** instead of `RegisterEvent` for `UNIT_*` (filtering happens in C). Use
   `UNIT_HEALTH` (there is no `UNIT_HEALTH_FREQUENT`) and `UNIT_POWER_FREQUENT` only for the player's primary resource.
3. **Build curves, color curves, formatters, AbbreviateConfig and heal calculators once**, at load, never per
   event. Reuse one calculator per frame.
4. **No per-event tables.** Don't capture `{...}` and don't build closures in handlers. Upvalue globals
   (`local UnitHealth = UnitHealth`) in hot files.
5. **Coalesce bursts.** Many `UNIT_*` events can fire in one frame (an AoE heal on 20 raid frames). Set a dirty
   flag and flush once per frame with a single driver frame using `SetOnUpdateMode("RunOnce")` (12.1.0), which
   re-arms on demand, or `C_Timer.After(0, flush)` guarded by a pending flag. **[inferred]** Check that
   `RunOnce` re-runs after `SetOnUpdateMode` is set again.
6. **One central ticker** for anything that must poll (range is event-free in 12.x only through
   `UNIT_IN_RANGE_UPDATE`; prefer that event over polling). Throttle to 0.1-0.2 s.
7. **Pool frames** (`CreateFramePool`, `CreateObjectPool`). Nameplates come and go constantly, so attach on
   `NAME_PLATE_UNIT_ADDED` and release on `_REMOVED`. Never create frames per plate per show.
8. **`TimedSignalMap`** (12.1.5) for many independent expirations, such as debuff fades or timeline highlights.
9. **Avoid secret anchoring cascades.** Don't anchor big layout trees to regions whose geometry became secret.
   Layout reads (`GetWidth`) on them return secrets and force fallbacks.
10. **Pixel rounding natively** via `SetRoundLayoutToNearestPixel(true)` rather than recomputing `PixelUtil`
    sizes on every scale change.
11. **Profile** with `GetScriptCPUUsage()` (12.0.7; per-function and per-event CPU getters were removed) and
    `/console scriptProfile 1` in a test session only, because profiling costs CPU.
12. Don't hook Blizzard functions that run every frame. Prefer `hooksecurefunc` on rare setup calls and
    `EventRegistry` callbacks.

---

## 13. Recommendations for SoulUI

1. **Core "secret-safe" helper module** (`SoulUI/Core/Secret.lua`):
   - `S.IsSecret(v)` wraps `issecretvalue`.
   - `S.Num(v, fallback)` returns `v` if readable, else `fallback`. Use it only for non-critical logic such as
     "hide text when 0".
   - Shared curve objects built once: `S.Curves.HealthGradient`, `S.Curves.Percent100`, `S.Curves.Execute20`,
     plus per-power-type color curves.
   - Shared formatters: one `AbbreviateConfig`, one `SecondsFormatter`, one abbreviated-number formatter.
   - Correct the "no `tostring`" hard rule in CLAUDE.md to: **`string.format`, `..` and `AbbreviateNumbers` are
     allowed on secrets. `tostring`, arithmetic, comparisons, `#` and table keys are not.**
2. **Unit frames:** one `UnitHealPredictionCalculator` per frame. Health, absorbs and heal absorbs from the
   calculator, with native interpolation. Color via color curves. Range via `SetAlphaFromBoolean(UnitInRange)`.
   Role and PvP icons via `UnitFrameUtil`. Class color via `C_ClassColor.GetClassColor` when `UnitClass` is
   secret. Text via `SetFormattedText` + `AbbreviateNumbers`/percent curve.
3. **Group frames:** `SecureGroupHeaderTemplate` headers created at load. Create one `AuraContainer` per button
   in the initial config (never in combat). Use `AddAuraSlot` with `includeSpellIDs` for corner HoT indicators,
   and `AddAuraGroup("HARMFUL|RAID_PLAYER_DISPELLABLE")` for dispellables. Private auras then show
   automatically.
4. **Auras everywhere = containers.** Drop any plan for a Lua aura iterator in combat. The only Lua-side aura
   reads are `GetPlayerAuraBySpellID` for never-secret buffs.
5. **Cast bars:** Duration objects plus `SetTimerDuration`, a `DurationTextBinding` for the time,
   `SetAlphaFromBoolean(notInterruptible)` for the shield, and `EvaluateColorFromBoolean` for the bar color.
   Never compare `castID`. Store `castBarID` (NeverSecret) for matching where useful.
6. **Nameplates (SoulUI_Nameplates):** own-frame approach for enemy plates (parent to the plate, hide Blizzard's
   `UnitFrame`), skip forbidden plates, set size and hit-test insets out of combat from the profile, and key
   state by plate frame, not GUID. Offer CVar toggles (friendly plates, motion, insets) in `/soul`, applied
   out of combat. Accept that friendly plates in instances are Blizzard-only.
7. **Damage meter module:** a thin skin over `C_DamageMeter`. Rows in server order. Values only via
   `SetValue`/`SetText`. Rich breakdown out of combat only. No sync.
8. **Cooldowns/CDM:** skin Blizzard's Cooldown Manager viewers and use `C_Spell.GetSpellCooldownDuration` +
   `SetCooldownFromDurationObject` for any of our own action-bar style icons. Use only our own (unprotected)
   Cooldown frames.
9. **Boss mods:** restyle Blizzard's encounter timeline and warnings. Optionally render the timeline ourselves
   from `GetSortedEventList` + `GetEventTimer`. Don't build a DBM-style timer engine.
10. **Movers:** keep `/soul move`. Optionally add LibEditMode registration as a later "Blizzard Edit Mode"
    compatibility feature.
11. **Pixel perfect:** call `SetRoundLayoutToNearestPixel(true)` on all regions (12.1.5 native).
12. **Dev workflow:** add `/soul secret` (toggle `addonCombatRestrictionsForced` and
    `addonEncounterRestrictionsForced`) so restricted code paths can be tested at a target dummy without a group.
13. **TOC hygiene:** first line `## Interface: 120105`. No leading `#` comment line (12.0.7 bug).
14. Use the 12.1.5 native `math`/`string`/`table` helpers instead of shipping our own utility copies.

---

## 14. Uncertain points to verify in game (12.1.5, build 70783)

1. **Error message text** for arithmetic or comparison on secrets. Record the exact BugSack output in BUILD_LOG.
2. **`SetAlphaFromBoolean` alpha scale**: the wiki says the default `alphaIfTrue` is 255, while oUF passes `1, 0`.
   Check whether values are 0-1 or 0-255 (`/run f:SetAlphaFromBoolean(true, 0.5, 0); print(f:GetAlpha())`).
3. Exact argument order of **`SetVertexColorFromBoolean`** (two ColorMixins? r,g,b,a pairs?).
4. **`Enum.LuaCurveType`** full list, and step-curve boundary semantics.
5. Whether **`UnitHealthMax`** for party/raid members is readable in M+ and raid encounters (expected: yes,
   player-controlled).
6. Whether **`C_DamageMeter` `combatSources`** arrive sorted by amount, and how often `DAMAGE_METER_COMBAT_SESSION_UPDATED`
   fires (throttle needed?).
7. Whether **`StatusBar:SetTimerDuration` / `Cooldown:SetCooldownFromDurationObject`** accept DurationObjects
   built from secret data in tainted code (oUF does it, but the docs say `AllowedWhenUntainted`).
8. Whether **`Texture:SetTexture(secretFileID)`** works for cast icons of restricted units.
9. Exact **`candidateFilters` table shape** (`includeSpellIDs = {[id]=true}` vs `{id, id}`) and the
   `AuraContainerSortMethod` / `AuraContainerSortDirection` / `CustomAuraContainerAuraProcessingPolicy` enums
   (`/dump` them).
10. **Flow layout setter enums** for `SetFlowLayoutAxis` / `SetFlowLayoutGrowthDirection`.
11. Whether **`NamePlate:SetHitTestPoints`** is callable by addons at all (docs: `AllowedWhenUntainted` +
    `RequiresCanChangeHitTestPoints`). Test with `plate:CanChangeHitTestPoints()`.
12. **`Enum.NamePlateType`** values for `SetNamePlateHitTestInsets`, and whether `SetNamePlateSize` errors in combat.
13. Friendly nameplate behavior in instances: confirm plates are forbidden, and whether `nameplateShowFriends`
    plus name-only CVars still work.
14. Which **`addon*RestrictionsForced` vs `secret*RestrictionsForced`** CVars actually exist in 12.1.5.
15. **`UnitThreatSituation`** secrecy in the open world vs dungeons. Can threat color be computed out of instances?
16. **`SetOnUpdateMode("RunOnce")`** re-arming semantics for a coalescing flush driver.
17. The 12.1.0 changes page lists `C_UnitAuras.AddAuraSound`, `CancelAuraByInstanceID` etc. as "removed", yet
    the 12.1.5 generated docs still contain them. Confirm with `/dump C_UnitAuras.CancelAuraByInstanceID`.
18. `canaccesssecrets`, `scrubsecretvalues`, `secretwrap` and `dropsecretaccess` semantics are undocumented, so
    don't rely on them.
19. Whether `UnitInRange` secrecy also applies out of instances, and whether `UNIT_IN_RANGE_UPDATE` still fires
    for party/raid.
20. `C_StringUtil.CreateAbbreviatedNumberFormatter()` object methods (`Format`?) and whether it beats
    `AbbreviateNumbers` + config in a hot path.
