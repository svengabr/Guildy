-- Reads statistics from the game for the Hall of Fame (data model in Core/Stats.lua).
-- Own character: Forever's Statistics API (GetStatisticsCategoryList / GetCategoryNumAchievements /
-- GetStatistic(category, index)), after login and every 10 minutes.
-- Other guild members: Blizzard's achievement comparison (SetAchievementComparisonUnit + the event
-- INSPECT_ACHIEVEMENT_READY + GetComparisonStatistic(id)). Only for the TARGET: on Forever that works
-- (verified twice), while asking for "party2" got no answer and asking for party/mouseover units was
-- followed by a server disconnect (2026-11-06). Guildy asks quietly when a guild member becomes the
-- target: one request at a time, at most every 10 seconds, each member at most once an hour, never in
-- combat and never while Blizzard's own achievement or inspect window may be using it.
local _, ns = ...
local S = ns.Stats

local GameStats = {}
ns.GameStats = GameStats

local OWN_INTERVAL = 600
local REQUEST_GAP = 10
local MEMBER_GAP = 3600
local TIMEOUT = 5
local RETRY = 120       -- no answer (out of range): try that member again after 2 minutes

local pending          -- { key, name, guid, at }
local lastRequest = 0
local tried = {}       -- nameKey -> GetTime() of the last request this session
local lastOwnSend = 0
GameStats.debug = false

local function Log(text)
  if GameStats.debug then ns.Print("stats: " .. text) end
end

local function GameDate(fmt, ts)
  local date = rawget(_G, "date") or os.date
  return date(fmt, ts)
end

local function Fire() ns.Fire("STATS") end

-- Own statistics: { [statID] = number } for EVERY statistic the game reports (zeros left out), and
-- the list of all statistic IDs is remembered (GuildyDB.statIds) to ask for the same ones by comparison
function GameStats.ReadOwn()
  local list = ns.Try(rawget(_G, "GetStatisticsCategoryList"))
  local count = rawget(_G, "GetCategoryNumAchievements")
  local get = rawget(_G, "GetStatistic")
  if type(list) ~= "table" or not count or not get then return nil end
  local values, ids, any = {}, {}, false
  for _, categoryID in ipairs(list) do
    for i = 1, ns.Try(count, categoryID) or 0 do
      local quantity, _, statID = ns.Try(get, categoryID, i)
      if type(statID) == "number" then
        ids[#ids + 1] = statID
        any = true
        local value = S.Parse(quantity)
        if value > 0 then values[statID] = value end
      end
    end
  end
  local db = ns.DB()
  if db and #ids > 0 then db.statIds = ids end
  return any and values or nil
end

-- Every statistic ID to ask for: the ones the game listed, plus the catalog
local function AllIds()
  local set = {}
  for id in pairs(S.Wanted()) do set[id] = true end
  local db = ns.DB()
  for _, id in ipairs(db and type(db.statIds) == "table" and db.statIds or {}) do set[id] = true end
  return set
end

function GameStats.UpdateOwn()
  local guild = ns.GuildData()
  local values = GameStats.ReadOwn()
  if not guild or not values then return end
  local member = ns.Store.Member(guild, ns.PlayerName())
  local before = member.stats and member.stats.v
  local changed = S.Update(member, values, ns.Now(), "self", GameDate)
  local differs = not before
  if before then
    for id, value in pairs(values) do
      if before[id] ~= value then differs = true break end
    end
  end
  if changed then Fire() end
  -- share at most every 10 minutes and only when something changed
  if differs and ns.Settings().share and GetTime() - lastOwnSend > OWN_INTERVAL - 5 then
    lastOwnSend = GetTime()
    ns.Sync.ShareStats(ns.Names.Key(ns.PlayerName()))
  end
end

-- Whether Blizzard's own windows may be using the comparison unit right now
local function BlizzardBusy()
  for _, name in ipairs({ "AchievementFrame", "InspectFrame", "StatisticsFrame" }) do
    local frame = rawget(_G, name)
    if frame and frame.IsShown and frame:IsShown() then return true end
  end
  return false
end

local function Clear()
  local clear = rawget(_G, "ClearAchievementComparisonUnit")
  if clear then pcall(clear) end
end

-- Tries to read unit's statistics (a guild member in range)
function GameStats.TryUnit(unit)
  if unit ~= "target" then return end -- other unit tokens disconnected the client on Forever
  local set = rawget(_G, "SetAchievementComparisonUnit")
  if not set or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
  local name = ns.Names.FromUnit(UnitName(unit))
  local m = ns.Roster.Find(name)
  if not m then return end
  local now = GetTime()
  if tried[m.key] and now < tried[m.key] then return end -- quiet: already read or waiting to retry
  local guild = ns.GuildData()
  local rec = guild and guild.members[m.key] and guild.members[m.key].stats
  if rec and rec.ts and ns.Now() - rec.ts < MEMBER_GAP then return end
  if pending then return end
  if InCombatLockdown() then return Log(m.name .. ": combat") end
  if BlizzardBusy() then return Log(m.name .. ": Blizzard window open") end
  if now - lastRequest < REQUEST_GAP then return end
  if not ns.Try(rawget(_G, "UnitIsConnected"), unit) then return Log(m.name .. ": offline") end
  local canInspect = rawget(_G, "CanInspect")
  if canInspect and not ns.Try(canInspect, unit) then return Log(m.name .. ": can't inspect (" .. unit .. ")") end
  -- the comparison only answers in inspect range (about 28 yards); further away: don't even ask
  local inRange = rawget(_G, "CheckInteractDistance")
  if inRange and ns.Try(inRange, unit, 1) == false then return Log(m.name .. ": too far away") end
  lastRequest = now
  tried[m.key] = now + RETRY
  pending = { key = m.key, name = m.name, guid = ns.Try(rawget(_G, "UnitGUID"), unit), at = now }
  -- SetAchievementComparisonUnit returns nothing: only a failing call counts
  if not pcall(set, unit) then
    pending = nil
    return Log(m.name .. ": request failed")
  end
  Log(m.name .. ": asked (" .. unit .. ")")
  C_Timer.After(TIMEOUT, function()
    if pending and pending.at == now then
      Log(pending.name .. ": no answer, retry in " .. RETRY .. " s")
      pending = nil
      Clear()
    end
  end)
end

-- INSPECT_ACHIEVEMENT_READY (guid of the compared player)
function GameStats.OnComparisonReady(guid)
  if not pending then return end
  if guid and pending.guid and guid ~= pending.guid then return end
  local request = pending
  pending = nil
  tried[request.key] = GetTime() + MEMBER_GAP
  local get = rawget(_G, "GetComparisonStatistic")
  local guild = ns.GuildData()
  if not get or not guild then
    Clear()
    return
  end
  local values, nonZero = {}, false
  for id in pairs(AllIds()) do
    local value = S.Parse(ns.Try(get, id))
    if value > 0 then
      values[id] = value
      nonZero = true
    end
  end
  Clear()
  if not nonZero then return Log(request.name .. ": answer was empty") end -- don't store zeros
  Log(request.name .. ": read")
  local member = ns.Store.Member(guild, request.name)
  if S.Update(member, values, ns.Now(), "seen", GameDate) then
    Fire()
    ns.Sync.ShareStats(request.key)
  end
end

function GameStats.Start()
  C_Timer.After(8, function() ns.SafeCall(GameStats.UpdateOwn) end)
  C_Timer.NewTicker(OWN_INTERVAL, function() ns.SafeCall(GameStats.UpdateOwn) end)
end

-- Values of the guild for the UI: { {key, name, classFile, rec, member} } of current roster members
function GameStats.Entries()
  local guild = ns.GuildData()
  local list = {}
  if not guild then return list end
  for _, m in ipairs(ns.Roster.Members()) do
    local record = guild.members[m.key]
    if record and type(record.stats) == "table" and record.stats.v then
      list[#list + 1] = { key = m.key, name = m.name, classFile = m.classFile, rec = record.stats, member = m }
    end
  end
  return list
end

function GameStats.Date(fmt, ts) return GameDate(fmt, ts) end
