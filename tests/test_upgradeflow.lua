-- "Upgrades aus der Gilde" in the stubbed client (tests/wow.lua): item stats from GetItemStats, the
-- requirements from the item tooltip in the client's language, the comparison under the tooltip.
local T = ...

local AGI, STR, STA, INT, SPI, AP = "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT"

local function IdOf(item)
  return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
end

-- A world with a feral druid (Au Tsch, level 46) in leather, and Makira who can make pieces
local function World()
  local w = { requested = {}, INFO = {}, STATS = {}, TIPS = {}, hidden = {}, tips = 0 }
  local world = dofile(T.testsDir .. "/wow.lua")(T, {
    roster = {
      { "Ran-Fred", "Offizier", 1, 16, "Druide", "Sturmwind", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-01" },
      { "Makira-Farron", "Offizier", 1, 50, "Paladin", "Eisenschmiede", "", "", true, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
      { "Au-Tsch", "Haifutter", 2, 46, "Druide", "Dämmerwald", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-03" },
    },
    setup = function(env)
      env.C_Item = {
        RequestLoadItemDataByID = function(id) w.requested[#w.requested + 1] = id end,
        GetItemStats = function(link)
          local stats = w.STATS[IdOf(link)]
          if not stats then return nil end
          local copy = {}
          for k, v in pairs(stats) do copy[k] = v end
          return copy
        end,
      }
      env.GetItemInfo = function(item)
        local id = IdOf(item)
        local it = not w.hidden[id] and w.INFO[id]
        if it then
          return it.name, "item:" .. id, it.quality or 2, it.level, it.reqLevel or 1, "Rüstung", "Leder", 1, it.equipLoc, 134, 1,
            it.classID or 4, it.subclassID or 2, it.bind or 2
        end
      end
      env.C_TooltipInfo = { GetItemByID = function(id)
        w.tips = w.tips + 1
        local it = w.INFO[id]
        local tip = w.TIPS[id] or (it and { it.name })
        if not tip then return nil end
        local lines = {}
        for i, text in ipairs(tip) do lines[i] = { leftText = text } end
        return { lines = lines }
      end }
      env.ITEM_MIN_LEVEL, env.ITEM_MIN_SKILL, env.ITEM_REQ_SKILL = "Benötigt Stufe %d", "Benötigt %s (%d)", "Benötigt %s"
      env.ITEM_CLASSES_ALLOWED, env.ITEM_REQ_REPUTATION = "Klassen: %s", "Benötigt %s - %s"
      env.ITEM_MOD_AGILITY_SHORT, env.ITEM_MOD_STAMINA_SHORT = "Beweglichkeit", "Ausdauer"
      env.ITEM_MOD_INTELLECT_SHORT = "Intelligenz"
      env.LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druide", PALADIN = "Paladin", ROGUE = "Schurke" }
    end,
  })
  w.env, w.ns, w.errors, w.Fire, w.RunTimers, w.SECRET = world.env, world.ns, world.errors, world.Fire, world.RunTimers, world.SECRET
  w.Fire("ADDON_LOADED", "Guildy")
  w.Fire("PLAYER_LOGIN")
  w.Fire("GUILD_ROSTER_UPDATE")
  w.RunTimers()
  w.env.CommunitiesFrame:Show()

  -- the druid's leather: agility, strength, stamina, attack power; the chest a weak piece
  local items = {}
  for i, slot in ipairs({ 1, 3, 7, 8, 10, 6, 5 }) do
    local id = 7000 + i
    w.INFO[id] = { name = "Leder " .. i, level = 40, equipLoc = "INVTYPE_HEAD", subclassID = 2 }
    w.STATS[id] = slot == 5 and { [AGI] = 6, [STA] = 5 } or { [AGI] = 6, [STR] = 4, [STA] = 6, [AP] = 10 }
    items[slot] = { id = id, e = 0, s = 0, l = 40, q = 2 }
  end
  local guild = w.ns.GuildData()
  guild.gear = guild.gear or {}
  guild.gear["au tsch"] = { ts = w.ns.Now(), src = "seen", items = items }
  -- what Makira's tailoring and engineering make
  w.INFO[700] = { name = "Winterzwirntunika", level = 50, reqLevel = 45, equipLoc = "INVTYPE_ROBE", subclassID = 1, quality = 3 }
  w.STATS[700] = { [INT] = 14, [SPI] = 10, [STA] = 4 }
  w.INFO[702] = { name = "Wildlederweste", level = 44, reqLevel = 40, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
  w.STATS[702] = { [AGI] = 14, [STA] = 8 }
  w.INFO[703] = { name = "Goblinmörser", level = 45, reqLevel = 40, equipLoc = "INVTYPE_TRINKET", subclassID = 0 }
  w.STATS[703] = { [AGI] = 10, [AP] = 20 }
  w.TIPS[703] = { "Goblinmörser", "Schmuck", "Benötigt Stufe 40", "|cffff2020Benötigt Ingenieurskunst (205)|r" }
  guild.members["makira farron"] = guild.members["makira farron"] or {}
  guild.members["makira farron"].profs = { [197] = { ts = w.ns.Now(), src = "relay", rank = 250, max = 300, recipes = { 99700 } },
    [202] = { ts = w.ns.Now(), src = "relay", rank = 250, max = 300, recipes = { 99702, 99703 } } }
  w.env.GuildyDB.craftItems = { [99700] = 700, [99702] = 702, [99703] = 703 }

  function w.Member() return w.ns.Roster.Find("Au Tsch") end
  function w.Offered()
    local rows, state = w.ns.GameGear.UpgradesFor(w.Member())
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = row.itemID end
    table.sort(ids)
    return ids, state, rows
  end
  function w.Asked(id)
    local n = 0
    for _, asked in ipairs(w.requested) do if asked == id then n = n + 1 end end
    return n
  end
  function w.Engineer(rank)
    w.ns.GuildData().members["au tsch"] = w.ns.GuildData().members["au tsch"] or {}
    w.ns.GuildData().members["au tsch"].profs = { [202] = { ts = w.ns.Now(), src = "relay", rank = rank, max = 300 } }
    w.ns.Fire("PROFS")
  end
  return w
end

T.describe("Upgrades from the guild in the game", function()
  T.it("offers the leather agility chest, not the cloth caster robe of a higher level", function()
    local w = World()
    local ids, state = w.Offered()
    T.eq(ids, { 702 })
    T.eq(state, "rows")
    T.eq(w.errors, {})
  end)

  T.it("drops the trinket that needs engineering 205 until the member is an engineer of 205", function()
    local w = World()
    T.eq(w.Offered(), { 702 })
    w.Engineer(150)
    T.eq(w.Offered(), { 702 })
    w.Engineer(210)
    T.eq(w.Offered(), { 702, 703 })
    T.eq(w.errors, {})
  end)

  T.it("skips an item whose tooltip text is secret and reads it once it is not", function()
    local w = World()
    w.Engineer(210)
    w.TIPS[703] = { "Goblinmörser", w.SECRET }
    T.eq(w.ns.GameGear.ItemRequirements(703), nil)
    T.eq(w.Offered(), { 702 })
    w.TIPS[703] = { "Goblinmörser", "Benötigt Ingenieurskunst (205)" }
    T.eq(w.ns.GameGear.ItemRequirements(703), { skill = "Ingenieurskunst", rank = 205 })
    T.eq(w.errors, {})
  end)

  T.it("skips an item whose stats are not loaded yet and asks for it once", function()
    local w = World()
    w.hidden[702] = true
    T.eq(w.Offered(), {})
    w.Fire("GET_ITEM_INFO_RECEIVED", 999, true)
    T.eq(w.Offered(), {})
    T.eq(w.Asked(702), 1)
    w.hidden[702] = nil
    w.ns.Fire("GEAR_INFO")
    T.eq(w.Offered(), { 702 })
    T.eq(w.errors, {})
  end)

  T.it("reads no item info, stats or tooltip again for other members once the items are known", function()
    local w = World()
    local guild = w.ns.GuildData()
    -- Ran and Makira wear what Au Tsch wears
    guild.gear["ran fred"] = { ts = w.ns.Now(), src = "seen", items = guild.gear["au tsch"].items }
    guild.gear["makira farron"] = { ts = w.ns.Now(), src = "seen", items = guild.gear["au tsch"].items }
    T.eq(w.Offered(), { 702 }) -- warm-up
    local counts = { info = 0, stats = 0 }
    local getInfo, getStats = w.env.GetItemInfo, w.env.C_Item.GetItemStats
    w.env.GetItemInfo = function(...) counts.info = counts.info + 1 return getInfo(...) end
    w.env.C_Item.GetItemStats = function(...) counts.stats = counts.stats + 1 return getStats(...) end
    local tips = w.tips
    for _, name in ipairs({ "Ran Fred", "Makira Farron" }) do w.ns.GameGear.UpgradesFor(w.ns.Roster.Find(name)) end
    w.ns.Fire("PROFS") -- the books change: Au Tsch's upgrades are worked out anew
    T.eq(w.Offered(), { 702 })
    T.eq(counts, { info = 0, stats = 0 })
    T.eq(w.tips, tips)
    T.eq(w.errors, {})
  end)

  T.it("builds the index of crafted pieces once per version of the books", function()
    local w = World()
    local builds, index = 0, w.ns.Upgrades.Index
    w.ns.Upgrades.Index = function(...) builds = builds + 1 return index(...) end
    for _, name in ipairs({ "Au Tsch", "Ran Fred", "Makira Farron" }) do w.ns.GameGear.UpgradesFor(w.ns.Roster.Find(name)) end
    w.ns.Fire("GEAR_INFO")
    w.ns.GameGear.UpgradesFor(w.ns.Roster.Find("Ran Fred"))
    T.eq(builds, 1)
    w.ns.Fire("PROFS")
    w.ns.GameGear.UpgradesFor(w.ns.Roster.Find("Ran Fred"))
    T.eq(builds, 2)
    T.eq(w.errors, {})
  end)

  T.it("takes in an item whose info loads later without building the index again", function()
    local w = World()
    local builds, index = 0, w.ns.Upgrades.Index
    w.ns.Upgrades.Index = function(...) builds = builds + 1 return index(...) end
    w.hidden[702] = true
    local _, _, rows = w.Offered()
    T.eq(#rows, 0)
    w.hidden[702] = nil
    w.ns.Fire("GEAR_INFO")
    T.eq(w.Offered(), { 702 })
    T.eq(builds, 1)
    T.eq(w.errors, {})
  end)

  T.it("adds the stat comparison under the item tooltip", function()
    local w = World()
    local lines = {}
    rawset(w.env.GameTooltip, "AddLine", function(_, text) lines[#lines + 1] = text end)
    w.ns.UI.ShowMember(w.Member())
    w.ns.UI.MemberPage():SetSize(1130 - 22, 760)
    w.ns.UI.MemberPage():Render()
    local row = w.ns.UI.MemberPage().Upgrades.Rows[1]
    T.eq(row:IsShown(), true)
    row.Item:GetScript("OnEnter")(row.Item)
    local all = table.concat(lines, "\n")
    T.truthy(all:find("+8 Beweglichkeit", 1, true), all)
    T.truthy(all:find("+3 Ausdauer", 1, true), all)
    T.truthy(all:find(w.ns.L.UPGRADE_COMPARE, 1, true), all)
    T.eq(w.errors, {})
  end)
end)
