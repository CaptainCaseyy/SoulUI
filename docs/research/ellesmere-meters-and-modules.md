# EllesmereUI study: Damage Meters, Action Bars and the remaining modules

Study date: 2026-11-04. Source: the installed EllesmereUI suite, version 9.7
(`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\EllesmereUI*`), every
`.toc` targeting `120000, 120001, 120005, 120007, 120100, 120105, 16001` (16001 = the "WoW
Forever" classic-style client, which they ship from the same files).

**Licence reminder.** EllesmereUI is "all rights reserved". This document describes *designs,
API usage and data flow* in our own words. File:line references point at the original so a
future reader can re-check a claim. They are not an invitation to copy. Snippets are kept under
10 lines and are paraphrased pseudo-code unless noted.

Paths below are relative to `Interface\AddOns\`.

---

## 0. Suite-wide patterns (seen in every module)

These recur everywhere, so they are described once here.

1. **Split files plus an internals table.** Each module has a root file that builds
   `ns._internals` (or `ns._dmInternals`, `ns._bagsInternals` and so on). Every later file does
   `local I = ns._internals; if not I or I.broken then return end; I.broken = true` at the top and
   sets `I.broken = false` at the bottom. A load error in file N silently disables files N+1 and
   later instead of cascading Lua errors. Shared mutable state is distributed through "setter
   lists": `I.inCombatSetters[#I.inCombatSetters+1] = function(v) _inCombat = v end`, so each file
   keeps a fast local upvalue copy. They split files partly because of **Lua 5.1's 60-upvalue
   limit** (comments say `CreateDMWindow sits at Lua 5.1's 60-upvalue cap`; see
   `EllesmereUIDamageMeters/EUI_DamageMeters_Format.lua:191`).
2. **Client gate.** Line 1 of every file: `if EUI_CLIENT_BLOCKED then return end`. The parent sets
   it when the client is older than 12.1 or the parent and child versions disagree.
3. **Combat queue.** `EllesmereUI.NewCombatQueue(frame)` returns an object with
   `Defer(key, fn)`. Keyed, so repeated requests collapse to one run after
   `PLAYER_REGEN_ENABLED` (for example `ns.CombatQueue.Defer("UpdateKeybinds", UpdateKeybinds)`,
   `EllesmereUIActionBars/EUI_ActionBars_Keybinds.lua:61`).
4. **Side tables, never fields on Blizzard frames.** `EFD(btn)` / `CFD(cf)` are weak-keyed lookup
   tables ("External weak-keyed lookup table for frame state (prevents tainting Blizzard
   frames)", repeated in BlizzardSkin, Friends and others). Writing `frame.myField = x` on a
   Blizzard frame from addon code taints that frame's table.
5. **CPU attribution shells.** `ns.TakeShell()` hands out frames created in the module's main chunk
   so the engine's per-addon CPU profiler bills event handlers to the right addon
   (`EllesmereUIActionBars/EllesmereUIActionBars.lua:8-13`).
6. **Zero cost when off.** Almost every optional feature says "no events registered, no frames
   built until enabled". Tickers exist only while there is a listener (DataBars heartbeat,
   `EllesmereUIDataBars/EllesmereUIDataBars.lua:483-501`).
7. **Secret discipline vocabulary.** The phrases recur: "type() existence checks", "duration
   objects into SetTimerDuration", "boolean colour curves via C_CurveUtil", "SetAlphaFromBoolean
   for secret-gated visibility", "never compared, concatenated or keyed". A secret value is
   allowed to reach a *sink* (StatusBar:SetValue, SetMinMaxValues, FontString:SetText,
   SetFormattedText, AbbreviateNumbers, Texture:SetDesaturation, Cooldown:SetCooldownFromDurationObject)
   but never Lua arithmetic, `==`, `<`, `..`, `tostring`, a table key or a truthiness test.
8. **Stock-style variants.** Most modules offer "EllesmereUI", "Blizzard Style" and "Classic WoW
   UI" looks plus the WoW Forever variant. This is a large share of their code and something
   SoulUI can skip.

---

## 1. EllesmereUIDamageMeters (TOP PRIORITY)

### 1.1 Purpose and file map

"Lightweight damage meters with simple but powerful customization" (toc Notes). A full
replacement for Blizzard's built-in 12.x meter UI, but it **does not collect any combat data
itself**. All numbers come from Blizzard's server-side meter through `C_DamageMeter`. The root
comment says it plainly: "Custom damage meter frame using C_DamageMeter API. Multi-window support
(up to 5). Zero Blizzard frame hooks." (`EllesmereUIDamageMeters.lua:3-5`).

Load order (toc): root, `_Style`, `_State`, `_Format`, `_Appearance`, `_SeasonMobs`,
`_SeasonRaids`, `_Tooltip`, `_Window` (2993 lines, the bulk), `_Apply`, `_Timer`, `_Lifecycle`,
`_SpellHistory`, `_ForeverThreat`. SavedVariables: `EllesmereUIDamageMetersDB`. About 9.7k lines.

| File | Role |
|---|---|
| `EllesmereUIDamageMeters.lua` | constants, type/session name tables, DB defaults, internals |
| `EUI_DamageMeters_State.lua` | combat-state flags, segment selection, Current-duration logic, `C_DamageMeter` and M+ events |
| `EUI_DamageMeters_Format.lua` | number/name/timer formatting, row metrics, class icons, secret helpers, the ally GUID resolver, target aggregation |
| `EUI_DamageMeters_Window.lua` | window factory: header, menus, row pool, scroll, pinned self row, `Refresh`/`RefreshUI`, breakdown view |
| `EUI_DamageMeters_Tooltip.lua` | hover breakdown tooltip (spells, death recap, enemy attackers, top targets) |
| `EUI_DamageMeters_Lifecycle.lua` | shared refresh ticker, combat start/stop detection, PvP end, login and window build, keybind buttons |
| `EUI_DamageMeters_Timer.lua` | standalone combat timer, keybinds (reset / toggle) |
| `EUI_DamageMeters_Appearance.lua` | row decorations, value gradient |
| `EUI_DamageMeters_SeasonMobs/Raids.lua` | this season's NPC IDs per map, so the enemy tooltip works mid-fight |
| `EllesmereUIDamageMeters_SpellHistory.lua` | separate feature: your own recent casts as an icon strip or bar window |
| `EllesmereUIDamageMeters_ForeverThreat.lua` | Forever-only "Threat" meter type fed by another addon |

### 1.2 Feature list (parity checklist)

- Up to **5 windows** (`MAX_WINDOWS = 5`, root:28), each with its own meter type, segment, size,
  position, lock and visibility rules. Windows are created one per frame after login
  (`C_Timer.After(0, CreateNextWindow)`, Lifecycle:475-495) to avoid a login hitch.
- **8 meter types** (root:30-39): Damage Done, Healing Done, Damage Taken, Avoidable Damage Taken,
  Enemy Damage Taken, Interrupts, Dispels, Deaths. A "home" screen of type tiles
  (`HOME_DEFAULTS` = damage, healing, interrupts, deaths).
- **Segments:** Current, Overall, plus the last 20 historical sessions from
  `GetAvailableCombatSessions` with name and duration (Window:857-889). Per-window options:
  "auto Current on combat start" (State:413-424), "auto swap Overall on key complete / Current on
  key start" (`autoSwapMythic`), "default meter type on M+ start" (`mythicStartDMType`),
  `syncSegments` across windows.
- **Auto reset on keystone start:** `CHALLENGE_MODE_START` calls `ResetAllCombatSessions()` so
  Overall equals this dungeon run (State:528-531).
- **Reset button and reset keybind**, **show/hide-all keybind** (hidden buttons driven by
  `SetOverrideBindingClick`, Lifecycle:417-437, Timer:430-438).
- **Bars:** rank number, spec or class icon (sprite sheet or spec icon, zoomable, optional border),
  name (realm stripped, optional name format), value text, class-coloured or accent or custom
  fill, fill alpha, bar texture (LibSharedMedia plus "thin line top/bottom" styles), bar
  background (optional class colour), separators, "player marker".
- **Value formats** (`numberFormat`): 0 = per-second only, 1 = total only, 2 = `total (perSec)`
  (default), 3 = `total | perSec` (Format:218-233). Optional **force English K/M/B** instead of
  CJK 万/億.
- **Pinned self row:** if your row scrolls out of view it sticks to the top or bottom edge
  (`W.UpdateSticky`, Window:1563-1719).
- **Right-text value gradient:** green (top) to red (bottom) colour by value range or rank
  (Appearance:49-90).
- **Click a row:** opens a full breakdown view in the window (spell list with icons, amounts and
  percent; Deaths opens the death recap; Enemy Damage Taken opens per-player attackers).
  Right-click goes back (Window:455-500).
- **Hover tooltip** breakdown (configurable scale and anchor), plus a top-3 "Targets" section for
  Damage Done out of combat (Tooltip:708-760).
- **Header:** title "Overall Damage Done" etc., combat timer `(m:ss)`, buttons for mode, segment,
  settings, reset; hover-only icons option; header colours, height, font.
- **Standalone combat timer** (optional tenths, accent colour, desaturate out of combat), its own
  mover.
- **Refresh rate** slider (default 1 s; floor 0.5 s, "unsafe" floor 0.2 s; root:18-22).
- **Visibility:** always / in combat / in group / mouseover plus per-window "hide in dungeon /
  raid / delve / PvP / out of instance" (Window:2733-2766).
- **Styles:** EllesmereUI, Blizzard Style (stock atlases), Classic WoW UI.
- **Spell History** (separate toggle): your casts with failed and interrupted markers.
- **Blizzard meter disabled** automatically (CVar).
- Window snapping and resizing, unlock-mode registration, profile swap without reload
  (`_G._EDM_Apply`, Lifecycle:500-540).

There is **no report-to-chat feature** (no `SendChatMessage` in the module).

### 1.3 Where the data comes from: every API

All data is server-computed. The addon never adds damage events (it cannot; there is no combat
log in 12.x). Everything in this table is called with `C_DamageMeter.` unless noted.

| API | Use | Where |
|---|---|---|
| `GetCombatSessionFromType(sessionType, meterType)` | **main fetch** for Current/Overall: returns `session` with `session.combatSources` (array) | Window:2045-2047 |
| `GetCombatSessionFromID(sessionID, meterType)` | same, for a historical segment (pcall-wrapped, ID may be stale) | Window:2042-2044 |
| `GetCombatSessionSourceFromType(sessionType, meterType, sourceGUID, sourceCreatureID)` | one source's breakdown: `srcData.combatSpells` | Tooltip:587-589, Window:2259 |
| `GetCombatSessionSourceFromID(sessionID, meterType, guid, creatureID)` | same for a historical segment | Tooltip:585-586 |
| `GetAvailableCombatSessions()` | list of `{sessionID, name, durationSeconds}` for the segment menu and historical durations | Window:861, 1994-1996 |
| `GetSessionDurationSeconds(sessionType)` | Current/Overall duration; **one argument only** (no meter type) | State:431-456, Window:2004 |
| `ResetAllCombatSessions()` | reset button, keybind, key start | Window:1021, Lifecycle:422, State:529 |
| `IsDamageMeterAvailable()` | used by Mythic Timer's run summary before harvesting | MythicTimer RunSummary:130-141 |
| `C_DeathRecap.GetRecapEvents(recapID)` / `GetRecapMaxHealth(recapID)` | Deaths breakdown | Tooltip:476-495, Window:2072-2079 |
| `C_Spell.GetSpellTexture(id)` / `GetSpellName(id)` | spell icons and names in breakdowns (they accept secret IDs) | Tooltip:657-699 |
| `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Combat)` | "is data still classified?" probe | Format:317-321 |
| CVar `damageMeterEnabled = 0` | turn off Blizzard's meter UI ("C_DamageMeter API still works") | Lifecycle:456-457 |

Enums: `Enum.DamageMeterType.{DamageDone, HealingDone, DamageTaken, AvoidableDamageTaken,
EnemyDamageTaken, Interrupts, Dispels, Deaths}` and `Enum.DamageMeterSessionType.{Current,
Overall}`.

**Fields read on a `combatSources[i]` row:**

- `name`: secret in combat (for group members and enemies).
- `sourceGUID`: secret in combat.
- `sourceCreatureID`: NPCs only; secret in combat.
- `classFilename`, `specIconID`: documented **NeverSecret** ("classFilename + specIconID are
  NeverSecret", Format:287-288). These are what keep icons and class colours working mid-fight.
- `isLocalPlayer`: NeverSecret (Format:271-278). They still guard it defensively.
- `totalAmount`: secret in combat.
- `amountPerSecond`: secret in combat. **The server computes DPS/HPS**; the addon never divides
  for the main bars.
- `deathRecapID`, `deathTimeSeconds`: Deaths type; can be secret.

**Fields on `srcData.combatSpells[i]`:** `spellID` (secret in combat), `totalAmount`,
`creatureName`, `combatSpellDetails.unitName` (used for Enemy Damage Taken: which player hit this
enemy).

Session list rows: `sessionID`, `name` (can be secret or empty, fallback "Combat"),
`durationSeconds`.

**Events** (State:521-526, Lifecycle:209-220):

| Event | Handling |
|---|---|
| `DAMAGE_METER_COMBAT_SESSION_UPDATED` | a session was created or updated (boss kill, combat end). Debounced 0.1 s; drops data caches only (never style caches). Out of combat: refresh all windows. In combat: only revive the ticker if it died. |
| `DAMAGE_METER_CURRENT_SESSION_UPDATED` | "Current just rolled" (chain pull into a boss). Fires often in combat, so in combat it only drops caches; out of combat one debounced 0.1 s refresh. |
| `DAMAGE_METER_RESET` | clear frozen timer, target cache, force full repaint. |
| `PLAYER_REGEN_DISABLED` / `_ENABLED` | combat start/end (with group logic, see 1.5) |
| `ENCOUNTER_START` / `_END` | hard segment boundary; on kill, end combat promptly instead of waiting for regen |
| `UNIT_FLAGS` (party/raid units) | a group member entered combat before you: start polling |
| `GROUP_ROSTER_UPDATE`, `PLAYER_SPECIALIZATION_CHANGED` | rebuild the class:spec to GUID map |
| `ADDON_RESTRICTION_STATE_CHANGED` | the exact moment combat data is declassified |
| `UNIT_SPELLCAST_SUCCEEDED` | Feign Death (spell 5384) detection only |
| `CHALLENGE_MODE_START` / `_COMPLETED` | auto reset and segment swaps |
| `PVP_MATCH_COMPLETE` / `PVP_MATCH_STATE_CHANGED` / `ZONE_CHANGED_NEW_AREA` | force-end the segment when a match ends (arenas do not reliably fire regen) |
| `PLAYER_ENTERING_WORLD` | re-derive combat state after a loading screen |

### 1.4 Data flow and update cadence

```
login -> CVar damageMeterEnabled=0 -> build windows one per frame
combat start (REGEN_DISABLED / ENCOUNTER_START / teammate UNIT_FLAGS)
   -> StartSharedTicker(): C_Timer.NewTicker(refreshRate, SharedRefreshTick)
                           C_Timer.NewTicker(0.5, TimerTick)   -- header clocks
SharedRefreshTick -> for each window: W.Refresh()
   W.Refresh: if hidden -> mark _refreshPending, return
              session = C_DamageMeter.GetCombatSessionFrom{Type|ID}(...)
              if the C call took > PEAK_BUDGET (1.5 ms) -> RefreshUI next frame
              else RefreshUI(session)
combat end (group fully out) -> FreezeCombat (pin duration) -> final Refresh -> stop ticker
out of combat: only events (SESSION_UPDATED etc.) and user actions refresh
```

Key points:

- **One shared ticker for all windows** (Lifecycle:64-180), not one per window. Default rate
  `TICK_COMBAT = 1` second; user range 0.5 s and up, 0.2 s with the "unsafe" toggle
  (root:18-21, Lifecycle:164-171). The rate is clamped again when the ticker starts, in case an
  imported profile carries 0.
- **Ticker runs only in combat** and only while something is on screen
  (`AnyTickViewer`, Lifecycle:93-106). A hidden window's refresh just sets `_refreshPending`; its
  `OnShow` does one catch-up refresh (Window:2022-2033).
- **Separate 0.5 s clock ticker** updates only the header timer text, memoised on the displayed
  whole second, so the clock ticks smoothly even at a slow meter refresh rate
  (Lifecycle:72-82, Window:1980-2018).
- **API spike guard:** `debugprofilestop()` around the session fetch; if it exceeded
  `PEAK_BUDGET = 1.5` ms the paint is deferred one frame so the two costs do not land in the same
  frame (Window:2040-2057).
- **Out of combat** nothing polls. Session events with a 0.1 s debounce cover rolls and resets.
- **After combat ends**, a refresh 0.5 s later picks up declassified data ("API needs a moment to
  declassify secret source GUIDs", Lifecycle:367-375).

### 1.5 Combat segment logic (the subtle part)

They track combat *for the group*, not just the player, because the server meter keeps counting
while teammates fight.

- `IsGroupInCombat()` loops `UnitAffectingCombat` over `player`, `raidN`/`partyN` using
  pre-built unit token arrays (State:461-480).
- **Player dies or leaves combat while the group fights:** `PLAYER_REGEN_ENABLED` sets
  `_needsFinalRefresh = true` and keeps the ticker running. Each tick checks
  `IsGroupInCombat()`; when the group is done (or 5 s failsafe after the player's regen, for
  lingering HoTs), it freezes and stops (Lifecycle:108-131, 348-366).
- **Teammate pulls first:** `UNIT_FLAGS` on a party/raid unit inside an instance, while not in
  combat and no ticker: if the group is in combat, start polling (Lifecycle:265-284). Gated hard
  because `UNIT_FLAGS` is frequent.
- **`ENCOUNTER_START`** is a hard boundary even during chain pulls where regen never toggles: bump
  a generation counter, wipe feign and death caches, set in-combat, refresh all windows
  (Lifecycle:285-306).
- **`ENCOUNTER_END`:** after 0.5 s (let Blizzard finalise), on a kill freeze immediately; on a
  wipe with people still fighting, keep polling (Lifecycle:307-332).
- **Generation counter `_combatGen`** guards every delayed stop so a stop scheduled at the end of
  pack 1 cannot cancel the ticker of pack 2 pulled 0.4 s later (Lifecycle:197-206).
- **Feign Death filter** for the Deaths type: `UNIT_SPELLCAST_SUCCEEDED` with spellID 5384 records
  the hunter's GUID; rows for that GUID are skipped until `UnitHealth` reads 0 (State:482-509,
  Window:1746-1764). The spellID can itself be secret, so it is checked with `issecretvalue`
  before comparing (Lifecycle:226-228).
- **PvP:** watch `C_PvP.IsMatchActive()` edges; 1.5 s after the match ends, force-freeze and
  block new segments for 20 s of post-match "combat" (Lifecycle:380-415).
- **After a loading screen:** `PLAYER_ENTERING_WORLD` re-derives in-combat / group-in-combat /
  force-end (State:614-646).

**Combat timer source of truth:** `GetCurrentViewDuration()` (State:426-447) reads
`GetSessionDurationSeconds(Current)` live while in combat, so the clock automatically resets when
the server rolls Current (chain pull into a boss) with no local clock to drift. At combat end
`FreezeCombat()` pins the last value (only if it is not smaller, in case Current already rolled
to an empty session). Out of combat the pinned value is shown. The duration can be secret; if it
is, they fall back to the last pinned value. Overall shows no timer.

### 1.6 The math (what the addon itself computes)

Very little, by design:

- **Sorting:** none. `combatSources` comes **pre-sorted by the server** (descending), and the
  addon relies on it. Rank = array index (`RANK_STRINGS[i]`). Breakdown spells are also
  pre-sorted: "API returns combatSpells pre-sorted; no table.sort needed" (Window:2271). Only the
  Deaths type is reversed into chronological order (Window:1746-1764). This is essential, because
  you cannot sort secret amounts in Lua.
- **Bar fill:** `maxAmt = sources[1].totalAmount` (top row), then
  `fill:SetMinMaxValues(0, maxAmt); fill:SetValue(src.totalAmount)` (Window:1765, 1850-1851).
  Both values may be secret; the StatusBar divides engine-side. Deaths rows are full bars
  (0..1, value 1).
- **DPS/HPS:** taken from `amountPerSecond` as provided. The only adjustment: if it is a plain
  number below 1 (long Overall windows produce tiny floats), clamp to 1 (Format:218-222).
- **Text:** `AbbrevNumber(total)` and `AbbrevNumber(perSec)` joined by `string.format("%s (%s)")`.
  `format` with `%s` accepts secret strings; `AbbreviateNumbers` accepts secret numbers and
  returns a secret string.
- **Breakdown percent:** only when the top spell amount is plain: sum all spell amounts and print
  `amount/total*100` with `%.1f%%` (Tooltip:644-704). In combat, amounts only.
- **Targets (Damage Done tooltip, out of combat only):** for each enemy in the
  `EnemyDamageTaken` session, fetch its source breakdown, read
  `combatSpells[i].combatSpellDetails.unitName` (the player who hit it) and `totalAmount`, and
  sum into `byPlayer[name][creatureID]`. Then sort each player's list descending and compute
  per-second as `total / duration`. Cached per session key; wiped on reset and combat edges
  (Format:606-680). Note the enemy key is `creatureID` "(numeric, never secret) to avoid secret
  table keys".
- **Value gradient:** range low/high over the visible rows' `totalAmount` (or `amountPerSecond`
  when the format is per-second). If any value is secret it falls back to rank position
  `(i-1)/(n-1)`. Colour `r = min(1,t), g = min(1,2-t), b = 0` where `t` is in 0..2
  (Appearance:49-90).
- **Durations for history segments:** `durationSeconds` from `GetAvailableCombatSessions`.

### 1.7 Number formatting engine

`EllesmereUI/EllesmereUI_NumberFormat.lua` wraps the **client's own `AbbreviateNumbers` and
`CreateAbbreviateConfig`** (both accept secrets) with breakpoint tables:

- English: B at 1e9 (divisor 1e7, fraction /100, so `1.23B`), M at 1e6, K at 1e3 (one decimal),
  plain below 1000 (NumberFormat:44-47).
- CJK (zhCN/zhTW/koKR): 亿/億/억 at 1e8 and 万/萬/만 at 1e4 (NumberFormat:63-66), with a "force
  English units" override.
- `EllesmereUI.AbbreviateNumber(n, forceEnglish)` calls
  `AbbreviateNumbers(tonumber(n) or 0, config)` (NumberFormat:132-133). The config is built once
  and cached per mode.

This matters: **a formatter built in Lua (`n/1e6`, `string.format("%.1f")`) cannot format secret
numbers. The C-side `AbbreviateNumbers` can.** SoulUI should do the same.

### 1.8 Secret-value handling, case by case

Facts they established in the field (comments say "three debug rounds"):

- **In combat:** `name`, `sourceGUID`, `sourceCreatureID`, `totalAmount`, `amountPerSecond`,
  `spellID`, death times are secret. `classFilename`, `specIconID`, `isLocalPlayer` stay plain.
  **Out of combat the whole list reads plain.**
- **Declassification lags `PLAYER_REGEN_ENABLED`.** The correct edge is
  `ADDON_RESTRICTION_STATE_CHANGED` with `rType == Enum.AddOnRestrictionType.Combat`, checked
  with `C_RestrictedActions.IsAddOnRestrictionActive` (Lifecycle:253-264, Format:310-321).
- **Getter functions refuse secret arguments.** You cannot pass a secret `sourceGUID` back into
  `GetCombatSessionSourceFromType`. This is why mid-combat breakdowns need tricks.
- **Durations can be secret too.** Every read is `type(d)=="number" and not issecretvalue(d)`.

Techniques:

1. **Pass secrets to sinks whole.** `bar.label:SetText(secretName)`,
   `bar.amount:SetText(format("%s (%s)", AbbrevNumber(t), AbbrevNumber(ps)))`,
   `fill:SetValue(secretAmount)`. Memo caches (`_cachedSrcName`, `_cachedAmtText`) are bypassed
   when the value is secret, because you cannot compare it with `~=` (Window:1911-1941).
2. **Never index a table with a secret.** `RAID_CLASS_COLORS[secret]` throws; the feign cache
   lookup is skipped for secret GUIDs (Window:431-435, 1755-1759).
3. **Own-row breakdown in combat:** if the row is yours (`isLocalPlayer`), substitute the plain
   `UnitGUID("player")` and query with that (Tooltip:612-624).
4. **Group-row breakdown in combat (dungeons only):** out of combat, snapshot the Overall session
   into a map `"CLASS:specIconID" -> guid`. If two players share the key, store `false` meaning
   ambiguous. In combat, join the row's NeverSecret class and spec icon against that map to get a
   plain GUID (Format:284-360). The map is additive (never wiped by a session roll), and is wiped
   only on roster or spec change out of combat.
5. **Enemy rows in combat:** their IDs are secret, so they ship a hand-maintained table of this
   season's boss NPC IDs per map (`ns.DM_SEASON_RAIDS`, SeasonRaids.lua; dungeon mobs
   generated into SeasonMobs) and query with those plain IDs ("gated preview",
   Tooltip:220-330).
6. **Secret spell IDs:** `C_Spell.GetSpellTexture` and `GetSpellName` accept secret IDs (marked
   AllowedWhenTainted) but can throw for some, so they use `pcall` and test the result with
   `type()` only, never truthiness (Tooltip:657-677).
7. **Death recap in combat:** HP fraction computed in Lua when plain; otherwise
   `SetMinMaxValues(0, secretMaxHP); SetValue(secretCurHP)`. Label via
   `SetFormattedText("-%.1fs %s", td, spellName)` so a secret name never meets `..`
   (Tooltip:520-568).
8. **Death timestamps:** when `deathTimeSeconds` is secret, they stamp the live Current duration
   the first time the death row appears (`_deathStamps[recapID]`), only for the live Current
   view (Format:367-415). A hidden Deaths window still runs this stamping pass.
9. **Cross-source math only out of combat:** "Targets" and percentages are skipped under
   `InCombatLockdown()` (Tooltip:708-714).
10. **Tooltip message:** in combat, breakdowns that cannot be shown display "Detailed information
    is secret while in combat" (Tooltip:134).
11. **Secret frame geometry:** a bar carrying secret values can report a secret height, so the
    last plain height is cached and used instead (Style:500-503).

### 1.9 Rendering and performance tricks

- **Fixed row pool of 40** (`BAR_POOL_SIZE`), created once per window (Window:1284). Rows beyond
  the count are hidden; content height is `min(#sources, 40) * stride`.
- **Visible-range painting:** compute `visFirst..visLast` from scroll offset and stride; only
  visible rows get per-tick text/value updates (Window:1783-1822).
- **Layout cache key:** a string of every style setting; a full restyle (fonts, textures, anchors)
  only when it changes or a bar moves slot. Per tick only `SetValue`, `SetText` and colour
  when the class changed (Window:1771-1819). Session events deliberately do **not** clear the
  style key ("nilling it here made every death restyle all bars at ticker rate (the dominant
  profiled cost)", State:571-574).
- **Per-row memos:** class, spec icon, colour class, name, amount text, rank, gradient `t`.
  Icon memo includes spec, because rows are recycled by rank and two same-class players can
  swap.
- **Pixel-perfect stride:** bar height and spacing both snapped to the same physical pixel grid
  (`PP.SnapForES`) so a 1px gap does not render as 0 or 2 px down the list (Format:173-190).
- **Thin-line textures** via a second StatusBar overlay with the parent's setters wrapped
  (Format:88-145). (This wraps methods on their own frames, which is fine.)
- **Window creation staggered** across frames at login.
- **Tooltip frame pre-created** after the windows exist so the first hover is free.
- **Hover poll frame** (`_hoverPollFrame` OnUpdate) is shown only while hovering.

### 1.10 Hiding Blizzard's meter

One line: `EllesmereUI.SetCVar("damageMeterEnabled", 0, "EllesmereUIDamageMeters")`
(Lifecycle:457). No frame hooks at all. The API keeps working with the stock UI off.

### 1.11 Spell History (bundled sub-feature)

Your own cast history (icon strip and/or bar window). Registers `UNIT_SPELLCAST_SENT/START/
SUCCEEDED/FAILED/FAILED_QUIET/INTERRUPTED/STOP/CHANNEL_START/CHANNEL_STOP` with
`RegisterUnitEvent(..., "player")` only while enabled (SpellHistory:486-497). Spell info cached
per ID (`_spellInfoCache`). Item "use" spells resolved through `C_Item.GetItemSpell`, with
`ITEM_DATA_LOAD_RESULT` for uncached items. Icons fade out over time on a single timer that
re-schedules to the next expiry (SpellHistory:682). Zero cost when disabled.

---

## 2. EllesmereUIActionBars (second priority)

### 2.1 Purpose and architecture

"Modern action bars built for performance and clarity." ~22.8k lines across 28 files. The design
headline (root:1-7): **they create their own secure buttons** (`EABButton<slot>` from
`ActionBarButtonTemplate, SecureActionButtonTemplate`) instead of reskinning Blizzard's
`ActionButton1..12` and so on. Stance and Pet bars reuse Blizzard's buttons. Paging is a
`RegisterStateDriver` plus a secure `ChildUpdate` that rewrites each button's `action`
attribute. Most of the module's code is about **avoiding taint** under 12.x, where tainted code
cannot hand secret cooldown values to `SetCooldown`.

Bars (`BAR_CONFIG`, root:245-275):

| Key | Slots | Notes |
|---|---|---|
| MainBar | 1-12, paged | `ACTIONBUTTON` binding |
| Bar2 | 61-72 | MultiBarBottomLeft, page 6 |
| Bar3 | 49-60 | MultiBarBottomRight, page 5 |
| Bar4 | 25-36 | MultiBarRight, page 3 |
| Bar5 | 37-48 | MultiBarLeft, page 4 |
| Bar6/7/8 | 145-156, 157-168, 169-180 | MultiBar5/6/7, pages 13/14/15 |
| Bar9 | 13-24 | custom bar on action page 2, custom binding in `Bindings.xml` |
| Bar10 | 109-120 | custom bar on action page 10 |
| StanceBar | StanceButton1-10 | reused Blizzard buttons |
| PetBar | PetActionButton1-10 | reused Blizzard buttons |

Slot offsets: `BAR_SLOT_OFFSETS` (Secure:352-363). Binding prefixes: `BINDING_MAP`
(Secure:367-381), for example `MULTIACTIONBAR1BUTTON` for Bar2.

Extra managed frames (`EXTRA_BARS`, root:282-291): Micro Menu, Bag Bar, Queue Status, XP bar,
Reputation bar, House Favor bar, Extra Action Button, Encounter Bar (holders plus movers; Blizzard
keeps ownership of their visibility).

### 2.2 Feature list (parity checklist)

Global settings (root defaults ~493-560): square icons, icon zoom, cooldown edge size/colour
(class colour), pushed texture type/colour/border, highlight texture type/colour/border, "match
bar border", cast highlight border, **charge recharge numbers**, **desaturate on cooldown**,
**alpha on cooldown**, cooldown swipe colour and alpha, proc glow type/colour (class colour),
assisted-combat glow style, Blizzard Style / Classic style, slot background colour, hide casting
animations, "mouseover shows all bars".

Per-bar settings (root ~560-640): enabled, border (texture, size, class colour, behind/above),
button padding, width, height, **mouseover fade** (alpha, speed), **show in combat / hide in
combat**, hide in housing, **custom visibility macro**, show while dragging, hide with gamepad,
only in instances, hide mounted, hide with no target, hide with no enemy, keybind text
(hide/size/colour/offset), macro text (hide/size/colour/offset), count text, always hidden,
click-through, number of icons, number of rows, grow direction, reverse order, **always show
empty buttons**, paging arrows (right side, skip visible pages), **custom paging**
(modifiers, forms, target conditions), disable form paging, disable skyriding paging, bar
background, **out-of-range colouring** (colour), **button shapes** (square, circle, diamond,
hexagon, portrait) with shape border.

Other: Quick Keybind mode support, spell flyout reskin, XP/Rep/House Favor data bars with text
positions, session XP rate, quest XP overlay, vehicle exit button, housing editor keybind
clearing, toggle-bar keybind, unlock-mode movers, first-install capture of Blizzard's layout
("Bars" file).

### 2.3 Hiding Blizzard's bars (Disposal.lua, runs at file load)

At **file load time, before combat state is restored**, so protected calls run clean
(Disposal:281-415):

- A permanently hidden full-size `EABHiddenParent` frame (Disposal:25-27). Stock bars
  `MultiBar5/6/7`, `MultiBarBottomLeft/Right`, `MultiBarLeft/Right` are **reparented to it**
  rather than `:Hide()`n. Their comment: `Hide()`/`HideBase()` route through protected
  `SetShownBase` via Edit Mode and later trigger `ADDON_ACTION_BLOCKED` in combat. Reparenting
  needs no protected call.
- `MainActionBar` is **kept in place but alpha 0 with mouse disabled**, end caps and border art
  hidden, Edit Mode selection hidden. Its hidden page-number arrows (frame level 100) would still
  eat clicks, so their mouse is also disabled (`KillPagerMouse`).
- Each Blizzard action button gets `UnregisterAllEvents()` and
  `SetAttributeNoHandler("statehidden", true)`, so Blizzard's own pass hides it
  (Disposal:28-37).
- `ReassertHiddenOnShow`: `HookScript("OnShow")` that re-parents to hidden out of combat if
  Blizzard re-shows a bar (Disposal:39-56).
- `ActionBarParent:Hide(); SetParent(hiddenParent)`.
- **Quieting Blizzard's event broadcasters** (Disposal:58-128): `ActionBarButtonEventsFrame` and
  `ActionBarActionEventsFrame` dispatch events to every registered button. EllesmereUI
  unregisters everything except `ACTIONBAR_SLOT_CHANGED` and `PLAYER_ENTERING_WORLD` (left as
  Blizzard's own registrations so they stay untainted). The fuller set is re-added only while a
  vehicle/override bar or the Extra Action Button needs painting, and never when
  `C_Secrets.ShouldCooldownsBeSecret()` is true (Disposal:182-236).

### 2.4 Creating their own secure buttons (Secure.lua)

`GetOrCreateButton(slot, parent, info, index)` (Secure:485-687):

- `CreateFrame("CheckButton", "EABButton"..slot, parent, "ActionBarButtonTemplate,
  SecureActionButtonTemplate")`, reusing the global if it already exists after `/reload`.
- `btn.UpdateButtonArt = function() end`: neuters the template's art reset, which re-applied
  atlases on every update across ~96 buttons (Secure:511-514).
- Unregister the template's own `ACTIONBAR_SLOT_CHANGED` and `ACTIONBAR_UPDATE_COOLDOWN`. A
  central dispatcher owns both (Secure:516-523).
- **Remove the button from `ActionBarButtonEventsFrame.frames`** by setting its entry to `nil` in
  place (not `tremove`, which would shift later Blizzard entries and taint them). The template's
  `OnLoad` inserted it under addon execution, so the entry is tainted and would taint Blizzard's
  dispatch loop (Secure:524-554).
- `btn:SetID(0); btn:SetAttribute("action", slot)`. With ID 0 the template resolves its slot from
  the `action` attribute, not from `actionpage`.
- Re-register a lean per-button event list (Secure:408-433): `ACTIONBAR_UPDATE_STATE`,
  `ACTIONBAR_UPDATE_USABLE`, `PLAYER_ENTERING_WORLD`, `UPDATE_SHAPESHIFT_FORM`,
  `SPELL_UPDATE_CHARGES`, `UPDATE_INVENTORY_ALERTS`, `PLAYER_EQUIPMENT_CHANGED`,
  `PLAYER_TARGET_CHANGED`. Deliberately **not** `ACTIONBAR_UPDATE_COOLDOWN` or `SLOT_CHANGED`
  per button: "assisted-combat dirties its slot ~11x/sec at total idle (dispatching to ~140
  mixins ran the full cooldown path ~1500x/sec forever)". Not `LOSS_OF_CONTROL_*` either (the
  mixin's handler cannot pass restricted LoC times under taint).
- Hooks added once per button (guarded by side-table flags, because `HookScript` stacks):
  `cooldown:HookScript("OnCooldownDone")` to restore desaturation at the exact end edge;
  `OnEnter` to re-assert desaturation and hotkey colour after Blizzard's hover repaint;
  `hooksecurefunc(btn, "StartFlash"/"StopFlash")` to replace the attack flash; `PostClick` to
  paint the predicted GCD at press time.
- **Shift-drag pickup fix:** a `SecureHandlerWrapScript(btn, "OnClick", ...)` that, on a mouse
  down with the pickup modifier, temporarily sets `useOnKeyDown=false` and restores it on the up
  click (Secure:633-676).
- Every button is registered with a central **`SecureHandlerAttributeTemplate` controller**
  (`EABActionButtonController`, Controllers:24) that wraps `OnAttributeChanged`, `PostClick`,
  `OnReceiveDrag`, `OnShow/OnHide`, `OnDragStart`, and implements bitwise show-grid and a
  deferred visibility flush (Controllers:84-250). A second controller follows vehicle, override
  and possess bars (Controllers:283-335).
- Protected setup work (SetParent, SetPoint, SetSize, Show) during a combat reload is done inside
  a restricted snippet on `EABSecureSetupHandler` (Secure:20-200) using `SetFrameRef`.

### 2.5 Paging (Bars.lua, Paging.lua)

Each bar is a `SecureHandlerStateTemplate` frame `EABBar_<key>` (Bars:36-48).

- **MainBar:** `RegisterStateDriver(frame, "page", conditions)`. The `_onstate-page` snippet
  sets `actionpage`, calls `self:ChildUpdate("eab-page", page)`, and **mirrors `actionpage` onto
  Blizzard's `MainActionBar`** because the native `ACTIONBUTTON1..12` bindings still fire
  Blizzard's hidden `ActionButton1..12`, which read their page from that frame (Bars:70-93).
  The comment warns: never `CallMethod` here; vehicle transitions evaluate all state drivers in
  one secure pass, and leaving to insecure Lua taints the pass, so `OverrideActionBar:Show()`
  gets blocked.
- Each button's `_childupdate-eab-page` snippet: `slot = base + (page-1)*12;
  SetAttribute("action", slot)`, then show/hide for empty slots and re-check press-and-hold
  (Paging:601-643).
- **Class default conditions** (`GetClassPagingConditions`): roughly
  `[overridebar] 14; [vehicleui][possessbar] 12; [bar:2] 2 ... [bar:6] 6; [bonusbar:1] 7;
  [bonusbar:2] 8; [bonusbar:3] 9; [bonusbar:4] 10; [bonusbar:5] 11; 1` with class tweaks (for
  example rogue `[bonusbar:1,stealth] 7`) (Paging:170-215). Override/vehicle indexes come from
  `GetOverrideBarIndex()` / `GetVehicleBarIndex()` with fallbacks 14 and 12 (Secure:703-709).
- **Ordering lesson** (Paging:131-145): manual `[bar:N]` pages must come **before** the
  skyriding `[bonusbar:5] 11` clause, or the bar stays pinned to the skyriding page.
- **Custom paging per bar:** modifiers `[mod:alt]`, `[mod:shift]`, `[mod:ctrl]`, form/stance
  picks and target conditions, built into a macro-condition string (Paging:30-160).
- **Paging arrows:** `SecureActionButtonTemplate` with `type="macro"` running
  `/changeactionbar [bar:6] 1; [bar:1] 2; ...` (Paging:235-241).

### 2.6 Keybinds and keybind text

- `UpdateKeybinds()` (Keybinds:49+) owns all override bindings on one frame
  (`EAB_BindOwner`), so they can be cleared and re-applied as a unit.
- **Routing rule:** standard bars bind keys to the **native commands** (`ACTIONBUTTON1`,
  `MULTIACTIONBAR1BUTTON1`...) because only native routing pairs key-down and key-up for
  empowered (press-hold-release) spells and queueing. Only custom-paged bars, Bar9/Bar10 and
  **flyouts** route through the button with `SetOverrideBindingClick` (flyouts need our visible
  button as the anchor). Detection: `GetActionInfo(slot) == "flyout"` and
  `C_Spell.IsPressHoldReleaseSpell(spellID)` (Keybinds:20-118).
- A **routing signature cache** skips rebuilds unless a bound key, routing decision or empower
  state changed, because `ACTIONBAR_SLOT_CHANGED` storms with mouseover macros.
- Combat: deferred via the combat queue. House editor: their overrides are cleared so housing
  hotkeys work.
- `ActionButtonUseKeyDown` CVar respected (Keybinds:314-341).
- **Hotkey text** `FormatHotkeyText` (root:917-943): use `GetBindingText(key, 1)` for gamepad
  glyph markup, otherwise shorten `CTRL-` to `C`, `ALT-` to `A`, `SHIFT-` to `S`, `META-` to `M`,
  mouse buttons to `M4`, wheel to `MwU`/`MwD`, `NUMPAD` to `N` (with specific numpad keys
  first). Hotkey colour is re-asserted after Blizzard's hover repaint (queued, coalesced).

### 2.7 Cooldowns: swipes, desaturation, charges (Events.lua)

A **central dispatcher** frame handles events for all buttons (Events:1030-1087):
`ACTIONBAR_UPDATE_COOLDOWN`, `SPELL_UPDATE_COOLDOWN` (aliased), `UNIT_SPELLCAST_SUCCEEDED`
(player; only marks dirty), `CURRENT_SPELL_CAST_CHANGED`, `START/STOP_AUTOREPEAT_SPELL`,
`PLAYER_ENTER/LEAVE_COMBAT`, `ACTIONBAR_UPDATE_USABLE`, `ACTIONBAR_SLOT_CHANGED`,
`PLAYER_ENTERING_WORLD`, `UPDATE_SHAPESHIFT_FORM`, `SPELL_UPDATE_CHARGES`, `SPELL_UPDATE_ICON`,
`UPDATE_VEHICLE_ACTIONBAR`, `UPDATE_OVERRIDE_ACTIONBAR`, `ACTIONBAR_PAGE_CHANGED`,
`UPDATE_BONUS_ACTIONBAR`, `PLAYER_TARGET_CHANGED`, `CVAR_UPDATE`, `BAG_UPDATE_DELAYED`,
`COOLDOWN_VIEWER_*`. It filters with `HasAction()` and keeps a `slot -> buttons` map.

**12.x cooldown API (the important part):**

- `C_ActionBar.GetActionCooldown(action)` returns a struct with `isActive`, `isOnGCD` (and
  secret timing fields in restricted content).
- `C_ActionBar.GetActionCooldownDuration(action)` returns a **duration object**.
- `cooldown:SetCooldownFromDurationObject(durObj)` is the sink that accepts secret timing. The
  numeric `SetCooldown(start, dur)` path is closed to tainted code for secret values
  ("SecretArguments AllowedWhenUntainted", Events:959-961).
- Charges: `C_ActionBar.GetActionCharges(action)` (`currentCharges`, `maxCharges`) and
  `C_ActionBar.GetActionChargeDuration(action)` into a lazily created `btn.chargeCooldown`
  (Events:1202-1240).
- Spell-keyed equivalents: `C_Spell.GetSpellCooldown(id)`, `C_Spell.GetSpellCooldownDuration(id)`,
  `C_Spell.GetSpellCharges`, `C_Spell.GetSpellChargeDuration`.
- Count text: `C_ActionBar.GetActionDisplayCount(action)` can be secret and goes straight to
  `SetText` (Events:1255-1265).

`PushButtonCooldown` (Events:962-1029): **no change gate while active**. Every pass re-pushes a
fresh duration object, because a duration object fetched in the same frame as the cast can be
unpopulated, and in combat you cannot inspect it to know. On the falling edge, `cd:Clear()`.

**Desaturate / dim on cooldown without reading secrets** (Events:700-916): a
`C_CurveUtil.CreateCurve()` of type `Enum.LuaCurveType.Step` with points `(0 -> 0)` and
`(gcdLength -> 1)`, where `gcdLength = 1.5/(1+haste/100)` floored at 0.75 s, plus 0.15 s margin,
rounded to 0.05 s. Then `icon:SetDesaturation(durObj:EvaluateTotalDuration(curve, 0))`. The
result may be secret; `SetDesaturation` accepts it. Using **total** duration (not remaining)
classifies "GCD only" against "real cooldown" for the cooldown's whole life. Alpha uses a
second step curve (`1` to the user's dim value) through `icon:SetAlpha(...)`. Fallback for
clients without `EvaluateTotalDuration`: `icon:SetAlphaFromBoolean(durObj:IsZero(), 1, dim)`.
Banked charges (current > 0, plain) keep the ready look. The haste threshold rises immediately
but only falls after a 2 s hold, so Bloodlust mid-GCD does not grey the bar.

**Loss of control** is painted by the dispatcher itself (the mixin cannot under taint).

### 2.8 Range, usability, glows

- **Range** (Range.lua): `C_ActionBar.EnableActionRangeCheck(slot, true)` per visible slot, then
  listen to `ACTION_RANGE_CHECK_UPDATE` (and `ACTION_USABLE_CHANGED`); tint with
  `icon:SetVertexColor`. No polling. Range checking is disabled for slots on hidden bars so they
  do not generate events. Enabling gives no initial state, so they seed once with
  `IsActionInRange(slot) == false` (Range:25-208).
- **Usability:** `C_ActionBar.IsUsableAction(action)` returns `isUsable, noMana`.
- **State:** `C_ActionBar.IsAttackAction`, `IsAutoRepeatAction`, `IsCurrentAction`, checked
  state (guarded for secret) (Events:60-100).
- **Assisted combat** (single-button rotation): `C_ActionBar.IsAssistedCombatAction(action)` plus
  a ticker painting the suggested spell's icon and cooldown.
- **Proc glows:** `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` into the shared glow engines
  (Glows.lua, 1207 lines).

### 2.9 Visibility drivers

`RegisterAttributeDriver(bar, "state-visibility", macro)` with built strings such as
`"[petbattle] hide; [vehicleui][petbattle][overridebar] hide; [combat] show; hide"`
(VisibilityDrivers:100-185). Mouseover fade is an insecure alpha animation on top (Fade.lua).
Lazy build: bars hidden at load are not built until needed, except that a keybind landing on
one forces the build (`ns._eabBuildSkippedBars()`).

### 2.10 Performance summary for ActionBars

- One dispatcher, not 140 mixins handling the same event.
- Spell-keyed cooldown prefetch: one cooldown struct and duration object per spell group per
  pass, shared by every button showing that spell.
- Per-frame memo of `UnitSpellHaste` and `IsMounted` (`GetTime()` keyed).
- Binding rebuilds skipped by signature.
- Hover repaint fixes are queued and coalesced.
- Range via engine events per slot, disabled for hidden bars.

---

## 3. EllesmereUIMythicTimer ("Mythic+ Tools")

**Purpose:** M+ timer overlay plus kick tracking, target/focus cast bars, an enemy cast list and
an end-of-run summary. SavedVariables `EllesmereUIMythicTimerDB` plus per-character
`EllesmereUIMythicRunsDB`. 14.8k lines.

**Features:** title / dungeon name / key level, affixes, +2/+3 thresholds and remaining time,
timer bar (ticks or segments), deaths and time lost, objectives with completion times and split
comparison (vs best / last, faster/slower colours, upcoming split targets), enemy forces bar
(percent or count) with a **current pull overlay**, completed-run milliseconds, preview mode,
lots of layout options. Mythic+ Tools sub-features: Kick Tracker (nameplate icons and bars), Target
and Focus cast bars, Targeted Spell Bars (one bar per casting enemy plate), Run Summary (party
table plus history, `/ov`), and a shared "Where to show" filter.

**Data:**

- Elapsed: `select(2, GetWorldElapsedTime(1))` (MythicTimer:939).
- Driver: `hooksecurefunc(ScenarioObjectiveTracker.ChallengeModeBlock, "UpdateTime", ...)`
  which Blizzard calls every frame while the key runs; deduped to once per whole second. An
  OnUpdate 1 s fallback runs only if the hook fails (MythicTimer:895-1007).
- Run info: `C_ChallengeMode.GetActiveChallengeMapID`, `GetMapUIInfo(mapID)` (name, time
  limit), `GetActiveKeystoneInfo()` (level, affixes), `GetAffixInfo`, `GetDeathCount()` (count,
  time lost), `GetChallengeCompletionInfo`.
- Objectives: `C_ScenarioInfo.GetCriteriaInfo(i)`; enemy forces parsed from `quantityString`
  (strip `%`, cached on the last string).
- Events: `CHALLENGE_MODE_START/COMPLETED/RESET`, `WORLD_STATE_TIMER_START/STOP`,
  `PLAYER_ENTERING_WORLD`; high-frequency `SCENARIO_CRITERIA_UPDATE` registered only during an
  active run (MythicTimer:3322-3330).
- Season constant: Challenger's Peril adds 90 s (comment near the top).

**Secret handling, the clever bit (pull bar):** per-unit forces are secret in M+. They walk
`nameplate1..40`, filter with plain-true checks (`UnitCanAttack`, `UnitAffectingCombat`, not
dead), call `C_ScenarioInfo.GetUnitCriteriaProgressValues(unit)` and test only `type(v) ~= "nil"`.
Each value goes to its own StatusBar segment (`SetMinMaxValues(0, total); SetValue(v)`), and
**each segment is anchored to the previous segment's fill edge**, so the pull total is added up
on screen without Lua ever adding it. A clip frame hides anything past 100%
(MythicTimer:1558-1646).

**Kick engine** (KickEngine header, lines 1-60): no event names the kicker in 12.x instanced
combat. They infer it from the **damage meter's Interrupts session**: a landed kick changes the
data (a row appears, rows reorder, or a member's kicked-spell list grows). Deductions use only
plain fields (row order, class, spec icon, local flag, list lengths). Where a count is hidden,
a "gate packet" hands the before/after counts (secret) to a hidden StatusBar
(value = before, max = after): the fill is full when nothing changed and short when the count
rose, and a clip on the fill's edge reveals that member's icon. **Identify the kicker without
reading the secret.** Cooldowns come from a class/spec/talent kick table
(`EllesmereUI.KickData`), talents from inspect out of combat.

**Run Summary** (RunSummary:122-180): harvests `GetCombatSessionFromType(Overall, type)` per
metric, diffs against a baseline taken at key start, banks gains across meter resets, waits for
`IsDamageMeterAvailable()` and declassification, wraps the walk itself in `pcall` because
`type()` says "table" for a secret table too.

**Blizzard frames:** hides `ObjectiveTrackerFrame` during a key with a `hooksecurefunc(otf,
"Show")`. Because it is Edit Mode managed and `Hide()` is protected in combat, in combat it is
set to alpha 0 and the real hide is deferred to after combat (MythicTimer:1032-1060).

**Cast bars:** secret discipline throughout: `type()` checks, duration objects into
`StatusBar:SetTimerDuration`, `C_CurveUtil.EvaluateColorValueFromBoolean` for
interruptible/important colours, `SetAlphaFromBoolean` for visibility, `C_Spell.IsSpellImportant`.

---

## 4. EllesmereUIDataBars

**Purpose:** user-built info bars ("clock, gold, reputation and more"). An engine
(`EllesmereUIDataBars.lua`, 3.3k lines) plus block factories in `Blocks\*.lua`.

**Features:** any number of bars (stable never-reused IDs), each with slots containing
**blocks**: Audio, Bags (free space), Clock, Crests, Currency, Gold (session/character ledger,
token price), Great Vault, Item Level, **LibDataBroker** plugins, Location / coordinates, Micro
Menu (with optional Blizzard micro menu hider), Profession (primary/secondary), Spacer, Spec
(spec, loot spec, loadout popups), Stats (FPS, latency, durability, combat), Travel (hearthstones,
M+ teleports), XP/Rep bar. Layout solver: auto-fit pixel widths plus percentage weights. Its own
rich tooltip replaces every GameTooltip call. Themes: EllesmereUI atlas or modern flat.

**Data:** `GetMoney`/`PLAYER_MONEY`, `C_CurrencyInfo.GetCurrencyInfo`, `C_Container.*`,
`GetFramerate`, `GetNetStats` ("cached ~30s, re-layout only on change"), 
`GetInventoryItemDurability`, `C_WeeklyRewards.GetActivities`, `C_MythicPlus.GetOwnedKeystone*`,
`C_ClassTalents.*` (loadouts), `C_Map.GetBestMapForUnit`, `C_Rep.GetWatchedFactionData`,
`C_MajorFactions.GetRenownLevels`, `C_WowTokenPublic.*`.

**Performance:** a **shared 1-second heartbeat** that exists only while a block is registered
(`ns.RegisterHeartbeat(key, fn)`, engine:483-501), text-fit cache, frame pool, out-of-combat
deferral.

**Blizzard frames:** micro menu hidden through a `SecureHandlerStateTemplate` `_onstate-vis`
driver, never `MicroMenuContainer:Hide()` from insecure code (MicroMenu.lua:40, 430).

---

## 5. EllesmereUIMinimap

**Purpose:** restyled minimap (square or circular, borders), clock/coords/zone text, addon button
collection. ~6.9k lines.

**Features:** shape (square mask, circle), size, border styles, zoom memory and mouse-wheel zoom,
hide zoom buttons, clock / coordinates / location text (font, colour, anchor), custom indicator
buttons (mail, crafting orders, calendar, tracking, LFG queue, Great Vault with tooltip, M+
portal), **addon button collection** into a flyout grid or "folio" (blacklists, junk filter,
grow directions), addon compartment styling, friends tooltip and calendar tooltip with lockouts,
mouseover reveal, opacity, icon scale, Farming HUD compatibility, stock styles.

**Data/APIs:** `Minimap:SetMaskTexture(...)`, `SetArchBlobRingScalar` and
`SetQuestBlobRingScalar` set to 0 for square (Apply:231-248), `Minimap:SetZoom`,
`C_Map.GetPlayerMapPosition`, `C_DateAndTime.*`, `C_FriendList`, `C_BattleNet`,
`C_WeeklyRewards.GetActivities`, `C_ChallengeMode.GetActiveKeystoneInfo`.

**Blizzard frames:** `hooksecurefunc(Minimap, "SetPoint"/"SetParent")` and
`hooksecurefunc(MinimapCluster, "SetIconScale")` to re-assert placement when Edit Mode moves it;
hooks on individual buttons (`Show`, `SetPoint`, `SetParent`, `SetScale`) to keep collected
buttons where they put them; `hooksecurefunc("ToggleMinimap")`. Button scan recognises
`LibDBIcon10_*` names and re-anchors `LibDBIconTooltip`.

---

## 6. EllesmereUIChat

**Purpose:** chat restyle with its own message renderer. ~11k lines.

**Features:** unified dark panel (chat plus input), custom tabs (font, colour, spacing,
borders), Blizzard chrome removed, timestamps, thin scrollbar, copy-chat popup, URL detection
and copy popup, hyperlink hover tooltips, **session history across reload/relog**, sidebar of
icons (friends, channels, portal flyout, chat menu), fade/visibility rules, edit box skin,
position/size lock with Edit Mode storage, stock styles.

**Architecture (worth copying as an idea):** Blizzard's chat frames remain the **secure
formatting and data plane** (class colours, player links, censoring, TTS, message filters all
stock). Their text container is set to alpha 0, and every formatted line is bridged by a single
`hooksecurefunc(cf, "AddMessage", ...)` into an addon-owned `ScrollingMessageFrame`. Scrolling
runs in lockstep, so Blizzard's invisible hyperlink hit zones stay under the visible text and
handle clicks securely (Engine header lines 1-60).

**Taint doctrine** (Engine header): never `hooksecurefunc` any `FCF_*` function; never reparent a
Blizzard chat widget that secure code later writes to; never write fields (even functions) onto
Blizzard chat frames. A replaced `AddMessage` field taints `ChatFrame_MessageEventHandler` and
kills the whisper path on a secret sender name.

**Secret handling:** during chat messaging lockdown (encounters, M+, PvP, dungeon/raid maps;
`C_ChatInfo.InChatMessagingLockdown()`), message strings can be secret. They pass through
whole: no concatenation, `gsub` or measuring. Copy, URL and history features skip any secret
line (`issecretvalue` gates, EditBox:134-140, 292-309, Links:65, 397, 425). History captures
only in the open world and never stores secrets.

---

## 7. EllesmereUIBags

**Purpose:** all-in-one bags and bank. ~19k lines. SavedVariables include
`EllesmereUIBagsInventoryDB` (offline inventories, kept separate from profiles).

**Features:** three display modes (grid, list with sortable/reorderable columns, compact
category blocks), sidebar category filter (categories by `Enum.ItemClass` IDs, rename, reorder,
group), search, sort, pin and assign modes, junk marker plus sell junk, item level, bind text,
quality borders, Pawn upgrade arrows, reagent bag window, footer with gold and tracked
currencies, bank and warband bank with tabs and purchase, **offline view of alts' bags and
banks** plus tooltip counts, Quick Actions (one secure button that casts a spell such as
Disenchant on the hovered item), stack splitter, controller support, auto-size.

**Data:** `C_Container.GetContainerItemInfo/NumSlots/NumFreeSlots/ItemLink/ItemCooldown/
ItemQuestInfo`, `C_Item.*`, `C_Bank.*`, `C_TooltipInfo.GetBagItem`, events `BAG_UPDATE`,
`BAG_UPDATE_DELAYED` (batching), `ITEM_LOCK_CHANGED`, `INVENTORY_SEARCH_UPDATE`,
`BANKFRAME_OPENED/CLOSED`, `PLAYER_INTERACTION_MANAGER_FRAME_HIDE`, `BANK_TABS_CHANGED`,
`PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED`, `GET_ITEM_INFO_RECEIVED`, `CURRENCY_DISPLAY_UPDATE`.

**Blizzard frames:** `hooksecurefunc("ToggleBackpack"/"ToggleAllBags"/"OpenAllBags"/"ToggleBag")`
to open their frame instead. Item slots are secure item buttons (Grid "secure item-slot
factory"). The Quick Actions button is moved and shown only out of combat and hidden on
`PLAYER_REGEN_DISABLED`.

---

## 8. EllesmereUIQuestTracker

**Purpose:** a reskin of Blizzard's `ObjectiveTrackerFrame`, not a replacement ("Blizzard's
ObjectiveTrackerFrame remains the rendering engine; we only skin it, drive its visibility, and
layer on QoL"). They threw away an earlier 3.8k-line custom tracker. ~4.3k lines.

**Features:** header/block/progress bar/timer bar styling (gold titles, grey objectives),
visibility rules (hide in combat, M+, instances, encounters), position through Edit Mode layout
(so Blizzard's own layout system places it), auto-accept and auto-turn-in quests (gossip and
quest events, combat-gated), quest item hotkey, SplashFrame taint fix, Wowhead quest links.

**Hooks:** `hooksecurefunc(tracker, "AddBlock"/"Update")`, `hooksecurefunc(otf, "AddModule")`,
`hooksecurefunc(header, "SetCollapsed")`, `hooksecurefunc(block, "GetPOIButton")`,
`hooksecurefunc(ObjectiveTrackerFrame, "ApplySystemAnchor")`. Rules in the Visibility header:
never `SetScript` on the tracker (only `HookScript`), never walk its children calling
`EnableMouse`, never `SetParent/SetPoint/Hide` the Edit Mode managed frame from addon execution
during combat. Position goes into `C_EditMode.SaveLayouts` and needs a reload.

---

## 9. EllesmereUIAuraBuffReminders

**Purpose:** clickable reminder icons for missing raid buffs, own auras (poisons, shields,
beacons), consumables (flask, food, rune, weapon oil) and talent loadouts. ~8k lines.

**Features:** sections for raid buffs, auras, consumables; click to cast or use (secure
buttons); glows and appear sounds; middle-click dismiss; "attach important buffs to cursor"
(optionally only in combat); ready-check healer mana warning; talent reminders per zone or
content; Beacon M+ reminders (Holy Paladin); per-section unlock movers.

**Data:** `C_UnitAuras.GetPlayerAuraBySpellID`, `GetAuraDataByIndex`, `GetUnitAuraBySpellID`,
`GetAuraDataBySpellName`, `C_PaperDollInfo.GetTemporaryEnchantmentInfo` (weapon oils),
`C_SpellBook.IsSpellKnown`, `C_Traits.*` / `C_ClassTalents.GetActiveConfigID`, bag counts.
Many events (`UNIT_AURA` unit-filtered, `GROUP_ROSTER_UPDATE`, `READY_CHECK`, `ENCOUNTER_*`,
`CHALLENGE_MODE_*`, `PLAYER_REGEN_*`, etc.) with a refresh throttle.

**Secret handling:** `C_Secrets.ShouldSpellAuraBeSecret(spellID)` decides per spell whether a
lookup is trustworthy (`EABR.IsRuntimeNonSecret`, Auras:29-36). A **pre-combat aura snapshot**
(`_preCombatAuraCache`, taken at `PLAYER_REGEN_DISABLED`) is used during combat. A miss on a
secret aura is "not authoritative" (no false reminders). Beacon M+ reminder: Lua never reads the
aura; an engine aura container on the tank's unit draws the icon only while the aura exists.
Colour curves via `C_CurveUtil.CreateColorCurve`.

---

## 10. EllesmereUIBlizzardSkin

**Purpose:** umbrella reskin of Blizzard windows. 38k lines (`_WindowPacks.lua` alone is 14k).

**Features:** themed **Character Sheet** (5k lines: item levels, enchants, gems, upgrade
tracks, stat diminishing-returns tooltips, socket panel), Inspect Sheet, Great Vault, Group
Finder (PVEFrame), tooltips (EllesmereUI style, anchor to cursor or fixed mover, growth
direction, show-tooltip modes with peek modifier, unit health strip), static popups, context
menus, chat bubbles (a styled frame riding Blizzard's bubbles via `C_ChatBubbles.GetAllChatBubbles`),
Skyriding HUD (`C_PlayerInfo.GetGlidingInfo`), mail alt list, merchant bulk buy, game menu, quick
keybind frame, LFG dialogs, UI widget bars, extra action button, and a **window engine** with
per-window "packs" for many load-on-demand Blizzard addons. Public `EllesmereUI.RegisterSkin(addon,
fn)` API for third parties.

**Approach:** primitive skinners (strip textures, flat panel, accent-underlined tabs, square
icons, flat scrollbars) applied when each Blizzard addon loads (`ADDON_LOADED` orchestration).
All state in weak-keyed side tables.

---

## 11. EllesmereUIQoL

**Purpose:** grab-bag of quality-of-life features. 21k lines.

**Feature list:** gear Upgrade Calculator (`/euic`), center-screen Alerts anchor, Auto combat
logging (by instance type and difficulty, forces advanced logging), Battle Res tracker (polls
`C_Spell.GetSpellCharges(20484)` for the shared raid pool), Bloodlust/Sated tracker, Cursor
ring/trail, Party Keys popup (`/keys`, via LibKeystone), Movement cooldown alert, Raid Buff Check
window (flask, food, rune, vantus, buffs per member), Raid Tools (marker band, ready/role check,
pull timer, secure marker buttons), Self Combat Text (replaces Blizzard's floating text),
Shifter (shift-drag to move Blizzard panels permanently, ctrl-drag temporarily), Teleport Prompt
on LFG join, upgrade tooltip lines, `/way` waypoints, guild chat privacy overlay, auto-accept
resurrection, secondary stats overlay, FPS counter, environment ping keybind, durability
warning, pixel-perfect UI scale, disable right-click targeting, character crosshair, transparent
world map sidebars, hide error messages (per message type via
`UIErrorsFrame:SetMessageTypeEnabled`), hide tutorial pop-ups, **group death announcer** (polls
group units for alive to dead since there is no combat log), combat enter/leave alert, target
distance text, hide item transform auras, equipment flyout item levels.

**Notable 12.x workarounds:** death detection by polling `UnitIsDeadOrGhost` transitions; error
message switches written once per session (writing back would taint Blizzard's flash code).

---

## 12. EllesmereUIQuickdraw

**Purpose:** "Hold a keybind to open a menu of actions; point or scroll to choose, release to
fire." 10.5k lines.

**Features:** three layouts (Arc with configurable span up to 360, Fan strip scroll- or
pointer-steered, Grid), slots can be spells, items, toys, mounts, macros, markers, spec swaps,
professions, outfits, interface panels; dynamic battle-res slot; usability filter; cooldown and
count display.

**Secure design:** one hidden `SecureActionButtonTemplate` button per palette, registered for
`AnyDown, AnyUp`, with the key routed by `SetOverrideBindingClick` (plus every modifier variant
nothing else uses). Key down: PreClick opens the palette and a wrapped secure snippet clears
`type` so the press does nothing. Key up: the snippet computes which slot the cursor points at
(angle maths in the restricted environment) and writes that slot's action attributes, then the
secure handler casts. Choosing must happen in the snippet because addons cannot write
attributes to protected frames in combat. Only the angular layouts are steered in-snippet so
far; the others fire only out of combat.

---

## 13. EllesmereUIForeverEssentials

`## Interface: 16001`, `## AllowLoadGameType: camelot`: **WoW Forever client only**, not retail.
Out of SoulUI scope. For completeness: classic spellbook and talents windows, flight timer,
map reveal, travel pins, zone levels, junk window, loot feed with gold/hour, macro manager, spell
uprank, threat meter (Forever's threat API is not secret there) feeding a "Threat" damage meter
type, gathering skill tooltips, fishing helpers, auto pet summon, quest reward value.

---

## 14. EllesmereUIFriends

**Purpose:** "A modern friends list". It skins Blizzard's native friends `ScrollBox` and buttons
directly ("no custom DataProvider, no friend groups"). The toc notes that their friend-groups
feature was removed because a value is secret on 12.1. Uses `C_FriendList.GetFriendInfoByIndex`,
`C_BattleNet.GetFriendAccountInfo`, `C_PartyInfo.InviteUnit`, `C_SocialUI.IsSystemEnabled`.
State in weak side tables.

---

## 15. EllesmereUIGroupFinder

**Purpose:** premade group search filters, list tweaks and an M+ applications bar. Currently
**held back from release** ("Held back from this release (EllesmereUI.HELD_BACK_ADDONS): nothing
runs"). Uses `C_LFGList.GetAdvancedFilter/SaveAdvancedFilter`, `GetSearchResultInfo`,
`GetSearchResultPlayerInfo`, `GetSearchResultMemberCounts`, `GetApplications`,
`GetApplicationInfo`, `CancelApplication`, `GetActivityInfoTable`; `C_MythicPlus` season best
data; application counts per session, character and account. Blizzard frame work deferred out
of combat via the combat queue.

---

## 16. EllesmereUILocales (localization approach only)

- The parent `EllesmereUI_Locale.lua` defines `EllesmereUI.L` as a callable lookup (English key
  is the string itself; a missing key falls back to English) and `EllesmereUI.Lf(s, ...)` which
  translates then `format`s with **positional specifiers** (`%1$s`, `%2$d`) so translators can
  reorder (Locale.lua:71-79). `EllesmereUI.EnKey(s)` reverse-maps a translated on-screen string
  to its English key for code that compares rendered text.
- Translations live in a separate **LoadOnDemand** addon, loaded by the parent at its
  `ADDON_LOADED` only when the effective locale (client locale or an in-game override) is not
  English.
- Each `.toc` line uses `[AllowLoadTextLocale deDE, enUS, enGB]` so a client parses only its own
  language file (and its pair: esMX/esES, zhCN/zhTW). English clients load a translation only
  when the user picks one in options.
- Each file: `local L = EllesmereUI.RegisterLocale("deDE"); if not L then return end`, then
  `L["English"] = "Deutsch"`. Module-specific files (`deDE_SLC.lua`) additionally return early
  unless that module will load (`EllesmereUI.LocaleModuleLoads(...)`), so disabled modules cost no
  memory.
- A `/euiloc dump <locale>` command generates the list of untranslated keys.

---

## 17. Recommendations for SoulUI

### 17.1 Damage meter (build this first, it is the cheapest high-value module)

1. **Use `C_DamageMeter` as the only data source.** Do not attempt our own accounting; 12.x makes
   it impossible and the server meter is authoritative. Turn off the stock UI with
   `SetCVar("damageMeterEnabled", 0)` (remember the old value and restore it if our module is
   disabled). No frame hooks needed.
2. **Trust the server's order and per-second values.** Rank = array index; fill =
   `SetMinMaxValues(0, sources[1].totalAmount)` + `SetValue(src.totalAmount)`; DPS =
   `amountPerSecond`. Never `table.sort` combat sources and never divide amounts in combat.
3. **Format numbers only through the client's `AbbreviateNumbers` with a
   `CreateAbbreviateConfig` table** (our own K/M/B breakpoints plus CJK). Compose with
   `string.format("%s (%s)", a, b)` or `FontString:SetFormattedText`. Put this in core
   (`SoulUI.FormatNumber`) so unit frames and nameplates share it.
4. **Refresh model:** one shared ticker for all meter windows, default 1.0 s, user minimum
   0.5 s, running only while (player or group) in combat and something is visible. A separate
   cheap clock update for the header timer. Out of combat refresh only on
   `DAMAGE_METER_COMBAT_SESSION_UPDATED`, `DAMAGE_METER_CURRENT_SESSION_UPDATED` (debounced
   ~0.1 s) and `DAMAGE_METER_RESET`. Hidden windows mark themselves stale and catch up on show.
5. **Group-aware combat end:** keep polling after the player's regen until
   `IsGroupInCombat()` is false (with a ~5 s failsafe); treat `ENCOUNTER_START` as a hard
   boundary; use a generation counter for every delayed stop; handle `PLAYER_ENTERING_WORLD` and
   PvP match end.
6. **Timer:** read `GetSessionDurationSeconds(Current)` live, pin it at combat end. Do not run
   our own stopwatch.
7. **Secret rules for rows:** text and values go straight to sinks; skip memo comparisons when a
   value is secret; never index tables by name/GUID/spellID without `issecretvalue` checks;
   class colour from `classFilename` (NeverSecret) but still guard; class/spec icon from
   `specIconID`.
8. **Breakdowns:** full breakdown out of combat. In combat, support at least **your own row**
   by substituting `UnitGUID("player")`. Treat the class:spec GUID map and the season NPC-ID
   table as optional later work (they need per-season maintenance). Show a clear "details are
   hidden during combat" message otherwise.
9. **Refresh snapshot data on `ADDON_RESTRICTION_STATE_CHANGED`** (combat restriction lifted),
   not only on `PLAYER_REGEN_ENABLED`, since declassification lags regen.
10. **Rendering:** fixed row pool (40), visible-range painting, a style cache key so per-tick work
    is only `SetValue`/`SetText`, per-row memos including spec, pixel-snapped stride. Pinned
    self row is a cheap, popular feature.
11. **Parity scope for v1:** windows (start with up to 3), 8 meter types, Current/Overall plus
    history segments, auto reset on key start, M+ auto segment swap, value formats 0-3, class
    colours, spec icons, click-through breakdown with death recap
    (`C_DeathRecap.GetRecapEvents`), hover tooltip, reset button and keybind, visibility rules.
    Defer: value gradient, Spell History, stock style variants, enemy breakdown in combat.
12. **Add a report-to-chat feature** EllesmereUI lacks, available **out of combat only** (values
    are plain then; `C_ChatInfo.InChatMessagingLockdown()` must be false).

### 17.2 Action bars (high risk; design before coding)

1. **Decide early:** own buttons (EllesmereUI approach: `ActionBarButtonTemplate,
   SecureActionButtonTemplate`, ID 0, explicit `action` attribute) versus reskinning Blizzard's.
   Owning buttons avoids cross-addon taint on Blizzard's protected buttons but obliges us to
   reproduce paging, keybind routing, cooldown painting and broadcaster cleanup. Recommended
   path for SoulUI: own buttons, but **start from the cleanup list in 2.3-2.4 as a checklist**
   (remove from `ActionBarButtonEventsFrame.frames` by nil-in-place, unregister the template's
   cooldown/slot events, neuter `UpdateButtonArt` on our buttons only).
2. **Hide stock bars by reparenting to a hidden frame at file load**, never `Hide()`. Keep
   `MainActionBar` in place at alpha 0 with mouse disabled (and its pager arrows) because native
   `ACTIONBUTTON` bindings still fire through its buttons; mirror `actionpage` onto it from the
   paging snippet.
3. **Keybinds:** native binding commands for standard bars (needed for empowered spells and
   spell queueing); `SetOverrideBindingClick` only for custom bars, custom paging and flyouts.
   Cache a routing signature to avoid rebuilding on every `ACTIONBAR_SLOT_CHANGED`.
4. **Paging:** `SecureHandlerStateTemplate` bar + `RegisterStateDriver(bar, "page", ...)` +
   `ChildUpdate` that rewrites `action`. Put manual `[bar:N]` clauses before `[bonusbar:5]`. Never
   `CallMethod` from the page snippet.
5. **Cooldowns: duration objects only.** `C_ActionBar.GetActionCooldownDuration` into
   `Cooldown:SetCooldownFromDurationObject`; re-push while active (no change gate); clear on the
   falling edge. Charges via `GetActionChargeDuration` on a second Cooldown. Desaturate/dim via a
   `C_CurveUtil` step curve evaluated with `EvaluateTotalDuration`, threshold = hasted GCD + margin.
6. **One central dispatcher** for cooldown, usable, slot-changed and page events with a slot to
   button map; per-button registration only for the cheap state events. Range via
   `C_ActionBar.EnableActionRangeCheck` + `ACTION_RANGE_CHECK_UPDATE`, disabled for hidden bars.
7. **Combat:** all binding, layout and attribute writes through `SoulUI:RunAfterCombat` with
   keyed de-duplication (their keyed `CombatQueue.Defer` is a good shape for our core queue).

### 17.3 Other modules

- **Mythic+ timer:** drive from a `hooksecurefunc` on `ChallengeModeBlock.UpdateTime` with a
  1 s throttled fallback; `GetWorldElapsedTime(1)`; `C_ScenarioInfo.GetCriteriaInfo`;
  `C_ChallengeMode` for limits, affixes and deaths. Adopt the **stacked StatusBar segments**
  technique for the pull bar (sum secrets visually). Hide the objective tracker with alpha in
  combat and a deferred real hide.
- **Secret-sum and secret-compare idioms** worth adding to SoulUI core helpers:
  stacked fills anchored edge to edge (visual addition); hidden StatusBar with value=before,
  max=after plus a clip on the fill edge (visual "did it change"); `SetAlphaFromBoolean`;
  `C_CurveUtil` colour/step curves; `SetTimerDuration` on duration objects.
- **Chat:** if we restyle chat, follow their doctrine (one `hooksecurefunc` on `AddMessage`,
  alpha-only suppression, no fields on Blizzard frames, secret lines pass through whole). A
  lighter v1: skin only, no custom message renderer.
- **Quest tracker:** skin Blizzard's tracker via hooks rather than replacing it (they abandoned a
  custom tracker). Position via Edit Mode layouts.
- **Bags:** large; defer. If built, use `BAG_UPDATE_DELAYED` batching, category by
  `Enum.ItemClass` IDs (locale-safe), and keep offline inventories in a separate SavedVariable
  from profiles.
- **Minimap:** `SetMaskTexture` plus blob ring scalars for square; hook `SetPoint`/`SetParent`
  to re-assert placement; collect `LibDBIcon10_*` buttons into a flyout.
- **Data bars:** a single heartbeat that exists only while blocks are registered; LDB support
  gets most third-party plugins for free.
- **Buff reminders:** use `C_Secrets.ShouldSpellAuraBeSecret` per spell and a pre-combat
  snapshot; never show a reminder from an absent secret aura.
- **QoL ideas cheap to copy as features:** battle res pool icon, Sated tracker, combat
  enter/leave alert, group death announcer (poll alive to dead), hide error spam per message
  type, auto combat logging, durability warning.
- **Skip:** Forever Essentials (other client), stock style variants, the 14k-line window packs.

### 17.4 Localization

Copy the *approach*, not the code: `L` callable with English-as-key and fallback, `Lf` with
positional format specifiers, a LoadOnDemand `SoulUI_Locales` addon whose toc lines carry
`[AllowLoadTextLocale ...]`, per-module locale files that return early when that module is
disabled, and a slash command that dumps untranslated keys.

### 17.5 Cross-cutting engineering habits to adopt

- Split large modules into files, using a per-module internals table with a `broken` guard so one
  file's load error stops later files cleanly.
- Weak-keyed side tables for any state about Blizzard frames.
- Every optional feature registers nothing until enabled; tickers exist only with listeners.
- `debugprofilestop()` budget checks on expensive C calls, deferring paint one frame on spikes.
- Document every taint lesson inline, as they do; the comments are why their code survives
  patch churn.
