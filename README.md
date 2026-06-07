# GuildRecipeDex

A catalog-first guild profession browser for World of Warcraft.

Instead of picking a guildie and browsing their recipes, GuildRecipeDex shows every recipe in the game and tells you who in your guild can craft each one. Find gaps in your guild's coverage at a glance, and find the right crafter without spamming guild chat.

## How it works

- Each client scans its own characters' known recipes when you open a profession window.
- Clients running the addon exchange data via guild addon-channel messages so everyone stays in sync.
- A static catalog (generated from game data) lists every recipe that exists, so the addon can show "nobody in the guild can craft this yet."

## Commands

- `/grd` — open the browser
- `/grd dump` — print the current character's tracked professions and recipe counts
- `/grd debug on|off` — toggle debug logging
