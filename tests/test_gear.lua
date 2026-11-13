local T = ...
local ns = T.pureNs()
local G = ns.Gear

local NOW = 1800000000
local DAY = 86400

local function info(map)
  return function(link) local v = map[link] if v then return v[1], v[2] end end
end

local function rec(items, ts, src)
  return { ts = ts or NOW, src = src or "seen", race = 4, sex = 3, items = items }
end

T.describe("Gear", function()
  T.it("reads the fields of an item link", function()
    T.eq({ G.ParseLink("|cff0070dd|Hitem:12345:1887:0:0:0:0:-17:0:60|h[X]|h|r") }, { 12345, 1887, -17, 0 })
    T.eq({ G.ParseLink("item:7") }, { 7, 0, 0, 0 })
    T.eq({ G.ParseLink("item:7484:0:0:0:0:0:-17:2752512:46") }, { 7484, 0, -17, 2752512 })
    T.eq(G.ParseLink(nil), nil)
    T.eq(G.ParseLink("spell:12"), nil)
    T.eq(G.ItemString({ id = 7, e = 1887, s = -17 }), "item:7:1887:0:0:0:0:-17")
  end)

  T.it("keeps the unique ID a random suffix needs and builds the full item string with it", function()
    -- Classic random suffixes: a negative suffix ID, the suffix factor in the unique ID
    T.eq(G.ItemString({ id = 7484, e = 0, s = -17, u = 2752512 }), "item:7484:0:0:0:0:0:-17:2752512")
    local links = { [5] = "item:7484:0:0:0:0:0:-17:2752512:46", [1] = "item:10:0:0:0:0:0:0:99887766:46" }
    local map = { [links[5]] = { 2, 39 }, [links[1]] = { 2, 30 } }
    local items = G.FromLinks(links, nil, info(map))
    T.eq(items[5], { id = 7484, e = 0, s = -17, u = 2752512, l = 39, q = 2 })
    T.eq(items[1], { id = 10, e = 0, s = 0, l = 30, q = 2 }) -- no suffix: the unique ID is of no use
  end)

  -- WoW Forever runs the modern engine: a random suffix ("des Tigers") is a bonus ID in the link
  -- (item:id:enchant:gem1..4:suffix:unique:linkLevel:spec:modifiersMask:context:numBonusIDs:bonusID...),
  -- not a suffix ID. Without it the game gives the base item: no stats, the bare name.
  local TIGER_LINK = "|cff1eff00|Hitem:7484::::::::46::::2:6655:1700:::::|h[Waldläufertunika des Tigers]|h|r"
  T.it("reads the bonus IDs of a modern item link and rebuilds the item string with them", function()
    T.eq({ G.ParseLink(TIGER_LINK) }, { 7484, 0, 0, 0, { 6655, 1700 } })
    T.eq(select(5, G.ParseLink("item:7484:0:0:0:0:0:-17:2752512:46")), nil) -- no bonus count: none
    T.eq(select(5, G.ParseLink("item:7484::::::::46::::0")), nil)
    T.eq(select(5, G.ParseLink("item:7484::::::::46::::3:1:2")), nil) -- fewer IDs than the count: not trusted
    T.eq(G.ItemString({ id = 7484, e = 0, s = 0, b = { 6655, 1700 } }), "item:7484:0:0:0:0:0:0:0:0:0:0:0:2:6655:1700")
    T.eq(G.ItemString({ id = 7484, e = 1887, s = -17, u = 5, b = { 6655 } }), "item:7484:1887:0:0:0:0:-17:5:0:0:0:0:1:6655")
    T.eq({ G.ParseLink(G.ItemString({ id = 7484, e = 0, s = 0, b = { 6655, 1700 } })) }, { 7484, 0, 0, 0, { 6655, 1700 } })
    local items = G.FromLinks({ [5] = TIGER_LINK }, { [5] = 7484 }, info({ [TIGER_LINK] = { 2, 39 } }))
    T.eq(items[5], { id = 7484, e = 0, s = 0, l = 39, q = 2, b = { 6655, 1700 } })
  end)

  T.it("sends the bonus IDs beside the item list and reads them back", function()
    local r = rec({ [5] = { id = 7484, e = 0, s = 0, l = 39, q = 2, b = { 6655, 1700 } },
      [6] = { id = 600, e = 0, s = 0, l = 39, q = 2 } }, NOW, "self")
    local wire = G.Wire(r)
    T.eq(wire.i, { "5:7484:0:0:39:2", "6:600:0:0:39:2" })
    T.eq(wire.b, { "5:6655,1700" })
    T.eq(G.Validate(wire, NOW), r)
    T.eq(G.Wire(rec({ [6] = { id = 600, e = 0, s = 0, l = 39, q = 2 } })).b, nil)
    local bad = G.Validate({ ts = NOW, i = { "5:7484:0:0:39:2", "6:600:0:0:39:2" }, b = { "5:x", "6:1.5", "9:7", "5" } }, NOW)
    T.eq(bad.items[5].b, nil)
    T.eq(bad.items[6].b, nil)
  end)

  T.it("takes a record of the same time that carries more of the items than the stored one", function()
    local plain = { [5] = { id = 7484, e = 0, s = 0, l = 39, q = 2 } }
    local full = { [5] = { id = 7484, e = 0, s = 0, l = 39, q = 2, b = { 6655 } } }
    local book = { a = rec(plain, NOW, "seen") }
    T.eq(G.Merge(book, "a", rec(full, NOW, "relay")), true)
    T.eq(book.a.items[5].b, { 6655 })
    T.eq(G.Merge(book, "a", rec(plain, NOW, "self")), false) -- the poorer one never comes back at the same time
    T.eq(G.Merge(book, "a", rec(full, NOW, "relay")), false) -- the same again: nothing new
    T.eq(G.Merge(book, "a", rec(full, NOW - 1, "api")), false) -- older stays out, rich or not
  end)

  T.it("keeps the member's own record against a richer api or seen one of the same time (as bnet-sync)", function()
    local plain = { [5] = { id = 7484, e = 0, s = 0, l = 39, q = 2 } }
    local full = { [5] = { id = 7484, e = 0, s = 0, l = 39, q = 2, b = { 6655 }, st = { ITEM_MOD_AGILITY_SHORT = 13 } } }
    local book = { a = rec(plain, NOW, "self") }
    T.eq(G.Merge(book, "a", rec(full, NOW, "api")), false)
    T.eq(G.Merge(book, "a", rec(full, NOW, "seen")), false)
    T.eq(book.a.src, "self")
    T.eq(G.Merge(book, "a", rec(full, NOW + 1, "api")), true) -- a newer one does replace it
    book.a = rec(plain, NOW, "self")
    T.eq(G.Merge(book, "a", rec(full, NOW, "relay")), true) -- a relayed copy of the same reading, richer
  end)

  T.it("sends the unique ID and stored stats beside the item list, which old clients read unchanged", function()
    local r = rec({ [5] = { id = 7484, e = 0, s = -17, u = 2752512, l = 39, q = 2 },
      [6] = { id = 600, e = 0, s = 0, l = 39, q = 2, st = { ITEM_MOD_AGILITY_SHORT = 13, ITEM_MOD_STRENGTH_SHORT = 13 } },
      [7] = { id = 700, e = 0, s = 0, l = 39, q = 2, st = {} } }, NOW, "api")
    local wire = G.Wire(r)
    T.eq(wire.i, { "5:7484:0:-17:39:2", "6:600:0:0:39:2", "7:700:0:0:39:2" }) -- six fields, as before
    T.eq(wire.u, { "5:2752512" })
    T.eq(wire.t, { "6:AGILITY=13,STRENGTH=13", "7:" })
    T.eq(G.Validate(wire, NOW), r)
    -- an old client's message has neither
    T.eq(G.Validate({ ts = NOW, i = { "5:7484:0:-17:39:2" } }, NOW).items[5], { id = 7484, e = 0, s = -17, l = 39, q = 2 })
    -- wrong entries are dropped, the item stays
    local bad = G.Validate({ ts = NOW, i = { "5:7484:0:-17:39:2", "6:600:0:0:39:2" },
      u = { "5:1.5", "9:7", "x" }, t = { "6:AGILITY=x", "5:agility=3", "9:AGILITY=3" } }, NOW)
    T.eq(bad.items[5], { id = 7484, e = 0, s = -17, l = 39, q = 2 })
    T.eq(bad.items[6], { id = 600, e = 0, s = 0, l = 39, q = 2 })
  end)

  T.it("makes items from the links of a complete read only", function()
    local links = { [1] = "item:10:0", [4] = "item:44", [5] = "item:50:1887", [19] = "item:190" }
    local ids = { [1] = 10, [4] = 44, [5] = 50, [19] = 190 }
    local map = { ["item:10:0"] = { 2, 30 }, ["item:44"] = { 1, 1 }, ["item:50:1887"] = { 9, 40 }, ["item:190"] = { -1, 1 } }
    local items = G.FromLinks(links, ids, info(map))
    T.eq(items[5], { id = 50, e = 1887, s = 0, l = 40, q = 5 })
    T.eq(items[4].id, 44)
    T.eq(items[19].q, 0)
    T.eq(items[1], { id = 10, e = 0, s = 0, l = 30, q = 2 })
    ids[7] = 70 -- an item ID without its link: incomplete
    T.eq(G.FromLinks(links, ids, info(map)), nil)
    ids[7] = nil
    map["item:44"] = nil -- item info not loaded
    T.eq(G.FromLinks(links, ids, info(map)), nil)
  end)

  T.it("checks a record from the guild", function()
    local good = { ts = NOW, src = "self", r = 4, x = 3, i = { "5:12345:1887:0:52:3", "1:100:0:-17:50:2" } }
    T.eq(G.Validate(good, NOW), { ts = NOW, src = "self", race = 4, sex = 3, items = {
      [5] = { id = 12345, e = 1887, s = 0, l = 52, q = 3 }, [1] = { id = 100, e = 0, s = -17, l = 50, q = 2 } } })
    local bad = G.Validate({ ts = NOW, src = "boss", r = -1, x = 1, i = { "0:1:0:0:1:1", "20:1:0:0:1:1",
      "2:1.5:0:0:1:1", "3:5:0:0:1:9", "6:5:0:0:1.5:1", "7:5:0:0:10:1", "junk" } }, NOW)
    T.eq(bad, { ts = NOW, src = "relay", items = { [7] = { id = 5, e = 0, s = 0, l = 10, q = 1 } } })
    T.eq(G.Validate({ ts = NOW + 301, i = {} }, NOW), nil)
    T.eq(G.Validate({ i = {} }, NOW), nil)
    T.eq(G.Validate("x", NOW), nil)
    T.eq(G.Validate({ ts = NOW, r = 2.5, x = 2, i = { "1:1:0:0:1:1" } }, NOW).race, nil)
    local many = {}
    for i = 1, 40 do many[i] = ((i - 1) % 19 + 1) .. ":" .. (1000 + i) .. ":0:0:10:2" end
    local read = G.Validate({ ts = NOW, i = many }, NOW)
    T.eq(read.items[19].id, 1019) -- the first 19 strings only
    T.eq(read.items[1].id, 1001)
  end)

  T.it("refuses a record without items, so it never wipes good gear", function()
    T.eq(G.Validate({ ts = NOW, src = "self", r = 4, x = 3, i = {} }, NOW), nil)
    T.eq(G.Validate({ ts = NOW, i = "x" }, NOW), nil)
    T.eq(G.Validate({ ts = NOW, i = { "junk", "0:1:0:0:1:1" } }, NOW), nil) -- nothing usable left
    local book = { a = rec({ [1] = { id = 100, e = 0, s = 0, l = 50, q = 2 } }, NOW, "seen") }
    T.eq(G.Merge(book, "a", rec({}, NOW + 1, "relay")), false)
    T.eq(book.a.items[1].id, 100)
  end)

  T.it("sends a record and reads it back the same", function()
    local r = rec({ [1] = { id = 100, e = 0, s = -17, l = 50, q = 2 }, [4] = { id = 44, e = 0, s = 0, l = 1, q = 1 },
      [16] = { id = 160, e = 1900, s = 0, l = 60, q = 4 } }, NOW, "self")
    local wire = G.Wire(r)
    T.eq(wire.i, { "1:100:0:-17:50:2", "4:44:0:0:1:1", "16:160:1900:0:60:4" })
    T.eq(G.Validate(wire, NOW), r)
  end)

  T.it("merges: newer wins, the member's own reading at the same time", function()
    local ONE = { [1] = { id = 1, e = 0, s = 0, l = 1, q = 1 } }
    local book = { a = rec(ONE, NOW, "seen") }
    T.eq(G.Merge(book, "a", rec(ONE, NOW - 1, "self")), false)
    T.eq(G.Merge(book, "a", rec(ONE, NOW, "relay")), false)
    T.eq(G.Merge(book, "a", rec(ONE, NOW, "self")), true)
    T.eq(book.a.src, "self")
    T.eq(G.Merge(book, "a", rec(ONE, NOW, "relay")), false)
    T.eq(book.a.src, "self")
    T.eq(G.Merge(book, "a", rec(ONE, NOW + 1, "relay")), true)
    T.eq(G.Merge(book, "b", rec(ONE, NOW, "api")), true)
  end)

  T.it("offers young records only and prunes members who left", function()
    local book = { a = rec({}, NOW), b = rec({}, NOW - 61 * DAY), c = rec({}, NOW - DAY) }
    T.eq(G.Digest(book, NOW), { a = NOW, c = NOW - DAY })
    T.eq(G.Prune(book, { a = true }), 2)
    T.eq(book.b, nil)
    T.truthy(book.a)
  end)

  T.it("averages the item levels of the listed slots", function()
    local r = rec({ [1] = { id = 1, e = 0, s = 0, l = 30, q = 2 }, [5] = { id = 2, e = 0, s = 0, l = 20, q = 2 },
      [16] = { id = 3, e = 0, s = 0, l = 40, q = 2 }, [4] = { id = 4, e = 0, s = 0, l = 1, q = 1 } })
    T.eq(G.Average(r), 300)
    T.eq(G.Average(rec({})), nil)
  end)

  T.it("flags the enchantable slots without an enchantment", function()
    local locs = { [17] = "INVTYPE_HOLDABLE", [27] = "INVTYPE_SHIELD" }
    local function loc(id) return locs[id] end
    local items = { [5] = { id = 5, e = 0, s = 0, l = 1, q = 1 }, [8] = { id = 8, e = 0, s = 0, l = 1, q = 1 },
      [1] = { id = 1, e = 0, s = 0, l = 1, q = 1 }, [15] = { id = 15, e = 20, s = 0, l = 1, q = 1 },
      [17] = { id = 17, e = 0, s = 0, l = 1, q = 1 } }
    local set, count = G.Unenchanted(rec(items), loc)
    T.eq(set, { [5] = true, [8] = true })
    T.eq(count, 2)
    items[17] = { id = 27, e = 0, s = 0, l = 1, q = 1 }
    set, count = G.Unenchanted(rec(items), loc)
    T.eq(set[17], true)
    T.eq(count, 3)
    items[17] = { id = 99, e = 0, s = 0, l = 1, q = 1 } -- equip location not known yet
    T.eq(select(2, G.Unenchanted(rec(items), loc)), 2)
    items[17] = nil -- empty off hand under a two-hander
    T.eq(select(2, G.Unenchanted(rec(items), loc)), 2)
  end)

  T.it("computes the ready mark from at least five members of the level", function()
    local list = { { 60, 400 }, { 60, 420 }, { 60, 450 }, { 60, 470 }, { 59, 100 } }
    T.eq(G.ReadyMark(list, 60), nil)
    list[#list + 1] = { 60, 500 }
    T.eq(G.ReadyMark(list, 60), 450)
    list[#list + 1] = { 60, 510 }
    T.eq(G.ReadyMark(list, 60), 450) -- even count: the lower of the two middle values
  end)

  T.it("finds the enchant line in the tooltip", function()
    T.eq(G.EnchantLine({ "Name", "Brust", "|cff00ff00+4 Werte|r", "Rüstung" }, { "Name", "Brust", "Rüstung" }), "+4 Werte")
    T.eq(G.EnchantLine({ "Name", "Brust" }, { "Name", "Brust" }), nil)
    T.eq(G.EnchantLine({ "A", "A", "B" }, { "A", "B" }), "A")
  end)

  T.it("keeps the enchant texts per language", function()
    local db = {}
    local names = G.EnchantCache(db, "deDE")
    names[1887] = "+4 Werte"
    T.eq(G.EnchantCache(db, "deDE")[1887], "+4 Werte")
    T.eq(G.EnchantCache(db, "frFR")[1887], nil)
    T.eq(db.enchantText.locale, "frFR")
  end)

  T.it("fits the list into the box", function()
    T.eq((G.Fit(17 * 18 + 52, 900)), 18)
    T.eq((G.Fit(300, 900)), 18)
    T.eq((G.Fit(17 * 24 + 52, 900)), 24)
    local _, barW, enchantW = G.Fit(400, 900)
    T.eq(barW, 130)
    T.eq(enchantW, 200)
    _, barW, enchantW = G.Fit(400, 560)
    T.eq(barW, 60)
    T.truthy(enchantW < 200, "enchant text narrower")
    _, barW, enchantW = G.Fit(400, 300)
    T.eq(barW, 60)
    T.eq(enchantW, 0)
  end)
end)
