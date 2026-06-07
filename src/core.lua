local addonName, ns = ...

ns.frame = CreateFrame("Frame", "GuildRecipeDexCore", UIParent)
ns.frame:RegisterEvent("ADDON_LOADED")
ns.frame:RegisterEvent("PLAYER_LOGIN")

ns.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    ns.DB:Init()
  elseif event == "PLAYER_LOGIN" then
    ns.Scanner:Init()
    ns.GuildScan:Init()
    ns.Comms:Init()
    ns.UI:Init()
    ns.Commands:Register()
  end
end)
