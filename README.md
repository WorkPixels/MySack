# MySack

The last bag addon you'll ever need — one unified window for all your bags, with
automatic item categorization, search, and sorting. Built with a unified compatibility
layer supporting Classic Era, TBC, Wrath, and Modern (Retail / The War Within / WoW Forever) clients.

## Features
- **One window, all bags.** Backpack, all four bag slots, and the keyring are
  merged into a single resizable frame. Bank bags get their own matching window
  when you visit a banker.
- **TBag-style categorization (clone goal).** Built-in auto groups (Equipment,
  Consumables, etc.) + fully user-manageable custom categories. Create new
  buckets, reorder everything, hide sections. Manual assignment via Alt+Right-click
  item or drag item to a category header. Order and visibility saved in profile.
- **Auto-categorization.** Items are grouped using class IDs + profession tools +
  quality (Junk) + your overrides/customs — locale and expansion friendly.
- **Custom categories.** Alt + Right-click any item (or drag to header) to assign.
  Manage in Settings → Categories tab (New Cat, ^/v arrows, Hide/Show, delete customs).
- **Click actions** (standard + extras):
  - Left-click: pick up / drag item.
  - Ctrl + Left-click: equip or try on the item (for gear).
  - Right-click: use / consume the item.
  - Alt + Right-click: assign to a custom category.
  - Ctrl + Right-click: protect from auto-sell.
  - Shift + Right-click: pick up item (alternative).
  - Drag item to a category header: assign category.
- **Search.** Type in the search box to fade everything that doesn't match.
- **Sort.** The Sort button triggers Blizzard's bag compaction; the window's own
  category grouping keeps things tidy regardless.
- **Free-slot + gold display** built into the frame.
- **Per-character profiles.** Every character uses the shared `Default` profile
  out of the box, so settings carry across all your characters. Any character can
  switch to its own profile (e.g. for a different window position) with
  `/msk profile char`, or share a custom one by name.
- **Item level badges** on equippable gear, **new-item glow** on freshly looted
  items, and **quest-item highlighting**.
- **Merchant tools.** A Sell Junk and Repair button appear on the window at a
  vendor; both can also run automatically (with optional guild-funded repairs).
  Recipes and formulas are never auto-sold.
- **Tooltip item counts** — every item tooltip shows how many you have in bags + bank (current character) and totals per-alt across all your characters.
- **Offline/cached bank view** (TBag-like): Bank contents are remembered after leaving the banker. Open bank view any time to see the last known layout and items for the current character (counts also feed alt tooltips). Visit the bank occasionally to refresh the cache for alts.
- **Smart search.** Beyond names, search by keyword (armor, weapon, potion,
  quest, trade, gem), quality (epic, rare, uncommon), or item level (>60, 60-70).
- **Replaces the default bags** so opening your bags (B) just works.

## Slash commands
```
/msk            toggle the bag window
/msk cols <n>   items per row (4-32)
/msk size <n>   icon size (20-64)
/msk scale <n>  window scale (0.5-2.0)
/msk reset      reset window position
/msk profile        show / list profiles
/msk profile char   give this character its own profile
/msk profile shared use the shared Default profile
/msk profile <name> switch to / create a named profile
/msk bank           show bank window (cached contents when away from banker)
/msk config      open settings (includes Categories manager)
/msk help       list commands
```

## Categories (TBag-like)
Open Settings (gear or /msk config → Categories tab) to:
- Create new custom categories (type name → New Cat)
- Reorder with ^ / v (affects display order like TBag)
- Hide/show sections
- Delete customs (X)

Assign items: Alt+Right-click an item in the bag window, or drag an item onto a category header.
Hidden categories' items fall back to Miscellaneous. Order and customs are per-profile.

## Install
Copy the `MySack-Forever` folder into
`World of Warcraft\_classic_\Interface\AddOns\` (or `_classic_beta_\`, `_forever_\`, `_retail_\`, etc.)
and restart the game. Make sure it's enabled on the character select AddOns list.

## Files
- `Compat.lua` — API compatibility shim across Classic Era, TBC, Wrath, and Modern/Retail APIs
- `Categories.lua` — item classification engine
- `Core.lua` — main unified bag window, item buttons, dynamic grid layout, search, events
- `Bank.lua` — bank container integration and offline bank view
- `Features.lua` — merchant auto-sell/repair tools, new-item highlights, and cross-character tooltip tracking
- `Config.lua` — tabbed graphical settings panel and category management
- `Options.lua` — saved variables, profiles, slash commands, and bag hooks

This is an original implementation written for MySack. It is not derived from the
source of any existing addon.
