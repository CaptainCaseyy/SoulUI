# EllesmereUI options editor: study notes for the SoulUI editor

Studied: EllesmereUI 9.7 (client 12.1.5, Interface 120105), November 2026.
Scope: the LoadOnDemand addon `EllesmereUIOptions` (101 Lua files, roughly 163k
lines including page builders) plus `EllesmereUI_Panel.lua`,
`EllesmereUI_GlobalSearch.lua`, `EllesmereUI_Popups.lua`,
`EllesmereUI_StyleCards.lua`, `EllesmereUI_FirstInstall.lua` and
`PLUGINS_API.md` in the core addon.

> **License note.** EllesmereUI is "all rights reserved". Everything below is a
> description, in our own words, of architecture and UX. No code is copied. The
> few identifiers quoted (function names, saved-variable keys) are there only
> so a reader can find the original when checking a claim. Do not lift
> constants, art, or text from the original. Choose our own values.

---

## 1. Big picture

EllesmereUI splits its settings UI into three layers:

1. **The core addon** (`EllesmereUI`, always loaded) owns the window shell:
   the frame, sidebar, header, tab bar, scroll area, footer, theme and
   background art, global search, popups, the module registry, slash commands
   and the minimap button. It holds no page content.
2. **The options addon** (`EllesmereUIOptions`, `## LoadOnDemand: 1`,
   `## Dependencies: EllesmereUI`) holds the widget factory, the frame pool, and
   one or more "page builder" files for every feature module. Nothing in it is
   parsed until the player first opens the panel.
3. **Feature modules** (`EllesmereUINameplates`, `EllesmereUIUnitFrames`, ...)
   are separate addons that hold runtime code and defaults. Each one publishes
   its private namespace into `EllesmereUI._ModuleNS[folder]` at load. The
   matching options file looks that namespace up, and if the module is
   disabled or missing it returns early, so the module gets no page.

So the settings for module X live in the options addon, not in module X. They
reach into X's namespace for `ns.db`, `ns.defaults` and refresh functions
such as `ns.RefreshAllSettings` and `ns.ReloadFrames`.

### 1.1 TOC load order of EllesmereUIOptions (framework first)

1. `EllesmereUI_FramePool.lua`: the page frame pool. It loads first because
   everything else creates frames through it.
2. `EllesmereUI_Widgets.lua`: the core widget factory (`EllesmereUI.Widgets`),
   plus SectionHeader, Toggle, Slider, Dropdown, Checkbox, the dropdown menu
   engine, tooltips and preview hit overlays.
3. `EllesmereUI_Widgets_Color.lua`: HSV helpers, a custom color picker popup
   that replaces Blizzard's, swatches, and the ColorPicker row.
4. `EllesmereUI_Widgets_Rows.lua`: Button, WideButton, the keybind button,
   **DualRow** and **TripleRow** (the workhorses), MultiSwatchRow,
   DropdownWithOffsets, WideDualButton, WideTripleButton, WideDropdown,
   TripleDropdown, TripleSlider and Spacer.
5. `EllesmereUI_Widgets_CogPopup.lua`: the "cog" mini settings popup.
6. `EllesmereUI_Widgets_SegmentedControl.lua`: the pill tab bar used for
   multi-edit selection.
7. `EllesmereUI_Widgets_ApplyToAll.lua`: sync icons, the multi-apply dropdown
   and flash effects.
8. `EllesmereUI_Widgets_RowAddons.lua`: inline toggle, cog and button, row
   label menus, the "less common" expander, inline swatches, section gates and
   the cursor anchor row.
9. `EllesmereUI_Widgets_AuraPopups.lua`: tracked-aura include/exclude editor
   and spell blacklist popups.
10. `EllesmereUI_Widgets_CheckboxDropdowns.lua`: multi-select checkbox
    dropdowns, the reorderable variant, and a dropdown that contains sliders.
11. `EllesmereUI_Widgets_Visibility.lua`: the unified visibility rule row and
    its checklist.
12. `EllesmereUI_Widgets_PageParts.lua`: shared page parts such as the unlock
    placeholder, link rows, action cards, note rows, module cards, manager
    tiles and the activation overlay.
13. `EllesmereUI_GlowOptions.lua`: shared glow-setting controls.
14. Global pages: Colors, Profiles, WhatsNew (Patch Notes), General, Fonts,
    Textures, Glows, Gamepad, Style, Party Mode (with its horoscope page).
15. Then each module's options in suite order. Large modules split into a
    subfolder of section files followed by a main file that registers the
    module. For example `Nameplates_Options\*.lua` holds GeneralPage,
    DisplayLayout, DisplayBars, ColorsPage, CoreTextColoring and
    NameplatePreview, and `EUI_Nameplates_Options.lua` registers the module.
    The section files only define functions. The main file wires them through a
    shared env table (`ns._XXO_OptEnv`).

Every options file wraps its body in a function that it appends to
`EllesmereUI._deferredInits`. `EnsureLoaded` runs those functions after
`LoadAddOn`. Loading the file therefore costs only parsing. Building the
widget closures waits until the panel opens.

---

## 2. Panel shell

### 2.1 Geometry

- The root frame is `EllesmereUIFrame` on UIParent, strata DIALOG, level 100,
  movable. The background art is about 1500x1154 units. Inside it sits a
  "click area" of about **1300 x 946**, which holds all the interactive parts.
- **Pixel-perfect scale:** on every show the base scale is recomputed as
  `GetScreenWidth()/physicalWidth`, so one unit equals one physical pixel.
  That value is multiplied by a user **Window Scale** setting. The Window Scale
  slider sits in the title bar, left of the collapse button. Popups go through
  a separate scale helper so they grow and shrink with the panel.
- **Sidebar:** 295 wide and the full height of the click area.
- **Right content region:** 1300 - 295 = **1005** wide. The code comment says
  1030, which is stale. From top to bottom it holds:
  - **Header**, 138 tall: module title, description line, banner art with an
    accent glow, and a dark band behind the tabs.
  - **Tab bar**, 40 tall: page tabs on the left and an inline search box on the
    right.
  - **Optional content header**: a fixed region that does not scroll. Live
    previews go here. A module fills it through `getHeaderBuilder(page)`,
    which returns `fn(frame, width) -> height`. It has a subtle tint and a 1px
    bottom divider.
  - **Scroll area**: clips its children, scrolls smoothly (lerp toward a
    target, snapping to whole pixels so text never jitters), and shows a thin
    scrollbar only when the content overflows. The scrollbar has a wider
    invisible hit area for click-to-jump and drag.
  - **Footer**, 82 tall: "Reset to Defaults" (shown only for plugin pages
    that supply `onReset`; suite modules reset from Global Settings), "Reload
    UI", social link icons (a copy-URL popup), and a "Close" button in the
    accent color.
- **Collapse button:** folds the whole window into a small "mini window" (a
  badge plus an expand box) while the options session stays open. Escape,
  entering combat, or the mini window's X fully close it.
- Inside a page the content pad is **45** on both sides. Rows are therefore
  about 935 wide (1005 - 2x45).

### 2.2 Sidebar

From top to bottom:

1. **Fixed nav rows**, each 40 tall with a 45x32 icon and a label:
   **Unlock Mode** (opens the mover overlay), **Global Settings**, **Patch
   Notes** (shows a red dot when the version changed since the last login),
   **Profiles & Presets**, and **EUI Legends** (credits and donors).
2. **A global search box**, which opens a results popup and never filters the
   sidebar itself (see section 6).
3. **A scrollable list of module rows in collapsible groups**:
   - **Core Addons:** Action Bars, Nameplates, Unit Frames, Cooldown Manager,
     Resource & Cast Bars, Raid & Party Frames.
   - **Secondary Addons:** Mythic+ Tools, Damage Meters, AuraBuff Reminders,
     Loadout Manager, Simple Loot Council.
   - **Utility Addons:** Quality of Life, Forever Essentials (WoW Forever
     client only), DataBars, Quickdraw, Party Mode.
   - **UI Enhancements:** Blizzard Skins+, Chat, Bags, Quest Tracker, Group
     Finder, Friends List, Minimap.
   - Group headers use the accent color and collapse on click. Each child row
     has a **power button** that enables or disables the addon itself. It
     shows a confirm popup "Disable & Reload" or "Enable & Reload", then calls
     `C_AddOns.EnableAddOn` or `DisableAddOn` and reloads. A disabled module
     shows dimmed: text alpha 0.11, icon alpha 0.20.
   - A **sync icon** beside the power button links a module's settings across
     profiles (profile sync).
   - The list scrolls smoothly, has a thin thumb, and a "scroll to bottom"
     arrow that dims when nothing is below.
4. **Plugin sections** (third-party addons) are added below the suite groups,
   or above them with `position="top"`.
5. **Class art** decorates the bottom of the sidebar.

Nav row states:
- **Selected:** a 3px accent bar on the left, a horizontal accent gradient
  starting at alpha 0.15, gradient lines on the top and bottom edges, and full
  white text.
- **Hover:** a faint mint-white gradient and a translucent 3px bar.
- **Enabled idle:** text at alpha 0.6.
- **Disabled:** text alpha 0.11, hovering raises it to 0.39.

### 2.3 Page tabs

- Each module declares `pages = { "Tab A", "Tab B", ... }`. A tab label can
  differ from the page identity (`TAB_LABEL_OVERRIDES`).
- Pages can be made conditional at registration time. Examples: the Swing
  Timer tab appears only if the swing timer API exists, and the Window Mover
  tab appears only if the QoL module is loaded. Pages can also be greyed out
  with a tooltip (`disabledPages`, `disabledPageTooltips`).
- The panel remembers the last page per module (`_lastPagePerModule`).
- The search box on the tab bar filters the **current page's** rows inline
  (`ApplyInlineSearch`).

### 2.4 Module registration contract (internal)

`EllesmereUI:RegisterModule(folderName, config)` takes these config fields:

| field | purpose |
|---|---|
| `title`, `description` | header text |
| `pages` | ordered tab list |
| `buildPage(pageName, parent, yOffset) -> height` | builds one page. `yOffset` is negative and runs top-down. |
| `getHeaderBuilder(pageName) -> fn or nil` | fixed preview header |
| `onPageCacheRestore(pageName)` | a cached page is shown again. Refresh anything that changed while it was hidden. |
| `onModuleLeave()` | the user switched away |
| `onReset()` | enables the footer Reset button |
| `disabledPages`, `disabledPageTooltips` | greyed tabs |
| `searchTerms` | extra sidebar and search aliases, such as "brez" or "pull timer" |
| `noSearchPages` | pages excluded from the hidden search pre-build |

Only trusted callers can register suite keys: the options addon, while it
loads or drains its deferred inits. Each suite key is sealed after its first
registration. Third parties must use `RegisterPlugin` (section 11).

### 2.5 Page lifecycle and caching

- `SelectModule(folder)` then `SelectPage(page)` runs `RunPagePass`. The pass
  takes a **kept wrapper frame** for `module::page` from the pool and calls
  `buildPage(page, wrapper, startY)`. The returned height sets the
  scroll-child height.
- **Pages are cached for the whole session.** WoW never frees frames, so
  dropping a page on close would only force a rebuild on the next visit. A
  revisit shows the cached wrapper and calls `onPageCacheRestore`.
- **The frame pool** (`EllesmereUI_FramePool.lua`) handles rebuilds. Every
  frame, texture, font string and animation group created on a "pool host" is
  recorded by host, kind and creation order. When the same page is built again
  (a forced refresh), the pool returns the previous build's objects reset to a
  fresh state, so builder code can stay naive ("create everything") and still
  create nothing new after the first pass. A **generation counter** per pooled
  object lets deferred callbacks notice that their frame has been reused for
  something else.
- `EllesmereUI:RefreshPage(force)`:
  - **Fast path** (not forced): every widget registered a "refresh" closure
    (`RegisterWidgetRefresh`) that re-reads its getter and repaints itself. The
    fast path runs all of them with no teardown and no allocation. This is how
    a change in one control updates the disabled state or value of every other
    control on the page.
  - **Slow path** (forced): a full rebuild through the pool. Scroll position
    and any inline search filter are preserved. It is used when a change alters
    the **structure** of a page, such as rows appearing or disappearing.
  - While the panel is hidden or collapsed, refreshes are deferred and run on
    the next show (`_pendingFastRefresh` / `_pendingForceRefresh`).
- `InvalidatePageCache()` and `InvalidateModulePageCache(module)` drop cached
  pages. They run after a profile switch, an import, and so on.

### 2.6 Lazy loading and the first open

- All panel entry points (slash commands, the minimap button, deep links,
  plugins) end in `EllesmereUI:Show()` or `Toggle()`. Those call
  `EnsureLoaded()`, which does `C_AddOns.LoadAddOn("EllesmereUIOptions")` and
  then drains `_deferredInits`.
- **First-open split:** loading the addon and building the panel in the same
  hardware-event script blew the script watchdog ("script ran too long"). So
  the first open only loads, sets `_openPending` (which ignores re-clicks), and
  builds the panel one frame later through `C_Timer.After(0)`. Later opens are
  synchronous.
- Module slash commands such as `/enp` and `/euf` are registered at login as
  **bootstrap stubs**. A stub refuses in combat, loads the options addon on a
  timer tick, then hands off to the real handler, which the options addon
  installed over the stub during its load.
- If the options addon is disabled, an error tells the user to enable
  "EllesmereUI Options" in the AddOn List.

### 2.7 How it opens

- **Slash commands:** `/eui`, `/ellesmere`, `/ellesmereui` toggle the panel.
  `/ee` is a quick alias. `/epm` opens Party Mode settings. `/unlock` opens
  Unlock Mode. Per-module commands: `/enp`, `/euf`, `/erf`, `/eabr`, `/qol`,
  `/emm`, `/efr`, `/edb`, `/eqd`, `/ebsk`, `/erbopt`, `/ecmeopt`, `/eqtopts`.
  All are deferred by one tick so the build runs outside the chat edit box's
  execution budget.
- **Minimap button:** a native button with no LDB dependency. Left-click
  toggles the panel, right-click enters Unlock Mode, middle-click hides the
  button. It can be dragged around the minimap ring (the angle is saved).
- **Game menu:** a button in the pause menu; Global Settings can hide it.
- **Deep links:** `NavigateToElementSettings(module, page, section,
  preSelectFn, highlightText)` opens a module and page, optionally pre-selects
  an internal selector (a unit or bar), scrolls to a section and pulses a
  highlight on a row. Unlock Mode "Element Options", the global search, and
  clicks on preview elements all use it.
- **Escape** closes the panel. It is registered through a single shared
  escape proxy.

### 2.8 Combat handling

- The panel never opens in combat. Every entry point checks
  `InCombatLockdown()` and prints "Cannot open options during combat".
- On `PLAYER_REGEN_DISABLED`, an open panel is **hidden** and a message is
  printed. Closing in combat is allowed. Opening or unfolding is not.
- The rationale: page builders and setters touch protected frames (action
  buttons, secure headers). Refusing to open is simpler than queueing every
  setter.
- Setters that must touch secure state outside the panel queue their work
  until combat ends.

---

## 3. The widget library (`EllesmereUI.Widgets`)

### 3.1 Layout model

- **Vertical stacking with a running y offset.** Every factory call takes
  `(parent, ..., yOffset, ...)`, anchors its frame at
  `TOPLEFT(parent) + (CONTENT_PAD, yOffset)`, and returns `frame, height`. The
  builder writes `y = y - h` after each call and finally returns `math.abs(y)`
  as the page height. There is no layout engine and no flexbox.
- **Row heights:** Toggle, Slider, Dropdown, ColorPicker, DualRow and TripleRow
  are all **50**. Checkbox is **36**. SectionHeader is **40**. Spacer is
  configurable.
- **Row width** is the parent width minus 2 x CONTENT_PAD (45 each side).
- **Alternating row backgrounds:** a black overlay at alpha 0.1 on odd rows and
  0.2 on even rows (`RowBg`). The counter restarts at each SectionHeader, so
  every section begins with the same stripe.
- **Two-up and three-up rows:** DualRow halves are each about 467 wide with a
  1px center divider. TripleRow splits into thirds, or custom ratios through
  `splits`. Style constants describe dual items as 350 wide with a 42 gap and
  triple items as 180 wide with a 50 gap.
- **Two-column pages:** `EllesmereUI:CreateSplitColumns(parent, y)` returns
  left and right column frames with a 1px divider, for pages that need two
  independent stacks. Section separators then span the full width.
- In each row the label sits on the left, inset 20, at font size 14. The
  control is right-aligned, inset 20. Labels are single-line and **ellipsize**
  when they collide with the control or inline extras. A truncated label
  reveals its full text in the hover tooltip.

### 3.2 Factory methods

All signatures follow the pattern "parent, label, y, ..., get, set, tooltip".
Getters return the current value. Setters receive the new value, and for
colors they receive `r, g, b, a`.

| Method | Signature (paraphrased) | Notes |
|---|---|---|
| `SectionHeader` | `(parent, text, y, tooltip?) -> frame, 40` | Dim uppercase-style label at size 12, alpha 0.41, with a faint 1px separator. Restarts row striping and records the "current section" for search. |
| `Toggle` | `(parent, text, y, get, set, tooltip?)` | Pill switch 40x20 with a sliding knob. The track uses the accent color when on and grey #444 at alpha 0.65 when off. The knob is alpha 0.5 off and 1.0 on. Animated. |
| `Slider` | `(parent, text, y, min, max, step, get, set, tooltip?, pixel?)` | Track about 320 wide and 4 tall with a 14px thumb. The fill uses the accent color at alpha 0.75. A 40x26 numeric input box sits right of the track; typing commits. `pixel=true` converts the value to physical pixels for border and offset sliders. |
| `Dropdown` | `(parent, text, y, values, get, set, order?, tooltip?)` | 200x30 button showing the current label and an arrow. The menu is built **lazily on first click**. |
| `Checkbox` | `(parent, text, y, get, set, tooltip?)` | Small box with a checkmark and the label to the right. Row height 36. |
| `ColorPicker` | `(parent, text, y, get, set, hasAlpha?)` | A 24px swatch that opens the custom picker. |
| `Button` / `WideButton` | `(parent, text, y, onClick[, width])` | Muted bordered button. |
| `WideDualButton` / `WideTripleButton` | two or three buttons on one row, with optional disabled options | |
| `WideDropdown` | `(parent, title, y, values, get, set, order, width, disabledValuesFn)` | A full-width dropdown, used for "selector" dropdowns that choose which bar or unit to edit. |
| `DualRow` | `(parent, y, leftCfg, rightCfg?)` | **The main workhorse.** Two declarative widget configs side by side. With only one config it spans the full width. |
| `TripleRow` | `(parent, y, a, b, c, splits?)` | Three configs. |
| `TripleDropdown` / `TripleSlider` | `(parent, configs, y)` | Shortcuts for three dropdowns or three sliders. |
| `MultiSwatchRow` | `(parent, y, {text, swatches={...}})` | A label plus N swatches, each with its own tooltip. |
| `DropdownWithOffsets` | `(parent, y, ddCfg, xCfg, yCfg)` | An anchor or position dropdown plus X and Y sliders. |
| `Spacer` | `(parent, y, h)` | Empty space. |

**Declarative slot configs** used by DualRow, TripleRow and cog popups. Usage
counts are from the source: about 1,170 sliders, 1,000 toggles, 690
dropdowns, 130 labels, 70 multiSwatch, 55 colorpicker, 36 input, plus
checkbox, button, labeledButton, spacer, keybind, segmented, reorder and
reordercheck.

```
{ type="slider",  text, min, max, step, getValue, setValue, tooltip,
  pixel?, trackWidth?, snapPoints?, valueSnap?, tooltipOnControl? }
{ type="dropdown", text, values, order, getValue, setValue,
  dropdownWidth?, disabledValues?, itemDisabled?, itemDisabledTooltip? }
{ type="toggle" | "checkbox", text, getValue, setValue }
{ type="colorpicker", text, getValue, setValue, hasAlpha }
{ type="multiSwatch", text, swatches = { {tooltip, getValue, setValue,
  hasAlpha, onClick?, refreshAlpha?}, ... } }
{ type="input", text, getValue, setValue, placeholder, inputWidth, inputStyle }
{ type="button", text, onClick, width }      -- or labeledButton (label + button)
{ type="label", text }                        -- informational slot
{ type="spacer" }                             -- empty half
-- common to all: tooltip, disabled=fn, disabledTooltip=string|fn,
-- rawTooltip=fn, requireState, labelOnlyDisabled, noCapture, tooltipOpts
```

**Dropdown values** are `key -> label`. A label can instead be a table
`{ text, note, font, action }`:
- `font` renders that menu item in its own font, which makes a font preview
  menu.
- `note` adds dim secondary text.
- `action` makes the entry a command (such as "Edit...") rather than a value.

Other dropdown features:
- A `"---"` key in `order` draws a divider.
- Items can open **sub-navigation flyouts**.
- A background callback can paint each item with a texture, sometimes layered
  over a base color. This is how texture pickers preview bar textures inside
  the menu.
- Dropdowns expose `_invalidateMenu()` to rebuild menus whose contents change
  at runtime, and `_refreshLabel()` to update only the label text.

### 3.3 Row add-ons (decorations attached to a DualRow half)

DualRow returns a frame with `_leftRegion` and `_rightRegion`. Helpers then
chain small controls **leftward** from the control, using the half's
`_lastInline` as the anchor:

- **Inline cog** (`BuildInlineCog`): a 26px gear icon at alpha 0.4, 0.7 when
  hovered or open, 0.15 when disabled. It opens a **cog popup**: a compact
  floating panel with a title and rows of
  slider/toggle/dropdown/input/button/segmented/reorder/reordercheck/swatches.
  Rows can be hidden dynamically (`row.hidden`). This is how "advanced" knobs
  such as X/Y offsets, border shift, show-behind and text size stay off the
  main page. The popup's title names the group, for example "Border Options",
  "Spell Icon Settings" or "Duration Text".
- **Inline toggle** (`BuildInlineToggle`): a smaller toggle (0.8 scale) left
  of a slider or dropdown, gating that control. For example, a toggle beside
  "Duration Size" turns the duration text on or off.
- **Inline swatches** (`BuildInlineSwatches`): color swatches beside a
  control, often a "Custom | Class color" pair. The inactive swatch dims to
  alpha 0.3, and clicking it switches mode instead of opening the picker.
- **Inline button** (`BuildInlineButton`): a small text button such as "Edit
  Filters" or "Edit Blacklist".
- **Unlock jump** (`BuildUnlockJump` / `BuildSectionUnlockJump`): an icon that
  opens Unlock Mode focused on this element's mover. It remembers the module
  and page to return to.
- **Row label menu**: the label itself becomes a dropdown trigger.
- **Sync icon** (`BuildSyncIcon`, "apply to all"): copies this setting's value
  to every other unit, bar or instance, or to a chosen subset through
  `BuildMultiApplyDropdown`, which lists checkboxes per target with an Apply
  button. Targets flash an accent border (`PlaySyncFlash`). The icon shows
  whether every target already matches. Global Settings has "Disable Sync
  Icons" and "Only Hide Fully Synced".
- **"Less common" expander**: a link that reveals rarely used rows of a
  section. It opens automatically while a search is active.
- **Cursor anchor row**: a shared "attach to cursor" row.

### 3.4 Other shared widgets

- **Segmented control:** a pill tab bar, 28 tall with a dark #202023 pill.
  The active segment uses the accent color and inactive segments are
  #77787b. It is used for **multi-edit**: select several units or bars and
  edit them all at once. One segment can be the "primary" (the "eyeball").
  Segments can be disabled with a tooltip.
- **Checkbox dropdown** (`BuildVisOptsCBDropdown`): a multi-select list with
  checkboxes and an optional search field, close button and max visible
  items. It is used for "Enabled Classes", "Stats to Show" and "Show In".
  `BuildReorderCBDropdown` adds drag reordering. `BuildSliderDropdown` is a
  dropdown whose menu holds several sliders. `AttachEmptyFilterWarn` warns
  when no box is checked.
- **Visibility row** (`BuildVisibilityRow`): one control that replaces older
  "Visibility" plus "Visibility Options" pairs, used by about 10 modules. The
  base modes are **Never**, **Always** and **Mouseover**. The match mode is
  **All** or **Any**. Each condition has a **Show** lane and a **Hide** lane
  (mutually exclusive per condition): In Combat, Out of Combat, In Raid Group,
  In Party, Solo (the three group rows form one OR-group), Skyriding
  (Airborne), Not Skyriding, Skyriding Mount, Instances, Dungeons, Housing,
  Mounted, Target, Enemy Target, Resting, and more. Modules can declare
  capabilities, such as no mouseover or no group modes; the Pet Bar, for
  example, cannot use group modes.
- **Aura popups:** `ShowTrackedAurasPopup` is a two-column INCLUDED / EXCLUDED
  spell-ID editor. Adding an ID to one list removes it from the other.
  `ShowSpellBlacklistPopup` edits a blacklist. Both are storage-agnostic and
  take accessor callbacks.
- **Keybind button** (`BuildKeybindButton`): left-click to listen for a key,
  right-click to unbind, Escape to cancel. It supports modifier chords and
  gamepad buttons.
- **Text input:** an edit box slot with placeholder text. It commits on Enter
  or focus loss.
- **Glow controls** (`EllesmereUI_GlowOptions.lua`): each glow setting is a
  "site" descriptor (an icon, bar or engine host) that renders the style
  dropdown, color swatches and a pixel-glow cog. Styles include Pixel Glow,
  Action Button Glow, Auto-Cast Shine, Shape Glow, Modern WoW Glow, Classic
  WoW Glow, Blizzard Default, Solid, and Blizzard (Pandemic) Border. The cog
  has lines, thickness, speed, background and background color.
- **Page parts:** unlock placeholder ("Move in Unlock Mode"),
  `MaxDurationDropdown`, sound dropdown values (built from a sound media
  list), `BuildLinkRow` (a deep link to another module's setting),
  `BuildActionCardRow`, `BuildNoteRow` (an informational banner),
  `BuildModuleCard`, `BuildManagerTile` (the tile sidebars of the Buff and
  Debuff Manager pages), and `BuildActivationOverlay` (an "enable this
  feature" overlay over a disabled page).
- **Color picker popup:** a singleton that replaces Blizzard's
  ColorPickerFrame. It has a saturation/value square, a hue strip, an optional
  opacity slider, a **Hex#** input, Prev and New preview chips, **Recent
  Colors**, and **Favorites** (right-click a chip to favorite or unfavorite
  it). A "default / custom / class color" **swatch trio** helper covers the
  common three-mode color choice.

### 3.5 Dependency and disable logic

- Any slot can carry `disabled = function() return <bool> end`. When it
  returns true, the control greys out and clicks are blocked, and hovering
  shows a standard sentence built from `disabledTooltip`: "This option
  requires **X** to be enabled". `requireState="disabled"` flips the wording
  to "...to be disabled". A tooltip that already starts with "This option" is
  used as-is. `rawTooltip=fn` decides at runtime whether to wrap the text.
- Because every widget registered a refresh closure, a dependent row updates
  immediately when its parent toggle changes. The setter calls
  `EllesmereUI:RefreshPage()` (the fast path), and every control re-evaluates
  its `disabled()` and value.
- There are three escalating patterns:
  1. **Grey out** dependent rows (`disabled=fn`). This is the default.
  2. **Hide a section while its master toggle is off**: the builder skips
     those rows, and the master toggle's setter is wrapped with
     `SectionToggleSetValue`, which forces a rebuild.
  3. **Hide individual rows depending on a value**: `DependentSetValue(pred,
     fn)` rebuilds only when the predicate actually flips, which avoids a
     rebuild flash on every value change.
- **Per-item disables** inside a dropdown use `itemDisabled(val)` and
  `itemDisabledTooltip(val)`, for example a shape that a given bar does not
  support.
- **Unit capability gating** (Unit Frames): `UNIT_SUPPORTS[key][unit]`. A row
  the selected unit does not support is dimmed to 0.35 with an explanatory
  tooltip.
- **Style gating:** `EllesmereUI.BlizzStyle.Gate(module, cfg)` hides rows that
  only make sense for the custom look while a stock Blizzard or Classic style
  is active. A row whose controls are all gated is built but takes no height.

### 3.6 Setter wrapping (important cross-cutting hooks)

Every toggle, slider, dropdown, checkbox and swatch silently wraps the caller's
setter to:
1. record the write for **Spec Overrides auto-capture**, attributing it to
   the row slot under the mouse;
2. set `EllesmereUI._settingsChanged = true`, used for "unsaved / reload"
   prompts;
3. keep `_captureCfg` on the row frame (type, label, get/set, range), so other
   systems can mirror the control. The Spec Overrides management page rebuilds
   overridden controls from these descriptors.

---

## 4. Live preview and refresh dispatch

- **Changes apply instantly.** A typical setter writes the profile key, then
  calls the module's apply function and then the preview update. In
  paraphrase: `set(v): db[key]=v; ReloadFrames(); UpdatePreview()`. There is
  no "Apply" button except where a reload is genuinely required.
- **Module apply functions** are reached through the module namespace:
  `ns.ReloadFrames`, `ns.RefreshAllSettings`, `ns.RefreshFriendlyBelowName`
  and so on. They are resolved **at call time**, never captured at load,
  because modules wrap their own functions later.
- **Selectors:** large modules edit one instance at a time. Unit Frames picks
  a unit, Action Bars picks a bar, Cooldown Manager picks a bar, Raid Frames
  picks a size bracket. The page keeps `optState.selectedUnit` or the
  equivalent. Helpers `SVal(key, default)`, `SSet(key, v)` and `SDB()` route
  reads and writes to the selected instance's table. With multi-edit active,
  writes fan out to every selected instance.
- **Preview in the content header:** Nameplates (Display page), Unit Frames,
  Action Bars (Bar Display), Cooldown Manager and Raid Frames all draw a
  **mock** of the element in the fixed header above the scroll area. It is
  built from the same settings with fake values (randomized nameplate names,
  health and auras) and updated through `UpdatePreview()` after every write.
  Previews re-render on panel scale changes so border pixels stay crisp.
- **Clickable previews:** `CreatePreviewHitOverlay(element, navigate, key)`
  puts a hover-highlight button over each part of the preview, such as the
  health text, cast bar or a buff icon. Clicking it scrolls the page to the
  matching setting and glows it with `MakeSettingGlow`, a pulsing accent
  outline. A one-time hint explains this.
- **In-world previews:** some modules also force their real frames into a
  preview state while the panel is open, such as boss frames with fake
  debuffs, raid preview, CDM buff previews or the edit overlay on an action
  bar. They clean up through `RegisterOnHide` and `onModuleLeave`.
- **Reload-gated settings** (global font, chat font, style, bag style, some
  skins) open a "Reload Required" confirm popup. Style settings are written
  **only** inside the popup's confirm handler, so cancelling leaves the
  profile untouched.
- **Profile switch:** invalidates page caches and calls every module's
  refresh. Some modules need a reload, and a popup offers "Reload Now".

---

## 5. Visual style

- **Accent color:** default teal **#0CD29D**. Themes: EllesmereUI (teal),
  EllesmereUI Original, EllesmereUI Forever (bronze #DCA77F), Horde
  (#FF5A1F), Alliance (#3FA7FF), Faction (Auto), Midnight (purple #7841C8),
  Dark (white), Pixels (white), Class Colored, and Custom Color (a picker).
  Every accent-colored element registers in an accent registry (`RegAccent`)
  under one of the kinds solid, gradient, font, vertex or callback, so a theme
  change recolors everything live.
- **Theme background art:** each theme has a full-window painted background.
  Teal art is desaturated and vertex-tinted to the accent, with a brightness
  boost for dark accents. On a theme switch two background layers crossfade
  over 0.5 seconds.
- **Surfaces:** a warm near-black panel (about #120F0C). Borders are white at
  alpha 0.05. Every grey is "white plus alpha" so it adapts to any tinted
  background.
- **Text:** white for labels, dim text at alpha 0.53, section headers at alpha
  0.41.
- **Control colors:**
  - Dropdown: background about #1A1816 at alpha 0.9 (0.98 when hovered),
    border white at alpha 0.20 (0.30 hovered), value text alpha 0.5 (0.6
    hovered). Menu item hover alpha 0.08, selected item alpha 0.04.
  - Button: background #171412 at alpha 0.6, border alpha 0.3 (0.45 hovered),
    text alpha 0.55 (0.70 hovered).
  - Checkbox box #1C1B19. Slider input box near black at alpha 0.25.
- **Font:** **Expressway** (a condensed sans) everywhere in the panel. For
  CJK and Cyrillic locales a system font fallback is used. Labels are size
  14, section headers 12, dropdown values 13, segmented control 13, search
  breadcrumbs 10.
- **Spacing:** content pad 45, row height 50 (checkbox 36), section header 40,
  in-row inset 20, inline control gap 8, label-to-control gap 12.
- **Tooltips:** one shared tooltip frame with a fade-in. It follows the panel
  scale only for anchors inside the panel.
- **Motion:** toggles animate their knob. Scrolling is smooth with lerp.
  Footer buttons fade their colors. Sync flashes and setting glows pulse.
  Backgrounds crossfade.
- **Pixel perfection** is everywhere: `PP.Size` and `PP.Point` snap to
  physical pixels, borders are always 1 physical pixel, and borders are
  re-snapped on scale changes.

---

## 6. Global search

- **Index:** built automatically by `SectionHeader` and by `TagOptionRow` and
  `IndexSlotForSearch`, which every factory row calls. Each entry stores the
  label (plus its localized form), the tooltip, the module, the page, the
  section, a "selector context" (which bar or unit was selected while it was
  built), and flags. Lowercase and space-free copies are precomputed, so
  "castbar" finds "Cast Bar".
- **Pre-build pass:** pages nobody has opened still need indexing. On the
  first search, every page builder runs once, with `EllesmereUI.Widgets`
  **swapped for a stub "absorber" factory**. The stub records labels and
  returns an object that swallows any method call, field access or
  arithmetic, and creates no frames. An earlier version built about 48 real
  pages, which leaked 10 to 25MB of frames. Builders check
  `EllesmereUI.IsSearchPrebuild()` (or `_prebuilding`) to skip side effects.
  Errors are swallowed per page, and that page is indexed on its first real
  visit. Pages can also be re-run with alternate selector values, so options
  that exist only under one selection are still findable.
- **Coarse targets:** every module and every page is itself a result ("Damage
  Meters > Spell History").
- **Scoring tiers**, best first: exact label substring, plural/stem match,
  exact tooltip match, tooltip stem, fuzzy label, fuzzy tooltip. The fuzzy
  match is a subsequence test with a density limit (match span at most the
  needle length plus 8) to reject scattered matches.
- **Module-scoped queries:** a module name or alias anywhere in the query
  ("raid frames border style", or "border style raid frames") adds a
  **boosted** pass limited to that module's entries. The plain pass always
  runs too, so cross-module matches are never removed. A module name that is
  still being typed works as a prefix filter.
- **Synonyms:** curated alternate terms, such as "skyriding" for "Dragon
  Riding", and abbreviations such as "cdm" and "rf".
- **Results UI:** a popup 380 wide with 34-tall rows, up to N visible. Each
  row shows the label plus a breadcrumb "Module > Page" with an arrow glyph.
  Choosing a result calls `NavigateToElementSettings`: select the module and
  page, restore the selector context, scroll to the row and pulse a highlight
  on it.
- **Inline page search** (the tab-bar box) is separate. It filters the current
  page's rows in place and expands "less common" sections.

---

## 7. Profiles & Presets module

This is its own sidebar entry with four tabs.

- **Profiles:**
  - Active Profile dropdown, plus New Profile, Copy Profile, Rename Profile
    and Delete Profile. A name-taken check and a confirm step guard these.
  - **Assign to Spec / Auto Assign to Specs:** a popup assigns profiles to
    specializations. If the current spec has an assigned profile, manual
    switching is blocked with an explanation.
  - **Export Profile:** pick which addons to include (checkbox list with
    Select All and Deselect All), then copy a string. Format: prefix `!EUI_`,
    then the serialized table, deflate-compressed and print-encoded with
    LibDeflate.
  - **Import Profile:** paste a string. It validates and handles an
    interrupted paste ("could not be read completely"), then shows an addon
    checklist with a status per addon: Ready, Skipped, Not Loaded, Not
    Included. Import into a new profile (name it) or overwrite. Options
    include Import Full Account Data, Keep Mine versus overwrite Window and
    Tooltip settings, and **UI Scale Mismatch** detection with "Match Scale".
    Resolution and UI-scale warnings say "frame positions may be off". The
    flow ends with "Import & Reload".
  - Keybind handling: profile-specific keybinds.
- **Presets:** "Popular Presets", community preset strings with previews, and
  "Browse community presets".
- **Overrides:** two management lists.
  - **Spec Overrides:** spec "groups" (cards with an icon and a set of specs).
    "Editing as <group>" swaps that group's values into the live profile; the
    user then edits with the normal widgets, and every write is auto-captured.
    Overridden rows get a **gold 1px border** on the real options pages. The
    management list shows each captured setting with "Go To Setting" and
    "Remove".
  - **Conditional Overrides:** the same idea, driven by conditions rather
    than specs.
- **Full Export:** export or import the whole account.
- **Profile sync:** per-module sync icons in the sidebar link a module's
  settings across several profiles.

---

## 8. First install, style choice, presets

- **First-install popup** (at PLAYER_LOGIN, before the addon-conflict check):
  - A modal dimmer with eyebrow text "FIRST TIME SETUP" and title "Welcome
    to ...".
  - **One column per sidebar group**, one checkbox per addon. A checkbox can
    also be a "front-end shortcut" that writes a feature flag, for example the
    QoL cursor circle.
  - Check All and Uncheck All links.
  - The only button is **Reload UI**. Escape is disabled, so the choice always
    takes effect. The popup is clamped to the screen.
  - It sets `firstInstallPopupShown`.
- **Style choice popup** (next login): three **look cards**, each with a
  live-drawn miniature of a unit frame and an icon row:
  - **EllesmereUI Style:** flat bars and square icons.
  - **Blizzard Style:** the stock player frame art and gryphon end caps,
    keeping every EUI feature.
  - **Classic WoW UI:** the vanilla art.
  The same cards head **Global Settings > Style**, where a per-module
  checkbox dropdown under each card assigns modules to looks. "Apply Styles"
  shows one reload prompt.
- Ordered **intro popups** (patch notes, raid frames, window skins, spec
  overrides and others) are chained so that only one shows at a time, and the
  conflict check runs after the last one.
- **Conflict check:** warns about overlapping addons, for example Leatrix Plus
  chat and minimap features.

---

## 9. Global Settings module (tabs: General, Style, Fonts, Textures, Glows, Colors, Gamepad*)

\*The Gamepad tab appears only if Action Bars, Unit Frames or Resource Bars is
loaded.

- **General:**
  - DISPLAY: UI Accent Color, EUI Options Theme, EUI Options Language (11
    languages, reload), UI Scale (pixel-perfect helper, with a popup on
    change), Hide Pause Menu Button, Hide Unlock Mode Menu Button, Show Minimap
    Button, EUI Buttons, Disable Sync Icons (cog: Only Hide Fully Synced).
  - UNLOCK MODE: Point Anchoring, Overlap Cycling.
  - COMBAT: Max Camera Distance, Increase Game Image Quality, Cast Actions on
    Key Down, Lag Tolerance.
  - Blizzard **Combat Text**: a font picker (about 25 bundled fonts), size,
    and per-category toggles (Damage, Periodic Damage, Pet Melee, Pet Spell,
    Healing, Absorb Shields, Target Effects, Others' Target Effects; logout
    required).
  - Prevent Swiftmend Icon Dim, Round Timer Seconds Down.
  - DEVELOPER: Suppress Lua Errors, Spell ID on Tooltip.
  - A "Reset EUI Module Settings" menu.
- **Style:** the look cards plus the per-module look assignment, Border Size,
  and Apply Styles.
- **Fonts:**
  - GLOBAL FONT: Global Font (System Default / Expressway / Blizzard Default /
    bundled fonts / SharedMedia), Outline Mode (Drop Shadow, Outline, Thick
    Outline), Apply to All Game Text, Outline Icon Text, Disable Slug Outline,
    per-module icon text toggles (Action Bars, Unit Frames, CDM, Raid, Bags),
    Name Font, Game Text Scale (logout).
  - MODULE FONTS: per-module font and outline overrides, each with "EUI
    Global Default", plus size knobs (aura stacks, healer mana text, chat, tab
    and edit box fonts, timer fonts, quest tracker, tooltip scale, enchant
    text, dragonriding speed text, combat text, and others).
- **Textures:** MODULE TEXTURES lists one picker per module surface: health,
  cast, GCD, background, tab, cursor ring, cast ring, meter bar, breakdown,
  spell history, dragonriding. Absorb, Heal Absorb and Max Health styles are
  also here. Bar textures are a curated list of about 22 plus SharedMedia.
- **Glows:** GLOW TEMPLATE (a shared style that modules can inherit, with
  Pixel Glow Settings) and MODULE GLOWS (Buff Manager icon glows, Debuff
  Manager glows, Player Aura Bars glows, and others).
- **Colors:**
  - DARK MODE: per module (Unit Frames, Raid & Party, Class Resource), Color
    Darkening, Dark Mode Fill, Background, Apply to All Profiles, Pull Colors
    From.
  - CLASS COLORS: one override per class.
  - POWER COLORS: one per power type.
  - CLASS RESOURCE COLORS: Combo Points, Runes, Soul Shards, Holy Power,
    Arcane Charges, Icicles, Chi, Essence, Soul Fragments, Maelstrom Weapon,
    Tip of the Spear, Whirlwind Stacks, Sweeping Strikes.
- **Gamepad:** ACTION BARS (Hide Action Bars) and CAST BARS (hide the Unit
  Frames or Resource Bars cast bar) when playing with a controller.
- Separate sidebar entries: **Patch Notes** (a per-version changelog with
  module tags) and **EUI Legends** (credits).

---

## 10. Per-module feature catalog (parity checklist)

Conventions in this catalog:
- "[cog]" means the item lives in an inline cog popup on the row above it.
- "+X/Y" means it has X/Y offset sliders.
- "Border block" means: Border Style (a texture list), Border Size, a color
  swatch, and a cog with Shift X, Shift Y and Show Behind.
- "Text block" means: Size, X, Y, often Anchor, plus color.

Most modules also have an **Unlock Mode** jump, **sync icons** ("apply to
all") on most rows, and a **Visibility row**.

### 10.1 Action Bars (tabs: Bar Display, XP Bar, Menu/Bags & Rep Bars, Bar Animations)

The bar selector covers Bar 1 to 8 (plus custom Bar 9 and 10), Stance and Pet.
A segmented multi-edit control and a live preview of the selected bar sit in
the header. Selecting a bar shows an "edit overlay" at the real bar's position.

- **Layout and visibility:**
  - Toggle Action Bar (enable).
  - Visibility row (Never / Always / Mouseover plus conditions). Extras: Show
    When Spellbook Is Open, Show During Drag. The Pet Bar cannot use group
    conditions.
  - Show All Bars on Mouseover, Bar Opacity, Always Show Buttons (empty
    slots), Click Through.
  - Icon Size, Button Spacing, Number of Icons, Number of Rows [cog: Grow
    Direction], Vertical Orientation, Icon Order.
  - Show Bar Background [cog: Width, Height, End Caps].
- **Bar background:** Enable Bar Background, Spacing, Background Color and
  Opacity, Border block, Multiplier X and Y [cog: growth direction].
- **Button appearance:**
  - Border Style and Size [cog incl. Border Above Effects].
  - Custom Button Shape (square, cropped, circle and others), Icon Zoom.
  - Blizzard Icon Background [cog: Opacity].
  - Cooldown Numbers [cog: Charge Recharge Numbers].
  - Icon Background.
  - One Button Assist Icon [cog: Icon Outset].
- **ICON EFFECTS:** Desaturate on Cooldown, Disable Tooltips, Out of Range
  Coloring, Show Item Rank, Alpha when on CD, CD Swipe Opacity, Hide Charge
  Count at 0, Show Equipped Item Color.
- **PAGING:**
  - Per-bar paging targets (Action Bar 1 to 10).
  - Disable Form Paging, Disable Skyriding Paging.
  - Paging Arrows [cog: Show Arrows on Right], Skip Visible Bars When Paging,
    Modifier/Target Paging.
- **Text:**
  - Hide Keybind Text, Keybind Text Size [cog: Position, X, Y].
  - Hide Macro Text, Macro Text Size [cog: Position, X, Y].
  - Charges Text Size [cog], Cooldown Text Size [cog: X, Y, Fit Size to
    Button].
- **End caps:** Left and Right Endcap art, Size, X and Y [End Cap Settings
  cog].
- **Bar Animations tab:**
  - Custom Proc Glow (glow site).
  - Bar Interactions Color, Class Colored Bar Interactions.
  - Pushed Type and Highlight Type [cogs: Border Size, Match Bar Border].
  - Hide Casting Animations, Show Highlight on Spell Cast [cog: Show as
    Border], Glow Color.
  - Assisted Highlight, Assisted Highlight Outset, Overlay Opacity, Fit Ring
    to Cropped Buttons.
- **XP Bar tab:**
  - CORE: XP Bar Style, Visibility, Show Dividers, 5% Line Style, Divider
    Text [Text Color, Size, X, Y], Ticks [Show Ticks Over Fill Bar].
  - CORE TEXT POSITIONS: **text slots** (Center, Left, Right and the four
    corners), each with a content choice (Current %, Current, Current/Max,
    Current/Max (Remaining), Rested, Rested %, Completed Quests (and %),
    Level, XP per Hour, Leveling In, Time This Level, Time This Session),
    Size, X and Y, Show Rested, and Remove. A "+ Add Text Slot" button adds
    more.
  - DISPLAY: Text Background, Fill Style, Rested Color, Fill Animation
    [Animate on XP Gain, Loop, Stretch to Bar], Background, Quest XP Overlay
    [Completed Quests Only, Current Zone Only].
- **Menu, Bags & Rep Bars tab:**
  - MICRO MENU & BAGS: visibility, end caps, Use Blizzard's Rep Bars.
  - Rep/Favor bars: Orientation [Rotate Bar Text, Rotate Divider Labels, Read
    Downward], Border block, Width, Height, Bar Texture, Click Through, Text
    Size [Anchor, X, Y], Custom Border, Color.
  - VEHICLE BAR: Hide Blizzard's Vehicle Bar.

### 10.2 Nameplates (tabs: Display, Colors, General)

The Display tab has a live nameplate preview in the header, with randomized
names and auras, and clickable parts.

- **Display > STYLE:**
  - Border (none, custom, and others), Border Size, Corner Radius [Wrap Around
    Castbar, Show Seam Line], Castbar Border.
  - Level Size, Elite Icon Size [X, Y].
  - Custom Border Style and Size [Shift, Show Behind].
  - Icon Borders [Custom Border on Aura Icons, on Spell Icon, Vertical
    Separator].
  - Background, Absorb Style [Opacity, Placement], Bar Texture, Cast Bar
    Texture, Show Level Box.
- **Display > CORE POSITIONS:** placement of the aura slots (**Debuffs, Buffs,
  Crowd Control, Debuffs + CC**). Each slot has a position (Top, Left, Right,
  Top Left, Top Right, Bottom), growth direction, a PvP-flag filter (Dim
  Unflagged / Flagged Only / Ignore), and custom spell-ID include lists.
  Raid Marker and Elite Icon positions are also here.
- **Display > CORE TEXT POSITIONS:** text slots (Top, Left, Right, Center,
  Bottom Left, Bottom Right). Content choices: Name, Level, Name | Level,
  Level | Name, Health %, Health #, combined formats, Name > Target, None.
  "+ Add Text Slot". CORE TEXT COLORING: Custom Name Color, Custom Level
  Color, Level Difficulty Color.
- **Display > HEALTH AND CAST BAR:**
  - Health Bar Width and Height, Cast Bar Height.
  - Spell Icon [Scale, X, Y, Make Icon Part of the Bar, Icon on Right, Full
    Sized, Hide Border, Use Target Border Color].
  - Cast Background, Cast Bar Border, Cast Timer, Cast Bar Y Offset.
  - Cast Color [Show Shield Icon, Show Spark, Important Cast Color,
    Interruptible While Kick Ready].
  - Kick Ready Mid-Cast Hint, Casts In Front of Nameplates, Show Interrupted
    Flash Effect, Focus Text Reminders.
- **Display > TARGET, FOCUS & HOVER EFFECTS:**
  - Target Effect (EUI Glow, Border Color, Highlight, Border Size, and more
    effects [Highlight Color and Opacity, Glow Opacity]).
  - Target Arrows [Scale].
  - Enable Target Color and Enable Focus Color.
  - Target, Focus and Hover Textures [Opacity, Full alpha on empty part,
    Don't tint].
  - Target and Focus Preview, Hover Effect.
- **Display > CLASS RESOURCE:** Show Class Resource, Fill Color, Position,
  Size [Position Settings], Bar Spacing, Background Color, Shape, Border
  [Thickness].
- **Display > GENERAL TEXT:** Debuff, Buff and CC Duration, Aura Stacks (each
  with a [Size, X, Y] cog), Spell Name, Spell Target.
- **Display, glow sites:** Dispel Glow, Pandemic Glow (Blizzard Pandemic
  Border), Important Cast Glow, Textured Background, Color by Type
  (Magic/Enrage).
- **Colors tab:**
  - Enemy Types: Modify Out of Combat, Enemy Colors [Simple Coloring When Not
    in M+, All Enemies], Neutral & Mini Enemies [Mini Coloring M+ Only],
    Enable Quest Mob Color.
  - Threat: Show Threat Colors, Tank Threat, Non-Tank Threat, the DPS and Tank
    "special" states (Near Aggro glow, No Aggro and Has Aggro, each with
    overrides for Mini-Boss, Caster and Boss colors), Classic Tank Aggro, Show
    Threat On (Health Bar / Border / Name), Show Threat % on Nameplates, Threat
    % Position [Text Shows, Color by Threat].
  - DEBUFF BASED NAMEPLATE COLORING: Debuff Coloring, Only My Debuffs, Color
    Border [Extra Border Size], Texture. A list editor (DEBUFFS and COMBOS
    with "+ Add Debuff", "+ Add Combo" and "+ Add Class") recolors a plate
    when specific debuffs or debuff combinations are present.
- **General tab:**
  - Friendly players: Show EUI Friendly Player Nameplates, Make Friendly
    Nameplates Name Only [Distance, Height, Width, Name Size, Show Health
    Percent, Class Colored Health Bar, Class Colored Names, Target Border
    Effects], Name color as a White or Class swatch pair.
  - Subtitle Text (None, Player Title, Guild Name, Title & Guild) [Name Text
    Settings: Show <> Around Guild], Guild Text Color (custom or class).
  - Friendly NPCs: Show Friendly NPC Nameplates, Friendly Name Size [Show NPC
    Titles, Name Size, Title Size, Name Color, Title Color], Friendly Names
    Not Clickable.
  - Show Enemy Pet Nameplates, Name Distance.
  - Stacking: Stacking Nameplates, Stacked Nameplate Spacing [Enemy and
    Friendly], Hitbox Size X and Y, Stacking Speed, Top Screen Inset.
  - Auras: Max Debuffs (reload), Show Buff/Debuff Tooltips, Pandemic Glow
    Preview, Enemy Buff Filter.
  - TARGET AND FOCUS EFFECTS:
    - Show Hash Line on Target at Percent, Hash Line Location, Scale Target
      Nameplate.
    - Non-Target Opacity [Keep Focus Full Opacity].
    - Focus Cast Height, Focus Letter [Anchor, Size, X, Y].
    - Distance to Target Text [Size, Offsets].
    - Scale Nameplate On Cast, Hide Enemy Name While Casting.
    - Name Raid Marker [Size].
    - Experimental: Cast Lockout as CC Icon.
    - Replace Quest Icon with Objective [Text Size].
    - Line of Sight Opacity, Range Check [Custom Range], Out of Range Opacity.
    - Execute Pulse Glow.
    - Hide Enemy Nameplates out of Combat, Out of Combat Opacity.
    - Hide Copies of Blood Plague, Show Sunder Armor.

### 10.3 Unit Frames (tabs: Main Frames, Boss Frames, Mini Frames, Player Aura Bars)

Main Frames covers the selected unit: Player, Target, Focus, Target of
Target, Focus Target, and Pet. A segmented multi-edit control and a live unit
preview sit in the header. Rows the selected unit does not support are dimmed.

- **DISPLAY:**
  - Show Nicknames.
  - Fade Out of Combat [Show When Health Missing, Out of Combat Alpha].
  - Bar Texture, Dark Mode.
  - Border block [Power Bar Seam], Corner Radius.
  - Show Tooltip For.
  - Frame Strata [Unit Frame, Main/Boss auras, Detached Power and Text Bar
    stratas].
  - Show Decimal on Health Text [Only for %, Show 2 for Boss, Hide Trailing
    Zeros].
  - Hover Borders [Highlight, Player Threat (non-tank)].
  - Show Threat % on Target, Threat % Position [Show on Focus, Color by
    Threat].
  - Blizz Colored Target Header.
- **PORTRAIT:**
  - Portrait Mode (none, 2D, 3D, class), Art Style, Custom Non-Player
    Portrait, Vertical Border Separator.
  - Size, Position, Portrait Zoom [2D, 3D and class zoom, Mirror], Offsets.
  - Shape, Shape Border [Size, Opacity, Unit Color in Dark Mode, Outer Ring
    and its Size, Inner Shadow].
  - Elite "Dragon" decoration [Size, X, Y, Flip, Class Color, Strata, Frame
    Level, Show in Instances].
- **HEALTH BAR:**
  - Health Bar Height, Bar Width, Frame Scale.
  - Reverse Fill and Vertical Fill.
  - Fill Color (class, reaction, custom, dynamic) [Dynamic Color, Enable
    Gradient, Gradient Direction], Bar Background (custom or class swatch,
    with opacity).
  - Smooth Health Bars, Fill Opacity.
  - Show Level [Size, X, Y, Difficulty Color].
  - Left, Right and Center Text plus Extra Text (full length). Each has a
    content format (Health %, Health #, # / Max, # | %, short, Name, Name >
    Target, Power, Health | Power, and so on) and a cog [Size, X, Y, Width %,
    Indicator Color, Separator, Prefix, Alignment]. Class color toggles are
    available per side.
- **POWER BAR:**
  - Hide Power Bar, Power Bar Height.
  - Bar Position (attached or detached) [Width, X, Y], Reverse Fill.
  - Power Text, Fill Opacity, Fill Color, Bar Background, Gradient.
  - Text Position and Color [Size, X, Y].
  - Power border block.
  - Spell Cost Prediction and its color, Mana Regen Spark.
  - Power Type (for shapeshifters).
  - Form Power Bar [X, Y], Form Power Text and its Position [Show %, Size, X,
    Y].
- **CLASS RESOURCE:** Enable Class Resource (reload), Fill Color, Position,
  Size [X, Y], Bar Spacing, Background Color, Combo Points style.
- **ABSORBS AND HEALS:**
  - Absorb Style and Opacity [Placement, Show Overshield, Blizzard Glow Line,
    Glow Line Texture, Show on Boss Frames].
  - Heal Absorb Style and Opacity [Placement, Backing Opacity].
  - Absorb Bar and Heal Absorb Bar with heights.
  - Heal Prediction, Prediction Opacity, Overheal, Heal Prediction Texture.
- **CAST BAR:**
  - Show Cast Bar, Height [Hide When Idle, Fill Opacity, Raise Cast Bar Strata,
    Kick Ready Mid-Cast Tick and Bar, Custom Border Style].
  - Show Icon [Icon Border, Part of Bar, Border Wraps Icon, Vertical Separator,
    Icon on Right, Icon on Portrait, Offsets].
  - Bar Background, Spell Name and Duration [Size, X, Y, Combine Spell Name and
    Target], Spell Target, Reverse Fill.
  - Important-cast glow [Glow Color].
- **TEXT BAR (detached info bar):** Enable Text Bar, Position [X, Y], Height,
  Width, Left, Right and Center Text [Size, X, Y, Width %, Indicator Color,
  Separator], Class Icon [Size, Location, X, Y].
- **BUFFS AND DEBUFFS:**
  - Buff Display and Debuff Display (location), Size [Icon Zoom, Dispel Type
    Borders, Use Dispel Colors], Position cogs [Growth, Max Count, Max Per Row,
    Offsets, Spacing X and Y, Cropped Icons, Max Important].
  - Duration and Stack Size [offsets, Precise Below (minutes)].
  - Border block [Behind Unit Frame, Textured Dispel Ring].
  - Filters: buff filter (All, Has Duration, Stealable, Big Defensive,
    Dispellable, Purgeable) and debuff filter (All, Has Duration, Hide
    Exhaustion, Match Mode), with "Edit Filters" and "Edit Blacklist" (the
    tracked-aura popups). Copy Included/Excluded Spells From (Target, Focus,
    Boss).
  - Dispel Overlay [Opacity, Color Custom Borders], Dispel Colors, Type Icon
    Position [Size, Offsets], Only Dispellable by You.
  - Purgeable Buff Glow and Important Cast Glow (Target and Focus).
- **EXTRAS:**
  - Combat Indicator [Class Colored, Position, Size, X, Y], Enemy Colors.
  - Raid Marker and its Size [Position, X, Y].
  - Leader Indicator [Icon Style, Position, X, Y].
  - Elite/Rare Indicator [Show in Instances, Style, Position, X, Y].
  - Faction Indicator [PvP Flag, Players Only, Icon Style, Position, X, Y].
- **Boss Frames tab:**
  - Enable Boss Frames, Show Portrait, Stack Direction, Vertical Spacing.
  - Simple Buff and Debuff Display [Max, Per Row, Offsets, Spacing, Duration
    and Stack positions], Boss Buff Filter, Debuff Filter.
  - Raid marker [Alignment], Out of Range Alpha, Spell Target, a full cast bar
    block, and an in-world boss preview toggle.
- **Mini Frames tab** (Target of Target, Focus Target, Pet):
  - DISPLAY: Hover and Target borders, Strata, Bar Texture, Dark Mode, Border
    Size, Show Highlight Border.
  - HEALTH BAR: same as Main Frames, reduced.
  - POWER BAR: Height, Above Health Bar, Fill and Text.
  - Portrait [Portrait on Right, Art and Class Style, Mirror].
  - Enable Pet Frame [Always Show Pet Frame].
  - PET HAPPINESS: Show Happiness, Size, Position, X, Y.
  - Buffs and Debuffs: locations and sizes, Copy Auras From.
- **Player Aura Bars tab** (player buff and debuff icon bars, replacing
  Blizzard's buff frame):
  - ASSIGNED BUFFS and ASSIGNED DEBUFFS: Filters, Extra Spells (custom IDs and
    presets), Edit Filters, Edit Blacklist.
  - CORE: Icon Size [Zoom], Growth Direction [Icon Wrap], Sort Method and Sort
    Direction, Duration [Text Size, Offsets, Position, Show S for Seconds,
    Precise Below], Stacks, Font Outline.
  - DISPLAY: Border block [Textured Dispel Ring], Icons Per Row [Max Rows, Max
    Total], Spacing [Row Spacing], Icon Shape, Icon Zoom, Show Duration Swipe
    [Reverse], Show Tooltips, Right-Click to Cancel.
  - DEBUFF DISPLAY: Type Icon Position. DISPEL COLORS: Magic, Curse, Disease,
    Poison, Bleed.
  - ICON EFFECTS: glows per filter.

### 10.4 Raid & Party Frames (tabs: Frames, Party, Buff Manager, Debuff Manager, HoverCast)

A raid size bracket selector covers "20 Man" and similar brackets, plus custom
sizes.

- **FRAME SIZES:**
  - Width and Height per bracket [Covers Up To, Switch At, Group Growth, Unit
    Growth, X, Y].
  - Auto Resize Icons [Indicators & Auras, Tracked Buffs].
  - "Add Custom Raid Size".
- **FRAME DISPLAY:**
  - Frame Spacing [Compact Mode], Group Spacing [Grid Mode].
  - Border block, Corner Radius.
  - Show When Solo.
  - Hover Borders [Hover and Target Border, sizes].
- **LAYOUT:**
  - Group Growth, Unit Growth.
  - Sort By (Group, Role, FrameSort) [Class Sorting: Prioritize Class, Class
    Order], Self Position.
  - Show Groups [per group, Hide Empty Groups, Hide Groups 5 to 8 in Mythic
    Raid, Exclude Hidden from Size], Merge Groups.
- **FRAME STYLE:** Frame Style (reload), Frame Scale [Spacing], Debuff and
  Buff Size [positions].
- **RAID SYNC AND SOLO:** Use Raid Settings For, Show When Solo [Center When
  Solo].
- **Party tab (FRAMES):**
  - Frame Width and Height, Horizontal Frames, Sort By, Self Position, Hide
    Self, Auto Resize Icons, Frame Spacing, Frame Growth, Party Frames in Small
    Raids.
  - PARTY TARGETS: Enable Party Targets, Include Own Target, Fill Color,
    Background, Width, Height, Position [X, Y].
  - PORTRAIT: Portrait Mode, Art Style, Size, Position, Zoom, Shape, Shape
    Border.
- **HEALTH BAR:**
  - Health Bar Texture, Fill Opacity [Vertical Fill, Fill Missing Health].
  - Fill Color (class or custom, with a 100% / 50% / 0% gradient), Background.
  - Heal Prediction and its Opacity, Smooth Health Bars.
  - Threat Borders [Color Custom Borders].
- **ABSORBS:** Absorb Style, Opacity [Placement, Overshield, Glow Line], Absorb
  Bar and Height [Vertical Grow], Heal Absorb Style, Opacity and Bar, Max
  Health Style and Opacity.
- **POWER BAR:** Show Power Bar For (Healers, Tanks, DPS), Power Height [Icons
  Ignore Power Bar, Extend Health Behind Power], power border block [Match
  Frame Border, Match Highlight Colors], Smooth Power Bars, Background.
- **TEXT DISPLAY:** Name Format, plus custom text slots via "+ Add Text"
  [Size, X, Y, Max Characters, Show Above Icons].
- **INDICATORS:**
  - Missing Buffs and its Size [class exceptions, per-buff toggles
    (Fortitude, Mark of the Wild and others), Offsets].
  - Role Icons and Show Role (Tank, Healer, DPS) [Role Text, Hide In Combat,
    Show Behind Border], Role Position and Size [offset].
  - Marker Position and Size.
  - Ready Check / Summon / Rez Icon Size [toggles, offsets].
  - Status Text [Show AFK].
  - Leader Icon [Show In Combat].
  - Combat Icon [Style, Class Colored].
  - Show Group Numbers.
  - Ping Marker.
- **DISPELS:** Dispel Overlay and Opacity, Frame Border, Type Icon Position
  [Size, offsets], Dispel Border [Debuff Icon Border, Color Custom Borders],
  Dispel Colors, Only Show Dispellable.
- **TOP NAME BAR:** Enable, Height [Divider, Match Highlight Colors],
  Background, Text Size [Offset], Alignment & Color, Show on Bottom.
- **FRIENDLY BOSS FRAMES:** Add Friendly Boss Group, Position [Show in
  Dungeons], Free Move Position, Boss Health Color [Horizontal], Extra Width
  and Height.
- **EXTRA FRAMES:** Add to Extra Group Hotkey, Show Tanks in Extra Group
  [Exclude Myself], Position, Free Move, Grow and Wrap Direction [Wrap After],
  Extra Width and Height [Auto Resize Indicators].
- **PET FRAMES:** Show Pets, Position, Extra Width and Height, Free Move,
  Growth Direction, Pet Side.
- **EXTRAS:**
  - Out of Range Alpha.
  - Show Raid & Party Frames Tooltip [Buff Tooltips].
  - Healer Mana Display [Size, Spacing, Align, Growth, Show Names in Raid,
    Class Colored Names] and its Text Color.
  - Hide Blizzard Party Panel, Status Colors, Right Mouse Camera Unlock, Frame
    Strata.
- **Buff Manager tab:** a tile sidebar of "indicators". Each indicator has an
  **indicator type**: Icon, Square, Duration Bar, Frame Glow, or Health Bar
  Color.
  - ASSIGNED BUFFS: Filters, Extra Spells (custom spell ID, presets), Show In,
    Custom Order (Buff Order).
  - CORE: Size, Max, Zoom, Position, Growth, Offsets, Icons Per Row, Spacing.
    For bars: Orientation, Position, Frame Level, Reverse Fill.
  - DISPLAY: Show Duration Text and Stacks [Text Size, Offsets], Tooltips (5
    modes: hidden, shown, at cursor, hidden in combat, with modifier), Show
    Duration Swipe, Color, Background, Opacity.
  - ICON EFFECTS: glow filters, Border, Size.
- **Debuff Manager tab:** a "Base Icons" tile that cannot be deleted, plus user
  tiles, editable per spec or spec group.
  - Filter vocabulary: Non-Player Auras, Important, Crowd Control, Boss
    Debuffs, Boss Role Debuffs, Raid, Raid In Combat, Dispellable By You,
    Dispels, All Debuffs, Has Duration, Hide Exhaustion, Match Mode. Less
    common filters: Cast By You, From Any Player, Magic, Curse, Poison,
    Disease, Bleed, Can Apply Aura.
  - Per tile: Size, Max Debuffs, Zoom, Position, Growth, Icons Per Row,
    Spacing, Duration and Stacks text, Tooltips, Swipe, Border Style [Textured
    Dispel Ring].
- **HoverCast tab:** mouseover click-casting bindings. The page builder lives
  in the raid frames addon itself.

### 10.5 Cooldown Manager (tabs: CDM Bars, Bar Glows, Tracking Bars, Rotation Assist Icon)

This module takes over Blizzard's Cooldown Manager. It has a bar selector:
Essential, Utility and Buff bars plus user-created bars, with Rename Bar,
Delete Bar, Repopulate Bars and Sync Generic CDs/Buffs across specs. A live
icon-row preview sits in the header. The **spell picker** adds and removes
spells per bar.

- **BAR LAYOUT:**
  - Number of Rows, Bar Opacity, Bar Background.
  - Row Icons [Row Growth, Custom Base Row Count and Icons, Custom Base and
    Second Row Size].
  - Out of Combat Alpha [Fade Out of Combat].
  - Max Icons (0 = off), Overflow To (another bar), Vertical Orientation, Keep
    Buffs in Same Place.
- **ICON DISPLAY:**
  - Icon Scale, Icon Spacing, Custom Icon Shape [Adjust Crop], Icon Zoom.
  - Border block.
  - Always Show Buffs [Desaturate Off CD].
  - Duration Size [Show Duration, Position, X, Y].
  - Charge/Stack Size [Show Item Count, Item Quality, Charge/Stack Text,
    Position, X, Y].
  - Suppress GCD.
  - Pixel Glow Thickness [Lines, Speed, Background, Background Color].
  - Only Show Numbers, Charges/Stacks Only (No Icon), Hide Charge Count at 0.
- **EXTRAS:**
  - Hide Items if Missing, Show Tooltip on Hover, Show Keybind.
  - Pandemic Glow Color, Show Non-On Use Trinkets.
  - Show Rotation Helper, Rotation Assist Style, Color, Color Mode, Custom
    Color, Thickness and Outset.
  - Mirror Key Presses (press flash), Bar Strata.
  - Swap Combat Potions When Missing.
  - Show Glows Only in Combat (global), Always Show Cooldown Edge.
- **Keybind text (global):** Font, Outline, Size, Anchor, X, Y, Background
  Color, Border Color, Border Size, Background Padding, Keep Keys on Bar Swap.
  There is also a CDM Font.
- **ADDITIONAL BAR OFFSET:** Offset X and Y.
- **FocusKick options** (interrupt bar): Nameplate Anchor [Offset], Focus Text
  Reminders [Size, X, Y], Focus Cast Sound, Interrupt Spell, Show on Target.
- **Per-spell menu** (right-click an icon in the preview or picker):
  - Glow style (Default, None, Pixel, Action Button, Auto-Cast, Shape, GCD,
    Modern, Classic) and glow color (default, class, custom).
  - CD Ready Glow (resource aware) [Suppress GCD, Hide Charge Text, Hide
    Swipe, Hide Recharge Edge, Hide Duration while charges > 0, Stay Hidden
    While Charges Remain].
  - Visibility state: Lower Alpha On CD; Hidden On CD, Hidden CD Ready, Hidden
    Until Usable, or Hidden Outside Form. Each has a "Shift Icons" variant
    that collapses the gap.
  - Swipe: Off, On, Reverse, Hide; swipe color or class colored; Hide Active
    State.
  - Desaturate, Keep Colored On CD, Color Out of Range, Ignore Resource Cost.
  - Duration Text [Show, Size, Color, Position, X, Y, Threshold Seconds,
    Threshold Color and Decimals].
  - Stack Text and Glows [Glow at Stacks, Comparison, Count, Show Stack Text,
    Size, Color, Position].
  - Border [Size, Color].
  - Show When Missing, Also Show Below.
  - Copy to Other Specs, Remove from Other Specs.
  - **Talent Conditions:** a popup draws the class and spec talent trees and
    cycles each node through Taken, Not Taken and cleared, so an icon shows
    only with a given build.
- **Bar Glows tab:** rules that glow an action-bar button.
  - Each rule: "When [buff] is [Active/Missing]", optional "And [buff2] is
    [state]", At Stacks [Comparison, Count], Glow Type, Glow Color, Only In
    Combat, Hero Talent filter.
  - Rules can be collapsed, duplicated and removed.
- **Tracking Bars tab** (buff and cooldown duration bars in groups):
  - GROUP SETTINGS: Grow Direction, Bar Spacing, Group Name, Auto-Add New to
    This Group, Global Group, Shift Elements If No Bars [Extra Y].
  - BAR LAYOUT: Height, Width, Vertical Orientation, Bar Texture.
  - Name Text [Custom Name, Size, Wrap, X, Y], Duration Text [Size, X, Y,
    Decimals, Decimal Threshold], Stacks Text.
  - Bar Strata, Reverse Fill and Fill Up (Buffs or Cooldowns), Charge Hash
    Lines [Line Width and Color, Partial Charge Shade, Darkness], Smooth Bars.
  - Display: Hide When Inactive, Show Icon, Opacity, Background and Fill Color,
    Show Spark, Border block.
  - EXTRAS: Stack Based Bar, Enable Max Stacks, Ticks at Stacks, Stack
    Threshold.
  - Add or Remove Bar to All Specs, Use Blizzard Bars.
- **Rotation Assist Icon tab:** Show, Icon Size, Only in Combat, Show Keybind,
  X, Y, Show GCD.

### 10.6 Resource & Cast Bars (tabs: Class/Power/Health Bars, Cast Bar, GCD Bar, Swing Timer, Totem Bar)

- **BAR DISPLAY:**
  - Smooth Bars (per bar), Dark Mode Class Resource.
  - Background [per bar], Health and Power Background.
  - Texture [Blizzard Class Resource Bar Texture], Frame Strata.
  - Border Around All [Separator Border and Color].
  - Blizzard Class Resource Art [Scale].
- **BAR SHIFTING:**
  - Expand Power Bar if No Resource [Extra Y], Shift Elements if No Resource
    or No Power, Hide Power Bar if Resource.
  - Power Type, Mana Regen Spark, Spell Cost Prediction.
  - Mana Bar while Shapeshifted [Position, Gap, Height, X, Y] and its text
    [Size, Show %, Anchor, X, Y].
  - Druid form overrides (Caster, Bear, Cat, Moonkin).
- **HEALTH BAR:**
  - Show, Orientation, Height, Width, Border block, Corner Radius, Opacity.
  - Fill Color [Gradient].
  - Max Health Reduction [Show, Texture, Color, Placement, Backing Opacity],
    absorb options [Overshield, Glow Line].
  - Out of Combat Opacity & Visibility [Fade, Opacity, Show When Health
    Missing].
  - Health Text and its Color [Anchor, X, Y], Text Size.
  - Threshold & Hash Lines [Position by percent, Hash Width, Style].
- **POWER BAR:** like the health bar, plus Draw Above GCD Bar, Extend
  Top/Bottom/Left/Right, Bottom Separator [Y], Show When Mana Missing, Power
  Text [Show %], and Threshold Coloring [color below a value].
- **CLASS RESOURCE BAR:**
  - Show, Orientation [Draw Above Other Bars], Height, Width, Border block,
    Extend edges, Separators [Horizontal and Vertical], Pip Border [border and
    background on individual pips], Bar Spacing.
  - Empty Bar Overlay, Opacity, Fill Color [Darken Partially Filled, Charged
    Color], Out of Combat Opacity.
  - Resource Text [Show %, Only if Power Bar Hidden, Hide at Zero, Size,
    Anchor, X, Y, Show Max Stacks, Stagger Full %].
  - Threshold Options [Threshold as, Direction, Only color at/above].
  - Custom Recharge Color, Simple Runes.
  - Spec specials: Show Focus as Power Bar (BM/MM), Enhance 5 Bar Style,
    Guardian Ironfur Bar [Hash Lines], Prot Warrior Ignore Pain Bar, Arms
    Sweeping Strikes Bar.
  - ARCANE SOUL (Sunfury) helper: Enable, Show Threshold, Position, countdown
    format (Seconds, GCD Count, or both), Text Size, Font, Outline, Colors.
- **Cast Bar tab:**
  - LAYOUT: Enable Player Cast Bar, Frame Strata, Height, Width, Show Spell
    Icon [Embed in Player Portrait, Icon on Right, Show Icon Divider, Border
    Art Divider], Show Spark, Always Show, Smooth Bar Animation.
  - DISPLAY: Border block with extends and separator, Fill Color [Gradient,
    Gray When Out of Range, Channel Color Override, Uninterruptible Color
    Override], Background, Bar Texture, Spell Text [Size, X, Y], Duration Text
    and Show Total Duration [Size, X, Y], Show Spell Rank.
  - TICK MARKERS: Enable, Channel Ticks, Last Tick, Colored Empowered Stages.
  - LATENCY: Enable Latency Overlay, Show Latency Text.
- **GCD Bar tab:** Enable, Strata, Position [X, Y], Height, Width,
  Orientation, Instance Only, Only Instant Casts, Always Show [Show Fill When
  Idle], Border block, Color, Background [Gradient], Texture, Spark, Deplete
  Fill.
- **Swing Timer tab:**
  - Enable, Strata, Position, Row Height, Width, Row Spacing, Text Size and
    Position, Hide When Idle [Show Fill When Idle].
  - Border block, Corner Radius, Color, Background, Texture, Deplete Fill.
  - Spark [Width, Overhang, Colors per hand].
  - Tracked Weapons (Main Hand, Off Hand, Ranged) [Always Show Rows, Hide
    Label Without Weapon, Shield As Off Hand, Combine Hands].
  - Show Time, Show Weapon Label.
  - Range Check [Out of Range Opacity], Attack State colors [Queued On Main
    Hand Only], Movement Guide [Text Cue].
- **Totem Bar tab:** Icon Size [Spacing], Timer Size, Show Timer, Border
  block, Strata, Orientation, Enabled Classes, Enable Call Totem Bar.
- **POSITIONING:** Unlock Elements. **RESET:** Reset Positions.

### 10.7 Mythic+ Tools (tabs: Mythic+ Timer, Kick Tracker, Targeted Spell Bars, Target/Focus Bars, Run Summary)

- **Timer DISPLAY:** Enable, Text Align, Scale, Background Opacity, Frame
  Width, Bar Width, Border block [Apply to Forces Bar].
- **TITLE AND AFFIXES:** Show Title, Title Size [Dungeon Name, Key Level,
  Spacing], Show Affix, Title/Affix Position, Affix Size, spacing gaps
  (Death, Timer, Bar).
- **TIMER:** Size, Format, Font.
- **TIMER BAR:** Show, Move Timer Inside Bar [In-Bar Height, Fill Opacity,
  Left Text], Height, Texture, Background Texture, the +2/+3 chest text
  [White Text, Size, X, Y].
- **THRESHOLDS:** Ticks/Gaps [Tick Opacity, Gap Size].
- **FORCES:** Show Enemy Forces, Bar Height, Enemy Text Format, Percent
  Position [Hide Label, Size, X, Y], Forces Position, Textures, Show Current
  Pull in Bar, Current Pull Color.
- **BOSS OBJECTIVES:** Show, Size, Position [X, Y], Show Objective Times, Time
  Position, Spacing, Split Compare [Always Show Splits, Strict Comparison,
  Fastest Run Splits].
- **Targeted Spell Bars** (casts targeting you or the party) and
  **Target/Focus Bars:**
  - Enable, Where to Show, Grow Direction, Width, Height, Spacing, Max Bars,
    Texture, Background, Border Size.
  - Show Icon [Icon on Right, Divider], Spell Name, Cast Timer and Spell
    Target, each [Size, X, Y], with target class colors or a custom color.
  - Cast Colors [Important Cast Color], Fade Out of Interrupt Range
    [Opacity], Raid Target Marker [Size].
  - Kick Ready Mid-Cast Hint [Bar and Tick Color], Interrupted Flash [Color],
    Important Cast Glow.
- **Kick Tracker:**
  - Enable, Where to Show, Focus Announce, Edit Announce Text.
  - NAMEPLATE ICON: Show on Nameplates, Icon, Size, Position, Offsets,
    Cooldown Timer [Position, Size, X, Y], Icon Effects [Cooldown Swipe, Class
    Color Border, Desaturate on CD], Show Above Overlapping Nameplates.
  - BARS: Show, Width, Height, Spacing, Grow, Texture, Background, Border,
    Display Elements (Icon, Name, Timer, Marker) [Icon on Right, Text Size],
    Include Yourself.
- **Run Summary:**
  - Enable, Show After Looting, History Size, Panel Scale, Text Size, Clear Run
    History.
  - COLUMNS: Spec Icons, Item Level, M+ Score, Loot, DPS, Damage Taken,
    Interrupts, Deaths.

### 10.8 Damage Meters (tabs: Damage Meters, Spell History)

- **DISPLAY:**
  - Refresh Rate [an unsafe fast rate].
  - Window Border block [Include Headerbar].
  - Background Texture and Opacity.
  - Always Show Player [Show Player Marker].
  - Reset Data Keybind [Hide Reset Button].
- **HEADER:** Height, Opacity, Bottom Border [Separator], Icon Size [Mouseover
  Icons], Text Size, Title Position.
- **BARS:**
  - Bar Texture, Height, Color (class or custom), Opacity, Spacing.
  - Icon Style [Zoom, Separator].
  - Bar Border block [Custom Icon Border, Border Follows Bar, Separators,
    Include Icon], Icon Border.
  - Show Breakdown on Hover [Texture, Scale, Anchor, Show More Spells],
    Background.
- **BAR TEXT:** Number Format, Hide Rank Numbers, Left and Right Text Size
  [X, Y], Force English Units.
- **STANDALONE COMBAT TIMER:**
  - Enable, Text Color.
  - Settings cog: Font, Size, Outline, Align, Decimal, Frame W and H,
    Background, Border Color and Size, Strata.
  - Show Out of Combat [Desaturate], Anchor to Windows, Shift-click Free Move,
    Lock Position.
- **EXTRAS:** Spell Tooltips on Hover, Show/Hide Windows Keybind [Scope:
  timer, spell history].
- **Spell History tab:**
  - ICON HISTORY: Enable, Free Move, hide-in lists (Dungeons, Raids, Delves,
    PvP, Outside), Grow, Icon Size, Max Icons, Zoom, Spacing, Opacity,
    Animation Style, Fade-Out Time.
  - BAR HISTORY: Enable, the same visibility options, Background Opacity, Hide
    Top Bar, Bar Height, Max Bars, Texture, Text Size, Color, Opacity.

### 10.9 AuraBuff Reminders (tabs: Auras/Buffs & Consumables, Talent Reminders)

- **Global:**
  - Enable, Scale, Grow Direction, Icon Spacing, Frame Strata, Layout [Y].
  - Border block.
  - Show Name [Font, Size, Anchor, X, Y], Show Item Count [Font, Size, X, Y].
  - Attach Important Buffs to Cursor [Only on Cursor in Combat].
  - Show Below, Show Below Pre-Key, Show Tooltips, Opacity.
  - Beacon M+ Reminders.
- **Per reminder group:**
  - "Show When" content filter: Open World, Mythic, Heroic and Normal/LFR
    Raid, Mythic and Non-Mythic Dungeons, Timewalking, Delve, Lair, Scenario,
    In Combat.
  - Where to Show (Others are missing my buff / I am missing others' buffs),
    Reminder Sound, Reminder Glow.
  - Custom spell groups: New Spell Group, Add Spell ID, Rename, Remove.
- **Categories:**
  - Raid buffs.
  - Camp Benefits.
  - Gathering Tracking [ignore if class tracking is active].
  - PETS: Missing Pet, Passive Pet, Allowed Demons, Wrong Demon.
  - Consumables: Flask, Food, Weapon Enhancement (each with "Preferred (click
    to buff)"), Augment Rune, Healthstone.
  - Inky Black Potion [zone ID list, Add Current Zone], Show Without Item in
    Bags.
  - Ready Check Mana Warning [Font, Size, X, Y].
  - Rogue Poisons, Paladin Rites, Shaman Imbues & Shields.
- **Talent Reminders:** reminders to swap talents per instance or zone.

### 10.10 Quality of Life (tabs: QoL, Raid Tools, Cursor, Shifter, MoveAlert, Upgrader)

- **GENERAL:**
  - Hide toggles: Party Panel (Sidebar), Talking Head (and its audio),
    Tutorial Popups, Error Messages, Group Loot Rolls Window [Mode, Close
    After], Top Screen Banners, Lua Errors.
  - Skip Cinematics [Auto Skip].
  - Quick Loot, Auto-Fill Delete Confirmation.
  - Auto Repair [Guild Funds, Coin Icons], Auto Sell Junk.
  - Hide Item Transforms.
  - Auto Select Single Gossip [Hold Shift to Skip, Disable in Instances,
    Ignore Low Level].
  - /cd opens the Blizzard CDM.
  - AH Current Expansion Only.
- **SELF COMBAT TEXT:** Enable, Size [Scroll Distance, Duration, Crit Scale,
  Stagger Hits], Font.
- **EXTRAS:**
  - FPS Counter [Attach to Secondary Stats, Size, Local and World MS, Hide
    Labels, Interval] with a Toggle Keybind.
  - Low Durability Warning [Size, Y, Repair %].
  - Disable Right Click on Enemies and on Allies in Combat.
  - Secondary Stat Display [Colored Values, Abbreviate, Scale, Choose Stats,
    Reorder, Raw Rating, % and Raw, Tertiary Label Color].
  - Guild Chat Privacy Cover.
  - Rested Indicator [X, Y].
  - Target Distance Text [Format, Align, Size, Strata].
  - Environment Ping.
  - Map Coordinates [Size].
  - Auto-Accept Resurrection [include combat res].
  - Transparent World Map Sidebars [Opacity].
- **CROSSHAIR:** Character Crosshair, Visibility (Always, Combat, Instances),
  H and V Length and Width, Border and its Color, X, Y, Strata, Melee Range
  for Holy Paladin, Color Out of Range.
- **GROUP FINDER:** Auto Insert Keystone, Announce Instance Reset, Quick
  Signup, Persistent Signup Note.
- **UI:** Hide Screenshot Status, Train All Button, Auto Unwrap Collections,
  Auto Open Containers [Exclude Warbound, Hold Capped Artisan Payouts].
- **Alerts:** Combat Alert [Show On, Size, Enter and Leave Text, Color and
  Class Color], Potion Ready Alert, Unspent Talents Alert, Announce Group
  Deaths [Size, Sound].
- **Battle Res and Bloodlust trackers:** Enable, Icon Size, Shape, Border
  Color, Zoom, Duration and Count Size, X, Y, Display Style, Text, Font and
  Outline. Bloodlust also has Show when Sated, Show with Ready Text, and Ready
  Size.
- **Keystone /keys popup:** Size and Window Scale. **LFG Reminder.** **/way
  command** [Hand-Placed Pin Arrival].
- **Auto Combat Logging:** triggers per content type (Mythic, Heroic and
  Normal Raid, LFR, M+, Arena, Scenarios) and Warcraft Recorder
  compatibility.
- **Raid Tools tab:**
  - GENERAL: Show, Toggle keybind, Default Collapsed, Show as, Window Scale,
    Menu Grow.
  - QUICK FIRE: world marker keybinds (Place, Undo Last, Clear All).
  - GROUP BUTTONS: Show Buff Check.
  - RAID BUFF CHECK: Open on Ready Check.
  - PULL TIMER.
- **Cursor tab:**
  - Cursor Circle: Color, Texture, Scale, Opacity, Cursor Trail, Only in
    Instances, Only When Hidden, Combat Only, Center Reticle.
  - GCD Circle: Color, Ring Texture, Scale, Opacity, Attach to Cursor,
    Instance and Combat only.
  - Cast Bar Circle: the same plus Show Spark.
- **Shifter tab:** drag Blizzard windows to new positions. Enable, Reset
  Specific Window, Reset All, Move Without Shift. Loot windows, the top bar
  event text and battleground frames can move in Unlock Mode, each with an
  option to hide its overlays.
- **MoveAlert tab:**
  - Movement cooldown alert: Enable, Combat Only, Display Mode (bar, icon or
    text), Bar Texture [Icon, Duration], Size [Text, Icon, Decimal], Sound,
    TTS Voice and Volume.
  - TRACKED SPELLS list.
  - Extra tracking: Time Spiral and Gateway Shard, each with text format,
    color, sound and TTS.
- **Upgrader tab** (crest upgrade calculator):
  - Open with Character Sheet, Window Scale, Show Fully-Upgraded, Hide
    Crafted.
  - Slot Groups (Armour, Jewelry, Trinkets, Weapons), Crest Rows (Adventurer
    to Myth), Earned/Cap and Still Available columns.
  - Calc Button on Character Sheet, Open with Crest Upgrader.
  - Enhanced Upgrade Tooltips.

### 10.11 Blizzard Skins+ (tabs: Window Skins, Window Mover, Tooltips/Menus & Popups, Chat Bubbles, Dragon Riding)

- **Window Skins:** one toggle per Blizzard window: Character Sheet, Progress
  Legacy, Great Vault, Adventure Guide, Collections, Talents & Spellbook,
  Professions and Crafting, Map & Quest Log, Guild & Communities, Calendar,
  Achievements, Mail, Catalyst, Gem Socketing, Item Upgrades, Loot Window,
  Loot Toasts, Friend Notifications, Loot Roll Popups and Window, Group
  Invite, Ready Check, Housing Dashboard, Micro Menu, Bag Bar, Dressing Room,
  Transmogrifier, Merchant, Auction House, Macros, Options Panel, AddOn List,
  Crafting Orders, Trainer, Gossip, Quest, Inspect Recipe, Delves Companion,
  Friends List, Queue Status, Delve Tier Picker, Choice Windows, Trade, and
  Flag Carriers. Most changes need a reload.
- **GLOBAL OPTIONS:** Show Accent Bar, Bar Fill Opacity, Link Color. Skin
  Third-Party Addons.
- **Character sheet extras:**
  - Item Level, Upgrade Track, Stat Letters, Tertiary, Gems.
  - Mythic+ Rating, Item Details, Socket Panel.
  - Enchants [Size], Show PvP Item Level, Durability [Location, Label].
  - Season Panel [Great Vault shortcut].
  - Stat Sections (Attributes, Secondary, Tertiary, Attack, Defense, Crests,
    PvP), Diminishing Returns, Secondary/Tertiary Text and Highlights.
  - Hide Slot Flyout Arrows.
- **Inspect Sheet:** enable, plus Enchants, Item Level and Upgrade Track.
- **Other window extras:**
  - Merchant: Show As List [Row Height, Item Level], Bulk Buy.
  - Loot toasts: Quality Strip, Gold Toast Strip, Toast Scale.
  - Alt List [Sort, Max, Minimum Level].
  - Remember Sign-Up Roles, Class Icon Theme, Auto-Accept Friend Invites.
- **BLIZZARD POPUPS & GAME MENU:** Reskin, Resurrect Accept Glow, Border
  Style, Button Border and Background, Element & Text Color, Font Size Scale,
  Enable Blizzard Pause Menu.
- **BLIZZARD TOOLTIP:**
  - Reskin, Show Tooltips [Peek Modifier].
  - Anchor to Cursor [Position, X, Y], Growth Direction.
  - Tooltip Extras: Player Titles, Item Level, M+ Score, Mount, Guild Rank,
    Unit Target, Detailed Tooltips.
  - Spell ID [Use Modifier, Icon ID, Item ID].
  - Show Max Stack, Item Stacks [Modifier].
  - Show Player Buffs [Position, Icon Size, Per Row, X, Y].
  - Health Strip [Texture, Height], Background, Border Style.
- **BLIZZARD BARS, POPUPS & BUTTONS:** Reskin Widget Bars [Minimum Size],
  Reskin Extra Action Buttons, Reskin Queue Popup, Show Queue Timer [Style,
  Size, Bar Height, Y], Icon Zoom.
- **Chat Bubbles:**
  - DISPLAY: Channels (Say, Yell, Party, Raid, NPCs, Emotes), Hide in
    Instances.
  - APPEARANCE: Padding, Max Width, Font [Size, Outline, Blizzard Color],
    Border, Show Speaker Name [Anchor, Size, X, Y], Vertical Offset,
    Background.
- **Dragon Riding** (skyriding HUD):
  - GENERAL: Enable, Hide in Combat, Speed Bar, Second Wind, Whirling Surge
    [Auto Size, Icon Size], Icon Cooldown Text, Vigor Style [Gem Scale, Sound
    on Full Charge], Stack Spacing, Width, Element Spacing, Border Size,
    Texture.
  - LAYOUT: Charge Height and Color, Background, Second Wind Height and Color.
  - SPEED BAR: Height, Thrill Color Change, Speed and Thrill Colors, Hash,
    Speed Text [Align, Size, Offset].
- **Window Mover:** links to the QoL Shifter.

### 10.12 Chat

- **DISPLAY:** Lock Main Chat Size, Background Opacity and Texture, Font
  (reload) and Size, Outline Mode, Border block.
- **IDLE FADE:** Enable, Fade Delay, Fade Strength.
- **SIDEBAR:** Visibility (Always, Mouseover, Never) [Scroll to Bottom], Hide
  Sidebar Background, Show on Right, Width, Separate Sidebar [Spacing].
- **ICONS:** Sidebar Icons and their Color and Size, Free Move Icons
  [Spacing], Scroll Button on Chat Panel.
- **Tabs:**
  - LAYOUT: Tabs Inside Chat Panel, Spacing, Height, Inner Padding X.
  - TYPOGRAPHY: Tab Font, Size, Color, Active Color.
  - APPEARANCE: background colors (normal and active) [Opacity], Active
    Underline, Tab Texture.
  - BORDER: Sync Border with Chat Panel, Style, Size [Shift], Active Tab
    Border.
- **INPUT FIELD:** Edit Box Height, Input on Top, Edit Box Font and Size.
- **EXTRAS:**
  - Remember Last Chat Lines [Session History, Max Lines].
  - Hide Tooltip on Hover, Hide Borders.
  - Whisper Sound.
  - Timestamps (about 7 formats), Timestamp All Messages.
  - Shortened Channel Names [Use Letters], Class Colored Names.

### 10.13 Bags (tabs: Bags, Bank)

- **LAYOUT:**
  - Bag Style (OneBag, MultiBag, list; reload), Default Selected Bag.
  - Window Scale, Strata.
  - Slot Size and Spacing, Auto-Size to Fit.
  - Background Color and Opacity, Slot Background.
- **DISPLAY:** Bank Display. **GROUPING:** Nest by Expansion, Group by
  Category.
- **SIDEBAR:** Category Sidebar, Hide Bank Tabs, Hide Empty Slots When
  Grouped.
- **OFFLINE BANK:** enable, Tooltip Item Counts.
- **CATEGORIES:**
  - Pinned Items [Show in OneBag, Hide from Others] and Recent Items [Clear
    Button].
  - Enabled Categories, Hide Empty, Hide "Add Category" Tab.
  - Split Set Gear by Set, Category Title Size, Hide Sidebar Icons When
    Collapsed.
- **DISPLAY (GRID / COMPACT):** Item Level [Size, Gear Track Rank], BoE /
  Warbound Text [Size], Item Count Size, Set Name on Gear [Size].
- **DISPLAY (LIST):** Left and Right Gap, Row Height, Text Size, Round Icons,
  Section Gold Value, Split by Type (Armor, Weapons, Professions), Hide Row
  Stripes.
- **EXTRAS:**
  - Merge Duplicate Items.
  - Group Gear by Slot [Compact].
  - Junk Item Visuals [Desaturate, Coin Icon], Quality Item Border.
  - Top Bar Icons (Bags, Junk, Quick Actions, Sort) and Sort Options [Sort to
    Bottom].
  - Enabled Currencies, Gold Tracking and History.
  - Icon Zoom, Stack Splitter, Open Bags with Character Window.

### 10.14 Quest Tracker

- **DISPLAY:** Hide in Raid, Background Opacity, Top Line, Header, Title and
  Objective Font Size, Font (reload), Quest Icons, Hide All Objectives.
- **COLORS:** Focused, Header and Line Color, Color Objectives by Progress
  [Progress Colors], Dim Completed [Opacity].
- **TRACKING:** Experimental Quest Tools, Announce Progress, Objective and
  Quest Complete Sounds, Sort Quests [Completed, Then By], Filter Quests, Auto
  Track Zone Quests.
- **EXTRAS:**
  - Auto Accept [Prevent Multi, Hold Shift to Enable or Skip, Ignore Low
    Level and Old Expansion].
  - Auto Turn In (same options).
  - Wowhead Quest Links [Client Language, Jump to Comments].

### 10.15 Minimap

- **Shape and frame:** Border Style (reload), Shape, Opacity, Size,
  Interactable Button Size, Minimap Icons [Size], Border block, Reset Zoom,
  Rotate, Scroll to Zoom.
- **MINIMAP & QOL BUTTONS:**
  - Ungroup Minimap Buttons, In-Group Button Size.
  - Show Extra Buttons, Mouseover Extra Buttons [Group Button], M+ Portals
    Scale.
  - Middle Click opens the Micro Menu.
  - Friends Tooltip and its Cap [Show Notes], Custom Tooltip Size.
  - Button Row Position, Free Move [Spacing, Distance, Grow Tooltip],
    Button Backgrounds.
- **BLIZZARD ELEMENTS:**
  - Omnium Folio and Addon Compartment, each with show, Scale and Position
    [Corner, X, Y].
  - Show elements (Calendar, Mail, Tracking, Crafting Order, Difficulty, Zoom
    buttons).
  - Element Row Position and Spacing, Mail Position.
- **TEXT:** Clock, Zone Text [Sub Zone, Reactive Coloring], Coordinates
  [Precision], FPS/MS [Size, Local and World MS, Interval], and Instance
  Difficulty as Text. Each has a Style or Position and a [Scale, X, Y] cog.
  Hover reveals (show on FPS or clock hover) and Accented Text.

### 10.16 Friends List

Class Icon Theme, Class Color Names, Border Size and Color, Accent Colors,
Faction Banners, Region Icons, Auto-Accept Friend Invites [from guildmates].

### 10.17 Group Finder (Premade Search)

Enable, Show Spec Icons, Show Applications [Counts: Accepted, Declined,
Delisted, Cancelled], Bar Texture, Reset Application Counts.

### 10.18 DataBars

Configurable info bars made of "blocks".

- **Bars:** create, rename and delete bars, with templates: Start Empty,
  Top/Bottom Info Bar, Minimap Companion, Micro Menu Strip.
- **BAR SETTINGS:**
  - Hide Border, Strata, Orientation.
  - Background Style [Backdrop Dim], Texture, Opacity.
  - Text Scale, Hover Highlight Blocks.
  - Snap to Screen Edge.
  - Block sizing: Auto Sized or Even Split, a "Fill Remaining Space" block,
    Force Centered.
- **Per-block settings:** Enable Text, Align, Content Scale, Text and Content
  Position, Text Color, Block Background, Icon Color, Show Icon, Prefix,
  Width and Max Width, Decimals, Show Tooltip Data, Separator, Order.
- **Block types:**
  - Gold [Silver and Copper, Tracking and History, Session, Characters, WoW
    Token].
  - Clock [Local Time, 24h].
  - Latency.
  - Volume [Audio Channel].
  - Currency, Crests Shown.
  - Durability and bag space [Low Space Warning].
  - Item Level.
  - M+ portals.
  - Micro menu elements (Character, Spellbook, Talents, Achievements, Quests,
    Guild, Social, Group Finder, PvP, Collections, Adventure Journal, Housing,
    Shop, Help, Professions, Legacy).
  - LDB plugin blocks.

### 10.19 Quickdraw (radial and grid action menus)

- **GENERAL:** Enable, Add, Rename and Delete Action Menu.
- **ACTION MENU SETUP:** Editing Action Menu, Keybind, Toggled Menu Select
  Action, Toggle Menu Open, Menu Cancel Action.
- **Content sources:** Spells, Mounts, Items, Toys, Macros, Battle Pets,
  Outfits, Target and World Markers, Pings, Specializations, Professions,
  Interface Panels, Hearthstones, Teleports, Potions, Druid Forms, Stances,
  Quest Items, Custom Macro, and nested menus.
- **LAYOUT:**
  - Layout (grid, arc, fan), Open At (cursor or fixed [X, Y]).
  - Auto Columns and Grid Columns.
  - Distance from Center, Arc Span and Rotation, Fan Direction [Select with
    Mouse, Spacing, Invert Scroll].
  - Visible Icons, Nest Distance and Icon Size [Nest Width, Max Span, Grid
    Nest Style].
  - Icon Size, Scale.
- **APPEARANCE:** Show Cooldowns, Dim Unusable, Selection Color, Action Text
  Label, Hide Unavailable, World Marker entries [Placed-Marker Pips].

### 10.20 Loadout Manager

- **GENERAL:** Enable, Auto-Swap of Gear Sets and Talent Loadouts [Queue In
  Combat, Re-Swap On Spec Change], Talent-Change Warning, Announce Swaps.
- **CURRENT LOCATION:** Location, Specialization, Gear Here, Talents Here.
- **SELECTED LOADOUT:** Gear Set [Verify Assigned Sets], Talent Loadout,
  Assign For, Equip Selection.
- **INSTANCES:** Any Difficulty or This Difficulty, Saved Instances,
  Assignment.
- **CONTENT TYPE DEFAULTS.**

### 10.21 Party Mode (tabs: Party Mode, Should I Raid Tonight?, AFK)

- A novelty module: Dim the Lights (Action Bars, Data, Unit, Resource, Power,
  Party and Raid frames), Spinning [Speed], Play Sound.
- CELEBRATION TRIGGERS: Randomly, Bloodlust, Level Up, Timed Keystone, boss
  kills by difficulty, Rated Arena and BG Win, M0 Completion, Duration,
  Minimum Cooldown.
- AFK SCREEN: bouncing logo, speed, spin, size, corner-hit party.
- Horoscope page.

### 10.22 Simple Loot Council

A single "General" page that is mostly inert. Its UI lives in the module.

### 10.23 Forever Essentials (WoW Forever client only; not relevant to retail parity)

Tabs: General (spell ranks, world map, classic windows, simplified stats,
companion pets, stance/form icon, gathering, junk items, fishing), Travel
(flight timer), Threat (threat meter), Loot (loot feed), and Macros (a macro
builder with a full condition and target vocabulary).

---

## 11. Plugin API (third-party pages)

- `EllesmereUI.RegisterPlugin(id, spec)`:
  - `spec`: `label` (the sidebar section header), `position` ("bottom" or
    "top"), and `modules` (1 to 20).
  - Each module: `key`, `title`, `description`, `pages` (1 to 20),
    `buildPage`, and optionally `getHeaderBuilder`, `onPageCacheRestore`,
    `onReset`, `onModuleLeave` and `searchPrebuild`.
  - The registration is copied as a snapshot.
  - Rules: one section per plugin; it cannot modify suite sections; reserved
    labels are refused; labels are plain text only.
  - Every callback runs protected (pcall). A failing page shows empty, and the
    error goes to the error handler.
  - Violations produce a once-per-session popup that names the offending
    addon.
- `OpenPlugin(id, moduleKey?, pageName?)`, `GetPluginModuleKey`,
  `IsPluginRegistered`, `IsSearchPrebuild`, plus CDM helpers. The API version
  is currently 3. The API only ever grows.
- Plugin pages are searchable for free if built with `EllesmereUI.Widgets`.
  They do **not** take part in profiles, sync or overrides.

---

## 12. Observations: what works well and what to avoid

**Worth emulating**
- A declarative slot config (`{type, text, get, set, disabled,
  disabledTooltip}`) plus a few row containers (single, dual, triple) gives a
  very dense, consistent layout from compact builder code.
- Cogs keep pages short: primary knobs stay on the row, offsets and fine
  tuning go in the cog.
- Refresh closures give live disabled-state propagation without a reactive
  framework.
- Selector plus multi-edit plus "apply to all" lets one page edit eight bars
  or six units.
- The standard "This option requires X" disabled tooltip.
- Search that indexes itself from the same widget calls, plus the stub-factory
  pre-build.
- Clickable live previews that jump to the matching setting.
- A LoadOnDemand options addon, deferred init, and a split first open.
- Never opening in combat, and closing the panel when combat starts.

**Complexity to avoid or simplify**
- The page frame pool is a large, subtle system (about 2,300 lines) that
  exists because the pages were written as "create everything every build".
  Instead, design widgets to be **re-bindable** (row objects with
  `:Bind(cfg)`) and recycle rows per page from the start.
- Many pages bypass `parent` and build onto the shared scroll frame
  (Profiles, Buff and Debuff Manager, HoverCast, Player Aura Bars). That
  forced a lot of special-case cleanup. Keep every page inside its own root.
- Setter wrapping for override capture plus ticker diffing of profiles is
  powerful but fragile. If we add spec overrides, put the override layer in
  the **DB accessor** (path-based get and set), not in the widgets.
- File-scope local and upvalue limits (Lua 5.1's 200 locals and 60 upvalues)
  pushed EUI into "pack constants into tables". Plan for this from the start.

---

## Recommendations for SoulUI editor

1. **Shell:**
   - Build `SoulUI_Options` as a LoadOnDemand addon. The core owns the window,
     registry, slash commands (`/soul`, `/soul move`) and the minimap or
     compartment entry.
   - Split the first open across two frames.
   - Refuse to open in combat, auto-close on `PLAYER_REGEN_DISABLED`, and
     print one short message.
   - Layout: a sidebar of about 260 to 300 wide with collapsible groups (Core,
     Combat, Utility, UI Skins); a header with title and description; a tab
     bar with inline page search; an optional fixed preview header; a smooth
     pixel-snapped scroll area; and a footer with Reset Module, Reload UI and
     Close.
   - Pixel-perfect base scale times a user Window Scale.
2. **Module contract:**
   - `SoulUI:RegisterOptions(key, { title, description, pages, build(page,
     ctx), header(page, frame, w), onShow, onLeave, onReset, searchTerms })`.
   - The build callback receives a `ctx` with `W` (widgets), `db` accessors
     and `refresh()`. Each options file guards on its module being loaded.
3. **Widget API:** keep EUI's proven shape but write it ourselves.
   - Row containers `Row`, `Row2` and `Row3` take slot specs
     `{type, label, get, set, min, max, step, values, order, tooltip,
     disabled, requires}`.
   - Types: toggle, slider (with numeric input and a pixel mode), dropdown
     (with font and texture preview items via LibSharedMedia, dividers and
     action entries), color (our own picker with hex, alpha, recent colors and
     a class-color option), input, button, keybind, label, multiColor,
     checklist (multi-select), segmented.
   - `Header(text)` restarts row striping.
   - Inline add-ons: `cog(rows)`, `inlineToggle`, `swatches`, `unlockJump`,
     `syncAll`.
   - Every widget returns a row object with `:Refresh()`, which goes into a
     page-level refresh list.
4. **Dependencies:**
   - Use `disabled = fn` plus a `requires = "Show Cast Bar"` string, rendered
     as a standard sentence.
   - Fast refresh (re-run all row refreshers) after every set.
   - Structural changes go through `ctx.rebuild()`, which keeps the scroll
     position.
   - Add a `visibleIf = fn` that hides rows, with automatic rebuild only when
     the predicate flips.
5. **Live apply:**
   - Each module exposes `Module:ApplySettings(scope)`, where scope is
     "layout", "colors", "text" or "all", and `Module:UpdatePreview()`.
   - Setters write through a DB path accessor and then call these. No Apply
     buttons except for reload-gated keys, which go through a "Reload
     Required" confirm that writes only on confirm.
   - Respect combat: queue protected changes with `SoulUI:RunAfterCombat`.
6. **Previews:**
   - Build a mock-frame preview in the fixed header for Unit Frames,
     Nameplates, Action Bars, CDM and Raid Frames, driven by the same style
     functions as the real frames, so there is one renderer and two data
     sources.
   - Make preview regions clickable, so a click jumps to the setting and
     glows it.
   - Remember Midnight secret values: previews use fake plain numbers, never
     live combat values.
7. **Selectors and multi-edit:**
   - A `WideDropdown` or segmented selector for unit, bar or size bracket. Set
     the page context `ctx.target` from it.
   - Multi-select fans out writes.
   - A per-row "apply to all" sync icon with a target checklist popup.
8. **Search:**
   - Index rows from the widget calls (label, tooltip, section, module,
     page).
   - Run a frameless pre-build with a stub widget factory on first search.
   - Ranked tiers (exact, then stem, then fuzzy subsequence with a density
     cap), module-name scoping, a synonym table.
   - Results jump with a highlight.
9. **Profiles page:**
   - New, Copy, Rename and Delete; spec auto-assign.
   - Export with per-module selection as a prefixed string, using LibDeflate
     (allowed under its own license) plus our own serializer.
   - Import with a per-module checklist, validation, and a UI-scale mismatch
     warning.
   - Defer spec and conditional overrides to a later phase. If we build them,
     implement them at the DB accessor layer.
10. **Onboarding:**
    - A first-run popup that picks modules (one column per group, Reload UI
      to finish).
    - Optionally a style choice with miniature look cards.
    - Patch notes with a version-change dot.
11. **Visual identity:**
    - Choose our own accent (not teal #0CD29D) and our own font (a licensed
      or open font, not Expressway). Use dark warm-neutral surfaces with
      white-plus-alpha greys, an accent-color registry for live theme changes,
      50px rows with alternating stripes, 45px page padding, and 12px dim
      uppercase section headers.
12. **Parity planning:**
    - Treat section 10 as the checklist.
    - Phase 1 core: Unit Frames, Nameplates, Action Bars, Raid Frames,
      Resource/Cast Bars, CDM.
    - Phase 2: Mythic+ Tools, Damage Meters, AuraBuff Reminders, QoL.
    - Phase 3: skins (Blizzard windows, tooltip, chat, bags, minimap, quest
      tracker, data bars).
    - Skip Forever Essentials, Party Mode and Simple Loot Council unless the
      guild asks for them.
13. **Plugin hook:** expose a small, versioned `RegisterPlugin`-style API from
    the start. It costs little and lets guild members add pages.
