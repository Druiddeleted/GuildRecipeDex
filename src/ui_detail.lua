local _, ns = ...
local P = ns.UIPriv

----------------------------------------------------------------------
-- Reagent slot rows (item or currency) + layout
----------------------------------------------------------------------

local function makeSlot()
  local parent = P.detailContent or P.detail
  local slot = CreateFrame("Button", nil, parent)
  slot:SetSize(344, 24)
  slot.icon = slot:CreateTexture(nil, "ARTWORK")
  slot.icon:SetSize(22, 22); slot.icon:SetPoint("LEFT", 0, 0)
  slot.count = slot:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  slot.count:SetPoint("BOTTOMRIGHT", slot.icon, "BOTTOMRIGHT", -1, 1)
  slot.label = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  slot.label:SetPoint("LEFT", slot.icon, "RIGHT", 6, 0)
  slot.label:SetPoint("RIGHT", -4, 0)
  slot.label:SetJustifyH("LEFT")
  slot:SetScript("OnEnter", function(self)
    if self.isCurrency and self.currencyID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetCurrencyByID(self.currencyID)
      GameTooltip:Show()
    elseif self.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetItemByID(self.itemID)
      GameTooltip:Show()
    end
  end)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slot:SetScript("OnClick", function(self)
    if IsModifiedClick("CHATLINK") then
      if self.isCurrency and self.currencyID then
        local link = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink
          and C_CurrencyInfo.GetCurrencyLink(self.currencyID, 0)
        if link then ChatEdit_InsertLink(link) end
      elseif self.itemID then
        local link = self.itemLink or select(2, GetItemInfo(self.itemID))
        if link then ChatEdit_InsertLink(link) end
      end
      return
    end
    -- Plain click on a multi-option parent toggles its expanded option list.
    if self.expandable and self.slotKey then
      P.reagentExpanded[self.slotKey] = not P.reagentExpanded[self.slotKey]
      P.refreshDetail()
    end
  end)
  return slot
end

-- Render one reagent row. `id` is an itemID, or a currencyID when opts.currency.
-- opts:
--   expandable/expanded/slotKey -> show a [+]/[-] toggle marker (multi-option parent)
--   indent   -> this is an option sub-row, shift the icon right
--   quality  -> append the crafting-quality star icon (distinguishes R1/R2/R3)
--   currency -> render via C_CurrencyInfo instead of the item APIs (e.g. crests)
local function fillSlot(slot, id, qty, opts)
  opts = opts or {}
  if not id then slot:Hide(); return end
  slot.itemID = nil
  slot.currencyID = nil
  slot.itemLink = nil
  slot.isCurrency = opts.currency or false
  slot.expandable = opts.expandable or false
  slot.slotKey = opts.slotKey
  slot.count:SetText((qty and qty > 0) and qty or "")
  slot.icon:SetTexture(134400)
  slot.icon:ClearAllPoints()
  slot.icon:SetPoint("LEFT", opts.indent and 16 or 0, 0)
  slot:Show()

  local marker = ""
  if opts.expandable then
    marker = opts.expanded and "  |cffffd200[-]|r" or "  |cffffd200[+]|r"
  end

  if opts.currency then
    slot.currencyID = id
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    if info and info.iconFileID then slot.icon:SetTexture(info.iconFileID) end
    slot.label:SetText(((info and info.name) or ("Currency " .. id)) .. marker)
    return
  end

  slot.itemID = id
  slot.label:SetText("...")
  local item = Item:CreateFromItemID(id)
  item:ContinueOnItemLoad(function()
    if slot.itemID ~= id then return end
    slot.itemLink = item:GetItemLink()
    slot.icon:SetTexture(item:GetItemIcon() or 134400)
    local qmarkup = ""
    if opts.quality and C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo then
      local q = C_TradeSkillUI.GetItemReagentQualityByItemInfo(id)
      if q then qmarkup = " " .. CreateAtlasMarkup("Professions-ChatIcon-Quality-Tier" .. q, 16, 16) end
    end
    slot.label:SetText((item:GetItemName() or ("Item " .. id)) .. qmarkup .. marker)
  end)
end

-- Lay out reagents + crafters inside the scrollable content child. Uses
-- absolute Y offsets (not relative chaining) so the running total gives us the
-- exact content height to set on the scroll child.
local function layoutReagents(buckets, craftersCount, sourceInfo)
  local detail = P.detail
  local content = P.detailContent
  local scroll = P.detailScroll
  local reagentSlots = P.reagentSlots

  for _, s in ipairs(reagentSlots) do s:Hide() end
  detail.headerRequired:Hide()
  detail.headerModifying:Hide()
  detail.headerFinishing:Hide()
  P.sourceHeader:Hide()
  P.sourceText:Hide()

  -- Collapse expansions and scroll back to top when the recipe changes.
  if P.state.selectedRecipeID ~= P.reagentExpandedFor then
    wipe(P.reagentExpanded)
    P.reagentExpandedFor = P.state.selectedRecipeID
    if scroll then scroll:SetVerticalScroll(0) end
  end

  local HEADER_H, ROW_H = 18, 24
  local y = 6
  local firstSection = true

  local nextSlotIdx = 1
  local function ensureSlot()
    local s = reagentSlots[nextSlotIdx]
    if not s then s = makeSlot(); reagentSlots[nextSlotIdx] = s end
    nextSlotIdx = nextSlotIdx + 1
    return s
  end

  local function placeHeader(fs)
    if not firstSection then y = y + 12 end
    firstSection = false
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
    fs:Show()
    y = y + HEADER_H + 4
  end

  -- Rows chain at a fixed x; indentation comes purely from the icon offset
  -- inside fillSlot, so option sub-rows align under their parent.
  local function placeRow(row)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
    y = y + ROW_H - 2
  end

  -- Source / "Recipe Unlearned" section (top), mirroring the profession book.
  if sourceInfo and (sourceInfo.unlearned or sourceInfo.text) then
    P.sourceHeader:ClearAllPoints()
    P.sourceHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
    if sourceInfo.unlearned then
      P.sourceHeader:SetText("|cffff4040" .. (TRADESKILL_UNLEARNED_RECIPE_HEADER or "Recipe Unlearned") .. "|r")
    else
      P.sourceHeader:SetText("Source")
    end
    P.sourceHeader:Show()
    y = y + HEADER_H + 4
    firstSection = false
    if sourceInfo.text and sourceInfo.text ~= "" then
      P.sourceText:ClearAllPoints()
      P.sourceText:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
      P.sourceText:SetPoint("RIGHT", content, "RIGHT", -8, 0)
      P.sourceText:SetText(sourceInfo.text)
      P.sourceText:Show()
      y = y + math.max(P.sourceText:GetStringHeight() or 0, 14) + 6
    end
  end

  local sections = {
    { header = detail.headerRequired, items = buckets.required },
    { header = detail.headerModifying, items = buckets.modifying },
    { header = detail.headerFinishing, items = buckets.finishing },
  }
  for _, sec in ipairs(sections) do
    if #sec.items > 0 then
      placeHeader(sec.header)
      for idx, slotData in ipairs(sec.items) do
        local options = slotData.options or {}
        local multi = #options > 1
        local slotKey = (sec.header:GetText() or "?") .. ":" .. idx
        local expanded = multi and P.reagentExpanded[slotKey] or false

        local parent = ensureSlot()
        fillSlot(parent, options[1], slotData.qty, {
          expandable = multi, expanded = expanded, slotKey = slotKey, currency = slotData.currency,
        })
        placeRow(parent)

        if expanded then
          for _, itemID in ipairs(options) do
            local opt = ensureSlot()
            fillSlot(opt, itemID, slotData.qty, { indent = true, quality = true, currency = slotData.currency })
            placeRow(opt)
          end
        end
      end
    end
  end

  -- Crafters section.
  y = y + 12
  P.craftersHeader:ClearAllPoints()
  P.craftersHeader:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -y)
  y = y + HEADER_H + 4
  P.craftersText:ClearAllPoints()
  P.craftersText:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
  P.craftersText:SetPoint("RIGHT", content, "RIGHT", -8, 0)
  P.noCraftersText:ClearAllPoints()
  P.noCraftersText:SetPoint("TOPLEFT", content, "TOPLEFT", 8, -y)
  local lines = (craftersCount and craftersCount > 0) and craftersCount or 1
  y = y + lines * 14

  content:SetHeight(y + 10)
end

function P.refreshDetail()
  local state = P.state
  if not state.selectedRecipeID then
    P.detailIcon:Hide(); P.detailName:SetText("")
    P.reagentsHeader:Hide()
    for _, slot in ipairs(P.reagentSlots) do slot:Hide() end
    P.craftersHeader:Hide(); P.craftersText:SetText("")
    P.noCraftersText:Hide()
    if P.sourceHeader then P.sourceHeader:Hide() end
    if P.sourceText then P.sourceText:Hide() end
    if P.trackCheck then P.trackCheck:Hide() end
    return
  end
  local name, icon, info = P.recipeDisplay(state.selectedRecipeID)
  P.detailIcon:SetTexture(icon); P.detailIcon:Show()
  P.detailName:SetText(name)

  if P.trackCheck then
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
      local tracked = C_TradeSkillUI.IsRecipeTracked and C_TradeSkillUI.IsRecipeTracked(state.selectedRecipeID, false)
      P.trackCheck:SetChecked(tracked or false)
      P.trackCheck:Show()
    else
      P.trackCheck:Hide()
    end
  end

  -- Normalize reagent data from any source into 3 buckets.
  -- Each entry: { qty, options = {id, ...}, currency = bool }
  local buckets = { required = {}, modifying = {}, finishing = {} }
  local r = info and info.reagents
  if type(r) == "table" then
    if r.required or r.modifying or r.finishing then
      -- New structured shape from scanner v3.
      for _, slot in ipairs(r.required or {}) do
        table.insert(buckets.required, { qty = slot.qty, options = slot.options })
      end
      for _, slot in ipairs(r.modifying or {}) do
        table.insert(buckets.modifying, { qty = slot.qty, options = slot.options })
      end
      for _, slot in ipairs(r.finishing or {}) do
        table.insert(buckets.finishing, { qty = slot.qty, options = slot.options })
      end
    else
      -- Legacy flat list { {itemID, qty}, ... }.
      for _, e in ipairs(r) do
        if e.itemID then
          table.insert(buckets.required, { qty = e.qty, options = { e.itemID } })
        end
      end
    end
  end
  -- Fall back to catalog data if nothing scanned.
  local catRecipe = ns.Catalog and ns.Catalog.recipes and ns.Catalog.recipes[state.selectedRecipeID]
  local usedFallback = false
  if #buckets.required == 0 and #buckets.modifying == 0 and #buckets.finishing == 0 then
    usedFallback = true
    if catRecipe and catRecipe.reagents then
      local function pull(name)
        for _, slot in ipairs(catRecipe.reagents[name] or {}) do
          -- slot is { qty, { id, ... }, c = true? }  (c flags a currency slot)
          table.insert(buckets[name], { qty = slot[1], options = slot[2], currency = slot.c })
        end
      end
      pull("required"); pull("modifying"); pull("finishing")
    end
  end

  -- Currency reagent slots (e.g. crest infusion) consume a currency, not an
  -- item, so the scanner never captures them — they exist only in the catalog.
  -- Merge them on top of any scanned item reagents (the fallback above already
  -- includes them when it ran).
  if not usedFallback and catRecipe and catRecipe.reagents then
    for _, name in ipairs({ "required", "modifying", "finishing" }) do
      for _, slot in ipairs(catRecipe.reagents[name] or {}) do
        if slot.c then
          table.insert(buckets[name], { qty = slot[1], options = slot[2], currency = true })
        end
      end
    end
  end

  local crafters = P.craftersForRecipe(state.selectedRecipeID)
  P.craftersHeader:Show()
  if #crafters == 0 then
    P.craftersText:SetText("")
    P.noCraftersText:Show()
  else
    P.noCraftersText:Hide()
    P.craftersText:SetText(table.concat(crafters, "\n"))
  end

  -- Source / unlearned info (mirrors the profession book: source shows for
  -- recipes the current character hasn't learned).
  local unlearned = not P.currentCharKnows(state.selectedRecipeID)
  local sourceText = unlearned and P.recipeSourceText(state.selectedRecipeID) or nil

  layoutReagents(buckets, #crafters, { unlearned = unlearned, text = sourceText })
end
