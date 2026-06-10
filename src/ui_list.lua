local _, ns = ...
local P = ns.UIPriv
local T = ns.UITheme

local WHITE = "Interface\\Buttons\\WHITE8X8"
local LISTW = 336          -- row width (≈ left-pane scroll width)
local CAT_H, REC_H = 26, 44 -- category header / recipe row heights
local VISIBLE_ROWS = 24    -- rows visible in the scroll viewport
local POOL_SIZE = VISIBLE_ROWS + 4

----------------------------------------------------------------------
-- Flat row list (category tree + recipes, or flat search results)
----------------------------------------------------------------------

-- Sections to hide from the list: "Appendix - …" buckets and any category whose
-- whole subtree has no recipes.
local function hiddenCat(c)
  if not c then return true end
  if (c._sub or 0) == 0 then return true end
  if c.name and c.name:find("^Appendix") then return true end
  if c.name and c.name:find("^Recraft") then return true end
  return false
end

local function flattenRows()
  local rows = {}
  local tree, roots = P.tree, P.roots
  if not tree or not roots then return rows end
  local s = P.state.search:lower()

  if s ~= "" then
    -- Flat search across all recipes whose category is in the current tree.
    local matches = {}
    for rid, r in pairs(ns.Catalog.recipes) do
      if tree[r.category] and not hiddenCat(tree[r.category]) then
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
    if not c or hiddenCat(c) then return end
    table.insert(rows, { kind = "cat", catID = cid, depth = depth })
    if not P.state.expanded[cid] then return end
    for _, child in ipairs(c.childCats) do visit(child, depth + 1) end
    local sortedRecipes = {}
    for _, rid in ipairs(c.recipeIDs) do
      local name = P.recipeDisplay(rid)
      if not name:find("^Recipe %d") then
        table.insert(sortedRecipes, { rid = rid, name = name })
      end
    end
    table.sort(sortedRecipes, function(a, b) return a.name < b.name end)
    for _, e in ipairs(sortedRecipes) do
      table.insert(rows, { kind = "recipe", recipeID = e.rid, depth = depth + 1 })
    end
  end
  for _, root in ipairs(roots) do visit(root, 0) end
  return rows
end

-- "Type · iLvl N" subtitle from the recipe's output item (may be "" until the
-- item is cached; refreshList warms it and re-sets the row).
local function recipeSubtitle(rid)
  local catr = ns.Catalog.recipes and ns.Catalog.recipes[rid]
  local item = catr and catr.item
  if item and item ~= 0 then
    local _, _, _, ilvl, _, _, isub = GetItemInfo(item)
    if isub then
      if ilvl and ilvl > 0 then return isub .. " · iLvl " .. ilvl end
      return isub
    end
  end
  return ""
end

----------------------------------------------------------------------
-- Rows
----------------------------------------------------------------------

local function makeRow()
  local row = CreateFrame("Button", nil, P.listChild)
  row:SetWidth(LISTW)

  -- selection chrome
  row.selBg = row:CreateTexture(nil, "BACKGROUND")
  row.selBg:SetPoint("TOPLEFT", 2, 0); row.selBg:SetPoint("BOTTOMRIGHT", -2, 0)
  row.selBg:SetColorTexture(T.rgba("rowSel")); row.selBg:Hide()
  row.selBar = row:CreateTexture(nil, "ARTWORK")
  row.selBar:SetPoint("TOPLEFT", 2, 0); row.selBar:SetPoint("BOTTOMLEFT", 2, 0); row.selBar:SetWidth(2)
  row.selBar:SetColorTexture(T.rgba("gold")); row.selBar:Hide()

  -- category-header widgets
  row.catChevron = T.Icon(row, "chevron-down", 11, "goldDim"); row.catChevron:Hide()
  row.catLabel = T.Text(row, { size = 11, color = "goldDim" }); row.catLabel:Hide()
  row.catCount = T.Text(row, { size = 11, color = "goldFaint" }); row.catCount:SetPoint("RIGHT", -10, 0); row.catCount:Hide()
  row.catLine = row:CreateTexture(nil, "ARTWORK"); row.catLine:SetColorTexture(T.rgba("border")); row.catLine:SetHeight(1); row.catLine:Hide()

  -- recipe-row widgets
  row.iconFrame = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.iconFrame:SetSize(28, 28)
  row.iconFrame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  row.iconFrame:SetBackdropColor(T.rgba("iconBg"))
  row.iconFrame:SetBackdropBorderColor(T.rgba("borderGold2"))
  row.icon = row.iconFrame:CreateTexture(nil, "ARTWORK")
  row.icon:SetPoint("TOPLEFT", 2, -2); row.icon:SetPoint("BOTTOMRIGHT", -2, 2)
  row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  row.iconFrame:Hide()

  row.name = T.Text(row, { size = 14, color = "blue" }); row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false); row.name:Hide()
  row.sub = T.Text(row, { size = 12, color = "goldFaint" }); row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false); row.sub:Hide()

  row.countPill = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.countPill:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  row.countPill:SetHeight(16); row.countPill:SetPoint("RIGHT", -8, 0)
  row.countText = T.Text(row.countPill, { size = 12, color = "greenBright", mono = true })
  row.countText:SetPoint("CENTER")
  row.countPill:Hide()

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
  local offsets = {}
  local totalH = 0
  for i, e in ipairs(flatRows) do
    offsets[i] = totalH
    totalH = totalH + (e.kind == "cat" and CAT_H or REC_H)
  end
  P.rowOffsets = offsets
  P.totalHeight = totalH
  P.listChild:SetHeight(math.max(totalH, 1))
  P.renderVisibleRows()
end

function P.renderVisibleRows()
  local flatRows = P.flatRows or {}
  local offsets  = P.rowOffsets or {}
  local scrollTop = P.state.scrollTop or 0
  local viewH = (P.listScroll and P.listScroll:GetHeight()) or (VISIBLE_ROWS * REC_H)
  local scrollBot = scrollTop + viewH

  local firstIdx = 1
  for i = 1, #flatRows do
    if (offsets[i] or 0) + (flatRows[i].kind == "cat" and CAT_H or REC_H) > scrollTop then
      firstIdx = i; break
    end
  end

  local counts = P.ensureCrafterCounts()
  local rows = P.listRows
  for i = #rows + 1, POOL_SIZE do rows[i] = makeRow() end

  local slot = 0
  for i = firstIdx, #flatRows do
    local rowTop = offsets[i] or 0
    if rowTop >= scrollBot then break end
    slot = slot + 1
    if slot > POOL_SIZE then break end
    local row = rows[slot]
    local e = flatRows[i]
    row:Show()
    row.entry = e
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -rowTop)

    if e.kind == "cat" then
      row:SetHeight(CAT_H)
      local c = P.tree[e.catID]
      row.iconFrame:Hide(); row.name:Hide(); row.sub:Hide(); row.countPill:Hide()
      row.selBg:Hide(); row.selBar:Hide()
      row.recipeID = nil
      local chev = P.state.expanded[e.catID] and T.ICON["chevron-down"] or T.ICON["chevron-right"]
      if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(chev) then row.catChevron:SetAtlas(chev) end
      row.catChevron:ClearAllPoints(); row.catChevron:SetPoint("LEFT", 10 + e.depth * 10, 0); row.catChevron:Show()
      row.catLabel:ClearAllPoints(); row.catLabel:SetPoint("LEFT", row.catChevron, "RIGHT", 6, 0)
      row.catLabel:SetText(string.upper(c and c.name or "?")); row.catLabel:Show()
      row.catCount:SetText(tostring((c and c._sub) or 0)); row.catCount:Show()
      row.catLine:ClearAllPoints()
      row.catLine:SetPoint("LEFT", row.catLabel, "RIGHT", 8, 0)
      row.catLine:SetPoint("RIGHT", row.catCount, "LEFT", -8, 0)
      row.catLine:Show()
    else
      row:SetHeight(REC_H)
      row.catChevron:Hide(); row.catLabel:Hide(); row.catCount:Hide(); row.catLine:Hide()
      row.recipeID = e.recipeID
      local sel = (P.state.selectedRecipeID == e.recipeID)
      local name, icon = P.recipeDisplay(e.recipeID)
      row.iconFrame:ClearAllPoints(); row.iconFrame:SetPoint("LEFT", 8 + e.depth * 10, 0); row.iconFrame:Show()
      row.icon:SetTexture(icon)
      row.name:ClearAllPoints()
      row.name:SetPoint("TOPLEFT", row.iconFrame, "TOPRIGHT", 8, -1)
      row.name:SetPoint("RIGHT", row, "RIGHT", -44, 0)
      row.name:SetText(name); row.name:SetTextColor(T.rgba(sel and "gold" or "blue")); row.name:Show()
      row.sub:ClearAllPoints()
      row.sub:SetPoint("BOTTOMLEFT", row.iconFrame, "BOTTOMRIGHT", 8, 1)
      row.sub:SetPoint("RIGHT", row, "RIGHT", -44, 0)
      row.sub:SetText(recipeSubtitle(e.recipeID)); row.sub:SetTextColor(T.rgba(sel and "goldDim" or "goldFaint")); row.sub:Show()
      local n = counts[e.recipeID] or 0
      row.countText:SetText(tostring(n))
      row.countPill:SetWidth((row.countText:GetStringWidth() or 8) + 12)
      if n > 0 then
        row.countPill:SetBackdropColor(T.rgba("chipOn"))
        row.countPill:SetBackdropBorderColor(T.rgba("chipBorder"))
        row.countText:SetTextColor(T.rgba("greenBright"))
      else
        row.countPill:SetBackdropColor(T.rgba("rowBg"))
        row.countPill:SetBackdropBorderColor(T.rgba("border"))
        row.countText:SetTextColor(T.rgba("goldFaint"))
      end
      row.countPill:Show()
      if sel then row.selBg:Show(); row.selBar:Show() else row.selBg:Hide(); row.selBar:Hide() end
      -- Warm the output item so the subtitle fills in once cached.
      local catr = ns.Catalog.recipes[e.recipeID]
      if catr and catr.item and catr.item ~= 0 and (row.sub:GetText() or "") == "" then
        local it = Item:CreateFromItemID(catr.item)
        local rid = e.recipeID
        it:ContinueOnItemLoad(function()
          if row.recipeID == rid then row.sub:SetText(recipeSubtitle(rid)) end
        end)
      end
    end
  end
  for i = slot + 1, #rows do rows[i]:Hide() end
end

----------------------------------------------------------------------
-- Expansion pills (horizontal, newest-first) + footer
----------------------------------------------------------------------

local function makePill()
  local p = CreateFrame("Button", nil, P.expPillChild, "BackdropTemplate")
  p:SetHeight(24)
  p:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  p.label = T.Text(p, { size = 11, color = "goldDim" })
  p.label:SetPoint("LEFT", 9, 0)
  p.label:SetPoint("RIGHT", -9, 0)
  p.count = T.Text(p, { size = 10, color = "goldFaint", mono = true })
  p.count:SetPoint("RIGHT", -9, 0)
  p:SetScript("OnClick", function(self) if self.eid ~= nil then P.selectExpansion(self.eid) end end)
  p:SetScript("OnSizeChanged", function(self)
    local lw = self.label:GetUnboundedStringWidth() or 0
    local cw = self.count:GetUnboundedStringWidth() or 0
    local needed = 9 + lw + 6 + cw + 9
    if math.abs((self:GetWidth() or 0) - needed) > 1 then
      self:SetWidth(math.max(needed, 40))
    end
  end)
  return p
end

function P.refreshExpansionPills()
  local child = P.expPillChild
  if not child then return end
  local pills = P.expPills
  local pid = P.state.professionID

  local entries = { { id = "all", label = "All", count = pid and P.professionRecipeCount(pid) or 0 } }
  if pid then
    for _, e in ipairs(P.expansionsForProfession(pid)) do  -- already newest-first
      entries[#entries + 1] = { id = e.id, label = e.era, count = P.expansionRecipeCount(e.id) }
    end
  end

  local x = 0
  for i, en in ipairs(entries) do
    local pill = pills[i]
    if not pill then pill = makePill(); pills[i] = pill end
    pill.eid = en.id
    pill.label:SetText(en.label)
    pill.count:SetText(tostring(en.count))
    local sel = (P.state.expansionID == en.id)
    if sel then
      pill:SetBackdropColor(T.rgba("rowSel")); pill:SetBackdropBorderColor(T.rgba("gold"))
      pill.label:SetTextColor(T.rgba("gold")); pill.count:SetTextColor(T.rgba("goldDim"))
    else
      pill:SetBackdropColor(T.rgba("rowBg")); pill:SetBackdropBorderColor(T.rgba("border2"))
      pill.label:SetTextColor(T.rgba("goldDim")); pill.count:SetTextColor(T.rgba("goldFaint"))
    end
    local labelW = pill.label:GetUnboundedStringWidth() or 10
    local countW = pill.count:GetUnboundedStringWidth() or 6
    local w = math.max(9 + labelW + 6 + countW + 9, 40)
    pill:SetWidth(w)
    pill:ClearAllPoints(); pill:SetPoint("LEFT", x, 0)
    pill:Show()
    x = x + w + 6
    local capturedPill = pill
    C_Timer.After(0, function()
      if not capturedPill:IsShown() then return end
      local lw2 = capturedPill.label:GetUnboundedStringWidth() or 0
      local cw2 = capturedPill.count:GetUnboundedStringWidth() or 0
      local w2 = math.max(9 + lw2 + 6 + cw2 + 9, 40)
      if math.abs(capturedPill:GetWidth() - w2) > 1 then
        capturedPill:SetWidth(w2)
        P.refreshExpansionPills()
      end
    end)
  end
  for i = #entries + 1, #pills do pills[i]:Hide() end
  child:SetWidth(math.max(x, 1)); child:SetHeight(26)
end

local function ago(ts)
  local d = time() - ts
  if d < 60 then return d .. "s ago" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

function P.refreshFooter()
  if not P.footerLeft then return end
  local shown = 0
  for _, e in ipairs(P.flatRows or {}) do if e.kind == "recipe" then shown = shown + 1 end end
  local total = 0
  for _, c in pairs(P.tree or {}) do total = total + #(c.recipeIDs or {}) end
  P.footerLeft:SetText(("Showing %d of %d"):format(shown, total))

  local ts, db = 0, GuildRecipeDexDB
  local key = ns.DB and ns.DB.CharKey and ns.DB:CharKey()
  local char = key and db and db.characters and db.characters[key]
  if char and char.professions then
    for _, prof in pairs(char.professions) do ts = math.max(ts, prof.scannedAt or 0) end
  end
  P.footerSync:SetText(ts > 0 and ("Last sync " .. ago(ts)) or "Never synced")
end

----------------------------------------------------------------------
-- Profession / expansion selection
----------------------------------------------------------------------

function P.selectExpansion(eid)
  local state = P.state
  state.expansionID = eid
  state.selectedRecipeID = nil
  state.scrollOffset = 0
  state.scrollTop = 0
  state.expanded = {}
  if eid == "all" then
    P.tree, P.roots = P.buildProfessionTree(state.professionID)
  else
    P.tree, P.roots = P.buildExpansionTree(eid)
  end
  for cid in pairs(P.tree) do state.expanded[cid] = true end
  if P.listScroll then P.listScroll:SetVerticalScroll(0) end
  P.refreshExpansionPills()
  P.refreshList(); P.refreshDetail(); P.refreshFooter()
end

function P.selectProfession(pid)
  local state = P.state
  state.professionID = pid
  state.selectedRecipeID = nil
  state.expanded = {}
  state.scrollOffset = 0
  P.ensureExpansionIndex()
  local expansions = P.expansionsForProfession(pid)
  if P.profName then P.profName:SetText(ns.Catalog.professions[pid].name) end
  if P.profCounts then
    local total = P.professionRecipeCount(pid)
    local craftable = P.professionCraftableCount and P.professionCraftableCount(pid) or 0
    if craftable > 0 then
      P.profCounts:SetText(total .. " recipes · " .. craftable .. " craftable")
    else
      P.profCounts:SetText(total .. " recipes")
    end
  end
  if P.profIconTex and expansions[1] and expansions[1].icon then P.profIconTex:SetTexture(expansions[1].icon) end
  if expansions[1] then
    P.selectExpansion(expansions[1].id)
  else
    state.expansionID = nil
    P.tree, P.roots = {}, {}
    P.refreshExpansionPills(); P.refreshList(); P.refreshDetail(); P.refreshFooter()
  end
end

function P.refreshProfCounts()
  local pid = P.state and P.state.professionID
  if not pid or not P.profCounts then return end
  local total = P.professionRecipeCount(pid)
  local craftable = P.professionCraftableCount and P.professionCraftableCount(pid) or 0
  if craftable > 0 then
    P.profCounts:SetText(total .. " recipes · " .. craftable .. " craftable")
  else
    P.profCounts:SetText(total .. " recipes")
  end
end
