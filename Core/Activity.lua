-- How active the guild is: an activity score 0-100 per player from the game's statistics (Core/Stats.lua)
-- and from the days a member was seen online, the guild's pulse as their average, and the totals of the
-- month. Pure: takes and returns tables, the time and the date function are passed in.
--   member.seen = { [day] = true }      -- days (Activity.Day) on which this client saw the member online
--   guild.seenSince = day               -- the day this client began to count
--   guild.pulse = { ["2026-11"] = 74 }  -- the pulse last computed in each month
-- The score has three parts (Activity.MAX): presence (days online a week), playing (kills, quests) and
-- group play, one pot of points for raid bosses, dungeon bosses, dungeon runs and battlegrounds, so a
-- player reaches its top by raiding, by dungeons alone or by PvP alone. Playing and group play are bent
-- by a saturating curve. A player without a current reading has no score, never a low one.
local _, ns = ...

local Activity = {}
ns.Activity = Activity

local DAY = 86400

Activity.DAYS_KEPT = 60
Activity.MAX = { presence = 30, playing = 25, group = 45 }
Activity.GROUP_POINTS = { raidBosses = 10, dungeonBosses = 3, dungeons = 1, battlegrounds = 3 } -- per event
Activity.K_GROUP = 30    -- group points a week that fill 63 % of the group part
Activity.K_PLAYING = 5   -- the same for playing, in (kills + 5 x honorable kills) / 100 + quests / 2
Activity.FULL_PRESENCE = 5 -- days a week for the whole presence part
Activity.MIN_SPAN = 3      -- days between snapshot and reading below which there are no rates
Activity.CURRENT_DAYS = 7  -- a reading this young is current whatever the member did since
Activity.MIN_COUNTED = 7   -- days counted before presence is rated at all
Activity.GONE_DAYS = 30    -- last online this long ago: the score is 0, with or without a reading
Activity.PULSES_KEPT = 4

-- weekly counts of a rates table, and the statistic each comes from
local COUNTS = { kills = 107, honorKills = 588, quests = 98, dungeons = 932, battlegrounds = 839,
  raidBosses = "raidBosses", dungeonBosses = "dungeonBosses" }

-- days ----------------------------------------------------------------------------------------------------

function Activity.Day(ts)
  return math.floor(ts / DAY)
end

-- The day a member was last online, from the roster: today when online, nil when the game does not say
function Activity.LastSeenDay(now, online, daysOffline)
  if online then return Activity.Day(now) end
  if type(daysOffline) ~= "number" then return nil end
  return Activity.Day(now - daysOffline * DAY)
end

-- Marks day in member.seen and forgets the days too old to matter; true when it was new
function Activity.MarkSeen(member, day)
  if type(member.seen) ~= "table" then member.seen = {} end
  if member.seen[day] then return false end
  member.seen[day] = true
  for other in pairs(member.seen) do
    if type(other) ~= "number" or other <= day - Activity.DAYS_KEPT then member.seen[other] = nil end
  end
  return true
end

-- Days from fromDay to toDay marked in any of the seen tables (the characters of one player)
function Activity.SeenCount(seenList, fromDay, toDay)
  local count = 0
  for day = fromDay, toDay do
    for _, seen in ipairs(seenList) do
      if type(seen) == "table" and seen[day] then
        count = count + 1
        break
      end
    end
  end
  return count
end

-- rates ---------------------------------------------------------------------------------------------------

local function Value(values, id)
  return ns.Stats.Value({ v = values }, id, "all") or 0
end

-- What a character did per week between the first reading of the previous month (else of this month)
-- and its newest reading: { span = days, fromDay, toDay, kills, honorKills, quests, raidBosses,
-- dungeonBosses, dungeons, battlegrounds, ownDays }. ownDays is the growth of the member's own days
-- counter over the window (not per week), nil when the counter is younger than the window. untilTs
-- stretches the window past the reading (nothing happened after the last logout). nil without a
-- usable snapshot or with less than MIN_SPAN days. A statistic that went down counts as 0.
function Activity.Rates(rec, now, date, untilTs)
  if type(rec) ~= "table" or type(rec.v) ~= "table" or type(rec.ts) ~= "number" or type(rec.months) ~= "table" then
    return nil
  end
  local this = ns.Stats.MonthKey(now, date)
  local snap = rec.months[ns.Stats.PreviousMonth(this)] or rec.months[this]
  if type(snap) ~= "table" or type(snap.ts) ~= "number" or type(snap.v) ~= "table" then return nil end
  if (rec.ts - snap.ts) / DAY < Activity.MIN_SPAN then return nil end
  local ends = math.max(rec.ts, untilTs or rec.ts)
  local span = (ends - snap.ts) / DAY
  local rates = { span = span, fromDay = Activity.Day(snap.ts), toDay = Activity.Day(ends) }
  for name, id in pairs(COUNTS) do
    rates[name] = math.max(0, Value(rec.v, id) - Value(snap.v, id)) / (span / 7)
  end
  local days, before = rec.v[ns.Stats.DAYS], snap.v[ns.Stats.DAYS]
  if type(days) == "number" and type(before) == "number" then rates.ownDays = math.max(0, days - before) end
  return rates
end

-- Adds the weekly counts of b into a (the characters of one player); returns a
function Activity.AddRates(a, b)
  for name in pairs(COUNTS) do a[name] = (a[name] or 0) + (b[name] or 0) end
  a.span = math.max(a.span or 0, b.span or 0)
  return a
end

-- Whether a statistics reading still says what the member has done: young enough, or taken at or after
-- the last logout of member m (the roster's last online), since nothing can have changed then
function Activity.IsCurrent(rec, m, now)
  if type(rec) ~= "table" or type(rec.ts) ~= "number" then return false end
  if rec.ts >= now - Activity.CURRENT_DAYS * DAY then return true end
  if m.online or type(m.daysOffline) ~= "number" then return false end
  return rec.ts >= now - m.daysOffline * DAY - 3600
end

-- score ---------------------------------------------------------------------------------------------------

local function Curve(max, x, k)
  return max * (1 - math.exp(-x / k))
end

-- Score 0-100 and its parts { presence, playing, group } in points, from weekly rates (of one character
-- or added up over a player's) and the days online a week. Without presence (days not counted long
-- enough) the other two parts are scaled up to 100.
function Activity.Score(rates, presence)
  local max = Activity.MAX
  local points = 0
  for name, worth in pairs(Activity.GROUP_POINTS) do points = points + (rates[name] or 0) * worth end
  local parts = {
    presence = presence and max.presence * math.min(1, presence / Activity.FULL_PRESENCE) or 0,
    playing = Curve(max.playing, ((rates.kills or 0) + 5 * (rates.honorKills or 0)) / 100 + (rates.quests or 0) / 2,
      Activity.K_PLAYING),
    group = Curve(max.group, points, Activity.K_GROUP),
  }
  local sum = parts.presence + parts.playing + parts.group
  if not presence then sum = sum * 100 / (max.playing + max.group) end
  return math.min(100, math.floor(sum + 0.5)), parts
end

-- players -------------------------------------------------------------------------------------------------

-- How recently a member was online, for picking a player's lead character: smaller is more recent
local function Away(m)
  if m.online then return -1 end
  return type(m.daysOffline) == "number" and m.daysOffline or math.huge
end

local function ScorePlayer(player, recordOf, now, date, since)
  local lead = player.chars[1]
  for _, m in ipairs(player.chars) do
    if Away(m) < Away(lead) then lead = m end
  end
  player.lead = lead
  if Away(lead) >= Activity.GONE_DAYS and Away(lead) ~= math.huge then
    player.score, player.parts = 0, { presence = 0, playing = 0, group = 0 }
    return
  end
  local sum, seen, ownDays
  for _, m in ipairs(player.chars) do
    local record = recordOf(m)
    local stats = record and record.stats
    if record then seen = seen or {}; seen[#seen + 1] = record.seen end
    local current = Activity.IsCurrent(stats, m, now)
    -- a reading that is only current because the member has not played since counts up to now
    local stale = current and stats.ts < now - Activity.CURRENT_DAYS * DAY
    local rates = current and Activity.Rates(stats, now, date, stale and now or nil)
    if m == lead and not rates then return end
    if rates then
      if rates.ownDays then ownDays = (ownDays or 0) + rates.ownDays * 7 / rates.span end
      if m == lead then
        sum = Activity.AddRates(rates, sum or {})
      else
        sum = Activity.AddRates(sum or { span = 0 }, rates)
      end
    end
  end
  local presence
  local today = Activity.Day(now)
  if since and sum.fromDay then
    local from = math.max(since, sum.fromDay)
    local counted = today - from + 1
    if counted >= Activity.MIN_COUNTED then presence = Activity.SeenCount(seen or {}, from, today) / counted * 7 end
  end
  if ownDays then presence = math.max(presence or 0, math.min(7, ownDays)) end
  player.score, player.parts = Activity.Score(sum, presence)
end

-- The players of a roster: a main with its twinks is one (mains = Family.Mains: { [key] = mainKey }), a
-- member without family is one alone. recordOf(m) -> the saved member record ({ stats, seen }) or nil;
-- since = guild.seenSince. Returns players { {key, chars = { m, ... }, lead = m, score = n | nil,
-- parts = t | nil} } in roster order and byKey { [memberKey] = player }.
function Activity.Players(members, mains, recordOf, now, date, since)
  local players, byMain, byKey = {}, {}, {}
  for _, m in ipairs(members) do
    local main = mains and mains[m.key] or m.key
    local player = byMain[main]
    if not player then
      player = { key = main, chars = {} }
      byMain[main] = player
      players[#players + 1] = player
    end
    player.chars[#player.chars + 1] = m
    byKey[m.key] = player
  end
  for _, player in ipairs(players) do ScorePlayer(player, recordOf, now, date, since) end
  return players, byKey
end

-- Bar of a score: 1 very active (75+), 2 active (50+), 3 occasional (25+), 4 hardly, 5 no score
function Activity.Bucket(score)
  if not score then return 5 end
  if score >= 75 then return 1 end
  if score >= 50 then return 2 end
  if score >= 25 then return 3 end
  return 4
end

-- { buckets = { n1 .. n5 }, scored = n, pulse = mean of the scores (one decimal), median }; pulse and
-- median are nil when nobody has a score
function Activity.Summary(players)
  local summary = { buckets = { 0, 0, 0, 0, 0 }, scored = 0 }
  local scores, sum = {}, 0
  for _, player in ipairs(players) do
    local bucket = Activity.Bucket(player.score)
    summary.buckets[bucket] = summary.buckets[bucket] + 1
    if player.score then
      scores[#scores + 1] = player.score
      sum = sum + player.score
    end
  end
  summary.scored = #scores
  if #scores > 0 then
    summary.pulse = math.floor(sum / #scores * 10 + 0.5) / 10
    table.sort(scores)
    local mid = math.floor((#scores + 1) / 2)
    summary.median = #scores % 2 == 1 and scores[mid] or (scores[mid] + scores[mid + 1]) / 2
  end
  return summary
end

-- Remembers the pulse of a month (the last one computed in it); a nil pulse stores nothing
function Activity.StorePulse(guild, monthKey, pulse)
  if type(pulse) ~= "number" then return end
  if type(guild.pulse) ~= "table" then guild.pulse = {} end
  guild.pulse[monthKey] = pulse
  local keys = {}
  for key in pairs(guild.pulse) do keys[#keys + 1] = key end
  table.sort(keys)
  for i = 1, #keys - Activity.PULSES_KEPT do guild.pulse[keys[i]] = nil end
end

-- pulse minus the pulse stored for the previous month (one decimal), nil when either is unknown
function Activity.PulseChange(guild, pulse, previousKey)
  local before = type(guild.pulse) == "table" and guild.pulse[previousKey]
  if type(pulse) ~= "number" or type(before) ~= "number" then return nil end
  return math.floor((pulse - before) * 10 + 0.5) / 10
end

-- month ---------------------------------------------------------------------------------------------------

Activity.MONTH_ROWS = { "raidBosses", "dungeonBosses", 932, 98, 588, "days" }

-- First and last day (Activity.Day) of the month ts lies in
local function MonthDays(ts, date)
  local key = ns.Stats.MonthKey(ts, date)
  local first, last = Activity.Day(ts), Activity.Day(ts)
  while ns.Stats.MonthKey((first - 1) * DAY + DAY / 2, date) == key do first = first - 1 end
  while ns.Stats.MonthKey((last + 1) * DAY + DAY / 2, date) == key do last = last + 1 end
  return first, last
end

local function Round1(value)
  return math.floor(value * 10 + 0.5) / 10
end

-- The rows of "This month": { {id, value, last, compare} } in the order of MONTH_ROWS. value = what the
-- guild did this month so far, last = in the whole month before, compare = last scaled to the share of
-- this month that has passed (a month ten days old is compared with a third of the last one); last and
-- compare are nil when nothing is known of last month. entries = { {rec} } (GameStats.Entries); a record
-- without a start value for a month is left out of that month. The "days" row is the mean number of
-- days online per player (players = Activity.Players, recordOf as there), over the players seen at all;
-- its last is nil while this client has not counted (since) the whole of last month.
function Activity.Month(entries, players, recordOf, now, date, since)
  local first, last = MonthDays(now, date)
  local today = Activity.Day(now)
  local share = (today - first + 1) / (last - first + 1)
  local rows = {}
  for i, id in ipairs(Activity.MONTH_ROWS) do
    local row = { id = id, value = 0 }
    if id == "days" then
      local beforeFirst, beforeLast = MonthDays((first - 1) * DAY + DAY / 2, date)
      local known = since and since <= beforeFirst
      local count, sum, sumBefore = 0, 0, 0
      for _, player in ipairs(players) do
        local seen = {}
        for _, m in ipairs(player.chars) do
          local record = recordOf(m)
          if record and type(record.seen) == "table" and next(record.seen) then seen[#seen + 1] = record.seen end
        end
        if #seen > 0 then
          count = count + 1
          sum = sum + Activity.SeenCount(seen, first, today)
          sumBefore = sumBefore + Activity.SeenCount(seen, beforeFirst, beforeLast)
        end
      end
      if count > 0 then
        row.value = Round1(sum / count)
        if known then row.last = Round1(sumBefore / count) end
      end
    else
      for _, entry in ipairs(entries) do
        local value = ns.Stats.Value(entry.rec, id, "month", now, date)
        if value then row.value = row.value + value end
        local before = ns.Stats.Value(entry.rec, id, "last", now, date)
        if before then row.last = (row.last or 0) + before end
      end
    end
    if row.last then row.compare = Round1(row.last * share) end
    rows[i] = row
  end
  return rows
end
