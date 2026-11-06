local T = ...
local ns = T.pureNs()
local Stats = ns.Stats

-- fixed calendar: ts in days since 2026-01-01, any day >= 304 is November, >= 273 October
local function date(fmt, ts)
  assert(fmt == "%Y-%m")
  local day = math.floor(ts / 86400)
  if day >= 304 then return "2026-11" end
  if day >= 273 then return "2026-10" end
  return "2026-09"
end
local OCT, NOV = 280 * 86400, 310 * 86400

T.describe("Stats.Parse", function()
  T.it("reads plain numbers and counts with text", function()
    T.eq(Stats.Parse("1298"), 1298)
    T.eq(Stats.Parse("672 (Humanoid)"), 672)
    T.eq(Stats.Parse("1.298"), 1298)
    T.eq(Stats.Parse(42), 42)
  end)
  T.it("treats -- and nil as zero", function()
    T.eq(Stats.Parse("--"), 0)
    T.eq(Stats.Parse(nil), 0)
  end)
  T.it("reads money in copper", function()
    local gold = "6|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 88|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t "
      .. "93|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"
    T.eq(Stats.Parse(gold), 68893)
    T.eq(Stats.Parse("30|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t"), 30)
  end)
end)

T.describe("Stats months", function()
  T.it("steps back a month", function()
    T.eq(Stats.PreviousMonth("2026-11"), "2026-10")
    T.eq(Stats.PreviousMonth("2026-01"), "2025-12")
  end)
  T.it("keeps the first values of each month and computes growth", function()
    local member = {}
    Stats.Update(member, { [107] = 100 }, OCT, "self", date)
    Stats.Update(member, { [107] = 150 }, OCT + 86400, "self", date)
    Stats.Update(member, { [107] = 300 }, NOV, "self", date)
    Stats.Update(member, { [107] = 340 }, NOV + 86400, "self", date)
    T.eq(member.stats.months["2026-10"].v[107], 100)
    T.eq(member.stats.months["2026-11"].v[107], 300)
    T.eq(Stats.Value(member.stats, 107, "all", NOV + 86400, date), 340)
    T.eq(Stats.Value(member.stats, 107, "month", NOV + 86400, date), 40)
    T.eq(Stats.Value(member.stats, 107, "last", NOV + 86400, date), 200)
  end)
  T.it("has no last month without both snapshots", function()
    local member = {}
    Stats.Update(member, { [107] = 300 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, 107, "last", NOV, date), nil)
  end)
  T.it("sums end boss kills", function()
    local member = {}
    Stats.Update(member, { [63570] = 2, [15027] = 1 }, NOV, "self", date)
    T.eq(Stats.Value(member.stats, "bosses", "all", NOV, date), 3)
  end)
end)

T.describe("Stats merge", function()
  T.it("validates and merges newer values and earlier month snapshots", function()
    local member = {}
    Stats.Update(member, { [107] = 300 }, NOV + 86400, "seen", date)
    local wire = Stats.Wire({ ts = NOV + 2 * 86400, src = "self", v = { [107] = 320, [999999] = 5 },
      months = { ["2026-11"] = { ts = NOV, v = { [107] = 290 } }, ["2026-10"] = { ts = OCT, v = { [107] = 100 } } } })
    local rec = Stats.Validate(wire)
    T.truthy(rec)
    T.eq(rec.v[999999], 5) -- statistics outside the catalog are kept for later
    T.truthy(Stats.Merge(member, rec))
    T.eq(member.stats.v[107], 320)
    T.eq(member.stats.months["2026-11"].v[107], 290)
    T.eq(member.stats.months["2026-10"].v[107], 100)
  end)
  T.it("keeps newer own data", function()
    local member = {}
    Stats.Update(member, { [107] = 500 }, NOV + 5 * 86400, "self", date)
    local rec = Stats.Validate({ ts = NOV, src = "relay", v = { ["107"] = 1 } })
    Stats.Merge(member, rec)
    T.eq(member.stats.v[107], 500)
  end)
  T.it("rejects broken records", function()
    T.eq(Stats.Validate(nil), nil)
    T.eq(Stats.Validate({ ts = "x", v = {} }), nil)
    T.eq(Stats.Validate({ ts = 1, v = { ["107"] = -5 } }).v[107], nil)
  end)
end)

T.describe("Stats ranking", function()
  T.it("sorts by value and skips members without statistics", function()
    local a, b, c = {}, {}, {}
    Stats.Update(a, { [98] = 10 }, NOV, "self", date)
    Stats.Update(b, { [98] = 30 }, NOV, "self", date)
    local ranking = Stats.Ranking({ { key = "a", name = "A", rec = a.stats }, { key = "b", name = "B", rec = b.stats },
      { key = "c", name = "C", rec = c.stats } }, 98, "all", NOV, date)
    T.eq(#ranking, 2)
    T.eq(ranking[1].name, "B")
    T.eq(Stats.Total(ranking), 40)
  end)
end)
