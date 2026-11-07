-- Reads statistics from the game for the Hall of Fame (data model in Core/Stats.lua).
-- Own character: Forever's Statistics API (GetStatisticsCategoryList / GetCategoryNumAchievements /
-- GetStatistic(category, index)), after login and every 10 minutes.
-- Other guild members: Blizzard's achievement comparison (SetAchievementComparisonUnit + the event
-- INSPECT_ACHIEVEMENT_READY + GetComparisonStatistic(id)). Only for the TARGET: on Forever that works
-- (verified twice), while asking for "party2" got no answer and asking for party/mouseover units was
-- followed by a server disconnect (2026-11-06, before the range and rate limits below existed).
-- Guildy asks quietly when a guild member becomes the target: one request at a time, at most every
-- 10 seconds, each member at most once an hour, never in combat and never while Blizzard's own
-- achievement or inspect window may be using it.
-- Right after the statistics Guildy inspects the same member (NotifyInspect + INSPECT_READY) for the
-- equipment and stores both together; without an answer the statistics are stored alone and the last
-- known equipment is kept.
-- Mouseover is a second try under the same limits, off by default (/guildy statmouse). Each mouseover
-- request leaves a mark in GuildyDB until it is answered or times out; a mark still there at the next
-- login means the session ended during a request, and Guildy turns mouseover off again.
local _, ns = ...
local S = ns.Stats

local GameStats = {}
ns.GameStats = GameStats

local OWN_INTERVAL = 600
local REQUEST_GAP = 10
local MEMBER_GAP = 3600
local TIMEOUT = 5
local RETRY = 120       -- no answer (out of range): try that member again after 2 minutes
local LATE_GEAR = 60    -- seconds the kept equipment waits for the member to be under the mouse again
local INSPECT_WAIT = 3  -- seconds to wait for the equipment after the statistics

local pending          -- { key, name, guid, unit, at }
local inspecting       -- { request, values }: waiting for INSPECT_READY after the statistics
local lastRequest = 0
local tried = {}       -- nameKey -> GetTime() of the last request this session
local lastOwnSend = 0
local lateGear         -- { request, values, untilTime }: inspect answered, member gone; read on the next hover
local noGear = {}      -- nameKey -> true: last read this session came without equipment
local resetAt = 0      -- /guildy statreset: values stored before this count as old
-- Test phase for mouseover: when true, mouseover reading is always on (whatever the setting says)
-- (the range is not checked any more). Only for local tests, false in releases. Debug output only with
-- /guildy statdebug.
GameStats.TESTING = false
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
  if not any then return nil end
  for id, value in pairs(GameStats.ReadGear() or {}) do values[id] = value end
  return values
end

-- Own equipment (Stats.GEAR), or nil while item info is still loading: then the game is asked to load
-- it, the last equipment is kept and Guildy reads again a few seconds later (at most GEAR_TRIES times).
local GEAR_TRIES = 5
local gearTries = 0
local function ItemInfoFunction()
  return rawget(_G, "GetItemInfo") or (C_Item and C_Item.GetItemInfo)
end

-- Equipment of unit ("player" or an inspected member), nil while item info is missing
local function ReadUnitGear(unit)
  local getLink, getInfo = rawget(_G, "GetInventoryItemLink"), ItemInfoFunction()
  if not getLink or not getInfo then return nil end
  return S.ReadGear(function(slot) return ns.Try(getLink, unit, slot) end,
    function(link) return ns.Try(getInfo, link) end)
end

-- Asks the game to load the item info of unit's equipment
local function LoadUnitItems(unit)
  local request = C_Item and C_Item.RequestLoadItemDataByID
  local getID = rawget(_G, "GetInventoryItemID")
  if not request or not getID then return end
  for _, slot in ipairs(S.GEAR_SLOTS) do
    local itemID = ns.Try(getID, unit, slot)
    if itemID then ns.Try(request, itemID) end
  end
end

function GameStats.ReadGear()
  local gear = ReadUnitGear("player")
  if gear then
    gearTries = 0
    return gear
  end
  LoadUnitItems("player")
  if gearTries < GEAR_TRIES then
    gearTries = gearTries + 1
    C_Timer.After(3, function() ns.SafeCall(GameStats.UpdateOwn) end)
  end
  return nil
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

-- PLAYER_EQUIPMENT_CHANGED: read again a few seconds later (changing a whole set is one reading)
local gearTimer
function GameStats.OnEquipmentChanged()
  if gearTimer then gearTimer:Cancel() end
  gearTimer = C_Timer.NewTimer(5, function()
    gearTimer = nil
    ns.SafeCall(GameStats.UpdateOwn)
  end)
end

-- Whether Blizzard's own windows may be using the comparison unit right now
local function BlizzardBusy()
  for _, name in ipairs({ "AchievementFrame", "InspectFrame", "StatisticsFrame" }) do
    local frame = rawget(_G, name)
    if frame and frame.IsShown and frame:IsShown() then return true end
  end
  return false
end

-- A unit token that points to the requested member right now: the mouse moves on long before the
-- answers arrive, so besides the asked unit also target, focus, group and nameplates are tried.
local function FindUnit(request)
  if not request.guid then return nil end
  local guidOf = rawget(_G, "UnitGUID")
  local function Is(unit) return ns.Try(guidOf, unit) == request.guid end
  for _, unit in ipairs({ request.unit, "target", "focus", "mouseover" }) do
    if unit and Is(unit) then return unit end
  end
  for i = 1, 4 do if Is("party" .. i) then return "party" .. i end end
  for i = 1, 40 do if Is("raid" .. i) then return "raid" .. i end end
  for i = 1, 40 do if Is("nameplate" .. i) then return "nameplate" .. i end end
  return nil
end

-- Blizzard's achievement window answers every INSPECT_ACHIEVEMENT_READY once it is loaded, and on
-- Forever that breaks (GetCategoryNumAchievements with the "summary" category, error in
-- Blizzard_AchievementUI). While Guildy asks, its frames don't get the event; afterwards they do again.
local quieted = {}
local function QuietBlizzard()
  local list = { rawget(_G, "AchievementFrameComparison"), rawget(_G, "AchievementFrame") }
  local registered = rawget(_G, "GetFramesRegisteredForEvent")
  if registered then
    for _, frame in ipairs({ ns.Try(registered, "INSPECT_ACHIEVEMENT_READY") }) do
      local name = type(frame) == "table" and frame.GetName and frame:GetName()
      if name and name:find("^Achievement") then list[#list + 1] = frame end
    end
  end
  for _, frame in ipairs(list) do
    if frame and not quieted[frame] and frame.IsEventRegistered
      and frame:IsEventRegistered("INSPECT_ACHIEVEMENT_READY") then
      frame:UnregisterEvent("INSPECT_ACHIEVEMENT_READY")
      quieted[frame] = true
    end
  end
end

local function WakeBlizzard()
  for frame in pairs(quieted) do
    pcall(frame.RegisterEvent, frame, "INSPECT_ACHIEVEMENT_READY")
    quieted[frame] = nil
  end
end

local function Clear()
  local clear = rawget(_G, "ClearAchievementComparisonUnit")
  if clear then pcall(clear) end
  WakeBlizzard()
end

-- Tries to read unit's statistics (a guild member in range)
local function MarkProbe(text)
  local db = ns.DB()
  if db then db.mouseoverProbe = text end
end

function GameStats.TryUnit(unit)
  -- other unit tokens disconnected the client on Forever; mouseover only when switched on
  if unit ~= "target" and not (unit == "mouseover" and (GameStats.TESTING or ns.Settings().statMouseover)) then return end
  if lateGear and GameStats.CheckLateGear(unit) then return end
  local set = rawget(_G, "SetAchievementComparisonUnit")
  if not set or not UnitExists(unit) or not UnitIsPlayer(unit) or UnitIsUnit(unit, "player") then return end
  local name = ns.Names.FromUnit(UnitName(unit))
  if name == "" then return end -- secret name (instance) or no name
  local m = ns.Roster.Find(name)
  if not m then
    -- a member of the own guild Guildy can't find in the roster: name format problem
    local unitGuild = ns.Try(rawget(_G, "GetGuildInfo"), unit)
    if unitGuild and unitGuild == ns.Try(rawget(_G, "GetGuildInfo"), "player") then
      Log(tostring(name) .. ": in the guild but not found in the roster (" .. unit .. ")")
    end
    return
  end
  local now = GetTime()
  if tried[m.key] and now < tried[m.key] then
    return Log(("%s: no new request for %d s"):format(m.name, math.ceil(tried[m.key] - now)))
  end
  local guild = ns.GuildData()
  local rec = guild and guild.members[m.key] and guild.members[m.key].stats
  -- values without creature kills at level 10+ are an incomplete answer from before: read again now
  local complete = not rec or (m.level or 0) < 10 or (type(rec.v) == "table" and rec.v[107])
  -- read without equipment this session: ask again after RETRY instead of after an hour
  if noGear[m.key] then complete = false end
  -- no equipment stored yet (never inspected, or an old incomplete read dropped): ask now
  if rec and type(rec.v) == "table" and not S.HasGear(rec.v) then complete = false end
  local fresh = rec and rec.ts and rec.ts >= resetAt and ns.Now() - rec.ts < MEMBER_GAP
  if fresh and complete then
    return Log(("%s: values are %d min old, read again after 60 min"):format(m.name, math.floor((ns.Now() - rec.ts) / 60)))
  end
  if pending then return Log(m.name .. ": waiting for the answer about " .. pending.name) end
  if inspecting then return Log(m.name .. ": waiting for the equipment of " .. inspecting.request.name) end
  if InCombatLockdown() then return Log(m.name .. ": combat") end
  if BlizzardBusy() then return Log(m.name .. ": Blizzard window open") end
  if now - lastRequest < REQUEST_GAP then
    return Log(("%s: last request %d s ago, at most one every %d s"):format(m.name, math.floor(now - lastRequest), REQUEST_GAP))
  end
  if not ns.Try(rawget(_G, "UnitIsConnected"), unit) then return Log(m.name .. ": offline") end
  local canInspect = rawget(_G, "CanInspect")
  if canInspect and not ns.Try(canInspect, unit) then return Log(m.name .. ": can't inspect (" .. unit .. ")") end
  -- Forever answers far beyond the 28 yards of CheckInteractDistance (seen at about 200 yards,
  -- 2026-11-07): ask whenever the member is visible; the range is only logged. No answer = retry later.
  local visible = rawget(_G, "UnitIsVisible")
  if visible and ns.Try(visible, unit) == false then return Log(m.name .. ": not visible") end
  local inRange = rawget(_G, "CheckInteractDistance")
  local near = not inRange or ns.Try(inRange, unit, 1) ~= false
  local range = near and "within 28 yd" or "beyond 28 yd"
  lastRequest = now
  tried[m.key] = now + RETRY
  pending = { key = m.key, name = m.name, guid = ns.Try(rawget(_G, "UnitGUID"), unit), unit = unit, at = now }
  if unit == "mouseover" then MarkProbe(m.name) end
  QuietBlizzard()
  -- SetAchievementComparisonUnit returns nothing: only a failing call counts
  if not pcall(set, unit) then
    WakeBlizzard()
    pending = nil
    MarkProbe(nil)
    return Log(m.name .. ": request failed")
  end
  Log(m.name .. ": asked (" .. unit .. ", " .. range .. ")")
  -- the inspect for the equipment goes out at once, while the member is still under the mouse
  local request = pending
  request.job = GameStats.StartInspect(request, nil)
  C_Timer.After(TIMEOUT, function()
    if pending and pending.at == now and not pending.reading then
      GameStats.DropInspect(pending.job)
      Log(pending.name .. ": no answer, retry in " .. RETRY .. " s")
      pending = nil
      MarkProbe(nil)
      Clear()
    end
  end)
end

-- INSPECT_ACHIEVEMENT_READY (guid of the compared player). The answer can come in parts: a level 22
-- member was stored with 8 values and no creature kills. So the values are read twice (now and
-- READ_AGAIN seconds later, the higher value wins), and an answer without creature kills for a member
-- of level MIN_LEVEL or more counts as incomplete and is not stored.
local READ_AGAIN = 1.5
local MIN_LEVEL = 10
local CREATURES = 107

local function ReadComparison(get, values)
  for id in pairs(AllIds()) do
    local value = S.Parse(ns.Try(get, id))
    if value > (values[id] or 0) then values[id] = value end
  end
end

local function Count(values)
  local count = 0
  for _ in pairs(values) do count = count + 1 end
  return count
end

function GameStats.OnComparisonReady(guid)
  if not pending or pending.reading then return end
  if guid and pending.guid and guid ~= pending.guid then return end
  local request = pending
  request.reading = true
  MarkProbe(nil)
  tried[request.key] = GetTime() + MEMBER_GAP
  local get = rawget(_G, "GetComparisonStatistic")
  local guild = ns.GuildData()
  if not get or not guild then
    pending = nil
    GameStats.DropInspect(request.job)
    Clear()
    return
  end
  local values = {}
  ReadComparison(get, values)
  local first = Count(values)
  -- the inspect started with the request; if that failed, try once more now
  local job = request.job
  if not job or job.failed then job = GameStats.StartInspect(request, values) end
  job.values = values
  C_Timer.After(READ_AGAIN, function()
    ns.SafeCall(function()
      ReadComparison(get, values)
      if pending == request then pending = nil end
      Clear()
      local count = Count(values)
      if count == 0 then
        GameStats.DropInspect(job)
        return Log(request.name .. ": answer was empty") -- don't store zeros
      end
      local m = ns.Roster.Find(request.name)
      if m and (m.level or 0) >= MIN_LEVEL and not values[CREATURES] then
        tried[request.key] = GetTime() + RETRY
        GameStats.DropInspect(job)
        return Log(("%s: answer incomplete (%d values, no creature kills at level %d), retry in %d s")
          :format(request.name, count, m.level, RETRY))
      end
      Log(("%s: read (%d values, %d at first)"):format(request.name, count, first))
      GameStats.StatsDone(request, values, job)
    end)
  end)
end

-- Equipment after the statistics -----------------------------------------------------------------

local function StoreRead(request, values)
  local guild = ns.GuildData()
  if not guild then return end
  local member = ns.Store.Member(guild, request.name)
  if S.Update(member, values, ns.Now(), "seen", GameDate) then
    Fire()
    ns.Sync.ShareStats(request.key)
  end
end

local function ClearInspect()
  local clear = rawget(_G, "ClearInspectPlayer")
  if clear and not BlizzardBusy() then pcall(clear) end
end

-- Statistics and equipment are asked for together (the inspect starts with the first read of the
-- statistics) and stored together once both are done; without an equipment answer the statistics are
-- stored alone and the last known equipment is kept.
local function Finish(job)
  if job.finished then return end
  job.finished = true
  if inspecting == job then inspecting = nil end
  for id, value in pairs(job.gear or {}) do job.values[id] = value end
  local key = job.request.key
  if job.gear and job.gear[S.GEAR.ILVL] then
    noGear[key] = nil
  else
    noGear[key] = true
    tried[key] = GetTime() + RETRY
  end
  Log(job.request.name .. (job.gear and job.gear[S.GEAR.ILVL]
    and (": equipment read (" .. tostring(job.gearUnit) .. "), item level " .. job.gear[S.GEAR.ILVL] / 10)
    or (": statistics stored without equipment (" .. (job.why or "no answer") .. "), next try in " .. RETRY .. " s")))
  StoreRead(job.request, job.values)
  if not job.gear and job.answered and job.why == "member no longer in a unit" then
    -- the game has the equipment, only no unit points to the member: keep it until the next hover
    local values = {}
    for id, value in pairs(job.values) do values[id] = value end
    lateGear = { request = job.request, values = values, untilTime = GetTime() + LATE_GEAR }
    Log(job.request.name .. ": equipment kept, read when the mouse or target is on them again (" .. LATE_GEAR .. " s)")
    return
  end
  ClearInspect()
end

local function GearDone(job)
  job.gearDone = true
  if job.statsDone then Finish(job) end
end

-- Starts the inspect for request; returns the job (job.failed with job.why when it could not start)
function GameStats.StartInspect(request, values)
  local notify = rawget(_G, "NotifyInspect")
  local unit = FindUnit(request)
  local why = (not notify and "no inspect") or (not unit and "member no longer in a unit")
    or (InCombatLockdown() and "combat") or (BlizzardBusy() and "Blizzard window open") or nil
  if why then return { request = request, values = values, why = why, failed = true } end
  local job = { request = request, values = values, unit = unit }
  lateGear = nil -- a new inspect replaces the kept equipment
  inspecting = job
  if not pcall(notify, unit) then
    inspecting = nil
    job.why, job.failed = "inspect failed", true
    return job
  end
  return job
end

-- The statistics are not stored: forget the inspect too
function GameStats.DropInspect(job)
  if not job then return end
  job.finished = true
  if inspecting == job then
    inspecting = nil
    ClearInspect()
  end
end

-- The statistics are read: store now, or when the equipment is there
function GameStats.StatsDone(request, values, job)
  job = job or { request = request, values = values, failed = true }
  job.values = values
  job.statsDone = true
  if job.failed or job.gearDone then return Finish(job) end
  Log(request.name .. ": waiting for the equipment")
  C_Timer.After(INSPECT_WAIT, function()
    if job.finished or job.gearDone or job.gearReading then return end -- reading takes its own time
    job.why = "no equipment answer"
    GearDone(job)
  end)
end

-- INSPECT_READY (guid of the inspected player): only the answer Guildy asked for. The links of an
-- inspected member arrive slot by slot after the event (Eoy Goldcog: 2 of 15 items at first), so
-- Guildy reads up to GEAR_READS times a second apart and stops once every slot with an item ID also
-- has a link and two reads in a row found the same number of items (item IDs may be missing too);
-- otherwise the read with the most items wins.
local GEAR_READS = 6
local REINSPECT_AT = 2 -- still missing items at this read: inspect once more (fills in the rest)

local function CountSlots(unit)
  local getID, getLink = rawget(_G, "GetInventoryItemID"), rawget(_G, "GetInventoryItemLink")
  local ids, links = 0, 0
  for _, slot in ipairs(S.GEAR_SLOTS) do
    if getID and ns.Try(getID, unit, slot) then ids = ids + 1 end
    if getLink and ns.Try(getLink, unit, slot) then links = links + 1 end
  end
  return ids, links
end

function GameStats.OnInspectReady(guid)
  local job = inspecting
  if not job or job.gearDone or job.gearReading
    or (guid and job.request.guid and guid ~= job.request.guid) then return end
  job.gearReading = true
  job.answered = true
  local last = -1
  local function Attempt(n)
    if job.finished or job.gearDone then return end
    local unit = FindUnit(job.request)
    if unit then
      local ids, links = CountSlots(unit)
      local gear = ReadUnitGear(unit)
      local steady = links == last
      last = links
      if gear and gear[S.GEAR.ILVL] and links > 0 and links >= ids and steady then
        -- only a complete read is kept: never store part of the equipment
        job.gear, job.gearUnit = gear, unit
        Log(("%s: equipment complete after %d read(s), %d items"):format(job.request.name, n, links))
        return GearDone(job)
      end
      job.why = gear and ("only " .. links .. " of " .. ids .. " items") or "item info not loaded"
      job.lastIds = ids
      LoadUnitItems(unit)
      local notify = rawget(_G, "NotifyInspect")
      if n == REINSPECT_AT and notify and not InCombatLockdown() and not BlizzardBusy() then
        Log(("%s: %d of %d items, inspecting once more"):format(job.request.name, links, ids))
        pcall(notify, unit)
      end
    else
      job.why = "member no longer in a unit"
    end
    if n >= GEAR_READS then
      Log(("%s: equipment not complete after %d reads (%s), not stored"):format(job.request.name, n,
        tostring(job.why)))
      return GearDone(job)
    end
    C_Timer.After(1, function() ns.SafeCall(Attempt, n + 1) end)
  end
  Attempt(1)
end

-- The kept equipment of lateGear, read when unit (mouse or target) shows that member again.
-- Returns true when unit was that member (no new request for them then).
function GameStats.CheckLateGear(unit)
  local late = lateGear
  if GetTime() > late.untilTime then
    lateGear = nil
    ClearInspect()
    return false
  end
  if ns.Try(rawget(_G, "UnitGUID"), unit) ~= late.request.guid then return false end
  local ids, links = CountSlots(unit)
  local gear = ReadUnitGear(unit)
  if not (gear and gear[S.GEAR.ILVL] and links > 0 and links >= ids) then
    LoadUnitItems(unit)
    Log(("%s: kept equipment not complete yet (%d of %d items)"):format(late.request.name, links, ids))
    return true
  end
  lateGear = nil
  for id, value in pairs(gear) do late.values[id] = value end
  noGear[late.request.key] = nil
  tried[late.request.key] = GetTime() + MEMBER_GAP
  Log(("%s: equipment read on the next look (%s), item level %s, %d items"):format(
    late.request.name, unit, gear[S.GEAR.ILVL] / 10, links))
  ClearInspect()
  -- into the record stored a moment ago (S.Update would skip it within the same second)
  local guild = ns.GuildData()
  local rec = guild and guild.members[late.request.key] and guild.members[late.request.key].stats
  if type(rec) ~= "table" or type(rec.v) ~= "table" then
    StoreRead(late.request, late.values)
    return true
  end
  local month = rec.months and rec.months[S.MonthKey(ns.Now(), GameDate)]
  for id, value in pairs(gear) do
    rec.v[id] = value
    if month and type(month.v) == "table" and month.v[id] == nil then month.v[id] = value end
  end
  rec.ts = math.max((rec.ts or 0) + 1, ns.Now()) -- newer than the copy without equipment others got
  Fire()
  ns.Sync.ShareStats(late.request.key)
  return true
end

-- /guildy statreset: every member can be asked again right away (waits and stored ages forgotten)
function GameStats.ResetWaits()
  tried, noGear, lastRequest, resetAt = {}, {}, 0, ns.Now() + 1
  ns.Print("statreset: every guild member can be read again right away")
end

-- Tests only: forget request state (rate limits, retries)
function GameStats._ResetForTest()
  pending, inspecting, lastRequest, tried, noGear, lateGear = nil, nil, 0, {}, {}, nil
end

-- /guildy statshow [name]: what Guildy knows about one member's statistics (for bug reports); without
-- a name the own character
function GameStats.Show(name)
  name = name and name:match("^%s*(.-)%s*$") or ""
  if name == "" then name = ns.PlayerName() end
  local guild = ns.GuildData()
  local key = ns.Names.Key(name or "")
  local m = ns.Roster.Find(name or "")
  local record = guild and guild.members[key]
  local rec = record and record.stats
  ns.Print(("statshow %s: roster %s, record %s"):format(tostring(name), m and "yes" or "no", rec and "yes" or "no"))
  if type(rec) ~= "table" then return end
  local count = 0
  for _ in pairs(rec.v or {}) do count = count + 1 end
  local months = {}
  for month in pairs(rec.months or {}) do months[#months + 1] = month end
  table.sort(months)
  local now = ns.Now()
  ns.Print(("  src %s, %d min old, %d values, months %s"):format(tostring(rec.src),
    rec.ts and math.floor((now - rec.ts) / 60) or -1, count, table.concat(months, " ")))
  local ids = {}
  for id in pairs(rec.v or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  local parts = {}
  for i = 1, math.min(#ids, 20) do parts[i] = ids[i] .. "=" .. tostring(rec.v[ids[i]]) end
  ns.Print("  values: " .. table.concat(parts, ", ") .. (#ids > 20 and ", ..." or ""))
  for _, period in ipairs({ "all", "month", "last" }) do
    ns.Print(("  %s: creatures %s, quests %s, bosses %s"):format(period,
      tostring(S.Value(rec, 107, period, now, GameDate)), tostring(S.Value(rec, 98, period, now, GameDate)),
      tostring(S.Value(rec, "bosses", period, now, GameDate))))
  end
  local listed = false
  for _, entry in ipairs(GameStats.Entries()) do
    if entry.key == key then listed = true end
  end
  ns.Print("  in the Hall of Fame list: " .. (listed and "yes" or "no"))
  local gear = {}
  for _, id in ipairs({ S.GEAR.ILVL, S.GEAR.EPIC, S.GEAR.RARE, S.GEAR.UNCOMMON, S.GEAR.COMMON,
    S.GEAR.POOR, S.GEAR.LEGENDARY, S.GEAR.EMPTY, S.GEAR.COUNT, 339, 338 }) do
    gear[#gear + 1] = id .. "=" .. tostring(rec.v and rec.v[id])
  end
  ns.Print("  equipment: " .. table.concat(gear, ", "))
  if ns.Names.Same(name or "", ns.PlayerName()) then
    local reading = GameStats.ReadGear()
    ns.Print(("  reading now: link %s, item info %s, result %s"):format(
      rawget(_G, "GetInventoryItemLink") and "yes" or "no", ItemInfoFunction() and "yes" or "no",
      reading and tostring(reading[S.GEAR.ILVL]) or "nil"))
  end
end

-- /guildy statmouse: switches reading guild members under the mouse on or off
function GameStats.ToggleMouseover()
  local settings = ns.Settings()
  settings.statMouseover = not settings.statMouseover
  ns.Print("statmouse " .. (settings.statMouseover and "on: guild members under the mouse are read nearby" or "off"))
end

function GameStats.Start()
  local db = ns.DB()
  if db and db.mouseoverProbe then
    -- the last session ended while a mouseover request was open: probably the disconnect again
    if GameStats.TESTING then
      ns.Print(("stats: the last session ended during a mouseover request (%s). Mouseover stays on (test phase)."):format(tostring(db.mouseoverProbe)))
    else
      ns.Print(("statmouse off: the last session ended during a mouseover request (%s)."):format(tostring(db.mouseoverProbe)))
      db.settings.statMouseover = false
    end
    db.mouseoverProbe = nil
  end
  -- equipment read nearby by older versions (no item count) may be incomplete: dropped
  for _, guild in pairs(db and type(db.guilds) == "table" and db.guilds or {}) do
    for _, member in pairs(type(guild) == "table" and type(guild.members) == "table" and guild.members or {}) do
      if type(member) == "table" then S.CleanRecord(member.stats) end
    end
  end
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
