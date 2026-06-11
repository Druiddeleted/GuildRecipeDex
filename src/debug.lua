local _, ns = ...

-- Lightweight diagnostics. Everything is captured SILENTLY into an in-memory
-- ring buffer (no chat spam) and viewed on demand in a popup via `/grd errors`.
-- Also captures uncaught Lua errors originating in this addon's own files.
-- Especially for local dev builds.

ns.Debug = {}
local D = ns.Debug

local RING_MAX = 300
D.ring = {}

local function stamp()
  return (date and date("%H:%M:%S")) or ""
end

-- Append to the ring. Consecutive identical entries collapse into one with a
-- count, so repetitive failures (decode errors, version skew) don't flood it.
local function push(level, cat, msg)
  local r = D.ring
  local last = r[#r]
  if last and last.level == level and last.cat == cat and last.msg == msg then
    last.count = (last.count or 1) + 1
    last.clock = stamp()
  else
    r[#r + 1] = { clock = stamp(), level = level, cat = cat, msg = msg, count = 1 }
    if #r > RING_MAX then table.remove(r, 1) end
  end
  if D.win and D.win:IsShown() then D:Refresh() end
end

function D:Log(cat, msg)   push("info", cat, msg)  end
function D:Warn(cat, msg)  push("warn", cat, msg)  end
function D:Error(cat, msg) push("error", cat, msg) end

-- Run fn(...) under xpcall, recording any error (with stack) into the ring.
-- Returns fn's first two results on success, or nil on error.
function D:Safe(cat, fn, ...)
  local n = select("#", ...)
  local args = { ... }
  local ok, a, b = xpcall(
    function() return fn(unpack(args, 1, n)) end,
    function(err)
      return tostring(err) .. "\n" .. (debugstack and debugstack(2, 6, 0) or "")
    end
  )
  if ok then return a, b end
  self:Error(cat, a)
  return nil
end

function D:Clear()
  wipe(self.ring)
  if self.win and self.win:IsShown() then self:Refresh() end
end

----------------------------------------------------------------------
-- Popup viewer
----------------------------------------------------------------------

local LEVEL_COLOR = { info = "ff9d9d9d", warn = "ffffd200", error = "ffff5555" }

local function buildWindow()
  local f = CreateFrame("Frame", "GuildRecipeDexDebugFrame", UIParent, "BackdropTemplate")
  f:SetSize(660, 460)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  f:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
  f:SetBackdropBorderColor(0, 0, 0, 1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("GuildRecipeDex — Diagnostics")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local scroll = CreateFrame("ScrollFrame", "GuildRecipeDexDebugScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -38)
  scroll:SetPoint("BOTTOMRIGHT", -34, 44)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetAutoFocus(false)
  edit:SetWidth(600)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  -- Selectable for copy, but discourage accidental edits by repainting on change.
  edit:SetScript("OnTextChanged", function(self, user) if user then D:Refresh() end end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local clear = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  clear:SetSize(90, 22)
  clear:SetText("Clear")
  clear:SetPoint("BOTTOMLEFT", 14, 12)
  clear:SetScript("OnClick", function() D:Clear() end)

  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMRIGHT", -36, 18)
  hint:SetText("drag to move · Esc to close · text is selectable")

  return f
end

function D:Refresh()
  if not self.win then return end
  local lines = {}
  for _, e in ipairs(self.ring) do
    local n = (e.count and e.count > 1) and (" |cff808080x" .. e.count .. "|r") or ""
    local first = e.msg:match("^[^\n]*") or e.msg
    local rest = e.msg:match("\n(.+)$")
    lines[#lines + 1] = ("|cff808080%s|r |c%s%s/%s|r%s  %s")
      :format(e.clock, LEVEL_COLOR[e.level] or "ff9d9d9d", e.level, e.cat, n, first)
    if rest then lines[#lines + 1] = "|cff707070" .. rest .. "|r" end
  end
  local txt = (#lines > 0) and table.concat(lines, "\n")
    or "|cff707070(no entries captured)|r"
  self.win.edit:SetText(txt)
  self.win.edit:SetCursorPosition(0)
end

function D:Toggle()
  if not self.win then self.win = buildWindow() end
  if self.win:IsShown() then
    self.win:Hide()
  else
    self:Refresh()
    self.win:Show()
  end
end

----------------------------------------------------------------------
-- Export (shareable plain-text dump)
----------------------------------------------------------------------

-- Plain text (no color codes), with a metadata header useful for bug reports.
function D:ExportText()
  local ver = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("GuildRecipeDex", "Version")) or "?"
  local _, build, _, tocver = GetBuildInfo()
  local name, realm = UnitFullName("player")
  local lines = {
    "=== GuildRecipeDex diagnostics ===",
    ("addon v%s · WoW %s (interface %s) · %s-%s · %s")
      :format(ver, tostring(build), tostring(tocver), name or "?", realm or (GetRealmName and GetRealmName()) or "?", (date and date()) or ""),
    ("%d entries this session"):format(#self.ring),
    "",
  }
  for _, e in ipairs(self.ring) do
    local n = (e.count and e.count > 1) and (" x" .. e.count) or ""
    lines[#lines + 1] = ("[%s] %s/%s%s  %s"):format(e.clock, e.level, e.cat, n, e.msg)
  end
  return table.concat(lines, "\n")
end

local function buildExportWindow()
  local f = CreateFrame("Frame", "GuildRecipeDexExportFrame", UIParent, "BackdropTemplate")
  f:SetSize(660, 460)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
  f:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
  f:SetBackdropBorderColor(0, 0, 0, 1)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("GuildRecipeDex — Export Log")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", 2, 2)

  local note = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  note:SetPoint("TOPLEFT", 14, -30)
  note:SetText("Press Ctrl+C to copy (text is pre-selected). Also written to SavedVariables\\GuildRecipeDex.lua on /reload or logout.")

  local scroll = CreateFrame("ScrollFrame", "GuildRecipeDexExportScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -48)
  scroll:SetPoint("BOTTOMRIGHT", -34, 16)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetFontObject(ChatFontNormal)
  edit:SetAutoFocus(false)
  edit:SetWidth(600)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  scroll:SetScrollChild(edit)
  f.edit = edit
  return f
end

function D:Export()
  local text = self:ExportText()
  -- Persist to a SavedVariable so there's a real file on disk after reload/logout.
  GuildRecipeDexLog = GuildRecipeDexLog or {}
  GuildRecipeDexLog.exportedAt = (date and date()) or ""
  GuildRecipeDexLog.text = text
  -- Show a copyable popup with everything pre-selected for Ctrl+C.
  if not self.exportWin then self.exportWin = buildExportWindow() end
  local edit = self.exportWin.edit
  edit:SetText(text)
  self.exportWin:Show()
  edit:SetCursorPosition(0)
  edit:SetFocus()
  edit:HighlightText()
  DEFAULT_CHAT_FRAME:AddMessage(("|cff7ec0eeGRD|r exported %d entries — Ctrl+C to copy, or grab SavedVariables\\GuildRecipeDex.lua after /reload"):format(#self.ring))
end

----------------------------------------------------------------------
-- Uncaught-error capture (our files only)
----------------------------------------------------------------------

local prevHandler = geterrorhandler()
seterrorhandler(function(err)
  if type(err) == "string" and err:find("GuildRecipeDex", 1, true) then
    push("error", "lua", err)
  end
  return prevHandler(err)
end)
