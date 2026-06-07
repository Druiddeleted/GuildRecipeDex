local _, ns = ...
local P = ns.UIPriv
local ROW_HEIGHT, VISIBLE_ROWS, LIST_WIDTH = P.ROW_HEIGHT, P.VISIBLE_ROWS, P.LIST_WIDTH

----------------------------------------------------------------------
-- Build frame
----------------------------------------------------------------------

local function buildFrame()
  local frame = CreateFrame("Frame", "GuildRecipeDexFrame", UIParent, "PortraitFrameTemplate")
  P.frame = frame
  frame:SetSize(740, 560)
  frame:SetPoint("CENTER")
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetFrameStrata("HIGH")
  frame:Hide()
  tinsert(UISpecialFrames, "GuildRecipeDexFrame")
  if frame.TitleContainer and frame.TitleContainer.TitleText then
    frame.TitleContainer.TitleText:SetText("GuildRecipeDex")
  elseif frame.TitleText then
    frame.TitleText:SetText("GuildRecipeDex")
  end
  if frame.SetPortraitToAsset then frame:SetPortraitToAsset("Interface\\Icons\\Trade_Engineering") end

  local profDropdown = CreateFrame("Frame", "GuildRecipeDexProfDropdown", frame, "UIDropDownMenuTemplate")
  P.profDropdown = profDropdown
  profDropdown:SetPoint("TOPLEFT", frame, "TOPLEFT", -4, -28)
  UIDropDownMenu_SetWidth(profDropdown, 130)
  UIDropDownMenu_Initialize(profDropdown, P.initProfDropdown)
  UIDropDownMenu_SetText(profDropdown, "Select profession")

  local expansionDropdown = CreateFrame("Frame", "GuildRecipeDexExpDropdown", frame, "UIDropDownMenuTemplate")
  P.expansionDropdown = expansionDropdown
  expansionDropdown:SetPoint("LEFT", profDropdown, "RIGHT", -8, 0)
  UIDropDownMenu_SetWidth(expansionDropdown, 170)
  UIDropDownMenu_Initialize(expansionDropdown, P.initExpansionDropdown)
  UIDropDownMenu_SetText(expansionDropdown, "Expansion")

  local searchBox = CreateFrame("EditBox", "GuildRecipeDexSearch", frame, "SearchBoxTemplate")
  searchBox:SetPoint("LEFT", expansionDropdown, "RIGHT", 4, 2)
  searchBox:SetSize(160, 20)
  searchBox:SetScript("OnTextChanged", function(self)
    SearchBoxTemplate_OnTextChanged(self)
    P.state.search = self:GetText() or ""
    P.state.selectedRecipeID = nil
    P.state.scrollOffset = 0
    P.refreshList(); P.refreshDetail()
  end)

  local listInset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  listInset:SetPoint("TOPLEFT", 8, -56)
  listInset:SetPoint("BOTTOMLEFT", 8, 8)
  listInset:SetWidth(LIST_WIDTH + 24)

  local listScroll = CreateFrame("ScrollFrame", "GuildRecipeDexListScroll", listInset, "UIPanelScrollFrameTemplate")
  P.listScroll = listScroll
  listScroll:SetPoint("TOPLEFT", 4, -4)
  listScroll:SetPoint("BOTTOMRIGHT", -24, 4)
  local listChild = CreateFrame("Frame", nil, listScroll)
  P.listChild = listChild
  listChild:SetSize(LIST_WIDTH, VISIBLE_ROWS * ROW_HEIGHT)
  listScroll:SetScrollChild(listChild)
  listScroll:SetScript("OnVerticalScroll", function(self, off)
    self:SetVerticalScroll(off)
    P.state.scrollOffset = math.floor(off / ROW_HEIGHT + 0.5)
    P.refreshList()
  end)

  -- Row pool grows on demand inside refreshList via makeRow.

  local detail = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  P.detail = detail
  detail:SetPoint("TOPLEFT", listInset, "TOPRIGHT", 4, 0)
  detail:SetPoint("BOTTOMRIGHT", -8, 8)

  local headerHover = CreateFrame("Button", nil, detail)
  headerHover:SetPoint("TOPLEFT", 8, -8)
  headerHover:SetPoint("TOPRIGHT", -8, -8)
  headerHover:SetHeight(64)
  local detailIcon = headerHover:CreateTexture(nil, "ARTWORK")
  P.detailIcon = detailIcon
  detailIcon:SetSize(56, 56)
  detailIcon:SetPoint("LEFT", 4, 0)
  detailIcon:Hide()

  local detailName = headerHover:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  P.detailName = detailName
  detailName:SetPoint("LEFT", detailIcon, "RIGHT", 10, 0)
  detailName:SetPoint("RIGHT", -4, 0)
  detailName:SetJustifyH("LEFT")
  detailName:SetWordWrap(false)

  headerHover:SetScript("OnEnter", function(self)
    if P.state.selectedRecipeID then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetSpellByID(P.state.selectedRecipeID)
      GameTooltip:Show()
    end
  end)
  headerHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  headerHover:SetScript("OnClick", function()
    P.tryInsertRecipeLink(P.state.selectedRecipeID)
  end)

  -- "Track Recipe" checkbox, mirroring the profession book. Tracks the recipe
  -- in the objective tracker via C_TradeSkillUI (recipeID is the spell ID).
  local trackCheck = CreateFrame("CheckButton", "GuildRecipeDexTrackCheck", headerHover, "UICheckButtonTemplate")
  P.trackCheck = trackCheck
  trackCheck:SetSize(24, 24)
  trackCheck:SetPoint("BOTTOMLEFT", detailIcon, "BOTTOMRIGHT", 6, 0)
  local trackLabel = _G[trackCheck:GetName() .. "Text"]
  if trackLabel then trackLabel:SetText("Track Recipe") end
  trackCheck:Hide()
  trackCheck:SetScript("OnClick", function(self)
    local rid = P.state.selectedRecipeID
    if not rid or not (C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked) then return end
    C_TradeSkillUI.SetRecipeTracked(rid, self:GetChecked(), false)
  end)

  -- Scrollable content region for everything below the fixed header. Expanded
  -- reagent lists can exceed the pane height, so this scrolls rather than
  -- overflowing the bottom of the window.
  local detailScroll = CreateFrame("ScrollFrame", "GuildRecipeDexDetailScroll", detail, "UIPanelScrollFrameTemplate")
  P.detailScroll = detailScroll
  detailScroll:SetPoint("TOPLEFT", headerHover, "BOTTOMLEFT", 0, -6)
  detailScroll:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -28, 8)
  local detailContent = CreateFrame("Frame", nil, detailScroll)
  P.detailContent = detailContent
  detailContent:SetSize(360, 1)
  detailScroll:SetScrollChild(detailContent)
  detailScroll:EnableMouseWheel(true)
  detailScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    local new = math.min(math.max(self:GetVerticalScroll() - delta * 24, 0), range)
    self:SetVerticalScroll(new)
  end)

  detail.headerRequired = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  detail.headerRequired:SetText("Reagents"); detail.headerRequired:Hide()
  detail.headerModifying = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  detail.headerModifying:SetText("Optional"); detail.headerModifying:Hide()
  detail.headerFinishing = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  detail.headerFinishing:SetText("Finishing"); detail.headerFinishing:Hide()

  P.reagentsHeader = detail.headerRequired  -- legacy alias, used by refreshDetail empty branch

  -- Source / "Recipe Unlearned" section (shown above reagents when the current
  -- character doesn't know the recipe).
  P.sourceHeader = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  P.sourceHeader:Hide()
  P.sourceText = detailContent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  P.sourceText:SetJustifyH("LEFT")
  P.sourceText:Hide()

  P.craftersHeader = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  P.craftersHeader:SetText("Crafters"); P.craftersHeader:Hide()

  P.craftersText = detailContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  P.craftersText:SetJustifyH("LEFT")

  P.noCraftersText = detailContent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  P.noCraftersText:SetText("Nobody known can craft this yet."); P.noCraftersText:Hide()
end

function ns.UI:Init()
  buildFrame()
end

function ns.UI:Toggle()
  local frame = P.frame
  if not frame then return end
  if frame:IsShown() then
    frame:Hide()
  else
    if not P.state.professionID then
      -- Prefer a profession the player actually has scanned data for.
      local db = GuildRecipeDexDB
      if db and db.characters then
        for _, char in pairs(db.characters) do
          for sid in pairs(char.professions or {}) do
            if ns.Catalog.professions and ns.Catalog.professions[sid] then
              P.selectProfession(sid); break
            end
          end
          if P.state.professionID then break end
        end
      end
      if not P.state.professionID then
        local list = P.professionsList()
        if list[1] then P.selectProfession(list[1].id) end
      end
    else
      P.refreshList(); P.refreshDetail()
    end
    UIDropDownMenu_Initialize(P.profDropdown, P.initProfDropdown)
    frame:Show()
  end
end
