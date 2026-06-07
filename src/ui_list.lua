local _, ns = ...
local P = ns.UIPriv
local ROW_HEIGHT, LIST_WIDTH = P.ROW_HEIGHT, P.LIST_WIDTH

----------------------------------------------------------------------
-- Flat row list (category tree + recipes, or flat search results)
----------------------------------------------------------------------

local function flattenRows()
  local rows = {}
  local tree, roots = P.tree, P.roots
  if not tree or not roots then return rows end
  local s = P.state.search:lower()

  if s ~= "" then
    -- Flat search across all recipes whose category is in the current tree.
    local matches = {}
    for rid, r in pairs(ns.Catalog.recipes) do
      if tree[r.category] then
        local info = P.scannedRecipeInfo(rid)
        local name = info and info.name
        if name and name:lower():find(s, 1, true) then
          table.insert(matches, { rid = rid, name = name })
        end
      end
    end
    table.sort(matches, function(a, b) return a.name < b.name end)
    for _, m in ipairs(matches) do
      table.insert(rows, { kind = "recipe", recipeID = m.rid, depth = 0 })
    end
    return rows
  end

  local function visit(cid, depth)
    local c = tree[cid]
    if not c then return end
    table.insert(rows, { kind = "cat", catID = cid, depth = depth })
    if not P.state.expanded[cid] then return end
    for _, child in ipairs(c.childCats) do visit(child, depth + 1) end
    -- Sort recipes by name (using scanned name if available, else recipeID).
    local sortedRecipes = {}
    for _, rid in ipairs(c.recipeIDs) do
      local name = P.recipeDisplay(rid)
      table.insert(sortedRecipes, { rid = rid, name = name })
    end
    table.sort(sortedRecipes, function(a, b) return a.name < b.name end)
    for _, e in ipairs(sortedRecipes) do
      table.insert(rows, { kind = "recipe", recipeID = e.rid, depth = depth + 1 })
    end
  end
  for _, root in ipairs(roots) do visit(root, 0) end
  return rows
end

local function makeRow(i)
  local row = CreateFrame("Button", nil, P.listChild)
  row:SetSize(LIST_WIDTH, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  -- selection highlight (recipe rows when selected)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints(); row.bg:SetColorTexture(0.3, 0.3, 0.6, 0.4); row.bg:Hide()
  -- category styling: dark filled rect + subtle border
  row.catBg = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  row.catBg:SetPoint("TOPLEFT", 2, -1)
  row.catBg:SetPoint("BOTTOMRIGHT", -2, 1)
  row.catBg:SetColorTexture(0.12, 0.08, 0.04, 0.85)
  row.catBg:Hide()
  row.catBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.catBorder:SetPoint("TOPLEFT", row.catBg, "TOPLEFT", 0, 0)
  row.catBorder:SetPoint("BOTTOMRIGHT", row.catBg, "BOTTOMRIGHT", 0, 0)
  row.catBorder:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 8 })
  row.catBorder:SetBackdropBorderColor(0.7, 0.55, 0.15, 0.8)
  row.catBorder:Hide()

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(ROW_HEIGHT - 2, ROW_HEIGHT - 2)
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.text:SetJustifyH("LEFT")
  row:SetScript("OnClick", function(self)
    local e = self.entry
    if not e then return end
    if e.kind == "recipe" and P.tryInsertRecipeLink(e.recipeID) then return end
    if e.kind == "cat" then
      P.state.expanded[e.catID] = not P.state.expanded[e.catID]
      P.refreshList()
    else
      P.state.selectedRecipeID = e.recipeID
      P.refreshList(); P.refreshDetail()
    end
  end)
  row:SetScript("OnEnter", function(self)
    if self.recipeID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetSpellByID(self.recipeID)
      GameTooltip:Show()
    end
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

function P.refreshList()
  local flatRows = flattenRows()
  P.flatRows = flatRows
  local listRows = P.listRows

  -- Grow pool to the number of entries.
  for i = #listRows + 1, #flatRows do
    listRows[i] = makeRow(i)
  end

  for i, row in ipairs(listRows) do
    local entry = flatRows[i]
    if not entry then
      row:Hide()
    else
      row:Show()
      row.entry = entry
      if entry.kind == "cat" then
        local c = P.tree[entry.catID]
        local marker = P.state.expanded[entry.catID] and "[-] " or "[+] "
        row.text:SetText("|cffffd200" .. marker .. (c and c.name or "?") .. "|r")
        row.icon:Hide()
        row.bg:Hide()
        row.catBg:Show()
        row.catBorder:Show()
        row.recipeID = nil
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", 6 + entry.depth * 10, 0)
        row.text:SetPoint("RIGHT", -4, 0)
      else
        local name, icon = P.recipeDisplay(entry.recipeID)
        row.text:SetText("|cffffffff" .. name .. "|r")
        row.icon:SetTexture(icon)
        row.icon:Show()
        row.icon:ClearAllPoints()
        row.icon:SetPoint("LEFT", 6 + entry.depth * 10, 0)
        row.catBg:Hide()
        row.catBorder:Hide()
        row.recipeID = entry.recipeID
        if P.state.selectedRecipeID == entry.recipeID then row.bg:Show() else row.bg:Hide() end
        row.text:ClearAllPoints()
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        row.text:SetPoint("RIGHT", -4, 0)
      end
    end
  end

  P.listChild:SetHeight(math.max(#flatRows * ROW_HEIGHT, 1))
end

----------------------------------------------------------------------
-- Profession / expansion selection + dropdowns
----------------------------------------------------------------------

function P.selectExpansion(eid)
  local state = P.state
  state.expansionID = eid
  state.selectedRecipeID = nil
  state.scrollOffset = 0
  state.expanded = {}
  P.tree, P.roots = P.buildExpansionTree(state.expansionID)
  for _, rcid in ipairs(P.roots) do state.expanded[rcid] = true end
  local e = ns.Catalog.expansions and ns.Catalog.expansions[eid]
  if P.expansionDropdown then UIDropDownMenu_SetText(P.expansionDropdown, e and e.name or "") end
  P.refreshList(); P.refreshDetail()
end

function P.initExpansionDropdown(_, level)
  if not P.state.professionID then return end
  for _, e in ipairs(P.expansionsForProfession(P.state.professionID)) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = e.name
    info.func = function() P.selectExpansion(e.id) end
    info.checked = (P.state.expansionID == e.id)
    UIDropDownMenu_AddButton(info, level)
  end
end

function P.selectProfession(pid)
  local state = P.state
  state.professionID = pid
  state.selectedRecipeID = nil
  state.expanded = {}
  state.scrollOffset = 0
  local expansions = P.expansionsForProfession(pid)
  UIDropDownMenu_SetText(P.profDropdown, ns.Catalog.professions[pid].name)
  if expansions[1] then
    P.selectExpansion(expansions[1].id)
  else
    state.expansionID = nil
    P.tree, P.roots = {}, {}
    if P.expansionDropdown then UIDropDownMenu_SetText(P.expansionDropdown, "") end
    P.refreshList(); P.refreshDetail()
  end
end

function P.initProfDropdown(_, level)
  for _, p in ipairs(P.professionsList()) do
    local info = UIDropDownMenu_CreateInfo()
    info.text = p.name
    info.func = function() P.selectProfession(p.id) end
    info.checked = (P.state.professionID == p.id)
    UIDropDownMenu_AddButton(info, level)
  end
end
