local T = ...
local ns = {}
T.loadInto(ns, "Core/Perf.lua")
local Perf = ns.Perf

-- a clock the test moves by hand
local now = 0
Perf.Clock = function() return now end
-- and memory that grows by 2 kB per millisecond of work
local memory = 0
Perf.Memory = function() return memory end
local function Work(ms, ...)
  now = now + ms
  memory = memory + ms * 2
  return ...
end

T.describe("Perf", function()
  T.it("only calls through while it is off", function()
    Perf.Enable(false)
    Perf.Reset()
    T.eq({ Perf.Call("refresh", "chat", Work, 5, "a", nil, "c") }, { "a", nil, "c" })
    T.eq(Perf.Rows(), {})
  end)

  T.it("adds up the runs of a measurement and keeps the longest", function()
    Perf.Enable(true)
    Perf.Reset()
    T.eq(Perf.Call("refresh", "members", Work, 4, "result"), "result")
    Perf.Call("refresh", "members", Work, 30)
    Perf.Call("refresh", "chat", Work, 2)
    local rows = Perf.Rows()
    T.eq(rows[1], { label = "refresh members", n = 2, total = 34, max = 30, slow = 1, kb = 68, avg = 17 })
    T.eq(rows[2].label, "refresh chat") -- the most expensive in total first
    T.eq(Perf.Elapsed(), 36)
  end)

  T.it("measures a function replaced on its table", function()
    Perf.Reset()
    local owner = { Scan = function(ms) return Work(ms, "scanned") end }
    Perf.Wrap(owner, "Scan", "scan", "roster")
    T.eq(owner.Scan(20), "scanned")
    T.eq(Perf.Rows()[1].label, "scan roster")
    T.eq(Perf.Rows()[1].slow, 1)
    Perf.Wrap(owner, "Missing", "scan", "nothing") -- no function there: nothing happens
    T.eq(owner.Missing, nil)
  end)

  T.it("measures the parts of a function as laps", function()
    Perf.Reset()
    local lap = Perf.Lap()
    Work(3)
    lap("scan roster:", "read members")
    Work(5)
    lap("scan roster:", "notes")
    T.eq(Perf.Rows()[1], { label = "scan roster: notes", n = 1, total = 5, max = 5, slow = 0, kb = 10, avg = 5 })
    T.eq(Perf.Rows()[2].total, 3)
    Perf.Enable(false)
    Perf.Lap()("scan roster:", "notes") -- off: nothing added
    T.eq(Perf.Rows()[1].n, 1)
    Perf.Enable(true)
  end)

  T.it("counts no memory for a run during which the collector freed more than the run took", function()
    Perf.Reset()
    Perf.Call("refresh", "chat", function() memory = memory - 500 end)
    T.eq(Perf.Rows()[1].kb, 0)
  end)

  T.it("reports the context, a head line and one line per measurement", function()
    Perf.Reset()
    Perf.Call("open", "window", Work, 2000)
    Perf.Call("fire", "CHAT", Work, 1)
    local lines = Perf.Lines("Guildy 1.2.0 · 500 members", 1)
    T.eq(lines[1], "Guildy 1.2.0 · 500 members · 2 s measured")
    T.eq(lines[3], "2000.0 | 1 | 2000.00 | 2000.0 | 1 | 4000 | open window")
    T.eq(#lines, 3) -- limited to one measurement
    Perf.Reset()
    T.eq(Perf.Lines()[2], "nothing measured yet")
    Perf.Enable(false)
  end)
end)
