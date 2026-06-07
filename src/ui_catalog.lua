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

function P.expansionsForProfession(pid)
  local out = {}
  local prof = ns.Catalog.professions and ns.Catalog.professions[pid]
  if not prof then return out end
  for _, eid in ipairs(prof.expansions or {}) do
    local e = ns.Catalog.expansions and ns.Catalog.expansions[eid]
    if e then table.insert(out, { id = eid, name = e.name, icon = e.icon }) end
  end
  -- Sort newest expansion first (higher skillLineID is newer).
  table.sort(out, function(a, b) return a.id > b.id end)
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

  -- The "patterns" category is our visual root.
  roots = { patternsCatID }

  local function nameOf(cid) return tree[cid] and tree[cid].name or "" end
  for _, c in pairs(tree) do
    table.sort(c.childCats, function(a, b) return nameOf(a) < nameOf(b) end)
  end
  return tree, roots
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
