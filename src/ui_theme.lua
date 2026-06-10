local _, ns = ...

-- Design foundation for the redesigned UI (see ui.bck.pen). Centralizes the
-- color palette, fonts, the Lucide-icon -> WoW-atlas mapping, and small builder
-- helpers (cards, icons, text). Everything visual should pull from here so the
-- look stays consistent and tweakable in one place.
local T = {}
ns.UITheme = T

----------------------------------------------------------------------
-- Color palette (hex straight from the .pen design)
----------------------------------------------------------------------

T.hex = {
  appBg       = "#0F1014",  -- window background
  titlebar    = "#1A1410",
  panel       = "#15110D",  -- left pane / cards
  panelAlt    = "#13100C",  -- filter strips
  rightPane   = "#0F0C09",
  rowBg       = "#1A1410",
  rowSel      = "#2A2418",  -- selected / hover row
  inputBg     = "#0B0907",
  iconBg      = "#3A2A1A",  -- reagent icon swatch
  chipOn      = "#1F2A1A",  -- active filter chip
  chipBorder  = "#3A5A2A",

  border      = "#2A2218",
  border2     = "#2E2818",
  borderGold  = "#3A2D1A",
  borderGold2 = "#5A4023",

  gold        = "#E8B963",  -- primary accent / headers
  goldDim     = "#9C8868",
  goldFaint   = "#6E5C40",

  textHi      = "#F5E6C8",  -- primary body text
  text        = "#E0E0E0",
  blue        = "#A8E0FF",  -- reagent / item names
  green       = "#7BC85A",  -- have / craftable
  greenBright = "#9FDB7A",
  red         = "#C04444",  -- missing / drop source
  purple      = "#D78EE6",  -- embellishment / optional
}

-- Parse "#RRGGBB"/"#RRGGBBAA" -> r,g,b,a in 0..1.
local function parseHex(hex)
  hex = hex:gsub("#", "")
  local r = (tonumber(hex:sub(1, 2), 16) or 0) / 255
  local g = (tonumber(hex:sub(3, 4), 16) or 0) / 255
  local b = (tonumber(hex:sub(5, 6), 16) or 0) / 255
  local a = #hex >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) / 255 or 1
  return r, g, b, a
end
T.parseHex = parseHex

-- Resolve a palette key or raw hex to r,g,b,a.
function T.rgba(key)
  return parseHex(T.hex[key] or key)
end

----------------------------------------------------------------------
-- Fonts
----------------------------------------------------------------------
-- The design uses Inter (UI text) and Geist Mono (numbers). Those aren't WoW
-- built-ins; drop Inter.ttf / GeistMono.ttf into Assets/Fonts and flip USE_TTF
-- to true. Until then we fall back to the game's bundled fonts so the UI still
-- renders.

local FONT_DIR = "Interface\\AddOns\\GuildRecipeDex\\Assets\\Fonts\\"
local FALLBACK_UI   = "Fonts\\FRIZQT__.TTF"
local FALLBACK_MONO = "Fonts\\ARIALN.TTF"

local function fontPath(file, fallback)
  local path = FONT_DIR .. file
  local probe = CreateFont("GRDProbe_" .. file)
  if probe and not pcall(probe.SetFont, probe, path, 12) then
    return fallback
  end
  return path
end

T.fontFile = {
  ui   = fontPath("Inter.ttf",    FALLBACK_UI),
  mono = fontPath("GeistMono.ttf", FALLBACK_MONO),
}

----------------------------------------------------------------------
-- Lucide icon -> WoW atlas mapping
----------------------------------------------------------------------
-- The design uses Lucide icons; WoW has no Lucide. Each maps to a WoW atlas (or
-- gets a bundled texture in the art pass). NOTE: these atlas names are
-- best-effort and MUST be verified in-game — an invalid atlas renders nothing.
-- Anything unmapped is hidden by T.Icon (no wrong-icon fallback).

-- Verified against the live atlas set (Blizzard UI source). Lucide glyphs with
-- no clean WoW equivalent are intentionally omitted -> T.Icon hides them rather
-- than showing a wrong icon. (Decorative card-header icons can be blank; their
-- text titles carry the meaning.)
T.ICON = {
  ["search"]        = "common-search-magnifyingglass",
  ["x"]             = "common-icon-redx",
  ["check"]         = "common-icon-checkmark",
  ["plus"]          = "common-icon-plus",
  ["minus"]         = "common-icon-minus",
  ["chevron-down"]  = "friendslist-categorybutton-arrow-down",
  ["chevron-right"] = "friendslist-categorybutton-arrow-right",
  ["refresh-cw"]    = "common-icon-undo",
  ["map-pin"]       = "Waypoint-MapPin-Untracked",
  ["flask-conical"] = "Professions-Icon-Reagents", -- needs in-game verification
  ["puzzle"]        = "Professions-ChatIcon-Quality-Tier5", -- needs in-game verification
  ["skull"]         = "VignetteKill", -- needs in-game verification
  ["scroll"]        = "UI-HUD-MicroMenu-Spellbook-Up", -- needs in-game verification
  ["sparkles"]      = "VignetteEvent", -- needs in-game verification
  ["package"]       = "VignetteLoot", -- needs in-game verification
  ["gem"]           = "poi-islands-azerite", -- needs in-game verification
  ["users"]         = "communities-icon-addmember", -- needs in-game verification
  ["message-square"]= "socialqueuing-icon-chat", -- needs in-game verification
}

----------------------------------------------------------------------
-- Builder helpers
----------------------------------------------------------------------

-- Solid background texture filling `frame`.
function T.fill(frame, key)
  local tex = frame:CreateTexture(nil, "BACKGROUND")
  tex:SetAllPoints()
  tex:SetColorTexture(T.rgba(key))
  return tex
end

-- A card/panel: a frame with a fill and a 1px border. cornerRadius from the
-- design is approximated using pixel-art corner masks.
-- `opts` = { fill=key, border=key, parent=frame }.
function T.Card(parent, opts)
  opts = opts or {}
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
  })
  f:SetBackdropColor(T.rgba(opts.fill or "panel"))
  f:SetBackdropBorderColor(T.rgba(opts.border or "border"))

  -- Pixel-art corner masks to simulate rounded corners
  local maskKey = "appBg"
  if opts.fill == "panel" then maskKey = "rightPane"
  elseif opts.fill == "chipOn" then maskKey = "panel" end
  local r, g, b, a = T.rgba(maskKey)
  
  local function addMask(point, x, y)
    local t = f:CreateTexture(nil, "OVERLAY")
    t:SetSize(1, 1)
    t:SetPoint(point, x, y)
    t:SetColorTexture(r, g, b, a)
  end
  addMask("TOPLEFT", 0, 0)
  addMask("TOPRIGHT", 0, 0)
  addMask("BOTTOMLEFT", 0, 0)
  addMask("BOTTOMRIGHT", 0, 0)

  return f
end

-- An icon texture from a Lucide name, sized and tinted. Atlas names are
-- best-effort (verified in the art pass), so guard against invalid ones: if the
-- atlas doesn't exist the texture stays blank rather than erroring.
function T.Icon(parent, lucideName, size, colorKey)
  local tex = parent:CreateTexture(nil, "ARTWORK")
  tex:SetSize(size or 14, size or 14)
  local atlas = T.ICON[lucideName]
  if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
    tex:SetAtlas(atlas)
  else
    tex:Hide()  -- unmapped / unknown atlas: don't show a wrong icon
  end
  if colorKey then tex:SetVertexColor(T.rgba(colorKey)) end
  return tex
end

-- A FontString. `mono` selects the numeric font. Returns the fontstring.
function T.Text(parent, opts)
  opts = opts or {}
  local fs = parent:CreateFontString(nil, "OVERLAY")
  local font = opts.mono and T.fontFile.mono or T.fontFile.ui
  if not pcall(fs.SetFont, fs, font, opts.size or 12, "") then
    fs:SetFont(opts.mono and FALLBACK_MONO or FALLBACK_UI, opts.size or 12, "")
  end
  fs:SetTextColor(T.rgba(opts.color or "text"))
  if opts.text then fs:SetText(opts.text) end
  if opts.justify then fs:SetJustifyH(opts.justify) end
  return fs
end
