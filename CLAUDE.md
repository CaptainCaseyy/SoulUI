# SoulUI — instructions for Claude (read this first, every session)

SoulUI is an original, modular World of Warcraft **retail** UI addon suite for the SoulBound
guild/community. Target client: **12.1.5 (Interface 120105)**, Midnight era. The owner works on it
from two machines (laptop + home PC) by pulling this repo, so **this repo is the only shared memory**.

## Before you change anything
1. Read `docs/BUILD_LOG.md` top to bottom (newest entries at the top). It records what was built,
   why, and what was tested. Do not redo or "simplify away" decisions recorded there without
   reading their reason.
2. Read `docs/ARCHITECTURE.md` — the module layout, data flow, DB schema, and conventions.
3. Skim `docs/research/` for the subsystem you are touching (Midnight API rules, EllesmereUI
   study notes, other addons). `docs/research/midnight-api.md` is the authority on what the
   12.x client allows (secret values etc.).
4. `git pull` before starting; the other machine may have pushed.

## After you change anything
- Add a dated entry at the TOP of `docs/BUILD_LOG.md`: what changed, why, files touched,
  what is untested/known-broken, and which machine. Keep entries factual and short.
- If you change architecture, DB schema, or a convention, update `docs/ARCHITECTURE.md` too.
- Bump `## Version` in every changed addon's `.toc` when shipping a test build, and note it in the log.
- Commit with a descriptive message and push so the other machine can pick it up.

## Hard rules
- **No copied code.** EllesmereUI (and several other studied addons) are "all rights reserved".
  We study their designs and write our own code. Embedded third-party libs (LibStub,
  CallbackHandler, LibSharedMedia, LibDeflate…) are allowed under their own licenses — keep
  their license files.
- **Secret values (12.x):** combat numbers (health, power, auras, cast times, damage meter
  amounts…) may be secret. Tainted code may store them, pass them, concatenate them, and format
  them (`string.format`, `..`, `AbbreviateNumbers`, `SetFormattedText`). It may not do arithmetic,
  compare them (`==`, `<`, …), truth-test a secret boolean, take `#`, call `tostring`, or use them
  as table keys. Pass them straight into widget APIs that accept secrets (`StatusBar:SetValue`,
  `SetMinMaxValues`, `SetTimerDuration`, `SetAlphaFromBoolean`, `Cooldown:SetCooldownFromDurationObject`,
  font strings, curves, duration objects). Guard with `issecretvalue(v)` before any comparison.
  See `docs/research/midnight-api.md`.
- **Combat lockdown:** never move/resize/show/hide protected frames in combat. Queue the change via
  `SoulUI:RunAfterCombat(fn)`.
- **Performance:** register unit events with `RegisterUnitEvent`, upvalue globals in hot files,
  throttle OnUpdate work through the core ticker, pool frames, never create tables per event.
- Everything user-visible must be configurable from the in-game editor (`/soul`) and every frame
  movable in unlock mode (`/soul move`). Defaults live in each module's `Defaults.lua`.

## Repo layout (summary — details in docs/ARCHITECTURE.md)
- `SoulUI/` core addon (framework, DB/profiles, movers, media, widgets for the editor)
- `SoulUI_<Module>/` one addon per feature module (Nameplates, UnitFrames, …)
- `SoulUI_Options/` LoadOnDemand editor pages
- `tools/` scripts (link the addons into the WoW AddOns folder, lint)
- `docs/` build log, architecture, research

## Testing in game
Run `tools/link-addons.ps1` once per machine (creates directory junctions from the WoW AddOns
folder to this repo, so edits are live after `/reload`). Default WoW path:
`C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns`.
Use `/soul debug` to toggle the debug log, and BugSack/`/console scriptErrors 1` for errors.
