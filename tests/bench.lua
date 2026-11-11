-- Benchmark: luajit tests/bench.lua [--members N] [--online N] [--chat N] [--runs N] [--save] [--no-compare]
-- (from the repo root). Loads Guildy against the test stubs (tests/wow.lua) with a big made-up guild
-- and measures every step a player takes: login, roster scan, opening the window, each tab, a chat
-- line, a roster update.
--
-- Per step:
--   ms       time of Guildy's Lua code, median of the runs. LuaJIT with the JIT off; WoW's Lua is
--            slower, so the numbers compare versions with each other, not with the game.
--   calls    widget method calls (SetText, SetPoint, Show ...): every one is work for the client that
--            the stubs don't do. Deterministic: the same code gives the same number.
--   widgets  frames, textures and font strings created in the step
--   kB       memory allocated in the step (garbage the client has to collect later)
--
-- --save writes the result to tests/bench-baseline.lua; later runs show the change against it.
local here = (debug.getinfo(1, "S").source:sub(2):gsub("\\", "/"):match("^(.*)/[^/]*$")) or "."
local T = dofile(here .. "/lib.lua")
local NewWorld = dofile(here .. "/wow.lua")
local BASELINE = here .. "/bench-baseline.lua"

if jit then jit.off() end

local opts = { members = 500, online = 60, chat = 1500, runs = 7 }
do
  local i = 1
  while arg[i] do
    local key = arg[i]:match("^%-%-(.+)$")
    if key == "save" then opts.save = true
    elseif key == "no-compare" then opts.noCompare = true
    elseif key and opts[key] and tonumber(arg[i + 1]) then
      opts[key] = tonumber(arg[i + 1])
      i = i + 1
    else
      error("unknown argument " .. tostring(arg[i]))
    end
    i = i + 1
  end
end

-- Clock in milliseconds: os.clock ticks in whole milliseconds on Windows, too coarse for one refresh
local Clock = function() return os.clock() * 1000 end
do
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi.os == "Windows" then
    ffi.cdef("int QueryPerformanceCounter(int64_t *count); int QueryPerformanceFrequency(int64_t *freq);")
    local value = ffi.new("int64_t[1]")
    ffi.C.QueryPerformanceFrequency(value)
    local frequency = tonumber(value[0])
    Clock = function()
      ffi.C.QueryPerformanceCounter(value)
      return tonumber(value[0]) * 1000 / frequency
    end
  end
end

-- The made-up guild -------------------------------------------------------------------------------

-- Same numbers on every run and every machine
local seed = 12345
local function Random(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n + 1
end

local CLASSES = {
  { "WARRIOR", "Krieger" }, { "PALADIN", "Paladin" }, { "HUNTER", "Jäger" }, { "ROGUE", "Schurke" },
  { "PRIEST", "Priester" }, { "SHAMAN", "Schamane" }, { "MAGE", "Magier" }, { "WARLOCK", "Hexenmeister" },
  { "DRUID", "Druide" },
}
local ZONES = { "Sturmwind", "Eisenschmiede", "Dämmerwald", "Westfall", "Rotkammgebirge", "Brachland", "Orgrimmar",
  "Schlingendorntal", "Tanaris", "Die Todesminen", "Der Geschmolzene Kern", "Winterquell" }
local RANKS = { "Gildenmeister", "Offizier", "Veteran", "Mitglied", "Anwärter" }
local NOTES = { "", "", "", "Tank", "Heiler", "Alch/Kräuter", "Twink von Ran", "Schmied Bergbau", "Main", "inaktiv bis Mai",
  "Schneider / Verzauberer", "Kürsch Leder" }
local FIRST = { "Ran", "Mak", "Au", "Syd", "Mae", "Tor", "Lin", "Bro", "Kel", "Ysa", "Dun", "Fen", "Gar", "Hil", "Ivo", "Jor" }
local MIDDLE = { "", "a", "i", "o", "ri", "la", "ne", "ko", "th", "ve" }
local LAST = { "Fred", "Farron", "Tsch", "Withersong", "Lightspark", "Eisenfaust", "Sturm", "Grauwolf", "Morgentau", "Dorn" }
local WORDS = { "hallo", "zusammen", "wer", "kommt", "mit", "nach", "Todesminen", "brauche", "einen", "Heiler", "danke",
  "gz", "lfm", "Kloster", "heute", "Abend", "Raid", "um", "acht", "hat", "jemand", "Zeit", "für", "eine", "Runde" }

local roster, lastOnline, guild = {}, {}, {}
do
  local used = {}
  for i = 1, opts.members do
    local name
    repeat
      name = FIRST[Random(#FIRST)] .. MIDDLE[Random(#MIDDLE)] .. MIDDLE[Random(#MIDDLE)] .. "-" .. LAST[Random(#LAST)]
        .. MIDDLE[Random(#MIDDLE)]
    until not used[name]
    used[name] = true
    local class = CLASSES[Random(#CLASSES)]
    local online = i <= opts.online
    local rankIndex = i == 1 and 0 or math.min(#RANKS - 1, 1 + Random(#RANKS - 1) - 1)
    roster[i] = { name, RANKS[rankIndex + 1], rankIndex, Random(60), class[2], ZONES[Random(#ZONES)], NOTES[Random(#NOTES)],
      Random(4) == 1 and "DKP 120" or "", online, 0, class[1], nil, nil, false, nil, nil, ("Player-1-%08X"):format(i) }
    -- offline members: a third within the month, the rest up to two years
    if not online then
      local days = Random(3) == 1 and Random(30) or Random(700)
      lastOnline[i] = { math.floor(days / 365), math.floor(days % 365 / 30), days % 30, Random(24) - 1 }
    end
    guild[i] = { name = name, classID = Random(#CLASSES) }
  end
end

local messages = {}
for i = 1, opts.chat do
  local words = {}
  for w = 1, 3 + Random(12) do words[w] = WORDS[Random(#WORDS)] end
  local author = guild[Random(math.min(#guild, 120))]
  messages[i] = {
    messageId = { epoch = (1700000000 - (opts.chat - i) * 90) * 1000000, position = i },
    content = table.concat(words, " "),
    author = { name = author.name, classID = author.classID, memberId = i },
  }
end

local function Setup(env)
  env.GetGuildRosterLastOnline = function(i)
    local t = lastOnline[i]
    if t then return t[1], t[2], t[3], t[4] end
  end
  env.GetNumGuildEvents = function() return 0 end
  env.Enum = { ClubStreamType = { Guild = 1, Officer = 2 } }
  env.C_CreatureInfo = { GetClassInfo = function(id) return CLASSES[id] and { classFile = CLASSES[id][1] } end }
  -- the guild's club with its chat history; everything else about clubs answers nothing
  env.C_Club = setmetatable({
    GetGuildClubId = function() return 1 end,
    GetStreams = function() return { { streamType = 1, streamId = 10 }, { streamType = 2, streamId = 11 } } end,
    GetMessageRanges = function(_, streamId)
      if streamId ~= 10 or #messages == 0 then return {} end
      return { { oldestMessageId = messages[1].messageId, newestMessageId = messages[#messages].messageId } }
    end,
    GetMessagesInRange = function(_, _, oldest, newest)
      if oldest.position == 1 and newest.position == #messages then return messages end
      local part = {}
      for i = oldest.position, newest.position do part[#part + 1] = messages[i] end
      return part
    end,
    GetMessagesBefore = function(_, _, newest, count)
      local part = {}
      for i = math.max(1, newest.position - count + 1), newest.position do part[#part + 1] = messages[i] end
      return part
    end,
    IsBeginningOfStream = function() return true end,
  }, { __index = function() return function() return nil end end })
end

-- Professions with recipe books for four of ten members, statistics for three of ten
local function FillData(ns)
  local data = ns.GuildData()
  local primary, secondary, statIds = {}, {}, {}
  for _, skillLine in ipairs(ns.Professions.ORDER) do
    local list = ns.Professions.PRIMARY[skillLine] and primary or secondary
    list[#list + 1] = skillLine
  end
  for _, category in ipairs(ns.Stats.CATALOG) do
    for _, id in ipairs(category.stats) do statIds[#statIds + 1] = id end
  end
  for i, row in ipairs(roster) do
    local record = ns.Store.Member(data, row[1])
    if i % 10 < 4 then
      local first = primary[i % #primary + 1]
      local second = primary[(i + 3) % #primary + 1]
      for _, skillLine in ipairs({ first, second, secondary[i % #secondary + 1] }) do
        local recipes = {}
        for r = 1, 40 + (i * 7 + skillLine) % 120 do recipes[r] = skillLine * 100 + r end
        record.profs[skillLine] = { rank = 75 + (i * 13) % 225, max = 300, recipes = recipes, ts = 1699000000 + i,
          src = i % 3 == 0 and "self" or "relay" }
      end
    end
    if i % 10 < 3 then
      local values = {}
      for _, id in ipairs(statIds) do values[id] = (i * 31 + id * 7) % 5000 end
      record.stats = { ts = 1699000000 + i, src = "relay", v = values,
        months = { ["2023-10"] = { ts = 1698000000, v = values } } }
    end
  end
end

-- One run: a fresh client, every step once ----------------------------------------------------------

local function Run()
  local world = NewWorld(T, { roster = roster, width = 1000, height = 600, setup = Setup })
  local env, ns, calls = world.env, world.ns, world.calls
  local steps = {}

  local function Step(name, fn)
    collectgarbage("collect")
    collectgarbage("stop")
    local n, objects, kb = calls.n, calls.objects, collectgarbage("count")
    local start = Clock()
    fn()
    local ms = Clock() - start
    steps[#steps + 1] = { name = name, ms = ms, calls = calls.n - n, widgets = calls.objects - objects,
      kb = collectgarbage("count") - kb }
    collectgarbage("restart")
    if #world.errors > 0 then error(name .. ": " .. world.errors[1], 0) end
  end

  Step("login", function()
    world.Fire("ADDON_LOADED", "Guildy")
    world.Fire("PLAYER_LOGIN")
    world.Fire("GUILD_ROSTER_UPDATE")
    world.RunTimers()
  end)
  FillData(ns)
  Step("roster scan", function() ns.Roster.Scan() end)
  Step("open window (chat)", function() env.CommunitiesFrame:Show() end)
  -- a line in the guild chat: the game says so twice, as a chat message and as a message of the
  -- guild's club, which is where the history comes from
  local last = messages[#messages]
  messages[#messages + 1] = { messageId = { epoch = last.messageId.epoch + 90000000, position = #messages + 1 },
    content = "wer kommt mit nach Todesminen?", author = last.author }
  Step("chat: new guild line", function()
    world.Fire("CHAT_MSG_GUILD", "wer kommt mit nach Todesminen?", roster[2][1], "", "", "", "", 0, 0, "", 0, 1, roster[2][17])
    world.Fire("CLUB_MESSAGE_ADDED", 1, 10)
  end)
  messages[#messages] = nil
  Step("chat: roster update", function() ns.Fire("ROSTER") end)
  for _, key in ipairs({ "members", "overview", "fame", "professions", "info", "ranks", "communities" }) do
    Step(key .. ": first show", function() ns.UI.SelectTab(key) end)
    if ns.UI.Current() == key then
      Step(key .. ": roster update", function() ns.Fire("ROSTER") end)
    end
  end
  Step("chat: show again", function() ns.UI.SelectTab("chat") end)
  Step("members: show again", function() ns.UI.SelectTab("members") end)
  Step("members: filter by class", function() ns.UI.FilterMembers({ classFile = "MAGE" }) end)
  local member = ns.Roster.Members()[3]
  Step("member tooltip", function() ns.UI.MemberTooltip(env.UIParent, member) end)
  Step("character page: first show", function() ns.UI.ShowMember(member) end)
  Step("character page: next member", function() ns.UI.ShowMember(ns.Roster.Members()[4]) end)
  Step("sync: send summary", function() ns.Sync.SendSummary() end)
  Step("roster update from the game", function()
    world.Fire("GUILD_ROSTER_UPDATE")
    world.RunTimers()
  end)
  return steps
end

local function Median(values)
  table.sort(values)
  return values[math.ceil(#values / 2)]
end

local runs = {}
for r = 1, opts.runs do runs[r] = Run() end
local result = {}
for i, step in ipairs(runs[1]) do
  local ms, kb = {}, {}
  for r = 1, opts.runs do
    ms[r] = runs[r][i].ms
    kb[r] = runs[r][i].kb
  end
  result[i] = { name = step.name, ms = Median(ms), calls = step.calls, widgets = step.widgets, kb = Median(kb) }
end

-- Report --------------------------------------------------------------------------------------------

local config = ("%d members, %d online, %d chat lines"):format(opts.members, opts.online, opts.chat)
local baseline
if not opts.noCompare then
  local chunk = loadfile(BASELINE)
  local saved = chunk and chunk()
  if saved and saved.config == config then
    baseline = {}
    for _, step in ipairs(saved.steps) do baseline[step.name] = step end
  elseif saved then
    print("baseline is for " .. saved.config .. ": not compared")
  end
end

local function Change(now, before)
  if not before or before == 0 then return "" end
  local percent = (now - before) / before * 100
  if math.abs(percent) < 0.5 then return "    =" end
  return ("%+5.0f%%"):format(percent)
end

print(("Guildy benchmark: %s, median of %d runs"):format(config, opts.runs))
print(("%-34s %9s %6s %9s %6s %8s %9s"):format("step", "ms", "", "calls", "", "widgets", "kB"))
local total = { ms = 0, calls = 0, widgets = 0, kb = 0 }
local function Line(step, before)
  print(("%-34s %9.2f %6s %9d %6s %8d %9.0f"):format(step.name, step.ms, Change(step.ms, before and before.ms),
    step.calls, Change(step.calls, before and before.calls), step.widgets, step.kb))
end
local beforeTotal = baseline and { ms = 0, calls = 0 }
for _, step in ipairs(result) do
  local before = baseline and baseline[step.name]
  Line(step, before)
  for key in pairs(total) do total[key] = total[key] + step[key] end
  if beforeTotal and before then
    beforeTotal.ms = beforeTotal.ms + before.ms
    beforeTotal.calls = beforeTotal.calls + before.calls
  end
end
total.name = "total"
Line(total, beforeTotal)
if baseline then print("change columns: against tests/bench-baseline.lua (time varies a few percent from run to run)") end

if opts.save then
  local out = { "-- Written by luajit tests/bench.lua --save", "return {", ("  config = %q,"):format(config), "  steps = {" }
  for _, step in ipairs(result) do
    out[#out + 1] = ("    { name = %q, ms = %.3f, calls = %d, widgets = %d, kb = %.0f },"):format(step.name, step.ms,
      step.calls, step.widgets, step.kb)
  end
  out[#out + 1] = "  },"
  out[#out + 1] = "}"
  local file = assert(io.open(BASELINE, "w"))
  file:write(table.concat(out, "\n"), "\n")
  file:close()
  print("saved as baseline: tests/bench-baseline.lua")
end
