local _, ns = ...
local P = ns.UIPriv
local T = ns.UITheme
local WHITE = "Interface\\Buttons\\WHITE8X8"

local CARDW = 406           -- card width (≈ detail content width, left column)
local PADX = 14             -- card inner horizontal padding
local HEADER = 36           -- header height inside a card
local ROWH = 34             -- reagent row height

----------------------------------------------------------------------
-- Small helpers
----------------------------------------------------------------------

-- bags + character bank + reagent bank + Warband (account) bank.
local function owned(itemID) return (GetItemCount and GetItemCount(itemID, true, false, true, true)) or 0 end

local function currencyQty(id)
  local i = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
  return (i and i.quantity) or 0
end

-- Pick a source-type icon from the free-text source string.
local function sourceIconFor(text)
  text = (text or ""):lower()
  if text:find("world drop") then return "gem"
  elseif text:find("drop") or text:find("slain") then return "skull"
  elseif text:find("trainer") or text:find("taught") then return "scroll"
  elseif text:find("quest") or text:find("reward") then return "sparkles"
  elseif text:find("vendor") or text:find("sold") or text:find("purchase") then return "package" end
  return "map-pin"
end

local function setHeaderIcon(tex, lucide, colorKey)
  local a = T.ICON[lucide]
  if a and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(a) then
    tex:SetAtlas(a); tex:Show()
  else
    tex:Hide()
  end
  if colorKey then tex:SetVertexColor(T.rgba(colorKey)) end
end

----------------------------------------------------------------------
-- Card + reagent-row builders
----------------------------------------------------------------------

local function getCard(i)
  local c = P.cards[i]
  if not c then
    c = T.Card(P.detailContent, { fill = "panel", border = "border" })
    c.hicon = T.Icon(c, "flask-conical", 13, "gold"); c.hicon:SetPoint("TOPLEFT", 14, -13)
    c.htitle = T.Text(c, { size = 11, color = "gold" }); c.htitle:SetPoint("LEFT", c.hicon, "RIGHT", 6, 0)
    c.hmeta = T.Text(c, { size = 10, color = "goldFaint" }); c.hmeta:SetPoint("TOPRIGHT", -14, -13)
    P.cards[i] = c
  end
  return c
end

local function makeSlot()
  local slot = CreateFrame("Button", nil, P.detailContent)
  slot.bg = slot:CreateTexture(nil, "BACKGROUND"); slot.bg:SetAllPoints(); slot.bg:SetColorTexture(T.rgba("rowBg"))
  slot.iconFrame = CreateFrame("Frame", nil, slot, "BackdropTemplate")
  slot.iconFrame:SetSize(28, 28); slot.iconFrame:SetPoint("LEFT", 6, 0)
  slot.iconFrame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  slot.iconFrame:SetBackdropColor(T.rgba("iconBg")); slot.iconFrame:SetBackdropBorderColor(T.rgba("borderGold2"))
  slot.icon = slot.iconFrame:CreateTexture(nil, "ARTWORK")
  slot.icon:SetPoint("TOPLEFT", 2, -2); slot.icon:SetPoint("BOTTOMRIGHT", -2, 2); slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  slot.reqFS = T.Text(slot, { size = 12, color = "goldDim", mono = true }); slot.reqFS:SetPoint("RIGHT", -10, 0)
  slot.ownedFS = T.Text(slot, { size = 12, color = "greenBright", mono = true }); slot.ownedFS:SetPoint("RIGHT", slot.reqFS, "LEFT", 0, 0)
  slot.label = T.Text(slot, { size = 12, color = "blue" }); slot.label:SetJustifyH("LEFT"); slot.label:SetWordWrap(false)
  slot.label:SetPoint("LEFT", slot.iconFrame, "RIGHT", 10, 0)
  slot.label:SetPoint("RIGHT", slot.ownedFS, "LEFT", -6, 0)

  slot:SetScript("OnEnter", function(self)
    if self.isCurrency and self.currencyID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetCurrencyByID(self.currencyID); GameTooltip:Show()
    elseif self.itemID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show()
    end
  end)
  slot:SetScript("OnLeave", function() GameTooltip:Hide() end)
  slot:SetScript("OnClick", function(self)
    if IsModifiedClick("CHATLINK") then
      if self.isCurrency and self.currencyID then
        local link = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink and C_CurrencyInfo.GetCurrencyLink(self.currencyID, 0)
        if link then ChatEdit_InsertLink(link) end
      elseif self.itemID then
        local link = self.itemLink or select(2, GetItemInfo(self.itemID))
        if link then ChatEdit_InsertLink(link) end
      end
      return
    end
    if self.expandable and self.slotKey then
      P.reagentExpanded[self.slotKey] = not P.reagentExpanded[self.slotKey]
      P.refreshDetail()
    end
  end)
  return slot
end

-- `id` is an itemID, or currencyID when opts.currency. opts: required, owned,
-- currency, expandable, expanded, slotKey, indent.
local function fillSlot(slot, id, opts)
  opts = opts or {}
  if not id then slot:Hide(); return end
  slot.itemID = nil; slot.currencyID = nil; slot.itemLink = nil
  slot.isCurrency = opts.currency or false
  slot.expandable = opts.expandable or false
  slot.slotKey = opts.slotKey
  slot.icon:SetTexture(134400)
  slot.iconFrame:ClearAllPoints(); slot.iconFrame:SetPoint("LEFT", opts.indent and 22 or 6, 0)
  slot:Show()

  local marker = opts.expandable and (opts.expanded and "  |cffffd200[-]|r" or "  |cffffd200[+]|r") or ""

  local req = opts.required or 0
  if req > 0 then
    local own = opts.owned or 0
    slot.ownedFS:SetText(tostring(own)); slot.ownedFS:SetTextColor(T.rgba(own >= req and "greenBright" or "red"))
    slot.reqFS:SetText(" / " .. req)
  else
    slot.ownedFS:SetText(""); slot.reqFS:SetText("")
  end

  if opts.currency then
    slot.currencyID = id
    local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(id)
    if info and info.iconFileID then slot.icon:SetTexture(info.iconFileID) end
    slot.label:SetTextColor(T.rgba("purple"))
    slot.label:SetText(((info and info.name) or ("Currency " .. id)) .. marker)
    return
  end

  slot.itemID = id
  slot.label:SetTextColor(T.rgba("blue"))
  slot.label:SetText("…")
  local item = Item:CreateFromItemID(id)
  item:ContinueOnItemLoad(function()
    if slot.itemID ~= id then return end
    slot.itemLink = item:GetItemLink()
    slot.icon:SetTexture(item:GetItemIcon() or 134400)
    slot.label:SetText((item:GetItemName() or ("Item " .. id)) .. marker)
  end)
end

----------------------------------------------------------------------
-- Layout (cards stacked in the scrollable detail content)
----------------------------------------------------------------------

local function layoutReagents(buckets, sourceInfo)
  local content = P.detailContent

  for _, s in ipairs(P.reagentSlots) do s:Hide(); s:SetParent(content) end
  for _, c in ipairs(P.cards) do c:Hide() end

  if P.state.selectedRecipeID ~= P.reagentExpandedFor then
    wipe(P.reagentExpanded)
    P.reagentExpandedFor = P.state.selectedRecipeID
    if P.detailScroll then P.detailScroll:SetVerticalScroll(0) end
  end

  local y = 12
  local ci, si = 0, 0
  local function nextSlot()
    si = si + 1
    local s = P.reagentSlots[si]
    if not s then s = makeSlot(); P.reagentSlots[si] = s end
    return s
  end

  local function slotOwned(sd)
    if sd.currency then return currencyQty((sd.options or {})[1]) end
    local total = 0
    for _, it in ipairs(sd.options or {}) do total = total + owned(it) end
    return total
  end

  local function reagentCard(title, iconName, items, meta, metaColor)
    if #items == 0 then return end
    ci = ci + 1
    local card = getCard(ci)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y); card:SetWidth(CARDW)
    setHeaderIcon(card.hicon, iconName, "gold")
    card.htitle:SetText(title)
    card.hmeta:SetText(meta or ""); card.hmeta:SetTextColor(T.rgba(metaColor or "goldFaint"))

    local cy = HEADER
    for idx, sd in ipairs(items) do
      local options = sd.options or {}
      local multi = #options > 1
      local slotKey = title .. ":" .. idx
      local expanded = multi and P.reagentExpanded[slotKey] or false

      local s = nextSlot(); s:SetParent(card)
      s:ClearAllPoints(); s:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); s:SetSize(CARDW - PADX * 2, ROWH)
      fillSlot(s, options[1], {
        required = sd.qty, owned = slotOwned(sd), currency = sd.currency,
        expandable = multi, expanded = expanded, slotKey = slotKey,
      })
      cy = cy + ROWH + 4

      if expanded then
        for _, it in ipairs(options) do
          local so = nextSlot(); so:SetParent(card)
          so:ClearAllPoints(); so:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); so:SetSize(CARDW - PADX * 2, ROWH)
          fillSlot(so, it, {
            required = sd.qty, owned = sd.currency and currencyQty(it) or owned(it),
            currency = sd.currency, indent = true,
          })
          cy = cy + ROWH + 4
        end
      end
    end
    cy = cy + 8
    card:SetHeight(cy); card:Show()
    y = y + cy + 12
  end

  -- A card whose body is a single wrapped fontstring (source / crafters).
  local function textCard(title, iconName, meta, metaColor, fs, fsText, emptyFs)
    ci = ci + 1
    local card = getCard(ci)
    card:ClearAllPoints(); card:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y); card:SetWidth(CARDW)
    setHeaderIcon(card.hicon, iconName, "gold")
    card.htitle:SetText(title)
    card.hmeta:SetText(meta or ""); card.hmeta:SetTextColor(T.rgba(metaColor or "goldFaint"))
    local cy = HEADER
    if fsText and fsText ~= "" then
      if emptyFs then emptyFs:Hide() end
      fs:SetParent(card); fs:ClearAllPoints()
      fs:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); fs:SetWidth(CARDW - PADX * 2)
      fs:SetText(fsText); fs:Show()
      cy = cy + math.max(fs:GetStringHeight() or 14, 14) + 10
    elseif emptyFs then
      fs:Hide()
      emptyFs:SetParent(card); emptyFs:ClearAllPoints()
      emptyFs:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); emptyFs:Show()
      cy = cy + 24
    end
    card:SetHeight(cy); card:Show()
    y = y + cy + 12
  end

  -- Reagents (required) with an "All in bank" badge when fully stocked.
  local allInBank = #buckets.required > 0
  for _, sd in ipairs(buckets.required) do
    if slotOwned(sd) < (sd.qty or 0) then allInBank = false; break end
  end
  reagentCard("REAGENTS", "flask-conical", buckets.required,
    allInBank and "All in bank" or nil, allInBank and "greenBright" or "goldFaint")

  -- Optional (modifying + finishing).
  local optional = {}
  for _, s in ipairs(buckets.modifying) do optional[#optional + 1] = s end
  for _, s in ipairs(buckets.finishing) do optional[#optional + 1] = s end
  reagentCard("OPTIONAL REAGENTS", "puzzle", optional, (#optional .. " slots"))

  if sourceInfo and (sourceInfo.unlearned or sourceInfo.text or sourceInfo.srcItem) then
    local body = (sourceInfo.text and sourceInfo.text ~= "") and sourceInfo.text
      or (sourceInfo.unlearned and "Source unknown — open this profession in-game to fetch it." or nil)
    if sourceInfo.srcItem then
      ci = ci + 1
      local card = getCard(ci)
      card:ClearAllPoints(); card:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -y); card:SetWidth(CARDW)
      setHeaderIcon(card.hicon, sourceIconFor(sourceInfo.text), "gold")
      card.htitle:SetText("SOURCE")
      card.hmeta:SetText(sourceInfo.unlearned and "Not learned" or ""); card.hmeta:SetTextColor(T.rgba("red"))
      local cy = HEADER
      local s = nextSlot(); s:SetParent(card)
      s:ClearAllPoints(); s:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); s:SetSize(CARDW - PADX * 2, ROWH)
      fillSlot(s, sourceInfo.srcItem, { required = 0 })
      cy = cy + ROWH + 4
      if body then
        P.sourceText:SetParent(card); P.sourceText:ClearAllPoints()
        P.sourceText:SetPoint("TOPLEFT", card, "TOPLEFT", PADX, -cy); P.sourceText:SetWidth(CARDW - PADX * 2)
        P.sourceText:SetText(body); P.sourceText:Show()
        cy = cy + math.max(P.sourceText:GetStringHeight() or 14, 14) + 10
      else
        P.sourceText:Hide()
      end
      card:SetHeight(cy); card:Show()
      y = y + cy + 12
    else
      textCard("SOURCE", sourceIconFor(sourceInfo.text),
        sourceInfo.unlearned and "Not learned" or nil, "red", P.sourceText, body, nil)
    end
  else
    P.sourceText:Hide()
  end

  content:SetHeight(y + 8)
end

----------------------------------------------------------------------
-- Refresh
----------------------------------------------------------------------

function P.refreshDetail()
  local state = P.state
  if not state.selectedRecipeID then
    P.detailIcon:Hide(); P.detailName:SetText("")
    for _, chip in ipairs(P.headerBadges or {}) do chip:Hide() end
    for _, s in ipairs(P.reagentSlots) do s:Hide() end
    for _, c in ipairs(P.cards) do c:Hide() end
    P.sourceText:Hide()
    if P.trackCheck then P.trackCheck:Hide() end
    if P.refreshCrafters then P.refreshCrafters() end
    return
  end

  local name, icon, info = P.recipeDisplay(state.selectedRecipeID)
  P.detailIcon:SetTexture(icon); P.detailIcon:Show()
  P.detailName:SetText(name)

  local catRecipe = ns.Catalog and ns.Catalog.recipes and ns.Catalog.recipes[state.selectedRecipeID]
  local outputItem = catRecipe and catRecipe.item
  local badges = {}
  if outputItem and outputItem ~= 0 then
    local _, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = GetItemInfo(outputItem)
    if not quality then
      local rid = state.selectedRecipeID
      local it = Item:CreateFromItemID(outputItem)
      it:ContinueOnItemLoad(function()
        if GuildRecipeDexDB and GuildRecipeDexDB.settings and GuildRecipeDexDB.settings.debug then
          local _, _, q2, _, _, _, _, _, _, _, _, _, _, bt2 = GetItemInfo(outputItem)
          DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD|r item load callback item=" .. outputItem .. " quality=" .. tostring(q2) .. " bindType=" .. tostring(bt2))
        end
        if P.state.selectedRecipeID == rid then P.refreshDetail() end
      end)
    else
      if quality >= 3 then
        local qualNames = { [3]="Rare", [4]="Epic", [5]="Legendary" }
        badges[#badges+1] = { text = qualNames[quality] or "Rare", color = quality >= 4 and "purple" or "blue" }
      end
      local tooltipBonding
      if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        local td = C_TooltipInfo.GetItemByID(outputItem)
        if td and td.lines then
          for _, line in ipairs(td.lines) do
            if line.bonding then tooltipBonding = line.bonding; break end
          end
        end
      end
      if GuildRecipeDexDB and GuildRecipeDexDB.settings and GuildRecipeDexDB.settings.debug then
        DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD|r badge debug item=" .. outputItem .. " bindType=" .. tostring(bindType) .. " tooltipBonding=" .. tostring(tooltipBonding))
      end
      local isWarbound = tooltipBonding == 1 or tooltipBonding == 5
      local isWuE      = tooltipBonding == 9 or tooltipBonding == 10
      local isBoP      = tooltipBonding == 6 or (not tooltipBonding and bindType == 1)
      local isBoE      = tooltipBonding == 7 or (not tooltipBonding and bindType == 2)
      if isWarbound then
        badges[#badges+1] = { text = "Warbound", color = "blue" }
      elseif isWuE then
        badges[#badges+1] = { text = "WuE", color = "blue" }
      elseif isBoP then
        badges[#badges+1] = { text = "BoP", color = "red" }
      elseif isBoE then
        badges[#badges+1] = { text = "BoE", color = "greenBright" }
      end
    end
  end
  -- Apply to P.headerBadges chips
  for i, chip in ipairs(P.headerBadges or {}) do
    local b = badges[i]
    if b then
      chip.label:SetText(b.text)
      chip.label:SetTextColor(T.rgba(b.color))
      chip:SetWidth((chip.label:GetStringWidth() or 20) + 12)
      chip:Show()
    else
      chip:Hide()
    end
  end

  if P.trackCheck then
    if C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked then
      local tracked = C_TradeSkillUI.IsRecipeTracked and C_TradeSkillUI.IsRecipeTracked(state.selectedRecipeID, false)
      P.trackCheck:SetChecked(tracked or false); P.trackCheck:Show()
    else
      P.trackCheck:Hide()
    end
  end

  -- Normalize reagents into 3 buckets. Each: { qty, options = {id,...}, currency }
  local buckets = { required = {}, modifying = {}, finishing = {} }
  local r = info and info.reagents
  if type(r) == "table" then
    if r.required or r.modifying or r.finishing then
      for _, slot in ipairs(r.required or {}) do table.insert(buckets.required, { qty = slot.qty, options = slot.options }) end
      for _, slot in ipairs(r.modifying or {}) do table.insert(buckets.modifying, { qty = slot.qty, options = slot.options }) end
      for _, slot in ipairs(r.finishing or {}) do table.insert(buckets.finishing, { qty = slot.qty, options = slot.options }) end
    else
      for _, e in ipairs(r) do
        if e.itemID then table.insert(buckets.required, { qty = e.qty, options = { e.itemID } }) end
      end
    end
  end

  local catRecipe = ns.Catalog and ns.Catalog.recipes and ns.Catalog.recipes[state.selectedRecipeID]
  local usedFallback = false
  if #buckets.required == 0 and #buckets.modifying == 0 and #buckets.finishing == 0 then
    usedFallback = true
    if catRecipe and catRecipe.reagents then
      local function pull(name)
        for _, slot in ipairs(catRecipe.reagents[name] or {}) do
          table.insert(buckets[name], { qty = slot[1], options = slot[2], currency = slot.c })
        end
      end
      pull("required"); pull("modifying"); pull("finishing")
    end
  end
  if not usedFallback and catRecipe and catRecipe.reagents then
    for _, name in ipairs({ "required", "modifying", "finishing" }) do
      for _, slot in ipairs(catRecipe.reagents[name] or {}) do
        if slot.c then table.insert(buckets[name], { qty = slot[1], options = slot[2], currency = true }) end
      end
    end
  end

  local unlearned = not P.currentCharKnows(state.selectedRecipeID)
  local sourceText = P.recipeSourceText(state.selectedRecipeID)
  local srcItem = (catRecipe and catRecipe.src and catRecipe.src ~= 0) and catRecipe.src or nil

  layoutReagents(buckets, { unlearned = unlearned, text = sourceText, srcItem = srcItem })
  P.refreshCrafters()
end

----------------------------------------------------------------------
-- Crafters column (right side of the detail pane)
----------------------------------------------------------------------

local function makeCrafterRow()
  local row = CreateFrame("Button", nil, P.craftersChild)
  row.bg = row:CreateTexture(nil, "BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetColorTexture(T.rgba("rowBg"))
  row.av = CreateFrame("Frame", nil, row, "BackdropTemplate")
  row.av:SetSize(30, 30); row.av:SetPoint("LEFT", 8, 0)
  row.av:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 2 })
  row.av:SetBackdropColor(T.rgba("borderGold"))
  row.avIcon = row.av:CreateTexture(nil, "ARTWORK")
  row.avIcon:SetPoint("TOPLEFT", 3, -3); row.avIcon:SetPoint("BOTTOMRIGHT", -3, 3)
  row.status = T.Text(row, { size = 9, color = "goldFaint", mono = true }); row.status:SetPoint("TOPRIGHT", -10, -4)
  row.name = T.Text(row, { size = 12, color = "textHi" })
  row.name:SetPoint("TOPLEFT", row.av, "TOPRIGHT", 10, -2); row.name:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
  row.name:SetJustifyH("LEFT"); row.name:SetWordWrap(false)
  row.sub = T.Text(row, { size = 10, color = "goldFaint" })
  row.sub:SetPoint("BOTTOMLEFT", row.av, "BOTTOMRIGHT", 10, 2); row.sub:SetPoint("RIGHT", -10, 0)
  row.sub:SetJustifyH("LEFT"); row.sub:SetWordWrap(false)
  row:SetScript("OnEnter", function(self) self.bg:SetColorTexture(T.rgba("rowSel")) end)
  row:SetScript("OnLeave", function(self)
    if P.state.selectedCrafter ~= self.target then
      self.bg:SetColorTexture(T.rgba("rowBg"))
    end
  end)
  row:SetScript("OnClick", function(self)
    if self.target and self.kind == "guild" then
      P.state.selectedCrafter = self.target
      P.whisperTarget = self.target
      if P.whisperLabel then P.whisperLabel:SetText("Whisper " .. (self.crafterName or "")) end
      if P.whisperBtn then P.whisperBtn:SetAlpha(1) end
      for _, r in ipairs(P.crafterRows) do
        if r:IsShown() then
          r.bg:SetColorTexture(T.rgba(P.state.selectedCrafter == r.target and "rowSel" or "rowBg"))
        end
      end
    end
  end)
  return row
end

local TAG = { you = "<You>", alt = "<Alt>", guild = "<Guild>" }
local TAGCOLOR = { you = "gold", alt = "blue", guild = "purple" }

function P.refreshCrafters()
  local child = P.craftersChild
  if not child then return end
  local rid = P.state.selectedRecipeID
  local list = rid and P.craftersInfoForRecipe(rid) or {}

  local canWhisper = 0
  for _, c in ipairs(list) do if c.kind == "guild" and c.online then canWhisper = canWhisper + 1 end end
  if P.craftersPill then P.craftersPill:SetText(canWhisper .. " can whisper") end

  local f = P.state.crafterFilter or "all"
  for _, tb in ipairs(P.crafterTabs) do
    local on = (tb.tid == f)
    tb:SetBackdropColor(T.rgba(on and "rowSel" or "panelAlt"))
    tb.label:SetTextColor(T.rgba(on and "gold" or "goldDim"))
  end

  local filtered = {}
  for _, c in ipairs(list) do
    if f == "all"
      or (f == "alts" and (c.kind == "alt" or c.kind == "you"))
      or (f == "guild" and c.kind == "guild")
      or (f == "online" and c.online) then
      filtered[#filtered + 1] = c
    end
  end

  -- whisper target: selected crafter if still in filtered list, else first online guild crafter, else first guild crafter.
  local target, targetName
  if P.state.selectedCrafter then
    for _, c in ipairs(filtered) do
      local t = c.name .. "-" .. c.realm
      if t == P.state.selectedCrafter and c.kind == "guild" then
        target = t; targetName = c.name; break
      end
    end
  end
  if not target then
    for _, c in ipairs(filtered) do
      if c.kind == "guild" and c.online then target = c.name .. "-" .. c.realm; targetName = c.name; break end
    end
    if not target then
      for _, c in ipairs(filtered) do
        if c.kind == "guild" then target = c.name .. "-" .. c.realm; targetName = c.name; break end
      end
    end
    P.state.selectedCrafter = target
  end
  P.whisperTarget = target
  if P.whisperLabel then P.whisperLabel:SetText(target and ("Whisper " .. targetName) or "No guild crafter") end
  if P.whisperBtn then P.whisperBtn:SetAlpha(target and 1 or 0.5) end

  local rows = P.crafterRows
  for i = #rows + 1, #filtered do rows[i] = makeCrafterRow() end
  local y = 0
  for i, row in ipairs(rows) do
    local c = filtered[i]
    if not c then
      row:Hide()
    else
      row:Show()
      row.kind = c.kind; row.target = c.name .. "-" .. c.realm; row.crafterName = c.name
      row.bg:SetColorTexture(T.rgba(P.state.selectedCrafter == row.target and "rowSel" or "rowBg"))
      row:ClearAllPoints(); row:SetPoint("TOPLEFT", 0, -y); row:SetPoint("RIGHT", child, "RIGHT", 0, 0); row:SetHeight(44)
      row.av:SetBackdropBorderColor(T.rgba(c.online and "green" or "borderGold2"))
      -- class color + class icon for the avatar; class-colored name
      local cc = c.class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(c.class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[c.class]))
      if cc then row.av:SetBackdropColor(cc.r * 0.35, cc.g * 0.35, cc.b * 0.35)
      else row.av:SetBackdropColor(T.rgba("borderGold")) end
      local coords = c.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[c.class]
      if coords then
        row.avIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        row.avIcon:SetTexCoord(unpack(coords)); row.avIcon:Show()
      else
        row.avIcon:Hide()
      end
      row.name:SetText(c.name)
      if cc then row.name:SetTextColor(cc.r, cc.g, cc.b) else row.name:SetTextColor(T.rgba("textHi")) end
      if c.kind == "you" then row.status:SetText("you")
      elseif c.online then row.status:SetText("now")
      else row.status:SetText(P.shortAgo(c.secs)) end
      local tag = "|cff" .. ({ gold = "e8b963", blue = "a8e0ff", purple = "d78ee6" })[TAGCOLOR[c.kind]] .. (TAG[c.kind] or "") .. "|r"
      local sub = tag .. "  " .. (c.realm or "")
      if c.skill then sub = sub .. "  · Skill " .. c.skill end
      row.sub:SetText(sub)
      y = y + 46
    end
  end
  for i = #filtered + 1, #rows do rows[i]:Hide() end
  child:SetHeight(math.max(y, 1))
end
