# SoulUI architecture

Target client: retail **12.1.5** (Interface `120105`). This file is the contract. If a later session wants to change a decision in the "Locked decisions" section, it needs a build-log entry that says why.

The design was taken from the studies in `docs/research/`. Those notes describe other addons. SoulUI code is original. Do not paste from EllesmereUI, ExwindCore, Northern Sky, BigWigs, WagoUI, or MDT.

## Locked decisions

1. **One addon per feature**, plus a core and a LoadOnDemand options addon. Children do not declare SavedVariables.
2. **One account saved variable**, `SoulUIDB`, owned by `SoulUI`. Modules receive a table inside the active profile.
3. **No oUF.** Unit frames are secure buttons plus a small event router we own.
4. **No per-setting spec-override watcher.** Profiles can be assigned to a spec. Diff-capturing individual settings was a major source of profile corruption in the addon we studied, and it is out of scope until the suite is otherwise stable.
5. **Profile strings use `C_EncodingUtil`** (CBOR, Deflate, Base64). Prefix `!SOUL1:`. No LibSerialize, LibDeflate, or AceSerializer.
6. **Auras, when we build them, use Blizzard `AuraContainer` frames.** Lua does not iterate aura lists during restricted content.
7. **Damage meters, when we build them, read `C_DamageMeter` only.** The combat log is not available to addons. Bars stay in the order the server sends. No sorting and no division while values are secret.
8. **Action bars, when we build them, are our own secure buttons**, not a reskin of Blizzard's buttons. Stock bars get hidden by reparenting, not `Hide()`.
9. **Cooldown Manager, when we build it, skins Blizzard's viewer frames** and does not reparent them.
10. **Boss timers stay with BigWigs.** A later optional piece is a BigWigs bar skin via `BigWigsAPI:RegisterBarStyle`. We do not write a boss-mod timer engine.
11. **Positions are CENTER offsets from UIParent's center**, in UIParent units. Releasing a drag writes that position into the active profile. Cancel restores the snapshot from when unlock opened. Export copies the whole profile, so positions and settings travel together. The default layout lives in `Core/Layout.lua`. It is written into a profile once per `LAYOUT_VERSION` (stamped as `profile._layoutVersion`) and again only when the user presses Reset Layout. After that the profile belongs to the user and nothing at login moves frames. (0.3.0 replaced the old `FitLayout` heuristics, which guessed which frames were "still on a default" and fought user edits.)
12. **Callbacks, not global apply functions.** Modules listen for `ProfileChanged` and `ThemeChanged`. The core never calls `_G._Something_Apply`.

## Layout

```
SoulUI/                  always loaded. Framework only. No feature frames.
SoulUI_UnitFrames/       player, target, focus, targettarget, pet
SoulUI_Nameplates/       enemy and neutral nameplates
SoulUI_GroupFrames/      party and raid headers
SoulUI_ActionBars/       main bar and the extra bars
SoulUI_ResourceBars/     primary power, class pips, cast, GCD
SoulUI_DamageMeters/     C_DamageMeter windows
SoulUI_Options/          LoadOnDemand editor
```

Load order inside `SoulUI`:

1. `Core/Gate.lua` sets `SoulUI_Blocked` on clients older than interface 120100 and then does nothing else, so an old client cannot rewrite `SoulUIDB`.
2. Libs: LibStub, CallbackHandler-1.0, LibSharedMedia-3.0.
3. Core, Database, Secret, Units, Runtime, Pixel, Media, Format, UIKit, Casts, Auras, Unlock, Profiles, Menu, Layout.

Every SoulUI lua file starts with `if SoulUI_Blocked then return end`, except `Gate.lua` and the third-party libs.

A child addon:

- `## Dependencies: SoulUI`
- `## Group: SoulUI`
- No SavedVariables line.
- First line of every file: `if SoulUI_Blocked or not SoulUI then return end`
- Calls `SoulUI:NewModule(key, addonName)` at file scope, so its event frame is created while that addon is loading. The CPU profiler bills that frame to the child.

`SoulUI_Options` is `LoadOnDemand` and also has no SavedVariables. `/soul` loads it. It refuses to open in combat and closes itself if combat starts.

## Lifecycle

`SoulUI:NewModule` gives the module `RegisterEvent` and `RegisterUnitEvent`. The module's event frame is created immediately.

`mod:RegisterUnitEvent(event, fn, unit1, unit2, ...)` gives **each unit token its own listener frame**. `frame:RegisterUnitEvent(event, unit)` replaces that event's unit filter on a frame, so before 0.3.0 registering `UNIT_HEALTH` for player, target, focus... on one frame kept only the last unit, and unit frames, nameplates, group frames and meter flags stopped updating live. Never call the raw frame method in a loop over units.

- `OnInitialize` runs on that addon's `ADDON_LOADED`, after the core database exists (the core addon loads first because of `## Dependencies`).
- `OnEnable` runs from the core's `PLAYER_LOGIN`, synchronously, so secure setup still happens during the loading screen. A combat reload depends on this. Do not defer secure `RegisterUnitWatch` / `RegisterStateDriver` work with `C_Timer`.
- A module loaded after login (there are none in 0.1.0) is enabled from its own `ADDON_LOADED`.

`SoulUI:On(event, fn)` / `SoulUI:Fire(event, ...)`. Built-in events: `ProfileChanged`, `ThemeChanged`, `Ready`.

`SoulUI:RunAfterCombat(key, fn)` runs `fn` immediately when the player is out of combat. In combat it keeps one callback per key and runs it on `PLAYER_REGEN_ENABLED`. `SoulUI:RunAfterCombat(fn)` also works.

## Saved variables

```lua
SoulUIDB = {
  activeProfile = "Default",
  profileOrder = { "Default" },
  specProfiles = { },          -- [specID] = "Profile name"
  profileKeys = { },           -- ["Name - Realm"] = "Profile name"
  lastSpecByChar = { },        -- ["Name - Realm"] = specID
  cvars = { },                 -- [cvar] = { original = "...", owner = "Module" }
  account = { debug = false, panelScale = 1, welcomed = true,
              windows = { [frameName] = { point, relPoint, x, y } },   -- movable SoulUI windows
              edit = { grid, snap, gridSize, shade, ghosts },           -- edit mode toolbar
              uiFont = nil },   -- LSM font name for the settings window / edit mode (nil = bundled Barlow Semi Condensed)
  _migrations = { },
  profiles = {
    Default = {
      _migrations = { },
      theme = {
        accent = { r = 0, g = 0.93, b = 1 },
        accentUseClass = false,
        font = "Friz Quadrata TT",
        fontOutline = "OUTLINE",
        statusbar = "SoulUI Flat",
        background = { r = 0.06, g = 0.06, b = 0.07, a = 0.92 },
      },
      unlock = { positions = { ["UnitFrames:player"] = { point, relPoint, relative, x, y } } },
      _layoutVersion = 3,       -- Core/Layout.lua default layout already written
      _partyVertical = true,    -- 0.4.0 party switch done
      _singleCast = true,       -- 0.5.0 player/pet unit-frame cast bars turned off once
      blizzard = { hideCastBar = true, personalDisplay = false, cooldownManager = false,
                   hiddenViewers = { [viewerFrameName] = true } },   -- Core/Blizzard.lua
      modules = {
        UnitFrames = { },
        Nameplates = { },
      },
    },
  },
}
```

Rules:

- Bookkeeping keys start with `_`. Profile diffs should ignore them.
- `SoulUI:ModuleDB(key)` always returns the **live** table for the active profile. Never cache it across `ProfileChanged`.
- Defaults live in each module's `Defaults.lua`. Missing keys are filled on read. On `PLAYER_LOGOUT` the core strips values that equal defaults, so the saved file stays small. `_` keys are not stripped.
- `SoulUI:RegisterMigration(id, fn)` runs once per account. Stamp the id only after the function succeeds. Migration bodies edit raw tables and do not call unit APIs.
- Changing a CVar goes through `SoulUI:SetOwnedCVar(name, value, owner)`, which remembers the previous value the first time. That snapshot is how a later uninstall can put the user's settings back.
- `specProfiles` is optional. If the current spec has an entry, `PLAYER_SPECIALIZATION_CHANGED` switches to that profile (after combat, if needed). No entry means the active profile stays put.

Public profile API, on both `SoulUI` and `SoulUIAPI`, matching the Wago installer contract:

`ExportProfile`, `ImportProfile` (activates the profile, never reloads, may return false), `DecodeProfileString`, `SetProfile`, `GetProfileKeys`, `GetProfileAssignments`, `GetCurrentProfileKey`, `OpenConfig`, `CloseConfig`.

The string is `!SOUL1:` plus URL-safe Base64 of a Deflate stream of a CBOR document. The same string is what the in-game import box accepts. WagoUI will not offer SoulUI in its installer until someone adds a `LibAddonProfiles` module for it. The API is ready before that.

## Secret values

`SoulUI.Secret` is the only helper layer. Hot code may call `issecretvalue` directly.

| Allowed | Not allowed |
|---|---|
| store, pass, `..`, `string.format`, `AbbreviateNumbers` | arithmetic, comparisons, `#`, `tostring` |
| truth-test a secret number or string (nil vs not) | `if secretBoolean then` |
| `StatusBar:SetValue`, `SetMinMaxValues`, `SetTimerDuration` | using a secret as a table key |
| `SetText`, `SetFormattedText`, `SetAlphaFromBoolean` | anchoring layout to a region whose size comes from a secret, then reading that geometry |
| `C_ClassColor.GetClassColor(secretClass)` | `RAID_CLASS_COLORS[secretClass]` |

Health is always secret to addon code, even out of combat. `UnitHealthPercent(unit, true, CurveConstants.ScaleTo100)` feeds percent text. Color for a secret class token goes through `C_ClassColor.GetClassColor`. Cast timing uses `UnitCastingDuration` / `UnitChannelDuration` and `StatusBar:SetTimerDuration`. A secret boolean uses `SetAlphaFromBoolean` or `C_CurveUtil.EvaluateColorFromBoolean`.

`/soul secret` turns on `addonCombatRestrictionsForced` and `addonEncounterRestrictionsForced` so this can be tested on a dummy. `/soul secret off` clears them.

## Frames

Unit frames are `SecureUnitButtonTemplate` buttons parented to a pet-battle state driver (`[petbattle] hide; show`). Left click targets. Right click runs `/click` on a secure menu proxy, because a raw `togglemenu` attribute on the unit button is unreliable on 12.x. `RegisterUnitWatch` shows and hides them. The player button sets `toggleForVehicle`. The watched token is stored on our own frame as `_soulUnit` (our frame, so this is not a Blizzard-frame taint).

Events use `RegisterUnitEvent`. `UNIT_HEALTH` updates the health bar only. Cast events are not dropped. A unit cast bar is its own frame, anchored just above that unit. Edit mode shows a sample on it (icon, name, partial fill, time). A real cast uses the same frame: `SetTimerDuration` for the fill and a duration text binding for the ticking time. `targettarget` also refreshes from `UNIT_TARGET` on `target`. Vehicle events are forwarded to the player frame.

Nameplates: on `NAME_PLATE_UNIT_ADDED`, if the plate is not forbidden and `UnitReaction` is hostile or neutral, a pooled frame is parented to the nameplate and Blizzard's `UnitFrame` is set to alpha 0. On remove, the Blizzard frame is restored, because the same plate object is recycled for friendly units. Friendly plates are never modified. Plates inside instances that fire `FORBIDDEN_NAME_PLATE_*` are left alone.

Neither module writes fields onto Blizzard frames. Side tables only.

Action buttons are our own `ActionBarButtonTemplate` buttons, **sized for real** (`SetSize`, scale 1). The 12.x template masks its icon with a fixed 45px `IconMask`; we remove that mask (`RemoveMaskTexture`, then shrink and hide it) and re-pin the icon after the template's own event handlers. Do not go back to `SetScale` on buttons: `SetScale` also scales `SetPoint` offsets, which is what spread 0.2.x buttons apart until the clipping holder cut them off. Highlight, pushed and checked textures are flat overlays. The holder does not clip.

Class pips (ResourceBars) are tiles: a frame with a 1px border holding an inset StatusBar "gate" (`SetMinMaxValues(i-1, i)` + `SetValue(power)`, so secret power works). Fill defaults to the class color, empty tiles to flat gray. The count number sits on the last full tile; with a secret value its alpha comes from a step curve instead of a Lua comparison.

## Editor and movers

Both are built from `Core/UIKit.lua` (`SoulUI.UI`): movable windows (`UI.Window`, position remembered in `account.windows`), buttons, switches, sliders, number boxes, one shared dropdown menu, color swatches, a 3x3 point picker and LibSharedMedia lists. Windows run at 1 unit = 1 physical pixel times `account.panelScale`. Every accent-colored piece registers through `UI.OnAccent`, so a theme change recolors open windows live. Menus and the color picker sit on TOOLTIP strata so they open above the edit mode windows.

**Settings (`/soul`, SoulUI_Options, LoadOnDemand), 0.6.0 redesign modeled on EllesmereUI's window (own code).** A movable 1180x780 window (drag the header or brand). Cool near-black base, darker sidebar, faint accent haze behind the header, 1px accent-tinted frame edge.
- **Sidebar (240):** diamond mark (two thick 45-degree Line objects) and "SoulUI", an accent rule that fades out at both ends, a pinned "Edit Mode" action row, the "SoulUI" group pages without a heading, the search-all box, then accent group headings (Frames, Combat) with page rows (2px accent bar plus fading tint on the active row, status dot for module pages). At the bottom, the active profile (click: Profiles) and the version.
- **Header:** 30px page title, description, a window-scale slider (applied on mouse-up) and a hairline close button.
- **Below the header:** a tab bar (text tabs, 2px accent underline on the active one) with page search on the right, then the optional live preview strip (`Previews.lua`, `preview(holder, width) -> height, update`), the eased scroll area with a thin track, and a footer (Reload UI and Reset page on the left, Edit Mode and Close on the right).

**Widgets.** A section is an uppercase heading over one flat panel (white at 2%, no border). Rows are 46 tall with no separators; two-column rows split on one continuous hairline. Labels are 15px.

**Controls (UIKit).**
- Square switches, a 3px slider track with an accent knob, hairline dropdowns with a drawn chevron, and hairline buttons.
- Icons are drawn with `UI.Glyph` (Line objects: close, chevrons, check, plus); no letters stand in for icons.
- The window and edit mode use the UI font (`UI.SetFont`, `account.uiFont`, General > Look > Window font). `UI.RefreshFonts` re-fonts open windows. Frames keep the theme font. Pages may set `addon` for the sidebar dot. Pages register with `SoulUI:RegisterPage { key, title, description, group, groupOrder, order, build(col) | tabs = { { key, title, build(col) } }, reset() }`. Builders stack declarative rows: `W.Section`, `W.Note`, `W.Row(spec)`, `W.Row2(left, right)`, `W.Selector` (per-unit / per-bar editing), `W.Buttons`, `W.Input`, `W.TextArea`, `W.List`. A spec is `{ type = toggle|slider|dropdown|font|statusbar|color|button|number, label, get, set, disabled, tooltip }`. Every set refreshes the whole page, so `disabled` rows grey out immediately. Rows are indexed for the sidebar search, which builds unvisited pages on first use, jumps to the page and flashes the row. `Soul:OpenOptions(pageKey)` opens on a page. There is no Apply button.

**Edit mode (`/soul move`, `Core/Unlock.lua`).** A movable toolbar (grid, snap, grid size, dim, Settings, Reset Layout, Cancel, Save & Exit), an overlay that dims the world and draws the grid, one mover per element, and a movable inspector for the selected element (X/Y, W/H, anchor-to element, this point / target point pickers, nudge, color, element settings, reset position). Drag snaps within 6px to the screen center and edges, other movers' edges and centers, then the grid, with accent guide lines; Shift locks the axis, Alt disables snapping. Wheel resizes by one physical pixel, arrows nudge 1px (Shift 10px), right-click opens the element's settings page. Edits write into the profile live; Cancel restores a snapshot of positions **and module settings** (resizing writes module settings) and fires `ProfileChanged`. Combat hides the session and resumes it 0.5s after combat. Mover elements: `key, label, getFrame, fallback, onResize, getColor, setColor, onEdit, isHidden, getEnabled, setEnabled, page`.

**Hiding elements (0.5.0).** `getEnabled()` / `setEnabled(on)` map an element to its module's own enable flag (`units[u].enabled`, `units[u].showCast`, `bars[k].enabled`, `showPrimary/showPips/showCast/showGCD`, `party/raid.enabled`, `windows[i].enabled`). There is no separate "hidden" table: hiding is the module setting, so it saves per profile, Cancel reverts it with the module snapshot, and the module's own page shows the same state. A hidden element keeps a dim "ghost" mover labelled "(hidden)" (toolbar switch "Hidden", `account.edit.ghosts`); the inspector's "Shown" switch toggles it. General > Hide & Show lists every element with `setEnabled`, grouped by module, plus the Blizzard toggles. `isHidden()` is now only for movers that do not apply at all. New movers must provide both functions. `Soul:Place` divides offsets by the frame's scale ratio, so frames with their own scale (Blizzard's) land where the UIParent-unit position says.

## Cast bars (0.7.0)

`Core/CastBar.lua` (`SoulUI.CastBar`) is the only cast bar. The player bar (Resources), unit frames and nameplates each create theirs with `CastBar.New(parent, { enemy = bool, name })`, set `cb.allowed` (the module's on/off setting) and `cb.getColor` (friendly color), call `cb:Layout(height, showIcon, fontSize)`, and forward `UNIT_SPELLCAST_*` with `cb:HandleEvent(event)`. Unit changes and settings changes go through `cb:Refresh()`, and edit mode uses `cb:SetPreview(on)`. Rules:
- **End events:** STOP, FAILED and INTERRUPTED re-query the unit and only finish the bar if it really stopped casting. A failed key press mid-cast, or a queued spell's late STOP, used to hide live bars.
- **Late duration:** a START whose duration object is not ready retries 3 times, 50ms apart.
- **`allowed()` is checked on every path,** so a bar that is turned off never shows.
- **End of cast:** a finished cast fades out; an interrupted one flashes red with "Interrupted".
- **Look:** square icon flush left, a spark on the fill edge, and the time bound with a duration text binding.
- **Enemy colors** still come from `Core/Casts.lua` (`theme.cast`). They are edited in one shared block (`Soul.Options.CastColorRows`) shown on General > Casts, Unit Frames and Nameplates. A per-unit `castColor` now applies only to player and pet.

## Action buttons (0.7.0)

- **Proc glow:** Blizzard's `SpellActivationAlert` is set to alpha 0 on SoulUI buttons, through a `ShowAlert` hook and in Chrome. Our glow is a 2px edge plus an inner gradient wash, drawn to the exact button rect, pulsing in one animation group.
- **What drives the glow:** `C_SpellActivationOverlay.IsSpellOverlayed(buttonSpell)`, re-checked (coalesced) on `SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE` and on slot or page changes. A secret answer drives alpha through `SetAlphaFromBoolean`.
- **Text overlay:** hotkey, stack/charge count and macro name are re-parented to a text frame above the cooldown and glow.
- **Settings:** `countAnchor`, `countColor`, `procGlow`, `procColor`.

## Casts and auras (0.4.0)

`Core/Casts.lua` (`SoulUI.Cast`) colors enemy cast bars (since 0.7.0 for `Core/CastBar.lua` objects): interruptible, interrupt-on-cooldown (`C_Spell.GetSpellCooldownDuration(kick):IsZero()`), not interruptible (lock icon), important outline (`C_Spell.IsSpellImportant`), and a STUN badge for important + uninterruptible. Secret booleans only reach `C_CurveUtil.EvaluateColorValueFromBoolean(bool, ifTrue, ifFalse)` and `SetAlphaFromBoolean`. An AND of two secret booleans is two nested frames each with its own boolean alpha. Settings: `theme.cast`. Note the engine argument order is (bool, **ifTrue**, ifFalse); `Secret.PickColor(flag, ifFalse, ifTrue)` swaps for its callers.

`Core/Auras.lua` (`SoulUI.Auras`) is the only aura path: `AuraContainer` groups with filter strings. `Auras.Icons` makes icon rows; `Auras.Highlight` makes one frame-sized button that exists only while the filter matches (the filter is the test, Lua never reads aura data). Filters used: `HARMFUL|RAID_PLAYER_DISPELLABLE` (cleansable on friends), `HELPFUL|DISPELLABLE` (purge/soothe on enemies), `HARMFUL|PLAYER` (your debuffs). `Auras.OffensiveDispel()` answers "can this character purge / soothe" from the spellbook. Containers are created out of combat only; friendly nameplates are never modified (forbidden in instances).

## Blizzard frames (0.5.0)

`Core/Blizzard.lua` (`SoulUI.Blizz`, settings `profile.blizzard`):
- **Player/pet cast bar:** `PlayerCastingBarFrame` and `PetCastingBarFrame` are parked (re-parented to a hidden frame) while `hideCastBar` is on and a SoulUI player cast bar is on (Resources cast or the player unit-frame cast). A `SetParent` hook re-parks on the next frame when Blizzard (Edit Mode) re-parents it. Same approach Ellesmere uses; events are not unregistered, so turning it off simply un-parks.
- **Personal resource display:** CVar `nameplateShowSelf` (off by default).
- **Cooldown Manager:** CVar `cooldownViewerEnabled` (off by default; Ellesmere had turned it on, which is the "icon row next to the bars" from the 0.4.0 test). When on, each viewer (`Essential/Utility/BuffIcon/BuffBarCooldownViewer`) has a mover (`Blizzard:<frame>`), can be hidden on its own (parked, `hiddenViewers`), and a position saved in SoulUI edit mode is re-applied through a `SetPoint` hook after Edit Mode re-anchors. Viewers without a SoulUI position are left where Blizzard puts them.
- Everything runs out of combat (`RunAfterCombat`). `Blizz.Refresh()` is called on Ready, ProfileChanged, and at the end of UF:Apply / RB:Apply.

## What 0.3.0 still does not do

Absorbs and heal prediction on unit frames. Aura containers on the player, target, and nameplates (raid and party buttons do get one dispel row). Stance bar and pet bar (those stay Blizzard's). Reskinning the cooldown manager (0.5.0 only shows, hides and moves it). Swing timer, totems, custom bar paging, and flyout reskins. Chat, bags, minimap, quest tracker, data bars, mythic timer. Per-setting spec overrides.

Next builds, unless a test shows 0.2.0 is wrong:

1. **In-game pass** of this build. The static audit does not replace it.
2. **Absorbs and heal prediction** on the unit frames, then aura containers on those frames and on nameplates.
3. **Stance and pet bars**, then action-bar flyouts, if the main bars survive a combat reload.
4. Minimap, chat skin, data text. Bags and a custom quest tracker stay late. The quest tracker should skin Blizzard's tracker, not replace it.
5. **Cooldown manager** only if someone asks. It skins Blizzard's viewer frames and does not reparent them.

## Conventions

- `## Interface: 120105` is the first toc line. `## Version:` is semver. Bump it on every test build.
- Pixel snapping: `SoulUI.Pixel:Scale`. Also call `SetRoundLayoutToNearestPixel(true)` when the method exists.
- New per-frame work goes through `SoulUI.Ticker` or a duration object. No lasting `OnUpdate` that runs while idle.
- `SoulUI:Print` uses `DEFAULT_CHAT_FRAME:AddMessage` and stays quiet during chat lockdown.
- Defaults that match the owner's current layout are a starting point (wide player and target frames, cyan accent, flat bar). They are data, not copied code, and the editor can change them.
