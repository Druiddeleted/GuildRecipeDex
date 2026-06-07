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

function ns.DB:GetCharacter()
  local key = charKey()
  local c = self.root.characters[key]
  if not c then
    c = { name = UnitName("player"), realm = GetRealmName(), class = select(2, UnitClass("player")), professions = {} }
    self.root.characters[key] = c
  end
  return c
end

function ns.DB:SetProfession(skillLineID, info)
  local c = self:GetCharacter()
  c.professions[skillLineID] = info
end
