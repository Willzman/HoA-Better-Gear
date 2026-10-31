# HoA Tier Glow

A small addon for **Hordes of Azeroth** that decorates the equipment slots on the character frame:

- **Quality glow** – an oGlow-style colored border around each equipped item, using the item's quality color (green / blue / purple / orange …).
- **Tier number** – the item's tier (the `Tier 10` shown in the top-right of the tooltip) is printed on the icon, similar to retail item-level addons. This works on equipped items and on items in the HoA bag window (which already has its own quality glow).

## Installation

1. Download the repository (Code → Download ZIP) and extract it.
2. Copy the **`HoATierGlow`** folder (the one containing `HoATierGlow.toc`) into your game's `Interface/AddOns/` directory, so you end up with `Interface/AddOns/HoATierGlow/HoATierGlow.toc`.
3. Restart the game (or log out to the character screen). If the addon shows as *out of date* in the AddOns list, tick **Load out of date AddOns**.

## Commands

| Command | Effect |
| --- | --- |
| `/hoatier` | Show help and current settings |
| `/hoatier glow` | Toggle the quality glow |
| `/hoatier tier` | Toggle the tier number |
| `/hoatier bags` | Toggle tier numbers on bag items |
| `/hoatier prefix` | Switch between `10` and `T10` |
| `/hoatier color` | Toggle quality-colored tier text (off = gold) |
| `/hoatier quality <0-5>` | Minimum quality that gets a glow (default `2` = uncommon) |
| `/hoatier anchor <point>` | Tier text position: `TOPLEFT`, `TOP`, `TOPRIGHT`, `CENTER`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT` |
| `/hoatier size <8-24>` | Tier text font size |
| `/hoatier debug` | List the tier read for each equipped item and where it came from |
| `/hoatier reset` | Restore defaults |

Settings are saved per account in `HoATierGlowDB`.

## How it works

- The tier comes straight from the Hordes of Azeroth UI addon, using the same lookup it uses for the `Tier N` line on tooltips: `VanillaBonkUI.FoundAt("inv", slot).tier` for rolled pieces, otherwise `VanillaBonkUI.GearTier(itemId)` for set, mythic and legendary gear.
- Numbers refresh when you open the character pane or bags, change gear, move bag items, or when the game finishes sending rolled-gear data (`BONK~foundend`).
- Quality comes from `GetItemInfo`, falling back to the color in the item link.
- Written for the 1.12.1 client (Lua 5.0).
