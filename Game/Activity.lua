-- The game side of Core/Activity.lua: marks the days members were seen online after every roster scan,
-- counts the days the own character was played, and computes the activity of the guild for the UI
-- (kept until the roster or the statistics change).
local _, ns = ...

local GameActivity = {}
ns.GameActivity = GameActivity

local A = ns.Activity
local cache

local function Date(fmt, ts)
  return ns.GameStats.Date(fmt, ts)
end

-- Days change at 5 in the morning local time, so an evening that runs past midnight is one day
local DAY_STARTS = 5 * 3600
local function SetDayShift()
  local date, time = rawget(_G, "date"), rawget(_G, "time")
  local now = ns.Now()
  local ok, offset = pcall(function() return time(date("*t", now)) - time(date("!*t", now)) end)
  A.SetDayShift((ok and type(offset) == "number" and offset or 0) - DAY_STARTS)
end

-- What the scores are worked out from besides the statistics and the member list (GameStats.version,
-- Roster.version): goes up when a member's seen days, online state or whole days offline change, or a
-- family changes (FAMILY, or a public or officer note: Family.Mains links characters through both). A roster scan that shows nothing new of that (the usual one, every few seconds) leaves
-- the scores as they are; measured in game 2026-11-13: every scan threw them away and the next render of
-- the character page worked them out anew for the whole guild (3.1 ms average, 10.9 ms max).
local seenVersion, familyVersion = 0, 0
local away = {} -- member key -> -1 online, whole days offline, -2 unknown (at the last scan)
local notes = {} -- member key -> public and officer note joined (at the last scan)

local function Away(m)
  if m.online then return -1 end
  return type(m.daysOffline) == "number" and math.floor(m.daysOffline) or -2
end

-- After a roster scan: today for who is online, the day of the roster's "last online" for the others.
-- Nothing while names are made up for pictures (the roster is the real one, but nothing new is kept).
local function MarkRoster()
  local members = ns.Roster.Members()
  local changed, linked = false, false
  for _, m in ipairs(members) do
    local now = Away(m)
    if away[m.key] ~= now then
      away[m.key] = now
      changed = true
    end
    local note = (m.note or "") .. "\031" .. (m.officerNote or "")
    if notes[m.key] ~= note then
      if notes[m.key] ~= nil then linked = true end
      notes[m.key] = note
    end
  end
  if linked then familyVersion = familyVersion + 1 end
  local guild = not ns.Anon.on and ns.GuildData() or nil
  if guild and #members > 0 then
    local now = ns.Now()
    local today = A.Day(now)
    if type(guild.seenSince) ~= "number" then guild.seenSince = today end
    for _, m in ipairs(members) do
      local day = A.LastSeenDay(now, m.online, m.daysOffline)
      if day and day > today - A.DAYS_KEPT then
        if A.MarkSeen(guild.members[m.key] or ns.Store.Member(guild, m.name), day) then changed = true end
      end
    end
  end
  if changed then seenVersion = seenVersion + 1 end
end

-- The number of days the own character was played, one more on the first call of each day
-- (GuildyDB.ownDays[key] = { day, n }); it goes into the own statistics record as Stats.DAYS. A count
-- lost with the saved data goes on from what the guild's record of the character still says.
function GameActivity.OwnDays()
  local db = ns.DB()
  if not db then return nil end
  local key = ns.Names.Key(ns.PlayerName())
  local own = type(db.ownDays) == "table" and db.ownDays[key] or nil
  if ns.Anon.on then return type(own) == "table" and own.n or nil end
  if type(db.ownDays) ~= "table" then db.ownDays = {} end
  if type(own) ~= "table" or type(own.n) ~= "number" then
    local guild = ns.GuildData()
    local record = guild and guild.members[key]
    local known = record and type(record.stats) == "table" and type(record.stats.v) == "table" and record.stats.v[ns.Stats.DAYS]
    own = { n = type(known) == "number" and known or 0 }
    db.ownDays[key] = own
  end
  SetDayShift()
  local today = A.Day(ns.Now())
  if own.day ~= today then own.day, own.n = today, own.n + 1 end
  return own.n
end

-- { players, byKey (Activity.Players), summary (Activity.Summary), change = pulse against last month's
-- or nil, month (Activity.Month) }
-- Kept until the statistics, the member list, a family, the seen days or the day change (or the guild,
-- or names made up for pictures); the character page, the members tab and the overview share it
function GameActivity.Get()
  local guild, db = ns.GuildData(), ns.DB()
  local now = ns.Now()
  local day = A.Day(now)
  local c = cache
  if c and c.stats == ns.GameStats.version and c.roster == ns.Roster.version and c.seen == seenVersion
    and c.families == familyVersion and c.day == day and c.guild == guild and c.anon == ns.Anon.on then
    return c
  end
  local members = ns.Roster.Members()
  local mains = ns.Family.Mains(members, guild and guild.families, db and db.ownChars)
  local function RecordOf(m) return guild and guild.members[m.key] or nil end
  local since = guild and guild.seenSince
  local players, byKey = A.Players(members, mains, RecordOf, now, Date, since)
  local summary = A.Summary(players)
  local month = ns.Stats.MonthKey(now, Date)
  local change
  if guild then
    if not ns.Anon.on then A.StorePulse(guild, month, summary.pulse) end
    change = A.PulseChange(guild, summary.pulse, ns.Stats.PreviousMonth(month))
  end
  cache = { players = players, byKey = byKey, summary = summary, change = change,
    month = A.Month(ns.GameStats.Entries(), players, RecordOf, now, Date, since),
    stats = ns.GameStats.version, roster = ns.Roster.version, seen = seenVersion, families = familyVersion, day = day,
    guild = guild, anon = ns.Anon.on }
  return cache
end

-- Score and parts of the player a member belongs to (nil without a score)
function GameActivity.ScoreOf(memberKey)
  local player = GameActivity.Get().byKey[memberKey]
  if not player then return nil end
  return player.score, player.parts, player.detail
end

-- One line for the chat: the pulse, the five bars and the median (/guildy activity)
function GameActivity.Report()
  local summary = GameActivity.Get().summary
  local b = summary.buckets
  return ns.L.ACTIVITY_REPORT:format(tostring(summary.pulse or "-"), b[1], b[2], b[3], b[4], b[5], tostring(summary.median or "-"))
end

ns.On("ROSTER", function()
  SetDayShift()
  MarkRoster()
end)
ns.On("FAMILY", function() familyVersion = familyVersion + 1 end)
