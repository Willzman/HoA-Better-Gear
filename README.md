# HoA Better Gear

An addon for **Hordes of Azeroth** that helps you pick better gear:

- **Tier numbers**: each item's tier (the `Tier 10` in the top-right of its tooltip) is printed on its icon, on the character frame and in your bags, like retail item-level addons.
- **Quality glow**: an oGlow-style colored border around equipped items on the character frame. HoA's bag window already has its own.
- **Gear comparison** (Pawn-style): every gear tooltip says how the item compares with what you have equipped, as a % upgrade or downgrade plus the difference in each stat.
- **Upgrade arrows**: bag items that would be an upgrade get a green arrow.

## Installation

1. Download the repository (Code → Download ZIP) and extract it.
2. Copy the **`HoABetterGear`** folder into your game's `Interface/AddOns/` directory, so you end up with `Interface/AddOns/HoABetterGear/HoABetterGear.toc`.
3. If you used the older **HoA Tier Glow** version, delete the `Interface/AddOns/HoATierGlow` folder.
4. Restart the game. If the addon shows as *out of date* in the AddOns list, tick **Load out of date AddOns**.

## Gear comparison

Each stat has a **weight**: how many score points one point of that stat is worth. An item's score is the sum of weight × stat. A tooltip then shows, for example:

```
Better Gear: +64.4% upgrade        vs Deadwalker Mantle
   +5.3 Armor
   +9% Power
   +10.6% Max health
   Score                           43.3  vs  26.3
```

- Rings, trinkets and one-handed weapons are compared with the **weaker** of your two equipped items, since that's the one you'd replace. An empty slot always counts as an upgrade.
- Items your class can't use get no comparison and no arrow.
- Stats are read exactly as HoA shows them, including the bonus lines on rolled items. Set bonuses aren't counted.

The default weights favor damage (Power, Haste and Crit chance at 1.0, most defensive stats at 0.5). Adjust them to your build:

```
/hbg weights                    list all weights
/hbg weight crit chance 1.5     set a weight (stat names can be shortened: crit, crit dmg, health, ...)
/hbg weight reset               back to the defaults
```

## Commands

`/bettergear` or `/hbg`. On its own, it lists everything with its current setting.

| Command | Effect |
| --- | --- |
| `/hbg compare` | Toggle the upgrade summary on tooltips |
| `/hbg diffs` | Toggle the per-stat differences and score under it |
| `/hbg arrows` | Toggle upgrade arrows on bag items |
| `/hbg weights` | List stat weights |
| `/hbg weight <stat> <number>` | Set a stat weight (`/hbg weight reset` for defaults) |
| `/hbg tier` | Toggle tier numbers |
| `/hbg bags` | Toggle tier numbers on bag items |
| `/hbg glow` | Toggle the quality glow on the character frame |
| `/hbg prefix` | Switch between `10` and `T10` |
| `/hbg color` | Toggle quality-colored tier text (off = gold) |
| `/hbg quality <0-5>` | Minimum quality that gets a glow (default `2` = uncommon) |
| `/hbg anchor <point>` | Tier text position: `TOPLEFT`, `TOP`, `TOPRIGHT`, `CENTER`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT` |
| `/hbg size <8-24>` | Tier text font size |
| `/hbg debug` | List tier, stat lines and score of each equipped item |
| `/hbg reset` | Restore default settings (keeps your stat weights) |

Settings are saved per account in `HoABetterGearDB`.

## How it works

- **Tiers** come from the HoA UI addon, using the same lookup as its tooltip: `VanillaBonkUI.FoundAt(bag, slot).tier` for rolled pieces, otherwise `VanillaBonkUI.GearTier(itemId)`.
- **Stats** come from `VanillaBonkUI.AddGearLines`, which writes the `+X% Stat` lines onto a tooltip. Hovered items are read from the game tooltip; equipped and bag items are read from a hidden one.
- Everything refreshes when you open the character pane or bags, change gear, move items, or when the game sends gear data (`BONK~...` system messages).
- Files: `Core.lua` (settings, events, commands), `Tiers.lua` (tier numbers and glow), `Compare.lua` (comparison and arrows), `UpgradeArrow.tga`.
- Written for the 1.12.1 client (Lua 5.0).
