# Changelog

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
