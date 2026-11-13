-- Guild upgrades on the character page against an item client that behaves like the game's (tests/wow.lua
-- opts.items): nothing known until asked, answers a timer round later, some IDs never resolve. Pins what
-- was measured in game (2026-11-13): the index of crafted pieces built on every render, items asked again
-- and again (765 GET_ITEM_INFO_RECEIVED in 30 s), about 320 kB per scoring run.
local T = ...

local AGI, STR, STA, INT, AP = "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT"

local LOCS = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_WAIST", "INVTYPE_LEGS", "INVTYPE_FEET",
  "INVTYPE_WRIST", "INVTYPE_HAND", "INVTYPE_FINGER", "INVTYPE_CLOAK", "INVTYPE_NECK", "INVTYPE_TRINKET" }
local UNKNOWN = { 90001, 90002, 90003, 90004, 90005 } -- in the craft map (bnet-sync), not in this client
local SWITCH = { "Au Tsch", "Syd Sturm", "Mae Dorn", "Ran Fred" }

-- crafts: how many crafted pieces Makira's book makes
local function World(crafts, extra)
  crafts = crafts or 60
  local data, worn = {}, {}
  for i, slot in ipairs({ 1, 3, 7, 8, 10, 6, 5 }) do
    local id = 7000 + i
    data[id] = { name = "Leder " .. i, level = 40, equipLoc = "INVTYPE_HEAD", subclassID = 2,
      stats = { [AGI] = 6, [STR] = 4, [STA] = 6, [AP] = 10 } }
    worn[slot] = { id = id, e = 0, s = 0, l = 40, q = 2 }
  end
  local recipes, craftMap = {}, {}
  for i = 1, crafts do
    local id, loc = 10000 + i, LOCS[(i - 1) % #LOCS + 1]
    local jewel = loc == "INVTYPE_FINGER" or loc == "INVTYPE_NECK" or loc == "INVTYPE_TRINKET" or loc == "INVTYPE_CLOAK"
    local level = 30 + i % 30
    data[id] = { name = "Werkstück " .. i, level = level, reqLevel = level - 5, equipLoc = loc, subclassID = jewel and 0 or 2,
      quality = 2 + i % 2, stats = { [AGI] = 4 + i % 12, [STA] = 3 + i % 7, [INT] = i % 3 == 0 and 5 or nil } }
    if i % 5 == 0 then data[id].tip = { data[id].name, "Benötigt Lederverarbeitung (" .. (100 + i) .. ")" } end
    if i % 7 == 0 then data[id].tip = { data[id].name, "Klassen: Druide, Schurke" } end
    recipes[#recipes + 1] = 200000 + i
    craftMap[200000 + i] = id
  end
  for i, id in ipairs(UNKNOWN) do
    recipes[#recipes + 1] = 300000 + i
    craftMap[300000 + i] = id
  end
  table.sort(recipes)
  local world = dofile(T.testsDir .. "/wow.lua")(T, {
    items = data,
    noCachedCheck = extra and extra.noCachedCheck,
    roster = {
      { "Ran-Fred", "Offizier", 1, 46, "Druide", "Sturmwind", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-01" },
      { "Makira-Farron", "Offizier", 1, 50, "Paladin", "Eisenschmiede", "", "", true, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
      { "Au-Tsch", "Haifutter", 2, 46, "Druide", "Dämmerwald", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-03" },
      { "Syd-Sturm", "Haifutter", 2, 46, "Schurke", "Dämmerwald", "", "", true, 0, "ROGUE", nil, nil, false, nil, nil, "Player-1-04" },
      { "Mae-Dorn", "Haifutter", 2, 46, "Druide", "Dämmerwald", "", "", false, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-05" },
    },
    setup = function(env)
      env.ITEM_MIN_LEVEL, env.ITEM_MIN_SKILL, env.ITEM_REQ_SKILL = "Benötigt Stufe %d", "Benötigt %s (%d)", "Benötigt %s"
      env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_REPUTATION = "Klassen: %s", "Benötigt %s - %s"
    end,
  })
  local w = { world = world, env = world.env, ns = world.ns, errors = world.errors, Fire = world.Fire,
    RunTimers = world.RunTimers, items = world.items, builds = 0 }
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  w.env.CommunitiesFrame:Show()
  local ns = w.ns
  local guild = ns.GuildData()
  guild.gear = guild.gear or {}
  for _, key in ipairs({ "au tsch", "syd sturm", "mae dorn", "ran fred" }) do
    local items = {}
    for slot, item in pairs(worn) do items[slot] = { id = item.id, e = 0, s = 0, l = 40, q = 2 } end
    guild.gear[key] = { ts = ns.Now(), src = "seen", items = items }
  end
  w.maker = ns.Store.Member(guild, "Makira-Farron")
  w.maker.profs = { [165] = { ts = ns.Now(), src = "relay", rank = 300, max = 300, recipes = recipes } }
  w.env.GuildyDB.craftItems = craftMap
  local index = ns.Upgrades.Index
  ns.Upgrades.Index = function(...)
    w.builds = w.builds + 1
    return index(...)
  end
  function w.Show(name)
    ns.UI.ShowMember(ns.Roster.Find(name))
    w.RunTimers(3)
  end
  -- warmed up: the background walk done and every answer of the game in
  function w.Warm()
    ns.GameGear.WarmUp()
    for _ = 1, 40 do w.RunTimers(5) end
  end
  function w.Offered(name)
    local ids = {}
    for _, row in ipairs((ns.GameGear.UpgradesFor(ns.Roster.Find(name)))) do ids[#ids + 1] = row.itemID end
    return ids
  end
  return w
end

T.describe("Guild upgrades against the game's item client", function()
  T.it("builds the index once for 12 renders switching between 4 members", function()
    local w = World()
    for i = 1, 12 do
      w.Show(SWITCH[(i - 1) % 4 + 1])
      w.Fire("GUILD_ROSTER_UPDATE") -- the roster scans every few seconds
      w.ns.Fire("PROFS")            -- a member's cooldowns came in: no book changed
      w.RunTimers(3)
    end
    T.eq(w.builds, 1)
    T.eq(w.errors, {})
  end)

  T.it("asks for an item the game does not have exactly once and never offers it", function()
    local w = World()
    for i = 1, 12 do w.Show(SWITCH[(i - 1) % 4 + 1]) end
    w.Warm()
    for i = 1, 8 do w.Show(SWITCH[(i - 1) % 4 + 1]) end
    for _, id in ipairs(UNKNOWN) do T.eq(w.items.requests[id], 1, "requests of " .. id) end
    for _, name in ipairs(SWITCH) do
      for _, id in ipairs(w.Offered(name)) do T.truthy(id < 90000, "offered " .. id) end
    end
    T.eq(w.errors, {})
  end)

  T.it("asks for every item at most once per session", function()
    local w = World()
    for i = 1, 12 do w.Show(SWITCH[(i - 1) % 4 + 1]) end
    w.Warm()
    for id, n in pairs(w.items.requests) do T.eq(n, 1, "requests of " .. id) end
    T.eq(w.errors, {})
  end)

  T.it("asks for every item at most once without IsItemDataCachedByID too", function()
    local w = World(60, { noCachedCheck = true })
    for i = 1, 12 do w.Show(SWITCH[(i - 1) % 4 + 1]) end
    w.Warm()
    for id, n in pairs(w.items.requests) do T.eq(n, 1, "requests of " .. id) end
    T.truthy(#w.Offered("Au Tsch") > 0, "offers once loaded")
    T.eq(w.errors, {})
  end)

  T.it("causes no item request and no tooltip read in 20 renders after the warm-up", function()
    local w = World()
    w.Warm()
    T.eq(w.ns.GameGear.WarmDone(), true)
    local requests, tips = w.items.Requests(), w.items.tips
    for i = 1, 20 do w.Show(SWITCH[(i - 1) % 4 + 1]) end
    T.eq(w.items.Requests(), requests)
    T.eq(w.items.tips, tips)
    T.truthy(#w.Offered("Au Tsch") > 0, "offers")
    T.eq(w.errors, {})
  end)

  T.it("marks the index stale on a burst of PROFS and builds it once, and not at all when no book changed", function()
    local w = World()
    w.Show("Au Tsch")
    local builds = w.builds
    local prof = w.maker.profs[165]
    for i = 1, 10 do -- ten books within a second: each a new list with one recipe more
      local list = {}
      for j, id in ipairs(prof.recipes) do list[j] = id end
      list[#list + 1] = 400000 + i
      prof.recipes = list
      w.ns.Fire("PROFS")
    end
    w.RunTimers(3)
    w.Show("Syd Sturm")
    w.Show("Au Tsch")
    T.eq(w.builds, builds + 1)
    for _ = 1, 10 do -- the same books again (a relay with a newer time): new tables, the same recipes
      local list = {}
      for j, id in ipairs(prof.recipes) do list[j] = id end
      prof.recipes = list
      w.ns.Fire("PROFS")
    end
    w.Show("Mae Dorn")
    T.eq(w.builds, builds + 1)
    T.eq(w.errors, {})
  end)

  T.it("pauses the warm-up in combat and finishes it afterwards", function()
    local w = World()
    local fight = true
    w.env.InCombatLockdown = function() return fight end
    local requests = w.items.Requests()
    w.ns.GameGear.WarmUp()
    for _ = 1, 10 do w.RunTimers(5) end
    T.eq(w.items.Requests(), requests)
    T.eq(w.ns.GameGear.WarmDone(), false)
    fight = false
    for _ = 1, 40 do w.RunTimers(5) end
    T.eq(w.ns.GameGear.WarmDone(), true)
    T.truthy(w.items.Requests() > requests, "items asked after the fight")
    T.eq(w.errors, {})
  end)

  T.it("allocates under 50 kB per scoring run once warm, with 400 crafted pieces", function()
    local w = World(400)
    w.Warm()
    local ns = w.ns
    local index = ns.GameGear.CraftIndexNow()
    local gear = ns.GuildData().gear
    local who = {}
    for i, name in ipairs(SWITCH) do who[i] = ns.GameGear.Who(ns.Roster.Find(name)) end
    local game = ns.GameGear.GAME
    for i = 1, 4 do ns.Upgrades.ForIndex(who[i], gear[who[i].key], index, ns.GameGear.ItemInfo, game) end -- warm
    -- once warm, scoring reads nothing from the game: no item info, no stats tables, no tooltips
    local calls = 0
    for _, owner in ipairs({ w.env, w.env.C_Item, w.env.C_TooltipInfo }) do
      for name, fn in pairs(owner) do
        if type(fn) == "function" and (name:find("Item") or name:find("Hyperlink")) then
          owner[name] = function(...) calls = calls + 1 return fn(...) end
        end
      end
    end
    collectgarbage("collect")
    collectgarbage("stop")
    local before, start = collectgarbage("count"), os.clock()
    for r = 1, 12 do
      local m = who[(r - 1) % 4 + 1]
      ns.Upgrades.ForIndex(m, gear[m.key], index, ns.GameGear.ItemInfo, game)
    end
    local kb, ms = (collectgarbage("count") - before) / 12, (os.clock() - start) * 1000 / 12
    collectgarbage("restart")
    T.truthy(kb < 50, ("%.1f kB per run (%.2f ms)"):format(kb, ms))
    T.truthy(ms < 1.5, ("%.2f ms per run"):format(ms))
    T.eq(calls, 0)
    T.eq(w.errors, {})
  end)
end)
