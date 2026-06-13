# Changelog

## 0.1.4

- Fix: recipe search returned no results (regression from 0.1.3's storage compaction). Search now resolves recipe names from the client spell DB instead of the removed per-character stored name. Searching e.g. "Bloom" finds "Bloomforged Greataxe" again.
- Performance: recipe rows no longer scan the entire character database to render a name (removed a dead lookup left over from the compaction).

## 0.1.3

- Performance: stored data is dramatically smaller. Full profession scans now persist only the set of known recipe IDs instead of duplicating each recipe's name/icon/category/reagents/output — all of which already live in the bundled catalog. A one-time migration compacts existing SavedVariables on load (a large guild DB shrank from ~56 MB to ~4 MB with no loss of information).
- New: `/grd errors` opens an on-demand diagnostics popup (color-coded, timestamped, selectable text) backed by an in-memory ring buffer. Errors and comms events are captured silently — no more chat spam.
- New: `/grd export` dumps the session's diagnostics as shareable plain text (pre-selected for Ctrl+C) and writes them to the `GuildRecipeDexLog` SavedVariable.
- New: uncaught Lua errors originating in this addon are captured automatically (with stack) for later review.
- Comms: decode failures now report which stage failed (`channel` / `decompress` / `deserialize`) so foreign traffic, corruption, and version mismatches are distinguishable. Added a protocol-version stamp; version-skew between peers is reported once per peer instead of on every message.

## 0.1.2

- Fix: recipe header binding badges (Warbound / Warbound-until-equipped / BoP / BoE) now render for recipes whose crafted-output item isn't baked into the catalog (~29% of recipes, e.g. the Voidlight Potion Cauldron). The output item is resolved at runtime via `C_TradeSkillUI.GetRecipeOutputItemData` when the catalog has none, so binding detection can run.
- Fix: binding classification now also recognizes Soulbound and Bind-on-Use tooltip states

## 0.1.1

- Fix: font files (Inter.ttf, GeistMono.ttf) were missing from the release package, causing a Lua error on load that prevented `/grd` from registering
- Fix: `T.Text()` now falls back to WoW built-in fonts if the bundled font file fails to load, so the addon always initializes even if Assets/Fonts is missing

## 0.1.0

- Virtual scroll for the recipe list — no frame count limit, smooth performance on "All" expansion with 2000+ recipes
- Guild-scoped crafter visibility: only guild members and eligible own alts shown; cross-realm guild members now correctly visible
- Robust sync arbitration: guild-view scans (from clicking guildies in the profession pane) never overwrite real self-scans regardless of timestamp; self-scans are immutable
- Guild-scan data now broadcasts immediately to online guildies (no manual resync needed)
- Full guild relay: any client with fresher data for any guildie pushes it proactively on HELLO exchange
- Source text for recipes syncs across guild members — first person to open a profession caches and broadcasts source texts for everyone
- Source text and source item icon shown for both learned and unlearned recipes
- `NEW_RECIPE_LEARNED` marks recipes known immediately without requiring the profession window to be open
- Recipe source scroll/book icon in SOURCE card with hover tooltip and shift-click link (5,829 recipes)
- Expansion pills correctly sized using `GetUnboundedStringWidth`
- Recrafting categories and unnamed recipes hidden from the list
- Duplicate HELLO broadcasts on login suppressed
- Guild home realm correctly read from `GetGuildInfo` (fixes cross-realm alt visibility)
- Character GUIDs stored for rename detection in roster diff
- Class icons and colors for guild-scanned characters

## 0.0.1

- Catalog-first guild profession browser: browse every recipe in every profession and see who in your guild can craft each one.
- Full UI: dark 1200×800 window with left recipe list, detail pane (reagents, optional reagents, source), and crafters column.
- Automatic sync via AceComm guild channel — clients exchange profession data on login and when you open a profession window.
- Reagent counts include bags, character bank, reagent bank, and Warband bank.
- Crafters column: class-colored names, class icons, online status, skill level, filter tabs (All / Alts / Guild / Online), click row to select whisper target, Whisper button to send tell.
- Recipe-header badges: Rare/Epic/Legendary quality, item level, BoP.
- Profession header shows total recipe count and guild-wide craftable count.
- Expansion pills for narrowing the recipe list by patch.
- Your alts are tracked and tagged separately from guild members.
- Slash commands: `/grd`, `/grd dump`, `/grd debug on|off`.

- Catalog-first guild profession browser: browse every recipe in every profession and see who in your guild can craft each one.
- Full UI: dark 1200×800 window with left recipe list, detail pane (reagents, optional reagents, source), and crafters column.
- Automatic sync via AceComm guild channel — clients exchange profession data on login and when you open a profession window.
- Reagent counts include bags, character bank, reagent bank, and Warband bank.
- Crafters column: class-colored names, class icons, online status, skill level, filter tabs (All / Alts / Guild / Online), click row to select whisper target, Whisper button to send tell.
- Recipe-header badges: Rare/Epic/Legendary quality, item level, BoP.
- Profession header shows total recipe count and guild-wide craftable count.
- Expansion pills for narrowing the recipe list by patch.
- Your alts are tracked and tagged separately from guild members.
- Slash commands: `/grd`, `/grd dump`, `/grd debug on|off`.
