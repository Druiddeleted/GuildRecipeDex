local _, ns = ...
local P = ns.UIPriv

----------------------------------------------------------------------
-- Catalog accessors + recipe display/link helpers
----------------------------------------------------------------------

function P.professionsList()
  local out = {}
  if not ns.Catalog or not ns.Catalog.professions then return out end
  for pid, p in pairs(ns.Catalog.professions) do
    table.insert(out, { id = pid, name = p.name })
  end
  table.sort(out, function(a, b) return a.name < b.name end)
  return out
end

-- Expansion skillLine IDs are NOT chronological (the pre-Shadowlands era IDs are
-- out of sequence), so order by a known era list. Higher = newer.
local ERA_ORDER = {
  ["Classic"] = 1, ["Outland"] = 2, ["Northrend"] = 3, ["Cataclysm"] = 4,
  ["Pandaria"] = 5, ["Draenor"] = 6, ["Legion"] = 7, ["Kul Tiran"] = 8,
  ["Shadowlands"] = 9, ["Dragon Isles"] = 10, ["Khaz Algar"] = 11, ["Midnight"] = 12,
}

function P.expansionsForProfession(pid)
  local out = {}
  local prof = ns.Catalog.professions and ns.Catalog.professions[pid]
  if not prof then return out end
  local profName = prof.name or ""
  for _, eid in ipairs(prof.expansions or {}) do
    local e = ns.Catalog.expansions and ns.Catalog.expansions[eid]
    if e then
      local era = (e.name:gsub(" " .. profName .. "$", ""))  -- "Midnight Leatherworking" -> "Midnight"
      table.insert(out, { id = eid, name = e.name, icon = e.icon, era = era, order = ERA_ORDER[era] or 0 })
    end
  end
  -- Newest era first; fall back to id for any unmapped era.
  table.sort(out, function(a, b)
    if a.order ~= b.order then return a.order > b.order end
    return a.id > b.id
  end)
  return out
end

-- Build the category tree for an expansion. Data structure: each expansion has
-- exactly one "Patterns" category tagged with skillLine == expansionID. All
-- sub-categories under it have skillLine == baseProfession; recipes (also
-- skillLine == base) attach to those leaf sub-categories by category ID.
function P.buildExpansionTree(expansionID)
  local tree = {}
  local roots = {}
  if not ns.Catalog or not ns.Catalog.categories or not ns.Catalog.recipes then return tree, roots end

  -- Find the root "Patterns" category for this expansion.
  local patternsCatID
  for cid, c in pairs(ns.Catalog.categories) do
    if c.skillLine == expansionID then patternsCatID = cid; break end
  end
  if not patternsCatID then return tree, roots end

  -- Walk DOWN, collecting all descendant categories.
  local function walk(cid)
    local c = ns.Catalog.categories[cid]
    if not c or tree[cid] then return end
    tree[cid] = { id = cid, name = c.name, parent = c.parent, childCats = {}, recipeIDs = {} }
    for childID, childCat in pairs(ns.Catalog.categories) do
      if childCat.parent == cid then walk(childID) end
    end
  end
  walk(patternsCatID)

  -- Wire up child relationships.
  for cid, c in pairs(tree) do
    if c.parent and tree[c.parent] then
      table.insert(tree[c.parent].childCats, cid)
    end
  end

  -- Attach recipes whose category is in our tree.
  for rid, r in pairs(ns.Catalog.recipes) do
    if tree[r.category] then
      table.insert(tree[r.category].recipeIDs, rid)
    end
  end

  local function nameOf(cid) return tree[cid] and tree[cid].name or "" end
  for _, c in pairs(tree) do
    table.sort(c.childCats, function(a, b) return nameOf(a) < nameOf(b) end)
  end

  -- Subtree recipe totals (direct + descendants) so the UI can hide empty
  -- sections and show accurate per-section counts.
  local function countSub(cid)
    local c = tree[cid]
    if not c then return 0 end
    if c._sub ~= nil then return c._sub end
    c._sub = 0  -- cycle guard
    local n = #(c.recipeIDs or {})
    for _, ch in ipairs(c.childCats) do n = n + countSub(ch) end
    c._sub = n
    return n
  end
  for cid in pairs(tree) do countSub(cid) end

  -- Skip the "Patterns" root entirely: its (now-sorted) child categories are the
  -- real top-level sections shown in the list.
  roots = {}
  local pc = tree[patternsCatID]
  if pc then for _, c in ipairs(pc.childCats) do roots[#roots + 1] = c end end
  return tree, roots
end

-- Precomputed map recipeID -> number of distinct characters who can craft it
-- (drives the list count pills). Cached; invalidate when scan/sync data changes.
function P.ensureCrafterCounts()
  if P._crafterCounts then return P._crafterCounts end
  local counts = {}
  local db = GuildRecipeDexDB
  if db and db.characters then
    for _, char in pairs(db.characters) do
      local seen = {}
      if char.professions then
        for _, prof in pairs(char.professions) do
          if prof.recipes then
            for rid in pairs(prof.recipes) do
              if not seen[rid] then seen[rid] = true; counts[rid] = (counts[rid] or 0) + 1 end
            end
          end
        end
      end
    end
  end
  P._crafterCounts = counts
  return counts
end

function P.invalidateCrafterCounts() P._crafterCounts = nil end

-- Merge every expansion's tree for a profession into one (the "All" pill).
function P.buildProfessionTree(pid)
  local mergedTree, mergedRoots = {}, {}
  for _, e in ipairs(P.expansionsForProfession(pid)) do
    local t, r = P.buildExpansionTree(e.id)
    for cid, c in pairs(t) do mergedTree[cid] = c end
    for _, rc in ipairs(r) do mergedRoots[#mergedRoots + 1] = rc end
  end
  return mergedTree, mergedRoots
end

-- Build (once, cached) a recipe-count-per-expansion index for the pill badges.
-- catExpansion maps a categoryID up to the expansion skillLine it belongs to.
function P.ensureExpansionIndex()
  if P._expRecipeCount then return end
  local cats = (ns.Catalog and ns.Catalog.categories) or {}
  local exps = (ns.Catalog and ns.Catalog.expansions) or {}
  local catExp = {}
  local function expOf(cid)
    if catExp[cid] ~= nil then return catExp[cid] end
    catExp[cid] = false  -- guard against cycles
    local c = cats[cid]
    local e = false
    if c then
      if exps[c.skillLine] then
        e = c.skillLine
      elseif c.parent and c.parent ~= 0 then
        e = expOf(c.parent)
      end
    end
    catExp[cid] = e
    return e
  end
  for cid in pairs(cats) do expOf(cid) end
  local counts = {}
  for _, r in pairs((ns.Catalog and ns.Catalog.recipes) or {}) do
    local e = catExp[r.category]
    if e then counts[e] = (counts[e] or 0) + 1 end
  end
  P._catExpansion = catExp
  P._expRecipeCount = counts
end

function P.expansionRecipeCount(eid)
  P.ensureExpansionIndex()
  return P._expRecipeCount[eid] or 0
end

function P.professionRecipeCount(pid)
  P.ensureExpansionIndex()
  local total = 0
  for _, e in ipairs(P.expansionsForProfession(pid)) do
    total = total + (P._expRecipeCount[e.id] or 0)
  end
  return total
end

function P.professionCraftableCount(pid)
  local counts = P.ensureCrafterCounts()
  local expansions = P.expansionsForProfession(pid)
  if not expansions or #expansions == 0 then return 0 end
  local seen = {}
  local total = 0
  for _, e in ipairs(expansions) do
    local t, _ = P.buildExpansionTree(e.id)
    for _, cat in pairs(t) do
      for _, rid in ipairs(cat.recipeIDs or {}) do
        if not seen[rid] and (counts[rid] or 0) > 0 then
          seen[rid] = true
          total = total + 1
        end
      end
    end
  end
  return total
end

-- Lookup: for a given recipeID, which characters have it learned?
function P.craftersForRecipe(recipeID)
  local out = {}
  local db = GuildRecipeDexDB
  if not db or not db.characters then return out end
  for _, char in pairs(db.characters) do
    if char.professions then
      for _, prof in pairs(char.professions) do
        if prof.recipes and prof.recipes[recipeID] then
          table.insert(out, char.name or "?")
          break
        end
      end
    end
  end
  return out
end

-- Compact "3h" / "2d" elapsed label.
function P.shortAgo(secs)
  if not secs or secs <= 0 then return "" end
  if secs < 3600 then return math.floor(secs / 60) .. "m" end
  if secs < 86400 then return math.floor(secs / 3600) .. "h" end
  return math.floor(secs / 86400) .. "d"
end

-- Guild roster status, keyed by lowercased "name-realm" and bare "name".
-- Best-effort: online flag + seconds-since-last-online. Empty if not guilded.
function P.guildStatus()
  local map = {}
  if not (IsInGuild and IsInGuild()) then return map end
  if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
  local n = (GetNumGuildMembers and GetNumGuildMembers()) or 0
  for i = 1, n do
    local fullName, _, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
    if fullName then
      local secs = 0
      if not online and GetGuildRosterLastOnline then
        local y, m, d, h = GetGuildRosterLastOnline(i)
        secs = (((((y or 0) * 365) + (m or 0) * 30 + (d or 0)) * 24) + (h or 0)) * 3600
      end
      local entry = { online = online, secs = secs }
      map[fullName:lower()] = entry
      local short = fullName:match("^([^-]+)")
      if short and not map[short:lower()] then map[short:lower()] = entry end
    end
  end
  return map
end

-- Structured crafter list for a recipe: who can make it, with kind (you/alt/
-- guild), profession skill, and best-effort online status. Sorted you → alts →
-- guild, online first.
function P.craftersInfoForRecipe(recipeID)
  local out = {}
  local db = GuildRecipeDexDB
  if not db or not db.characters then return out end
  local myKey = ns.DB and ns.DB:CharKey()
  local status = P.guildStatus()
  for key, char in pairs(db.characters) do
    local has, skill = false, nil
    if char.professions then
      for _, prof in pairs(char.professions) do
        if prof.recipes and prof.recipes[recipeID] then
          has = true
          skill = prof.rank or skill
        end
      end
    end
    if has then
      local kind = (key == myKey) and "you" or (char.own and "alt" or "guild")
      local name, realm = char.name or "?", char.realm or ""
      local st = status[(name .. "-" .. realm):lower()] or status[name:lower()]
      local online = (kind == "you") or (st and st.online) or false
      out[#out + 1] = {
        key = key, name = name, realm = realm, class = char.class,
        kind = kind, skill = skill, online = online, secs = (st and st.secs) or 0,
      }
    end
  end
  local rank = { you = 0, alt = 1, guild = 2 }
  table.sort(out, function(a, b)
    if rank[a.kind] ~= rank[b.kind] then return rank[a.kind] < rank[b.kind] end
    if a.online ~= b.online then return a.online end
    return a.name < b.name
  end)
  return out
end

-- Lookup: get the scanned info for a recipe from any character that has it
-- (used to display reagents/icon since the catalog doesn't include those).
function P.scannedRecipeInfo(recipeID)
  local db = GuildRecipeDexDB
  if not db or not db.characters then return nil end
  for _, char in pairs(db.characters) do
    if char.professions then
      for _, prof in pairs(char.professions) do
        local r = prof.recipes and prof.recipes[recipeID]
        if type(r) == "table" then return r end
      end
    end
  end
  return nil
end

-- Does the player's CURRENT character know this recipe? (drives the
-- "Recipe Unlearned" indicator). Uses our own scan data, so it's reliable
-- regardless of whether a profession window is open.
function P.currentCharKnows(recipeID)
  local db = GuildRecipeDexDB
  if not db or not db.characters then return false end
  local key = ns.DB and ns.DB.CharKey and ns.DB:CharKey()
  local char = key and db.characters[key]
  if not char or not char.professions then return false end
  for _, prof in pairs(char.professions) do
    if prof.recipes and prof.recipes[recipeID] then return true end
  end
  return false
end

-- Source text ("Vendor: …", "Drops from …", "Requires Specialization: …") for an
-- unlearned recipe, mirroring the profession book. C_TradeSkillUI.GetRecipeSourceText
-- only returns data when the client has that profession's trade-skill data loaded,
-- so successful lookups are cached in SavedVariables to grow coverage over time.
function P.recipeSourceText(recipeID)
  local live
  if C_TradeSkillUI and C_TradeSkillUI.GetRecipeSourceText then
    local ok, txt = pcall(C_TradeSkillUI.GetRecipeSourceText, recipeID)
    if ok and txt and txt ~= "" then live = txt end
  end
  local cache = GuildRecipeDexDB and GuildRecipeDexDB.sources
  if live then
    if cache then cache[recipeID] = live end
    return live
  end
  return cache and cache[recipeID] or nil
end

-- Build a chat-insertable hyperlink for a recipe (spellID). Prefer the trade
-- skill recipe link (shows reagents) when available; fall back to the spell
-- link, which works for any spell ID even if the recipe is unknown.
local function recipeLink(recipeID)
  local link = C_TradeSkillUI and C_TradeSkillUI.GetRecipeLink and C_TradeSkillUI.GetRecipeLink(recipeID)
  if not link then
    if C_Spell and C_Spell.GetSpellLink then
      link = C_Spell.GetSpellLink(recipeID)
    elseif GetSpellLink then
      link = GetSpellLink(recipeID)
    end
  end
  return link
end

-- Shift-click handler: insert the recipe link into the active chat edit box.
-- Returns true if it handled the click so the caller can stop.
function P.tryInsertRecipeLink(recipeID)
  if not recipeID or not IsModifiedClick("CHATLINK") then return false end
  local link = recipeLink(recipeID)
  if link then ChatEdit_InsertLink(link) end
  return true
end

function P.recipeDisplay(rid)
  local info = P.scannedRecipeInfo(rid)
  local name = info and info.name
  local icon
  -- Prefer the OUTPUT item's icon over the spell's icon (which is often the
  -- generic profession icon for unlearned recipes).
  local cat = ns.Catalog and ns.Catalog.recipes and ns.Catalog.recipes[rid]
  if cat and cat.item and cat.item ~= 0 then
    local _, _, _, _, itemIcon = GetItemInfoInstant(cat.item)
    icon = itemIcon
  end
  if not icon then icon = info and info.icon end
  if not name then
    local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(rid)
    if spellInfo then
      name = spellInfo.name or name
      if not icon then icon = spellInfo.iconID end
    end
  end
  return name or ("Recipe " .. rid), icon or 134400, info
end
