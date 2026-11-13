-- Talent specs in the stubbed client (tests/wow.lua): the own talents read and shared, a member's read
-- inside Guildy's inspect, records from the guild, the upgrades scored by the spec, the heading text.
local T = ...

local AGI, STR, STA, INT, SPI, AP = "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_STAMINA_SHORT",
  "ITEM_MOD_INTELLECT_SHORT", "ITEM_MOD_SPIRIT_SHORT", "ITEM_MOD_ATTACK_POWER_SHORT"

local function IdOf(item)
  return type(item) == "number" and item or tonumber(tostring(item):match("item:(%d+)"))
end

-- A world with the player Ran Fred (a mage), a feral druid Au Tsch (level 46) in leather and Makira who
-- makes pieces; every message Guildy sends is kept
local function World()
  local w = { INFO = {}, STATS = {}, sent = {}, clock = 1000, notified = 0, inspectReads = 0 }
  w.own = { { "Arkan", 135932, 0, "MageArcane" }, { "Feuer", 135810, 31, "MageFire" }, { "Frost", 135846, 5, "MageFrost" } }
  w.inspected = { { "Gleichgewicht", 1, 0, "DruidBalance" }, { "Wildheit", 2, 31, "DruidFeralCombat" },
    { "Wiederherstellung", 3, 20, "DruidRestoration" } }
  local world = dofile(T.testsDir .. "/wow.lua")(T, {
    roster = {
      { "Ran-Fred", "Offizier", 1, 60, "Magier", "Sturmwind", "", "", true, 0, "MAGE", nil, nil, false, nil, nil, "Player-1-01" },
      { "Makira-Farron", "Offizier", 1, 50, "Paladin", "Eisenschmiede", "", "", true, 0, "PALADIN", nil, nil, false, nil, nil, "Player-1-02" },
      { "Au-Tsch", "Haifutter", 2, 46, "Druide", "Dämmerwald", "", "", true, 0, "DRUID", nil, nil, false, nil, nil, "Player-1-03" },
    },
    setup = function(env)
      env.GetTime = function() return w.clock end
      env.C_ChatInfo.SendAddonMessage = function(_, text) w.sent[#w.sent + 1] = text end
      env.C_Item = {
        IsItemDataCachedByID = function(id) return w.INFO[id] ~= nil end,
        GetItemStats = function(link)
          local stats = w.STATS[IdOf(link)]
          if not stats then return nil end
          local copy = {}
          for k, v in pairs(stats) do copy[k] = v end
          return copy
        end,
      }
      env.GetItemInfo = function(item)
        local it = w.INFO[IdOf(item)]
        if it then
          return it.name, "item:" .. IdOf(item), it.quality or 2, it.level, it.reqLevel or 1, "Rüstung", "Leder", 1, it.equipLoc,
            134, 1, it.classID or 4, it.subclassID or 2, it.bind or 2
        end
      end
      env.C_TooltipInfo = { GetItemByID = function(id)
        local it = w.INFO[id]
        return it and { lines = { { leftText = it.name } } } or nil
      end }
      env.LOCALIZED_CLASS_NAMES_MALE = { DRUID = "Druide", PALADIN = "Paladin", MAGE = "Magier" }
      env.GetNumTalentTabs = function() return 3 end
      env.GetTalentTabInfo = function(i, inspect)
        if inspect then
          w.inspectReads = w.inspectReads + 1
          return unpack(w.inspected[i])
        end
        return unpack(w.own[i])
      end
      env.NotifyInspect = function() w.notified = w.notified + 1 end
      env.ClearInspectPlayer = function() end
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
  guild.gear["au tsch"] = { ts = w.ns.Now() - 100, src = "seen", items = items }
  w.INFO[702] = { name = "Wildlederweste", level = 44, reqLevel = 40, equipLoc = "INVTYPE_CHEST", subclassID = 2 }
  w.STATS[702] = { [AGI] = 14, [STA] = 8 }
  guild.members["makira farron"] = guild.members["makira farron"] or {}
  guild.members["makira farron"].profs = { [165] = { ts = w.ns.Now(), src = "relay", rank = 250, max = 300, recipes = { 99702 } } }
  w.env.GuildyDB.craftItems = { [99702] = 702 }
  w.sent = {}

  function w.Member() return w.ns.Roster.Find("Au Tsch") end
  function w.Offered()
    local rows, state, _, spec, tree = w.ns.GameGear.UpgradesFor(w.Member())
    local ids = {}
    for _, row in ipairs(rows) do ids[#ids + 1] = row.itemID end
    return ids, state, spec, tree
  end
  -- every message sent so far of kind, once time let them all out
  function w.Messages(kind)
    for _ = 1, 200 do
      if w.ns.Sync.Waiting() == 0 then break end
      w.clock = w.clock + 20
      w.ns.Sync.Pump()
    end
    local P = w.ns.Protocol
    local assembler, found = P.NewAssembler(), {}
    for _, part in ipairs(w.sent) do
      local payload = P.AddPart(assembler, "x", part, 0)
      local envelope = payload and P.Decode(payload)
      if envelope and envelope.t == kind then found[#found + 1] = envelope.d end
    end
    return found
  end
  -- a message from another Guildy user
  function w.Receive(kind, data, sender)
    local P = w.ns.Protocol
    w.clock = w.clock + 1
    for _, part in ipairs(P.Chunk("ab" .. w.clock, P.Encode(kind, data, "1.8.0"))) do
      w.ns.Sync.OnAddonMessage(P.PREFIX, part, "GUILD", sender or "Au-Tsch")
    end
  end
  return w
end

T.describe("Talent specs in the game", function()
  T.it("reads the own talent points at login and shares them with the guild", function()
    local w = World()
    T.eq(w.ns.GuildData().talents["ran fred"].trees, { 0, 31, 5 }) -- read with the own statistics at login
    w.ns.GuildData().talents = nil
    w.ns.GameTalents.ReadOwn()
    local rec = w.ns.GuildData().talents["ran fred"]
    T.eq(rec.trees, { 0, 31, 5 })
    T.eq(rec.src, "self")
    local gear = w.Messages("GEAR")
    T.eq(#gear, 1)
    T.eq(gear[1].m, "Ran Fred")
    T.eq(gear[1].k.p, { 0, 31, 5 })
    T.eq(gear[1].g, nil) -- no own gear known in this world: the talents alone
    T.eq(w.env.GuildyDB.talentNames.classes.MAGE, { "Arkan", "Feuer", "Frost" })
    T.eq(w.errors, {})
  end)

  T.it("keeps unchanged own talents and sends nothing again", function()
    local w = World()
    w.ns.GuildData().talents = nil
    w.ns.GameTalents.ReadOwn()
    local ts = w.ns.GuildData().talents["ran fred"].ts
    w.ns.GameTalents.ReadOwn()
    T.eq(w.ns.GuildData().talents["ran fred"].ts, ts)
    T.eq(#w.Messages("GEAR"), 1)
    T.eq(w.errors, {})
  end)

  T.it("stores but never sends the own talents with share off", function()
    local w = World()
    w.ns.Settings().share = false
    w.ns.GuildData().talents = nil
    w.ns.GameTalents.ReadOwn()
    T.eq(w.ns.GuildData().talents["ran fred"].trees, { 0, 31, 5 })
    T.eq(#w.Messages("GEAR"), 0)
    -- nor on a summary that asks for them
    w.Receive("SUM", { d = {}, k = { ["ran fred"] = 1 } }, "Makira-Farron")
    w.RunTimers(10)
    T.eq(#w.Messages("GEAR"), 0)
    T.eq(w.errors, {})
  end)

  T.it("reads again a moment after points were spent", function()
    local w = World()
    w.ns.GameTalents.ReadOwn()
    w.own[2][3] = 32
    w.Fire("CHARACTER_POINTS_CHANGED", -1)
    T.eq(w.ns.GuildData().talents["ran fred"].trees, { 0, 31, 5 })
    w.RunTimers()
    T.eq(w.ns.GuildData().talents["ran fred"].trees, { 0, 32, 5 })
    T.eq(w.errors, {})
  end)

  T.it("reads nothing from a client without the talent API or with secret values", function()
    local w = World()
    w.ns.GuildData().talents = nil
    w.env.GetTalentTabInfo = nil
    w.ns.GameTalents.ReadOwn()
    T.eq((w.ns.GuildData().talents or {})["ran fred"], nil)
    w.env.GetTalentTabInfo = function(i) if i == 2 then return "Feuer", 1, w.SECRET end return "Arkan", 1, 0 end
    w.ns.GameTalents.ReadOwn()
    T.eq((w.ns.GuildData().talents or {})["ran fred"], nil)
    T.eq(w.errors, {})
  end)

  T.it("takes a member's talents from the guild, validated, beside the gear", function()
    local w = World()
    local guild = w.ns.GuildData()
    local gearWire = w.ns.Gear.Wire({ ts = w.ns.Now(), src = "self", items = { [1] = { id = 7001, e = 0, s = 0, l = 41, q = 2 } } })
    w.Receive("GEAR", { m = "Au Tsch", g = gearWire, k = { ts = w.ns.Now(), src = "self", p = { 0, 31, 20 } } })
    T.eq(guild.talents["au tsch"].trees, { 0, 31, 20 })
    T.eq(guild.talents["au tsch"].src, "self")
    T.eq(guild.gear["au tsch"].items[1].l, 41)
    -- a wrong record is dropped, the gear beside it still taken
    gearWire.ts = gearWire.ts + 5
    w.Receive("GEAR", { m = "Au Tsch", g = gearWire, k = { ts = w.ns.Now() + 5, p = { 0, 99999, 20 } } })
    T.eq(guild.talents["au tsch"].trees, { 0, 31, 20 })
    T.eq(guild.gear["au tsch"].ts, gearWire.ts)
    -- an older Guildy's message without talents: the gear as before, the talents kept
    gearWire.ts = gearWire.ts + 5
    w.Receive("GEAR", { m = "Au Tsch", g = gearWire })
    T.eq(guild.gear["au tsch"].ts, gearWire.ts)
    T.eq(guild.talents["au tsch"].trees, { 0, 31, 20 })
    -- talents alone, relayed by someone else
    w.Receive("GEAR", { m = "Au Tsch", k = { ts = w.ns.Now() + 50, src = "self", p = { 0, 11, 40 } } }, "Makira-Farron")
    T.eq(guild.talents["au tsch"].trees, { 0, 11, 40 })
    T.eq(guild.talents["au tsch"].src, "relay")
    T.eq(w.errors, {})
  end)

  T.it("offers known talents on a summary that names older ones, not to an older Guildy", function()
    local w = World()
    local guild = w.ns.GuildData()
    guild.talents = { ["au tsch"] = { ts = w.ns.Now(), src = "seen", trees = { 0, 31, 20 } } }
    local mine = w.ns.Talents.Digest(guild.talents, w.ns.Now())
    w.Receive("SUM", { d = {}, g = w.ns.Gear.Digest(guild.gear, w.ns.Now()) }, "Makira-Farron")
    w.RunTimers(10)
    T.eq(#w.Messages("GEAR"), 0)
    w.Receive("SUM", { d = {}, g = w.ns.Gear.Digest(guild.gear, w.ns.Now()), k = { ["au tsch"] = mine["au tsch"] - 10 } },
      "Makira-Farron")
    w.RunTimers(10)
    local gear = w.Messages("GEAR")
    T.eq(#gear, 1)
    T.eq(gear[1].k.p, { 0, 31, 20 })
    T.truthy(gear[1].g) -- the gear rides along
    T.eq(w.errors, {})
  end)

  T.it("says what it knows of talents in its summary", function()
    local w = World()
    local guild = w.ns.GuildData()
    guild.talents = { ["au tsch"] = { ts = w.ns.Now(), src = "seen", trees = { 0, 31, 20 } } }
    w.ns.Sync.SendSummary()
    local sum = w.Messages("SUM")
    T.eq(sum[#sum].k, { ["au tsch"] = w.ns.Now() })
    T.eq(w.errors, {})
  end)

  T.it("reads a member's talents only inside Guildy's own inspect", function()
    local w = World()
    local guild = w.ns.GuildData()
    w.env.UnitGUID = function(unit) if unit == "target" then return "Player-1-03" end end
    w.env.UnitClass = function(unit) if unit == "target" then return "Druide", "DRUID" end return "Magier", "MAGE" end
    w.env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and (slot == 1 or slot == 3) then return "|cff1eff00|Hitem:700" .. slot .. "::::::::|h[Leder]|h|r" end
    end
    w.env.GetInventoryItemID = function(unit, slot) if unit == "target" and (slot == 1 or slot == 3) then return 7000 + slot end end
    -- an inspect someone else started (Blizzard's window): nothing is read
    w.Fire("INSPECT_READY", "Player-1-03")
    w.RunTimers()
    T.eq(w.inspectReads, 0)
    local request = { key = "au tsch", name = "Au Tsch", guid = "Player-1-03", unit = "target" }
    local job = w.ns.GameStats.StartInspect(request, {})
    T.eq(w.notified, 1)
    w.ns.GameStats.StatsDone(request, {}, job)
    T.eq(w.inspectReads, 0)
    w.Fire("INSPECT_READY", "Player-1-03")
    w.RunTimers(3)
    T.eq(w.notified, 1) -- no inspect of its own for the talents
    T.truthy(w.inspectReads > 0)
    T.eq(guild.talents["au tsch"].trees, { 0, 31, 20 })
    T.eq(guild.talents["au tsch"].src, "seen")
    T.eq(w.env.GuildyDB.talentNames.classes.DRUID, { "Gleichgewicht", "Wildheit", "Wiederherstellung" })
    local gear = w.Messages("GEAR")
    T.eq(gear[#gear].k.p, { 0, 31, 20 })
    T.eq(w.errors, {})
  end)

  T.it("stores no inspected talents when the game gives no points", function()
    local w = World()
    w.inspected = { { "Gleichgewicht", 1, 0 }, { "Wildheit", 2, 0 }, { "Wiederherstellung", 3, 0 } }
    w.env.UnitGUID = function(unit) if unit == "target" then return "Player-1-03" end end
    w.env.UnitClass = function() return "Druide", "DRUID" end
    w.env.GetInventoryItemLink = function(unit, slot)
      if unit == "target" and slot == 1 then return "|cff1eff00|Hitem:7001::::::::|h[Leder]|h|r" end
    end
    local request = { key = "au tsch", name = "Au Tsch", guid = "Player-1-03", unit = "target" }
    local job = w.ns.GameStats.StartInspect(request, {})
    w.ns.GameStats.StatsDone(request, {}, job)
    w.Fire("INSPECT_READY", "Player-1-03")
    w.RunTimers(3)
    T.eq((w.ns.GuildData().talents or {})["au tsch"], nil)
    T.eq(w.errors, {})
  end)

  T.it("forgets the talents of members who left", function()
    local w = World()
    local guild = w.ns.GuildData()
    guild.talents = { ["gone guy"] = { ts = 1, src = "seen", trees = { 1, 2, 3 } },
      ["au tsch"] = { ts = 1, src = "seen", trees = { 0, 31, 20 } } }
    w.Fire("GUILD_ROSTER_UPDATE")
    w.RunTimers()
    T.eq(guild.talents["gone guy"], nil)
    T.truthy(guild.talents["au tsch"])
    T.eq(w.errors, {})
  end)
end)

T.describe("Upgrades by talent spec in the game", function()
  T.it("falls back to the worn gear while the spec is unknown, and works out anew when the talents change", function()
    local w = World()
    local guild = w.ns.GuildData()
    local ids, state, spec = w.Offered()
    T.eq(ids, { 702 })
    T.eq(spec, nil)
    -- balance: the agility chest is nothing for a caster
    guild.talents = { ["au tsch"] = { ts = w.ns.Now(), src = "seen", trees = { 31, 0, 20 } } }
    ids, state, spec = w.Offered()
    T.eq(ids, {})
    T.eq(state, "none")
    T.eq(spec, "DRUID_BALANCE")
    -- feral in cat gear: cat weights
    guild.talents["au tsch"] = { ts = w.ns.Now() + 1, src = "seen", trees = { 0, 31, 20 } }
    local tree
    ids, state, spec, tree = w.Offered()
    T.eq(ids, { 702 })
    T.eq(spec, "DRUID_CAT")
    T.eq(tree, 2)
    T.eq(w.errors, {})
  end)

  T.it("says in the upgrades heading what the pieces are rated for", function()
    local w = World()
    local L = w.ns.L
    local page
    local function Basis()
      w.ns.UI.ShowMember(w.Member())
      page = w.ns.UI.MemberPage()
      page:SetSize(1130 - 22, 760)
      page:Render()
      return page.Upgrades.Basis:GetText()
    end
    T.eq(Basis(), L.UPGRADES_RATED_GEAR)
    local guild = w.ns.GuildData()
    guild.talents = { ["au tsch"] = { ts = w.ns.Now(), src = "seen", trees = { 0, 31, 20 } } }
    w.ns.Fire("TALENTS", "au tsch")
    T.eq(Basis(), L.UPGRADES_RATED_SPEC:format(L.TALENT_CAT:format(L.TALENT_TREE:format(2))))
    w.env.GuildyDB.talentNames = { locale = "deDE", classes = { DRUID = { "Gleichgewicht", "Wildheit", "Wiederherstellung" } } }
    guild.talents["au tsch"] = { ts = w.ns.Now() + 1, src = "seen", trees = { 0, 11, 40 } }
    T.eq(Basis(), L.UPGRADES_RATED_SPEC:format("Wiederherstellung"))
    w.env.GuildyDB.talentNames.locale = "enUS" -- names of another language are not used
    guild.talents["au tsch"] = { ts = w.ns.Now() + 2, src = "seen", trees = { 0, 31, 20 } }
    T.eq(Basis(), L.UPGRADES_RATED_SPEC:format(L.TALENT_CAT:format(L.TALENT_TREE:format(2))))
    T.eq(w.errors, {})
  end)
end)
