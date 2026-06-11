local _, ns = ...

ns.Comms = {}

local PREFIX = "GRD"
local PROTO = 1   -- wire protocol version; bump when the payload shape changes

local AceComm, LibSerialize, LibDeflate

local function debug(msg) ns.Debug:Log("comms", msg) end

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

-- Returns the decoded table, or (nil, stage) naming which step failed so a
-- decode error actually tells us something:
--   "channel"     bytes aren't WoW-addon-channel safe → foreign/garbled traffic
--   "decompress"  not valid deflate → different compression / corruption
--   "deserialize" valid deflate but not a readable LibSerialize stream →
--                 incompatible LibSerialize version between peers
local function decode(s)
  local c = LibDeflate:DecodeForWoWAddonChannel(s)
  if not c then return nil, "channel" end
  local raw = LibDeflate:DecompressDeflate(c)
  if not raw then return nil, "decompress" end
  local ok, t = LibSerialize:Deserialize(raw)
  if not ok then return nil, "deserialize" end
  return t
end

----------------------------------------------------------------------
-- Payload builders
----------------------------------------------------------------------

-- HELLO: inventory of every character we have data for + per-profession timestamp.
local function buildHello()
  local chars = {}
  local db = GuildRecipeDexDB
  local myGuild = db and db.playerGuild
  if db and db.characters then
    for charKey, c in pairs(db.characters) do
      local relevant = c.own or (myGuild and c.guildName == myGuild)
      if relevant and c.professions then
        local cp = {}
        local any
        for sid, p in pairs(c.professions) do
          local count = 0
          for _ in pairs(p.recipes or {}) do count = count + 1 end
          cp[sid] = { ts = p.scannedAt or 0, c = count, sg = p.sourceGuild and true or nil }
          any = true
        end
        if any then
          chars[charKey] = {
            n = c.name, r = c.realm, cl = c.class,
            own = c.own or nil, fa = c.faction or nil,
            gn = c.guildName or nil, gr = c.guildRealm or nil,
            p = cp,
          }
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
    ck = charKey, n = c.name, r = c.realm, cl = c.class, own = c.own or nil, fa = c.faction or nil,
    gn = c.guildName or nil, gr = c.guildRealm or nil,
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
  payload.v = PROTO
  self:SendCommMessage(PREFIX, encode(payload), "GUILD")
end

function ns.Comms:SendWhisper(target, payload)
  payload.v = PROTO
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
    if myChar then
      if peerChar.own and not myChar.own then myChar.own = true end
      if peerChar.fa and not myChar.faction then myChar.faction = peerChar.fa end
      if peerChar.gn and not myChar.guildName then myChar.guildName = peerChar.gn end
      if peerChar.gr and not myChar.guildRealm then myChar.guildRealm = peerChar.gr end
    end
    for sid, peerProf in pairs(peerChar.p or {}) do
      local myProf = myChar and myChar.professions and myChar.professions[sid]
      local myTs   = (myProf and myProf.scannedAt) or 0
      local mySG   = myProf and myProf.sourceGuild
      local peerTs = peerProf.ts or 0
      local peerSG = peerProf.sg
      local myEff   = mySG   and 0 or myTs
      local peerEff = peerSG and 0 or peerTs
      if peerEff > myEff then
        ns.Comms:SendWhisper(sender, { t = "R", ck = charKey, sid = sid })
      elseif myEff > peerEff then
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

local function handleSources(self, sender, msg)
  if not msg.s then return end
  local db = GuildRecipeDexDB
  db.sources = db.sources or {}
  local added = 0
  for rid, txt in pairs(msg.s) do
    if not db.sources[rid] and type(txt) == "string" and txt ~= "" then
      db.sources[rid] = txt
      added = added + 1
    end
  end
  if added > 0 then debug(("merged %d source texts from %s"):format(added, sender)) end
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
  if data.fa and not c.faction then c.faction = data.fa end
  if data.gn and not c.guildName then c.guildName = data.gn end
  if data.gr and not c.guildRealm then c.guildRealm = data.gr end
  c.professions = c.professions or {}
  local existing = c.professions[data.sid]
  if existing and not existing.sourceGuild and not existing.synced then return end
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
  local payload, stage = decode(message)
  if not payload then
    -- The stage tells us the cause: "channel" = foreign/garbled traffic on the
    -- short "GRD" prefix; "deserialize" = a peer on an incompatible LibSerialize
    -- (i.e. an out-of-date addon build); "decompress" = corruption/truncation.
    ns.Debug:Warn("comms", ("decode failed from %s — %d bytes on %s — stage=%s")
      :format(tostring(sender), #(message or ""), tostring(channel), tostring(stage)))
    return
  end
  if payload.v ~= PROTO then
    -- Benign (their messages still decode) and repetitive, so warn once per peer.
    self._skewWarned = self._skewWarned or {}
    if not self._skewWarned[sender] then
      self._skewWarned[sender] = true
      ns.Debug:Warn("comms", ("version skew from %s: their proto=%s, ours=%d (handling anyway)")
        :format(tostring(sender), tostring(payload.v), PROTO))
    end
  end
  ns.Debug:Safe("comms:" .. tostring(payload.t), function()
    if payload.t == "H" then handleHello(self, sender, payload)
    elseif payload.t == "R" then handleReq(self, sender, payload)
    elseif payload.t == "D" then handleData(self, sender, payload)
    elseif payload.t == "S" then handleSources(self, sender, payload)
    else ns.Debug:Warn("comms", ("unknown payload type %q from %s"):format(tostring(payload.t), tostring(sender)))
    end
  end)
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function ns.Comms:BroadcastHello()
  if not IsInGuild() then debug("comms: not in guild"); return end
  self:SendGuild(buildHello())
  debug("sent HELLO")
end

function ns.Comms:BroadcastSources(newSources)
  if not IsInGuild() then return end
  if not newSources or not next(newSources) then return end
  self:SendGuild({ t = "S", s = newSources })
  debug(("broadcast %d source texts"):format((function() local n=0; for _ in pairs(newSources) do n=n+1 end; return n end)()))
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
    ns.Debug:Error("comms", "missing libs (AceComm/LibSerialize/LibDeflate), sync disabled")
    return
  end
  C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
  AceComm:Embed(self)
  self:RegisterComm(PREFIX, "OnReceive")
  -- Delay HELLO so guild data is fully loaded.
  C_Timer.After(10, function() self:BroadcastHello() end)
end
