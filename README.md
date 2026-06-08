# GuildRecipeDex

**GuildRecipeDex** flips the usual guild-crafting workflow on its head. Instead of asking in guild chat "does anyone have X?" or clicking through every guildie's profession window, you open one browser that shows **every recipe in the game** and tells you **who in your guild can make it**.

## How it works

- **Catalog-first**: a baked-in database of every recipe in every profession means you can see gaps in your guild's coverage — recipes nobody has learned yet — not just what people happen to have open.
- **Automatic sync**: each client scans its own characters' known recipes when you open a profession window. The addon quietly exchanges that data over the guild addon channel, so everyone's view stays current without any manual steps.
- **Your alts count too**: your own characters are tracked alongside guild members and shown separately so you always know whether you can craft something yourself before you bother anyone.

## The browser

Open it with `/grd`. The left pane lists every recipe in the selected profession, organized by expansion and category. Each row shows the recipe name, item level, type, and a pill showing how many people in your guild (including your alts) can craft it.

Click a recipe and the right pane shows:

- **Reagents** — required and optional, with your current owned counts (bags + bank + reagent bank + Warband bank) and an "All in bank" badge when you're fully stocked
- **Optional reagents** — embellishments, finishing reagents, and quality-tier slots
- **Source** — where to learn it, if you haven't already
- **Crafters** — everyone who can make it, sorted by you → your alts → online guildmates → offline guildmates, with class colors, skill level, and last-seen time. Filter by All / Alts / Guild / Online. Click a row to select them, then hit **Whisper** to open a tell.

The profession header shows the total recipe count and how many your guild can currently craft. Expansion pills let you narrow the list to a single patch's recipes.

## Commands

- `/grd` — open or close the browser
- `/grd dump` — print tracked profession data to chat (debugging)
- `/grd debug on|off` — toggle verbose logging

## Notes

- Requires all players who want to share data to have the addon installed and loaded.
- Recipe source text (vendor location, drop source, etc.) is fetched live from the game client the first time you view an unlearned recipe with that profession open, then cached. Coverage improves the more professions you open in-game.
