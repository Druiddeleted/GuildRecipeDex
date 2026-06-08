local _, ns = ...
local P = ns.UIPriv
local T = ns.UITheme
local ROW_HEIGHT, VISIBLE_ROWS, LIST_WIDTH = P.ROW_HEIGHT, P.VISIBLE_ROWS, P.LIST_WIDTH

local WHITE = "Interface\\Buttons\\WHITE8X8"

----------------------------------------------------------------------
-- Build frame (redesign shell: titlebar + left list pane + detail pane).
-- Keeps every widget contract ui_list/ui_detail rely on (P.listChild,
-- P.detailContent, dropdowns, detail header widgets, etc.).
----------------------------------------------------------------------

-- Thin colored edge texture on one side of a frame.
local function edge(parent, side, colorKey)
  local t = parent:CreateTexture(nil, "BORDER")
  t:SetColorTexture(T.rgba(colorKey))
  if side == "right" then
    t:SetPoint("TOPRIGHT"); t:SetPoint("BOTTOMRIGHT"); t:SetWidth(1)
  elseif side == "bottom" then
    t:SetPoint("BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT"); t:SetHeight(1)
  end
  return t
end

local function buildFrame()
  ----------------------------------------------------------------- frame
  local frame = CreateFrame("Frame", "GuildRecipeDexFrame", UIParent, "BackdropTemplate")
  P.frame = frame
  frame:SetSize(1200, 800)
  frame:SetPoint("CENTER")
  frame:SetMovable(true); frame:EnableMouse(true)
  frame:SetFrameStrata("HIGH")
  frame:SetClampedToScreen(true)
  frame:Hide()
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  frame:SetBackdropColor(T.rgba("appBg"))
  frame:SetBackdropBorderColor(T.rgba("borderGold"))
  tinsert(UISpecialFrames, "GuildRecipeDexFrame")

  -------------------------------------------------------------- titlebar
  local titlebar = CreateFrame("Frame", nil, frame)
  titlebar:SetPoint("TOPLEFT", 1, -1)
  titlebar:SetPoint("TOPRIGHT", -1, -1)
  titlebar:SetHeight(44)
  T.fill(titlebar, "titlebar")
  edge(titlebar, "bottom", "border")
  titlebar:EnableMouse(true)
  titlebar:RegisterForDrag("LeftButton")
  titlebar:SetScript("OnDragStart", function() frame:StartMoving() end)
  titlebar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

  local titleIcon = T.Icon(titlebar, "hammer", 16, "gold")
  titleIcon:SetPoint("LEFT", 14, 0)
  local title = T.Text(titlebar, { size = 14, color = "gold", text = "GuildRecipeDex" })
  title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
  local subtitle = T.Text(titlebar, { size = 11, color = "goldFaint", text = "· profession browser" })
  subtitle:SetPoint("LEFT", title, "RIGHT", 8, 0)
  P.titleSubtitle = subtitle  -- updated with recipe counts later

  local close = CreateFrame("Button", nil, titlebar)
  close:SetSize(28, 28); close:SetPoint("RIGHT", -8, 0)
  local closeIcon = T.Icon(close, "x", 14, "goldDim")
  closeIcon:SetPoint("CENTER")
  close:SetScript("OnEnter", function() closeIcon:SetVertexColor(T.rgba("gold")) end)
  close:SetScript("OnLeave", function() closeIcon:SetVertexColor(T.rgba("goldDim")) end)
  close:SetScript("OnClick", function() frame:Hide() end)

  ------------------------------------------------------------------ body
  local body = CreateFrame("Frame", nil, frame)
  body:SetPoint("TOPLEFT", titlebar, "BOTTOMLEFT", 0, 0)
  body:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)

  -------------------------------------------------------------- leftPane
  local leftPane = CreateFrame("Frame", nil, body)
  leftPane:SetPoint("TOPLEFT", 0, 0)
  leftPane:SetPoint("BOTTOMLEFT", 0, 0)
  leftPane:SetWidth(380)
  T.fill(leftPane, "panel")
  edge(leftPane, "right", "border")

  -- search bar (custom dark input) --------------------------------------
  local searchBar = CreateFrame("Frame", nil, leftPane)
  searchBar:SetPoint("TOPLEFT", 0, 0); searchBar:SetPoint("TOPRIGHT", 0, 0); searchBar:SetHeight(46)
  T.fill(searchBar, "titlebar"); edge(searchBar, "bottom", "border")
  local sIn = CreateFrame("Frame", nil, searchBar, "BackdropTemplate")
  sIn:SetPoint("LEFT", 12, 0); sIn:SetPoint("RIGHT", -12, 0); sIn:SetHeight(28)
  sIn:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  sIn:SetBackdropColor(T.rgba("inputBg")); sIn:SetBackdropBorderColor(T.rgba("border2"))
  local sIcon = T.Icon(sIn, "search", 14, "goldDim"); sIcon:SetPoint("LEFT", 8, 0)
  local searchBox = CreateFrame("EditBox", "GuildRecipeDexSearch", sIn)
  P.searchBox = searchBox
  searchBox:SetPoint("LEFT", sIcon, "RIGHT", 6, 0); searchBox:SetPoint("RIGHT", -8, 0); searchBox:SetHeight(24)
  searchBox:SetAutoFocus(false)
  searchBox:SetFont(T.fontFile.ui, 13, ""); searchBox:SetTextColor(T.rgba("textHi"))
  local placeholder = T.Text(sIn, { size = 13, color = "goldFaint", text = "Search recipes, reagents, sources…" })
  placeholder:SetPoint("LEFT", sIcon, "RIGHT", 8, 0)
  P.searchPlaceholder = placeholder
  searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  searchBox:SetScript("OnTextChanged", function(self)
    local txt = self:GetText() or ""
    placeholder:SetShown(txt == "")
    P.state.search = txt
    P.state.selectedRecipeID = nil
    P.state.scrollOffset = 0
    P.refreshList(); P.refreshDetail(); P.refreshFooter()
  end)

  -- profession header (custom selector matching the mock) ---------------
  local profHeader = CreateFrame("Button", nil, leftPane)
  profHeader:SetPoint("TOPLEFT", searchBar, "BOTTOMLEFT", 0, 0)
  profHeader:SetPoint("TOPRIGHT", searchBar, "BOTTOMRIGHT", 0, 0)
  profHeader:SetHeight(48)
  T.fill(profHeader, "titlebar"); edge(profHeader, "bottom", "border")
  local pHov = profHeader:CreateTexture(nil, "HIGHLIGHT")
  pHov:SetAllPoints(); pHov:SetColorTexture(T.rgba("rowSel")); pHov:SetAlpha(0.5)

  local pIconFrame = CreateFrame("Frame", nil, profHeader, "BackdropTemplate")
  pIconFrame:SetSize(32, 32); pIconFrame:SetPoint("LEFT", 12, 0)
  pIconFrame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  pIconFrame:SetBackdropColor(T.rgba("borderGold")); pIconFrame:SetBackdropBorderColor(T.rgba("borderGold2"))
  local pIcon = pIconFrame:CreateTexture(nil, "ARTWORK")
  pIcon:SetPoint("TOPLEFT", 2, -2); pIcon:SetPoint("BOTTOMRIGHT", -2, 2); pIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  P.profIconTex = pIcon

  local pChev = T.Icon(profHeader, "chevron-down", 14, "goldDim"); pChev:SetPoint("RIGHT", -12, 0)

  local pName = T.Text(profHeader, { size = 14, color = "gold" })
  pName:SetPoint("TOPLEFT", pIconFrame, "TOPRIGHT", 10, -1)
  pName:SetPoint("RIGHT", pChev, "LEFT", -8, 0)
  pName:SetJustifyH("LEFT"); pName:SetWordWrap(false); pName:SetText("Select profession")
  P.profName = pName
  local profCounts = T.Text(profHeader, { size = 11, color = "goldFaint" })
  profCounts:SetPoint("BOTTOMLEFT", pIconFrame, "BOTTOMRIGHT", 10, 1)
  P.profCounts = profCounts

  profHeader:SetScript("OnClick", function(self)
    if MenuUtil and MenuUtil.CreateContextMenu then
      MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle("Profession")
        for _, p in ipairs(P.professionsList()) do
          root:CreateButton(p.name, function() P.selectProfession(p.id) end)
        end
      end)
    end
  end)

  -- expansion pills (horizontal scroll, reverse chron) ------------------
  local pillBar = CreateFrame("Frame", nil, leftPane)
  pillBar:SetPoint("TOPLEFT", profHeader, "BOTTOMLEFT", 0, 0)
  pillBar:SetPoint("TOPRIGHT", profHeader, "BOTTOMRIGHT", 0, 0)
  pillBar:SetHeight(38)
  T.fill(pillBar, "panelAlt"); edge(pillBar, "bottom", "border")
  local pillScroll = CreateFrame("ScrollFrame", nil, pillBar)
  pillScroll:SetPoint("TOPLEFT", 10, -6); pillScroll:SetPoint("BOTTOMRIGHT", -10, 6)
  P.expPillScroll = pillScroll
  local pillChild = CreateFrame("Frame", nil, pillScroll)
  pillChild:SetSize(10, 26)
  pillScroll:SetScrollChild(pillChild)
  P.expPillChild = pillChild
  pillScroll:EnableMouseWheel(true)
  pillScroll:SetScript("OnMouseWheel", function(self, delta)
    local maxs = math.max((pillChild:GetWidth() or 0) - (self:GetWidth() or 0), 0)
    self:SetHorizontalScroll(math.min(math.max(self:GetHorizontalScroll() - delta * 40, 0), maxs))
  end)

  -- recipe list ---------------------------------------------------------
  local listScroll = CreateFrame("ScrollFrame", "GuildRecipeDexListScroll", leftPane, "UIPanelScrollFrameTemplate")
  P.listScroll = listScroll
  listScroll:SetPoint("TOPLEFT", pillBar, "BOTTOMLEFT", 4, -4)
  listScroll:SetPoint("BOTTOMRIGHT", leftPane, "BOTTOMRIGHT", -26, 34)
  local listChild = CreateFrame("Frame", nil, listScroll)
  P.listChild = listChild
  listChild:SetSize(336, VISIBLE_ROWS * ROW_HEIGHT)
  listScroll:SetScrollChild(listChild)
  listScroll:SetScript("OnVerticalScroll", function(self, off)
    self:SetVerticalScroll(off)
    P.state.scrollTop = off
    if P.renderVisibleRows then P.renderVisibleRows() end
  end)

  -- footer (counts · last sync · re-sync) -------------------------------
  local footer = CreateFrame("Frame", nil, leftPane)
  footer:SetPoint("BOTTOMLEFT", 0, 0); footer:SetPoint("BOTTOMRIGHT", 0, 0); footer:SetHeight(30)
  T.fill(footer, "titlebar")
  local ftop = footer:CreateTexture(nil, "BORDER")
  ftop:SetColorTexture(T.rgba("border")); ftop:SetPoint("TOPLEFT"); ftop:SetPoint("TOPRIGHT"); ftop:SetHeight(1)
  local footerLeft = T.Text(footer, { size = 10, color = "goldFaint" })
  footerLeft:SetPoint("LEFT", 12, 0)
  P.footerLeft = footerLeft
  local resync = CreateFrame("Button", nil, footer)
  resync:SetSize(20, 20); resync:SetPoint("RIGHT", -10, 0)
  local rIcon = T.Icon(resync, "refresh-cw", 13, "goldDim"); rIcon:SetPoint("CENTER")
  resync:SetScript("OnEnter", function()
    rIcon:SetVertexColor(T.rgba("gold"))
    GameTooltip:SetOwner(resync, "ANCHOR_TOP"); GameTooltip:SetText("Re-sync now"); GameTooltip:Show()
  end)
  resync:SetScript("OnLeave", function() rIcon:SetVertexColor(T.rgba("goldDim")); GameTooltip:Hide() end)
  resync:SetScript("OnClick", function()
    if ns.Scanner and ns.Scanner.ScanCurrent then ns.Scanner:ScanCurrent() end
    if ns.Comms and ns.Comms.BroadcastHello then ns.Comms:BroadcastHello() end
    if P.invalidateCrafterCounts then P.invalidateCrafterCounts() end
    if P.refreshFooter then C_Timer.After(1, P.refreshFooter) end
    if P.refreshProfCounts then C_Timer.After(1, P.refreshProfCounts) end
  end)
  local footerSync = T.Text(footer, { size = 10, color = "goldFaint" })
  footerSync:SetPoint("RIGHT", resync, "LEFT", -8, 0)
  P.footerSync = footerSync

  ------------------------------------------------------------ detailPane
  local detail = CreateFrame("Frame", nil, body)
  P.detail = detail
  detail:SetPoint("TOPLEFT", leftPane, "TOPRIGHT", 0, 0)
  detail:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
  T.fill(detail, "rightPane")

  -- Recipe header (icon + name + track checkbox).
  local headerHover = CreateFrame("Button", nil, detail)
  headerHover:SetPoint("TOPLEFT", 16, -14)
  headerHover:SetPoint("TOPRIGHT", -16, -14)
  headerHover:SetHeight(64)
  edge(headerHover, "bottom", "border")

  local detailIcon = headerHover:CreateTexture(nil, "ARTWORK")
  P.detailIcon = detailIcon
  detailIcon:SetSize(56, 56)
  detailIcon:SetPoint("LEFT", 2, 0)
  detailIcon:Hide()

  local detailName = T.Text(headerHover, { size = 18, color = "textHi" })
  P.detailName = detailName
  detailName:SetPoint("LEFT", detailIcon, "RIGHT", 12, 10)
  detailName:SetPoint("RIGHT", -4, 10)
  detailName:SetJustifyH("LEFT")
  detailName:SetWordWrap(false)

  headerHover:SetScript("OnEnter", function(self)
    if P.state.selectedRecipeID then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
      GameTooltip:SetSpellByID(P.state.selectedRecipeID)
      GameTooltip:Show()
    end
  end)
  headerHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  headerHover:SetScript("OnClick", function()
    P.tryInsertRecipeLink(P.state.selectedRecipeID)
  end)

  local trackCheck = CreateFrame("CheckButton", "GuildRecipeDexTrackCheck", headerHover, "UICheckButtonTemplate")
  P.trackCheck = trackCheck
  trackCheck:SetSize(22, 22)
  trackCheck:SetPoint("BOTTOMLEFT", detailIcon, "BOTTOMRIGHT", 10, -2)
  local trackLabel = _G[trackCheck:GetName() .. "Text"]
  if trackLabel then trackLabel:SetText("Track Recipe"); trackLabel:SetTextColor(T.rgba("goldDim")) end
  trackCheck:Hide()
  trackCheck:SetScript("OnClick", function(self)
    local rid = P.state.selectedRecipeID
    if not rid or not (C_TradeSkillUI and C_TradeSkillUI.SetRecipeTracked) then return end
    C_TradeSkillUI.SetRecipeTracked(rid, self:GetChecked(), false)
  end)

  P.headerBadges = {}
  for i = 1, 3 do
    local chip = T.Card(headerHover, { fill = "chipOn", border = "chipBorder" })
    chip:SetHeight(18)
    if i == 1 then
      chip:SetPoint("BOTTOMRIGHT", -4, 6)
    else
      chip:SetPoint("RIGHT", P.headerBadges[i-1], "LEFT", -4, 0)
    end
    chip.label = T.Text(chip, { size = 10, color = "goldFaint" })
    chip.label:SetPoint("CENTER")
    chip:Hide()
    P.headerBadges[i] = chip
  end

  -- Crafters column (right side of the detail pane) ---------------------
  local cp = T.Card(detail, { fill = "panel", border = "border" })
  cp:SetPoint("TOPRIGHT", headerHover, "BOTTOMRIGHT", 0, -8)
  cp:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -14, 14)
  cp:SetWidth(340)

  local cIcon = T.Icon(cp, "users", 13, "gold"); cIcon:SetPoint("TOPLEFT", 14, -13)
  local cTitle = T.Text(cp, { size = 11, color = "gold", text = "CRAFTERS" }); cTitle:SetPoint("LEFT", cIcon, "RIGHT", 6, 0)
  local cPill = T.Card(cp, { fill = "chipOn", border = "chipBorder" })
  cPill:SetPoint("TOPRIGHT", -12, -10); cPill:SetSize(104, 18)
  P.craftersPill = T.Text(cPill, { size = 10, color = "greenBright" }); P.craftersPill:SetPoint("CENTER")

  local tabRow = CreateFrame("Frame", nil, cp)
  tabRow:SetPoint("TOPLEFT", 12, -34); tabRow:SetPoint("TOPRIGHT", -12, -34); tabRow:SetHeight(22)
  local tabDefs = { { "all", "All" }, { "alts", "Alts" }, { "guild", "Guild" }, { "online", "Online" } }
  local tx = 0
  for _, td in ipairs(tabDefs) do
    local tb = CreateFrame("Button", nil, tabRow, "BackdropTemplate")
    tb:SetHeight(20); tb:SetBackdrop({ bgFile = WHITE })
    tb.label = T.Text(tb, { size = 10, color = "goldDim", text = td[2] }); tb.label:SetPoint("CENTER")
    tb.tid = td[1]
    local w = (tb.label:GetStringWidth() or 20) + 16; tb:SetWidth(w)
    tb:SetPoint("LEFT", tx, 0); tx = tx + w + 4
    tb:SetScript("OnClick", function() P.state.crafterFilter = tb.tid; P.refreshCrafters() end)
    P.crafterTabs[#P.crafterTabs + 1] = tb
  end

  local cScroll = CreateFrame("ScrollFrame", nil, cp, "UIPanelScrollFrameTemplate")
  cScroll:SetPoint("TOPLEFT", 12, -62); cScroll:SetPoint("BOTTOMRIGHT", -26, 48)
  local cChild = CreateFrame("Frame", nil, cScroll); cChild:SetSize(300, 10)
  cScroll:SetScrollChild(cChild)
  P.craftersChild = cChild
  cScroll:EnableMouseWheel(true)
  cScroll:SetScript("OnMouseWheel", function(self, delta)
    local r = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - delta * 30, 0), r))
  end)

  local wb = CreateFrame("Button", nil, cp, "BackdropTemplate")
  wb:SetPoint("BOTTOMLEFT", 12, 12); wb:SetPoint("BOTTOMRIGHT", -12, 12); wb:SetHeight(30)
  wb:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  wb:SetBackdropColor(T.rgba("borderGold")); wb:SetBackdropBorderColor(T.rgba("borderGold2"))
  local wbLabel = T.Text(wb, { size = 12, color = "gold", text = "Whisper" }); wbLabel:SetPoint("CENTER", 9, 0)
  local wbIcon = T.Icon(wb, "message-square", 13, "gold"); wbIcon:SetPoint("RIGHT", wbLabel, "LEFT", -6, 0)
  P.whisperBtn = wb; P.whisperLabel = wbLabel
  wb:SetScript("OnEnter", function() wb:SetBackdropColor(T.rgba("rowSel")) end)
  wb:SetScript("OnLeave", function() wb:SetBackdropColor(T.rgba("borderGold")) end)
  wb:SetScript("OnClick", function() if P.whisperTarget then ChatFrame_SendTell(P.whisperTarget) end end)

  -- Reagents/source scroll (left of the crafters column) ----------------
  local detailScroll = CreateFrame("ScrollFrame", "GuildRecipeDexDetailScroll", detail, "UIPanelScrollFrameTemplate")
  P.detailScroll = detailScroll
  detailScroll:SetPoint("TOPLEFT", headerHover, "BOTTOMLEFT", 0, -8)
  detailScroll:SetPoint("RIGHT", cp, "LEFT", -16, 0)
  detailScroll:SetPoint("BOTTOM", detail, "BOTTOM", 0, 12)
  local detailContent = CreateFrame("Frame", nil, detailScroll)
  P.detailContent = detailContent
  detailContent:SetSize(410, 1)
  detailScroll:SetScrollChild(detailContent)
  detailScroll:EnableMouseWheel(true)
  detailScroll:SetScript("OnMouseWheel", function(self, delta)
    local range = self:GetVerticalScrollRange()
    self:SetVerticalScroll(math.min(math.max(self:GetVerticalScroll() - delta * 24, 0), range))
  end)

  P.sourceText = T.Text(detailContent, { size = 12, color = "textHi" })
  P.sourceText:Hide()
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
    frame:Show()
  end
end
