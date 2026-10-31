# HoA Tier Glow

A small addon for **Hordes of Azeroth** that decorates the equipment slots on the character frame:

- **Quality glow** – an oGlow-style colored border around each equipped item, using the item's quality color (green / blue / purple / orange …).
- **Tier number** – the item's tier (the `Tier 10` shown in the top-right of the tooltip) is printed on the icon, similar to retail item-level addons.

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
| `/hoatier prefix` | Switch between `10` and `T10` |
| `/hoatier color` | Toggle quality-colored tier text (off = gold) |
| `/hoatier quality <0-5>` | Minimum quality that gets a glow (default `2` = uncommon) |
| `/hoatier anchor <point>` | Tier text position: `TOPLEFT`, `TOP`, `TOPRIGHT`, `CENTER`, `BOTTOMLEFT`, `BOTTOM`, `BOTTOMRIGHT` |
| `/hoatier size <8-24>` | Tier text font size |
| `/hoatier reset` | Restore defaults |

Settings are saved per account in `HoATierGlowDB`.

## How it works

- The tier is read by scanning a hidden tooltip for a line reading `Tier N`, so it works for whatever the server puts in the tooltip. If item data isn't cached yet, the addon retries every half-second while the character pane is open.
- Quality comes from `GetInventoryItemQuality` / `GetItemInfo`, falling back to the color embedded in the item link.
- The code avoids newer Lua/API features (`#`, `select`, `string.match`, `hooksecurefunc`, varargs) so it runs on the 1.12-era client as well as later ones.
