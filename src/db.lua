local _, ns = ...

ns.DB = {}

function ns.DB:Init()
  GuildRecipeDexDB = GuildRecipeDexDB or {}
  local db = GuildRecipeDexDB
  db.characters = db.characters or {}
  db.guild = db.guild or {}
  db.settings = db.settings or { debug = false }
  -- [recipeID] = source text from C_TradeSkillUI.GetRecipeSourceText, cached so
  -- it survives after the relevant profession window is closed.
  db.sources = db.sources or {}
  self.root = db
end

local function charKey()
  local name, realm = UnitFullName("player")
  return (realm or GetRealmName()) .. "-" .. name
end

function ns.DB:CharKey()
  return charKey()
end

function ns.DB:RefreshPlayerContext()
  local db = self.root
  -- Connected realms (realm-group). GetAutoCompleteRealms may be nil on some builds.
  local realms = {}
  if GetAutoCompleteRealms then
    for _, r in ipairs(GetAutoCompleteRealms() or {}) do
      if r and r ~= "" then realms[r] = true end
    end
  end
  local myRealm = GetRealmName and GetRealmName()
  if myRealm then realms[myRealm] = true end
  db.connectedRealms = realms
  -- Faction
  db.playerFaction = UnitFactionGroup and UnitFactionGroup("player") or nil
  local guildName, _, _, guildHomeRealm = GetGuildInfo and GetGuildInfo("player")
  db.playerGuild = guildName or nil
  db.playerGuildRealm = guildName and (guildHomeRealm or myRealm) or nil
  local P = ns.UIPriv
  if P and P.invalidateCrafterCounts then P.invalidateCrafterCounts() end
end

function ns.DB:GetCharacter()
  local key = charKey()
  local c = self.root.characters[key]
  if not c then
    c = { name = UnitName("player"), realm = GetRealmName(), class = select(2, UnitClass("player")), professions = {} }
    self.root.characters[key] = c
  end
  c.own = true  -- distinguishes your own characters (you/alts) from guild members
  c.guid = UnitGUID and UnitGUID("player") or c.guid
  c.faction = UnitFactionGroup and UnitFactionGroup("player") or nil
  local gn, _, _, gnRealm = GetGuildInfo and GetGuildInfo("player")
  c.guildName = gn or nil
  c.guildRealm = gn and (gnRealm or (GetRealmName and GetRealmName())) or nil
  return c
end

function ns.DB:SetProfession(skillLineID, info)
  local c = self:GetCharacter()
  c.professions[skillLineID] = info
end

function ns.DB:DiffRoster()
  local db = self.root
  local myGuild = db.playerGuild
  local myGuildRealm = db.playerGuildRealm
  if not myGuild then return end
  local currentNames = {}
  local guidToName = {}
  local n = GetNumGuildMembers and GetNumGuildMembers() or 0
  for i = 1, n do
    local fullName, _, _, _, _, _, _, _, _, _, _, _, _, _, _, _, guid = GetGuildRosterInfo and GetGuildRosterInfo(i)
    if fullName then
      local name = fullName:match("^([^%-]+)")
      if name then
        currentNames[name:lower()] = true
        if guid and guid ~= "" then guidToName[guid] = name end
      end
    end
  end
  for key, c in pairs(db.characters or {}) do
    if not c.own and c.guildName == myGuild and c.guildRealm == myGuildRealm then
      if c.name and not currentNames[c.name:lower()] then
        local newName = c.guid and guidToName[c.guid]
        if newName then
          c.name = newName
        else
          c.guildName = nil
          c.guildRealm = nil
        end
      end
    end
    if c.name and not c.guid then
      local lname = c.name:lower()
      for guid, rname in pairs(guidToName) do
        if rname:lower() == lname then c.guid = guid; break end
      end
    end
  end
  -- Invalidate crafter counts cache so UI reflects the change
  local P = ns.UIPriv
  if P and P.invalidateCrafterCounts then P.invalidateCrafterCounts() end
end
