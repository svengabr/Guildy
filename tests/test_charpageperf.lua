-- The character page draws only when something it shows changed, at most once per burst of events, and
-- reuses what it worked out (rankings, upgrades) until their data changes. In the stubbed client.
local T = ...

local function IdOf(item)
  return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
end

local function World()
  local w = { renders = 0, rankings = 0, upgrades = 0, tips = 0 }
  w.INFO = {
    [7000] = { "Alter Gürtel", 46, "INVTYPE_WAIST" },
    [7100] = { "Makiras Gürtel", 40, "INVTYPE_WAIST" },
    [50001] = { "Gürtel des Rechtsprechers", 58, "INVTYPE_WAIST" },
  }
  local world = dofile(T.testsDir .. "/wow.lua")(T, { setup = function(env)
    env.C_Item = { RequestLoadItemDataByID = function() end,
      GetItemStats = function() return { ITEM_MOD_INTELLECT_SHORT = 5 } end }
    env.C_TooltipInfo = {
      GetItemByID = function(id) return { lines = { { leftText = "Item " .. id } } } end,
      GetHyperlink = function(link)
        w.tips = w.tips + 1
        local _, enchant = tostring(link):match("item:(%d+):?(%d*)")
        local lines = { { leftText = "Item" } }
        if enchant ~= "" and enchant ~= "0" and enchant ~= "77" then lines[2] = { leftText = "+5 Ausdauer" } end
        return { lines = lines }
      end,
    }
    env.GetItemInfo = function(item)
      local id = IdOf(item)
      local it = w.INFO[id]
      if it then return it[1], "item:" .. id, 2, it[2], 10, "Rüstung", "Stoff", 1, it[3], 134, 1, 4, 1, 2 end
    end
  end })
  w.env, w.ns, w.errors, w.Fire, w.RunTimers = world.env, world.ns, world.errors, world.Fire, world.RunTimers
  local ns = w.ns
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  w.env.CommunitiesFrame:Show()
  local guild = ns.GuildData()
  guild.gear = guild.gear or {}
  guild.gear["au tsch"] = { ts = ns.Now(), src = "seen", items = { [6] = { id = 7000, e = 0, s = 0, l = 46, q = 2 } } }
  guild.gear["makira farron"] = { ts = ns.Now(), src = "seen", items = { [6] = { id = 7100, e = 0, s = 0, l = 40, q = 2 } } }
  guild.members["makira farron"].profs[197] = { ts = ns.Now(), src = "relay", rank = 250, max = 300, recipes = { 99001 } }
  w.env.GuildyDB.craftItems = { [99001] = 50001 }
  -- counted: rankings built and upgrades worked out
  local ranking = ns.Stats.Ranking
  ns.Stats.Ranking = function(...)
    w.rankings = w.rankings + 1
    return ranking(...)
  end
  local upgradesFor = ns.Upgrades.ForIndex
  ns.Upgrades.ForIndex = function(...)
    w.upgrades = w.upgrades + 1
    return upgradesFor(...)
  end
  ns.UI.ShowMember(ns.Roster.Find("Au Tsch"))
  w.page = ns.UI.MemberPage()
  local render = w.page.Render
  w.page.Render = function(...)
    w.renders = w.renders + 1
    return render(...)
  end
  w.RunTimers()
  w.renders = 0
  return w
end

T.describe("Character page renders", function()
  T.it("works out the upgrades for a member", function()
    local w = World()
    T.eq(w.upgrades, 1)
    T.eq(w.page.Upgrades.Rows[1].itemID, 50001)
    T.eq(w.errors, {})
  end)

  T.it("does not rebuild rankings or upgrades when it draws again without a change", function()
    local w = World()
    local rankings = w.rankings
    T.truthy(rankings > 0, "rankings built for the first page")
    w.page:Render()
    w.page:Render()
    w.ns.UI.ShowMember(w.ns.Roster.Find("Au Tsch"))
    T.eq(w.rankings, rankings)
    T.eq(w.upgrades, 1)
    T.eq(w.renders, 3) -- an explicit show draws at once
    T.eq(w.errors, {})
  end)

  T.it("draws once for a burst of roster and item events", function()
    local w = World()
    w.page.waiting = true -- an item name still loading
    w.ns.Roster.Find("Au Tsch").zone = "Wald von Elwynn"
    for _ = 1, 3 do w.ns.Fire("ROSTER") end
    w.ns.Fire("GEAR_INFO")
    w.ns.Fire("GEAR_INFO")
    T.eq(w.renders, 0)
    w.RunTimers()
    T.eq(w.renders, 1)
    T.eq(w.errors, {})
  end)

  T.it("does not draw for an event about another member or a roster that shows nothing new", function()
    local w = World()
    w.ns.Fire("GEAR", "makira farron")
    w.ns.Fire("STATS", "makira farron")
    w.ns.Fire("ROSTER")
    w.ns.Fire("GEAR_INFO") -- nothing on the page waits for an item
    w.RunTimers()
    T.eq(w.renders, 0)
    w.ns.Fire("GEAR", "au tsch")
    w.RunTimers()
    T.eq(w.renders, 1)
    T.eq(w.errors, {})
  end)

  T.it("shows a piece the game names for a newly synced recipe without waiting for an item", function()
    local w = World()
    w.INFO[50002] = { "Gürtel der Neuen", 62, "INVTYPE_WAIST" }
    w.env.C_Item.GetItemInfoInstant = function(item)
      local it = w.INFO[IdOf(item)]
      if it then return IdOf(item), "Rüstung", "Stoff", it[3] end
    end
    w.env.C_TradeSkillUI = { GetRecipeOutputItemData = function(spellID)
      if spellID == 99002 then return { itemID = 50002 } end
    end }
    local prof = w.ns.GuildData().members["makira farron"].profs[197]
    prof.recipes = { 99001, 99002 }
    w.ns.Fire("PROFS")
    w.RunTimers(1) -- the page draws; the recipe's item is asked from the game
    T.eq(w.page.Upgrades.Rows[1].itemID, 50001)
    T.eq(w.page.waiting, false)
    w.RunTimers(10) -- the game names the item, GEAR_INFO
    T.eq(w.page.Upgrades.Rows[1].itemID, 50002)
    T.eq(w.errors, {})
  end)

  T.it("builds rankings anew when statistics change, upgrades when gear or books change", function()
    local w = World()
    local rankings = w.rankings
    w.ns.Fire("STATS", "makira farron")
    w.page:Render()
    T.truthy(w.rankings > rankings, "rankings rebuilt")
    T.eq(w.upgrades, 1) -- statistics do not change upgrades
    w.ns.Fire("GEAR", "makira farron")
    w.page:Render()
    T.eq(w.upgrades, 1) -- another member's gear neither
    local rec = w.ns.GuildData().gear["au tsch"]
    rec.ts = rec.ts + 5
    w.ns.Fire("GEAR", "au tsch")
    w.RunTimers()
    T.eq(w.upgrades, 2)
    w.ns.Fire("PROFS")
    w.RunTimers()
    T.eq(w.upgrades, 3)
    T.eq(w.errors, {})
  end)

  T.it("works out the guild's activity scores once for 20 renders switching members between roster scans", function()
    local w = World()
    local players, ns = 0, w.ns
    local fn = ns.Activity.Players
    ns.Activity.Players = function(...)
      players = players + 1
      return fn(...)
    end
    local names = { "Au Tsch", "Makira Farron", "Ran Fred" }
    ns.Fire("STATS") -- what the first render worked out is gone
    for i = 1, 20 do
      ns.UI.ShowMember(ns.Roster.Find(names[(i - 1) % 3 + 1]))
      w.Fire("GUILD_ROSTER_UPDATE") -- the roster scans every few seconds: nobody came or went
      w.RunTimers()
    end
    T.eq(players, 1)
    T.eq(w.errors, {})
  end)

  T.it("works out the first titles of the whole guild once per version of the statistics, not per member", function()
    local w = World()
    local built, ns = 0, w.ns
    local fn = ns.Stats.FirstTitles
    ns.Stats.FirstTitles = function(...)
      built = built + 1
      return fn(...)
    end
    local names = { "Au Tsch", "Makira Farron", "Ran Fred" }
    ns.Fire("STATS")
    for i = 1, 9 do ns.UI.ShowMember(ns.Roster.Find(names[(i - 1) % 3 + 1])) end
    T.eq(built, 1)
    ns.Fire("STATS", "au tsch")
    for i = 1, 3 do ns.UI.ShowMember(ns.Roster.Find(names[i])) end
    T.eq(built, 2)
    T.eq(w.errors, {})
  end)

  T.it("works out the activity scores anew when statistics, families, seen days or the day change", function()
    local w = World()
    local players, ns = 0, w.ns
    local fn = ns.Activity.Players
    ns.Activity.Players = function(...)
      players = players + 1
      return fn(...)
    end
    local function Score() return ns.GameActivity.ScoreOf("au tsch") end
    Score()
    Score()
    T.eq(players, 0) -- worked out for the first render already
    ns.Fire("STATS", "makira farron")
    Score()
    Score()
    T.eq(players, 1)
    ns.Fire("STATS", "makira farron")
    Score()
    T.eq(players, 2)
    ns.Fire("FAMILY")
    Score()
    T.eq(players, 3)
    -- Makira comes online: a new seen day with the next scan
    local info = w.env.GetGuildRosterInfo
    w.env.GetGuildRosterInfo = function(i)
      local values = { info(i) }
      if i == 2 then values[9] = true end
      return unpack(values, 1, 17)
    end
    w.env.GetGuildRosterLastOnline = function() end
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    Score()
    T.eq(players, 4)
    local now = ns.Now
    ns.Now = function() return now() + 86400 end
    Score()
    T.eq(players, 5)
    ns.Now = now
    T.eq(w.errors, {})
  end)

  T.it("works out the activity scores anew when a public or officer note links characters", function()
    local w = World()
    local players, ns = 0, w.ns
    local fn = ns.Activity.Players
    ns.Activity.Players = function(...)
      players = players + 1
      return fn(...)
    end
    local function Score() return ns.GameActivity.ScoreOf("au tsch") end
    local notes = {}
    local info = w.env.GetGuildRosterInfo
    w.env.GetGuildRosterInfo = function(i)
      local values = { info(i) }
      if notes[i] then values[7], values[8] = notes[i][1], notes[i][2] end
      return unpack(values, 1, 17)
    end
    local function Scan()
      w.Fire("GUILD_ROSTER_UPDATE")
      w.RunTimers()
    end
    Score()
    T.eq(players, 0)
    notes[3] = { "Twink von Ran", "" }
    Scan()
    Score()
    T.eq(players, 1)
    Scan() -- the same notes again: nothing new
    Score()
    T.eq(players, 1)
    notes[2] = { "Heiler", "Twink von Ran" }
    Scan()
    Score()
    T.eq(players, 2)
    T.eq(w.errors, {})
  end)

  T.it("does not wait for a worn item the game says it does not have", function()
    local w = World()
    w.ns.GuildData().gear["au tsch"].items[1] = { id = 7999, e = 0, s = 0, l = 46, q = 2 }
    w.page:Render()
    T.eq(w.page.waiting, true) -- asked from the game
    w.Fire("GET_ITEM_INFO_RECEIVED", 7999, false)
    w.page:Render()
    T.eq(w.page.waiting, false)
    w.renders = 0
    w.ns.Fire("GEAR_INFO") -- items of another addon loading
    w.RunTimers()
    T.eq(w.renders, 0)
    T.eq(w.errors, {})
  end)

  T.it("reads an enchantment's text once per session, a missing one too", function()
    local w = World()
    local rec = w.ns.GuildData().gear["au tsch"]
    rec.items[6].e = 77 -- the tooltip names no line for it
    rec.items[1] = { id = 7000, e = 12, s = 0, l = 46, q = 2 }
    w.page:Render()
    local tips = w.tips
    T.truthy(tips > 0, "tooltips read")
    w.page:Render()
    w.page:Render()
    T.eq(w.tips, tips)
    T.eq(w.errors, {})
  end)
end)

T.describe("Character page item names", function()
  T.it("reads the tooltip of a suffixed worn piece once when its name is the base item's", function()
    local w = World()
    local tooltip = w.env.C_TooltipInfo.GetHyperlink
    w.env.C_TooltipInfo.GetHyperlink = function(link)
      local result = tooltip(link)
      result.lines[1].leftText = "Alter Gürtel" -- the full item string's name is the base name
      return result
    end
    w.ns.GuildData().gear["au tsch"].items[6] = { id = 7000, e = 0, s = 5, l = 46, q = 2 }
    w.page:Render()
    local tips = w.tips
    T.truthy(tips > 0, "tooltip read")
    w.page:Render()
    w.page:Render()
    T.eq(w.tips, tips)
    T.eq(w.errors, {})
  end)
end)
