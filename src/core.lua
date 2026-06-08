local addonName, ns = ...

ns.frame = CreateFrame("Frame", "GuildRecipeDexCore", UIParent)
ns.frame:RegisterEvent("ADDON_LOADED")
ns.frame:RegisterEvent("PLAYER_LOGIN")
ns.frame:RegisterEvent("PLAYER_GUILD_UPDATE")
ns.frame:RegisterEvent("GUILD_ROSTER_UPDATE")

local rosterTimer = nil

ns.frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == addonName then
    ns.DB:Init()

  elseif event == "PLAYER_LOGIN" then
    ns.DB:RefreshPlayerContext()
    ns.Scanner:Init()
    ns.GuildScan:Init()
    ns.Comms:Init()
    ns.UI:Init()
    ns.Commands:Register()

  elseif event == "PLAYER_GUILD_UPDATE" then
    ns.DB:RefreshPlayerContext()
    -- Stamp the current character's guild fields
    if ns.DB.root then ns.DB:GetCharacter() end
    -- If we just joined a guild, broadcast after a short delay so roster loads first
    if IsInGuild and IsInGuild() then
      C_Timer.After(5, function()
        if ns.Comms and ns.Comms.BroadcastHello and IsInGuild() then
          ns.Comms:BroadcastHello()
        end
      end)
    end

  elseif event == "GUILD_ROSTER_UPDATE" then
    -- Debounce: cancel any pending timer and restart
    if rosterTimer then rosterTimer:Cancel(); rosterTimer = nil end
    rosterTimer = C_Timer.NewTimer(5, function()
      rosterTimer = nil
      ns.DB:DiffRoster()
    end)
  end
end)
