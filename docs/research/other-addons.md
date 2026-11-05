# Other Addons Research: Raid Tools, Profile Installers, Boss Mods, Media

Scope: the user's installed addons that sit around the core UI suite. That means ExwindCore, Northern Sky Raid Tools (NSRT + NSRT_UI), the WagoUI family (WagoUI, WagoUI_Storage, WagoAppCompanion), BigWigs (Plugins, Core, a quick look at the loader), MythicDungeonTools (briefly), and SharedMedia_MusclebrahTV. It also covers the user's current EllesmereUI configuration, read from WTF SavedVariables.

Client target: retail 12.1.5 (Interface 120105), Midnight, with secret-value restrictions.

Research date: 2026-11-04. All paths are relative to
`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\` unless noted. Line numbers
refer to the versions installed on that date.

> Ground rule for SoulUI: we study patterns and API usage here, not code. Several of these addons
> are **All Rights Reserved** (BigWigs, NSRT, ExwindCore by default). Even the GPL ones (WagoUI,
> MDT) would force GPL on SoulUI if we copied code. We write everything ourselves from the
> patterns described below.

---

## 0. Quick reference table

| Addon | Version | Interface | License | SavedVariables | Role |
|---|---|---|---|---|---|
| ExwindCore | 6.0.0 (`.wago`: v26.10.28.2259) | 120105, 120100 | **No license file, so All Rights Reserved by default** | `EXCORE12S2` | Rendering/GUI framework for the Exwind tool suite (EXBoss etc.) |
| NorthernSkyRaidTools | 12.1.32 | 120105, 16001 | **All Rights Reserved** (c) 2026 Reloe | `NSRT`, `NSRTTimelineData` | Raid tools: reminders, nicknames, aura tracking/glows/sounds, encounter alerts |
| NorthernSkyRaidTools_UI | 12.1.32 | 120105, 16001 | **All Rights Reserved** | (none) | Load-on-demand options UI for NSRT |
| WagoUI | 1.9.2 | 120105, 120100, 50504, 20506, 11509 | **GPL v2** | `WagoUIDB`, `WagoUICDB` (per char) | UI pack installer |
| WagoUI_Storage | 1.0.0 | 120100… | (generated data, Wago) | none (it is a global table written by the Wago App) | Pack payloads |
| WagoAppCompanion | 1.0.0 | 120100… | (generated, Wago) | none | WeakAuras companion data (empty here) |
| BigWigs (+Core, Plugins) | toc-driven | 11508…120107 | **All Rights Reserved**. The toc says: "You are free to fork and modify on GitHub, please ask us about anything else." | `BigWigs3DB` etc. | Boss mod |
| MythicDungeonTools | 6.3.27 | 120107, 120105 | **GPL v2** | `MythicDungeonToolsDB` | M+ route planner |
| SharedMedia_MusclebrahTV | 2.2.9 | 120000…120105, 16001, 20506 | No addon license. Font is **SIL OFL 1.1** (Mozilla/Telefonica, i.e. Fira Sans lineage) | `MuscleUIDB` | LSM media pack for the "MuscleUI" Wago pack |

---

## 1. Embedded libraries (with versions)

Versions come from the `MINOR` constant passed to `LibStub:NewLibrary`. When several copies are loaded, the highest MINOR wins at runtime.

### ExwindCore (`ExwindCore/libs/`)
| Library | Version (MINOR) | License notes |
|---|---|---|
| LibStub | 2 | Public domain |
| CallbackHandler-1.0 | 8 | BSD-ish (Ace) |
| AceLocale-3.0 | 6 | Ace3 BSD |
| LibDataBroker-1.1 | 4 | Public domain-ish |
| LibDBIcon-1.0 | 56 | All rights reserved / free use (Rabbit) |
| LibDeflate | 3 (1.0.2) | zlib (LICENSE.txt shipped) |
| LibSerialize | 7 | MIT |
| LibSharedMedia-3.0 | 12000005 ("12.0.0 v5") | LGPL 2.1 |
| LibRangeCheck-3.0 | 38 | MIT (LICENSE shipped) |
| LibSpecialization | 28 | BigWigs (All Rights Reserved, free to embed) |
| LibKeystone | 11 | BigWigs (All Rights Reserved, free to embed) |
| LibOpenRaid | 177 (CONST_LIB_VERSION) | GPL (LICENSE shipped) |

### NorthernSkyRaidTools (`NorthernSkyRaidTools/Libs/`)
| Library | Version |
|---|---|
| LibStub | 2 |
| CallbackHandler-1.0 | 8 |
| AceComm-3.0 | 14 |
| LibCustomGlow-1.0 | 25 (BSD, LICENSE shipped) |
| LibDBIcon-1.0 | 55 |
| LibDataBroker-1.1 | 4 |
| LibDFramework-1.0 (DetailsFramework) | dversion 752 (LICENSE shipped) |
| LibGetFrame-1.0 | 78 |
| LibRangeCheck-3.0 | 35 |
| LibSharedMedia-3.0 | 12000003 |
| LibSpecialization | 28 |
| LibTranslit-1.0 | 4 |
| IndentationLib | (For All Indents And Purposes; used for the notes/code editor) |

### WagoUI (`WagoUI/libs/`)
| Library | Version |
|---|---|
| AceAddon-3.0 | 13 |
| AceComm-3.0 | 14 |
| AceConfig-3.0 / AceConfigCmd-3.0 | 3 / 14 |
| AceConsole-3.0 | 7 |
| AceDB-3.0 | 39 |
| AceDBOptions-3.0 | 17 |
| AceEvent-3.0 | 4 |
| AceGUI-3.0 | 41 |
| AceLocale-3.0 | 6 |
| AceSerializer-3.0 | 5 |
| AceSerializer-3.0Async | 5 (Wago fork, coroutine-friendly) |
| AceTimer-3.0 | 17 |
| CallbackHandler-1.0 | 8 |
| **LibAddonProfiles** | **19** (the Wago integration layer; see section 4) |
| LibAsync | 5 |
| LibDBIcon-1.0 | 57 |
| LibDFramework-1.0 | dversion 767 (LGPL 2.1 LICENSE in this copy) |
| LibDataBroker-1.1 | 4 |
| LibDeflate / LibDeflateAsync | 3 / 3 |
| LibSerialize | 7 |
| LibSharedMedia-3.0 | 12000004 |
| LibWagoFramework | 1 |

### BigWigs (`BigWigs/Libs/`, `BigWigs_Plugins/Libs/`)
| Library | Version |
|---|---|
| AceDB-3.0 | 39 |
| CallbackHandler-1.0 | 8 |
| LibDBIcon-1.0 | 57 |
| LibDataBroker-1.1 | 4 |
| LibDualSpec-1.0 | 35 |
| LibDurability | 5 |
| LibKeystone | 11 |
| LibLatency | 5 |
| LibSharedMedia-3.0 | 12000005 |
| LibSpecialization | 29 |
| LibCandyBar-3.0 (Plugins) | 110 |
| LibCustomGlow-1.0 (Plugins) | 25 |
| LibSink-2.0 (Plugins) | 120001 |

### MythicDungeonTools (`MythicDungeonTools/libs/`)
AceComm-3.0 14, CallbackHandler-1.0 8, LibAsync 5 (GPL, LICENSE shipped), LibDBIcon-1.0 57,
LibDataBroker-1.1 4, LibSharedMedia-3.0 12000005, LibStub. Since 6.x MDT ships no AceSerializer or
LibDeflate. It uses `C_EncodingUtil` instead (section 6).

### SharedMedia_MusclebrahTV (`libs/`)
LibStub, CallbackHandler-1.0 **6** (old), LibSharedMedia-3.0 **6010002** ("6.1.0 v2", very old).
These are harmless because a newer LSM copy from another addon wins via LibStub. Still, a
standalone install of this pack would run an ancient LSM.

**What this means for library choices**
- **LibSharedMedia-3.0 12000005** is the current 12.x-aware build. SoulUI should embed that MINOR or newer.
- Newer addons (NSRT, MDT, BigWigs profiles) have **dropped LibSerialize/LibDeflate/AceSerializer
  for serialization in favor of `C_EncodingUtil`** (CBOR + Deflate + Base64). The Wago guide also
  recommends this (section 4). SoulUI should do the same and skip the codec libs completely.
- LibCustomGlow-1.0 v25 is the shared glow lib. LibSpecialization 28/29 (BigWigs) is the de-facto
  group-spec sync lib.

---

## 2. ExwindCore

### 2.1 Architecture
ExwindCore is the shared engine behind the Exwind tool suite (EXBoss, MythicCast and others). It is about
70,600 Lua lines across ~70 core files and is written mostly in Chinese with English comments
in newer code. The TOC load order *is* the architecture:

1. `libs/load_libs.xml`, then locales (11 languages; zhCN is the source locale).
2. **Main engine**: `ExwindTools_Metadata`, `ExwindTools`, **`ExwindCapability`**, GUI color/metrics/icons, panel theme, visual layers, media, unit-frame helpers, nameplate/unit anchors, **`ExwindEvent`**, bug report, **`ExwindFrameTask`**, changelog.
3. **DB and state**: `ExwindDB` (static class/spec data with localized names and icons), **`ExwindState`** (a reactive state store: `ExwindTools:UpdateState("InMythicPlus", ...)`), `ExwindEditMode`.
4. **Widgets and settings**: frame pool, virtual list/table, GUI, settings list, color picker, choice groups, tree, texture catalog/browser, then a "Renderer" layer (`ExwindWidgets`, `RegionElements`, `IconCollection`, `TimerBarCollection`, `StackBarCollection`, `RingCollection`, `TextCollection`, `SecureActionPanelWidget`, `CentralRender*`, `AnchorController`, `ModuleDefinition`), then the unified panel and router.
5. **Config**: `ExwindExport` (profile strings), `PartySync`. `PartySpec` is commented out in the TOC ("temporarily disabled while investigating memory growth").

Design highlights:
- **Module definitions plus central renderers.** Feature modules (in other addons) declare
  widget models. ExwindCore owns the frame pools and renders them (`ExwindModuleDefinition.lua`,
  `ExwindCentralRender.lua`). The module never touches the frames directly. That is how they keep
  secret-value handling in one place.
- **Runtime capability probing** (`Core/ExwindCapability.lua`). This is the most reusable idea here (2.2).
- **Frame-budgeted coroutine tasks** (`Core/ExwindFrameTask.lua:1-40`). `EXUI:StartFrameTask(name, budgetMs, func, onError)` runs a coroutine and advances it each frame until a per-task millisecond budget is spent. Starting a task with the same name cancels the old one. Use this for heavy work like building option pages or importing profiles.
- **Event bus with owner bindings** (`Core/ExwindEvent.lua:15-30`). `ExwindTools:RegisterEvent(event, owner, func)` supports real and "virtual" events, plus per-unit bindings with owner bookkeeping, so teardown is cheap.
- **Virtual list** (`Core/GUI/ExwindVirtualList.lua`): event-driven, reusable rows, row count = `ceil(height/rowHeight)+overscan`.
- **Edit mode** (`Core/Renderer/ExwindEditMode.lua`). It has its own "world preview" overlay with staged module hooks (`RunEditModeModuleStage`, line 130), and each stage reports failures per module instead of erroring globally.

### 2.2 12.x API usage and secret-value workarounds

| Technique | Location | Notes |
|---|---|---|
| Capability registry: `Capability:Register(name, probe)`, `:RefreshAll()` on login, `:Has(name)` | `Core/ExwindCapability.lua:4, 77-98` | Each probe is `pcall`ed. Failures are stored in `Capability.Diagnostics[name]` with a reason string. |
| Probe `C_DurationUtil.CreateDuration` plus methods `HasSecretValues/GetRemainingDuration/...` | `ExwindCapability.lua:100-104` | Gates the duration-object pipeline. |
| Probe `C_DurationUtil.CreateDurationTextBinding`, `C_StringUtil.CreateSecondsFormatter`, `CreateNumericRuleFormatter`, `Enum.DurationTextBindingProperty`, `Enum.SecondsFormatter*` | `ExwindCapability.lua:106-118` | Native countdown text with no Lua OnUpdate. |
| Probe `C_CurveUtil.CreateColorCurve` plus `binding:SetTextColorCurve` | `ExwindCapability.lua:120-127` | Threshold coloring of secret durations. |
| Probe Blizzard `AuraContainer` / `CustomAuraContainerTemplate` / `CustomAuraButtonTemplate` methods (`SetUnit`, `AddAuraGroup`, `SetAuraProcessingPolicy`, flow layout, `SetDurationText/Bar/Cooldown`, `AddPandemicRegion`, `AddDispelTypeTexture`) | `ExwindCapability.lua:38-75, 135-180` | Probe frames are created lazily and **deferred while `InCombatLockdown()`** (lines 44-47, 64-67). |
| `C_UnitAuras.AddAuraSound/RemoveAuraSound` plus `Enum.UnitAuraSoundTrigger` | `ExwindCapability.lua:182-185` | |
| `StatusBar:SetTimerDuration`, `Enum.StatusBarTimerDirection`, `Enum.StatusBarInterpolation` | `ExwindCapability.lua:192-198` | |
| Radial status bars: `SetRenderMode(Enum.StatusBarRenderMode.Radial)`, `SetRadialProgressBar*` | `ExwindCapability.lua:200-205` | Rings without custom shaders. |
| `C_Secrets.ShouldAurasBeSecret()` (pcall'd) published into the state store as `AuraSecretsActive` | `Core/ExwindState.lua:1250-1261, 1840-1845` | One central flag that every module reads. |
| **Duration object drives StatusBar fill natively**: `bar:SetTimerDuration(durationObject, interpolation, direction)` then `bar:SetToTargetValue()` | `Core/Renderer/ExwindWidgets.lua:2557-2570` | The comment explains that a pooled bar keeps its previous rendered value unless you snap it with `SetToTargetValue()` once. After that the C++ timer owns every frame and **no Lua reads the secret remaining time**. |
| **Lesson learned**: `DurationTextBinding` on a pooled FontString caused `FontString:SetText(): Font not set` taint after release | `ExwindWidgets.lua:740-746` | The native binding fired one more queued update after `SetToDefaults()` had cleared the font. They rolled back to a stripped `Cooldown` frame (swipe/edge/bling off, numbers only) as a "SecretCountdownWidget". Takeaway: **clear and disable bindings before releasing pooled FontStrings, and never `SetToDefaults` a FontString that still has a live binding.** |
| `SetAlphaFromBoolean(secretBool, trueAlpha, falseAlpha)` | `ExwindWidgets.lua:272, 665, 2937-2938`; `ExwindRegionElements.lua:421, 619`; `ExwindTimerBarCollection.lua:249-250` | Show/hide driven by a secret boolean. **Pattern**: before applying, reset pooled widgets to `SetAlpha(1)` (`ExwindWidgets.lua:2920-2925`), because a secret alpha from the previous use carries over. |
| `issecretvalue` guards on anchor math (secret coords are refused) | `Core/Renderer/ExwindAnchorController.lua:121, 162` | |
| Preview models must not contain secrets (hard assertion) | `Core/Renderer/ExwindStandardPreview.lua:81-98` | Test/preview data is validated as "plain values only". |
| Bug-report scrubber replaces secrets with a placeholder before serializing stack/locals | `Core/ExwindBugReport.lua:40-124` | SoulUI's error handler needs the same thing. Never `tostring` a secret. |
| `C_ChatInfo.InChatMessagingLockdown()` gate before addon comms | `Core/PartySync.lua:552, 598` | Messages are queued and flushed when the lockdown lifts. |
| `ExwindRingCollection` hands Duration objects straight to `SetTimerDuration` ("no Lua timing") | `Core/Renderer/ExwindRingCollection.lua:6, 152` | |

### 2.3 Profile export format
`Core/ExwindExport.lua`: prefix `!EX1!` (line 20). Pipeline: LibSerialize, then LibDeflate `CompressDeflate`, then `EncodeForPrint` (lines 104-115). The export lets the user pick modules and adds `profileName/authorName/note`. Import (`ParseImportString`, line 131) checks the prefix first, shows a summary (`GetImportSummary`, line 184), then applies with a `mergeMode` (`ApplyImport`, line 218, which uses `DeepMerge`). **Patterns worth taking**: per-module selective import, a summary screen before applying, and merge vs. replace.

### 2.4 UI patterns worth adopting
- Capability probes with diagnostics that a `/soul debug` page can show (which 12.x APIs exist on this client build).
- A central renderer owns all frames. Modules emit declarative models, so secret handling lives in one layer.
- Frame-budgeted coroutines for any heavy UI build.
- Virtualized lists for long option lists (spell lists, aura filters).
- "Pooled widget hygiene": reset alpha, bindings, and scripts on acquire, not only on release.

### 2.5 License
There is no LICENSE file, and the `.wago` metadata has no license. Treat it as **All Rights Reserved**: patterns only, no code.

---

## 3. Northern Sky Raid Tools (NSRT + NSRT_UI)

### 3.1 Architecture
- **Two-addon split**: `NorthernSkyRaidTools` (runtime, ~17.7k lines in the root files plus encounter files) and `NorthernSkyRaidTools_UI` (`## LoadOnDemand: 1`, `## Dependencies: NorthernSkyRaidTools`). The runtime calls `NSI:LoadUI(showOptions, pendingTabName)` (`NorthernSkyRaidTools.lua:92-117`). That function uses `C_AddOns.LoadAddOn`, guards against reentrancy (`UILoading`), and keeps a `PendingShow/PendingTabName` while the UI is still initializing. The UI addon's first file, `UI/Bootstrap.lua` (`[Bootstrap]` tag in the TOC), registers itself back onto the runtime namespace (`NSI.UIBootstrap = UI`).
- **Per-file game-type gating in the TOC**: `File.lua [AllowLoadGameType standard]`, together with `## AllowLoadGameType: standard, camelot`. This is the modern way to ship one package across clients without `if WOW_PROJECT_ID` checks.
- `## Category:` with localized `Category-xxXX` lines groups the addon in the 12.x AddOn list.
- Feature files: `Reminders`, `NickNames`, `AuraTracking`, `AuraGlows`, `AuraSounds`, `InterruptDisplay`, `CooldownCheck`, `ReadyCheck(Consumables)`, `BreakTimer`, `PaceComparison`, `BossTimelines/*` (static timeline data per season), `EncounterAlerts/MidnightS1|S2/*.lua` (one file per boss, each registering `DetectPhaseChange[encounterID]` and alert logic), and `Profiles.lua`.
- Public API on the global `NSAPI` (nicknames: `NSAPI:Shorten`, `GetName`, `GetChar`; TTS: `NSAPI:TTS`; callbacks: `NSAPI.RegisterCallback`; profiles, see 3.3). Unit-frame addons (Grid2, ElvUI, Cell, DandersFrames, VuhDo, UUF) are `OptionalDeps` so NSRT nicknames can show on their frames.

### 3.2 12.x API usage and secret-value workarounds

| Technique | Location |
|---|---|
| `NSI:Restricted()` is a thin wrapper over `C_Secrets.ShouldAurasBeSecret()`, used as "are we in a restricted encounter right now" | `Functions.lua:66-68` |
| **Encounter Timeline**: registers `ENCOUNTER_TIMELINE_EVENT_ADDED/REMOVED/STATE_CHANGED` | `EventHandler.lua:13-15` |
| Filters to `info.source == Enum.EncounterTimelineEventSource.Encounter` and records script/custom events in `CustomEvents` so their removal is ignored | `EventHandler.lua:438-468` |
| `C_EncounterTimeline.GetEventState(eventID)`. A `Canceled` state is treated as removal | `EventHandler.lua:463-467` |
| Counts active encounter events via `GetEventList/GetEventInfo/GetEventState` | `Functions.lua:108-117` |
| **Phase detection from timeline events**. Per-boss handlers look at event add/remove timing and `info.duration` (not secret) to infer phase changes, e.g. `addedcount >= 8 or info.duration == 60` | `EncounterAlerts/MidnightS1/CrownOfTheCosmos.lua:119-155`; `MidnightS2/Kithix.lua:104` (`Enum.EncounterTimelineEventState.Canceled`) |
| **Secretness as a signal**: `issecretvalue(GetRaidTargetIndex(unit))` stands in for "this unit has a raid marker" when the value itself is hidden | `EncounterAlerts/MidnightS2/TheCoiledAltar.lua:782, 859-862, 884, 897, 998` |
| `SetAlphaFromBoolean(interruptible, 0, 1)` on nameplate text when the interruptible flag is secret | `EncounterAlerts/MidnightS1/FallenKingSalhadaar.lua:62-64, 85-87` |
| Bail out early on secret `UnitExists`/`UnitIsUnit` results | `MidnightS2/Sszorak.lua:391`, `Ulatek.lua:218, 1061-1067` |
| Step color curve for duration text: `C_CurveUtil.CreateColorCurve()`, `SetType(Enum.LuaCurveType.Step)`, points at 0 and the threshold, bound to `Enum.DurationTextBindingProperty.RemainingDuration` | `AuraTracking.lua:878-887` |
| `C_StringUtil.CreateNumericRuleFormatter()` with breakpoints (`%dm` above 60s) for native duration text | `AuraGlows.lua:17-30` |
| Blizzard `AuraContainer`: `CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")`, `SetUnit`, `SetAuraProcessingPolicy(CustomAuraContainerAuraProcessingPolicy.ProcessAura)` | `AuraGlows.lua:916-932` |
| Loads `Blizzard_AuraContainer` on demand before using it | `AuraGlows.lua:1004-1011`; `AuraTracking.lua:1817-1819` |
| `button:SetDurationText(duration, {textFormatter = ...})` on aura buttons | `AuraGlows.lua:764`; `AuraTracking.lua:1797` |
| `C_UnitAuras.AddAuraSound(trigger, {unitToken, spellID, soundFileName, outputChannel, throttleSeconds})` (throttle clamped 0-5s) | `AuraSounds.lua:505-521` |
| `C_ChatInfo.InChatMessagingLockdown()` gates on break-timer and sync sends, with pending flags flushed later | `BreakTimer.lua:168, 259, 270`; `EventHandler.lua:279, 407` |
| Comms with `C_EncodingUtil`: CBOR, then Deflate (`OptimizeForSize`), then Base64 `StandardUrlSafe`. Each stage is `pcall`ed on receive, and messages with characters outside `[A-Za-z0-9_-=]` are rejected (old versions) | `Comms.lua:7-32` |
| Fake whispers: whisper payloads go over `RAID` on a separate prefix and are filtered on receive | `Comms.lua:18-20` |
| `issecretvalue` guards in name shortening and TTS (secret names return empty) | `Functions.lua:132-134, 286, 341` |

### 3.3 Profiles and the Wago-compatible API
- Export string: `"!NSRT:" .. exportType .. ":" .. base64url(deflate(cbor(data)))` (`Functions.lua:559-563`). On decode, a pre-12.1.5 string gets a localized "can no longer be imported" message (`Functions.lua:565-579`). **Typed prefixes** (`Profile`, alerts, etc.) let one codec serve several kinds of import.
- `CopySerializableValue` (`Functions.lua:~540-557`) deep-copies only serializable values before CBOR, with cycle protection via a `copies` table.
- **NSRT implements the full WagoUI ImplementationGuide API on `NSAPI`** (`Profiles.lua:840-905`): `ExportProfile`, `ImportProfile` (routes through the LoD UI's import popup, or queues `PendingProfileImport` while the UI initializes), `DecodeProfileString`, `SetProfile`, `GetProfileKeys`, `GetProfileAssignments`, `GetCurrentProfileKey`, `OpenConfig`, `CloseConfig`, `ProfileExists`. NSRT has **no module yet in WagoUI's LibAddonProfiles 19**. Exposing the API is necessary but not enough: the Wago team must also add a module file (section 4.5).
- Profile system: `NSRT.Profiles[name]`, `NSRT.ProfileKeys[char]`, `NSRT.CurrentProfile`, plus `RunProfileMigrations` and `AddMissingDefaults/AddMissingTableDefaults` (`Profiles.lua:141-149, 646`).

### 3.4 UI patterns worth adopting
- Split the options UI into a load-on-demand addon. This saves memory and login time, and the runtime stays small.
- A per-boss file layout that registers into tables keyed by encounter ID.
- Typed import prefixes with a clear "too old to import" message.
- Users can preview/test (`NSAPI:OpenAlert`, `NSAPI:DebugEncounter(id)`).

### 3.5 License
`LICENSE`: "All Rights Reserved, Copyright (c) 2026 Reloe" (both addons). Patterns only.

---

## 4. WagoUI, WagoUI_Storage, WagoAppCompanion: how profile installs work

This section matters most for making SoulUI Wago-compatible.

### 4.1 The pieces
- **WagoUI_Storage** (`main.lua`, ~410 KB here). The **Wago desktop app writes this file**. It contains a single global `WagoUI_Storage = { [packId] = pack, ... }`. The installed pack here is `"Ndl83W1g"` = "MuscleUI - Midnight". Structure:
  ```
  pack = {
    localName, createdBy, gameVersion = 120105, gameFlavor = "retail",
    resolutions = { chosen = "any", enabled = { ["1080"]=false, ["1440"]=false, ["2160"]=false, any=true } },
    profileKeys     = { [resolution] = { [moduleName] = "MuscleUI" } },
    profiles        = { [resolution] = { [moduleName] = "<profile string>" } },
    profileMetadata = { [resolution] = { [moduleName] = { lastUpdatedAt = <unix> } } },
    releaseNotes    = { [unixTimestamp] = "<text>" },
  }
  ```
  `moduleName` is the **LibAddonProfiles module name** ("EllesmereUI", "BigWigs", "BigWigs Boss Options", "Blizzard Edit Mode", "Plater", ...). This pack's payloads: EllesmereUI (`!EUI_...`, ~194 KB for "any" and ~48 KB for 1080/2160 variants), BigWigs (`BW2:...`), BigWigs Boss Options (`BWB1:...`), and Blizzard Edit Mode (a raw Edit Mode export string).
- **WagoUI** (installer UI). It reads `WagoUI_Storage` (`modules/wagoData.lua:92-170`) and builds per-resolution import state. For each module it calls `LAP:GetModule(moduleName)` and asks `needsInitialization()`, `isLoaded()`, `isUpdated()`.
- **WagoAppCompanion**. `data.lua` holds an empty `WagoAppCompanionData`, and `init.lua` passes it to `WeakAuras.AddCompanionData` on `ADDON_LOADED`. It is only relevant to WeakAuras, not to us.

### 4.2 The install loop (`wagoFrames/introFrame/installPage.lua:15-80`)
1. If any checked module's addon is not loaded, the page offers "Enable AddOns". It runs `LAP:EnableAddOns(lap.addonNames)` and then `ReloadUI()`.
2. Otherwise "Install Profiles": refuse when `InCombatLockdown()`. Run async (`addon:Async`), iterate the modules sorted by name, and for each checked module that is loaded and up to date call
   `lap:importProfile(profileString, profileKey, true)`.
   - If it **returns `false`**, WagoUI prints "Skipped" (so our import may decline).
   - Otherwise it disables `conflictingAddons`, records `lastUpdatedAt` in `WagoUIDB.importedProfiles[char][pack][resolution]`, and if `needReloadOnImport` is set shows a reload indicator. **WagoUI performs a single reload at the end.**
3. Version gate: `private:GenericVersionCheck(module)` (`libs/LibAddonProfiles/Utils.lua:128-138`) compares the addon's TOC `Version` (semver compare via `IsSemverSameOrHigher`) against `module.oldestSupported`. **`@project-version@` is treated as up to date.** So **SoulUI's TOC `## Version:` must be semver-parseable** (e.g. `1.4.2` or `v1.4.2`).

### 4.3 The contract: `ImplementationGuide.lua` (verbatim behavior, paraphrased)
WagoUI asks each addon to expose a **global API table** with these methods. NSRT (`NSAPI`) and NorskenUI (`NorskenUIAPI`) both follow it. EllesmereUI exposes the same functions on its main `EllesmereUI` global.

| Method | Required behavior |
|---|---|
| `API:ExportProfile(profileKey) -> string` | Export **any named profile**, not only the active one. Use `"Global"` if the addon has no profile system. |
| `API:ImportProfile(profileString, profileKey)` | Import, **create/overwrite the profile named `profileKey`, and make it active**. **Must not call `ReloadUI()`**, because WagoUI batches reloads. May return `false` to decline. |
| `API:DecodeProfileString(profileString) -> table` | Decode to a plain table. WagoUI uses it for diffing and creator changelogs. |
| `API:SetProfile(profileKey)` | Activate an existing profile. |
| `API:GetProfileKeys() -> {[key]=true}` | All profile names. Return `{Global=true}` if there are no profiles. |
| `API:GetProfileAssignments() -> {[charKey]=profileKey} or nil` | Lets WagoUI restore per-character selections on alts. |
| `API:GetCurrentProfileKey() -> string` | Active profile (or `"Global"`). |
| `API:OpenConfig()` / `API:CloseConfig()` | Open/close options. Leave empty if config lives in Edit Mode. |

The guide **recommends `C_EncodingUtil`**: `SerializeCBOR`, then `CompressString(Deflate, OptimizeForSize)`, then `EncodeBase64`. The reverse is `DecodeBase64`, `DecompressString(Deflate)`, `DeserializeCBOR`. It also **requires that strings from this API are 100% compatible with the addon's own in-game import box.**

### 4.4 The module side (`libs/LibAddonProfiles/modules/EllesmereUI.lua`)
Each supported addon has a module table in WagoUI's library:
```
moduleName="EllesmereUI", wagoId="ZKbxbRN1", oldestSupported="8.7.8",
addonNames={"EllesmereUI"}, conflictingAddons={}, icon=GetAddOnMetadata(...,"IconTexture"),
slash="/eui", needReloadOnImport=true, needProfileKey=true, preventRename=false,
willOverrideProfile=true, nonNativeProfileString=false, needSpecialInterface=false,
isLoaded, isUpdated (GenericVersionCheck), needsInitialization,
openConfig/closeConfig/getProfileKeys/getCurrentProfileKey/isDuplicate/setProfile/
importProfile/exportProfile -> all xpcall(EllesmereUI.X, geterrorhandler()),
areProfileStringsEqual -> DecodeProfileString both + private:DeepCompareAsync(a, b, ignoredKeys)
```
EllesmereUI passes **ignored keys** to the diff (`_migrations`, `_capturedOnce`, `_capturedOnce_EAB`, `_capturedOnce_CDM`, `_dormantMerged`, `_barFilterModelV6`) so that bookkeeping fields don't show up as changes. **Lesson: keep migration flags and internal bookkeeping under clearly prefixed keys (`_`) so pack diffs stay clean.**

`CompressionUtils.lua` also provides generic codecs that WagoUI uses for addons without a native string: `GenericEncode` (AceSerializer + LibDeflateAsync + `EncodeForPrint`, lines 11-23), `GenericDecode` (optionally LibSerialize, lines 35-48), and `BlizzardDecodeB64CBOR` (lines 66-77). Everything is async/coroutine-based so big profiles don't freeze the client.

### 4.5 What SoulUI must do to be Wago-compatible
1. Expose a global `SoulUIAPI` (or methods on `SoulUI`) with **all 10 methods** in 4.3, matching the semantics exactly. In particular: import activates the profile, nothing reloads, and import may return `false`.
2. Use one codec everywhere: e.g. `"!SOUL1:" .. Base64(Deflate(CBOR(payload)))`, with the same string for the in-game import box and the API.
3. Keep `## Version:` semver and publish on Wago (TOC `## X-Wago-ID:`), so a `wagoId` exists for the module.
4. Ask the Wago team (or open a PR on the WagoUI repository) to add `libs/LibAddonProfiles/modules/SoulUI.lua`. **WagoUI only knows addons that have a module there.** NSRT already exposes the API but has no module yet, which shows that the module step is separate. Supply `oldestSupported`, `slash`, `needReloadOnImport` (true if we rebuild frames on reload), and the `_`-prefixed ignore list.
5. If SoulUI replaces addons (e.g. a SoulUI nameplate module vs. Plater), consider asking for `conflictingAddons` in the module so WagoUI disables them on install.
6. Optional: support **resolution variants** by letting pack creators export separate profiles per resolution. WagoUI handles the selection. We only need named profiles.

---

## 5. BigWigs (Plugins, Core, Loader)

### 5.1 Architecture
- `BigWigs` is the always-loaded **loader** (`Loader.lua`, `Init_*.lua` per flavor, `API.lua`, locales, media). `BigWigs_Core` (`Core.lua`, `BossPrototype.lua` ~5.4k lines, `BossPrototype_Classic.lua`, `PluginPrototype.lua`) and `BigWigs_Plugins` load **on demand** when you enter a supported zone or open options. Boss packs (`BigWigs_TheVoidspire`, `BigWigs_MidnightLairs`, ...) are separate LoD addons.
- Plugins talk through an internal message bus (`self:SendMessage("BigWigs_StartBar", ...)`, `BigWigs_Message`, `BigWigs_StartConfigureMode`). Bars, Messages, Sound, Flash, Countdown, InfoBox, Timeline and Auras are all independent consumers.
- **TOC per-file flavor gating** (`[AllowLoadGameType classic]`, `[AllowLoadGameType standard]`, `[AllowLoadGameType mainline]`). In retail 12.x, **`Proximity.lua`, `Nameplates.lua`, `RaidIcon.lua`, and `AutoReply.lua` are classic-only**: BigWigs dropped retail proximity and nameplate features because range/positions and nameplate data are restricted. **`Timeline.lua`** (standard) and **`Auras.lua`** (mainline) are new for 12.x.

### 5.2 How BigWigs gets encounter data in 12.x
1. **`C_EncounterTimeline`** is the main timer source (`BigWigs_Plugins/Timeline.lua`):
   - Registers `ENCOUNTER_TIMELINE_EVENT_ADDED/STATE_CHANGED/REMOVED` when enabled (`:277-285`).
   - On ADDED (`:361-388`), with the plugin's own annotations: **not secret** are `source`, `id`, `duration`, `maxQueueDuration`. **Secret** are `spellID`, `spellName`, `iconFileID`, `icons` (role/spell indicators), `severity`, `isApproximate`. It ignores `source == 1` (Script) and renames EditMode (`source == 2`) test events.
   - It still **passes the secret `spellName` and `iconFileID` straight into its bars**. That works because FontString `SetText` and Texture `SetTexture` accept secrets. Lua never compares them.
   - STATE_CHANGED (`:390-410`) maps `Enum.EncounterTimelineEventState` Active/Paused/Canceled/Finished to Resume/Pause/Stop bar messages.
   - On enable, rebuilds bars from `GetEventList()` + `GetEventState()` + `GetEventInfo()` + `GetEventTimeRemaining()` (`:332-349`). This makes `/reload` mid-pull safe.
   - **Test mode** uses `C_EncounterTimeline.AddEditModeEvents()`, which returns a duration and is re-queued on a timer, and `CancelEditModeEvents()` (`Timeline.lua:216, 236`; `Bars.lua:404-415`). This is a free, official way to preview timers.
   - **Role/spell indicator icons** on bars: `C_EncounterTimeline.SetEventIconTextures(eventId, bitmask, textureList)` (`Bars.lua:1652`). Blizzard paints the secret icons into textures you provide.
   - Safety rule in Bars: **a bar whose text is secret must have an `eventId`**, otherwise it errors (`Bars.lua:1883-1888`). Secret bars can only be keyed and stopped by the timeline event ID, never by text.
2. **`ENCOUNTER_WARNING`** (Blizzard boss emotes and warnings as structured data). In `Messages.lua:982-1017`: `severity` is not secret. `text`, `casterName`, `targetName`, `iconFileID` are secret. It still class-colors the target via `GetPlayerInfoByGUID(targetGUID)` and builds the text with `string.format(text, casterName, targetName)`, which is allowed on secrets and returns a secret string. The plugin admits it "can't check if the message is targeting the player" anymore (comment at `:1001-1003`).
   - Boss modules use it for **secret target messages**: `boss:SecretTargetMessage` and the `ENCOUNTER_WARNING` capture window (`BossPrototype.lua:4425-4470`) briefly listen for the next warning and print "<spell> on <secret player>".
3. **Combat log** is still wrapped (`BossPrototype.lua:1497-1543`) but is only useful outside restricted content. Private aura sound APIs are **deprecated no-ops** (`BossPrototype.lua:447-455`).
4. `boss:IsSecret(v)` = `issecretvalue(v)` (`BossPrototype.lua:5137-5142`). It guards GUIDs, health, and aura names throughout (`:1840, 1871, 2017, 2529, 2754-2757, 2814-2880`). `PluginPrototype.lua:86` ships a fallback `issecretvalue = issecretvalue or function() return false end` for older clients.

### 5.3 Auras plugin (replaces private-aura anchoring)
`BigWigs_Plugins/Auras.lua`:
- Uses Blizzard **`CustomAuraContainerTemplate`** for debuff tracking on player/tank/named units (`:2383-2420`): `AddAuraGroup("debuffs", "HARMFUL", {maxFrameCount, initializeFrame, sortMethod = 4 (ExpirationOnly), sortDirection, layout = {elementSpacing, elementWidth, elementHeight}})`, then `SetEnabled`, `SetUnit`.
- Before touching pooled aura frames it calls **`aura:CanBeAccessedInContext()`** (`:2409`).
- Aura frames: `SetDurationCooldown`, `SetDurationText(duration, options)`, `C_DurationUtil.CreateDurationTextBinding` with `C_CurveUtil.CreateColorCurve` coloring (`:1989-2053, 2085, 2283, 2574-2579`).
- **Restriction-aware registration** (`:2676-2760`): `C_RestrictedActions.IsAddOnRestrictionActive(type)` (1 = Encounter, 2 = ChallengeMode, 0 = Combat). If a restriction is active, it **queues** the `AddAuraSound` and listens for `ADDON_RESTRICTION_STATE_CHANGED`. When `state == 0` (Inactive) it registers the sound. `C_UnitAuras.AddAuraSound(trigger, {unitToken, spellID, soundFileName|soundFileID, outputChannel, throttleSeconds})` accepts either an LSM path string or a numeric file ID.
- `Sound.lua:447-553` uses the same pattern for configured aura sounds.

### 5.4 Other plugins worth noting
- `InfoBox.lua:241-304, 667`: a `StatusBar` driven by a `DurationObject` plus a DurationTextBinding.
- `Pull.lua`: `C_ChatInfo.InChatMessagingLockdown()` checks before sending pull timers.
- `BarStyles.lua` / `API.lua:65-86`: **`BigWigsAPI:RegisterBarStyle(key, {apiVersion=1, version, GetStyleName, ApplyStyle(bar), BarStopped(bar), GetSpacing, barSpacing, barHeight, fontSizeNormal, fontSizeEmphasized, fontOutline, spellIndicatorsOffset})`**. A UI suite can register its own BigWigs bar skin. ElvUI and others do this.
- `API.lua:200-245, 316`: **`BigWigsAPI.RegisterProfile(addonName, profileString, customName, callback)`**, `RequestProfile`, `SwapProfile`, `GetProfileList`, `GetProfileName`, `IsValidProfile`. Profile import goes through a **user confirmation popup** and is **async with a callback**. WagoUI's BigWigs module uses exactly this. SoulUI's installer can call it to ship a matching BigWigs profile.
- `API.CreateBarFromAddon(addonName, text, icon, time)`, `SendBarToGroup` (`API.lua:29, 43`): third-party timers rendered by BigWigs.

### 5.5 License
`## X-License: All Rights Reserved: You are free to fork and modify on GitHub, please ask us about anything else.` Patterns only. Calling its public API (`BigWigsAPI`) from SoulUI is fine.

---

## 6. MythicDungeonTools (brief)

- **Architecture**: `Core/` (Bootstrap, Lifecycle, SavedVariables, CombatLogging), `Modules/` (API, DungeonEnemies, Transmission, LiveSession, ErrorHandling, FramePools...), per-expansion dungeon data (`Midnight/*.lua` for the current season's 16 dungeons via `load_midnight.xml`).
- **Restricted-environment gate**: `MDT:IsInRestrictedEnvironment(shouldWarn)` = `C_Secrets.ShouldAurasBeSecret()` (`MythicDungeonTools.lua:12-20`). Sharing and live sessions are blocked with a message while it is true.
- **Lockdown diagnostics**: `MDT:GetLockdownState()` (`Modules/ErrorHandling.lua:10-27`) loops over `Enum.AddOnRestrictionType` names `Map, Chat, Combat, Encounter, ChallengeMode, PvPMatch` and `pcall`s `C_RestrictedActions.IsAddOnRestrictionActive`. It is a nice compact way to show "why is this blocked" in a debug panel.
- **Codec**: `!~MDT2~` + Base64(Deflate(CBOR)) via `C_EncodingUtil` (`Modules/Transmission.lua:11-29`). There is also a secret-safe diagnostic formatter, `issecretvalue(v) -> "<secret>"` (`:34`), and a failure probe list including `InChatMessagingLockdown` (`:400-411`).
- `Modules/API.lua:13`: refuses secret NPC IDs.
- **License**: GPL v2. Patterns only.

---

## 7. SharedMedia_MusclebrahTV: LibSharedMedia registration

- `MyMedia.lua`: `local LSM = LibStub("LibSharedMedia-3.0")`. A small helper `RegisterMedia(name, type, path)` wraps `LSM:Register(type, COLOR_PREFIX..name..COLOR_SUFFIX, path)`, so **the media names are color-coded** (`|cff19dfe6MuscleUI: Stack|r`) and stand out in dropdowns. The font and statusbars are registered plainly as `'MuscleUI'` and `"MuscleUI"` / `"MuscleUI Blank"`.
- Registrations: 1 font (`font\MuscleUI.ttf`, OFL; the OFL text credits Mozilla/Telefonica, i.e. Fira Sans lineage), 2 statusbars (`MuscleUI.tga`, `MuscleUI_Blank.tga`), and about 40 voice sounds (`.ogg`: Adds, AOE, Bait, Bloodlust, Soak, Spread, Stack...).
- **Important for SoulUI**: other addons persist LSM media **by registered name**. The user's EllesmereUI profile stores `"sm:MuscleUI"` and `"sm:MuscleUI Blank"`, and fonts as both name and path (`unitNameFontPath = Interface\Addons\SharedMedia_MusclebrahTV\font\MuscleUI.ttf`). If SoulUI uses LSM it should (a) store names, (b) also cache the resolved path as a fallback, and (c) re-resolve on `LibSharedMedia_Registered` callbacks for media packs that load after us.
- `EditModeHelper.lua`: on login it switches Blizzard Edit Mode to the layout named "MuscleUI" (`C_EditMode.GetLayouts()` plus `C_EditMode.SetActiveLayout(presetCount + i)`, lines 86-99). It counts presets via `EditModePresetLayoutManager:GetCopyOfPresetLayouts()` because retail has 2 presets and Forever has 3 (lines 72-82). After the switch it **pokes EllesmereUI's Cooldown Manager to do a full rebuild** (`EllesmereUI._ModuleNS["EllesmereUICooldownManager"].FullCDMRebuild("editmode_close")`, lines 52-58). A scripted layout switch never fires the Edit Mode "close" path, so CDM icons would otherwise stay stale. **Lesson for SoulUI**: listen to `EDIT_MODE_LAYOUTS_UPDATED` and do a full rebuild of anything anchored to Blizzard systems, not only on the Edit Mode exit hook.
- Also: `ScaleCheck_TBC.lua` (scale warnings on TBC), `MUITargetArrow.lua`, `MUIOptions.lua`.

---

## 8. User's current EllesmereUI configuration (from WTF)

Source: `WTF\Account\<account>\SavedVariables\EllesmereUI.lua` (1.15 MB). **Every EllesmereUI
sub-addon SV file (`EllesmereUIActionBars.lua`, `...UnitFrames.lua`, etc.) is an empty stub
(`= { }`)**. All settings live in one `EllesmereUIDB` table with a shared profile system. Character names and GUIDs in the file are deliberately left out of this summary.

### 8.1 Top-level structure of `EllesmereUIDB`
- `profiles = { Default, MuscleUI }`, `activeProfile = "MuscleUI"`, `profileOrder`, `specProfiles` (empty, so no spec-based profile switching), `lastNonSpecProfile`.
- Global (account-wide) settings sit beside the profiles: `ppUIScale = 0.5333` (**pixel-perfect at 1440p**; the `uiScale` CVar is also `0.533333`, `useUiScale = 1`), `ppUIScaleAuto = false`, `panelScale = 1.1`, `tooltipFontScale = 1.3`, `windowLookPerProfile = true`, and character-sheet tweaks (`showItemLevel`, `showEnchants`, `showSpellID`, `showMythicRating`, `showUpgradeTrack`, `showAdjustedStats` are true; `showPvpItemLevel` and `showCharSheetDurability` are false), a gold ledger, bag currency, mail alt roster, `clickCast`, a big `spellAssignments` (~450 KB), `unlockAnchors` (positions for every movable), `restoreOnUninstall` (saved CVars/bits to restore when EUI is uninstalled, a nice touch), and many `*Seeded` / `_migrations` flags.
- A profile (`profiles.MuscleUI`) contains: `addons = { [ModuleAddonName] = settings }`, `fonts`, `customColors`, `darkMode`, `euiAccent`, `unlockLayout` (anchors / width-match / height-match), **per-spec overrides** (`specOverrides` with 25 groups, `specUnlockOverrides`, `specBmOverrides`, `specDmOverrides`), conditional overrides (`condOverrides`, `condDmOverrides`), `windowSkinLook = "eui"`, `tooltipFixedPos`, `_migrations`.

### 8.2 Modules present in the active profile
CooldownManager, Bags, MythicTimer, Nameplates, DamageMeters, Minimap, Chat, DataBars, UnitFrames, AuraBuffReminders, QuestTracker, RaidFrames, ActionBars, Friends (empty), ResourceBars, QoL, GroupFinder, Quickdraw, DragonRiding. In practice, **the user runs the full EllesmereUI suite**. BlizzardSkin is in use through `windowSkinStyleSlots`.

### 8.3 Look and feel
- **Font**: a single global font, `"MuscleUI"` (Fira-Sans-like, from SharedMedia_MusclebrahTV), `applyToAllGameText = true`, `outlineMode = "outline"`. The same font is in both "eui" and "classic" style slots.
- **Statusbar texture**: `sm:MuscleUI` for health bars everywhere (unit frames, raid, party, boss, nameplates, castbars). Resource bars use `sm:MuscleUI Blank` (flat).
- **Accent color**: custom cyan, `r=0, g=0.93, b=1` (`useClass = false`). It matches the MuscleUI media color `#19dfe6`.
- **Dark mode panel bg**: grey `0.31/0.31/0.31`. Resource/cast bar backgrounds are `0.169` grey at alpha 1.
- **Custom class colors**: MONK `(0,1,0.6)`, PALADIN `(0.96,0.55,0.73)`. Custom class-resource colors are set for Runes, Chi, Combo Points, Holy Power, Soul Shards, Essence, Arcane Charges, Maelstrom, etc.
- Absorb style `stripedThick`, overshield shown, no portraits (`portraitStyle = "none"`), combat indicator style `combat0`.

### 8.4 Sizes and layout (UI units at scale 0.5333)
| Element | Key settings |
|---|---|
| Player frame | 290 x 52 health, no power bar on frame (`powerPosition = "none"`), text 20, debuffs 65 px with cooldown text 20, castbar 290 wide |
| Target frame | 290 x 52, **detached power bar** under the frame (172 x 10), buffs/debuffs 24, castbar 290 x 26, cast text 16 |
| Focus | 140 wide, castbar 140 x 19, interrupt-ready coloring on castbar, debuffs 41 |
| ToT / FocusTarget | 140 x 34 |
| Pet | 120 x 34 |
| Boss | 200 x 42 |
| Positions | Player at about (-561, -321) and target at (562, -321) from center, symmetric. Castbars sit below them. Focus is left of the player at (-636, -215). Boss frames are on the right at (629, 272) |
| Party frames | 225 x 78, name size 21, cell spacing ~15, power bar 8 |
| Raid frames | 120 x 70, name 14, groups grow DOWN, units grow RIGHT, ~0 spacing (pixel-tight), modern (non-classic) style |
| Nameplates | health 80 x 20, castbar 20 high, cast name 15, max debuffs 4, target scale 110%, target arrow 2.2x, hitbox Y 200% |
| Action bars | **45 x 45 buttons, 1.33 px padding (one physical pixel at this scale), 2 px border**. MainBar and Bar2 always visible (12 buttons, 1 row); Bar3/4/5 vertical; Bar6-10 are 2 rows and **mouseover-only (alpha 0)**. Pet bar 23 px. Stance 45. Bag bar mouseover. Micro bar always. XP/Rep bars always shown (text 16/13). |
| Resource bars | primary 371 x 15, text 18, smooth bars; standalone cast bar 331 x 40, cyan fill `(0, 1, 0.99)`, last-tick and empower-stage coloring |
| Tooltip | fixed position |

### 8.5 What SoulUI defaults should borrow from this
- One global font and one statusbar texture everywhere, selectable by LSM name.
- Pixel-perfect scale presets per resolution (0.5333 for 1440p, 0.7111 for 1080p, 0.3556 for 2160p). Express padding in physical pixels (`1 px = 768/screenHeight/uiScale`), as EUI's 1.333 padding at 0.5333 shows.
- A centered, symmetric player/target pair (~290 x 52), small focus/ToT/pet frames, and bars the same width as the frames ("width match" keys in `unlockLayout`).
- 45 px action buttons with a 2 px border. Extra bars mouseover-faded by default.
- Accent color choice (class or custom) applied consistently to the UI chrome.
- Per-spec layout overrides as a first-class feature (the user has 25 spec-override groups).
- `_`-prefixed migration flags inside profiles. A `restoreOnUninstall` snapshot of CVars changed by the UI.

---

## 9. Cross-cutting 12.x patterns (summary)

| Problem | Pattern used by these addons |
|---|---|
| "Am I restricted right now?" | `C_Secrets.ShouldAurasBeSecret()` (NSRT, MDT, Exwind state). Finer grained: `C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.X)` plus the `ADDON_RESTRICTION_STATE_CHANGED` event (BigWigs, MDT) |
| Boss timers | `C_EncounterTimeline` events and getters. Pass secret name/icon straight to FontString/Texture. Key bars by `eventId`. `AddEditModeEvents()` for previews. `SetEventIconTextures` for role icons |
| Boss warnings / targets | `ENCOUNTER_WARNING`. `string.format` with secret args. `GetPlayerInfoByGUID(targetGUID)` for class color |
| Countdown text on secret durations | `C_DurationUtil.CreateDurationTextBinding` plus `C_StringUtil` formatters. Alternative: a stripped native `Cooldown` frame (numbers only). Unbind before releasing pooled FontStrings |
| Bar fill on secret durations | `StatusBar:SetTimerDuration(durationObj, interp, dir)`, then `SetToTargetValue()` once on reused bars |
| Threshold coloring | `C_CurveUtil.CreateColorCurve()` (Step) attached to the binding |
| Show/hide on secret booleans | `Region:SetAlphaFromBoolean(b, aTrue, aFalse)`. Reset alpha on pool acquire |
| Aura icons on restricted units | Blizzard `CustomAuraContainerTemplate` / `AuraButton` (load `Blizzard_AuraContainer` on demand). `CanBeAccessedInContext()` check |
| Aura sounds | `C_UnitAuras.AddAuraSound/RemoveAuraSound`, registered outside restrictions (queued until state Inactive) |
| Addon comms | `C_ChatInfo.InChatMessagingLockdown()` gate plus a pending queue. CBOR+Deflate+Base64url payloads |
| Serialization | `C_EncodingUtil` (CBOR, Deflate, Base64) with prefixed, versioned strings |
| Diagnostics | Capability probes (Exwind), lockdown state lists (MDT), secret scrubbing in error reports (Exwind, MDT) |
| "Hidden" info | Use `issecretvalue(x)` itself as a boolean signal where the presence of a value is what matters (NSRT raid-marker trick). Use with care |

---

## Recommendations for SoulUI

1. **Codec**: use `C_EncodingUtil` only (SerializeCBOR, then CompressString(Deflate, OptimizeForSize), then EncodeBase64 with the `StandardUrlSafe` variant). Use a versioned, typed prefix, e.g. `!SOUL1:profile:<data>` and `!SOUL1:module:<name>:<data>`. Detect old or foreign strings and give a clear localized message. Do not embed LibSerialize, LibDeflate, or AceSerializer.

2. **Wago compatibility, day one**: ship a global `SoulUIAPI` implementing `ExportProfile`, `ImportProfile` (activate, no reload, may return `false`), `DecodeProfileString`, `SetProfile`, `GetProfileKeys`, `GetProfileAssignments`, `GetCurrentProfileKey`, `OpenConfig`, `CloseConfig`. Keep `## Version:` semver and add `## X-Wago-ID:`. Then request a `LibAddonProfiles/modules/SoulUI.lua` from the WagoUI team (GPL repo, so a PR is the natural route), with our `_`-prefixed ignore list for `areProfileStringsEqual`. Export must work for *any named profile*, not only the active one.

3. **Profile model**: one account SV with `profiles`, `profileKeys[char]`, optional spec profiles, and module tables nested under `profile.modules[...]` (EUI's `profile.addons[...]` shape). Put every bookkeeping or migration key under a `_` prefix. Add `restoreOnUninstall`-style CVar snapshots. Provide selective per-module import with a summary screen and merge vs. replace (ExwindExport pattern).

4. **Restriction layer** (one module, used by everything):
   - `Soul.Restrictions:IsActive(type)` wrapping `C_RestrictedActions.IsAddOnRestrictionActive` with `pcall`, plus `C_Secrets.ShouldAurasBeSecret()`. Publish changes via `ADDON_RESTRICTION_STATE_CHANGED`.
   - A deferred-work queue that runs when restrictions lift (aura sound registration, comms, frame creation that needs templates).
   - A comms wrapper that respects `InChatMessagingLockdown()` and queues.

5. **Capability probes at login** (ExwindCore pattern): probe DurationObject, DurationTextBinding, ColorCurve, StatusBar timer/radial, AuraContainer, and AuraSound. Store reasons, gate features on them, and show them in `/soul debug`. Defer template probes while in combat.

6. **Secret-safe rendering primitives** (our own implementations):
   - A timer bar fed by a DurationObject: `SetTimerDuration` + `SetToTargetValue()` on acquire.
   - A countdown text: DurationTextBinding with a numeric-rule formatter and a step color curve. Disable and unbind before releasing, never `SetToDefaults()` a bound FontString. Keep a fallback to a numbers-only `Cooldown`.
   - A visibility mixin for `SetAlphaFromBoolean`, with an alpha reset in the pool's acquire path.
   - Aura displays built on `CustomAuraContainerTemplate` (load `Blizzard_AuraContainer` on demand; check `CanBeAccessedInContext()`).
   - Error handler and debug dumps that scrub secrets (`issecretvalue`, then "<secret>").

7. **Boss timers (if SoulUI ships a timeline or bar skin)**: build on `C_EncounterTimeline` (ADDED/STATE_CHANGED/REMOVED, rebuild from `GetEventList` on enable). Key everything by `eventId`, use `AddEditModeEvents()` for the "test" button, and use `SetEventIconTextures` for role icons. Better still, don't compete with BigWigs: **register a SoulUI bar style via `BigWigsAPI:RegisterBarStyle`** (apiVersion 1) so BigWigs bars match our theme. Optionally offer a BigWigs profile through `BigWigsAPI.RegisterProfile(..., callback)` in our installer.

8. **Packaging**: put options in a separate load-on-demand addon (`SoulUI_Options`) with a bootstrap handshake and pending-show handling (NSRT). Gate per-file by flavor with `[AllowLoadGameType ...]` if we ever target Forever/Classic. Add `## Category:` plus localized variants. Use frame-budgeted coroutines for heavy builds and imports.

9. **Media**: embed LibSharedMedia-3.0 at MINOR 12000005 or higher. Register SoulUI media with a recognizable (optionally color-coded) prefix. Persist media by LSM name, cache the path, and re-resolve on `LibSharedMedia_Registered`. Consider shipping an OFL font (Fira Sans family) so the default feel resembles the user's MuscleUI font legally.

10. **Defaults that feel familiar** (from the user's live EUI profile): pixel-perfect scale per resolution (0.5333 at 1440p), a single global outlined font, a flat MuscleUI-like statusbar, a cyan accent (`#00EDFF`-ish) with a class-color toggle, player/target at 290 x 52 placed symmetrically around ±560 x, -320 y, focus/ToT 140 wide, 45 px action buttons with 2 px borders and 1 physical pixel padding, extra bars fading on mouseover, party 225 x 78, raid 120 x 70 (groups down, units right), nameplates 80 x 20 with target scale 110%. Ship per-spec layout overrides as a core feature.

11. **Edit Mode interop**: when SoulUI anchors to Blizzard systems (CDM, encounter timeline, etc.), rebuild on `EDIT_MODE_LAYOUTS_UPDATED`. A scripted `C_EditMode.SetActiveLayout` never fires the manager's hide path (MusclebrahTV's workaround for EUI's CDM).

12. **Licensing hygiene**: no code from BigWigs, NSRT, or ExwindCore (All Rights Reserved), and none from WagoUI or MDT (GPL v2) unless SoulUI itself is GPL. Libraries we embed (LibStub, CallbackHandler, LibSharedMedia LGPL, LibCustomGlow BSD) keep their license files in `libs/`. Calling public APIs (`BigWigsAPI`, `NSAPI`, `LibSharedMedia`) is fine and encouraged.
