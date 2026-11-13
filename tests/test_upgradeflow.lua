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
        IsItemDataCachedByID = function(id) return w.INFO[id] ~= nil and not w.hidden[id] end,
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
    w.ns.Fire("PROFS") -- cooldowns, a note: no recipe list changed
    w.ns.GameGear.UpgradesFor(w.ns.Roster.Find("Ran Fred"))
    T.eq(builds, 1)
    w.ns.GuildData().members["makira farron"].profs[197].recipes = { 99700, 99701 }
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

  T.it("reads a suffixed worn item's stats through its full item string, each suffix apart", function()
    local w = World()
    w.INFO[7100] = { name = "Waldläufertunika", level = 39, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
    local asked = {}
    local getStats = w.env.C_Item.GetItemStats
    w.env.GetItemInfo = function(item)
      local id = IdOf(item)
      local it = w.INFO[id]
      if it then -- the link keeps what the item string carried, as the game's does
        local link = type(item) == "string" and item or ("item:" .. id)
        return it.name, link, 2, it.level, 1, "Rüstung", "Leder", 1, it.equipLoc, 134, 1, 4, 2, 2
      end
    end
    w.env.C_Item.GetItemStats = function(link)
      asked[#asked + 1] = link
      if link == "item:7100:0:0:0:0:0:-17:2752512" then return { [STR] = 13, [AGI] = 13 } end
      if link == "item:7100:0:0:0:0:0:-17:1376256" then return { [STR] = 6, [AGI] = 6 } end
      return getStats(link)
    end
    local tiger = { id = 7100, e = 0, s = -17, u = 2752512, l = 39, q = 2 }
    local weak = { id = 7100, e = 0, s = -17, u = 1376256, l = 39, q = 2 }
    T.eq(w.ns.GameGear.ItemStats(tiger), { [STR] = 13, [AGI] = 13 })
    T.eq(w.ns.GameGear.ItemStats(weak), { [STR] = 6, [AGI] = 6 })
    T.eq(w.ns.GameGear.ItemStats({ id = 7100, e = 0, s = -17, u = 2752512, l = 39, q = 2 }), { [STR] = 13, [AGI] = 13 })
    T.eq(asked, { "item:7100:0:0:0:0:0:-17:2752512", "item:7100:0:0:0:0:0:-17:1376256" })
    T.eq(w.errors, {})
  end)

  T.it("names a suffixed worn item on its gear row in full, as worn", function()
    local w = World()
    local guild = w.ns.GuildData()
    w.INFO[7300] = { name = "Waldläufertunika", level = 39, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
    w.STATS[7300] = {}
    local full = "item:7300:0:0:0:0:0:-17:2752512"
    local tips = {}
    w.env.C_TooltipInfo.GetHyperlink = function(link)
      tips[#tips + 1] = link
      if link == full then return { lines = { { leftText = "Waldläufertunika des Tigers" }, { leftText = "Leder" } } } end
      return { lines = { { leftText = "Waldläufertunika" } } }
    end
    guild.gear["au tsch"].items[5] = { id = 7300, e = 0, s = -17, u = 2752512, l = 39, q = 2 }
    local function RowName()
      w.ns.UI.ShowMember(w.Member())
      local page = w.ns.UI.MemberPage()
      page:SetSize(1130 - 22, 760)
      page:Render()
      for _, r in ipairs(page.Gear.Rows) do if r.slot == 5 then return r.Name:GetText() end end
    end
    -- the game's GetItemInfo gives the bare base name: the tooltip of the full item string names it
    T.truthy(RowName():find("Waldläufertunika des Tigers", 1, true), RowName())
    local asked = #tips
    RowName()
    T.eq(#tips, asked) -- read once, not on every render
    -- a link that carries the full name is taken as it is
    w.env.GetItemInfo = function(item)
      local id = IdOf(item)
      local it = w.INFO[id]
      if not it then return nil end
      local link = id == 7300 and type(item) == "string" and item:find(":-17:", 1, true)
        and "|cff1eff00|H" .. item .. "|h[Waldläufertunika des Affen]|h|r" or ("item:" .. id)
      return it.name, link, 2, it.level, 1, "Rüstung", "Leder", 1, it.equipLoc, 134, 1, 4, 2, 2
    end
    guild.gear["au tsch"].items[5] = { id = 7300, e = 0, s = -17, u = 1376256, l = 39, q = 2 }
    T.truthy(RowName():find("Waldläufertunika des Affen", 1, true), RowName())
    -- an item without a suffix keeps its plain name
    guild.gear["au tsch"].items[5] = { id = 7300, e = 0, s = 0, l = 39, q = 2 }
    T.truthy(RowName():find("Waldläufertunika|r", 1, true), RowName())
    T.eq(w.errors, {})
  end)

  T.it("takes the stats bnet-sync stored with Sven's tiger tunic and offers no chest over it", function()
    local w = World()
    local guild = w.ns.GuildData()
    w.INFO[7200] = { name = "Waldläufertunika", level = 39, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
    w.STATS[7200] = {} -- the base item: no stats without the suffix
    w.INFO[710] = { name = "Barbarischer Harnisch", level = 40, reqLevel = 35, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
    w.STATS[710] = { [STR] = 7, [AGI] = 8, [STA] = 8 }
    guild.members["makira farron"].profs[165] = { ts = w.ns.Now(), src = "relay", rank = 250, max = 300, recipes = { 99710 } }
    w.env.GuildyDB.craftItems[99710] = 710
    local function Wear(st)
      local items = {}
      for slot, it in pairs(guild.gear["au tsch"].items) do items[slot] = it end
      items[5] = { id = 7200, e = 0, s = 0, l = 39, q = 2, st = st }
      guild.gear["au tsch"] = { ts = guild.gear["au tsch"].ts + 1, src = "api", items = items }
      w.ns.Fire("PROFS")
      local _, _, rows = w.Offered()
      local offered = false
      for _, row in ipairs(rows) do offered = offered or row.slot == 5 end
      return offered
    end
    T.eq(Wear({ [AGI] = 2 }), true) -- a weak chest by its stored stats: a chest is offered
    T.eq(Wear({ [STR] = 13, [AGI] = 13 }), false)
    T.eq(Wear(nil), false) -- nothing stored, the bare base item: not known, nothing offered
    T.eq(w.errors, {})
  end)

  -- The page's item tooltips (GuildyItemTooltip, GuildyWornTooltip) noted: shown, links, texts
  local function Watch(w, name)
    local tip = w.env[name]
    local log = { links = {}, texts = {} }
    local function Text(_, text) if type(text) == "string" then log.texts[#log.texts + 1] = text end end
    rawset(tip, "SetHyperlink", function(_, link)
      log.links[#log.links + 1] = link
      local first = w.env[name .. "TextLeft1"]
      if first then first:SetText("Item " .. link) end
    end)
    rawset(tip, "SetText", function(self, text) log.texts = {} Text(self, text) end)
    rawset(tip, "ClearLines", function() log.texts = {} end)
    rawset(tip, "AddLine", Text)
    rawset(tip, "AddDoubleLine", Text)
    function log.all() return table.concat(log.texts, "\n") end
    return log
  end
  local function Page(w)
    w.ns.UI.ShowMember(w.Member())
    local page = w.ns.UI.MemberPage()
    page:SetSize(1130 - 22, 760)
    page:Render()
    return page
  end

  T.it("shows the offer with the stat comparison in Guildy's own item tooltip", function()
    local w = World()
    local page = Page(w)
    local offer = Watch(w, "GuildyItemTooltip")
    local row = page.Upgrades.Rows[1]
    T.eq(row:IsShown(), true)
    local gameLink = false
    rawset(w.env.GameTooltip, "SetHyperlink", function() gameLink = true end)
    row.Item:GetScript("OnEnter")(row.Item)
    T.eq(offer.links, { "item:702" })
    T.eq(w.env.GuildyItemTooltip:IsShown(), true)
    local all = offer.all()
    T.truthy(all:find("+8 Beweglichkeit", 1, true), all)
    T.truthy(all:find("+3 Ausdauer", 1, true), all)
    T.truthy(all:find("Beweglichkeit", 1, true) < all:find("Ausdauer", 1, true), "by weight: " .. all)
    T.truthy(all:find(w.ns.L.UPGRADE_COMPARE, 1, true), all)
    T.eq(gameLink, false)
    T.eq(w.env.GameTooltip:IsShown(), false)
    T.eq(w.env.GuildyItemTooltip.supportsItemComparison, false) -- Blizzard's compare stays off
    T.eq(w.errors, {})
  end)

  T.it("shows the member's worn piece of the compared slot beside the offer, headed with their name", function()
    local w = World()
    local page = Page(w)
    local worn = Watch(w, "GuildyWornTooltip")
    w.env.GuildyWornTooltipTextLeft1 = w.env.CreateFrame("Frame")
    local row = page.Upgrades.Rows[1]
    row.NameHit:GetScript("OnEnter")(row.NameHit)
    T.eq(w.env.GuildyWornTooltip:IsShown(), true)
    T.eq(worn.links, { "item:7007:0:0:0:0:0:0" }) -- the weak leather chest
    local first = w.env.GuildyWornTooltipTextLeft1:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    T.truthy(first:find("Trägt Au Tsch\n", 1, true) == 1, first) -- the header line on top
    T.truthy(first:find("Item item:7007", 1, true), first)
    T.eq(w.errors, {})
  end)

  T.it("says the slot is empty when the member wears nothing there", function()
    local w = World()
    local guild = w.ns.GuildData()
    guild.gear["au tsch"].items[5] = nil
    guild.gear["au tsch"].ts = guild.gear["au tsch"].ts + 1
    local page = Page(w)
    local worn = Watch(w, "GuildyWornTooltip")
    local row = page.Upgrades.Rows[1]
    row.Item:GetScript("OnEnter")(row.Item)
    T.eq(w.env.GuildyWornTooltip:IsShown(), true)
    T.eq(worn.links, {})
    T.truthy(worn.all():find("Trägt Au Tsch", 1, true), worn.all())
    T.truthy(worn.all():find("Platz leer", 1, true), worn.all())
    T.eq(w.errors, {})
  end)

  T.it("names a worn piece that is not loaded yet, or shows dots", function()
    local w = World()
    local guild = w.ns.GuildData()
    guild.gear["au tsch"].items[5].st = { [AGI] = 6, [STA] = 5 } -- compared by its stored stats
    w.hidden[7007] = true
    local page = Page(w)
    local worn = Watch(w, "GuildyWornTooltip")
    local row = page.Upgrades.Rows[1]
    row.Item:GetScript("OnEnter")(row.Item)
    T.eq(worn.links, {})
    T.truthy(worn.all():find("…", 1, true), worn.all())
    T.eq(w.errors, {})
  end)

  T.it("shows a gear row's item without any comparison", function()
    local w = World()
    local page = Page(w)
    local item, worn = Watch(w, "GuildyItemTooltip"), Watch(w, "GuildyWornTooltip")
    local gameLink = false
    rawset(w.env.GameTooltip, "SetHyperlink", function() gameLink = true end)
    local row
    for _, r in ipairs(page.Gear.Rows) do if r.slot == 5 then row = r end end
    row:GetScript("OnEnter")(row)
    T.eq(item.links, { "item:7007:0:0:0:0:0:0" })
    T.eq(w.env.GuildyItemTooltip:IsShown(), true)
    T.eq(w.env.GuildyWornTooltip:IsShown(), false)
    T.eq(worn.links, {})
    T.eq(item.all():find(w.ns.L.UPGRADE_COMPARE, 1, true), nil)
    T.eq(gameLink, false)
    T.eq(w.errors, {})
  end)

  T.it("hides both item tooltips on leave and when the page hides", function()
    local w = World()
    local page = Page(w)
    local row = page.Upgrades.Rows[1]
    row.Item:GetScript("OnEnter")(row.Item)
    row.Item:GetScript("OnLeave")(row.Item)
    T.eq(w.env.GuildyItemTooltip:IsShown(), false)
    T.eq(w.env.GuildyWornTooltip:IsShown(), false)
    row.NameHit:GetScript("OnEnter")(row.NameHit)
    row.NameHit:GetScript("OnLeave")(row.NameHit)
    T.eq(w.env.GuildyWornTooltip:IsShown(), false)
    local gearRow = page.Gear.Rows[1]
    gearRow:GetScript("OnEnter")(gearRow)
    gearRow:GetScript("OnLeave")(gearRow)
    T.eq(w.env.GuildyItemTooltip:IsShown(), false)
    row.Item:GetScript("OnEnter")(row.Item)
    page:Hide()
    T.eq(w.env.GuildyItemTooltip:IsShown(), false)
    T.eq(w.env.GuildyWornTooltip:IsShown(), false)
    T.eq(w.errors, {})
  end)

  T.it("gives both item tooltips the look of Guildy's floating panels", function()
    local w = World()
    Page(w)
    local gold = w.ns.Widgets.GOLD
    for _, name in ipairs({ "GuildyItemTooltip", "GuildyWornTooltip" }) do
      local tip = w.env[name]
      local ground = tip.Ground
      T.eq(type(ground), "table", name .. ": its own ground")
      local _, _, _, alpha = ground:GetBackdropColor()
      T.eq(alpha, 1)
      local r, g, b, a = ground:GetBackdropBorderColor()
      T.eq({ r, g, b, a }, { gold[1], gold[2], gold[3], 1 })
      T.truthy(tip.Shadow and tip.Shadow[1], name .. ": a shadow around it")
    end
    T.eq(w.errors, {})
  end)
end)
