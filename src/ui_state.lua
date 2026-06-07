local _, ns = ...

-- Public module surface (Init/Toggle live in ui.lua).
ns.UI = {}

-- Private shared state for the UI files (ui_catalog, ui_list, ui_detail, ui).
-- Everything the UI modules share — constants, widget refs, selection state,
-- the category tree, and the cross-file functions — hangs off this one table so
-- the code can be split across files without true globals. Each UI file does:
--   local _, ns = ...
--   local P = ns.UIPriv
ns.UIPriv = {
  -- Layout constants.
  ROW_HEIGHT = 18,
  VISIBLE_ROWS = 24,
  LIST_WIDTH = 300,

  -- Widget references (assigned by buildFrame in ui.lua).
  frame = nil,
  profDropdown = nil,
  expansionDropdown = nil,
  searchBox = nil,
  listScroll = nil,
  listChild = nil,
  detail = nil,
  detailScroll = nil,
  detailContent = nil,
  detailIcon = nil,
  detailName = nil,
  reagentsHeader = nil,
  sourceHeader = nil,
  sourceText = nil,
  craftersHeader = nil,
  craftersText = nil,
  noCraftersText = nil,
  trackCheck = nil,

  -- Pools.
  listRows = {},
  reagentSlots = {},
  flatRows = {},

  -- Category tree for the selected expansion.
  tree = {},
  roots = {},

  -- Reagent slot expansion (multi-quality / multi-option), reset per recipe.
  reagentExpanded = {},
  reagentExpandedFor = nil,

  -- Selection / view state.
  state = {
    professionID = nil,    -- profession base skillLineID (e.g. 165 = Leatherworking)
    expansionID = nil,     -- selected expansion child skillLineID (e.g. 2915 = Midnight LW)
    search = "",
    selectedRecipeID = nil,
    expanded = {},         -- [categoryID] = true
    scrollOffset = 0,
  },
}
