local T = ...
local ns = T.pureNs()
local Bank = ns.Bank

local HOUR, DAY = 3600, 86400
local NOW = 1700000000

-- an item entry read at `at`, `hours` old
local function Item(kind, who, id, count, hours, at)
  at = at or NOW
  return { k = kind, w = who, i = "item:" .. id, id = id, n = count, a = 1, ts = at - hours * HOUR, at = at, by = "Reader" }
end

local function Gold(kind, who, copper, hours, at)
  at = at or NOW
  return { k = kind, w = who, c = copper, ts = at - hours * HOUR, at = at, by = "Reader" }
end

local function Kinds(run)
  local out = {}
  for i, e in ipairs(run) do out[i] = e.k == "gap" and "gap" or (e.w .. ":" .. (e.n or e.c)) end
  return table.concat(out, " ")
end

T.describe("Bank.ItemOf", function()
  T.it("takes item string, id and name from a link", function()
    local item, id, name = Bank.ItemOf("|cffffffff|Hitem:13446::::::::60:::::|h[Major Healing Potion]|h|r")
    T.eq(item, "item:13446::::::::60")
    T.eq(id, 13446)
    T.eq(name, "Major Healing Potion")
    T.eq(Bank.ItemOf("item:5:::"), "item:5")
    T.eq(Bank.ItemOf("nothing"), nil)
    T.eq(Bank.ItemOf(nil), nil)
  end)
end)

T.describe("Bank.Merge", function()
  T.it("adds what a later reading shows beyond the known entries", function()
    local known = { Item("deposit", "A", 1, 5, 3), Item("withdraw", "B", 1, 2, 2) }
    -- an hour later: the same two, one hour older, and a new one
    local later = NOW + HOUR
    local run = { Item("deposit", "A", 1, 5, 4, later), Item("withdraw", "B", 1, 2, 3, later), Item("deposit", "C", 2, 1, 0, later) }
    local merged, added = Bank.Merge(known, run)
    T.eq(Kinds(merged), "A:5 B:2 C:1")
    T.eq(added, 1)
    T.eq(merged[1].at, NOW) -- the first reading of an entry stays
  end)

  T.it("keeps equal entries apart: the same deposit three times is three entries", function()
    local known = { Item("deposit", "A", 1, 20, 1), Item("deposit", "A", 1, 20, 1) }
    local run = { Item("deposit", "A", 1, 20, 1), Item("deposit", "A", 1, 20, 1), Item("deposit", "A", 1, 20, 0) }
    local merged, added = Bank.Merge(known, run)
    T.eq(#merged, 3)
    T.eq(added, 1)
  end)

  T.it("reads nothing twice, however often the bank is opened", function()
    local known = {}
    for round = 0, 5 do
      local at = NOW + round * 600
      local run = { Item("deposit", "A", 1, 5, 30, at), Item("withdraw", "B", 2, 1, 7, at), Gold("repair", "C", 420, 7, at) }
      known = Bank.Merge(known, run)
    end
    T.eq(#known, 3)
  end)

  T.it("puts entries of the other side in where they belong", function()
    local mine = { Item("deposit", "A", 1, 1, 9), Item("deposit", "C", 1, 3, 2) }
    local theirs = { Item("deposit", "A", 1, 1, 9), Item("deposit", "B", 1, 2, 5), Item("deposit", "C", 1, 3, 2) }
    T.eq(Kinds((Bank.Merge(mine, theirs))), "A:1 B:2 C:3")
    T.eq(Kinds((Bank.Merge(theirs, mine))), "A:1 B:2 C:3")
    -- within the same hour the order of the longer run decides
    local short = { Item("deposit", "C", 1, 3, 2) }
    local long = { Item("deposit", "B", 1, 2, 2), Item("deposit", "C", 1, 3, 2) }
    T.eq(Kinds((Bank.Merge(short, long))), "B:2 C:3")
    T.eq(Kinds((Bank.Merge(long, short))), "B:2 C:3")
  end)

  T.it("marks a gap when a full log joins nothing known", function()
    local known = { Item("deposit", "A", 1, 1, 200), Item("deposit", "A", 1, 2, 190) }
    local entries = {}
    for i = 1, Bank.LOG_LIMIT do entries[i] = Item("deposit", "B", 2, i, 30 - i) end
    local merged, added = Bank.Merge(known, Bank.Run(entries))
    T.eq(added, Bank.LOG_LIMIT)
    T.eq(#merged, Bank.LOG_LIMIT + 3)
    T.eq(merged[3].k, "gap")
    -- the same reading again changes nothing
    local again = Bank.Merge(merged, Bank.Run(entries))
    T.eq(#again, #merged)
  end)

  T.it("marks no gap when the full log continues the known entries", function()
    local known = { Item("deposit", "A", 1, 1, 40), Item("deposit", "B", 2, 1, 29) }
    local entries = {}
    for i = 1, Bank.LOG_LIMIT do entries[i] = Item("deposit", "B", 2, i, 30 - i) end
    local merged = Bank.Merge(known, Bank.Run(entries))
    T.eq(#merged, Bank.LOG_LIMIT + 1)
    for _, e in ipairs(merged) do T.truthy(e.k ~= "gap", "no gap") end
  end)

  T.it("closes a gap when someone else knows what happened in it", function()
    local old = Item("deposit", "A", 1, 1, 200)
    local mid = { Item("deposit", "M", 3, 1, 100), Item("deposit", "M", 3, 2, 90) }
    local new = Item("deposit", "B", 2, 9, 5)
    local mine = { old, { k = "gap", ts = new.ts }, new }
    local theirs = { Item("deposit", "A", 1, 1, 200), mid[1], mid[2], Item("deposit", "B", 2, 9, 5) }
    T.eq(Kinds((Bank.Merge(mine, theirs))), "A:1 M:1 M:2 B:9")
    T.eq(Kinds((Bank.Merge(theirs, mine))), "A:1 M:1 M:2 B:9")
    -- theirs starts with that entry: it does not know what stood before it, the gap stays
    T.eq(Kinds((Bank.Merge(mine, { Item("deposit", "B", 2, 9, 5) }))), "A:1 gap B:9")
  end)

  T.it("never starts or ends with a gap and keeps the newest entries when it grows too long", function()
    local run = { { k = "gap", ts = NOW - 5 * HOUR }, Item("deposit", "A", 1, 1, 5) }
    T.eq(Kinds((Bank.Merge({}, run))), "A:1")
    local long = {}
    for i = 1, Bank.MAX_ENTRIES + 10 do long[i] = Item("deposit", "A", 1, i, 0, NOW - (Bank.MAX_ENTRIES + 10 - i) * DAY) end
    local merged = Bank.Merge({}, long)
    T.eq(#merged, Bank.MAX_ENTRIES)
    T.eq(merged[#merged].n, Bank.MAX_ENTRIES + 10)
  end)
end)

local function Reading(at, money, logs, tabs)
  return { at = at, by = "Reader", money = money, logs = logs or {}, tabs = tabs or {} }
end

T.describe("Bank.Apply", function()
  T.it("keeps money, tabs, contents and logs of a reading", function()
    local bank = Bank.Get({})
    local slots = { [1] = { i = "item:13446", id = 13446, n = 5, nm = "Potion" }, [98] = { i = "item:7", id = 7, n = 1 } }
    local changed = Bank.Apply(bank, Reading(NOW, 12340000, { money = { Gold("deposit", "A", 50000, 2) }, ["1"] = { Item("deposit", "A", 13446, 5, 1) } },
      { [1] = { name = "Potions", icon = 134, text = "for raids", slots = slots } }))
    T.eq(changed, true)
    T.eq(bank.money, 12340000)
    T.eq(bank.at, NOW)
    T.eq(bank.by, "Reader")
    T.eq(bank.tabs[1].name, "Potions")
    T.eq(bank.tabs[1].text, "for raids")
    T.eq(Bank.Used(bank.tabs[1]), 2)
    T.eq(Bank.Used({}), nil)
    T.eq(#bank.logs.money, 1)
    T.eq(#bank.logs["1"], 1)
    T.eq(bank.samples, { { ts = NOW, c = 12340000 } })
    -- the same reading again: nothing changed
    T.eq(Bank.Apply(bank, Reading(NOW, 12340000, { money = { Gold("deposit", "A", 50000, 2) } },
      { [1] = { name = "Potions", icon = 134, text = "for raids", slots = slots } })), false)
  end)

  T.it("takes the logs of an older reading but not its money or contents", function()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW, 900, { money = { Gold("deposit", "A", 100, 1) } }, { [1] = { name = "New", slots = {} } }))
    local before = NOW - DAY
    Bank.Apply(bank, Reading(before, 500, { money = { Gold("deposit", "B", 7, 5, before) } },
      { [1] = { name = "Old", slots = { [1] = { i = "item:1", id = 1, n = 1 } } } }))
    T.eq(bank.money, 900)
    T.eq(bank.at, NOW)
    T.eq(bank.tabs[1].name, "New")
    T.eq(Bank.Used(bank.tabs[1]), 0)
    T.eq(Kinds(bank.logs.money), "B:7 A:100")
  end)

  T.it("keeps a tab's contents when a reading has none for it", function()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW, 1, nil, { [2] = { name = "Herbs", slots = { [3] = { i = "item:9", id = 9, n = 20 } } } }))
    Bank.Apply(bank, Reading(NOW + 60, 1, nil, { [2] = { name = "Herbs & Ore" } }))
    T.eq(bank.tabs[2].name, "Herbs & Ore")
    T.eq(Bank.Used(bank.tabs[2]), 1)
  end)
end)

T.describe("Bank views", function()
  local function Sample()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW, 1000000, {
      money = { Gold("deposit", "Ann Bee", 300000, 50), Gold("repair", "Cid Dee", 20000, 30), Gold("withdraw", "Ann Bee", 100000, 3) },
      ["1"] = { Item("deposit", "Ann Bee", 5, 20, 40), Item("withdraw", "Cid Dee", 5, 4, 2) },
      ["2"] = { Item("move", "Cid Dee", 6, 1, 1) },
    }))
    return bank
  end

  T.it("lists every movement newest first with the gold after each money entry", function()
    local rows = Bank.Ledger(Sample())
    T.eq(#rows, 6)
    T.eq(rows[1].e.k, "move")
    T.eq(rows[#rows].e.c, 300000)
    local after = {}
    for _, row in ipairs(rows) do
      if row.log == "money" then after[#after + 1] = row.after end
    end
    T.eq(after, { 1000000, 1100000, 1120000 })
  end)

  T.it("filters by gold, items, tab and member", function()
    local bank = Sample()
    T.eq(#Bank.Ledger(bank, { kind = "gold" }), 3)
    T.eq(#Bank.Ledger(bank, { kind = "items" }), 3)
    T.eq(#Bank.Ledger(bank, { tab = 1 }), 2)
    T.eq(#Bank.Ledger(bank, { tab = 2, kind = "gold" }), 0)
    T.eq(#Bank.Ledger(bank, { who = "ann bee" }), 3)
  end)

  T.it("stops the gold after an entry at a gap", function()
    local bank = Sample()
    table.insert(bank.logs.money, 2, { k = "gap", ts = NOW - 31 * HOUR })
    local known = 0
    for _, row in ipairs(Bank.Ledger(bank, { kind = "gold" })) do
      if row.after then known = known + 1 end
    end
    T.eq(known, 2)
    T.eq(#Bank.Ledger(bank, { who = "ann bee" }), 3) -- no gap row in one member's list
  end)

  T.it("sums the week", function()
    T.eq(Bank.Sums(Sample(), NOW, 7), { paid = 300000, taken = 100000, repairs = 20000, itemsIn = 20, itemsOut = 4 })
    T.eq(Bank.Sums(Sample(), NOW, 1), { paid = 0, taken = 100000, repairs = 0, itemsIn = 0, itemsOut = 4 })
  end)

  T.it("draws the gold as steps with the days' sums", function()
    local chart = Bank.Chart(Sample(), NOW, 30)
    T.eq(#chart.steps, 3)
    T.eq(chart.steps[1].c, 1120000)
    T.eq(chart.steps[3].c, 1000000)
    T.eq(chart.start, 820000)
    T.eq(chart.low, 820000)
    T.eq(chart.high, 1120000)
    T.eq(chart.days[0], { plus = 0, minus = 100000 })
    T.eq(chart.days[2], { plus = 300000, minus = 0 })
    -- a window that starts inside the log: it starts with the gold of that moment
    local short = Bank.Chart(Sample(), NOW, 1)
    T.eq(#short.steps, 1)
    T.eq(short.start, 1100000)
    T.eq(Bank.Chart(Bank.Get({}), NOW, 30), nil)
  end)

  T.it("marks tab purchases and what moved a large share of the gold", function()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW, 3000000, { money = {
      Gold("deposit", "A", 400000, 90), Gold("buyTab", "B", 100000, 80), Gold("repair", "C", 900000, 70),
      Gold("deposit", "D", 5000, 60), Gold("withdraw", "E", 800000, 50), Gold("deposit", "F", 600000, 40),
      Gold("deposit", "G", 795000, 30),
    } }))
    local steps = Bank.Chart(bank, NOW, 30).steps
    T.eq(steps[1].k, "deposit")
    T.eq(steps[1].w, "A")
    T.eq(steps[1].c - steps[1].b, 400000)
    local function Names(marks)
      local out = {}
      for i, step in ipairs(marks) do out[i] = step.w end
      return table.concat(out)
    end
    T.eq(Names(Bank.Marks(steps, 0.25, 10)), "BEFG") -- not the repair, not the smaller deposits
    T.eq(Names(Bank.Marks(steps, 0.25, 3)), "BEG")    -- the tab and the two largest, oldest first
    T.eq(Names(Bank.Marks(steps, 2, 10)), "B")        -- a tab always, whatever the share
    T.eq(Names(Bank.Marks({ { ts = 1, c = 5 } }, 0.1, 10)), "") -- a step from a reading says nothing
  end)

  T.it("draws from earlier readings where the log has a gap", function()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW - 10 * DAY, 500, {}))
    Bank.Apply(bank, Reading(NOW, 900, { money = { { k = "gap", ts = NOW - 2 * HOUR }, Gold("deposit", "A", 100, 2) } }))
    local chart = Bank.Chart(bank, NOW, 30)
    T.eq(#chart.steps, 2)
    T.eq(chart.steps[1], { ts = NOW - 10 * DAY, c = 500 })
    T.eq(chart.start, nil)
  end)
end)

T.describe("Bank per member", function()
  local function Sample()
    local bank = Bank.Get({})
    Bank.Apply(bank, Reading(NOW, 1000000, {
      money = { Gold("deposit", "Ann Bee", 300000, 300), Gold("buyTab", "Ann Bee", 50000, 200), Gold("repair", "Cid Dee", 20000, 30),
        Gold("withdraw", "Ann Bee", 100000, 3), Gold("depositSummary", nil, 7, 2) },
      ["1"] = { Item("deposit", "Ann Bee", 5, 20, 40), Item("withdraw", "Cid Dee", 5, 4, 2), Item("withdraw", "Eve Eff", 5, 20, 1),
        Item("move", "Cid Dee", 6, 1, 1) },
    }, { [1] = { name = "A", slots = { [1] = { i = "item:1", id = 1, n = 1 }, [2] = { i = "item:1", id = 1, n = 1 } } }, [2] = { name = "B" } }))
    return bank
  end
  local function ByKey(list)
    local out = {}
    for _, m in ipairs(list) do out[m.key] = m end
    return out
  end

  T.it("adds up what every member put in and took out", function()
    local all = ByKey(Bank.Balance(Sample(), NOW))
    T.eq(all["ann bee"], { key = "ann bee", name = "Ann Bee", paid = 300000, taken = 150000, repairs = 0, net = 150000,
      itemsIn = 20, itemsOut = 0, last = NOW - 3 * HOUR, count = 4 })
    T.eq(all["cid dee"].taken, 20000)
    T.eq(all["cid dee"].repairs, 20000)
    T.eq(all["cid dee"].net, -20000)
    T.eq(all["cid dee"].itemsOut, 4)
    T.eq(all["cid dee"].count, 3) -- the move counts as a movement, not as items in or out
    T.eq(all["eve eff"].itemsOut, 20)
    local n = 0
    for _ in pairs(all) do n = n + 1 end
    T.eq(n, 3) -- the guild's own income has no member
    -- the last week only
    local week = ByKey(Bank.Balance(Sample(), NOW, 7))
    T.eq(week["ann bee"].paid, 0)
    T.eq(week["ann bee"].taken, 100000)
    T.eq(week["ann bee"].itemsIn, 20)
  end)

  T.it("lists the largest withdrawals, gold and items", function()
    local rows = Bank.Largest(Sample(), NOW, nil, 4)
    T.eq(#rows, 4)
    T.eq(rows[1].e.c, 100000)
    T.eq(rows[2].e.c, 50000)
    T.eq(rows[3].e.n, 20)
    T.eq(rows[4].e.n, 4)
    T.eq(#Bank.Largest(Sample(), NOW, nil, 20), 5)
    local week = Bank.Largest(Sample(), NOW, 7, 2)
    T.eq(week[1].e.c, 100000)
    T.eq(week[2].e.n, 20)
    T.eq(#Bank.Largest(Bank.Get({}), NOW, 7, 9), 0)
  end)

  T.it("counts the slots of the tabs that were read", function()
    local used, room, tabs = Bank.Slots(Sample())
    T.eq({ used, room, tabs }, { 2, 98, 2 })
  end)
end)

T.describe("Bank sharing", function()
  local function Sample()
    local bank = Bank.Get({})
    local log = {}
    for i = 1, 40 do log[i] = Item("deposit", "Ann Bee", 5, i, 400 - i * 10) end
    bank.cost = 2500000
    Bank.Apply(bank, Reading(NOW, 77, { ["1"] = log, money = { Gold("deposit", "Ann Bee", 5, 1) } },
      { [1] = { name = "Potions", icon = "Interface\\Icons\\X", slots = { [4] = { i = "item:5", id = 5, n = 20, nm = "Thing" } } } }))
    return bank
  end

  T.it("says what it knows and whether that is news", function()
    local digest = Bank.Digest(Sample())
    T.eq(digest, { at = NOW, ts = NOW, n = 41 })
    T.eq(Bank.Digest(Bank.Get({})), nil)
    T.eq(Bank.Newer(digest, nil), true)
    T.eq(Bank.Newer(digest, { at = NOW, ts = NOW }), false)
    T.eq(Bank.Newer(digest, { at = NOW - 5, ts = NOW }), true)
    T.eq(Bank.Newer(digest, { at = NOW, ts = NOW - HOUR }), true)
    T.eq(Bank.Newer(nil, digest), false)
  end)

  T.it("round-trips through the wire into an empty bank", function()
    local wire = ns.json.decode(ns.json.encode(Bank.Excerpt(Sample(), 0)))
    local reading = Bank.Validate(wire, "Sender", NOW)
    local bank = Bank.Get({})
    T.eq(Bank.Apply(bank, reading), true)
    T.eq(bank.money, 77)
    T.eq(bank.cost, 2500000)
    T.eq(bank.by, "Reader")
    T.eq(#bank.logs["1"], 40)
    T.eq(bank.logs["1"][40].id, 5)
    T.eq(bank.logs["1"][40].by, "Reader")
    T.eq(bank.tabs[1].name, "Potions")
    T.eq(bank.tabs[1].slots[4], { i = "item:5", id = 5, n = 20, nm = "Thing" })
  end)

  T.it("sends only what is newer, with a gap where it cut", function()
    local wire = Bank.Excerpt(Sample(), NOW - 60 * HOUR)
    T.eq(wire.logs["1"][1].k, "gap")
    T.eq(#wire.logs["1"], 8) -- the gap and the seven entries of the last 66 hours
    -- who knows the older entries joins them without a gap, who does not keeps none at the start
    local full = Sample()
    Bank.Apply(full, Bank.Validate(ns.json.decode(ns.json.encode(wire)), "S", NOW))
    T.eq(#full.logs["1"], 40)
    local limited = Bank.Excerpt(Sample(), 0, 10, false)
    T.eq(limited.tabs["1"].slots, nil)
    local total = 0
    for _, run in pairs(limited.logs) do total = total + #run end
    T.truthy(total <= 12, "cut to the newest entries: " .. total)
  end)

  T.it("refuses what is no reading and drops what makes no sense", function()
    T.eq(Bank.Validate(nil, "S", NOW), nil)
    T.eq(Bank.Validate({ at = "now" }, "S", NOW), nil)
    T.eq(Bank.Validate({ at = NOW + 10 * DAY }, "S", NOW), nil)
    local reading = Bank.Validate({ at = NOW, money = -5, tabs = { ["99"] = { name = "x" }, ["2"] = { name = ("n"):rep(200), slots = { 500, "item:1", 1, "" } } },
      logs = { evil = { { k = "deposit", ts = NOW } }, ["1"] = { { k = "deposit", ts = NOW + 9 * DAY }, { k = "de posit", ts = NOW },
        { k = "deposit", w = "A", i = "notanitem", n = 2, ts = NOW - 5 }, "junk" } } }, "Sender", NOW)
    T.eq(reading.money, nil)
    T.eq(reading.by, "Sender")
    T.eq(reading.tabs[99], nil)
    T.eq(reading.tabs[2].name, nil)
    T.eq(reading.tabs[2].slots, {})
    T.eq(reading.logs.evil, nil)
    T.eq(#reading.logs["1"], 1)
    T.eq(reading.logs["1"][1].i, nil)
    T.eq(reading.logs["1"][1].by, "Sender")
  end)
end)
