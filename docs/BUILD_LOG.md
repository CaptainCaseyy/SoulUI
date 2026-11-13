# SoulUI build log

Newest entries at the top. Each entry says what changed, why, which files, what is untested, and which machine.

## 2026-11-13 — laptop — 0.9.19 vendor checked; empty bag filters say so

**Auto repair works (checked at a repair vendor).** It paid from guild funds first: "Repaired for 15g 49s (guild)".

**Sell junk.** The character had no gray items, so nothing was sold, and the feature correctly printed nothing. Selling an actual gray item is still unchecked.

**Empty bag filter (`Bags.lua` `Layout`).** A sidebar category with no items, such as Junk, showed only the "Free" block, which looked like a glitch. It now also shows a dim "Nothing in <category>." line under the free slot. The line hides again on All or on any category that has items. Checked in game.

## 2026-11-13 — laptop — 0.9.18 bank checked at a banker

**Bank tab buttons (`Bank.lua`).** A tab with no chosen icon carries the game's question mark (134400), so three unset tabs showed as red and grey question marks. That looked like an error. Such a tab now shows its number, white when selected and dim otherwise.

**Tooltips in a row (`UIKit.lua` `ShowTip`).** A tooltip normally sits to the right of its owner, which on the tab strip covered the next tab. An owner with `_tipBelow` gets its tooltip below instead; the bank tabs use it.

**Checked in game, at a banker:**
- The bank opens with the bags.
- Bank and Warband switch; Warband shows BoE tags and "Deposit warbound".
- The tab buttons switch the contents.
- The X ends the bank visit and closes the bags.
- "Blizzard bank" hands the visit to the stock frame.

**Not checked:**
- Deposit reagents, deposit warbound, sort, and right-click deposit: these move the owner's items.
- Vendor repair and sell junk.

## 2026-11-13 — laptop — 0.9.17 keystone and buff check windows, visible chat copy button

**Keystone popup (`/soulkeys`) and ready-check buff list (`Raid.lua`).** Both were plain dark boxes with a letter "x". They now use the shared `UI.Window`:
- A title band you drag to move; the position is saved per window.
- The drawn close button, and Escape closes them (`UISpecialFrames`).
- The panel scale is applied.
- "Say in party" is an outline accent button.

**Chat copy button (`Chat.lua`).** Its idle opacity went from 0.35 to 0.7: on a faded chat window it was nearly invisible.

**Checked in game.**
- `/way 50 50` sets the pin.
- `/soulkeys` shows the new window, and Escape closes it.
- The copy button is visible and opens the copy box.

**Not checked.**
- The bank and warband bank, and vendor repair and sell junk (these need the character at an NPC).
- The buff check window: it needs a ready check.

## 2026-11-13 — laptop — 0.9.16 older profiles keep their old look

The owner's call: profiles from before the 0.9.14 defaults keep the look they had.

**Why.** A value equal to the old default was stripped at logout, so it is nil in the saved profile and would silently pick up Cursor's new default.

**Migration `look-0.9.15` (`Database.lua InitDB`).** It applies only to profiles with layout version 1–3, and pins the old value only where the profile has nothing of its own:
- **Action bars:** empty slots shown; no macro text on the main bar.
- **Meters:** value format "both", no rank, background 0.75.
- **Nameplates:** cast height 12.
- **Resources:** class-colored shards; gap 2, height 32, width 276; cast bar 22 x 276.
- **Unit frames:**
  - The pale solid shield (light blue, 0.5 alpha, overflow 0.22).
  - The target frame has no custom color.
  - The player name size is automatic.

The accent color and meter 1's size were already pinned by `accent-0.9.14`.

**Merge change.** `Merge` now leaves an explicit `false` in place when the default is a table. Before, `false` ("deliberately no custom color") was replaced by the default table, which would have painted the target frame white.

**Unaffected.** The owner's laptop profile is version 4: it is the source of the new defaults.

**Checked in game.** `/reload` loads cleanly and the laptop profile looks the same.

**Not checked.** An actual pre-0.9.14 profile, such as the home PC or a guild member, keeping its look.

## 2026-11-13 — laptop — 0.9.15 review of the Cursor build, checked in game

Cursor shipped 0.9.1–0.9.14 in one commit (b30e7ee): new Bags and QoL modules, plus changes to core and every module. That commit was never reviewed. Three Claude reviewers each read one area line by line and fixed what they found. The lead checked the live game before and after.

**Layout and profiles (`Layout.lua`, `Database.lua`).**
- **Every existing profile was being overwritten.** Layout v4 rebuilt any profile below v4, and `BuildDefaultLayout` wipes `unlock.positions`, so every guild member's layout (and the home PC's) would be replaced on login. A profile with an older `_layoutVersion` now keeps its layout, is flagged v4, and prints once that Reset Layout loads the new default.
- **Reset Layout** now also resets sizes (`ResetGeometry`), not only positions.
- **Other screen sizes:** the 1920x1200 snapshot is fitted to the current screen. Each element keeps its distance to the nearest edge (`Fit`).
- **Migration `accent-0.9.14`:** older profiles keep the cyan accent and their meter 1 size instead of switching silently.
- **Not pinned (the owner decides):** other new defaults, such as `showEmpty`, meter value format and rank, and the striped shield look, still apply to profiles that never changed them.

**Bags (`SoulUI_Bags/*`, `PagesBags.lua`).**
- **Window behaviour:**
  - It keeps its top edge when filtering or searching (`BG.PlaceTop`); before, it jumped under the cursor.
  - The item area scrolls inside a height cap (`maxHeight`, default 560).
  - The sidebar no longer runs into the footer, and gold has separators ("965,326").
- **Stack splitting:** it called the removed global `SplitContainerItem`; it now uses `C_Container.SplitContainerItem`.
- **List rows** used `btn:Click()` from addon code, which the game blocks. The real secure slot button now sits in each row.
- **Item level:** gear not yet cached stayed blank forever. It now waits for `GET_ITEM_INFO_RECEIVED`.
- **Pinned toggle** did nothing (missing default).
- **Quick action button:**
  - Its setup waits until out of combat.
  - It takes both click directions.
  - It is hidden for unknown spells and hides when the bags close.
- **Bank cooldowns** repaint now.
- **Footer:** buttons no longer overlap.
- **Performance:** no per-slot table churn.
- **Alts and gold panels:** they close with Escape and can be dragged.

**Quality of life (`SoulUI_QoL/*`, `PagesQoL*.lua`).**
- **Raid.lua `UI` was undefined:** the buff check and keystone popup would error.
- **Buff check:** reading auras throws while auras are restricted on 12.1; it is now pcall'd per unit.
- **Pull timer and world markers:**
  - Markers use the right icons and take both click directions.
  - The secure marker bar is no longer shown or hidden in combat.
  - The pull timer has its own size and no double countdown.
- **Secret values:** a secret compare in Versatility was removed.
- **Death alert:** each death alerts once.
- **Accepting a group invite** marks the popup accepted, so it does not decline on hide.
- **Containers:** they are never opened while a vendor, bank, mail, trade, auction house or guild or warband bank is open.
- **Chat:** a link opens the copy box once.
- **Tools, rewritten:**
  - Shift-drag uses the 12.x frames and hooks windows that load later.
  - `/way` checks its input.
  - Rested, healthstone, talents and combat text update and undo correctly.
  - The cursor trail and GCD ring OnUpdates run only while on.
  - Shared size keys are split.
- **Skins** undo cleanly.
- **Labels and tab notes** now match what each switch does and its default.

**Core and modules.**
- **Damage meters:**
  - The resize grip stops if the window hides mid-drag.
  - The saved position math is fixed.
  - Header drag clears the client's own saved position.
  - The All-windows Width and Rows sliders work again.
- **Action bars:**
  - The extra-button rescue leaves Blizzard's container alone and no longer blocks world clicks above center.
  - The proc alert is no longer scaled twice.
  - The press textures no longer allocate a table per click.
  - Stack text fits the 12px extra bar.
- **`PullInside`** only moves single-anchor UIParent frames. **`ClampToScreen`** skips secret anchors.
- **Edit mode:**
  - The toolbar is TOOLTIP strata, level 800, under the dropdown lists.
  - `CloseUnlock` hides the edit surface first.
  - The "Cancel does nothing on first open" report was the input tool jumping the cursor and clicking in the same instant: WoW had not registered the hover yet. With the cursor resting on the button, Cancel closes edit mode on the first open after a reload. Checked in game.
- **New glyphs** `bag`, `checklist` and `spark`; the Bags and Quality of Life sidebar rows use them.

**Checked in game (12.1.5, after `/reload`):**
- The bags open on B.
- The category filter keeps the header fixed.
- Search focuses, dims non-matches and clears on Escape.
- Gold and scroll display correctly, and Escape closes the window.
- The Bags and all nine QoL tabs build.
- Edit mode opens, and Cancel and Escape close it.
- The sidebar icons show.

**Not checked:**
- The bank and warband bank, splitting, list mode and quick action.
- Every QoL automation: these need a vendor, invites, cinematics, a ready check and a key.
- Meters and action bar procs in combat.
- The extra action button on a chest.
- Reset Layout on a 1080p screen.

## 2026-11-13 — laptop — 0.9.14 current profile is the default layout

Layout version 4 is the owner's live Default profile: frame positions, bar sizes, meter window, unit frame sizes, and the quality-of-life switches that were on. A new profile and Reset layout both start there. Class color is the default accent. The settings window scale starts at 1.55.

Files: `Layout.lua`, `Database.lua`, Defaults in Unit Frames, Action Bars, Damage Meters, Nameplates, Group Frames, Resource Bars, and QoL.

## 2026-11-13 — laptop — 0.9.14 meter resize starts on click

The corner waited for a drag gesture, so a hold at the screen edge never moved far enough to begin. Resizing now starts on mouse-down and keeps following until the button is released, even after the cursor leaves the grip.

Files: `DamageMeters.lua`.

## 2026-11-13 — laptop — 0.9.13 smooth meter resize

Dragging a meter's corner was rebuilding the window on a pixel grid, so the size jumped. The frame now tracks the cursor for the whole drag and keeps that size when you let go. The top-left corner stays put.

Files: `DamageMeters.lua`.

## 2026-11-13 — laptop — 0.9.12 move and resize meters directly

Each damage meter can be dragged by its header and resized from a grip in the bottom-right corner, without edit mode. Width and row count are stored on that meter. A chevron on the left of the header opens the list of what the meter shows. Right-click the header still switches Current and Overall.

Files: `DamageMeters.lua`.

## 2026-11-13 — laptop — 0.9.11 dropdowns above the element panel

The element panel and the edit toolbar were on the same layer as dropdown lists, and a click raised the panel over the list. The panel and toolbar sit under the lists now. A dropdown list is raised again on the next frame so the click cannot cover it.

Files: `UIKit.lua`, `Unlock.lua`, `Core.lua`.

## 2026-11-13 — laptop — 0.9.10 stacks, procs, press flash, aura stack

Stack numbers use a thick outline and a larger automatic size. Action Bars has a stack brightness slider, and the size slider goes higher.

Procs use Blizzard's gold burst and spinning ring, scaled to the button, instead of the thin edge. The pressed, checked and highlight textures are anchored to the button, including on mouse down, so they follow that button's size instead of staying at 45px.

Nameplate buffs and debuffs sit between the health bar and the name. The name and the classification mark move up with them.

Files: `ActionBars.lua`, `Defaults.lua` in Action Bars, `PagesModules.lua`, `Nameplates.lua`, `UnitFrames.lua`, `Core.lua`.

## 2026-11-13 — laptop — 0.9.9 extra action button, target auras

The extra action button sits on the main bar, and that bar is faded out, so a chest or zone button never appears. The extra bar and the zone ability bar are moved onto the screen, above center, and kept clickable.

Target and focus frames had no aura icons. They now show the unit's buffs and debuffs. Nameplates show the same two rows, not only your own debuffs.

Files: `ActionBars.lua`, `UnitFrames.lua`, `Nameplates.lua`, `Core.lua`. Needs a `/reload`. Not confirmed on the chest yet.

## 2026-11-13 — laptop — 0.9.8 bags stay out of edit mode

Edit mode was opening the bag window, and the mover was the full window, so nothing underneath could be selected. The window stays closed while editing. A small Bags tag marks its spot. If the bags were already open, they close for the session and open again when edit mode ends.

Files: `Unlock.lua`, `Bags.lua`, `Core.lua`.

## 2026-11-13 — laptop — 0.9.7 shield hatch, bottom menu

The striped shield tiled horizontally only, so each stripe stretched to the full bar height and read as a few huge diagonals. It now tiles in both directions inside the clip, which keeps the hatch at the texture's own size.

The retail micro menu and bag row were drawn past the bottom edge of the window. After login, and when they show, they are pulled back inside while Edit Mode is closed.

Files: `UnitFrames.lua`, `Blizzard.lua`, `Core.lua`.

## 2026-11-13 — laptop — 0.9.6 shield color, keep every frame on screen

The raid-frame stripe texture ignores status-bar color, so the shield stayed white. The fill is a white bar tinted with the chosen color, and the stripes sit in a clip the size of that fill. The stored shield color has no red channel, so it paints white until the color is picked again. The color picker writes the color when it closes.

The previous on-screen nudge read GetRect, which does not match a frame whose scale differs from the parent, so a bar saved past the edge never moved. The nudge now uses the anchor and the frame's real size. It runs again shortly after login, and the escape menu and editor windows use it too. Saved positions are not rewritten.

Files: `UnitFrames.lua`, `Unlock.lua`, `Core.lua`, `UIKit.lua`, `Menu.lua`.

## 2026-11-13 — laptop — 0.9.5 frames back on screen, shield stripes

The bag window rewrote its anchor on every refresh and walked off the window. That nudge is gone. Frames that sit past the current window (the layout was saved at 1920x1200; this client is smaller) are pulled back inside once. The saved position is not changed.

The striped shield was a second texture, tiled horizontally and vertically and anchored to the health fill, so the lines ran outside the bar. The stripes are the status bar texture again, tiled across the fill only. The opacity slider is the bar's alpha.

Files: `Unlock.lua`, `Bags.lua`, `UnitFrames.lua`, core toc.

## 2026-11-13 — laptop — 0.9.4 quality chip, striped shield, square map

The bag chip was still wrong because a bare item id does not carry Midnight's reagent mark. The slot now asks `GetItemReagentQualityInfo` with the item link (the id only if the link is missing) and draws `iconInventory`. The template's own diamond overlay is hidden. The thin slot border is unchanged. The bag window nudges itself back on screen when the sidebar pushes it off the right edge.

Striped shields were a solid white fill under a stripe texture that ignores its own alpha, so the slider did not change the pattern you see. The fill is clear and the bar's alpha is the slider. Party and raid frames now draw the same overflow wash over the health bar, not only the piece past the end of the health.

Square minimap sets the client's square mask (texture 130937). A file path was leaving the round mask in place. Compass and ring art are hidden while the option is on.

Files: `Bags.lua`, `UnitFrames.lua`, `GroupFrames.lua`, `Skins.lua`, `Core.lua`, those tocs. Not confirmed in game yet.

## 2026-11-13 — laptop — 0.9.3 crafting quality, shields, minimap

The bag quality mark was still the old Dragonflight diamond (`Professions-Icon-Quality-Tier`). Asking the game by item id did not return the Midnight chip. See 0.9.4. The thin slot border was put back.

The striped shield texture ignores its own alpha. The opacity slider now fades the whole shield bar, stripes included.

Shield sliders did nothing because every health update cleared the shield color. The color is put back after each update. The default shield is a white striped pattern, at 90% on the part past your health and 75% on the overflow laid over the bar. Party frames use the same shield.

Square minimap was only changing the mask, so the round border art stayed. That border is hidden while the option is on, and a square edge is drawn instead.

Not checked after this change. `/reload`. Open bags on a quality reagent. Change shield opacity with a shield up. Turn on square minimap.

## 2026-11-13 — laptop — 0.9.2 bag layouts and the rest of the helpers

The bag window was one category grid. It now has three styles (one categorized bag, one block per bag, and a list), a category sidebar, alt-click to pin, shift-right-click to split a stack, a quick-action button for a spell such as Disenchant, an Alts list of what each character was carrying the last time their bags were opened, and a Gold button for recent gold changes. Alts and gold live on the account, not in the profile.

Quality of life gained the rest of the practical set. `/soulpull 10` counts down and talks in party or raid. World marker buttons are secure so they survive combat. A ready check lists how many helpful auras each person is showing, and says when that number is hidden. `/soulkeys` shows your keystone. Shift-drag moves a handful of Blizzard windows. `/way x y` drops a map pin. Chat can be covered until you mouse over it. Target distance, rested, healthstone, unspent talents, a movement cooldown, the scrolling combat text font, a cursor trail, and a GCD ring are switches. The quest tracker header, the minimap, and chat can take the SoulUI font. Chat message text is not rewritten.

Not in this build, because the game does not hand an addon that data: other players' keystones, a combat-log damage stream, and a full crest-upgrade spreadsheet. The buff check is a count, not a flask-by-flask raid window.

Files: `Bags.lua`, `BagsExtra.lua`, `Defaults.lua` in Bags and QoL, `Raid.lua`, `Tools.lua`, `Skins.lua`, `PagesBags.lua`, `PagesQoLMore.lua`, tocs.

Not tested in game. Restart once so the new files load. Open bags, switch Style, alt-click an item, and try `/soulpull 5` and `/way`.

## 2026-11-13 — laptop — 0.9.1 bags and quality of life wired in

The bags and quality-of-life addons were written but not finished. The quality-of-life toc asked for a Keybinds file that does not exist, so the addon would not load. There was no settings page, and neither addon was on the module list.

- Removed the missing file from the toc.
- `/soul` now has Bags (already written) and Quality of Life, under Utility. Every switch calls Apply, so it takes effect without a reload.
- Both addons are on General > Modules, and their frames are on the show/hide page.
- The group death alert also watches the player, not only party and raid units.

Bags is one window: categories, search, sort, item level, quality borders, gold and currencies, plus the bank and warband bank. Blizzard's bags are parked, not hidden with Hide(). Quality of life covers repair, junk selling, loot and popup helpers, quests, chat copy, and the on-screen trackers. Anything that accepts or skips for you starts off. Repair and selling gray items start on.

Files: `SoulUI_QoL.toc`, `Displays.lua`, `PagesQoL.lua`, `Pages.lua`, `SoulUI_Options.toc`.

Not tested in game. Restart the client once so WoW sees the two new addons, then `/reload`. Open bags with B. Open a vendor for repair and junk. Open `/soul` and turn a tracker on, then `/soul move`.

## 2026-11-13 — laptop — 0.9.0 logo, clearer text, shields, clickable casts

The owner asked for:
- clearer text (the black outline was hard to read);
- a customizable shield bar;
- enemy cast bars you can click to target;
- a check of nameplates and party frames in game;
- the SoulBound website logo as the addon icon and an animated menu mark;
- a bags redesign and EllesmereUI's quality-of-life features (separate entries below when they land).

**Logo.**
- **Source:** `SoulUI/Media/Source/soulbound-mark.svg`, a copy of `public/brand/mark.svg` from the owner's SoulBound website repo (`WoWWebsiteRepo`).
- **Build:** `tools/build_logo.py` rasterizes it with Pillow, with no downloads: drawn at 4x and downsampled, even-odd holes, vertical gradients. It writes 256px TGAs with the same header as the other textures:
  - `Logo.tga`: everything.
  - `LogoBook.tga`: the open book.
  - `LogoSoul.tga`: the swirl, the wisps and the star.
  - `LogoSparkles.tga`: the sparkles.
- **Addon icon:** every `.toc` now has `## IconTexture: Interface\AddOns\SoulUI\Media\Textures\Logo`, which shows in the addon list.
- **Settings window (`Panel.lua`):** the mark is the three layers.
  - On open, the soul rises 9px out of the book and fades in, then the sparkles fade in.
  - While the window is open, the soul floats 1.5px, the sparkles twinkle and a soft blue glow breathes.
  - The `breathe:Play()` / `breathe:Stop()` call sites are unchanged.

**Text (`Core/Media.lua`, `Database.lua`, Look page).** Modules passed "OUTLINE" to `Soul:ApplyFont` everywhere, which ignored the theme. "OUTLINE" now means "the frame text style", which follows General > Look > Text style. The new default "SHADOW" draws no outline and a soft 1px drop shadow. Outline, Thick outline and None stay available.

**Shields (`UnitFrames.lua`, Unit Frames > Shields).** The default stays the owner's pale wash. New options:
- Placement: full height, bottom strip or top strip.
- Pattern: solid, striped (Blizzard's tiled `Interface\RaidFrame\Shield-Overlay`) or the bar texture.
- Color, plus shield opacity (past the fill) and overflow opacity (the pale band).

**Clickable enemy cast bars (`Nameplates.lua`).** Clicking inside an enemy nameplate's frame targets it, and `C_NamePlate.SetNamePlateSize` sets that frame.
- `NP:ApplyHitbox()` sizes it to the health bar plus the cast bar below it, with enemy hit insets of -10000 so the whole frame counts.
- Our bar moves up by half the cast drop so both sit inside the frame.
- It runs out of combat and is queued if needed. The setting is `castClick` (Nameplates > "Click the cast bar to target"). The same API is studied from Ellesmere's hitbox code; the code here is our own.

**Party "Show while solo" never worked (`GroupFrames.lua`).** The visibility rule allowed solo, but the header was hard-coded `showSolo = false`. Fixed.

**Checked in game:**
- Text is shadowed, not outlined.
- The party frame shows when "Show while solo" is on and hides at once when it is turned off.

**Not checked:**
- Enemy nameplates and the cast click: there are no enemies in town.
- The logo textures: new files need a full client restart.
- Shields under a real absorb.

## 2026-11-13 — laptop — 0.8.2 pale shield back, meter rank after restart

- **Shield overflow (`UnitFrames.lua`).** The owner preferred the pale full-height wash from the right end, so the 0.8.1 bottom strip is reverted. Do not change it again without asking.
- **Meter rank number missing after a client restart (`DamageMeters.lua`).** It was visible after a `/reload`, but blank after a full restart, even with "Rank numbers" on.
  - The rank had a fixed-width column measured from the font, and that measurement could come out too narrow and hide the number. The rank now sizes to its own text.
  - The measurement helper restores the text it borrows from the top row, and falls back to a size estimate when the font reports 0.
  - Every row font string gets a font at creation, because a paint can run before Apply.

Checked in game after the owner's restart: the bundled "SoulUI Smooth" texture draws on the health bar, shards and meters; the pale shield band is back; the meter shows "1 Capcasey" again.

## 2026-11-13 — laptop — 0.8.1 frames, from the live game

These were checked up close in the running game, after `/reload`.

- **Shield overflow (`UnitFrames.lua`).** Shield that did not fit past the health fill was drawn as a full-height light wash from the right end. On a full bar it looked like a rendering glitch: a pale band over the last fifth of the player frame. It is now a 3px bright strip along the bottom edge, growing in from the right.
- **Top edge on the health fill (`UnitFrames.lua`).** A 1px light line along the top of the fill, so the bar reads as shaped rather than a flat block. It follows the "Soft shading on the fill" switch.
- **Meter rank number (`DamageMeters.lua`).** It was one size smaller and gray on a colored bar. It is now the row's font size, near-white, and the rank column is measured at that size.

Versions: SoulUI_UnitFrames and SoulUI_DamageMeters are 0.8.1.

Checked in game after `/reload`: the shield strip and the rank number. Not checked:
- **Bar texture:** "SoulUI Smooth" needs a full client restart, because WoW only finds new files at launch. Until then bars draw flat.
- **Combat:** these frames have not been seen in combat.

## 2026-11-13 — laptop — 0.8.0 motion, live check, edit-mode tags

This was the first pass that looked at the running game: the settings window, edit mode and the frames, at the owner's 155% window scale. The owner asked for the UI and menu to look animated and refined, like EllesmereUI (studied only, nothing copied).

**Found live.**
- **Nameplates failed to load.** Chat showed "SoulUI Nameplates enable failed: FontString:SetText(): Font not set". In 0.7.13 the edit-mode nameplate sample set text before setting a font, which aborted the rest of `OnEnable`. Fixed in `Nameplates.lua`.
- **Edit mode Cancel did not close twice in a row.** `/soul move` did close it. The cause was not found from code, because the client disconnected before it could be reproduced. Now:
  - Cancel and Save register any mouse button.
  - Cancel forces the session closed if it is still open.
  - Escape with nothing selected leaves edit mode, the same as Cancel.
- **Unreadable edit-mode labels.** Labels were drawn on top of each element's content and collided with each other.
- **A sparse, still settings window.** It had big empty section boxes and an empty tab band on pages without tabs, and nothing moved.

**Motion system (`Core/UIKit.lua`).**
- `UI.Animate(key, seconds, step, done, ease)` runs on one driver frame. Its OnUpdate runs only while a tween is active. Starting the same key again replaces the tween, and finished tweens complete outside the traversal.
- `account.motion = false` (General > Look > Animations) makes every change instant.
- Uses:
  - The window opens with a fade while growing from 97%, and closes with a fade and a slight shrink.
  - One sidebar selection indicator slides between rows, and row hover washes fade.
  - One tab underline slides and stretches to the active tab.
  - Page content rises 12px into place while fading in.
  - The brand glow breathes slowly while the window is open.
- `UI.Tip` now uses SoulUI's own tooltip: a dark surface, an accent hairline and the UI font, fading in after 0.25s. GameTooltip is no longer used.
- New line glyphs for the nav icons: move, sliders, user, frame, plate, group, grid, pips, bars, search.

**Settings window (`Panel.lua`, `Widgets.lua`).**
- **Bundled original textures** in `SoulUI/Media/Textures`, generated by a script:
  - `Smooth.tga`: bar texture.
  - `Shadow.tga`: 9-slice drop shadow.
  - `Glow.tga`: soft radial glow.
  - `Circle.tga` and `Ring.tga`: antialiased shapes. These replace the portrait-mask discs.
- **Window chrome:**
  - Drop shadow under the window.
  - Accent glow behind the header.
  - Brand: a disc with a ring and a glow.
- **Header and tabs:**
  - The header is 104 tall with a 30px title.
  - Page search moved into the header beside the close button.
  - The tab band collapses on pages without tabs.
  - The accent streak and its end marks are gone.
- **Sidebar:** every page row has a line icon, and Edit Mode has a move icon.
- **Rows and sections:**
  - Rows are 42 tall instead of 52.
  - Each section is a small uppercase label with a short accent tick, over one faint borderless surface. It used to be a bordered recessed box.
  - Default slider width is 128 and dropdowns are at most 190, so labels keep their room.
- **Footer** buttons are 34 tall.

**Edit mode (`Unlock.lua`).**
- **Idle:** a faint outline and a small name tag on a dark backing, centered, shown only when it fits inside the box.
- **Hover:** a tag above the box with the name and size.
- **Selected:** an accent outline, an accent tag and four corner handles.

**Defaults (`Database.lua`).** Frames now default to the "SoulUI Barlow SemiBold" font and the "SoulUI Smooth" bar texture. Profiles that never chose a font or texture pick these up; General > Look switches back.

**Tools.** `tools/lint.mjs` now flags invalid string escapes (`"Interface\AddOns"` written with single backslashes). Lua rejects those at load and luaparse did not. That gap shipped bad paths twice.

**Not tested in game.** The client was at the login screen before these changes could be loaded. To check:
- the shadow 9-slice (`SetTextureSliceMargins`);
- the glyph icons;
- the sliding indicator and tab line;
- the page rise;
- the own tooltip;
- the edit-mode tags;
- Escape and Cancel.

## 2026-11-06 — laptop — 0.7.13 guild build, BigWigs and RaiderIO

Shipped so the guild can install it from GitHub. BigWigs and LittleWigs keep their own bars. SoulUI will not park a frame whose name starts with BigWigs, LittleWigs, or RaiderIO. Enemy nameplates only fade Blizzard's unit frame, and the SoulUI bar sits just above that frame so a boss-mod icon on the plate can stay on top.

Unit tooltips, including party and raid, use the normal game tooltip. Hiding it waits long enough for the cursor to move onto the tooltip or RaiderIO's panel. Party and raid have a Unit tooltip toggle, on by default.

Files: `Core/Compat.lua`, `Core/Blizzard.lua`, `Nameplates.lua`, `UnitFrames.lua`, `GroupFrames.lua`, `Defaults.lua`, `PagesModules.lua`, `SoulUI.toc`, `README.md`.

Not tested in game. Load with BigWigs, LittleWigs, and RaiderIO enabled. Hover a unit frame and a party frame and confirm the RaiderIO score is on the tooltip. Pull a boss and confirm BigWigs bars still show.

## 2026-11-06 — laptop — 0.7.12 scroll scales by a percentage

A one-pixel step on a wide bar was real, and still looked like the element had not moved. The wheel now scales by about 6%. Shift scales by about 15%. Alt is one pixel. Each notch still cannot land on the same physical pixel as the size it already had.

The element under the cursor is the one that scales. A previously selected large frame no longer takes the wheel from a smaller element you are pointing at. A hidden ghost still loses to a real element.

Files: `Core/Pixel.lua`, `Core/Unlock.lua`, `ActionBars.lua`, `UnitFrames.lua`, `GroupFrames.lua`, `ResourceBars.lua`, `DamageMeters.lua`, `Nameplates.lua`, `Core.lua`, tocs.

Not tested in game. `/reload`, `/soul move`. Scroll a health bar and an action bar. The change should be obvious. Shift+wheel is a bigger jump. Alt+wheel is one pixel.

## 2026-11-06 — laptop — 0.7.11 scroll scale, full pass

Finished the scroll-to-scale pass. A notch was still able to do nothing, or to hit the wrong box.

- The saved size now keeps stepping until the snapped size actually changes. Action bars, party, raid and meters snap to physical pixels, and a one-unit step can land on the same pixel.
- The wheel goes to the element under the cursor. The selected element wins. A hidden ghost loses to a real element. A large party or raid holder loses to the smaller element on top of it. A cooldown viewer no longer swallows the wheel.
- A bar shorter than 4px (the GCD) used to be replaced by a fixed 150x26 tag, so scrolling it did not show. The box now matches the real frame.
- Typing or wheeling the inspector size on a multi-button bar moves the button size even when one pixel of the holder is only a fraction of a button.
- Meter width and row height use the same limits as their sliders (120–500 and 10–40).
- Nameplates are in edit mode. The sample sits above center. Scrolling it changes width, health height and cast height for every plate. Dragging it only moves the sample.
- A size slider in the settings window takes the wheel on its whole row, not only the thin track.

Files: `Core/Pixel.lua`, `Core/Unlock.lua`, `ActionBars.lua`, `GroupFrames.lua`, `DamageMeters.lua`, `Nameplates.lua`, `Options/Widgets.lua`, `Core.lua`, tocs.

Not tested in game. `/reload`, `/soul move`. Scroll up and down on a health bar, an action bar, the shards, a meter, and the nameplate sample. Every notch should change that element, in both directions.

## 2026-11-06 — laptop — 0.7.10 scroll scale always moves

Scroll-to-scale dropped notches. A wheel step is often less than 1 UI unit at this client's scale, and the size math then rounded back to the number it already stored. Action bars, party, raid, and meters also compared that step to a reconstructed size that did not match the frame on screen, so the same notch sometimes grew the element and sometimes did nothing.

Every notch now changes the stored size by exactly 1, taken from the saved number rather than the frame on screen. A health bar, cast, shard row, focus bar and GCD all do this. An action bar changes button size by 1. Party and raid change the cell by 1. A meter changes width and row height by 1. The selected element is drawn above the others. An overlay that cannot be resized (a cooldown viewer) no longer eats the wheel, so the element under it still scales.

Files: `Core/Pixel.lua`, `Core/Unlock.lua`, `ActionBars.lua`, `UnitFrames.lua`, `GroupFrames.lua`, `ResourceBars.lua`, `DamageMeters.lua`, `Core.lua`, `SoulUI.toc`.

Not tested in game. `/reload`, `/soul move`, scroll up and down on a health bar, an action bar, a shard row, and a meter. Every notch should change the size, both ways.

## 2026-11-06 — laptop — 0.7.9 menu motion and loose badges

The settings window, edit mode, and dropdowns appeared all at once. Opening the settings window now fades in. Closing it from the button fades out. Changing page fades the new page. Dropdowns fade in, and if the list would leave the bottom of the screen it opens upward instead. Edit mode fades the dim, the toolbar, and the inspector.

The cast lock sat just outside the left of the bar, and the STUN badge sat just outside the right. Both now sit inside the bar, lock on the right and STUN on the left, so they are not floating in the gap beside the frame.

Files: `Core/UIKit.lua`, `Core/Unlock.lua`, `Core/Casts.lua`, `Core/Core.lua`, `SoulUI_Options/Panel.lua`, tocs.

Not tested in game. `/reload`, open `/soul`, change page, open a dropdown near the bottom of a page, and press Escape to confirm SoulUI is still a row inside the game menu.

## 2026-11-06 — laptop — 0.7.8 escape menu row

Pressing Escape showed SoulUI as its own button glued under the game menu, six pixels below the frame, parented to the screen. It did not share the menu's width, font, or rows.

SoulUI is now the last wide row inside the game menu. It uses the same button template as the other rows, matches their width and height, and the menu grows by however much of that row would otherwise stick out. A second layout pass does not keep stretching the menu. Closing the menu hides the row.

Files: `Core/Menu.lua`, `Core.lua`, `SoulUI.toc`.

Not tested in game. Press Escape. SoulUI should be the bottom row inside the menu, not a strip floating under it. Clicking it closes the menu and opens `/soul`.

## 2026-11-06 — laptop — 0.7.7 full functional pass

Walked every module against `docs/research/midnight-api.md` and the other-addon notes. Fixes from this pass:

- Nameplate login scan no longer calls `GetNamePlates()` (that throws if the API is missing) and no longer gives up when the return is not a table. It scans `nameplate1` through `nameplate40`.
- The focus/rage bar only copies the shard position after that position exists. Marking it done first left the bar at the old 10px spot forever if layout had not written yet.
- Group class color from a secret class token uses `GetRGB()` instead of `.r`/`.g`/`.b`, which are not always fields.
- Unit-frame cast color no longer indexes `units[unit]` when that entry is missing.

Already safe, left as they are: cast duration objects and the next-frame retry, health snaps, meter events plus the fast backup ticker, meter on/off without restoring `damageMeterEnabled`, secure group headers and action-button attributes deferred in combat, no combat log, secret checks before compares, aura containers instead of aura iteration, forbidden nameplates skipped.

Not tested in game. `/reload`, then a dummy: health, cast, nameplate, bars, and one out-of-range party frame if grouped.

## 2026-11-06 — laptop — 0.7.6 first-run functional fixes

Checked the live paths against the Midnight notes. Four things would have failed on the first try:

- Party and raid power bars skipped the update when `UnitPowerType` was secret, so the bar froze in combat. They now use `UnitPower` / `UnitPowerMax` with no type, which accept secrets.
- Range fade branched on `UnitInRange`'s second return. That return is a secret boolean, and testing it throws. The fade now goes through `SetAlphaFromBoolean` only.
- Nameplates were only collected on `PLAYER_ENTERING_WORLD`. If that event had already fired, the first login showed no plates until a zone change. Enable now scans the plates that are already up.
- A reload in combat threw on the action buttons' secure attributes and aborted the whole bar module. Those attributes, the page driver, and the main-bar frame ref wait until combat ends.
- A profile that had already turned the focus/rage bar on was treated as automatic and hidden again on a spec that has shards. An explicit on stays on.

Cast bars, meters, unit health, and the secure group headers already follow the Midnight rules (duration objects, no combat log, no secret compares, headers configured out of combat).

Files: `GroupFrames.lua`, `Nameplates.lua`, `ActionBars.lua`, `ResourceBars.lua`, `Core.lua`, those tocs.

Not tested in game. `/reload` out of combat first. Then a target dummy: health, a cast, party range if grouped, and one nameplate.

## 2026-11-06 — laptop — 0.7.5 power bar for specs without shards

Specs with no class resource (hunter focus, warrior rage, demon hunter fury, priest mana, and a druid spec that has no combo points) had the power bar switched off, and the default bar was 10 pixels tall. That bar now stands in the shard slot: same width and height as the tiles, power-colored fill, gray empty, border, a light top edge, and a centered number. It turns on by itself until the player chooses on or off under Resources > Power & GCD. Changing spec or form rebuilds it, so a guardian druid gets rage and a feral druid gets combo points.

Class tiles keep a faint top edge even when gloss is off. Action buttons: empty slots are a solid dark plate, keybinds and counts have a shadow, and a spell you cannot pay for tints gray instead of blue.

Files: `ResourceBars.lua`, `Defaults` unchanged, `Units.lua` power colors, `ActionBars.lua`, `PagesModules.lua`, tocs, `Core.lua`.

Not tested in game. `/reload` on a hunter or warrior, and on a warlock to confirm shards are unchanged. Resources > Power & GCD is the switch.

## 2026-11-06 — laptop — 0.7.4 instant bars, meter toggle

Health, nameplate, and party/raid bars were easing toward the new value (`ExponentialEaseOut`), so every hit looked late. They now snap. Cast bars retry a missing duration on the next frame instead of waiting 50ms, and the time text updates every hundredth of a second. Target-of-target casts are checked 20 times a second.

Damage meters ignored server updates while their 4 Hz ticker was running, and the ticker refused to go faster than 4 Hz. They now repaint on `DAMAGE_METER_COMBAT_SESSION_UPDATED` and `DAMAGE_METER_CURRENT_SESSION_UPDATED`. The backup ticker is at least 20 Hz. Meter bars no longer ease.

Turning the meters off restored `damageMeterEnabled`, which does not take effect until a reload, so turning them back on did nothing and never said so. The toggle now only hides or shows our windows and leaves that cvar at 0. If it is already 1 (an older toggle did that), turning the meters on asks for a reload. Turning on Blizzard's Cooldown Manager when its frames were never created asks for a reload too.

The other module switches (unit frames, nameplates, party, raid, action bars, resources, each meter window) already apply live. Their other controls stay disabled while that piece is off, and the on/off switch itself stays clickable.

Files: `Core/CastBar.lua`, `Core/Core.lua`, `UnitFrames.lua`, `Nameplates.lua`, `GroupFrames.lua`, `DamageMeters.lua`, `Pages.lua`, `PagesModules.lua`, and those tocs.

Not tested in game. `/reload`. Cast, take damage, and toggle Damage Meters off and on without another reload.

## 2026-11-06 — laptop — 0.7.3 settings layout, not another recolor

0.7.2 recolored the existing window. The owner pointed out the structure had not changed. This pass changes the layout.

- Window is 1280x840. Sidebar is 280. Header is 124. Footer is 78. Page inset is 48.
- Sidebar rows are 40 tall. The brand mark is 28. Search fields are 34 tall.
- Page title is 36. A preview sits in a padded stage instead of flush under the tabs.
- Each settings section is a recessed block. Rows inside are 52 tall.
- Two-column rows are two columns with a 36px gap. The center hairline is gone.
- Dropdowns are 32px wells, number boxes are 30px, switches are 44x22, swatches are 36x26, slider tracks are 4px with a 10px thumb. The dropdown menu rows are 30 tall.

Files: `Core/UIKit.lua`, `Core/Core.lua`, `SoulUI_Options/Panel.lua`, `SoulUI_Options/Widgets.lua`, both tocs.

Not tested in game. `/reload`, then `/soul`. Open a page with two columns, such as Nameplates, and one with a preview.

## 2026-11-06 — laptop — 0.7.2 settings window overhaul

The owner posted the EllesmereUI settings window and asked for SoulUI's menu to be reminiscent of it. Own layout and own mark. No copied art.

The window is now a deep navy shell.
- Sidebar: accent disc and the SoulUI name, Edit Mode with a small mark, accent group labels, a 3px accent bar and a fading wash on the selected page, a ring on each module row.
- Header: large title, then an accent streak across the tab row that fades at both ends.
- Footer: dark Reset and Reload wells, solid accent Close. Edit Mode stays in the sidebar.
- Slider thumbs are square. Section headings no longer sit on a line.

Files: `Core/UIKit.lua`, `Core/Core.lua`, `SoulUI_Options/Panel.lua`, `SoulUI_Options/Widgets.lua`, both tocs.

Not tested in game. `/reload`, then `/soul`. The disc and the rings use the client portrait mask; if that mask is missing they draw as tiles.

## 2026-11-06 — laptop — 0.7.1 quieter settings window

The owner re-read the suite after 0.7.0 and still found the settings window cheap. The accent color was doing the decorating: a glow behind the header, a colored frame, a diamond mark, fading rules, gradient nav rows, accent group titles, an accent scrollbar, and the stock search icon.

The window is now neutral. The accent stays on controls and on the active tab mark.
- Sidebar: a 7px square and the name, hairline, inset plate for the current page, uppercase group labels, a dot only when a module is off.
- Header: title, description, close. Window scale moved to the footer.
- Sections: a heading and a hairline, not a gray card.
- Edit-mode windows drop the 2px accent stripe on the title bar.
- The escape-menu fallback button is no longer cyan.

Files: `Core/UIKit.lua`, `Core/Menu.lua`, `Core/Core.lua`, `SoulUI_Options/Panel.lua`, `SoulUI_Options/Widgets.lua`, both tocs. Other modules were not changed.

Not tested in game. `/soul` after `/reload`.

## 2026-11-05 — laptop — 0.7.0 one cast bar for everything, proc glow, shard count, polish pass

The owner tested 0.6.1 and reported problems:
- **Shard count:** the shard number moved as shards were spent; it should stay centered on the middle shard.
- **Stack and charge numbers:** these were hard to see, and their size could not be set.
- **Player unit-frame cast bar:** it still appeared when casting, even though it was turned off.
- **Cast bars in general:** they sometimes showed and sometimes did not, for the player and for enemies.
- **Proc glow:** the glow on lit-up abilities flickered and was the wrong size.
- **Enemy cast colors:** these looked impossible to customize.

The owner also asked for a polishing pass over the whole addon.

**Cast bars, root causes.**
- **Player unit-frame bar:** the bar was shown straight from the `UNIT_SPELLCAST_START` handler, which never checked `showCast`.
- **Bars hiding mid-cast:** every end event hid the bar unconditionally. FAILED fires when you press a key mid-cast, and with spell queueing the previous cast's STOP can arrive after the next START. Both hid a live bar.
- **Nameplates:** they also gave up when the duration object was not ready on START.

**Cast bars, the fix.** A new `Core/CastBar.lua` is the single implementation, used by the player bar (Resources), unit frames and nameplates. See ARCHITECTURE "Cast bars (0.7.0)". It adds:
- re-query on every end event;
- a gate on every path, so a disabled bar never shows;
- retries when the duration is late;
- one look for all bars: icon flush left, a spark, the remaining time, a fade-out, and a red flash with "Interrupted".

**Enemy cast colors.**
- **The bug:** a per-unit `castColor` (for example one set from the edit-mode color swatch on the target cast bar) silently replaced the shared interruptible color.
- **Fix:** that override now applies only to player and pet. The edit-mode swatch on target and focus edits the shared color instead.
- **Easier to find:** the full color block (interruptible, interrupt on cooldown, not interruptible, high priority ring, and the toggles) now also appears on the Unit Frames and Nameplates pages.

**Shard count.** One number, centered on the row, which is always the middle shard. It shows whole resources through `SetFormattedText("%d")`, so secret values work. This replaces the per-tile number that moved as shards were spent.

**Stack and charge numbers.**
- They now sit on a text layer above the cooldown swipe and the proc glow.
- **New settings:** a size slider ("Stacks and charges"), a position setting, and a color.

**Proc glow.**
- **The cause:** Blizzard's alert is laid out for 45px buttons and is restarted from several template code paths.
- **The fix:** it is hidden on our buttons and replaced by our own glow: a 2px edge plus an inner wash, drawn to the button rect, pulsing.
- **Settings:** on/off and a color.

**Polish pass.** Four parallel agents each took one module (own files only), and the lead wired their new settings into the options pages.
- **Unit frames:**
  - Solid black outline with a 1px line above the power bar, and a darker backdrop.
  - Text on its own layer above absorbs.
  - Dead, offline and tapped states.
  - Heal absorbs.
  - Hover and "is your target" outlines.
  - Raid marker, leader crown and combat icon.
  - Events now update only what changed.
- **Nameplates:**
  - Per-plate pixel-exact border.
  - Target indicator (border, arrows, both, glow or none) and dimming of the other plates.
  - Name above or inside the bar.
  - Percent text, raid marker, elite/rare mark, gray when tapped.
  - One spacing value for all rows.
  - Style is reapplied only when something changed.
- **Party and raid:**
  - Pixel-snapped sizes, a 1px border and a 1px line above the power bar.
  - Class or dark health color.
  - Inline or stacked text, with percent or missing-health text that hides at full health.
  - Dead, ghost, offline and AFK states.
  - Range fade (never on yourself).
  - Target and hover outlines, absorbs, a ready-check icon.
  - Dispel icons inside the frame.
  - Raid `columnSpacing` sign fixed.
  - Party gap is now 1, and Layout.lua was updated to match.
- **Meters:**
  - **Float numbers fixed:** "23M (21.600304115133)". The client's `AbbreviateNumbers` defaults leave values below 1000 unabbreviated; the meter now passes its own breakpoints.
  - Two aligned number columns.
  - Header on one baseline, with drawn icons.
  - Empty-state text.
  - Smooth wheel scrolling of long lists.
  - Your own row marked.

**Files.**
- **New:** `SoulUI/Core/CastBar.lua`.
- **Changed:**
  - `Core/Casts.lua` (no change in behaviour)
  - `Core/Layout.lua`
  - `SoulUI.toc`
  - all module .lua and Defaults files
  - `SoulUI_Options/Pages.lua`, `PagesModules.lua` and `Previews.lua`
  - `tools/audit.mjs`, so its checks look for the cast APIs in CastBar.lua
- All `.toc` versions are now 0.7.0.

**Review pass.** A review agent found these, all fixed:
- **Load-order crash (critical):** `Soul.Options` was nil while Pages.lua loaded, which would have broken the whole settings window. `Widgets.lua` now creates it.
- **Stale cast after a target change:** the old target's cast stayed on the frame. `CastBar:Reset()` now runs on unit change.
- **Interrupted flash cut short:** a second end event during the fade shortened it. Only a live cast finishes now.
- **Target of target:** the game sends no cast events for it, so its bar is polled while a cast is up.
- **Proc glow textures leaking** on every Apply. The glow is now built once and repainted only when its color changes.
- **Proc glow missing after a bar reappears:** the visibility gate is gone.
- **Vertical party resize:** used the 5-across math. It now reads the orientation.
- **Smaller fixes:**
  - no tables or colors created per cast event;
  - the time binding resumes after Alt+Z;
  - edit mode no longer previews a cast bar that is turned off;
  - action bar defaults added for the new keys.

**Not tested in game (all of it).** To check:
- the cast bar on fast chain-casting and on interrupts;
- the proc glow on a real proc;
- whether `IsSpellOverlayed` returns plain or secret values;
- the meter number formatting (`/run print(SoulUI:GetModule("DamageMeters").Abbrev(21.6))` should print 21);
- the unit-frame tooltip on mouseover (new, on by default);
- the raid row spacing;
- the nameplate arrow glyphs.

## 2026-11-05 — laptop — 0.6.1 bundled UI font

The owner asked to bundle a font for a closer match to Ellesmere's typography. Arial Narrow, the 0.6.0 default, was the nearest font the client ships.

**Font.** Barlow Semi Condensed, Medium and SemiBold, by The Barlow Project Authors. License: SIL Open Font License 1.1, kept next to the fonts as `SoulUI/Media/Fonts/OFL-Barlow.txt`. Downloaded from github.com/google/fonts (`ofl/barlowsemicondensed`).
- **Where it is used:** it is the default for the settings window and edit mode. Text 18px and larger uses SemiBold; everything else uses Medium.
- **Fallback:** if a file fails to load, `UI.SetFont` uses `Fonts\ARIALN.TTF`.
- **Font lists:** registered with LibSharedMedia as "SoulUI Barlow" and "SoulUI Barlow SemiBold", so the fonts can also be picked for frames.
- **General > Look > Window font:** the default entry now reads "SoulUI default (Barlow)".

**Files.**
- New: `SoulUI/Media/Fonts/` (two .ttf files and the license).
- Changed: `Core/UIKit.lua` (`UI.FontPath(size)`, `DEFAULT_BOLD`, `FALLBACK_FONT`), `Core/Media.lua`, `SoulUI_Options/Pages.lua`.
- SoulUI and SoulUI_Options are now 0.6.1.

**Not tested in game.** The fonts have not been seen in game yet. Barlow is slightly wider than Arial Narrow, so check that long labels and the tabs still fit.

**Note.** `tools/lint.mjs` does not flag invalid Lua string escapes such as `"Interface\AddOns"` written with single backslashes. Such a path was caught by hand in this change. Write paths as `"Interface\\AddOns..."` in Lua source.

## 2026-11-05 — laptop — 0.6.0 settings window redesign

The owner sent a screenshot of EllesmereUI's Global Settings window and asked for a full redesign of `/soul` to that level of cleanliness. The design comes from studying the screenshot; no Ellesmere code or assets were used.

**What the reference does that ours did not.** Fewer, calmer surfaces. One condensed font. Hairlines instead of boxed cards. A big page title. Text tabs with an underline. Accent used only for headings, the active item and on-states. Square controls. Generous row height.

**Window (`SoulUI_Options/Panel.lua`, rewritten).**
- **Size:** 1180x780.
- **Sidebar:**
  - Diamond logo and name.
  - Fading accent rule.
  - Pinned Edit Mode row.
  - General and Profiles pages.
  - Search box.
  - Accent group headings with page rows.
  - Profile and version at the bottom.
  - The nav scrolls if it ever outgrows the window.
- **Header:** large title, description, and a window-scale slider (moved here from General > Look, applied on mouse release) next to a drawn close button.
- **Below the header:** tabs with an underline and page search, the preview strip, scrolling content with a thin scroll track, and a footer.

**Rows (`Widgets.lua`).** Sections are an uppercase heading over one flat panel, with no borders and no row separators. Rows are 46 tall, two-column rows split on one hairline, labels are 15px, and the selector is outlined segments.

**Controls (`Core/UIKit.lua`).**
- New palette.
- Square switch with a hairline.
- Thinner slider with an accent knob.
- Dropdown with a drawn chevron.
- Hairline buttons.
- New `UI.Glyph` and `UI.IconButton`, drawn from Line objects.
- New UI font system: `UI.SetFont`, `UI.RefreshFonts`, and `account.uiFont`, defaulting to Arial Narrow, which ships with the client. Choose it under General > Look > Window font.
- Edit mode picks up the same look.

**Versions.** SoulUI and SoulUI_Options are 0.6.0.

**Untested in game.**
- The Line-based glyphs and the diamond logo. If CreateLine misbehaves they would be missing, not erroring.
- Arial Narrow sizes.
- The header scale slider.

**Review pass.** A review agent found three defects, all fixed:
- **Window outline:** the sidebar covered the outline. It now sits on its own frame above the sidebar.
- **Brand glow:** the gradient was upside down.
- **Window font change:** pages kept measurements from the old font. They are now rebuilt after a change.

Also: `/soul scale` now applies the scale to an open window, and profile list rows use the new inset.

**Possible follow-up.** Bundle an open-license condensed font (for example Inter or Roboto Condensed, both OFL or Apache) in SoulUI/Media for a closer match to Ellesmere's typography. This needs a font file added to the repo.

## 2026-11-05 — laptop — 0.5.0 one player cast bar, hide any element, Cooldown Manager

The owner tested 0.4.0 (edit-mode screenshot). Problems:
- **Three cast bars when casting:** the Resources "Player Cast" at the bottom, the player unit-frame cast bar above the player frame, and Blizzard's own. Only the bottom one should show.
- **No way to hide an element** from the editor.
- **A horizontal icon row next to the three left bars** that edit mode could not select. It is Blizzard's Cooldown Manager: `cooldownViewerEnabled` was "1" in this character's config-cache.wtf (EllesmereUI's CDM turns it on), and its Edit Mode position came from the Ellesmere setup.

**One cast bar.**
- `Core/Blizzard.lua` (new) parks Blizzard's player and pet cast bars while a SoulUI player cast bar is on. Parking means re-parenting to a hidden frame, with a SetParent hook so Edit Mode cannot bring it back.
- Migration `profile._singleCast` (Layout.lua) turns off the player and pet unit-frame cast bars once. Either one can be turned back on in edit mode or on the Unit Frames page.
- Blizzard's personal resource display (`nameplateShowSelf`) is off by default too, in case that was the "cast bar above my character".

**Hide any element.**
- New mover contract `getEnabled/setEnabled`, mapped to each module's existing enable flags. Wired up for unit frames, unit cast bars, the four Resources bars, all eight action bars, party, raid, the three meters and the Cooldown Manager rows.
- Edit mode: hidden elements keep a dim "(hidden)" box; select it and use the inspector's new "Shown" switch. The toolbar's "Hidden" switch shows or hides those boxes.
- Settings: General > Hide & Show lists every element by module with a switch, plus the Blizzard toggles (cast bar, personal resource display, Cooldown Manager).

**Cooldown Manager.** Off by default (CVar owned by SoulUI, original value remembered). When turned on, each row is movable and hideable in SoulUI edit mode.

**Other changes.**
- `Soul:Place` now divides offsets by the frame's scale ratio. This changes nothing for SoulUI frames, which run at scale 1.
- The edit toolbar is 980 wide and the inspector 500 tall.
- Edit-mode Cancel also restores `profile.blizzard`.

**Files.** New: `SoulUI/Core/Blizzard.lua`. Changed: `SoulUI/SoulUI.toc`, `Core/Unlock.lua`, `Core/Layout.lua`, `Core/Core.lua`, every module's mover registration, `SoulUI_Options/Pages.lua`. All `.toc` versions are now 0.5.0.

**Untested in game.**
- Blizzard re-parenting the cast bar mid-session, for example through Blizzard's Edit Mode "lock to player frame".
- Cooldown Manager viewers moving with a saved SoulUI position while Blizzard Edit Mode also moves them (SoulUI's position wins).
- Ghost boxes for frames that have no size while hidden. These fall back to a 150x26 tag.

**Review pass.** A review agent found two bugs, both fixed:
- **Invisible ghost boxes:** an element that was disabled since login (a meter window, a unit frame) was never anchored, so its ghost box did not appear. FitMover now places the tag at the saved or fallback position.
- **Cancel and Reset Position did not move a Cooldown Manager row back:** Blizzard.lua now remembers each viewer's own anchor and restores it when SoulUI no longer holds a position for it. Viewer movers get `onReset`.

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
