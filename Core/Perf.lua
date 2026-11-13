-- Measures how long Guildy's own code runs, so a hitch can be named and two versions compared
-- (/guildy perf, UI/Commands... see Core/Init.lua). Off by default: Perf.Call then only calls through.
-- Pure: the clock is injected (debugprofilestop in game, os.clock in tests).
--
-- A measurement is "kind name" ("event GUILD_ROSTER_UPDATE", "refresh members", "scan roster") with
-- how often it ran, the time in total, the longest single run, how many runs took longer than a
-- frame at 60 fps, and the memory its runs allocated (what the client has to collect again later;
-- a run during which the collector worked counts as nothing). Times and memory are inclusive: "event CHAT_MSG_GUILD" contains the "fire CHAT" it causes,
-- which contains the "refresh chat" of the open tab.
local _, ns = ...

local Perf = {}
ns.Perf = Perf

Perf.FRAME_MS = 16.7 -- one frame at 60 fps: a run above it is felt as a stutter
Perf.on = false

local marks = {}
local since = 0 -- clock value when measuring began (or was reset)

local function Clock()
  local stop = rawget(_G, "debugprofilestop")
  if stop then return stop() end
  return os.clock() * 1000
end
Perf.Clock = Clock

-- Lua memory in use, in kB
function Perf.Memory()
  return collectgarbage("count")
end

-- Adds one run of ms milliseconds that allocated kb kilobytes to "kind name"
function Perf.Add(kind, name, ms, kb)
  local label = name and (kind .. " " .. tostring(name)) or kind
  local mark = marks[label]
  if not mark then
    mark = { label = label, n = 0, total = 0, max = 0, slow = 0, kb = 0 }
    marks[label] = mark
  end
  mark.n = mark.n + 1
  mark.total = mark.total + ms
  if ms > mark.max then mark.max = ms end
  if ms > Perf.FRAME_MS then mark.slow = mark.slow + 1 end
  if kb and kb > 0 then mark.kb = mark.kb + kb end
end

-- Counts one occurrence of "kind name" (no time, no memory) while measuring is on: how often something
-- happened, such as Guildy asking the game for an item ("item requests (Guildy)")
function Perf.Count(kind, name)
  if Perf.on then Perf.Add(kind, name, 0, 0) end
end

-- Every item Guildy makes the client ask the server for (C_Item.RequestLoadItemDataByID, GetItemInfo or
-- TryOn of an item it does not have): GET_ITEM_INFO_RECEIVED comes for every addon's requests, this line
-- tells Guildy's own apart
Perf.ITEM_REQUESTS = "item requests (Guildy)"
function Perf.ItemRequest() Perf.Count(Perf.ITEM_REQUESTS) end

local function Done(kind, name, start, memory, ...)
  Perf.Add(kind, name, Perf.Clock() - start, Perf.Memory() - memory)
  return ...
end

-- fn(...) with its results; measured as "kind name" while measuring is on
function Perf.Call(kind, name, fn, ...)
  if not Perf.on then return fn(...) end
  return Done(kind, name, Perf.Clock(), Perf.Memory(), fn(...))
end

-- Replaces owner[field] by a measured version of itself ("kind name"); callers that look the function
-- up on the table at call time get the measured one
function Perf.Wrap(owner, field, kind, name)
  local fn = owner and owner[field]
  if type(fn) ~= "function" then return end
  owner[field] = function(...)
    if not Perf.on then return fn(...) end
    return Done(kind, name, Perf.Clock(), Perf.Memory(), fn(...))
  end
end

-- Parts of one function: local lap = Perf.Lap() at its start, then lap("kind", "name") after each
-- part adds the time since the start or the lap before. Does nothing while measuring is off.
local function NoLap() end
function Perf.Lap()
  if not Perf.on then return NoLap end
  local last, memory = Perf.Clock(), Perf.Memory()
  return function(kind, name)
    local now, memoryNow = Perf.Clock(), Perf.Memory()
    Perf.Add(kind, name, now - last, memoryNow - memory)
    last, memory = now, memoryNow
  end
end

function Perf.Enable(on)
  on = on and true or false
  if on and not Perf.on then since = Perf.Clock() end
  Perf.on = on
end

function Perf.Reset()
  marks = {}
  since = Perf.Clock()
end

-- Milliseconds measured so far
function Perf.Elapsed()
  return Perf.on and (Perf.Clock() - since) or 0
end

-- The measurements, the most expensive in total first: { label, n, total, max, slow, kb, avg }
function Perf.Rows()
  local rows = {}
  for _, mark in pairs(marks) do
    rows[#rows + 1] = { label = mark.label, n = mark.n, total = mark.total, max = mark.max, slow = mark.slow,
      kb = mark.kb, avg = mark.total / mark.n }
  end
  table.sort(rows, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.label < b.label
  end)
  return rows
end

-- The report as text lines: a head line (context: version, guild size, memory), then one line per
-- measurement, at most `limit` of them
function Perf.Lines(context, limit)
  local rows = Perf.Rows()
  local lines = { ("%s · %.0f s measured"):format(context or "Guildy", Perf.Elapsed() / 1000) }
  if #rows == 0 then
    lines[#lines + 1] = "nothing measured yet"
    return lines
  end
  lines[#lines + 1] = "total ms | runs | avg ms | max ms | over 16.7 ms | kB | what"
  for i = 1, math.min(#rows, limit or #rows) do
    local row = rows[i]
    lines[#lines + 1] = ("%.1f | %d | %.2f | %.1f | %d | %.0f | %s"):format(row.total, row.n, row.avg, row.max,
      row.slow, row.kb, row.label)
  end
  return lines
end
