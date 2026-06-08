local _, ns = ...

ns.Comms = {}

local PREFIX = "GRD"

local AceComm, LibSerialize, LibDeflate

local function debug(msg)
  if GuildRecipeDexDB and GuildRecipeDexDB.settings and GuildRecipeDexDB.settings.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD|r " .. msg)
  end
end

local function selfName()
  local n, r = UnitFullName("player")
  return n, r, (n or "") .. "-" .. (r or GetRealmName() or "")
end

local function senderIsMe(sender)
  if not sender or sender == "" then return false end
  local me = UnitName("player")
  if sender == me then return true end
  if me and sender:find("^" .. me .. "%-") then return true end
  return false
end

----------------------------------------------------------------------
-- Encoding
----------------------------------------------------------------------

local function encode(t)
  local s = LibSerialize:Serialize(t)
  local c = LibDeflate:CompressDeflate(s, { level = 5 })
  return LibDeflate:EncodeForWoWAddonChannel(c)
end

local function decode(s)
  local c = LibDeflate:DecodeForWoWAddonChannel(s)
  if not c then return nil end
  local raw = LibDeflate:DecompressDeflate(c)
  if not raw then return nil end
  local ok, t = LibSerialize:Deserialize(raw)
  if not ok then return nil end
  return t
end

----------------------------------------------------------------------
-- Payload builders
----------------------------------------------------------------------

-- HELLO: inventory of every character we have data for + per-profession timestamp.
local function buildHello()
  local chars = {}
  local db = GuildRecipeDexDB
  if db and db.characters then
    for charKey, c in pairs(db.characters) do
      if c.professions then
        local cp = {}
        local any
        for sid, p in pairs(c.professions) do
          local count = 0
          for _ in pairs(p.recipes or {}) do count = count + 1 end
          cp[sid] = { ts = p.scannedAt or 0, c = count }
          any = true
        end
        if any then
          chars[charKey] = { n = c.name, r = c.realm, cl = c.class, own = c.own or nil, p = cp }
        end
      end
    end
  end
  return { t = "H", chars = chars }
end

-- DATA: full recipe-ID set for one character's profession.
local function buildData(charKey, skillLineID)
  local db = GuildRecipeDexDB
  local c = db and db.characters and db.characters[charKey]
  if not c then return nil end
  local p = c.professions and c.professions[skillLineID]
  if not p then return nil end
  local ids = {}
  for rid in pairs(p.recipes or {}) do ids[#ids + 1] = rid end
  return {
    t = "D",
    ck = charKey, n = c.name, r = c.realm, cl = c.class, own = c.own or nil,
    sid = skillLineID,
    ts = p.scannedAt or 0,
    pn = p.name, rank = p.rank, max = p.maxRank,
    ids = ids,
  }
end

----------------------------------------------------------------------
-- Send helpers
----------------------------------------------------------------------

function ns.Comms:SendGuild(payload)
  if not IsInGuild() then return end
  self:SendCommMessage(PREFIX, encode(payload), "GUILD")
end

function ns.Comms:SendWhisper(target, payload)
  self:SendCommMessage(PREFIX, encode(payload), "WHISPER", target)
end

----------------------------------------------------------------------
-- Receive handlers
----------------------------------------------------------------------

local function handleHello(self, sender, hello)
  if not hello.chars then return end
  local db = GuildRecipeDexDB
  local _, _, myCharKey = selfName()
  for charKey, peerChar in pairs(hello.chars) do
    local myChar = db.characters and db.characters[charKey]
    if peerChar.own and myChar and not myChar.own then
      myChar.own = true
    end
    for sid, peerProf in pairs(peerChar.p or {}) do
      local myTs = (myChar and myChar.professions and myChar.professions[sid] and myChar.professions[sid].scannedAt) or 0
      local peerTs = peerProf.ts or 0
      if peerTs > myTs then
        -- Peer has fresher data for some character; ask for it.
        ns.Comms:SendWhisper(sender, { t = "R", ck = charKey, sid = sid })
      elseif myTs > peerTs and charKey == myCharKey then
        -- We have fresher data for our OWN character; offer it.
        local payload = buildData(charKey, sid)
        if payload then ns.Comms:SendWhisper(sender, payload) end
      end
    end
  end
end

local function handleReq(self, sender, req)
  if not req.ck or not req.sid then return end
  local payload = buildData(req.ck, req.sid)
  if payload then ns.Comms:SendWhisper(sender, payload) end
end

local function handleData(self, sender, data)
  if not data.ck or not data.sid then return end
  local db = GuildRecipeDexDB
  db.characters = db.characters or {}
  local _, _, myCharKey = selfName()
  -- Never accept overwrite of our own character's data via sync.
  if data.ck == myCharKey then return end

  local c = db.characters[data.ck] or {}
  c.name = data.n or c.name
  c.realm = data.r or c.realm
  c.class = data.cl or c.class
  -- Preserve or adopt the own-alt flag: keep it if already set locally,
  -- or accept it from the sender (they know their own alts).
  if c.own or data.own then c.own = true end
  c.professions = c.professions or {}
  local existing = c.professions[data.sid]
  if existing and (existing.scannedAt or 0) >= (data.ts or 0) then return end
  local recipes = {}
  for _, rid in ipairs(data.ids or {}) do recipes[rid] = true end
  c.professions[data.sid] = {
    name = data.pn,
    rank = data.rank,
    maxRank = data.max,
    scannedAt = data.ts or 0,
    recipes = recipes,
    synced = true,
  }
  db.characters[data.ck] = c
  debug(("synced %s's %s: %d recipes (from %s)"):format(data.n or "?", data.pn or "?", #(data.ids or {}), sender))
end

function ns.Comms:OnReceive(prefix, message, channel, sender)
  if prefix ~= PREFIX then return end
  if senderIsMe(sender) then return end
  local payload = decode(message)
  if not payload then debug("comms: decode failed from " .. tostring(sender)); return end
  if payload.t == "H" then handleHello(self, sender, payload)
  elseif payload.t == "R" then handleReq(self, sender, payload)
  elseif payload.t == "D" then handleData(self, sender, payload)
  end
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ns.Comms:BroadcastHello()
  if not IsInGuild() then debug("comms: not in guild"); return end
  self:SendGuild(buildHello())
  debug("sent HELLO")
end

-- Called by Scanner after a successful change to push fresh data.
function ns.Comms:AnnounceChange(charKey, skillLineID)
  if not IsInGuild() then return end
  local payload = buildData(charKey, skillLineID)
  if payload then self:SendGuild(payload) end
end

function ns.Comms:Init()
  AceComm = LibStub("AceComm-3.0", true)
  LibSerialize = LibStub("LibSerialize", true)
  LibDeflate = LibStub("LibDeflate", true)
  if not AceComm or not LibSerialize or not LibDeflate then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD|r comms: missing libs, sync disabled")
    return
  end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  AceComm:Embed(self)
  self:RegisterComm(PREFIX, "OnReceive")
  -- Delay HELLO so guild data is fully loaded.
  C_Timer.After(10, function() self:BroadcastHello() end)
end
