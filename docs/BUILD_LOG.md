# SoulUI build log

Newest entries at the top. Each entry says what changed, why, which files, what is untested, and which machine.

## 2026-11-05 — laptop — 0.4.0 casts, dispels, vertical party, meter and menu restyle

The owner tested 0.3.0. Edit mode was much better. Still wrong:
- **Settings menu:** not close to Ellesmere's quality.
- **Casts:** no difference between interruptible and uninterruptible.
- **Dispels:** no dispel or purge tracking.
- **Party frames:** horizontal, with no way to change it.
- **Meters:** looked unrefined.

Reference: the EllesmereUI CurseForge gallery (Nameplates options screenshot) and the installed EllesmereUI source for the APIs.

**Casts (`Core/Casts.lua`, new).** Root cause: `Secret.PickColor` passed its colors to `C_CurveUtil.EvaluateColorFromBoolean` in the wrong order. The engine signature is `(bool, ifTrue, ifFalse)`. So interruptible casts were drawn gray and uninterruptible ones in the accent color, which made the two look reversed. The helper is fixed, and enemy casts (nameplates, target, focus) now go through `Soul.Cast.Paint`:
- **Interruptible:** gold.
- **Your interrupt on cooldown:** dark orange. The kick is the first known spell from a per-class list, read via `C_Spell.GetSpellCooldownDuration(id):IsZero()`, and re-colored on `SPELL_UPDATE_COOLDOWN`.
- **Not interruptible:** gray, with a lock icon.
- **Important casts** (`C_Spell.IsSpellImportant`): a pulsing red outline.
- **Important and not interruptible:** a STUN badge, made from two nested frames with `SetAlphaFromBoolean`, so the AND is computed by alpha multiplication, not by Lua.

Colors use `EvaluateColorValueFromBoolean` per channel, so secret booleans are never compared. Colors and toggles live in `theme.cast` and are edited under General > Casts. The STUN badge is a heuristic: the game's important flag plus uninterruptible. Bosses ignore stuns.

**Dispels (`Core/Auras.lua`, new).** Everything goes through `AuraContainer` groups, because 12.1 errors on Lua aura reads while auras are restricted. The highlight is a single frame-sized aura button with an outline. The engine shows that button only while the group filter matches, and tints it by dispel type where `AddDispelTypeTexture` is supported.
- **Party and raid buttons, and player/target/focus frames:** outlined while the unit has a debuff you can cleanse (`HARMFUL|RAID_PLAYER_DISPELLABLE`).
- **Enemy nameplates:** a row of buffs you can purge or soothe (`HELPFUL|DISPELLABLE`, blue ring), an outline on the plate, and your own debuffs (`HARMFUL|PLAYER`). Purge display defaults to "auto", meaning only when the player knows Purge, Dispel Magic, Spellsteal, Consume Magic, Devour Magic, Soothe or Tranquilizing Shot.
- **Enemy target/focus frames:** the same purge outline, only while you can attack the unit.
- **Friendly nameplates are not touched.** In instances they are forbidden to addons, so friendly dispels show on the group and unit frames instead. This is explained on the page.

The nameplate pool is now 30, built at login. Plates built later in combat have no aura rows.

**Party frames.** Vertical by default, with a Layout dropdown (vertical / horizontal). Existing profiles switch once (`profile._partyVertical`). The party column moves right of the left bar columns (`Soul:DefaultPartySpot` in Layout.lua).

**Damage meters.** Restyled, from our own code, to Ellesmere's proportions:
- **Header:** solid dark (#1B1B1B), with the meter name in the accent color and an accent underline. Segment and clock are dimmed. There are three icon buttons (segment, reset, hide), optionally shown only on hover. Click the title for the mode menu (right-click for the segment) using the shared UI kit menu.
- **Rows:** spec icon (class crest when no spec), class-colored bar, name left, value right.
- **Value formats:** `138M (412K)` (default), `138M | 412K`, total, per second, or total and percent.
- **Window:** black at 75%.
- **Tooltip:** total and per second on hover.
- **Settings:** bar texture, class colors on/off, bar opacity, row gap, text size, rank numbers, mark my row, header height/color/accent/underline, window border.

**Settings menu rebuilt again.**
- **Window:** 1240x800. Gradient background tinted toward the accent, with an accent glow and streak in the header. Drag the header or the brand to move it.
- **Sidebar:** brand mark, search across all settings, accent group headers, and module rows with an on/off dot (gray when the module addon is disabled).
- **Page header:** large title and description, tab bar, and a "search this page" box.
- **Live preview strip:** at the top of most pages, drawn from the same settings and redrawn on every change (`SoulUI_Options/Previews.lua`). Previews exist for unit frame, nameplate (cast, debuffs, purge ring and outline), cast colors, class resource tiles, action bar, party/raid and meter.
- **Rows:** sections are cards with divider lines and hover, in two columns.
- **Footer:** Reset Page, Reload UI, Edit Mode, and an outlined Done.

**Checks.** `node tools/lint.mjs` and `node tools/audit.mjs` pass. **Nothing here has been run in game.** Watch for:
- Whether `AddDispelTypeTexture` accepts the option table (on failure, the outlines show in their base color).
- Whether the aura highlight button really covers the whole frame, since button size is set in `initializeFrame`.
- STUN badge alpha nesting.
- Kick detection for warlock pets.
- The meter header icon textures (stock Blizzard files).
- The party column position on the laptop.

All addon versions are 0.4.0.

**Review pass (same day).** A separate code review found 14 issues, all fixed before commit:
- **Cast spell ID (in-combat error):** the `and/or` pick of the spell ID truth-tested a value that can be secret, which errors in restricted combat. It now picks by index.
- **Nameplate login hitch:** nameplate aura containers (90 at login, about half a second of hitch) are now built lazily on first use out of combat. Plates still missing them get them at `PLAYER_REGEN_ENABLED`.
- **Cast recolor cost:** recolors compute the kick state once per event, and cast state reuses one table per bar.
- **Smaller fixes:** inner important-outline anchors, failed previews no longer leak frames, a guard for disabled modules in previews, stack-count options, meter resize math and spell-icon coords, the party migration flag ordering, row hover reset, and STUN badge width in the cast preview.

The review questioned the `EvaluateColorValueFromBoolean` argument order. EllesmereUI's live code (`ev(isUnint, unintColor.r, cr)`) confirms `(bool, ifTrue, ifFalse)`. To check in game: `/run print(C_CurveUtil.EvaluateColorValueFromBoolean(true,1,0))` prints 1.

## 2026-11-05 — laptop — 0.3.0 editor rebuild, action bar sizing, shards, reference layout

The owner tested 0.2.12 and compared it to the reference stream screenshot. Problems: action bar icons oversized, spread apart and cut off on the right; soul shards washed out; the settings window unrefined, not working right and not movable; the overall layout not matching the reference. This pass also re-indexed the whole repo (the 0.2.x work was done through Cursor).

**Action bars.** Root cause: buttons were kept at 45px and `SetScale`d to the slot size, but `SetScale` also scales the `SetPoint` offsets, so each button landed `scale` times too far along and the clipping holder cut off the end of the row. Buttons are now sized for real and the template's fixed 45px `IconMask` is removed (the approach EllesmereUI's flat style uses). Flat highlight/pushed/checked overlays, optional 1px border, no clipping. New per-bar settings: buttons, rows (columns when vertical), keybind/count/macro text toggles. New global settings: text sizes and "show empty slots". Default spacing is 1px.

**Unit events (real bug, all modules).** `frame:RegisterUnitEvent(event, unit)` replaces the unit filter, and every module registered the same event once per unit on one frame. Only the last unit kept its events:
- Unit frames only listened to `vehicle`.
- Nameplates only listened to the newest plate.
- Group frames only listened to the last raid token.
- Meters' `UNIT_FLAGS` only listened to raid40.

`mod:RegisterUnitEvent` in `Core/Core.lua` now keeps one listener frame per unit token. Call sites did not change. This is the likely reason health text never moved off its first value.

**Soul shards / class pips.**
- **Tiles:** each pip is a bordered tile with an inset StatusBar gate.
- **Colors:** fill is the class color, the same as the player bar, as in the reference. Empty tiles are flat gray (0.17).
- **Spacing and finish:** 2px gap between tiles, gloss optional.
- **Count:** the shard count ("3") sits on the last full tile. Secret values drive it through step curves.
- **Settings:** size, gap, border, fill mode and color, empty color, count, count size.

**Layout.** `Core/Fit.lua` (heuristics that matched the old defaults) is gone. `Core/Layout.lua` computes the reference layout in "pitches": one pitch is a button plus 1px, and a button is about 3.35% of UI height (clamped to 34–50).
- **Action rows:** two 12-button rows, centered, with the lower row 20.6% up the screen.
- **Shards:** centered above the rows, half the row width, 0.68 pitch tall.
- **Player and target:** player bar 4.67 x 1.41 pitches, left of the shards with bottoms aligned. Target mirrors it on the right.
- **Pet:** left of the lower row, name above the bar, with a tiny 2x6 bar under it.
- **Left edge:** three 12-button columns.
- **Party:** a strip at the top left.
- **Meters:** three windows on the right.

It runs once per layout version (`profile._layoutVersion = 3`) and from Reset Layout. **The owner's existing profile gets the new layout once, on the next login.** After that, edits are never overwritten. The one-time 0.2.4/0.2.5 layout migrations were removed from `Core.lua` because the new layout replaces them.

**Unit frame text.** Two layouts: name top-left with "925K | 100%" bottom-right like the reference, or everything on one line. New settings:
- Health format: both, value, percent or hidden.
- Name on or off, inside or above the bar.
- Name and health text size.

The player cast bar is the Resources one, so the unit-frame player cast is off by default.

**Shared UI kit (`Core/UIKit.lua`).** New. Both editors use it. It contains:
- Windows, buttons, switches, sliders and number boxes.
- A dropdown menu that scrolls past 14 items and previews fonts and textures.
- A color swatch, a point picker, media lists and an accent registry.

**Settings window rebuilt.**
- **Window:** movable by dragging the title bar, with its position remembered. Pixel-perfect, with a window-scale setting.
- **Shell:** Ellesmere-style sidebar with search, page header, tabs, eased scrolling, a footer (Reload UI / Reset Page / Close) and an Edit Mode button.
- **Rows:** two columns. Controls are switches, sliders with typed values, dropdowns, font and bar-texture pickers and color swatches. Dependent rows grey out, and per-unit and per-bar selectors pick what you are editing.
- **Pages:**
  - General: Look, Modules, Tools.
  - Profiles: a list with activate/copy/delete, create, per-spec dropdowns, export and import.
  - Unit Frames, Nameplates, Damage Meters.
  - Party and Raid: Party and Raid tabs.
  - Action Bars: Bars and Style tabs.
  - Resources: Class Resource, Cast Bar, Power & GCD tabs.
- **Modules:** General > Modules turns each module on or off, with a reload prompt.

**Edit mode rebuilt.**
- **Toolbar:** movable, with grid and snap toggles. Snapping shows guide lines.
- **Moving and sizing:** Shift locks the axis, Alt turns snapping off, arrow keys nudge, the mouse wheel resizes, and right-click opens that element's settings.
- **Inspector:** movable, with X/Y/W/H, anchor target, 3x3 point pickers, nudge, color and reset position.
- **Save and Cancel:** Cancel now also reverts sizes, because it restores a snapshot of module settings. `/soul move` toggles edit mode and saves; Cancel discards.

**Meters.** The header clock showed "301:36:13". With no finished session, `GetSessionDurationSeconds` returned something like client uptime. Values above 24h are now dropped. The clock and the background opacity are settings.

**Commands.** `/soul`, `/soul move` (also `edit`), `/soul reset layout`, `/soul scale 0.5-2`, `/soul debug`, `/soul secret [off]`.

**Checks.** `node tools/lint.mjs` and `node tools/audit.mjs` pass. **Nothing here has been run in game yet.** Watch for:
- How icon art fits after the mask removal. If the rounded corner art returns after combat or a page change, the mask was re-added (`DropIconMask` runs on every button event).
- The pip count curve on a secret value.
- Menu and color picker layering over edit mode.
- Arrow-key nudge eating keys when nothing is selected.
- The default layout on the laptop (2560x1600) compared with a 1080p/1440p screen.

**Review pass (same day).** A separate code review of the new files found 15 issues, all fixed before commit:
- **Anchor loops:** an element could be anchored to its own child, for example player to player cast. `DependsOn` now refuses that in the anchor list and in `Place`.
- **Search menu:** the settings search menu closed on alternate keystrokes.
- **Snapping:** a frame snapped to its own cast bar while being dragged.
- **Cast previews:** previews stayed on after combat paused edit mode. Previews are also skipped for hidden cast bars.
- **Unit frame name:** the name was vertically centered in the corners layout.
- **Performance:** pips re-laid all tiles on every power event (now memoized), and the icon mask was re-cleared on every button event (now once).
- **Smaller fixes:** wheel resize minimum, cancelling the color picker writing a default as a custom color, the section rule anchor, a stray point-picker tooltip value, oversized bar holders on uneven rows, menu raise order, and a secret color reaching the swatch.

Files: Core (Core, UIKit new, Unlock rewritten, Layout new, Fit removed, toc), ActionBars, ResourceBars, UnitFrames, DamageMeters, Options (all four files rewritten), docs. All addon versions are 0.3.0.

## 2026-11-04 — laptop — 0.2.12 icon fit and live cast bars

Action buttons were still drawing the spell art at the template's 45px size, so the icons hung outside the bar. Each button now stays 45px internally and scales so its on-screen size matches the slot. The holder clips anything that still sticks out. The icon is pinned to the button again after the template's own events.

The editor cast bar is the same frame a real cast uses. The sample shows an icon, a spell name, and a time. A live cast fills that bar from `UnitCastingDuration` / `UnitChannelDuration` through `SetTimerDuration`, and the time ticks from a duration text binding. If the duration is not ready on the start event, it looks once more on the next frame. Closing the editor hides the sample. A target has to exist for the target cast to run.

Untested in game. Core version string is 0.2.12.

## 2026-11-04 — laptop — 0.2.11 editor select, anchors, cast bars

The editor wash was opaque and the name sat on top of the frame. Overlays are light, the name sits above the element, and a Shade slider on the banner changes that wash. Clicking an element selects it and shows width, height, and anchor controls. Anchor can be the screen or another element. Shift-drag on an edge is gone. Scroll scales up and down by a full pixel, including when the last step was too small to survive pixel snapping. Action buttons refill their slot when the bar size changes, so the icons grow and shrink with the bar instead of leaving gaps.

Unit-frame cast bars were never given a position, so the target cast bar could not appear in the editor. Each unit cast bar now sits just above its frame, and edit mode shows a preview labeled Cast even when nothing is casting.

Untested in game. Core version string is 0.2.11.

## 2026-11-04 — laptop — 0.2.10 centered bars, shard tiles, editor

The two horizontal action bars were centered on the player, so they sat under the left health bar. They now sit on the screen center, under the shards. Soul shards are short wide tiles, about half the health bar tall, brightened above the class color, with a light top edge and a flat gray empty tile. That is the shape and color in the reference, where the empty shards are gray rather than dark purple.

`/soul move` is the on-screen editor. Drag moves an element. Shift-drag on an edge stretches that axis. The scroll wheel scales it by one pixel per notch. Right-click opens a color picker for that element's fill. Sizes write back into the module settings, so a later login does not overwrite a size unless the frame is still on a fitted position that this layout moves.

Untested in game. Core version string is 0.2.10.

## 2026-11-04 — laptop — 0.2.9 bar text and shard join

The 0.2.8 reload put the cluster in the right area, but the player bar was too narrow for its own text, so the name collapsed to "...". The shards also sat in a gap to the right and hung below the bar. The health font is now capped at 14 so the name and the health number both fit, the bar is wider, and its right edge meets the shard row. Shards stay on the screen center and share the bar's bottom edge. A light-to-dark shade sits on the health fill.

Untested in game. Core version string is 0.2.9.

## 2026-11-04 — laptop — 0.2.8 reference layout

Measured the stream frame instead of guessing. The player bar is left of center and about twice as tall as the 0.2.7 bar. The target is its mirror. The five soul shards sit in the center gap between those bars, not under the player. The smaller button row and the main bar hang under the player, clear of the chat. Left bars stay on the left edge at the same button size. Party frames grow sideways in a strip at the top left. Empty shards keep a dim class-color plate instead of a black hole. Meter panels are shorter and more transparent.

Sizes are fractions of the current screen, so the same picture holds at different UI scales. A frame still on a shipped default, the last fitted spot, or off the screen moves. A hand-dragged on-screen spot stays.

Untested in game. Core version string is 0.2.8.

## 2026-11-04 — laptop — 0.2.7 load-path secret guards

Went through every module that runs at login. The cast crash was `type()` receiving no value when an API returns nothing. The same mistake was still in cast duration checks, and several first-update paths compared or indexed values that are secret even in a city. Health is always secret, so abbreviating it now goes straight to `AbbreviateNumbers` and never calls `type()`. Nameplates no longer truth-test `UnitIsPlayer` or `UnitIsDeadOrGhost`. Group range, action-button charges, and meter totals check `issecretvalue` before any compare or field read. The audit script now flags `type(SomeCall())`.

Untested in game. Core version string is 0.2.7.

## 2026-11-04 — laptop — 0.2.6 screen fit and enable crash

Resource bars and unit frames died on login because `type(UnitCastingInfo())` runs with no value when the unit is not casting. That aborted enable, so class color, shard size, and the rest of the layout never finished. Cast checks now keep the first return and use `Secret.Present`. The same call sites in nameplates were changed too.

The 0.2.5 coordinates assumed a huge UIParent, so on this screen the player cluster sat in the bottom-left corner, the left bars fell off the left edge, and the meters fell off the right edge. `FitLayout` runs at login and places the cluster from the real UIParent size: class-colored player and target pair, square shards centered under the player bar, a smaller button row, then the main bar, two vertical bars inset from the left edge, and three meters inset from the right edge. It only moves a frame that is still on a shipped default, still on the last fitted point, or off the screen. Health and shard borders are hidden so the bars read as flat color. The escape button hangs just under the game menu instead of covering Return to Game.

Untested in game. Core version string is 0.2.6. `/reload` picks it up. A frame that was dragged to an on-screen spot will stay there.

## 2026-11-04 — laptop — 0.2.5 match the stream layout

The stream shot is the target. Player and target are a wide pair. Five large soul-shard squares sit under the player bar, then a shorter button row, then the main bar, all centered on that bar. Two vertical bars sit on the left. Meters are slim panels on the right: title on the left, a clock on the right (hours when the fight is long), and an x that hides that window. Health text reads like `925K  (100%)`. A shield still fills missing health, and a light overlay shows absorb while the bar is full.

`/soul` waits 0.2s and opens at full alpha, so the chat Enter key cannot fade it back out. The escape menu gets a SoulUI button parented to the bottom of the game menu on show, because the menu tag never produced a visible row.

Migration `layout-stream-0.2.5` moves frames that are still on the 0.2.0 or 0.2.4 defaults. A dragged position stays. Untested in game. Core version string is 0.2.5.

## 2026-11-04 — laptop — 0.2.4 layout, shield, editor, escape menu

The editor flashed and closed because Enter in chat hides every special frame after the slash command. `/soul` now opens on the next frame. The escape button never appeared because a successful `Menu.ModifyMenu` call was treated as done even when that menu tag is not the game menu. The installer now hooks `GameMenuFrameMixin:InitButtons`, adds the button on show, and still registers the menu tags.

Layout follows the centered lower arrangement from the owner's live UI. Player and target health are a matching pair at ±560, -320, with no power strip on the frame. Soul shards sit between them, 380 by 32, and partial shards use the raw power scale of 10 so the fill can be fractional without dividing a secret. Primary power and the player cast sit under the player frame. Main bar and bar 2 sit under the pair. Bars 3–5 are vertical columns on the left. Meters sit on the right, with taller rows. Raid frames default to 64 tall. A one-time migration (`layout-lower-center-0.2.4`) moves a frame only when it is still on the previous default, so a position that was dragged stays.

Health bars draw a shield in the missing portion. A clip anchored to the health fill shows `UnitGetTotalAbsorbs` and hides the rest, so the shield length is the overlap of absorb and missing health without comparing secrets.

Untested in game. Core version string is 0.2.4. If a frame was already dragged off the old default, reload will not move it; `/soul move` will.

## 2026-11-04 — laptop — 0.2.3 list editor, meter header, bar plates

The 0.2.2 layout fix left the editor as a stack of filled rectangles, the meter header as three gray buttons, and empty action slots as holes.

**Editor.** Setting rows are a hairline list. Section titles get a short accent rule. Toggles slide over 0.12s and take the accent color when on. Slider thumbs and values follow the accent. The active page in the sidebar gets a quiet fill, and a divider splits the sidebar from the page.

**Meters.** Mode, segment, and Reset are text on the header. Hover washes the text. Reset stays dim.

**Action bars.** An empty slot is a dark plate. The hover highlight is a white wash. Keybinds sit at the top right of the icon, counts at the bottom right.

**Unit frames.** The name stops at the health text so the two do not draw through each other.

Untested in game. Core version string is 0.2.3.

Files: Options widgets and panel, DamageMeters, ActionBars, UnitFrames, core version.

## 2026-11-04 — laptop — 0.2.2 editor, meters, plates, bars, profiles

First in-game pass. The suite worked, and the layout did not. This pass is the visual and settings cleanup from that session.

**Editor.** Inactive pages stayed shown, and the scroll frame did not clip, so General's buttons sat under Damage Meters and slider values drew past the panel. Pages now hide, the scroll clips, and page width is a fixed 720. A scrollbar thumb tracks the scroll. The panel fades in. Dropdowns replace the cycle buttons for meter mode, meter segment, and bar visibility.

**Meters.** Three windows default to damage current, damage overall, and healing current, each with its own header dropdowns and a Reset button. Reset calls `C_DamageMeter.ResetAllCombatSessions` (one shared reset; the API has no per-window reset). Bars ease with `ExponentialEaseOut`. A saved profile is migrated once (`meters-three-windows-0.2.2`) so the tested profile picks this up. Positions are kept. Width 220 becomes 300 so the header fits.

**Nameplates.** `nameplateShowAll` was forced on, which stacked every friendly city plate. It now stays off unless "Show every friendly nameplate" is on. Stacking is on by default (`nameplateMotion` 1, overlap 0.4). The plate visual is the health bar only; the cast hangs underneath instead of reserving empty space.

**Action bars.** Button chrome and the pixel border start hidden. "Button borders" turns the pixel border back on. The stock button frame stays hidden either way.

**Profiles and escape.** Letting go of a mover writes that position into the active profile. Cancel restores the snapshot from when unlock opened. The profile string already carries positions and settings. Escape's game menu gets a SoulUI button via `Menu.ModifyMenu("MENU_GAME_MENU")`, with a `GameMenuButtonTemplate` fallback.

**Untested in game.** The menu tag, nameplate stacking CVars, borderless action buttons, the meter migration on the existing profile, and whether the header fits at UI scale 0.53. Core version string is 0.2.2.

Files: core Menu, Unlock, Pixel, version; Options panel, widgets, pages; DamageMeters; Nameplates; ActionBars.

## 2026-11-04 — laptop — 0.2.1 meter refresh at 4 Hz

The combat ticker was 1 second and refused anything faster than 0.5. Default is now 0.25 seconds (4 updates a second). The editor slider is "Updates per second", from 1 to 4. Changing it while a ticker is already running restarts that ticker. The header clock stays on a half-second tick because it only shows whole seconds.

Files: `SoulUI_DamageMeters/Defaults.lua`, `DamageMeters.lua`, `SoulUI_Options/PagesModules.lua`. Both addon versions are 0.2.1. Untested in game.

## 2026-11-04 — laptop — 0.2.0 party, raid, bars, resources, meters

The owner has not loaded SoulUI in game yet. This pass adds the next four modules and checks the 0.1.0 framework against `docs/research/` before that first boot. Cooldown Manager is not in this build.

**Why.** Party and raid frames, action bars, resource bars, and damage meters are the pieces needed for a normal combat UI. The cooldown manager was explicitly deferred. Designs follow the research notes (secure group headers, our own action buttons, pip gates, `C_DamageMeter` only). The code is original.

**Framework check.** Health coloring now lives in `SoulUI/Core/Units.lua` and bails out before it branches on a secret class, tap, or reaction. Unit frames call it. `node tools/lint.mjs` and `node tools/audit.mjs` both have to pass. The audit rejects a combat-log registration, `table.sort` in the combat modules, numeric `SetCooldown`, `CallMethod` in secure snippets, and `Hide()` on a Blizzard bar or raid frame. It also checks that the new modules call the APIs the research settled on.

**What landed**

- `SoulUI_GroupFrames` — one party header and one raid header (`SecureGroupHeaderTemplate`). Health is a 0–100 percent bar. Raid grows units right and groups down. Buttons are pre-spawned at login. A dispel icon row is added with `pcall` so a rejected aura API does not take the frames down. Blizzard compact party and raid frames are reparented to a hidden frame, not `Hide()`d.
- `SoulUI_ActionBars` — eight bars, our own secure buttons, file-load reparent of the stock multi-bars. `MainActionBar` stays at alpha 0 so `ACTIONBUTTON` bindings still fire, and the page snippet mirrors `actionpage` onto it. Cooldowns go through `GetActionCooldownDuration`. Stance and pet bars are untouched.
- `SoulUI_ResourceBars` — primary power, class pips (status-bar gates) or death knight runes, player cast, GCD spell 61304. No swing timer.
- `SoulUI_DamageMeters` — three windows, one shared 1s ticker while the group is in combat, server order, `damageMeterEnabled` forced off with the old value remembered. Spell breakdown is out of combat only.
- Editor pages for all four, under Frames and Combat.

**Untested in game (0.1.0 list still applies, plus these)**

- Combat reload with the new secure headers and action buttons. Secure setup runs at `PLAYER_LOGIN`, and stock bars are reparented at file load. Both still need a real reload in combat to confirm.
- Party layout in a party, raid layout in a raid, and the pre-spawned buttons actually existing before the pull.
- Right-click menu on a group frame (`togglemenu` on the header button).
- Action-bar paging for stance, vehicle, and override, and that empowered spells still fire through the native bindings.
- Cooldown swipe and desaturation inside a restricted instance (`/soul secret`).
- Class pips for a combo-point spec, holy power, and runes. Cast color argument order is still the open question from 0.1.0.
- Meter rows during combat (secret amounts must not Lua-error) and the percent text after combat.
- `SetAlphaFromBoolean` scale, still unverified. Range fade on group frames uses it.

**Known limits.** No absorbs, no unit-frame auras, no nameplate auras, no stance or pet bar, no cooldown manager, no swing timer. Extra action bars 1–3 start disabled. Mouseover bars fade instead of hiding, so an invisible bar can still be clicked if the cursor is over its rectangle.

## 2026-11-04 — laptop — 0.1.0 first playable build

Research was already in `docs/research/` (Midnight API, Ellesmere core, options editor, frames and plates, meters, other addons). No addon code, architecture doc, or build log existed yet. This entry is the first implementation.

**Why this slice.** A full Ellesmere-sized suite cannot be validated in one pass. 0.1.0 is the smallest build that proves the decisions the rest of the suite sits on: one saved-variable store, secret-safe health and casts, a real editor, and movers. Action bars, raid frames, auras, and damage meters are deliberately not in this build. Their designs are locked in `docs/ARCHITECTURE.md` so the next session does not reopen them.

**What landed**

- `docs/ARCHITECTURE.md` — module layout, saved-variable schema, secret rules, and the phase plan.
- `SoulUI` core: client gate, module lifecycle, profiles, pixel snap, media, combat queue, unlock mode, profile strings (`!SOUL1:`), Wago-shaped `SoulUIAPI`.
- `SoulUI_UnitFrames` — player, target, focus, target-of-target, pet. Health, power, name, cast bar. Blizzard versions of those frames are hidden while the module is on.
- `SoulUI_Nameplates` — enemy and neutral plates only. Friendly plates, including friendly plates inside instances, stay Blizzard's.
- `SoulUI_Options` — LoadOnDemand editor (`/soul`): General, Profiles, Unit Frames, Nameplates.
- Embedded, unmodified libs: LibStub (public domain), CallbackHandler-1.0, LibSharedMedia-3.0 (LGPL-2.1). See `SoulUI/Libs/NOTICES.txt`.

**Untested (needs an in-game pass)**

- Load, `/reload`, and a combat reload. Watch BugSack.
- Health, power, names, and cast bars on a training dummy and on a friendly target.
- `/console addonCombatRestrictionsForced 1` then the same, to confirm secret values do not Lua-error.
- Nameplates on hostile NPCs. Confirm friendly nameplates were not replaced.
- `/soul` edits apply without a reload. `/soul move` drag, Save, Cancel, and a reload that keeps the position.
- Profile create, copy, export, import.
- Right-click unit menu. If it errors, the secure proxy needs another pass.
- Cast-bar color when a cast cannot be interrupted. The boolean helper's argument order is marked in code and may be swapped.
- `SetAlphaFromBoolean` scale (0–1 vs 0–255) is still an open question in the Midnight notes.

**How to test.** Disable the EllesmereUI addons first or the two UIs will draw on top of each other. Run `tools/link-addons.ps1` once so the WoW AddOns folder points at this repo. `/soul` opens the editor. `/soul move` unlocks frames.

**Known limits of 0.1.0.** No absorbs, heal prediction, auras, raid frames, action bars, resource bars, cooldown manager, or damage meter. No anchor links between frames. No spec-override watcher (per-spec profile assignment exists; per-setting overrides do not).
