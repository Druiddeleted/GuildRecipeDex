local _, ns = ...

ns.GuildScan = {}

local function debug(msg)
  if GuildRecipeDexDB and GuildRecipeDexDB.settings and GuildRecipeDexDB.settings.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD-GS|r " .. msg)
  end
end

-- Hook SetItemRef so we can see the raw link a clicked profession produces.
-- Modern guild panel may or may not route through SetItemRef; instrumented to find out.
local origSetItemRef = SetItemRef
SetItemRef = function(link, text, button, chatFrame)
  if link and (link:find("^trade:") or link:find("^tradeskill:") or link:find("^profession:")) then
    debug("SetItemRef link: " .. link)
    GuildRecipeDexDB._lastTradeLink = { ts = time(), link = link }
  end
  return origSetItemRef(link, text, button, chatFrame)
end

-- Pull every shape of identifier we can from a linked tradeskill view.
local function probeIdentifiers()
  local probe = {}
  if C_TradeSkillUI.GetTradeSkillListLink then
    probe.listLink = C_TradeSkillUI.GetTradeSkillListLink()
  end
  if C_TradeSkillUI.GetBaseProfessionInfo then
    probe.base = C_TradeSkillUI.GetBaseProfessionInfo()
  end
  if C_TradeSkillUI.GetChildProfessionInfo then
    probe.child = C_TradeSkillUI.GetChildProfessionInfo()
  end
  if C_TradeSkillUI.IsTradeSkillLinked then probe.isLinked = C_TradeSkillUI.IsTradeSkillLinked() end
  if C_TradeSkillUI.IsTradeSkillGuild then probe.isGuild = C_TradeSkillUI.IsTradeSkillGuild() end

  -- Communities frame internal state (best-guess paths).
  if CommunitiesFrame then
    probe.cf = {
      selectedClubId = CommunitiesFrame.selectedClubId,
      selectedStreamId = CommunitiesFrame.selectedStreamId,
    }
    if CommunitiesFrame.MemberList and CommunitiesFrame.MemberList.selectedEntryIndex then
      probe.cf.selectedEntryIndex = CommunitiesFrame.MemberList.selectedEntryIndex
    end
    if CommunitiesFrame.GuildMemberDetailFrame then
      probe.cf.detailFrameMember = CommunitiesFrame.GuildMemberDetailFrame.memberInfo and CommunitiesFrame.GuildMemberDetailFrame.memberInfo.name
    end
  end
  -- Some builds use a dedicated guild professions frame.
  for _, name in ipairs({ "CommunitiesGuildProfessionsFrame", "GuildMemberDetailName", "CommunitiesGuildProfessions" }) do
    local g = _G[name]
    if g then
      probe[name] = {
        isShown = g.IsShown and g:IsShown() or false,
        text = (g.GetText and g:GetText()) or nil,
        selectedName = g.selectedName,
        selectedMemberName = g.selectedMemberName,
      }
    end
  end
  return probe
end

-- Parse "Player-realmID-charHex" GUID out of a trade skill link if present.
local function parsePlayerGUIDFromLink(link)
  if not link then return nil end
  return link:match("(Player%-%d+%-%w+)")
end

local function scanLinkedView()
  if not C_TradeSkillUI then return end
  local isLinked, linkedName
  if C_TradeSkillUI.IsTradeSkillLinked then
    isLinked, linkedName = C_TradeSkillUI.IsTradeSkillLinked()
  end
  local isGuild = C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild()
  if not isLinked and not isGuild then return end

  local probe = probeIdentifiers()
  debug(("linked view active (linked=%s guild=%s linkedName=%s)"):format(
    tostring(isLinked), tostring(isGuild), tostring(linkedName)))

  -- IsTradeSkillLinked returns (boolean, playerName) — the wiki was stale.
  -- linkedName is typically a short name ("Bob") for same-realm guildies.
  local crafterName, crafterRealm = linkedName, nil
  if linkedName and linkedName:find("-") then
    crafterName, crafterRealm = linkedName:match("^(.-)%-(.+)$")
  end

  -- Collect learned recipes, including their schematics where available so we
  -- can show full reagent (required + optional + finishing) info for guildie
  -- recipes the local player hasn't learned.
  local function extractReagents(schematic)
    local out = { required = {}, modifying = {}, finishing = {} }
    if not schematic or not schematic.reagentSlotSchematics then return out end
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
      -- Enum.CraftingReagentType: 0=Modifying, 1=Basic, 2=Finishing, 3=Automatic.
      local bucket
      if slot.reagentType == 0 then bucket = out.modifying
      elseif slot.reagentType == 1 then bucket = out.required
      elseif slot.reagentType == 2 then bucket = out.finishing end
      if bucket and slot.reagents and slot.reagents[1] then
        local options = {}
        for _, rg in ipairs(slot.reagents) do
          if rg.itemID then table.insert(options, rg.itemID) end
        end
        if #options > 0 then
          table.insert(bucket, { qty = slot.quantityRequired or 1, options = options })
        end
      end
    end
    return out
  end

  local known = {}
  local count = 0
  for _, rid in ipairs(C_TradeSkillUI.GetAllRecipeIDs() or {}) do
    local r = C_TradeSkillUI.GetRecipeInfo(rid)
    if r and r.learned then
      local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(rid, false)
      known[rid] = {
        name = r.name,
        icon = r.icon,
        categoryID = r.categoryID,
        outputItemID = schematic and schematic.outputItemID or nil,
        reagents = extractReagents(schematic),
      }
      count = count + 1
    end
  end
  debug(("  captured %d learned recipes"):format(count))

  -- Always save a debug record so we can inspect even if name lookup failed.
  GuildRecipeDexDB._lastLinkedCapture = {
    ts = time(),
    probe = probe,
    linkedName = linkedName,
    crafterName = crafterName,
    crafterRealm = crafterRealm,
    recipeCount = count,
    recipeIDs = known,
  }

  -- Persist into db.characters when we know who.
  if crafterName and probe.base and probe.base.professionID then
    local realm = crafterRealm
    if not realm or realm == "" then realm = GetRealmName() end
    local key = realm .. "-" .. crafterName
    GuildRecipeDexDB.characters = GuildRecipeDexDB.characters or {}
    local c = GuildRecipeDexDB.characters[key] or {}
    c.name = crafterName
    c.realm = realm
    local linkGUID = parsePlayerGUIDFromLink(probe.listLink)
    if linkGUID then c.guid = linkGUID end
    if not c.class then
      local rn = GetNumGuildMembers and GetNumGuildMembers() or 0
      for i = 1, rn do
        local rName, _, _, _, _, _, _, _, _, _, rClass = GetGuildRosterInfo(i)
        if rName then
          local rShort = rName:match("^([^%-]+)")
          if rShort and rShort:lower() == crafterName:lower() then
            c.class = rClass; break
          end
        end
      end
    end
    -- Stamp guild context: this person is in our guild (we can only see their
    -- linked profession because they're a guildie).
    local db = GuildRecipeDexDB
    c.guildName = (db and db.playerGuild) or c.guildName
    c.guildRealm = (db and db.playerGuildRealm) or c.guildRealm
    c.professions = c.professions or {}
    c.professions[probe.base.professionID] = {
      name = probe.base.professionName,
      rank = probe.base.skillLevel,
      maxRank = probe.base.maxSkillLevel,
      scannedAt = time(),
      recipes = known,
      synced = false,
      sourceGuild = true,
    }
    GuildRecipeDexDB.characters[key] = c
    debug(("  saved as %s (%s, %d recipes)"):format(key, probe.base.professionName or "?", count))
  else
    debug("  no crafter identified — data NOT saved to characters")
  end
end

function ns.GuildScan:Init()
  local f = CreateFrame("Frame", "GuildRecipeDexGuildScan")
  f:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
  f:RegisterEvent("TRADE_SKILL_SHOW")
  f:SetScript("OnEvent", function()
    C_Timer.After(0.3, scanLinkedView)
  end)
  self.frame = f

  -- Hook every plausible API Blizzard's Communities panel might call to open
  -- a guildie's tradeskill. We log args to SavedVariables so we can inspect
  -- what (if anything) carries the crafter identity.
  GuildRecipeDexDB._apiCalls = {}
  local function logCall(name, ...)
    local args = { ... }
    -- Stringify args for serialization safety.
    for i, v in ipairs(args) do
      if type(v) == "table" then args[i] = "<table>" end
    end
    table.insert(GuildRecipeDexDB._apiCalls, { ts = time(), fn = name, args = args })
    if #GuildRecipeDexDB._apiCalls > 30 then
      table.remove(GuildRecipeDexDB._apiCalls, 1)
    end
    debug(("call %s(%s)"):format(name, table.concat(args, ", ")))
  end
  if C_TradeSkillUI then
    if C_TradeSkillUI.OpenTradeSkill then
      hooksecurefunc(C_TradeSkillUI, "OpenTradeSkill", function(...) logCall("OpenTradeSkill", ...) end)
    end
    if C_TradeSkillUI.SetTradeSkillRecipe then
      hooksecurefunc(C_TradeSkillUI, "SetTradeSkillRecipe", function(...) logCall("SetTradeSkillRecipe", ...) end)
    end
  end
end
