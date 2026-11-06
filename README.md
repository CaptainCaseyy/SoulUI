# SoulUI

SoulBound's unit frames, nameplates, action bars, and meters for WoW retail (Interface 120105).

BigWigs, LittleWigs, and RaiderIO stay in charge of what they already do. SoulUI does not move their frames. Boss timers stay on BigWigs. RaiderIO adds its score to the normal unit tooltip.

## Install

The repo is https://github.com/CaptainCaseyy/SoulUI

1. On that page, choose Code, then Download ZIP.
2. Open the zip. Inside `SoulUI-main`, copy these folders into:

   `World of Warcraft\_retail_\Interface\AddOns`

   Copy the folders themselves, not the outer `SoulUI-main` folder:

   - `SoulUI`
   - `SoulUI_ActionBars`
   - `SoulUI_DamageMeters`
   - `SoulUI_GroupFrames`
   - `SoulUI_Nameplates`
   - `SoulUI_Options`
   - `SoulUI_ResourceBars`
   - `SoulUI_UnitFrames`

3. In the addon list, enable every SoulUI addon. If EllesmereUI is installed, disable it. Both draw the same frames.
4. Leave BigWigs, LittleWigs, and RaiderIO enabled.
5. `/reload`

`/soul` opens settings. `/soul move` moves and scales frames.

## What stays with the other addons

- BigWigs and LittleWigs draw their own bars, messages, and sounds.
- RaiderIO draws its score on the game tooltip when you mouse over a unit frame, a party frame, or a raid frame. Party and raid have a Unit tooltip toggle if you want that off.
