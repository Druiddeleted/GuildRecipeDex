local _, ns = ...

ns.Scanner = {}

local SCAN_EVENTS = {
  "TRADE_SKILL_LIST_UPDATE",
  "TRADE_SKILL_SHOW",
  "NEW_RECIPE_LEARNED",
  "SKILL_LINES_CHANGED",
}

local function debugPrint(msg)
  if GuildRecipeDexDB and GuildRecipeDexDB.settings and GuildRecipeDexDB.settings.debug then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGRD|r " .. msg)
  end
end

local lastFingerprint = {}

function ns.Scanner:ScanCurrent()
  if not C_TradeSkillUI then return end
  local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
  local child = C_TradeSkillUI.GetChildProfessionInfo and C_TradeSkillUI.GetChildProfessionInfo()
  local info = child or base
  if not info or not info.professionID or info.professionID == 0 then return end
  if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then return end
  if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then return end

  local skillLineID = (base and base.professionID) or info.professionID
  local profName = (base and base.professionName) or info.professionName or info.parentProfessionName or ("Profession " .. skillLineID)

  local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs() or {}
  local known = {}
  local fingerprintIDs = {}
  for _, rid in ipairs(recipeIDs) do
    local r = C_TradeSkillUI.GetRecipeInfo(rid)
    if r and r.learned then
      -- Store only the known-recipe ID set. Name/icon/category/reagents/output
      -- all live in the baked catalog (ns.Catalog.recipes[rid]); duplicating them
      -- per character bloated SavedVariables ~10x. The UI reads details from the
      -- catalog by ID, and only the keys of this table are ever consumed.
      known[rid] = true
      fingerprintIDs[#fingerprintIDs + 1] = rid
    end
  end

  local fp = #fingerprintIDs
  local sum = 0
  for _, rid in ipairs(fingerprintIDs) do sum = sum + rid end
  local key = skillLineID
  if lastFingerprint[key] and lastFingerprint[key].count == fp and lastFingerprint[key].sum == sum then
    return
  end
  lastFingerprint[key] = { count = fp, sum = sum }

  ns.DB:SetProfession(skillLineID, {
    name = profName,
    rank = info.skillLevel or (base and base.skillLevel),
    maxRank = info.maxSkillLevel or (base and base.maxSkillLevel),
    recipes = known,
    scannedAt = time(),
  })

  debugPrint(("scanned %s: %d known recipes"):format(profName, fp))

  if ns.Comms and ns.Comms.AnnounceChange then
    ns.Comms:AnnounceChange(ns.DB:CharKey(), skillLineID)
  end

  if C_TradeSkillUI.GetRecipeSourceText then
    local db = GuildRecipeDexDB
    db.sources = db.sources or {}
    local newSources = {}
    for _, rid in ipairs(recipeIDs) do
      local ok, txt = pcall(C_TradeSkillUI.GetRecipeSourceText, rid)
      if ok and txt and txt ~= "" then
        if db.sources[rid] ~= txt then
          db.sources[rid] = txt
          newSources[rid] = txt
        end
      end
    end
    if ns.Comms and ns.Comms.BroadcastSources and next(newSources) then
      ns.Comms:BroadcastSources(newSources)
    end
  end
end

function ns.Scanner:LearnRecipe(recipeID)
  if not recipeID or recipeID == 0 then return end
  if not (IsPlayerSpell and IsPlayerSpell(recipeID)) then return end
  local cat = ns.Catalog and ns.Catalog.recipes and ns.Catalog.recipes[recipeID]
  if not cat then return end
  local c = ns.DB:GetCharacter()
  local skillLineID = cat.skillLine
  if not skillLineID or skillLineID == 0 then return end
  c.professions = c.professions or {}
  local prof = c.professions[skillLineID]
  if not prof then
    prof = { name = "Unknown", recipes = {}, scannedAt = time() }
    c.professions[skillLineID] = prof
  end
  if not prof.recipes[recipeID] then
    prof.recipes[recipeID] = true
    prof.scannedAt = time()
    debugPrint(("learned recipe %d in skillLine %d"):format(recipeID, skillLineID))
    if ns.Comms and ns.Comms.AnnounceChange then
      ns.Comms:AnnounceChange(ns.DB:CharKey(), skillLineID)
    end
    local P = ns.UIPriv
    if P and P.invalidateCrafterCounts then P.invalidateCrafterCounts() end
    if P and P.refreshList then P.refreshList() end
    if P and P.refreshDetail then P.refreshDetail() end
  end
end

function ns.Scanner:Init()
  local f = CreateFrame("Frame", "GuildRecipeDexScanner")
  for _, ev in ipairs(SCAN_EVENTS) do f:RegisterEvent(ev) end
  f:SetScript("OnEvent", function(_, event, arg1)
    if event == "NEW_RECIPE_LEARNED" then
      ns.Scanner:LearnRecipe(arg1)
    end
    ns.Scanner:ScanCurrent()
  end)
  self.frame = f
  C_Timer.After(1, function() ns.Scanner:ScanCurrent() end)
end
