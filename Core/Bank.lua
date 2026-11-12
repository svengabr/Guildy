-- The guild bank as Guildy knows it, pure. The game only tells about the bank while its window is open
-- at a guild banker, and of each log (one per bank tab, one for the money) only the newest entries, each
-- with an age in whole hours. So every reading is kept and joined to what is known (Game/Bank.lua reads,
-- Game/Sync.lua shares readings between Guildy users):
--   guild.bank = {
--     v = 1, at = time of the newest reading, by = who read it,
--     money = copper at that reading, samples = { { ts, c } } the money at every reading it changed,
--     cost = copper the next tab costs (nil: not read, 0: none to buy),
--     tabs = { [n] = { name, icon, text, at, slots = { [slot] = { i = item string, id, nm = name, n = count } } } },
--     logs = { money = { Entry }, ["1"] = { Entry }, ... }   oldest first
--     mine = { [nameKey] = { at, gold = copper left today (-1: no limit),
--                            tabs = { [n] = { view, deposit, limit, left } } } }   never shared
--   }
--   Entry = { k = kind as the game names it ("deposit", "withdraw", "move", "repair", "buyTab", ...) or "gap",
--             w = who, i = item string, id = item id, nm = item name, n = count, a = bank tab, b = tab moved to,
--             c = copper, ts = when (reading time minus the age), at = time of the reading, by = who read it }
-- Everything the game hands over is kept, also what no view shows yet (whole item strings, the contents of
-- every tab, tab texts and icons). A "gap" stands where entries may be missing: a reading came back full and
-- joined nothing known before it.
local _, ns = ...

local Bank = {}
ns.Bank = Bank

Bank.VERSION = 1
Bank.LOG_LIMIT = 25     -- a log this long may have lost older entries (the server keeps no more)
Bank.MAX_ENTRIES = 3000 -- kept per log
Bank.MAX_SAMPLES = 600
Bank.MAX_TABS = 12
Bank.SLOTS = 98
Bank.MONEY = "money"
Bank.WIRE_ENTRIES = 240 -- entries in one shared message at most

-- money kinds by what they do to the bank's gold
Bank.PLUS = { deposit = true, depositSummary = true, refundRename = true }
Bank.MINUS = { withdraw = true, repair = true, withdrawForTab = true, buyTab = true, buyRename = true }

local floor, max, min, abs = math.floor, math.max, math.min, math.abs

function Bank.Get(guild)
  if type(guild.bank) ~= "table" then guild.bank = {} end
  local bank = guild.bank
  bank.v = bank.v or Bank.VERSION
  if type(bank.tabs) ~= "table" then bank.tabs = {} end
  if type(bank.logs) ~= "table" then bank.logs = {} end
  if type(bank.samples) ~= "table" then bank.samples = {} end
  if type(bank.mine) ~= "table" then bank.mine = {} end
  return bank
end

-- "item:13446::::::::60" and 13446 from an item link (or item string); nil for anything else
function Bank.ItemOf(link)
  if type(link) ~= "string" then return nil end
  local item = link:match("(item:[%-%d:]+)")
  if not item then return nil end
  item = item:gsub(":+$", "")
  local id = tonumber(item:match("^item:(%d+)"))
  if not id then return nil end
  return item, id, link:match("%[(.-)%]")
end

-- How far two readings may disagree about when an entry happened: ages come in whole hours, older ones
-- in days and months of thirty days
local function Slack(e)
  return 2 * 3600 + 0.1 * max(0, (e.at or e.ts) - e.ts)
end

local function Same(x, y)
  if x.k ~= y.k or x.k == "gap" then return false end
  if x.w ~= y.w or x.id ~= y.id or x.n ~= y.n or x.c ~= y.c or x.a ~= y.a or x.b ~= y.b then return false end
  return abs(x.ts - y.ts) <= max(Slack(x), Slack(y))
end
Bank.Same = Same

-- First index from `from` on where list holds entry, nil once the list is past its time
local function FindAhead(list, from, entry)
  local limit = entry.ts + Slack(entry)
  for index = from, #list do
    local other = list[index]
    if other.k ~= "gap" then
      if Same(other, entry) then return index end
      if other.ts - Slack(other) > limit then return nil end
    end
  end
  return nil
end

-- Joins two runs of one log (each oldest first, each a stretch of what really happened, with "gap"
-- where something may be missing). Returns the joined run and how many entries of `theirs` were new.
function Bank.Merge(mine, theirs)
  local out, added = {}, 0
  local i, j = 1, 1
  local function Mine() out[#out + 1] = mine[i] i = i + 1 end
  local function Theirs()
    if theirs[j].k ~= "gap" then added = added + 1 end
    out[#out + 1] = theirs[j]
    j = j + 1
  end
  -- a gap of one side goes when the other side knows what stood right before the entry after it
  local function Gap(own, ownIndex, other, otherIndex, takeOther)
    local gap, after = own[ownIndex], own[ownIndex + 1]
    local found = after and after.k ~= "gap" and FindAhead(other, otherIndex, after)
    if found then
      while otherIndex < found do
        takeOther()
        otherIndex = otherIndex + 1
      end
      if not (found > 1 and other[found - 1].k ~= "gap") then out[#out + 1] = gap end
    else
      while other[otherIndex] and other[otherIndex].k ~= "gap" and other[otherIndex].ts < gap.ts do
        takeOther()
        otherIndex = otherIndex + 1
      end
      out[#out + 1] = gap
    end
  end
  while mine[i] or theirs[j] do
    local a, b = mine[i], theirs[j]
    if not a then
      Theirs()
    elseif not b then
      Mine()
    elseif a.k == "gap" then
      Gap(mine, i, theirs, j, Theirs)
      i = i + 1
    elseif b.k == "gap" then
      Gap(theirs, j, mine, i, Mine)
      j = j + 1
    elseif Same(a, b) then
      -- one entry, read twice: the first reading stays (its time was taken closer to the event)
      if not a.i and b.i then a.i, a.nm = b.i, b.nm end
      out[#out + 1] = a
      i, j = i + 1, j + 1
    else
      local inTheirs, inMine = FindAhead(theirs, j + 1, a), FindAhead(mine, i + 1, b)
      if inTheirs and (not inMine or inTheirs - j <= inMine - i) then
        while j < inTheirs do Theirs() end
      elseif inMine then
        while i < inMine do Mine() end
      elseif a.ts <= b.ts then
        Mine()
      else
        Theirs()
      end
    end
  end
  -- no gap at the start or the end, never two in a row; the oldest entries go when the log grows too long
  local clean = {}
  for _, entry in ipairs(out) do
    local last = clean[#clean]
    if entry.k ~= "gap" or (last and last.k ~= "gap") then clean[#clean + 1] = entry end
  end
  if clean[#clean] and clean[#clean].k == "gap" then clean[#clean] = nil end
  local over = #clean - Bank.MAX_ENTRIES
  if over > 0 then
    local kept = {}
    for index = over + 1, #clean do kept[#kept + 1] = clean[index] end
    if kept[1] and kept[1].k == "gap" then table.remove(kept, 1) end
    clean = kept
  end
  return clean, added
end

-- A log as the game returned it (oldest first) as a run to merge: with a gap in front when it came back
-- full, since older entries may have dropped out of it
function Bank.Run(entries, limit)
  local run = {}
  if #entries >= (limit or Bank.LOG_LIMIT) then run[1] = { k = "gap", ts = entries[1].ts } end
  for _, entry in ipairs(entries) do run[#run + 1] = entry end
  return run
end

local function SameSlots(x, y)
  for slot = 1, Bank.SLOTS do
    local p, q = x[slot], y[slot]
    if (p == nil) ~= (q == nil) then return false end
    if p and (p.i ~= q.i or p.n ~= q.n) then return false end
  end
  return true
end

-- Takes a reading in: { at, by, money, tabs = { [n] = { name, icon, text, slots } }, logs = { key = run } }.
-- Logs are joined whatever their age; money and tabs only count from a reading newer than the known one.
-- Returns true when anything changed.
function Bank.Apply(bank, reading)
  local changed = false
  for key, run in pairs(reading.logs or {}) do
    if #run > 0 then
      local merged, added = Bank.Merge(bank.logs[key] or {}, run)
      if added > 0 or #merged ~= #(bank.logs[key] or {}) then changed = true end
      bank.logs[key] = merged
    end
  end
  local at = reading.at or 0
  if type(reading.money) == "number" then
    local last = bank.samples[#bank.samples]
    if at >= (bank.at or 0) then
      if bank.money ~= reading.money then changed = true end
      bank.money = reading.money
      if not last or last.c ~= reading.money then
        bank.samples[#bank.samples + 1] = { ts = at, c = reading.money }
        while #bank.samples > Bank.MAX_SAMPLES do table.remove(bank.samples, 1) end
      end
    end
  end
  if type(reading.cost) == "number" and at >= (bank.at or 0) and bank.cost ~= reading.cost then
    bank.cost, changed = reading.cost, true
  end
  for index, tab in pairs(reading.tabs or {}) do
    local known = bank.tabs[index]
    if not known or at >= (known.at or 0) then
      known = known or {}
      if tab.name and (known.name ~= tab.name or known.icon ~= tab.icon) then
        known.name, known.icon, changed = tab.name, tab.icon, true
      end
      if tab.text ~= nil and known.text ~= tab.text then known.text, changed = tab.text, true end
      if tab.slots then
        if not known.slots or not SameSlots(known.slots, tab.slots) then changed = true end
        known.slots = tab.slots
        known.at = at
      end
      known.at = known.at or at
      bank.tabs[index] = known
    end
  end
  if at > (bank.at or 0) then
    bank.at, bank.by = at, (reading.by ~= "" and reading.by) or bank.by
    changed = true
  end
  return changed
end

-- Slots in use in a tab, nil while its contents were never read
function Bank.Used(tab)
  if type(tab) ~= "table" or type(tab.slots) ~= "table" then return nil end
  local used = 0
  for _ in pairs(tab.slots) do used = used + 1 end
  return used
end

local function Newest(bank)
  local newest, count = 0, 0
  for _, log in pairs(bank.logs) do
    for _, entry in ipairs(log) do
      if entry.k ~= "gap" then
        count = count + 1
        if entry.ts > newest then newest = entry.ts end
      end
    end
  end
  return newest, count
end

-- What a Guildy user says about their bank data in the summary after login (Game/Sync.lua)
function Bank.Digest(bank)
  if type(bank) ~= "table" or type(bank.logs) ~= "table" or not bank.at then return nil end
  local newest, count = Newest(bank)
  return { at = bank.at, ts = newest, n = count }
end

-- True when `mine` knows something `theirs` (a digest, nil: nothing) does not
function Bank.Newer(mine, theirs)
  if type(mine) ~= "table" then return false end
  if type(theirs) ~= "table" then return true end
  return (mine.at or 0) > (tonumber(theirs.at) or 0) or (mine.ts or 0) > (tonumber(theirs.ts) or 0)
end

-- The part of the bank to share: money, tabs (with contents unless slots == false) and of every log
-- the entries after `since`, the newest `limit` in all. A log cut off that way starts with a gap.
function Bank.Excerpt(bank, since, limit, slots)
  local wire = { at = bank.at, by = bank.by, money = bank.money, cost = bank.cost, tabs = {}, logs = {} }
  for index, tab in pairs(bank.tabs) do
    wire.tabs[tostring(index)] = { name = tab.name, icon = tab.icon, text = tab.text, at = tab.at,
      slots = slots ~= false and tab.slots and Bank.PackSlots(tab.slots) or nil }
  end
  since = (since or 0) - 6 * 3600
  local picked, total = {}, 0
  for key, log in pairs(bank.logs) do
    local first = #log + 1
    while first > 1 and (log[first - 1].k == "gap" or log[first - 1].ts > since) do first = first - 1 end
    picked[key] = first
    total = total + (#log - first + 1)
  end
  local keep = min(1, (limit or Bank.WIRE_ENTRIES) / max(1, total))
  for key, log in pairs(bank.logs) do
    local first = picked[key]
    local count = #log - first + 1
    if keep < 1 then first = #log - floor(count * keep) + 1 end
    while log[first] and log[first].k == "gap" do first = first + 1 end
    if first <= #log then
      local run = {}
      if first > 1 then run[1] = { k = "gap", ts = log[first].ts } end
      for index = first, #log do
        local e = log[index]
        run[#run + 1] = { k = e.k, w = e.w, i = e.i, nm = e.nm, n = e.n, a = e.a, b = e.b, c = e.c, ts = e.ts,
          at = e.at ~= bank.at and e.at or nil, by = e.by ~= bank.by and e.by or nil }
      end
      wire.logs[key] = run
    end
  end
  return wire
end

-- Tab contents for the wire: { slot, item string, count, name, ... } in one flat list
function Bank.PackSlots(slots)
  local flat = {}
  for slot = 1, Bank.SLOTS do
    local s = slots[slot]
    if s then
      flat[#flat + 1] = slot
      flat[#flat + 1] = s.i
      flat[#flat + 1] = s.n or 1
      flat[#flat + 1] = s.nm or ""
    end
  end
  return flat
end

local function Text(value, length)
  if type(value) ~= "string" or value == "" or #value > length then return nil end
  return value
end

local function Whole(value, low, high)
  if type(value) ~= "number" or value ~= value or value < low or value > high then return nil end
  return floor(value)
end

local function UnpackSlots(flat)
  if type(flat) ~= "table" then return nil end
  local slots = {}
  for index = 1, min(#flat, Bank.SLOTS * 4), 4 do
    local slot = Whole(flat[index], 1, Bank.SLOTS)
    local item, id = Bank.ItemOf(Text(flat[index + 1], 160))
    if slot and item then
      slots[slot] = { i = item, id = id, n = Whole(flat[index + 2], 1, 100000) or 1, nm = Text(flat[index + 3], 120) }
    end
  end
  return slots
end

-- A shared reading made safe to take in (Bank.Apply), nil when it is none. sender: who it came from.
function Bank.Validate(wire, sender, now)
  if type(wire) ~= "table" then return nil end
  local latest = now + 86400
  local at = Whole(wire.at, 1, latest)
  if not at then return nil end
  local by = Text(wire.by, 60) or sender
  local reading = { at = at, by = by, money = Whole(wire.money, 0, 1e13), cost = Whole(wire.cost, 0, 1e13),
    tabs = {}, logs = {} }
  if type(wire.tabs) == "table" then
    for key, tab in pairs(wire.tabs) do
      local index = Whole(tonumber(key), 1, Bank.MAX_TABS)
      if index and type(tab) == "table" then
        local icon = tab.icon
        if type(icon) ~= "number" then icon = Text(icon, 200) end
        reading.tabs[index] = { name = Text(tab.name, 60), icon = icon, text = Text(tab.text, 600),
          slots = UnpackSlots(tab.slots) }
      end
    end
  end
  if type(wire.logs) == "table" then
    for key, run in pairs(wire.logs) do
      local known = key == Bank.MONEY or Whole(tonumber(key), 1, Bank.MAX_TABS)
      if known and type(run) == "table" then
        local clean, last = {}, 0
        for index = 1, min(#run, 600) do
          local e = run[index]
          local ts = type(e) == "table" and Whole(e.ts, 1, latest)
          local kind = type(e) == "table" and Text(e.k, 24)
          -- oldest first, as every run is: an entry out of order would break the joining
          if ts and kind and kind:match("^%a+$") and ts >= last - 30 * 86400 then
            if kind == "gap" then
              clean[#clean + 1] = { k = "gap", ts = ts }
            else
              local item, id = Bank.ItemOf(Text(e.i, 160))
              clean[#clean + 1] = { k = kind, w = Text(e.w, 60), i = item, id = id, nm = item and Text(e.nm, 120) or nil,
                n = Whole(e.n, 1, 100000), a = Whole(e.a, 1, Bank.MAX_TABS), b = Whole(e.b, 1, Bank.MAX_TABS),
                c = Whole(e.c, 0, 1e13), ts = ts, at = Whole(e.at, 1, latest) or at, by = Text(e.by, 60) or by }
            end
            last = max(last, ts)
          end
        end
        if #clean > 0 then reading.logs[tostring(key)] = clean end
      end
    end
  end
  return reading
end

-- Views -----------------------------------------------------------------------------------------------

-- The bank's gold after every entry of the money log, newest first as far as it is known for sure:
-- from the money of the newest reading back to the first gap or unknown kind
local function After(bank)
  local after = {}
  local log = bank.logs[Bank.MONEY] or {}
  local money = bank.money
  for index = #log, 1, -1 do
    local e = log[index]
    if not money or e.k == "gap" or not e.c then break end
    after[e] = money
    if Bank.PLUS[e.k] then
      money = money - e.c
    elseif Bank.MINUS[e.k] then
      money = money + e.c
    else
      break
    end
  end
  return after
end

-- Every entry of every log, newest first. filter = { kind = "gold" | "items" | nil, tab = n | nil,
-- who = nameKey | nil, since = ts | nil (nothing older) }. Rows are { e = Entry, log = key,
-- after = copper or nil }.
function Bank.Ledger(bank, filter)
  filter = filter or {}
  local after = After(bank)
  local since = filter.since or 0
  local rows = {}
  for key, log in pairs(bank.logs) do
    local isMoney = key == Bank.MONEY
    local shown = (isMoney and filter.kind ~= "items" and not filter.tab)
      or (not isMoney and filter.kind ~= "gold" and (not filter.tab or tostring(filter.tab) == key))
    if shown then
      for index, e in ipairs(log) do
        if (e.ts or 0) < since then -- older than the days looked at
        elseif e.k == "gap" then
          if not filter.who then rows[#rows + 1] = { e = e, log = key, index = index } end
        elseif not filter.who or (e.w and ns.Names.Key(e.w) == filter.who) then
          rows[#rows + 1] = { e = e, log = key, index = index, after = after[e] }
        end
      end
    end
  end
  table.sort(rows, function(x, y)
    if x.e.ts ~= y.e.ts then return x.e.ts > y.e.ts end
    if x.log ~= y.log then return x.log < y.log end
    return x.index > y.index
  end)
  return rows
end

-- Sums over the last `days`: { paid, taken, repairs, itemsIn, itemsOut }
function Bank.Sums(bank, now, days)
  local since = now - days * 86400
  local sums = { paid = 0, taken = 0, repairs = 0, itemsIn = 0, itemsOut = 0 }
  for key, log in pairs(bank.logs) do
    for _, e in ipairs(log) do
      if e.k ~= "gap" and e.ts >= since then
        if key == Bank.MONEY then
          if e.k == "repair" then
            sums.repairs = sums.repairs + (e.c or 0)
          elseif Bank.PLUS[e.k] then
            sums.paid = sums.paid + (e.c or 0)
          elseif Bank.MINUS[e.k] then
            sums.taken = sums.taken + (e.c or 0)
          end
        elseif e.k == "deposit" then
          sums.itemsIn = sums.itemsIn + (e.n or 1)
        elseif e.k == "withdraw" then
          sums.itemsOut = sums.itemsOut + (e.n or 1)
        end
      end
    end
  end
  return sums
end

-- The bank's gold over the last `days` as steps: { steps = { { ts, c } } oldest first ("from ts on the
-- bank held c"), start = copper before the first step or nil, days = { [n] = { plus, minus } } with n = 0
-- today, low, high }. nil while no money is known.
function Bank.Chart(bank, now, days)
  if not bank.money then return nil end
  local since = now - days * 86400
  local after = After(bank)
  local log = bank.logs[Bank.MONEY] or {}
  local perDay = {}
  for _, e in ipairs(log) do
    if e.k ~= "gap" and e.ts >= since then
      local day = floor((now - e.ts) / 86400)
      perDay[day] = perDay[day] or { plus = 0, minus = 0 }
      if Bank.PLUS[e.k] then
        perDay[day].plus = perDay[day].plus + (e.c or 0)
      elseif Bank.MINUS[e.k] then
        perDay[day].minus = perDay[day].minus + (e.c or 0)
      end
    end
  end
  -- the sure part of the log, newest first
  local steps, start, oldest, reached = {}, nil, now, false
  for index = #log, 1, -1 do
    local e = log[index]
    if not after[e] then break end
    if e.ts >= since then
      local before = after[e] + (Bank.PLUS[e.k] and -e.c or e.c)
      -- a step of the log also says what happened: k = kind, w = who, b = the gold before it
      table.insert(steps, 1, { ts = e.ts, c = after[e], k = e.k, w = e.w, b = before })
      start, oldest = before, e.ts
    else
      if #steps == 0 then start = after[e] end
      reached = true
      break
    end
  end
  -- before it: the money at earlier readings
  if not reached then
    for index = #bank.samples, 1, -1 do
      local sample = bank.samples[index]
      if sample.ts < oldest then
        if sample.ts < since then
          start = sample.c
          break
        end
        table.insert(steps, 1, { ts = sample.ts, c = sample.c })
        start, oldest = nil, sample.ts
      end
    end
  end
  local low, high = bank.money, bank.money
  for _, step in ipairs(steps) do low, high = min(low, step.c), max(high, step.c) end
  if start then low, high = min(low, start), max(high, start) end
  return { steps = steps, start = start, days = perDay, low = low, high = high }
end

-- The steps of a chart worth a mark: every tab bought, and what moved at least `share` of the bank's
-- gold (of the larger of before and after) in one go; repairs never. The `limit` largest, oldest first.
function Bank.Marks(steps, share, limit)
  local picked = {}
  for _, step in ipairs(steps) do
    if step.k and step.b then
      local amount = abs(step.c - step.b)
      local tab = step.k == "buyTab"
      if tab or (step.k ~= "repair" and amount > 0 and amount >= share * max(step.c, step.b)) then
        picked[#picked + 1] = { step = step, amount = amount, tab = tab }
      end
    end
  end
  table.sort(picked, function(x, y)
    if x.tab ~= y.tab then return x.tab end
    if x.amount ~= y.amount then return x.amount > y.amount end
    return x.step.ts > y.step.ts
  end)
  local marks = {}
  for index = 1, min(#picked, limit) do marks[index] = picked[index].step end
  table.sort(marks, function(x, y) return x.ts < y.ts end)
  return marks
end

-- What every member put in and took out over the last `days` (nil: everything known):
-- { { key, name, paid, taken (repairs and tab purchases included), repairs, net = paid - taken,
--     itemsIn, itemsOut, last = time of the newest movement, count } }, in no order
function Bank.Balance(bank, now, days)
  local since = days and now - days * 86400 or 0
  local by, list = {}, {}
  for key, log in pairs(bank.logs) do
    for _, e in ipairs(log) do
      if e.k ~= "gap" and e.w and e.ts >= since then
        local id = ns.Names.Key(e.w)
        local m = by[id]
        if not m then
          m = { key = id, name = e.w, paid = 0, taken = 0, repairs = 0, itemsIn = 0, itemsOut = 0, last = 0, count = 0 }
          by[id] = m
          list[#list + 1] = m
        end
        m.count = m.count + 1
        m.last = max(m.last, e.ts)
        if key == Bank.MONEY then
          if Bank.PLUS[e.k] then
            m.paid = m.paid + (e.c or 0)
          elseif Bank.MINUS[e.k] then
            m.taken = m.taken + (e.c or 0)
            if e.k == "repair" then m.repairs = m.repairs + (e.c or 0) end
          end
        elseif e.k == "deposit" then
          m.itemsIn = m.itemsIn + (e.n or 1)
        elseif e.k == "withdraw" then
          m.itemsOut = m.itemsOut + (e.n or 1)
        end
      end
    end
  end
  for _, m in ipairs(list) do m.net = m.paid - m.taken end
  return list
end

-- The largest withdrawals of the last `days` (nil: all): gold by amount (repairs included), items by
-- count, half of the `limit` rows each where there are both. Rows { e = Entry, log = key }, gold first.
function Bank.Largest(bank, now, days, limit)
  local since = days and now - days * 86400 or 0
  local gold, items = {}, {}
  for key, log in pairs(bank.logs) do
    for _, e in ipairs(log) do
      if e.k ~= "gap" and e.ts >= since then
        if key == Bank.MONEY then
          if Bank.MINUS[e.k] and (e.c or 0) > 0 then gold[#gold + 1] = { e = e, log = key } end
        elseif e.k == "withdraw" then
          items[#items + 1] = { e = e, log = key }
        end
      end
    end
  end
  table.sort(gold, function(x, y)
    if x.e.c ~= y.e.c then return x.e.c > y.e.c end
    return x.e.ts > y.e.ts
  end)
  table.sort(items, function(x, y)
    local p, q = x.e.n or 1, y.e.n or 1
    if p ~= q then return p > q end
    return x.e.ts > y.e.ts
  end)
  local half = floor(limit / 2)
  local golds = min(#gold, max(limit - half, limit - #items))
  local rows = {}
  for index = 1, golds do rows[#rows + 1] = gold[index] end
  for index = 1, min(#items, limit - golds) do rows[#rows + 1] = items[index] end
  return rows
end

-- Slots in use over all tabs whose contents were read, the room of those tabs, and how many tabs there are
function Bank.Slots(bank)
  local used, read, tabs = 0, 0, 0
  for _, tab in pairs(bank.tabs) do
    tabs = tabs + 1
    local count = Bank.Used(tab)
    if count then used, read = used + count, read + 1 end
  end
  return used, read * Bank.SLOTS, tabs
end
