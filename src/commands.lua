local _, ns = ...

ns.Commands = {}

local function print_(msg)
  DEFAULT_CHAT_FRAME:AddMessage("|cff7ec0eeGuildRecipeDex|r: " .. msg)
end

function ns.Commands:Register()
  SLASH_GUILDRECIPEDEX1 = "/guildrecipedex"
  SLASH_GUILDRECIPEDEX2 = "/grd"
  SlashCmdList["GUILDRECIPEDEX"] = function(input)
    input = (input or ""):lower():match("^%s*(.-)%s*$")
    if input == "" or input == "show" or input == "open" then
      ns.UI:Toggle()
    elseif input == "debug on" then
      GuildRecipeDexDB.settings.debug = true; print_("debug ON")
    elseif input == "debug off" then
      GuildRecipeDexDB.settings.debug = false; print_("debug OFF")
    elseif input == "dump" then
      local c = ns.DB:GetCharacter()
      local n = 0
      for sid, p in pairs(c.professions) do
        local rc = 0; for _ in pairs(p.recipes or {}) do rc = rc + 1 end
        print_(("%s (skillLine=%d): %d known recipes"):format(p.name, sid, rc))
        n = n + 1
      end
      if n == 0 then print_("no professions scanned yet — open your profession window once.") end
    elseif input == "sync" then
      if ns.Comms and ns.Comms.BroadcastHello then
        ns.Comms:BroadcastHello(); print_("sync HELLO sent")
      else
        print_("comms not initialized")
      end
    elseif input == "peers" then
      local me = ns.DB:CharKey()
      local n = 0
      for ck, c in pairs(GuildRecipeDexDB.characters or {}) do
        if ck ~= me then
          n = n + 1
          local prCount, total = 0, 0
          for _, p in pairs(c.professions or {}) do
            prCount = prCount + 1
            for _ in pairs(p.recipes or {}) do total = total + 1 end
          end
          print_(("  %s — %d professions, %d total recipes"):format(ck, prCount, total))
        end
      end
      if n == 0 then print_("no peer data yet (need at least one other guildie running the addon)") end
    elseif input:match("^test ") then
      local arg = input:match("^test (.+)")
      if not arg then print_("usage: /grd test <recipeID or partial name>"); return end
      local rids = {}
      local asNum = tonumber(arg)
      if asNum and ns.Catalog.recipes[asNum] then
        table.insert(rids, asNum)
      else
        local needle = arg:lower()
        for rid in pairs(ns.Catalog.recipes or {}) do
          local si = C_Spell.GetSpellInfo(rid)
          if si and si.name and si.name:lower():find(needle, 1, true) then
            table.insert(rids, rid)
            if #rids >= 5 then break end
          end
        end
      end
      if #rids == 0 then print_("no match for '" .. arg .. "'"); return end
      for _, rid in ipairs(rids) do
        local cat = ns.Catalog.recipes[rid]
        local si = C_Spell.GetSpellInfo(rid)
        print_(("[%d] %s — skillLine=%d cat=%d item=%d"):format(rid, si and si.name or "?", cat.skillLine or 0, cat.category or 0, cat.item or 0))
        if cat.item and cat.item ~= 0 then
          local id, _, _, _, icon = GetItemInfoInstant(cat.item)
          print_(("    GetItemInfoInstant(%d): id=%s icon=%s"):format(cat.item, tostring(id), tostring(icon)))
        end
        print_(("    spell iconID=%s"):format(si and tostring(si.iconID) or "nil"))
      end
    else
      print_("commands: show, dump, sync, peers, debug on|off, test <recipeID>")
    end
  end
end
