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

-- Extract reagent slots from a recipe schematic, grouped by type.
-- Returns { required = {...}, modifying = {...}, finishing = {...} } where each
-- slot is { qty, options = { {itemID, qty}, ... } }. Most basic slots have one
-- option (the required reagent); quality-tiered or modifying slots have several.
local function extractReagents(schematic)
  local out = { required = {}, modifying = {}, finishing = {} }
  if not schematic or not schematic.reagentSlotSchematics then return out end
  for _, slot in ipairs(schematic.reagentSlotSchematics) do
    -- Enum.CraftingReagentType: 0=Modifying, 1=Basic, 2=Finishing, 3=Automatic.
    local bucket
    if slot.reagentType == 0 then bucket = out.modifying
    elseif slot.reagentType == 1 then bucket = out.required
    elseif slot.reagentType == 2 then bucket = out.finishing
    end
    if bucket and slot.reagents and slot.reagents[1] then
      local options = {}
      for _, r in ipairs(slot.reagents) do
        if r.itemID then table.insert(options, r.itemID) end
      end
      if #options > 0 then
        table.insert(bucket, { qty = slot.quantityRequired or 1, options = options, slotInfo = slot.slotInfo })
      end
    end
  end
  return out
end

-- Walk UP from each known recipe's categoryID to build the full category tree.
-- More reliable than C_TradeSkillUI.GetCategories which has API quirks across patches.
local function snapshotCategories(recipeIDs)
  local tree = {}
  local triedCount, gotCount = 0, 0
  local function record(catID)
    if not catID or catID == 0 or tree[catID] then return end
    triedCount = triedCount + 1
    local info = C_TradeSkillUI.GetCategoryInfo(catID)
    if not info or (not info.name and not info.parentCategoryID) then return end
    gotCount = gotCount + 1
    tree[catID] = {
      name = info.name or ("Category " .. catID),
      parentCategoryID = info.parentCategoryID,
    }
    if info.parentCategoryID and info.parentCategoryID ~= 0 then
      record(info.parentCategoryID)
    end
  end
  for _, rid in ipairs(recipeIDs or {}) do
    local r = C_TradeSkillUI.GetRecipeInfo(rid)
    if r and r.categoryID then record(r.categoryID) end
  end
  debugPrint(("categories: %d/%d resolved"):format(gotCount, triedCount))
  return tree
end

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
      local schematic = C_TradeSkillUI.GetRecipeSchematic and C_TradeSkillUI.GetRecipeSchematic(rid, false)
      known[rid] = {
        name = r.name,
        icon = r.icon,
        categoryID = r.categoryID,
        outputItemID = (schematic and schematic.outputItemID) or nil,
        reagents = extractReagents(schematic),
      }
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
    categories = snapshotCategories(fingerprintIDs),
    scannedAt = time(),
  })

  debugPrint(("scanned %s: %d known recipes"):format(profName, fp))

  if ns.Comms and ns.Comms.AnnounceChange then
    ns.Comms:AnnounceChange(ns.DB:CharKey(), skillLineID)
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
